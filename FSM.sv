//==============================================================================
// usb2_cdr_lock_fsm  (diagram block: "Lock FSM")
//   Edge counter   : edges since packet start (ted_valid), saturates at 7
//   Lock detector  : consecutive edges with |ted| <= TED_THR (2-bit, 0..3)
//   SE0 qualifier  : line "not J/K" (SE0 or SE1) for >= SE0_QUAL clk_sys -> EOP.
//                    Also counts J (idle) for >= IDLE_QUAL clk_sys.
//   Timeout cnt    : ce ticks (clk_sys cycles in FS) spent in ACQUIRE without lock
//   State reg      : IDLE / ACQUIRE / TRACK / LOSS
//
//   IDLE   : loop_reset = 1, acc_reset = 1, locked = 0, gain high
//   ACQUIRE: gain high, locked = 0
//   TRACK  : gain low,  locked = 1
//   LOSS   : locked = 0; integrator held (loop_reset = 0), accumulator parked
//            (acc_reset = 1, so no further strobes); both cleared in IDLE
//
//   IDLE    -> ACQUIRE : first edge (ted_valid)
//   ACQUIRE -> TRACK   : >= EDGE_MIN edges and M_GOOD consecutive small errors
//   ACQUIRE -> IDLE    : timeout
//   ACQUIRE -> LOSS    : qualified SE0 (abort; waits for J before re-arming)
//   TRACK   -> LOSS    : qualified SE0 / invalid line state
//   TRACK   -> IDLE    : BAD_MAX consecutive large timing errors
//   LOSS    -> IDLE    : line idle (J) for IDLE_QUAL clk_sys
//==============================================================================
/*module usb2_cdr_lock_fsm #(
    parameter OS        = 8,
    parameter TED_W     = 6,
    parameter EDGE_MIN  = 4,        // edges (incl. the first) before lock is allowed
    parameter M_GOOD    = 3,        // consecutive small-error edges, max 3 (2-bit counter)
    parameter TED_THR   = 8,        // |ted| <= THR is "err_small"  (8 = 1/8 bit)
    parameter TED_BAD   = 24,       // |ted| >  BAD is "err_large"  (24 = 3/8 bit)
    parameter BAD_MAX   = 3,        // consecutive err_large errors that drop TRACK
    parameter SE0_QUAL  = OS,       // ce ticks of SE0 that qualifies as EOP
    parameter IDLE_QUAL = 4,        // ce ticks of J that qualifies "line idle"
    parameter TIMEOUT   = 8*OS      // ce ticks in ACQUIRE without lock
)(
    input  wire                    clk_sys,
    input  wire                    rstn,
    input  wire                    ce,          // all counters / state advance on ce
    input  wire                    enable,
    input  wire                    se0,
    input  wire                    se1,
    input  wire                    idle,
    input  wire signed [TED_W-1:0] ted_value,
    input  wire                    ted_valid,

    output wire                    acc_reset,
    output wire                    loop_reset,
    output wire                    gain_sel,
    output wire                    locked,
    output wire [1:0]              state_o
);
    localparam [1:0] S_IDLE = 2'd0, S_ACQ = 2'd1, S_TRK = 2'd2, S_LOSS = 2'd3;
    localparam TO_W = $clog2(TIMEOUT) + 1;          // 7 bits for 64 @ OS = 8
    localparam QW   = 8;

    reg [1:0]       state;
    reg [2:0]       edge_cnt;
    reg [1:0]       good_cnt;
    reg [1:0]       bad_cnt;
    reg [TO_W-1:0]  to_cnt;
    reg [QW-1:0]    se0_cnt, idle_cnt;

    // ---------------- magnitude check --------------------------------------
    wire [TED_W:0] ted_abs = ted_value[TED_W-1] ? (-{ted_value[TED_W-1], ted_value})
                                                :  ({ted_value[TED_W-1], ted_value});
    wire err_small = (ted_abs <= TED_THR);
    wire err_large = (ted_abs >  TED_BAD);

    // ---------------- SE0 qualifier ----------------------------------------
    wire line_bad = se0 | se1;
    always @(posedge clk_sys) begin
        if (!rstn) begin
            se0_cnt  <= {QW{1'b0}};
            idle_cnt <= {QW{1'b0}};
        end else if (ce) begin
            if (!line_bad)                se0_cnt  <= {QW{1'b0}};
            else if (se0_cnt < SE0_QUAL)  se0_cnt  <= se0_cnt + 1'b1;
            if (!idle)                    idle_cnt <= {QW{1'b0}};
            else if (idle_cnt < IDLE_QUAL) idle_cnt <= idle_cnt + 1'b1;
        end
    end
    wire se0_ok  = (se0_cnt  >= SE0_QUAL);
    wire idle_ok = (idle_cnt >= IDLE_QUAL);

    // ---------------- timeout ----------------------------------------------
    wire timeout_ev = (state == S_ACQ) && (to_cnt == TIMEOUT-1);

    // ---------------- lock-detector next values ----------------------------
    wire lock_ev = ted_valid && err_small &&
                   (edge_cnt >= EDGE_MIN-1) && (good_cnt >= M_GOOD-1);
    wire drop_ev = ted_valid && err_large && (bad_cnt >= BAD_MAX-1);

    // ---------------- state register ---------------------------------------
    always @(posedge clk_sys) begin
        if (!rstn || !enable) begin
            state    <= S_IDLE;
            edge_cnt <= 3'd0;
            good_cnt <= 2'd0;
            bad_cnt  <= 2'd0;
            to_cnt   <= {TO_W{1'b0}};
        end else if (ce) begin
            case (state)
            S_IDLE: begin
                edge_cnt <= 3'd0; good_cnt <= 2'd0; bad_cnt <= 2'd0; to_cnt <= {TO_W{1'b0}};
                if (ted_valid) begin
                    edge_cnt <= 3'd1;
                    state    <= S_ACQ;
                end
            end
            S_ACQ: begin
                to_cnt <= to_cnt + 1'b1;
                if (ted_valid) begin
                    if (edge_cnt != 3'd7) edge_cnt <= edge_cnt + 1'b1;
                    if (err_small) begin
                        if (good_cnt != 2'd3) good_cnt <= good_cnt + 1'b1;
                    end else
                        good_cnt <= 2'd0;
                end
                if (se0_ok)           state <= S_LOSS;
                else if (lock_ev)   begin state <= S_TRK; bad_cnt <= 2'd0; end
                else if (timeout_ev)  state <= S_IDLE;
            end
            S_TRK: begin
                if (ted_valid) begin
                    if (err_large) bad_cnt <= bad_cnt + 1'b1;
                    else       bad_cnt <= 2'd0;
                end
                if (se0_ok)         state <= S_LOSS;
                else if (drop_ev)   state <= S_IDLE;
            end
            S_LOSS: begin
                if (idle_ok) state <= S_IDLE;
            end
            endcase
        end
    end

    // ---------------- Moore outputs ----------------------------------------
    assign state_o    = state;
    assign locked     = (state == S_TRK);
    assign loop_reset = (state == S_IDLE);
    assign acc_reset  = (state == S_IDLE);// || (state == S_LOSS);
    assign gain_sel   = (state == S_IDLE) || (state == S_ACQ);   // 1 = high gain
endmodule*/

