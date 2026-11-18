//=============================================================================
// tb_fir_fullscale.v -- directed corner case: the one input that saturates
//
//   The random sweep deliberately drops the code 0x8000 so that |x| < 1 holds
//   strictly, which keeps |y| < 64 and leaves the saturator unreachable.  That
//   makes the saturator the one path a random test can never cover, so it gets
//   its own directed test here.
//
//   0x8000 is a legal Q1.15 word: it is exactly -1.0.  With every input and
//   every coefficient at -1.0 the ideal output is exactly +64.0, while the
//   Q7.9 format tops out at 63.998.  Correct behaviour is to clamp to 32767,
//   not to wrap to -64.0.
//
//   Three cases are checked:
//     1. all x = b = -1.0        -> ideal +64.0  -> must clamp to +32767
//     2. all x = b = +0.99997    -> ideal 63.996 -> must NOT clamp (32766)
//     3. all x = -1.0, b = +0.99997 -> ideal -63.998 -> must NOT clamp (-32767)
//
//   Also verifies the accumulator does not overflow on the way: 64 products of
//   1.0 need 2^24 in Q2.18, far inside the 32-bit range.
//=============================================================================
`timescale 1ns / 1ps

module tb_fir_fullscale;

    localparam integer P = 8, K = 8, PW = 20;

    reg  clk1, clk2, rstn, dv;
    reg  signed [15:0] din, cin;
    reg  [5:0] caddr;
    reg  cload;

    wire signed [15:0] dout;
    wire               dvalid;

    fir_core #(.P(P), .K(K), .PW(PW)) dut (
        .rstn(rstn), .clk1(clk1), .clk2(clk2),
        .din(din), .din_valid(dv),
        .cin(cin), .caddr(caddr), .cload(cload),
        .dout(dout), .dout_valid(dvalid)
    );

    initial begin clk1 = 1'b0; forever #5.0   clk1 = ~clk1; end
    initial begin clk2 = 1'b0; #0.31; forever #0.625 clk2 = ~clk2; end

    integer n, i, errors;
    reg signed [15:0] last_y;

    always @(posedge clk2) if (dvalid) begin
        n = n + 1;
        last_y = dout;
    end

    // hold reset long enough for BOTH clock domains: five clk1 periods
    task reset_dut;
        begin
            dv = 0; cload = 0; din = 0; cin = 0; caddr = 0;
            rstn = 1'b0;
            repeat (8) @(negedge clk1);
            rstn = 1'b1;
            repeat (8) @(negedge clk2);
        end
    endtask

    task run_case;
        input signed [15:0] xv;
        input signed [15:0] cv;
        input signed [15:0] exp_y;
        input               may_clamp;
        input [8*24-1:0]    tag;
        begin
            reset_dut;
            n = 0;
            for (i = 0; i < 64; i = i + 1) begin
                cin = cv; caddr = i[5:0]; cload = 1'b1;
                @(negedge clk2);
            end
            cload = 1'b0;
            // 70 samples so the window is fully populated past the last tap
            for (i = 0; i < 70; i = i + 1) begin
                @(negedge clk1);
                din = xv; dv = 1'b1;
            end
            @(negedge clk1); dv = 1'b0;
            repeat (40) @(negedge clk2);

            $write("  %0s  y = %0d (%.6f)", tag, last_y, $itor(last_y)/512.0);
            if (may_clamp) begin
                if (last_y !== exp_y) begin
                    $write("   FAIL, expected clamp to %0d", exp_y);
                    errors = errors + 1;
                end else $write("   OK (saturated, did not wrap)");
            end else begin
                if (last_y !== exp_y) begin
                    $write("   FAIL, expected %0d", exp_y);
                    errors = errors + 1;
                end else $write("   OK (no clamp)");
            end
            $write("\n");
        end
    endtask

    initial begin
        errors = 0; n = 0; last_y = 0;
        $display("");
        $display("=========== full-scale / saturation corner case ===========");

        // ideal +64.0 exceeds the Q7.9 maximum of 63.998 -> must clamp
        run_case(-16'sd32768, -16'sd32768, 16'sd32767, 1'b1, "all x=b=-1.0      ");
        // ideal +63.996, inside the range
        run_case( 16'sd32767,  16'sd32767, 16'sd32766, 1'b0, "all x=b=+0.99997  ");
        // ideal -63.996, inside the range (negative rail is -64.0)
        run_case(-16'sd32768,  16'sd32767, -16'sd32767, 1'b0, "x=-1.0, b=+0.99997");

        if (errors == 0) $display(" RESULT: PASS");
        else             $display(" RESULT: FAIL (%0d)", errors);
        $display("==========================================================");
        $finish;
    end

    initial begin
        #200000;
        $display("ERROR: timeout");
        $finish;
    end

endmodule
