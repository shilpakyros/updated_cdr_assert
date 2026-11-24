//==============================================================================
// usb2_cdr_sampler  (diagram block: "Sampler")
//   Tap_pick    : sample_tap = sample_window[ phase_idx + phase_frac ]
//                 At a strobe phase_idx is normally 0, so this is tap0 when the
//                 residual after the wrap is < half a step and tap1 otherwise:
//                 the latched sample is always within half a clk_sys of the
//                 bit centre.
//   Out_register: loads sample_tap on bit_strobe.
// recovered_bit_clk = bit_strobe (one clk_sys wide clock ENABLE, not a clock).
// recovered_data changes one clk_sys after the strobe and holds for the bit.
// Optional 3-sample majority (MAJORITY=1) is folded into the tap picker.
//==============================================================================
module usb2_cdr_sampler #(
    parameter OS       = 8,
    parameter LOG2_OS  = 3,
    parameter MAJORITY = 0
)(
    input  wire                clk_sys,
    input  wire                rstn,
    input  wire                ce,
    input  wire                d_p_sync,
    input  wire                d_n_sync,

    input  wire [OS-1:0]       sample_window,
    input  wire [LOG2_OS-1:0]  phase_idx,
    input  wire                phase_frac,
    input  wire                bit_strobe,
    input  wire                acc_reset,
    output wire                sample_tap,
    output logic                recovered_bit_clk,
    output logic               dp_out,
    output logic                dm_out,
    
    output reg                 recovered_data,
    output reg                 rx_bit_valid
);
    wire [LOG2_OS:0] sel_raw = {1'b0, phase_idx} + {{LOG2_OS{1'b0}}, phase_frac};
    wire [LOG2_OS:0] sel     = (sel_raw > OS-1) ? (OS-1) : sel_raw;     // clamp to window
    wire             tap_c   = sample_window[sel];

    // majority of {tap-1, tap, tap+1}, edges of the window fall back to the single tap
    wire             tap_lo  = (sel == 0)      ? tap_c : sample_window[sel-1];
    wire             tap_hi  = (sel == OS-1)   ? tap_c : sample_window[sel+1];
    wire             tap_maj = (tap_lo & tap_c) | (tap_c & tap_hi) | (tap_lo & tap_hi);

    assign sample_tap = (MAJORITY != 0) ? tap_maj : tap_c;

   /* always @(posedge clk_sys) begin
        if (!rstn)     begin
	        recovered_data <= 1'b1;
		rx_bit_valid <=1'b0;
	  end
        else if (bit_strobe && ce) begin 
		recovered_data <= sample_tap;
		rx_bit_valid <=1'b1;
		end
	 
    end*/

always @(posedge clk_sys) begin
    if (!rstn) begin
        recovered_data <= 1'b1;
	dp_out<= 1'b1;
	dm_out<= 1'b0;
        rx_bit_valid   <= 1'b0;
    end
  /*  else if (acc_reset) begin
	dp_out<= 1'b1;
	dm_out<= 1'b0;

        recovered_data <= 1'b1;
        rx_bit_valid   <= 1'b0;
    end*/
    else begin
      //  rx_bit_valid <= bit_strobe & ce;

        if (bit_strobe && ce)begin
	dp_out<= d_p_sync;
	dm_out<= d_n_sync;

            recovered_data <= sample_tap;
        rx_bit_valid <= 1'b1;
	end
	else 
        rx_bit_valid <= 1'b0;
	
    end
end
    // bit_strobe is held for a whole ce period; ce picks the single clk_sys in which
    // the data register loads, so the output strobe is 1 clk_sys wide at both speeds.
    assign recovered_bit_clk = bit_strobe & ce;
endmodule