/*module usb2_cdr_lock_fsm #(
    parameter OS        = 8,
    parameter TED_W     = 6,
    parameter EDGE_MIN  = 4,        // edges (incl. the first) before lock is allowed
    parameter M_GOOD    = 3,        // consecutive small-error edges, max 3 (2-bit counter)
    parameter TED_THR   = 8,        // |ted| <= THR is "err_small"
    parameter TED_BAD   = 24,       // |ted| >  BAD is "err_large"
    parameter BAD_MAX   = 20,        // consecutive err_large edges that drop TRACK
    parameter SE0_QUAL  = OS,       // ce ticks of SE0/SE1 that qualify as EOP
    parameter IDLE_QUAL = 4,        // ce ticks of J that qualify "line idle"
    parameter TIMEOUT   = 8*OS      // ce ticks in ACQUIRE without lock
)(
    input  wire                    clk_sys,
    input  wire                    rstn,
    input  wire                    ce,          // all counters / state advance on ce
    input  wire                    enable,
    input  wire                    se0,
    input  wire                    se1,
    input  wire                    idle,
    input  wire signed [TED_W-1:0] ted_value,
    input  wire                    ted_valid,

    output wire                    acc_reset,
    output wire                    loop_reset,
    output wire                    gain_sel,
    output wire                    locked,
    output wire [1:0]              state_o
);
    localparam [1:0] S_IDLE = 2'd0, S_ACQ = 2'd1, S_TRK = 2'd2, S_LOSS = 2'd3;
    localparam TO_W = $clog2(TIMEOUT) + 1;
    localparam QW   = 8;

    reg [1:0]       state;
    reg [2:0]       edge_cnt;
    reg [1:0]       good_cnt;
    reg [13:0]       bad_cnt;
    reg [TO_W-1:0]  to_cnt;
    reg [QW-1:0]    se0_cnt, idle_cnt;

    // ---------------- magnitude check --------------------------------------
    wire [TED_W:0] ted_abs = ted_value[TED_W-1] ? (-{ted_value[TED_W-1], ted_value})
                                                :  ({ted_value[TED_W-1], ted_value});
    wire err_small = (ted_abs <= TED_THR);
    wire err_large = (ted_abs >  TED_BAD);

    // ---------------- SE0 / idle qualifiers --------------------------------
    wire line_bad = se0 | se1;
    always @(posedge clk_sys) begin
        if (!rstn) begin
            se0_cnt  <= {QW{1'b0}};
            idle_cnt <= {QW{1'b0}};
        end else if (ce) begin
            if (!line_bad)                 se0_cnt  <= {QW{1'b0}};
            else if (se0_cnt < SE0_QUAL)   se0_cnt  <= se0_cnt + 1'b1;
            if (!idle)                     idle_cnt <= {QW{1'b0}};
            else if (idle_cnt < IDLE_QUAL) idle_cnt <= idle_cnt + 1'b1;
        end
    end
    wire se0_ok  = (se0_cnt  >= SE0_QUAL);
    wire idle_ok = (idle_cnt >= IDLE_QUAL);

    // ---------------- timeout ----------------------------------------------
    wire timeout_ev = (state == S_ACQ) && (to_cnt == TIMEOUT-1);

    // ---------------- lock / drop events -----------------------------------
    wire lock_ev = ted_valid && err_small &&
                   (edge_cnt >= EDGE_MIN-1) && (good_cnt >= M_GOOD-1);
    wire drop_ev = ted_valid && err_large && (bad_cnt >= BAD_MAX-1);

    // ---------------- state register ---------------------------------------
    always @(posedge clk_sys) begin
        if (!rstn || !enable) begin
            state    <= S_IDLE;
            edge_cnt <= 3'd0;
            good_cnt <= 2'd0;
            bad_cnt  <= 2'd0;
            to_cnt   <= {TO_W{1'b0}};
        end else if (ce) begin
            case (state)
            S_IDLE: begin
                edge_cnt <= 3'd0; good_cnt <= 2'd0; bad_cnt <= 2'd0; to_cnt <= {TO_W{1'b0}};
                if (ted_valid) begin
                    edge_cnt <= 3'd1;
                    state    <= S_ACQ;
                end
            end
            S_ACQ: begin
                to_cnt <= to_cnt + 1'b1;
                if (ted_valid) begin
                    if (edge_cnt != 3'd7) edge_cnt <= edge_cnt + 1'b1;
                    if (err_small) begin
                        if (good_cnt != 2'd3) good_cnt <= good_cnt + 1'b1;
                    end else
                        good_cnt <= 2'd0;
                end
                if (se0_ok)            state <= S_LOSS;
                else if (lock_ev)    begin state <= S_TRK; bad_cnt <= 2'd0; end
                else if (timeout_ev)   state <= S_IDLE;
            end
            S_TRK: begin
                if (ted_valid) begin
                    if (err_large) bad_cnt <= bad_cnt + 1'b1;
                    else           bad_cnt <= 2'd0;
                end
                if (se0_ok)          state <= S_LOSS;
                else if (drop_ev)    state <= S_IDLE;
            end
            S_LOSS: begin
                if (idle_ok) state <= S_IDLE;
            end
            endcase
        end
    end

    // ---------------- Moore outputs ----------------------------------------
    assign state_o    = state;
    assign locked     = (state == S_TRK);
    assign loop_reset = (state == S_IDLE);
    assign acc_reset  = (state == S_IDLE) || (state == S_LOSS);
    assign gain_sel   = (state == S_IDLE) || (state == S_ACQ);   // 1 = high gain
endmodule*/


