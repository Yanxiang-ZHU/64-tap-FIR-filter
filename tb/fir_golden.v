//=============================================================================
// fir_golden.v  --  64-tap FIR golden block (float32 reference)
//
//   CSEE W4823 Advanced Logic Design -- Project Report #1
//
//   This block is the *reference* implementation of the 64-tap FIR filter.
//   It lives only in the testbench and is never synthesized, so its area and
//   power are not counted.
//
//   Arithmetic: IEEE-754 binary32 ("shortreal").  Every product and every
//   partial accumulation is rounded to float32, exactly as a float32
//   datapath would behave.  The inputs and coefficients are the *same*
//   16-bit Q1.15 words that are fed to the DUT, so the only difference
//   between golden and DUT is fixed-point quantization -- which is what we
//   want to measure.
//
//   Interface: streams one output per accepted input sample, in the clk1
//   (100 MHz) domain.  Coefficient preload uses the same cin / caddr /
//   cload protocol as the DUT, sampled on clk2.
//=============================================================================
`timescale 1ns / 1ps

module fir_golden #(
    parameter integer NTAP = 64
)(
    input  wire               rstn,
    input  wire               clk1,       // 100 MHz input domain
    input  wire               clk2,       // core domain (coefficient load)
    input  wire               din_valid,  // sample present on din this clk1
    input  wire signed [15:0] din,
    input  wire signed [15:0] cin,        // coefficient write data
    input  wire [5:0]         caddr,      // coefficient write address
    input  wire               cload,      // coefficient write enable
    output real               yout,       // float32-precision result
    output reg                yvalid
);

    // ---------------------------------------------------------------- storage
    shortreal coef [0:NTAP-1];
    shortreal xbuf [0:NTAP-1];
    integer   i;

    // 1.0 / 2^15 : Q1.15 integer -> real
    `define Q15_SHIFT 3.0517578125e-05

    integer idx;

    // ------------------------------------------------------- coefficient load
    // Same protocol as CMEM: caddr + cin + cload, one word per clk2.
    always @(posedge clk2) begin
        if (cload) begin
            coef[caddr] <= $itor(cin) * `Q15_SHIFT;
        end
    end

    // ------------------------------------------------- window + convolution
    // Tracks the same "how many samples have been pushed" as the DUT so
    // that zero history is treated identically.
    integer nsamp;

    initial begin
        yvalid = 1'b0;
        yout   = 0.0;
        nsamp  = 0;
        for (i = 0; i < NTAP; i = i + 1) begin
            xbuf[i] = 0.0;
        end
    end

    always @(posedge clk1) begin
        yvalid <= 1'b0;
        if (!rstn) begin
            nsamp <= 0;
            for (i = 0; i < NTAP; i = i + 1) xbuf[i] = 0.0;
        end else if (din_valid) begin
            // shift the sample window  (xbuf[0] = newest)
            for (i = NTAP-1; i > 0; i = i - 1) begin
                xbuf[i] = xbuf[i-1];
            end
            xbuf[0] = $itor(din) * `Q15_SHIFT;

            // discrete convolution, float32 accumulation
            begin : CONV
                shortreal acc;
                acc = 0.0;
                for (idx = 0; idx < NTAP; idx = idx + 1) begin
                    acc = acc + coef[idx] * xbuf[idx];
                end
                yout   <= acc;
                yvalid <= 1'b1;
                nsamp  <= nsamp + 1;
            end
        end
    end

endmodule
