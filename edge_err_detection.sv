//==============================================================================
// usb2_cdr_error_detection  (diagram block: "Error_detection")
//   xor           : edge = rx_s ^ rx_s_d
//   Phase Capture : phase_value <= phase (full NCO accumulator) on an edge
//   Error calc    : error = phase_value - EDGE_REF   (wrapped, signed, W bits)
//   Edge_gate     : ted_value = 0 and ted_valid = 0 when there was no edge
//
// ted_value = top TED_W bits of error, 1 LSB = 2^-TED_W bit.
//   ted_value > 0 : edge arrived late in NCO phase  -> NCO is running early
//   ted_value < 0 : edge arrived early              -> NCO is running late
// ted_value / ted_valid are delayed by one clock w.r.t. 'edge' (phase_value
// is a register), so both are aligned with each other.
//==============================================================================
module usb2_cdr_error_detection #(
    parameter W        = 24,
    parameter TED_W    = 6,
    parameter [W-1:0] EDGE_REF = 24'h500000
)(
    input  wire                     clk_sys,
    input  wire                     rstn,
    input  wire                     ce,
    input  wire                     rx_s,
    input  wire                     rx_s_d,
    input  wire [W-1:0]             phase,
    output wire                     edge_o,       // un-gated edge (debug / TB)
    output reg  [W-1:0]             phase_value,
    output wire signed [W-1:0]      error,
    output wire signed [TED_W-1:0]  ted_value,
    output wire                     ted_valid
);

 parameter integer ACC_W = 32;
    parameter [ACC_W-1:0] FCW = 32'd515396076;

   
    reg bit_center_tick;

    reg [ACC_W-1:0] phase_acc;
    reg phase_msb_d;

    wire edge_w = rx_s ^ rx_s_d;
    assign edge_o = edge_w;

    reg edge_q;
    always @(posedge clk_sys) begin
        if (!rstn) begin
            edge_q      <= 1'b0;
            phase_value <= {W{1'b0}};
        end else if (ce) begin
            edge_q      <= edge_w;
            if (edge_w) phase_value <= phase;
        end
    end

    assign error = $signed(phase_value - EDGE_REF);          // wraps to +/-0.5 bit
    wire signed [TED_W-1:0] ted_raw = error[W-1 -: TED_W];   // top bits: no overflow possible

    assign ted_value = edge_q ? ted_raw : {TED_W{1'b0}};
    assign ted_valid = edge_q;// || bit_center_tick;



   
 /*   always @(posedge clk_sys) begin
        if (!rstn) begin
            phase_acc       <= {ACC_W{1'b0}};
            phase_msb_d     <= 1'b0;
            bit_center_tick <= 1'b0;
        end
        else begin
            phase_acc <= phase_acc + FCW;

            phase_msb_d <= phase_acc[ACC_W-1];

            // Detect rising transition of NCO phase MSB
            bit_center_tick <=
                phase_acc[ACC_W-1] && !phase_msb_d;
        end
    end*/



endmodule 




//`timescale 1ns/1ps
// Unit test: usb2_cdr_error_detection
/*`define CHK(c,m) if (!(c)) begin errors = errors + 1; if (errors < 20) $display("ERROR t=%0t: %s", $time, m); end
module tb_error_detection;
    localparam W = 24, TED_W = 6;
    localparam [W-1:0] EDGE_REF = 24'h500000;
    reg clk = 0; always #5 clk = ~clk;
    reg rstn = 0, rx_s = 0, rx_s_d = 0;
    reg [W-1:0] phase = 0;
    wire edge_o, ted_valid;
    wire [W-1:0] phase_value;
    wire signed [W-1:0] error;
    wire signed [TED_W-1:0] ted_value;
    usb2_cdr_error_detection #(.W(W), .TED_W(TED_W), .EDGE_REF(EDGE_REF)) dut (
        .clk_sys(clk), .rstn(rstn), .rx_s(rx_s), .rx_s_d(rx_s_d), .phase(phase),
        .edge_o(edge_o), .phase_value(phase_value), .error(error),
        .ted_value(ted_value), .ted_valid(ted_valid));

    integer errors = 0, i, nn;
    reg [W-1:0] ph, cap;
    task cyc(input integer c); begin repeat (c) begin @(posedge clk); #1; end end endtask

    initial begin
        rstn = 0; cyc(3); rstn = 1; cyc(1);
        `CHK(ted_valid === 0 && ted_value === 0, "idle after reset");

        // ---- no edge: ted is gated to zero whatever the phase ----------------------
        for (i = 0; i < 200; i = i + 1) begin
            rx_s = i[3]; rx_s_d = i[3]; phase = $random;
            #1 `CHK(edge_o === 0, "no edge when rx_s == rx_s_d");
            cyc(1);
            `CHK(ted_valid === 0 && ted_value === 0, "Edge_gate: ted forced to 0 without edge");
        end

        // ---- edge: every ted code, random low bits, rising and falling ---------------
        for (nn = -32; nn <= 31; nn = nn + 1) begin
            ph = EDGE_REF + (nn * 262144) + ($random & 32'h3ffff);   // N * 2^18 + (0..2^18-1)
            rx_s = nn[0]; rx_s_d = ~nn[0]; phase = ph;
            #1 `CHK(edge_o === 1, "edge_o = rx_s ^ rx_s_d (combinational)");
            cyc(1);
            rx_s_d = rx_s; phase = $random;                          // next cycle: no edge, phase moves on
            `CHK(ted_valid === 1, "ted_valid one clk after the edge");
            `CHK(ted_value === nn, "ted_value = top 6 bits of (phase - EDGE_REF)");
            `CHK(phase_value === ph, "Phase Capture holds the phase of the edge cycle");
            cap = ph;
            cyc(1);
            `CHK(ted_valid === 0 && ted_value === 0, "gated again on the next clock");
            `CHK(phase_value === cap, "phase_value holds between edges");
        end

        // ---- wrap-around: phase half a bit away from the reference --------------------
        rx_s = 1; rx_s_d = 0; phase = EDGE_REF + 24'h800000; cyc(1); rx_s_d = 1;
        `CHK(error === -24'sh800000 && ted_value === -32, "error wraps to -0.5 bit (ted = -32)");
        cyc(1);
        rx_s = 0; rx_s_d = 1; phase = EDGE_REF - 24'h000001; cyc(1); rx_s_d = 0;
        `CHK(ted_value === -1, "1 LSB below reference -> ted = -1 (floor)");
        cyc(1);
        rx_s = 1; rx_s_d = 0; phase = EDGE_REF; cyc(1); rx_s_d = 1;
        `CHK(ted_value === 0 && ted_valid === 1, "on-time edge: ted = 0 with ted_valid = 1");
        cyc(1);

        // ---- back-to-back edges ---------------------------------------------------------
        rx_s = 0; rx_s_d = 1; phase = EDGE_REF + 24'h040000; cyc(1);
        rx_s = 1; rx_s_d = 0; phase = EDGE_REF - 24'h080000;
        `CHK(ted_valid === 1 && ted_value === 1, "first of two consecutive edges");
        cyc(1);
        rx_s_d = rx_s; phase = 0;
        `CHK(ted_valid === 1 && ted_value === -2, "second of two consecutive edges");
        cyc(1);
        `CHK(ted_valid === 0, "valid drops after the pair");

        // ---- reset clears the pipeline -------------------------------------------------------
        rx_s = 1; rx_s_d = 0; phase = 24'h123456; cyc(1);
        rstn = 0; cyc(1);
        `CHK(ted_valid === 0 && phase_value === 0, "reset clears edge_q and phase_value");

        if (errors == 0) $display("PASS tb_error_detection"); else $display("FAIL tb_error_detection errors=%0d", errors);
        $finish;
    end
endmodule*/
