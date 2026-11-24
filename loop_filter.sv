//==============================================================================
// usb2_cdr_loop_filter  (diagram block: "Loop_filter")
//   Proportional : p_term  = -Kp * ted_value     (shift, Kp selected by gain_sel)
//   Integral     : i_delta = -Ki * ted_value     (shift, Ki selected by gain_sel)
//   Integrator   : i_state += i_delta on ted_valid, saturated (anti-windup)
//   Sum + clamp  : loop_delta = clamp(p_term + i_state)
// The minus sign: ted_value > 0 means the NCO is early, so the step is reduced.
//
// Limits (loop_delta and i_state): +/-0.5 % of step_nominal for FS,
//                                  +/-2.0 % for LS (1.5 % + margin).
// gain_sel = 1 : high gain (ACQUIRE),  0 : low gain (TRACK)
// loop_reset   : clears the integrator (and the P hold register)
//
// P_HOLD = 1 : p_term is held between edges (zero-order hold).  A pure one-clock
//              p_term pulse is far too small to matter once clamped to the
//              frequency limit, so the hold is what gives the P path authority.
//              The TED still outputs 0 without an edge (runs of equal bits do
//              not create new error), only the last proportional result is held.
// P_HOLD = 0 : literal one-cycle P path (kept for experiments)
//==============================================================================
module usb2_cdr_loop_filter #(
    parameter TED_W    = 6,
    parameter LOOP_W   = 18,
    parameter STEP_NOM = 2097152,
    parameter KP_HI    = 10,      // left shifts of ted_value
    parameter KP_LO    = 9,
    parameter KI_HI    = 9,
    parameter KI_LO    = 8,
    parameter P_HOLD   = 1,
    parameter ACC_W    = 24       // KP/KI shifts below are for ACC_W = 24 and are scaled
)(
    input  wire                     clk_sys,
    input  wire                     rstn,
    input  wire                     ce,
    input  wire signed [TED_W-1:0]  ted_value,
    input  wire                     ted_valid,
    input  wire                     gain_sel,
    input  wire                     loop_reset,
    input  wire [1:0]               speed,
    output wire signed [LOOP_W-1:0] loop_delta,
    output wire signed [LOOP_W-1:0] p_term,
    output wire signed [LOOP_W-1:0] i_delta,
    output reg  signed [LOOP_W-1:0] i_state
);
    localparam integer ADJ = ACC_W - 24;               // gain scaling with accumulator width
    localparam AW = LOOP_W + 6 + ((ADJ > 0) ? ADJ : 0);                       // arithmetic width, no overflow
    localparam integer LIM_FS = (STEP_NOM + 100) / 200;   // 0.5 %  (10486 @ 2^21)
    localparam integer LIM_LS = (STEP_NOM +  25) /  50;   // 2.0 %  (41943 @ 2^21)

    wire signed [AW-1:0] lim = (speed == 2'b00) ? LIM_LS : LIM_FS;
    wire signed [AW-1:0] nlim = -lim;

    function signed [AW-1:0] sat;
        input signed [AW-1:0] x;
        input signed [AW-1:0] l;
        begin
            if (x >  l) sat =  l;
            else if (x < -l) sat = -l;
            else sat = x;
        end
    endfunction

    wire signed [AW-1:0] ted_x = ted_value;

    // ---- proportional ------------------------------------------------
    wire signed [AW-1:0] p_raw  = -(gain_sel ? (ted_x <<< (KP_HI+ADJ)) : (ted_x <<< (KP_LO+ADJ)));
    wire signed [AW-1:0] p_sat  = sat(p_raw, lim);

    reg  signed [AW-1:0] p_hold;
    always @(posedge clk_sys) begin
        if (!rstn || loop_reset) p_hold <= {AW{1'b0}};
        else if (ce && ted_valid) p_hold <= p_sat;
    end
    wire signed [AW-1:0] p_use = (P_HOLD != 0) ? p_hold : p_sat;
    assign p_term = p_sat[LOOP_W-1:0];

    // ---- integral + integrator ----------------------------------------
    wire signed [AW-1:0] i_d = -(gain_sel ? (ted_x <<< (KI_HI+ADJ)) : (ted_x <<< (KI_LO+ADJ)));
    assign i_delta = i_d[LOOP_W-1:0];

    wire signed [AW-1:0] i_next = sat($signed({{(AW-LOOP_W){i_state[LOOP_W-1]}}, i_state}) + i_d, lim);
    always @(posedge clk_sys) begin
        if (!rstn || loop_reset) i_state <= {LOOP_W{1'b0}};
        else if (ce && ted_valid) i_state <= i_next[LOOP_W-1:0];
    end

    // ---- sum + clamp ---------------------------------------------------
    wire signed [AW-1:0] i_ext = $signed({{(AW-LOOP_W){i_state[LOOP_W-1]}}, i_state});
    wire signed [AW-1:0] sum   = p_use + i_ext;
    wire signed [AW-1:0] sumc  = sat(sum, lim);
    assign loop_delta = sumc[LOOP_W-1:0];
endmodule
