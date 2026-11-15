//=============================================================================
// tb_fir_win.v -- unit testbench for fir_win (Report #3 block)
//
//   Pushes a stream of samples and, for every output index n and every tap
//   group j, checks the invariant
//
//       port p  ==  x[n - p - P*j]        (zero before the start of the stream)
//
//   which is the whole point of the rotating bank structure.  Also checks
//   that the group-0 / tap-0 write-through bypass delivers the incoming
//   sample on the accept cycle, and that a bank's contents survive the 7
//   cycles in which it is not written.
//=============================================================================
`timescale 1ns / 1ps

module tb_fir_win;

    localparam integer P  = 8;
    localparam integer K  = 8;
    localparam integer NS = 200;             // samples pushed

    reg  clk, rstn;
    reg  we;
    reg  signed [15:0] din;
    reg  [2:0] gidx;
    wire signed [P*16-1:0] xg;

    fir_win #(.P(P), .K(K)) dut (
        .clk(clk), .rstn(rstn), .we(we), .din(din), .gidx(gidx), .xg(xg)
    );

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    reg signed [15:0] stim [0:NS-1];
    integer errors, n, p, j, seed;

    // expected sample of the stream (zero before index 0)
    function signed [15:0] xs;
        input integer idx;
        begin
            if (idx < 0) xs = 16'sd0;
            else         xs = stim[idx];
        end
    endfunction

    task check;
        input integer nn;
        input integer jj;
        integer pp;
        reg signed [15:0] exp;
        begin
            for (pp = 0; pp < P; pp = pp + 1) begin
                exp = xs(nn - pp - P*jj);
                if (xg[pp*16 +: 16] !== exp) begin
                    $display("FAIL n=%0d j=%0d p=%0d got %0d exp %0d",
                             nn, jj, pp, xg[pp*16 +: 16], exp);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0; seed = 32'hbeef_0042;
        rstn = 1'b0; we = 1'b0; din = 16'sd0; gidx = 3'd0;

        for (n = 0; n < NS; n = n + 1) begin
            stim[n] = $random(seed);
            if (stim[n] == -16'sd32768) stim[n] = 16'sd32767;
        end

        repeat (3) @(posedge clk);
        @(negedge clk); rstn = 1'b1;
        @(negedge clk);

        // One group per clock, all signals changed on the falling edge so that
        // nothing races with the rising edge the DUT samples.
        for (n = 0; n < NS; n = n + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                @(negedge clk);
                gidx = j[2:0];
                if (j == 0) begin
                    din = stim[n];             // accept cycle
                    we  = 1'b1;
                end else begin
                    we  = 1'b0;
                end
                #1;
                check(n, j);                   // j == 0 also exercises the bypass
                @(posedge clk);
            end
        end

        $display("");
        $display("=========== fir_win unit check ===========");
        $display(" window %0d entries = %0d banks x %0d", P*K, P, K);
        $display(" samples pushed %0d, groups checked %0d", NS, NS*K);
        if (errors == 0) $display(" RESULT: PASS");
        else             $display(" RESULT: FAIL (%0d)", errors);
        $display("==========================================");
        $finish;
    end

endmodule
