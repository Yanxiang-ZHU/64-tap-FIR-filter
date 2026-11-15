//=============================================================================
// tb_fir_cmem.v -- unit testbench for fir_cmem (Report #3 block)
//
//   Checks
//     1. the address transpose: coefficient index i must read back on bank
//        (i mod P) at entry (i div P), so that group j presents
//        b[p + P*j] on port p
//     2. read stability: an unrelated write must not disturb the read ports
//     3. write-through timing: a write is visible on the following cycle
//     4. all 64 words are distinct and none is aliased
//=============================================================================
`timescale 1ns / 1ps

module tb_fir_cmem;

    localparam integer P = 8;
    localparam integer K = 8;
    localparam integer NW = 64;

    reg  clk;
    reg  we;
    reg  [5:0] waddr;
    reg  signed [15:0] wdata;
    reg  [2:0] gidx;
    wire signed [P*16-1:0] cg;

    fir_cmem #(.P(P), .K(K)) dut (
        .clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
        .gidx(gidx), .cg(cg)
    );

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    reg  signed [15:0] coef [0:NW-1];
    integer errors, i, p, j;
    integer seed;

    task check_group;
        input integer jj;
        begin
            gidx = jj[2:0];
            #1;
            for (p = 0; p < P; p = p + 1) begin
                if (cg[p*16 +: 16] !== coef[p + P*jj]) begin
                    $display("FAIL group=%0d bank=%0d got %0d exp %0d",
                             jj, p, cg[p*16 +: 16], coef[p + P*jj]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0; seed = 32'hc0de_1234;
        we = 0; waddr = 0; wdata = 0; gidx = 0;

        // ---- distinct coefficient set
        for (i = 0; i < NW; i = i + 1) begin
            coef[i] = $random(seed);
            if (coef[i] == -16'sd32768) coef[i] = 16'sd32767;
        end

        // ---- preload, one word per cycle, natural index order
        repeat (2) @(posedge clk);
        for (i = 0; i < NW; i = i + 1) begin
            @(negedge clk);
            we    = 1'b1;
            waddr = i[5:0];
            wdata = coef[i];
        end
        @(negedge clk);
        we = 1'b0;

        // ---- read back the whole transpose
        for (j = 0; j < K; j = j + 1) check_group(j);

        // ---- an unrelated write must not perturb the read ports
        @(negedge clk);
        waddr = 6'd0; wdata = 16'sd1234; we = 1'b1;
        gidx  = 3'd5;
        @(negedge clk);
        we = 1'b0;
        // index 0 lives on bank 0 entry 0, group 5 reads entry 5 -> no effect
        for (p = 0; p < P; p = p + 1) begin
            if (cg[p*16 +: 16] !== coef[p + P*5]) begin
                $display("FAIL read disturbed bank=%0d", p);
                errors = errors + 1;
            end
        end

        // ---- write-through: index 0 is visible on group 0 next cycle
        @(negedge clk);
        gidx = 3'd0;
        #1;
        if (cg[0 +: 16] !== 16'sd1234) begin
            $display("FAIL write-through got %0d exp 1234", cg[0 +: 16]);
            errors = errors + 1;
        end

        $display("");
        $display("=========== fir_cmem unit check ===========");
        $display(" capacity %0d x 16b in %0d banks x %0d entries", P*K, P, K);
        $display(" transpose: bank(i mod %0d), entry(i div %0d)", P, P);
        if (errors == 0) $display(" RESULT: PASS");
        else             $display(" RESULT: FAIL (%0d)", errors);
        $display("===========================================");
        $finish;
    end

endmodule
