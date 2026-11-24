//==============================================================================
// usb2_cdr_phase_acc  (diagram block: "Phase_accumulator")
//   Step Sum  : sum      = step_nominal + loop_delta
//   Step Clamp: step_eff = clamp(sum, nominal -/+ limit)     (limit: LS 2 %, FS 0.5 %)
//   Phase acc : W-bit register, phase <= phase + step_eff every clk_sys
//   bit_strobe: registered carry-out; high in the cycle where phase shows its
//               wrapped value (residual < step), one clk_sys wide.
//   ce        : the accumulator only advances when ce = 1 (LS runs at clk_sys/8)
//   acc_reset : loads RESET_PHASE, clears the strobe (held in IDLE / LOSS)
//
//   phase_idx  = top log2(OS) bits of phase  (to the sampler tap picker)
//   phase_frac = next bit below phase_idx; at a strobe it is 1 when the
//                residual after the wrap is >= half a step (used by Tap_pick)
//==============================================================================
module usb2_cdr_phase_acc #(
    parameter W         = 24,
    parameter OS        = 8,
    parameter LOG2_OS   = 3,
    parameter LOOP_W    = 18,
    parameter [W-1:0] STEP_NOM    = 24'h200000,
    parameter [W-1:0] RESET_PHASE = 24'h900000
)(
    input  wire                     clk_sys,
    input  wire                     rstn,
    input  wire                     ce,          // clock enable (1 = FS, 1 of 8 clk = LS)
    input  wire                     acc_reset,
    input  wire signed [LOOP_W-1:0] loop_delta,
    input  wire [1:0]               speed,
    output reg  [W-1:0]             phase,
    output wire [LOG2_OS-1:0]       phase_idx,
    output wire                     phase_frac,
    output reg                      bit_strobe,
    output wire [W-1:0]             step_eff
);
    localparam integer LIM_FS = (STEP_NOM + 100) / 200;
    localparam integer LIM_LS = (STEP_NOM +  25) /  50;

    wire signed [W+1:0] lim  = (speed == 2'b00) ? LIM_LS : LIM_FS;
    wire signed [W+1:0] nom  = {2'b00, STEP_NOM};
    wire signed [W+1:0] sum  = nom + $signed({{(W+2-LOOP_W){loop_delta[LOOP_W-1]}}, loop_delta});
    wire signed [W+1:0] lo   = nom - lim;
    wire signed [W+1:0] hi   = nom + lim;
    wire signed [W+1:0] stc  = (sum < lo) ? lo : (sum > hi) ? hi : sum;
    assign step_eff = stc[W-1:0];

    wire [W:0] acc_next = {1'b0, phase} + {1'b0, step_eff};   // widened: carry kept

    always @(posedge clk_sys) begin
        if (!rstn || acc_reset) begin
            phase      <= RESET_PHASE;
            bit_strobe <= 1'b0;
        end else if (ce) begin
            phase      <= acc_next[W-1:0];
            bit_strobe <= acc_next[W];
        end
    end

    assign phase_idx  = phase[W-1 -: LOG2_OS];
    assign phase_frac = phase[W-LOG2_OS-1];
endmodule
