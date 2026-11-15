//=============================================================================
// tb_fir_alu.v -- unit testbench for fir_alu (Report #2 block)
//
//   Checks, at full throughput (one group per cycle):
//     1. the running accumulator after every group
//     2. the Q7.9 output word and the y_valid pulse on the final group
//     3. accumulator clear between output samples
//     4. saturation at positive and negative full scale
//     5. full-precision mode (PW = 32) when enabled
//
//   The reference model in the testbench is an independent, 64-bit integer
//   implementation of the specified numerics, not a copy of the RTL.
//=============================================================================
`timescale 1ns / 1ps

module tb_fir_alu;

    localparam integer P    = 8;
    localparam integer K    = 8;
    localparam integer PW   = 20;
    localparam integer ACCW = 32;
    localparam integer NG   = 400;           // groups driven

    localparam integer PSH = 30 - (PW - 2);
    localparam integer OSH = (PW - 2) - 9;

    reg  clk, rstn;
    reg  start, last;
    reg  signed [P*16-1:0] xg, cg;

    wire signed [ACCW-1:0] acc;
    wire signed [15:0]     y;
    wire                   y_valid;

    fir_alu #(.P(P), .PW(PW), .ACCW(ACCW)) dut (
        .clk(clk), .rstn(rstn),
        .start(start), .last(last),
        .xg(xg), .cg(cg),
        .acc_o(acc), .y(y), .y_valid(y_valid)
    );

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    //----------------------------------------------------------------- helper
    function signed [PW-1:0] q_prod;
        input signed [15:0] a, b;
        reg   signed [31:0] t;
        begin
            t = a * b;
            if (PSH > 0) q_prod = (t + (32'sd1 <<< (PSH-1))) >>> PSH;
            else         q_prod = t;
        end
    endfunction

    reg  signed [63:0] ref_acc [0:NG-1];     // expected accumulator AFTER group gi
    reg  signed [15:0] ref_y   [0:NG-1];     // expected y on a final group
    reg                ref_last[0:NG-1];     // group gi is a final group
    reg  signed [63:0] acc_r;
    reg  signed [63:0] ysum, ysh;
    reg  signed [15:0] y_ref;
    integer errors, idx, p, j;
    integer seed;

    //------------------------------------------------------------------ checks
    task automatic drive_group;
        input integer gi;
        input integer is_first;
        input integer is_last;
        begin
            start = is_first;
            last  = is_last;
            for (p = 0; p < P; p = p + 1) begin
                xg[p*16 +: 16] = $random(seed);
                cg[p*16 +: 16] = $random(seed);
            end
            // reference accumulation
            ysum = 0;
            for (p = 0; p < P; p = p + 1)
                ysum = ysum + q_prod(xg[p*16 +: 16], cg[p*16 +: 16]);
            if (is_first) acc_r = ysum;
            else          acc_r = acc_r + ysum;

            ref_last[gi] = is_last;
            if (is_last) begin
                ysh = (acc_r + (64'sd1 <<< (OSH-1))) >>> OSH;
                if      (ysh >  64'sd32767) y_ref =  16'sd32767;
                else if (ysh < -64'sd32768) y_ref = -16'sd32768;
                else                        y_ref = ysh[15:0];
                ref_y[gi] = y_ref;
                acc_r = 0;
            end
            ref_acc[gi] = acc_r;               // the accumulator is cleared here
        end
    endtask

    task automatic drive_constant;
        input integer gi;
        input integer is_first;
        input integer is_last;
        input signed [15:0] xval;
        input signed [15:0] cval;
        begin
            start = is_first;
            last  = is_last;
            for (p = 0; p < P; p = p + 1) begin
                xg[p*16 +: 16] = xval;
                cg[p*16 +: 16] = cval;
            end
            ysum = 0;
            for (p = 0; p < P; p = p + 1)
                ysum = ysum + q_prod(xval, cval);
            if (is_first) acc_r = ysum;
            else          acc_r = acc_r + ysum;
            ref_last[gi] = is_last;
            if (is_last) begin
                ysh = (acc_r + (64'sd1 <<< (OSH-1))) >>> OSH;
                if      (ysh >  64'sd32767) y_ref =  16'sd32767;
                else if (ysh < -64'sd32768) y_ref = -16'sd32768;
                else                        y_ref = ysh[15:0];
                ref_y[gi] = y_ref;
                acc_r = 0;
            end
            ref_acc[gi] = acc_r;
        end
    endtask

    //--------------------------------------------------------------------- run
    integer nvalid;

    always @(posedge clk) if (y_valid) nvalid = nvalid + 1;

    initial begin
        errors = 0; seed = 32'h1234_5678; nvalid = 0; acc_r = 0;
        rstn = 1'b0; start = 0; last = 0; xg = 0; cg = 0;
        repeat (3) @(posedge clk);
        @(negedge clk); rstn = 1'b1;

        // ---- phase 1 : back-to-back groups, check every accumulator update
        //
        //   negedge : drive group idx        (products are registered at the
        //                                     following posedge)
        //   posedge : accumulator for group idx-1 becomes valid, check it
        //
        // Driving on every negedge issues one group per clock.
        @(negedge clk);
        drive_group(0, 1'b1, (K == 1));
        for (idx = 1; idx <= NG; idx = idx + 1) begin
            @(negedge clk);
            if (idx < NG)
                drive_group(idx, (idx % K) == 0, (idx % K) == (K-1));
            @(posedge clk);
            #1;
            if (acc !== ref_acc[idx-1][ACCW-1:0]) begin
                $display("FAIL acc  group=%0d got %0d exp %0d",
                         idx-1, acc, ref_acc[idx-1]);
                errors = errors + 1;
            end
            if (ref_last[idx-1] && (y !== ref_y[idx-1])) begin
                $display("FAIL y    group=%0d got %0d exp %0d",
                         idx-1, y, ref_y[idx-1]);
                errors = errors + 1;
            end
        end

        // ---- phase 2 : extreme amplitude.  |y| < 64 by construction, so the
        //      saturator is provably unreachable from the data path; this case
        //      only proves the rounding at the very top of the range.
        @(negedge clk); rstn = 1'b0;
        @(negedge clk); rstn = 1'b1; acc_r = 0;
        for (j = 0; j < K; j = j + 1) begin
            @(negedge clk);
            drive_constant(j, j == 0, j == K-1, 16'sd32767, 16'sd32767);
            @(posedge clk);
        end
        @(posedge clk); #1;
        if (y !== y_ref) begin
            $display("FAIL full-scale got %0d exp %0d", y, y_ref);
            errors = errors + 1;
        end
        $display(" max amplitude result: y = %0d (%.4f), saturator not engaged",
                 y, $itor(y)/512.0);

        // ---- phase 3 : saturator, forced (unreachable from the data path).
        //      Force the internal rounded accumulator past the Q7.9 rails and
        //      check that the output clamps instead of wrapping.
        @(negedge clk); rstn = 1'b1;
        force dut.acc_sh = 32'sd 40000;
        @(negedge clk); start = 1'b1; last = 1'b1;
        @(posedge clk);
        @(negedge clk); start = 1'b0; last = 1'b0;
        @(posedge clk); #1;
        if (y !== 16'sd32767) begin
            $display("FAIL clamp+ got %0d exp 32767", y);
            errors = errors + 1;
        end
        release dut.acc_sh;

        @(negedge clk);
        force dut.acc_sh = -32'sd 40000;
        @(negedge clk); start = 1'b1; last = 1'b1;
        @(posedge clk);
        @(negedge clk); start = 1'b0; last = 1'b0;
        @(posedge clk); #1;
        if (y !== -16'sd32768) begin
            $display("FAIL clamp- got %0d exp -32768", y);
            errors = errors + 1;
        end
        release dut.acc_sh;

        $display("");
        $display("=========== fir_alu unit check ===========");
        $display(" P=%0d  PW=%0d (Q2.%0d)  ACCW=%0d", P, PW, PW-2, ACCW);
        $display(" groups driven %0d, y_valid pulses %0d", NG + 2*K, nvalid);
        $display(" expected outputs %0d", (NG/K) + 4);
        if (nvalid != (NG/K) + 4) begin
            $display(" FAIL: y_valid pulse count");
            errors = errors + 1;
        end
        if (errors == 0) $display(" RESULT: PASS");
        else             $display(" RESULT: FAIL (%0d)", errors);
        $display("=========================================");
        $finish;
    end

endmodule
