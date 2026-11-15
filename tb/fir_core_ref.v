//=============================================================================
// fir_core_ref.v -- behavioural fixed-point reference model of the FIR core
//
//   CSEE W4823 Advanced Logic Design -- 64-tap FIR filter project
//   Part of the Project Report #1 deliverable.
//
//   This is NOT the design.  It is a deliberately independent, unoptimised
//   implementation of the same numerics that the synthesizable core
//   (rtl/fir_core.v) implements:
//
//       * the same 16-bit Q1.15 input and coefficient words
//       * the same Q2.18 product truncation with round-half-up
//       * the same 32-bit accumulator
//       * the same round-half-up to Q7.9 and the same saturation
//
//   It exists so that Report #1 can ship a runnable self-checking testbench
//   before any RTL exists, and it stays in the tree afterwards as an
//   independent cross-check: tb_fir_core.v checks the synthesizable core
//   against the floating-point golden model, tb_fir_ref.v checks this model
//   against the same golden values, so the two must agree to within one
//   Q7.9 LSB.
//
//   Structure is intentionally naive: a 64-entry shift register and 64
//   multiply-accumulates evaluated in a single clock.  That is ~64
//   multipliers if it were ever synthesised, which is exactly why the real
//   design uses the banked window and 8 MACs instead.
//=============================================================================

module fir_core_ref #(
    parameter integer NTAP = 64,       // total taps
    parameter integer PW   = 20        // product width, Q2.(PW-2)
)(
    input  wire               rstn,
    input  wire               clk1,          // 100 MHz input domain
    input  wire               clk2,          // core domain (coefficient load)
    input  wire signed [15:0] din,
    input  wire               din_valid_in,
    input  wire signed [15:0] cin,           // coefficient write data
    input  wire [5:0]         caddr,         // coefficient write address
    input  wire               cload,         // coefficient write enable
    output reg  signed [15:0] dout,          // Q7.9
    output reg                dout_valid
);

    localparam integer PSH = 30 - (PW - 2);    // Q2.30    -> Q2.(PW-2)
    localparam integer OSH = (PW - 2) - 9;     // Q2.(PW-2)-> Q7.9

    reg signed [15:0] coef [0:NTAP-1];
    reg signed [15:0] xbuf [0:NTAP-1];

    //---------------------------------------------------------------- coefficient
    always @(posedge clk2) begin
        if (cload) coef[caddr] <= cin;
    end

    //------------------------------------------------ window + convolution
    //  The window shift and the convolution live in ONE block and the shift
    //  uses blocking assignments, so the sum below sees the freshly loaded
    //  sample.  (Splitting them, or shifting with <=, silently delays the
    //  window by one sample and costs ~19 % NRMSE.)
    //  48-bit accumulation also covers the full-precision corner case (PW=32).
    reg signed [47:0] acc;
    reg signed [47:0] ytmp;
    reg signed [31:0] pr;
    integer i, k;

    always @(posedge clk1 or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < NTAP; i = i + 1) xbuf[i] = 16'sd0;
            dout       <= 16'sd0;
            dout_valid <= 1'b0;
        end else begin
            dout_valid <= 1'b0;
            if (din_valid_in) begin
                for (i = NTAP-1; i > 0; i = i - 1) xbuf[i] = xbuf[i-1];
                xbuf[0] = din;

                acc = 48'sd0;
                for (k = 0; k < NTAP; k = k + 1) begin
                    pr = xbuf[k] * coef[k];                       // Q2.30
                    if (PSH > 0)
                        acc = acc + ((pr + (32'sd1 <<< (PSH-1))) >>> PSH);
                    else
                        acc = acc + pr;
                end
                ytmp = (acc + (48'sd1 <<< (OSH-1))) >>> OSH;
                if      (ytmp >  48'sd32767)  dout <=  16'sd32767;
                else if (ytmp < -48'sd32768)  dout <= -16'sd32768;
                else                          dout <= ytmp[15:0];
                dout_valid <= 1'b1;
            end
        end
    end

endmodule
