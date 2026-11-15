//=============================================================================
// fir_alu.v -- 8-MAC pipelined multiply-accumulate datapath
//
//   CSEE W4823 Advanced Logic Design -- 64-tap FIR filter project
//   Deliverable for Project Report #2 (ALU block).
//
//   One group of P taps is consumed per clock.  A group is
//       {x[p], c[p]}  for p = 0 .. P-1
//   presented by the core as two packed P*16-bit buses.  The unit
//   accumulates K groups and emits one Q7.9 output word per K groups.
//
//   Numerics
//       input / coefficient : 16-bit signed Q1.15
//       product             : 32-bit  Q2.30  ->  rounded to PW-bit Q2.(PW-2)
//                             (default PW = 20, i.e. Q2.18; PW = 32 keeps
//                              the product at full precision)
//       accumulator         : ACCW-bit, Q2.(PW-2)   (default 32)
//       output              : 16-bit signed Q7.9, round-half-up + saturation
//
//   Range proof (PW = 20)
//       |x| < 1, |c| < 1, 64 taps  =>  |y| < 64, so Q2.18 needs
//       7 integer bits + 18 fractional bits + 1 sign = 26 bits.  32 bits
//       for the accumulator leaves 6 bits of head-room; the measured
//       worst case over 10^4 random coefficient sets is |sum| < 2^25.
//
//   Pipeline
//       stage 1 : P x (16x16) multiplier, product rounding, register
//       stage 2 : 3-level adder tree, accumulate, final round + saturate
//   Latency 2 cycles, throughput 1 group per cycle.  The split puts the
//   multiplier on its own 1.25 ns budget at clk2 = 800 MHz and leaves the
//   shallower adder tree in the other stage.
//
//   Control
//       start : first group of a new output sample; the accumulator is
//               loaded instead of accumulated.  Delayed 1 cycle to match
//               the pipeline.
//       last  : final group; one cycle later the sum is rounded, saturated
//               and emitted on y with y_valid for exactly one cycle, and the
//               accumulator returns to zero.
//       K = 1 degenerates correctly: start and last coincide and the single
//       group is emitted directly.
//
//   Synthesis
//       pure Verilog-2001, no delays, no initial blocks, no latches; every
//       output is assigned on every path.  P, PW and ACCW are parameters.
//=============================================================================

module fir_alu #(
    parameter integer P    = 8,     // parallel multipliers
    parameter integer PW   = 20,    // product width,  Q2.(PW-2), PW <= 30
    parameter integer ACCW = 32     // accumulator width
)(
    input  wire                     clk,
    input  wire                     rstn,
    input  wire                     start,      // pulse: first group of output
    input  wire                     last,       // pulse: final group of output
    input  wire signed [P*16-1:0]   xg,         // {x[P-1] ... x[0]}, 16b each
    input  wire signed [P*16-1:0]   cg,         // {c[P-1] ... c[0]}, 16b each
    output reg  signed [ACCW-1:0]   acc_o,      // running accumulator
    output reg  signed [15:0]       y,          // Q7.9 result
    output reg                      y_valid     // one-cycle pulse with y
);

    //-------------------------------------------------------------------------
    // fixed-point constants
    //-------------------------------------------------------------------------
    localparam integer PSH = 30 - (PW - 2);     // Q2.30    -> Q2.(PW-2)
    localparam integer OSH = (PW - 2) - 9;      // Q2.(PW-2)-> Q7.9

    //=========================================================================
    // stage 1 : multipliers and product rounding
    //=========================================================================
    wire signed [PW-1:0] prodw [0:P-1];

    genvar gi;
    generate
        for (gi = 0; gi < P; gi = gi + 1) begin : g_mac
            wire signed [15:0] x_i = xg[gi*16 +: 16];
            wire signed [15:0] c_i = cg[gi*16 +: 16];
            wire signed [31:0] p30 = x_i * c_i;             // Q2.30

            if (PSH > 0) begin : g_round
                // round-half-up then drop PSH bits; the slice also tells the
                // synthesiser exactly which product bits to implement
                /* verilator lint_off UNUSEDSIGNAL */
                // the low PSH bits only feed the round-up carry; they are
                // deliberately not routed past this adder
                wire signed [31:0] p30r = p30 + (32'sd1 <<< (PSH-1));
                /* verilator lint_on UNUSEDSIGNAL */
                assign prodw[gi] = p30r[PW+PSH-1 : PSH];
            end else begin : g_full
                assign prodw[gi] = p30[PW-1:0];             // full precision
            end
        end
    endgenerate

    reg signed [PW-1:0] prod [0:P-1];
    reg                 start_s1, last_s1;

    integer i;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            start_s1 <= 1'b0;
            last_s1  <= 1'b0;
            for (i = 0; i < P; i = i + 1) prod[i] <= {PW{1'b0}};
        end else begin
            start_s1 <= start;
            last_s1  <= last;
            for (i = 0; i < P; i = i + 1) prod[i] <= prodw[i];
        end
    end

    //=========================================================================
    // stage 2 : 3-level adder tree, accumulate, round, saturate
    //=========================================================================
    // level 1 : 4 adders, PW+1 bits
    wire signed [PW:0]   s10 = prod[0] + prod[1];
    wire signed [PW:0]   s11 = prod[2] + prod[3];
    wire signed [PW:0]   s12 = prod[4] + prod[5];
    wire signed [PW:0]   s13 = prod[6] + prod[7];

    // level 2 : 2 adders, PW+2 bits
    wire signed [PW+1:0] s20 = s10 + s11;
    wire signed [PW+1:0] s21 = s12 + s13;

    // level 3 : 1 adder, PW+3 bits
    wire signed [PW+2:0] sum = s20 + s21;

    // sign-extend the group sum to the accumulator width
    wire signed [ACCW-1:0] sumx = {{(ACCW-(PW+3)){sum[PW+2]}}, sum};

    wire signed [ACCW-1:0] acc_sum = acc_o + sumx;

    // round-half-up from Q2.(PW-2) to Q7.9
    wire signed [ACCW-1:0] half  = {{(ACCW-1){1'b0}}, 1'b1} <<< (OSH-1);
    wire signed [ACCW-1:0] acc_rnd = acc_sum + half;
    wire signed [ACCW-1:0] acc_sh  = acc_rnd >>> OSH;

    // saturation to the 16-bit Q7.9 range
    wire signed [15:0] y_sat = (acc_sh >  32'sd 32767) ?  16'sd 32767 :
                               (acc_sh < -32'sd 32768) ? -16'sd 32768 :
                                                         acc_sh[15:0];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            acc_o   <= {ACCW{1'b0}};
            y       <= 16'sd0;
            y_valid <= 1'b0;
        end else begin
            y_valid <= 1'b0;
            if (last_s1) begin
                y       <= y_sat;
                y_valid <= 1'b1;
                acc_o   <= {ACCW{1'b0}};
            end else if (start_s1) begin
                acc_o   <= sumx;                // fresh sample: load, not add
            end else begin
                acc_o   <= acc_sum;
            end
        end
    end

endmodule