//==============================================================================
// usb2_cdr_lock_fsm  (diagram block: "Lock FSM")
//   Edge counter   : edges since packet start (ted_valid), saturates at 7
//   Lock detector  : consecutive edges with |ted| <= TED_THR (2-bit, 0..3)
//   SE0 qualifier  : line "not J/K" (SE0 or SE1) for >= SE0_QUAL clk_sys -> EOP.
//                    Also counts J (idle) for >= IDLE_QUAL clk_sys.
//   Timeout cnt    : ce ticks (clk_sys cycles in FS) spent in ACQUIRE without lock
//   State reg      : IDLE / ACQUIRE / TRACK / LOSS
//
//   IDLE   : loop_reset = 1, acc_reset = 1, locked = 0, gain high
//   ACQUIRE: gain high, locked = 0
//   TRACK  : gain low,  locked = 1
//   LOSS   : locked = 0; integrator held (loop_reset = 0), accumulator parked
//            (acc_reset = 1, so no further strobes); both cleared in IDLE
//
//   IDLE    -> ACQUIRE : first edge (ted_valid)
//   ACQUIRE -> TRACK   : >= EDGE_MIN edges and M_GOOD consecutive small errors
//   ACQUIRE -> IDLE    : timeout, or line idle (J) for IDLE_ACQ_QUAL ce ticks (idle_acq_ok)
//   (ACQUIRE priority: se0_ok > idle_acq_ok > lock_ev > timeout_ev)
//   ACQUIRE -> LOSS    : qualified SE0 (abort; waits for J before re-arming)
//   TRACK   -> LOSS    : qualified SE0 / invalid line state
//   TRACK   -> IDLE    : BAD_MAX consecutive large timing errors
//   LOSS    -> IDLE    : line idle (J) for IDLE_QUAL clk_sys
//==============================================================================
/*module usb2_cdr_lock_fsm #(
    parameter OS        = 8,
    parameter TED_W     = 6,
    parameter EDGE_MIN  = 4,        // edges (incl. the first) before lock is allowed
    parameter M_GOOD    = 3,        // consecutive small-error edges, max 3 (2-bit counter)
    parameter TED_THR   = 8,        // |ted| <= THR is "err_small"
    parameter TED_BAD   = 24,       // |ted| >  BAD is "err_large"
    parameter BAD_MAX   = 20,        // consecutive err_large edges that drop TRACK
    parameter SE0_QUAL  = OS,       // ce ticks of SE0/SE1 that qualify as EOP
    parameter IDLE_QUAL = 4,        // ce ticks of J that qualify "line idle" (LOSS -> IDLE)
    parameter IDLE_ACQ_QUAL = 7*OS, // ce ticks of J that abort ACQUIRE. Must exceed the longest
                                    // legal J run in a stuffed packet (6 bits = 6*OS ticks),
                                    // otherwise ordinary J data bits would kick ACQUIRE to IDLE
    parameter TIMEOUT   = 8*OS      // ce ticks in ACQUIRE without lock
)(
    input  wire                    clk_sys,
    input  wire                    rstn,
    input  wire                    ce,          // all counters / state advance on ce
    input  wire                    enable,
    input  wire                    se0,
    input  wire                    se1,
    input  wire                    idle,
    input  wire signed [TED_W-1:0] ted_value,
    input  wire                    ted_valid,

    output wire                    acc_reset,
    output wire                    loop_reset,
    output wire                    gain_sel,
    output wire                    locked,
    output wire [1:0]              state_o
);
    localparam [1:0] S_IDLE = 2'd0, S_ACQ = 2'd1, S_TRK = 2'd2, S_LOSS = 2'd3;
    localparam TO_W = $clog2(TIMEOUT) + 1;
    localparam QW   = 8;
    localparam IDLE_MAX = (IDLE_ACQ_QUAL > IDLE_QUAL) ? IDLE_ACQ_QUAL : IDLE_QUAL;
    localparam IW   = $clog2(IDLE_MAX + 1);        // idle counter must hold IDLE_ACQ_QUAL

    reg [1:0]       state;
    reg [2:0]       edge_cnt;
    reg [1:0]       good_cnt;
    reg [13:0]       bad_cnt;
    reg [TO_W-1:0]  to_cnt;
    reg [QW-1:0]    se0_cnt;
    reg [IW-1:0]    idle_cnt;

    // ---------------- magnitude check --------------------------------------
    wire [TED_W:0] ted_abs = ted_value[TED_W-1] ? (-{ted_value[TED_W-1], ted_value})
                                                :  ({ted_value[TED_W-1], ted_value});
    wire err_small = (ted_abs <= TED_THR);
    wire err_large = (ted_abs >  TED_BAD);

    // ---------------- SE0 / idle qualifiers --------------------------------
    wire line_bad = se0 | se1;
    always @(posedge clk_sys) begin
        if (!rstn) begin
            se0_cnt  <= {QW{1'b0}};
            idle_cnt <= {IW{1'b0}};
        end else if (ce) begin
            if (!line_bad)                 se0_cnt  <= {QW{1'b0}};
            else if (se0_cnt < SE0_QUAL)   se0_cnt  <= se0_cnt + 1'b1;
            if (!idle)                     idle_cnt <= {IW{1'b0}};
            else if (idle_cnt < IDLE_MAX)  idle_cnt <= idle_cnt + 1'b1;
        end
    end
    wire se0_ok  = (se0_cnt  >= SE0_QUAL);
    wire idle_ok     = (idle_cnt >= IDLE_QUAL);       // LOSS -> IDLE
    wire idle_acq_ok = (idle_cnt >= IDLE_ACQ_QUAL);   // ACQUIRE -> IDLE

    // ---------------- timeout ----------------------------------------------
    wire timeout_ev = (state == S_ACQ) && (to_cnt == TIMEOUT-1);

    // ---------------- lock / drop events -----------------------------------
    wire lock_ev = ted_valid && err_small &&
                   (edge_cnt >= EDGE_MIN-1) && (good_cnt >= M_GOOD-1);
    wire drop_ev = ted_valid && err_large && (bad_cnt >= BAD_MAX-1);

    // ---------------- state register ---------------------------------------
    always @(posedge clk_sys) begin
        if (!rstn || !enable) begin
            state    <= S_IDLE;
            edge_cnt <= 3'd0;
            good_cnt <= 2'd0;
            bad_cnt  <= 2'd0;
            to_cnt   <= {TO_W{1'b0}};
        end else if (ce) begin
            case (state)
            S_IDLE: begin
                edge_cnt <= 3'd0; good_cnt <= 2'd0; bad_cnt <= 2'd0; to_cnt <= {TO_W{1'b0}};
                if (ted_valid) begin
                    edge_cnt <= 3'd1;
                    state    <= S_ACQ;
                end
            end
            S_ACQ: begin
                to_cnt <= to_cnt + 1'b1;
                if (ted_valid) begin
                    if (edge_cnt != 3'd7) edge_cnt <= edge_cnt + 1'b1;
                    if (err_small) begin
                        if (good_cnt != 2'd3) good_cnt <= good_cnt + 1'b1;
                    end else
                        good_cnt <= 2'd0;
                end
                // priority: se0_ok > idle_acq_ok > lock_ev > timeout_ev
                if (se0_ok)            state <= S_LOSS;
                else if (idle_acq_ok)  state <= S_IDLE;
                else if (lock_ev)    begin state <= S_TRK; bad_cnt <= 2'd0; end
                else if (timeout_ev)   state <= S_IDLE;
            end
            S_TRK: begin
                if (ted_valid) begin
                    if (err_large) bad_cnt <= bad_cnt + 1'b1;
                    else           bad_cnt <= 2'd0;
                end
                if (se0_ok)          state <= S_LOSS;
                else if (drop_ev)    state <= S_IDLE;
            end
            S_LOSS: begin
                if (idle_ok) state <= S_IDLE;
            end
            endcase
        end
    end

    // ---------------- Moore outputs ----------------------------------------
    assign state_o    = state;
    assign locked     = (state == S_TRK);
    assign loop_reset = (state == S_IDLE);
    assign acc_reset  = (state == S_IDLE) || (state == S_LOSS);
    assign gain_sel   = (state == S_IDLE) || (state == S_ACQ);   // 1 = high gain
endmodule*/



