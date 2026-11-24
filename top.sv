//==============================================================================
// usb2_cdr_top : USB 2.0 LS/FS digital clock-and-data recovery
//   rx_serial -> Sync+Deglitch -> Oversampler -> Edge detect/TED -> Loop filter
//             -> Phase accumulator (NCO) -> Sampler -> recovered_bit_clk / data
//   Lock FSM watches TED + line state and drives gain_sel, loop_reset,
//   acc_reset and locked.
//
// Clock plan : clk_sys = 480 MHz for every speed.  The CDR datapath runs on a clock
//              enable ce:  FS  ce = 1        -> 12 Mbps x OS 40 = 480 MHz
//                          LS  ce = 1 of 8   ->  1.5 Mbps x OS 40 =  60 MHz
//              so OS = 40 samples per bit at both speeds.  Sync/deglitch and the
//              line-state decode stay on the full clk_sys.
// speed      : 2'b00 LS, 2'b01 FS, 2'b10 HS.  HS is handled by the external PHY:
//              this block is held idle (locked = 0, no strobes) when speed = HS.
// HS PHY interface (phy_rx_*) is out of scope: wrapper-defined.
//==============================================================================
module usb2_cdr_top #(
    parameter OS         = 40,        // samples per bit (ce ticks): FS 480/12, LS 60/1.5
    parameter ACC_WIDTH  = 24,        // 20..30 (gains scale automatically)
    parameter TED_W      = 6,
    parameter LOOP_W     = ACC_WIDTH - 6,   // holds +/-2 % of step_nominal pre-clamp
    parameter DEGLITCH_W = 2,   // pulses shorter than W clk_sys are removed (0/1 = bypass)
    parameter KP_HI      = 10,
    parameter KP_LO      = 9,
    parameter KI_HI      = 9,
    parameter KI_LO      = 8,
    parameter P_HOLD     = 1,
    parameter MAJORITY   = 0,
    parameter EDGE_MIN   = 4,
    parameter M_GOOD     = 3,
    parameter TED_THR    = 8,
    parameter TED_BAD    = 24,
    parameter BAD_MAX    = 3,
    parameter SE0_QUAL   = OS,
    parameter IDLE_QUAL  = 4 + DEGLITCH_W,   // must outlast the deglitch delay of the data path
    parameter TIMEOUT    = 8*OS,      // ce ticks
    parameter LS_DIV     = 8          // clk_sys / ce rate in LS (480 MHz / 60 MHz)
)(
    input  wire       clk_sys,
    input  wire       rstn,
    input  wire       enable,
    input  wire [1:0] speed,
    input  wire       rx_serial,
    input  wire       dp,
    input  wire       dm,
    output  logic      dp_out,
    output  logic       dm_out,

    output logic       recovered_bit_clk,   // 1-cycle bit-centre strobe
    output logic       rx_bit_valid

    );
    //----------------------------------------------------------------------
    // Derived constants (64-bit so ACC_WIDTH up to 30 is safe)
    //----------------------------------------------------------------------
    localparam integer LOG2_OS   = $clog2(OS);
    localparam integer PIPE_LAT  = 2;          // sample_window latency (shift_reg + window reg)
    localparam integer EDGE_LAT  = 2;          // edge -> edge_q -> FSM state
    localparam [63:0]  TWO_W     = 64'd1 << ACC_WIDTH;
    localparam [63:0]  STEP64    = TWO_W / OS;
    // NCO phase at which an on-time edge must be captured so that the strobe
    // falls on the centre of the bit as seen in sample_window:
    //   D = OS/2 + PIPE_LAT - 1/2 clocks between edge and strobe.
    localparam [63:0]  D2        = OS + 2*PIPE_LAT - 1;           // 2*D
    localparam [63:0]  REF64     = TWO_W - ((D2 * STEP64) >> 1);
    localparam [ACC_WIDTH-1:0] STEP_NOM    = STEP64[ACC_WIDTH-1:0];
    localparam [ACC_WIDTH-1:0] EDGE_REF    = REF64[ACC_WIDTH-1:0];
    // phase_acc is parked here while acc_reset = 1, so that it is exactly in
    // step with a first edge that was detected EDGE_LAT clocks earlier.
    localparam [63:0]  RST64     = REF64 + EDGE_LAT * STEP64;
    localparam [ACC_WIDTH-1:0] RESET_PHASE = RST64[ACC_WIDTH-1:0];
 //wire       rx_bit_valid;
 wire       recovered_data;      // NRZI line level, changes 1 clk after the strobe
    
   // output wire       rx_bit_valid,
 wire       locked;
 wire [TED_W-1:0] quality;        // last timing error (signed), diagnostic

    wire en_eff = enable & (speed != 2'b10);
//	assign dp_out=dp;
//	assign dm_out=dm;
    //----------------------------------------------------------------------
    // Clock enable: always 1 in FS, one clk_sys pulse every LS_DIV clk in LS
    //----------------------------------------------------------------------
    localparam integer CE_W = $clog2(LS_DIV);
    wire is_ls = (speed == 2'b00);
    reg [CE_W-1:0] ce_cnt;
    always @(posedge clk_sys) begin
        if (!rstn || !is_ls || (ce_cnt == LS_DIV-1)) ce_cnt <= {CE_W{1'b0}};
        else                                         ce_cnt <= ce_cnt + 1'b1;
    end
    wire ce = is_ls ? (ce_cnt == LS_DIV-1) : 1'b1;

    //----------------------------------------------------------------------
    wire rx_sync, rx_s, d_p_sync, d_n_sync, se0, se1, idle;
    wire [OS-1:0] sample_shift, sample_window;
    wire rx_s_d;
    wire [ACC_WIDTH-1:0] phase, phase_value, step_eff;
    wire signed [ACC_WIDTH-1:0] error;
    wire edge_w;
    wire signed [TED_W-1:0] ted_value;
    wire ted_valid;
    wire signed [LOOP_W-1:0] loop_delta, p_term, i_delta, i_state;
    wire [LOG2_OS-1:0] phase_idx;
    wire phase_frac, bit_strobe, sample_tap;
    wire acc_reset, loop_reset, gain_sel;
    wire [1:0] fsm_state;

    usb2_cdr_sync_deglitch #(.DEGLITCH_W(DEGLITCH_W)) u_sync (
        .clk_sys(clk_sys), .rstn(rstn),
        .rx_serial(rx_serial), .d_p(dp), .d_n(dm), .speed(speed),
        .rx_sync(rx_sync), .rx_s(rx_s),
        .d_p_sync(d_p_sync), .d_n_sync(d_n_sync),
        .se0(se0), .se1(se1), .idle(idle));

    usb2_cdr_oversampler #(.OS(OS)) u_os (
        .clk_sys(clk_sys), .rstn(rstn), .ce(ce), .rx_s(rx_s),
        .sample_shift(sample_shift), .sample_window(sample_window), .rx_s_d(rx_s_d));

    usb2_cdr_error_detection #(.W(ACC_WIDTH), .TED_W(TED_W), .EDGE_REF(EDGE_REF)) u_ted (
        .clk_sys(clk_sys), .rstn(rstn), .ce(ce), .rx_s(rx_s), .rx_s_d(rx_s_d), .phase(phase),
        .edge_o(edge_w), .phase_value(phase_value), .error(error),
        .ted_value(ted_value), .ted_valid(ted_valid));

    // Loop is frozen while the accumulator is parked (IDLE / LOSS): an edge seen
    // there (e.g. SE0 -> J after an EOP) must not disturb the held loop state.
    wire lf_valid = ted_valid & ~acc_reset;

    usb2_cdr_loop_filter #(.TED_W(TED_W), .LOOP_W(LOOP_W), .STEP_NOM(STEP_NOM),
                           .KP_HI(KP_HI), .KP_LO(KP_LO), .KI_HI(KI_HI), .KI_LO(KI_LO),
                           .P_HOLD(P_HOLD), .ACC_W(ACC_WIDTH)) u_lf (
        .clk_sys(clk_sys), .rstn(rstn), .ce(ce), .ted_value(ted_value), .ted_valid(lf_valid),
        .gain_sel(gain_sel), .loop_reset(loop_reset), .speed(speed),
        .loop_delta(loop_delta), .p_term(p_term), .i_delta(i_delta), .i_state(i_state));

    usb2_cdr_phase_acc #(.W(ACC_WIDTH), .OS(OS), .LOG2_OS(LOG2_OS), .LOOP_W(LOOP_W),
                         .STEP_NOM(STEP_NOM), .RESET_PHASE(RESET_PHASE)) u_nco (
        .clk_sys(clk_sys), .rstn(rstn), .ce(ce), .acc_reset(acc_reset | ~en_eff),
        .loop_delta(loop_delta), .speed(speed),
        .phase(phase), .phase_idx(phase_idx), .phase_frac(phase_frac),
        .bit_strobe(bit_strobe), .step_eff(step_eff));

    usb2_cdr_sampler #(.OS(OS), .LOG2_OS(LOG2_OS), .MAJORITY(MAJORITY)) u_smp (
        .clk_sys(clk_sys), .rstn(rstn), .ce(ce), .sample_window(sample_window),
        .phase_idx(phase_idx), .phase_frac(phase_frac), .bit_strobe(bit_strobe),.d_n_sync(d_n_sync),.d_p_sync(d_p_sync),.dp_out(dp_out),.dm_out(dm_out),
        .sample_tap(sample_tap), .recovered_bit_clk(recovered_bit_clk),.acc_reset(acc_reset),
        .recovered_data(recovered_data),.rx_bit_valid(rx_bit_valid));

    usb2_cdr_lock_fsm #(.OS(OS), .TED_W(TED_W), .EDGE_MIN(EDGE_MIN), .M_GOOD(M_GOOD),
                        .TED_THR(TED_THR), .TED_BAD(TED_BAD), .BAD_MAX(BAD_MAX),
                        .SE0_QUAL(SE0_QUAL), .IDLE_QUAL(IDLE_QUAL), .TIMEOUT(TIMEOUT)) u_fsm (
        .clk_sys(clk_sys), .rstn(rstn), .ce(ce), .enable(en_eff),
        .se0(se0), .se1(se1), .idle(idle),
        .ted_value(ted_value), .ted_valid(ted_valid),
        .acc_reset(acc_reset), .loop_reset(loop_reset), .gain_sel(gain_sel),
        .locked(locked), .state_o(fsm_state));

    assign quality = ted_value;
endmodule
