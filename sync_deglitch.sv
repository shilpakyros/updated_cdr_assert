//==============================================================================
// usb2_cdr_sync_deglitch  (diagram block: "Sync + Deglitch")
//   data path      : rx_serial -> 2FF Sync -> rx_sync -> Deglitch -> rx_s
//   line-state path: D_p/D_n   -> 2FF Sync -> d_p_sync/d_n_sync -> Line state
//                    (+ Speed from AFE)                          -> SE0, idle
//
// speed encoding : 2'b00 = LS, 2'b01 = FS, 2'b10 = HS (HS uses FS polarity;
//                  the HS path itself is not implemented here)
//
// Deglitch = stability (debounce) filter, DEGLITCH_W in clk_sys:
//   rx_s changes only after rx_sync has held the NEW level for DEGLITCH_W
//   consecutive samples.  Every pulse shorter than W is removed, however many
//   there are and however close together (bursts / chatter included).  Pulses
//   of W or more pass with their width unchanged, only delayed by W.
//     W = 0 or 1 : bypass (rx_s = rx_sync, nothing is filtered)
//     W = 2      : removes 1-clk glitches           (default)
//     W = 3      : removes glitches up to 2 clk  ... and so on, up to W = 31
//   Latency from rx_serial to rx_s = 2 + W clk_sys.
//   Trade-off: a glitch that lands within W clk_sys of a real edge can move
//   that edge, and W must stay well below OS (a real bit is OS clk wide).
//
// Reset : while rstn = 0 the data path loads the current input level, so the
//         idle level (either polarity) produces no false edge after reset.
//         Hold rstn low for >= 4 clk_sys.
//==============================================================================
module usb2_cdr_sync_deglitch #(
    parameter DEGLITCH_W = 2
)(
    input  wire       clk_sys,
    input  wire       rstn,
    input  wire       rx_serial,   // AFE differential receiver
    input  wire       d_p,         // AFE single-ended D+
    input  wire       d_n,         // AFE single-ended D-
    input  wire [1:0] speed,       // from AFE

    output wire       rx_sync,     // after 2-FF synchronizer
    output wire       rx_s,        // deglitched data
    output wire       d_p_sync,
    output wire       d_n_sync,
    output wire       se0,         // both lines low
    output wire       se1,         // both lines high (invalid state)
    output wire       idle         // line in J state
);
      
    // 2-FF synchronizers (no reset on purpose, see header)
      
    reg [1:0] rx_ff, dp_ff, dn_ff;
    always @(posedge clk_sys) begin
        rx_ff <= {rx_ff[0], rx_serial};
        dp_ff <= {dp_ff[0], d_p};
        dn_ff <= {dn_ff[0], d_n};
    end
    assign rx_sync  = rx_ff[1];
    assign d_p_sync = dp_ff[1];
    assign d_n_sync = dn_ff[1];

      
    // Deglitch: count consecutive samples that differ from the output.
    // Any sample equal to the output restarts the count, so a glitch (or a
    // whole burst of them) shorter than W never reaches the output.
      
    reg [4:0] dg_cnt;
    reg       rx_s_r;
    wire      dg_diff = rx_sync ^ rx_s_r;
    always @(posedge clk_sys) begin
        if (!rstn) begin
            rx_s_r <= rx_sync;
            dg_cnt <= 5'd0;
        end else if (!dg_diff) begin
            dg_cnt <= 5'd0;
        end else if (dg_cnt == DEGLITCH_W-1) begin
            rx_s_r <= rx_sync;
            dg_cnt <= 5'd0;
        end else begin
            dg_cnt <= dg_cnt + 5'd1;
        end
    end
    assign rx_s = (DEGLITCH_W <= 1) ? rx_sync : rx_s_r;

      
    // Line state decode.  FS: J = D+ high / D- low.  LS: J and K swapped.
      
    wire is_ls = (speed == 2'b00);
    wire j_fs  =  d_p_sync & ~d_n_sync;
    wire j_ls  = ~d_p_sync &  d_n_sync;
    assign idle = is_ls ? j_ls : j_fs;
    assign se0  = ~d_p_sync & ~d_n_sync;
    assign se1  =  d_p_sync &  d_n_sync;
endmodule