//==============================================================================
// usb2_cdr_lock_fsm  (diagram block: "Lock FSM")
//   Edge counter   : edges since packet start (ted_valid), saturates at 7
//   Lock detector  : consecutive edges with |ted| <= TED_THR (2-bit, 0..3)
//   SE0 qualifier  : line "not J/K" (SE0 or SE1) for >= SE0_QUAL clk_sys -> EOP.
//                    Also counts J (idle) for >= IDLE_QUAL clk_sys.
//   Timeout cnt    : ce ticks (clk_sys cycles in FS) spent in ACQUIRE without lock
//   State reg      : IDLE / ACQUIRE / TRACK / LOSS
//
//   IDLE   : loop_reset = 1, acc_reset = 1, locked = 0, gain high
//   ACQUIRE: gain high, locked = 0
//   TRACK  : gain low,  locked = 1
//   LOSS   : locked = 0; integrator held (loop_reset = 0), accumulator parked
//            (acc_reset = 1, so no further strobes); both cleared in IDLE
//
//   IDLE    -> ACQUIRE : first edge (ted_valid)
//   ACQUIRE -> TRACK   : >= EDGE_MIN edges and M_GOOD consecutive small errors
//   ACQUIRE -> IDLE    : timeout, or line idle (J) for IDLE_ACQ_QUAL ce ticks (idle_acq_ok)
//   (ACQUIRE priority: se0_ok > lock_ev > idle_acq_ok > timeout_ev)
//   ACQUIRE -> LOSS    : qualified SE0 (abort; waits for J before re-arming)
//   TRACK   -> LOSS    : qualified SE0 / invalid line state
//   TRACK   -> IDLE    : BAD_MAX consecutive large timing errors
//   LOSS    -> IDLE    : line idle (J) for IDLE_QUAL clk_sys
//==============================================================================
module usb2_cdr_lock_fsm #(
    parameter OS        = 8,
    parameter TED_W     = 6,
    parameter EDGE_MIN  = 4,        // edges (incl. the first) before lock is allowed
    parameter M_GOOD    = 3,        // consecutive small-error edges, max 3 (2-bit counter)
    parameter TED_THR   = 8,        // |ted| <= THR is "err_small"
    parameter TED_BAD   = 24,       // |ted| >  BAD is "err_large"
    parameter BAD_MAX   = 20,        // consecutive err_large edges that drop TRACK
    parameter SE0_QUAL  = OS,       // ce ticks of SE0/SE1 that qualify as EOP
    parameter IDLE_QUAL = 4,        // ce ticks of J that qualify "line idle" (LOSS -> IDLE)
    parameter IDLE_ACQ_QUAL = IDLE_QUAL, // ce ticks of J that abort ACQUIRE (LFSM_016). Default = IDLE_QUAL
                                    // as specified. A system with OS > IDLE_QUAL MUST override this above
                                    // the longest legal J run (6*OS): see usb2_cdr_top
    parameter TIMEOUT   = 8*OS      // ce ticks in ACQUIRE without lock
)(
    input  wire                    clk_sys,
    input  wire                    rstn,
    input  wire                    ce,          // all counters / state advance on ce
    input  wire                    enable,
    input  wire                    se0,
    input  wire                    se1,
    input  wire                    idle,
    input  wire signed [TED_W-1:0] ted_value,
    input  wire                    ted_valid,

    output wire                    acc_reset,
    output wire                    loop_reset,
    output wire                    gain_sel,
    output wire                    locked,
    output wire [1:0]              state_o
);
    localparam [1:0] S_IDLE = 2'd0, S_ACQ = 2'd1, S_TRK = 2'd2, S_LOSS = 2'd3;
    localparam TO_W = $clog2(TIMEOUT) + 1;
    localparam QW   = 8;
    localparam IDLE_MAX = (IDLE_ACQ_QUAL > IDLE_QUAL) ? IDLE_ACQ_QUAL : IDLE_QUAL;
    localparam IWC  = $clog2(IDLE_MAX + 1);
    localparam IW   = (IWC > QW) ? IWC : QW;       // >= 8 bits (matches assert port), wide enough for IDLE_ACQ_QUAL

    reg [1:0]       state;
    reg [2:0]       edge_cnt;
    reg [1:0]       good_cnt;
    reg [13:0]       bad_cnt;
    reg [TO_W-1:0]  to_cnt;
    reg [QW-1:0]    se0_cnt;
    reg [IW-1:0]    idle_cnt;

    // ---------------- magnitude check --------------------------------------
    wire [TED_W:0] ted_abs = ted_value[TED_W-1] ? (-{ted_value[TED_W-1], ted_value})
                                                :  ({ted_value[TED_W-1], ted_value});
    wire err_small = (ted_abs <= TED_THR);
    wire err_large = (ted_abs >  TED_BAD);

    // ---------------- SE0 / idle qualifiers --------------------------------
    wire line_bad = se0 | se1;
    always @(posedge clk_sys) begin
        if (!rstn) begin
            se0_cnt  <= {QW{1'b0}};
            idle_cnt <= {IW{1'b0}};
        end else if (ce) begin
            if (!line_bad)                 se0_cnt  <= {QW{1'b0}};
            else if (se0_cnt < SE0_QUAL)   se0_cnt  <= se0_cnt + 1'b1;
            if (!idle)                     idle_cnt <= {IW{1'b0}};
            else if (idle_cnt < IDLE_MAX)  idle_cnt <= idle_cnt + 1'b1;
        end
    end
    wire se0_ok  = (se0_cnt  >= SE0_QUAL);
    wire idle_ok     = (idle_cnt >= IDLE_QUAL);       // LOSS -> IDLE
    wire idle_acq_ok = (idle_cnt >= IDLE_ACQ_QUAL);   // ACQUIRE -> IDLE

    // ---------------- timeout ----------------------------------------------
    wire timeout_ev = (state == S_ACQ) && (to_cnt == TIMEOUT-1);

    // ---------------- lock / drop events -----------------------------------
    wire lock_ev = ted_valid && err_small &&
                   (edge_cnt >= EDGE_MIN-1) && (good_cnt >= M_GOOD-1);
    wire drop_ev = ted_valid && err_large && (bad_cnt >= BAD_MAX-1);

    // ---------------- state register ---------------------------------------
    always @(posedge clk_sys) begin
        if (!rstn || !enable) begin
            state    <= S_IDLE;
            edge_cnt <= 3'd0;
            good_cnt <= 2'd0;
            bad_cnt  <= 2'd0;
            to_cnt   <= {TO_W{1'b0}};
        end else if (ce) begin
            case (state)
            S_IDLE: begin
                edge_cnt <= 3'd0; good_cnt <= 2'd0; bad_cnt <= 2'd0; to_cnt <= {TO_W{1'b0}};
                if (ted_valid) begin
                    edge_cnt <= 3'd1;
                    state    <= S_ACQ;
                end
            end
            S_ACQ: begin
                to_cnt <= to_cnt + 1'b1;
                if (ted_valid) begin
                    if (edge_cnt != 3'd7) edge_cnt <= edge_cnt + 1'b1;
                    if (err_small) begin
                        if (good_cnt != 2'd3) good_cnt <= good_cnt + 1'b1;
                    end else
                        good_cnt <= 2'd0;
                end
                // priority: se0_ok > lock_ev > idle_acq_ok > timeout_ev
                // (idle_acq_ok and timeout_ev both go to IDLE, so their order is immaterial)
                if (se0_ok)            state <= S_LOSS;
                else if (lock_ev)    begin state <= S_TRK; bad_cnt <= 2'd0; end
                else if (idle_acq_ok)  state <= S_IDLE;
                else if (timeout_ev)   state <= S_IDLE;
            end
            S_TRK: begin
                if (ted_valid) begin
                    if (err_large) bad_cnt <= bad_cnt + 1'b1;
                    else           bad_cnt <= 2'd0;
                end
                if (se0_ok)          state <= S_LOSS;
                else if (drop_ev)    state <= S_IDLE;
            end
            S_LOSS: begin
                if (idle_ok) state <= S_IDLE;
            end
            endcase
        end
    end

    // ---------------- Moore outputs ----------------------------------------
    assign state_o    = state;
    assign locked     = (state == S_TRK);
    assign loop_reset = (state == S_IDLE);
    assign acc_reset  = (state == S_IDLE) || (state == S_LOSS);
    assign gain_sel   = (state == S_IDLE) || (state == S_ACQ);   // 1 = high gain
endmodule
