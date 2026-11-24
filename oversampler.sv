//==============================================================================
// usb2_cdr_oversampler  (diagram block: "Over_sampling")
//   Shift_reg    : last OS samples of rx_s        -> sample_shift
//   Sample_window: registered copy of sample_shift -> sample_window
//   Delay / reg  : one-clock delay of rx_s         -> rx_s_d
// tap 0 (bit 0) = newest.  sample_window[0] at cycle t equals rx_s(t-2).
// No tap select here: that is done in the sampler.
//==============================================================================
/*module usb2_cdr_oversampler #(
    parameter OS = 8
)(
    input  wire          clk_sys,
    input  wire          rstn,
    input  wire          rx_s,
    output wire [OS-1:0] sample_shift,
    output reg  [OS-1:0] sample_window,
    output reg           rx_s_d
);
    reg [OS-1:0] shift_reg;
    assign sample_shift = shift_reg;

    always @(posedge clk_sys) begin
        if (!rstn) begin               // load current level: no false edge
            shift_reg     <= {OS{rx_s}};
            sample_window <= {OS{rx_s}};
            rx_s_d        <= rx_s;
        end else begin
            shift_reg     <= {shift_reg[OS-2:0], rx_s};
            sample_window <= shift_reg;
            rx_s_d        <= rx_s;
        end
    end
endmodule
*/



module usb2_cdr_oversampler #(
    parameter integer OS = 40
)(
    input  wire          clk_sys,
    input  wire          rstn,
    input  wire          ce,             // sample enable: 1 = FS (480 MHz), 1 of 8 clk = LS (60 MHz)
    input  wire          rx_s,

    output wire [OS-1:0] sample_shift,
    output reg  [OS-1:0] sample_window,
    output reg           rx_s_d
);
    // One shift register for both speeds.  The sampling rate is set by ce, so
    // OS taps always span exactly one bit:  FS 480/12 = 40,  LS 60/1.5 = 40.
    reg [OS-1:0] shift_reg;
    assign sample_shift = shift_reg;

    always @(posedge clk_sys) begin
        if (!rstn) begin
            shift_reg     <= {OS{rx_s}};
            sample_window <= {OS{rx_s}};
            rx_s_d        <= rx_s;
        end else if (ce) begin
            shift_reg     <= {shift_reg[OS-2:0], rx_s};
            sample_window <= shift_reg;
            rx_s_d        <= rx_s;
        end
    end
endmodule



//`timescale 1ns/1ps
// Unit test: usb2_cdr_oversampler.  Cycle-exact comparison against a history model.
//   after posedge n :  sample_shift[k]  = rx_s(n-k)
//                      rx_s_d           = rx_s(n)
//                      sample_window[k] = rx_s(n-1-k)       (tap0 = newest)
/*`define CHK(c,m) if (!(c)) begin errors = errors + 1; if (errors < 20) $display("ERROR t=%0t: %s", $time, m); end
module tb_oversampler;
    parameter OS = 8;
    reg clk = 0; always #5 clk = ~clk;
    reg rstn = 0, rx_s = 1;
    wire [OS-1:0] sample_shift, sample_window; wire rx_s_d;
    usb2_cdr_oversampler #(.OS(OS)) dut (.clk_sys(clk), .rstn(rstn), .rx_s(rx_s),
        .sample_shift(sample_shift), .sample_window(sample_window), .rx_s_d(rx_s_d));

    reg hist [0:4999];
    reg rst_lvl;
    integer errors = 0, n, k, rep;

    function h(input integer i);
        begin h = (i <= 0) ? rst_lvl : hist[i]; end
    endfunction

    task cyc(input integer c); begin repeat (c) begin @(posedge clk); #1; end end endtask

    initial begin
        for (rep = 0; rep < 2; rep = rep + 1) begin
            rst_lvl = rep[0] ? 1'b0 : 1'b1;
            rstn = 0; rx_s = rst_lvl; cyc(4);
            `CHK(sample_shift === {OS{rst_lvl}} && sample_window === {OS{rst_lvl}} && rx_s_d === rst_lvl,
                 "reset loads the current rx_s level into every register");
            rstn = 1;
            for (n = 1; n <= 2000; n = n + 1) begin
                // runs of equal bits and random toggling
                if (n % 50 < 20) rx_s = $random; else rx_s = (n % 7 < 4);
                hist[n] = rx_s;
                cyc(1);
                for (k = 0; k < OS; k = k + 1) begin
                    `CHK(sample_shift[k]  === h(n-k),   "sample_shift tap");
                    `CHK(sample_window[k] === h(n-1-k), "sample_window tap (2 clk behind rx_s)");
                end
                `CHK(rx_s_d === h(n), "rx_s_d is rx_s delayed by one register");
            end
        end
        if (errors == 0) $display("PASS tb_oversampler (OS=%0d)", OS); else $display("FAIL tb_oversampler errors=%0d", errors);
        $finish;
    end

initial begin
    $shm_open("wave.shm");
    $shm_probe("ACTMF");
end

endmodule*/
