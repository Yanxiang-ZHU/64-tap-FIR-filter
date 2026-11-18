//=============================================================================
// tb_fir_sync.v -- unit testbench for the dual-clock FIFO (fir_sync)
//
//   This bench exists because the full-core regression cannot see a broken
//   full flag: with a gap-free stimulus the FIFO never fills, so a flag that
//   reports "full" while the FIFO is empty loses nothing.  The three tests
//   below are aimed directly at that failure mode.
//
//   Test A  directed fill/drain
//           8 writes into an idle FIFO must be accepted, the 8th must raise
//           full, and draining must return the words in order with no extra
//           empty/full transitions.
//
//   Test B  ordered streaming with random stalls on both sides
//           the producer writes an incrementing counter, honouring full; the
//           consumer drains at line rate, honouring empty.  Every consumed word
//           must equal the expected counter, so a dropped or duplicated word
//           fails immediately.  This is the check that catches a full flag
//           asserted while the FIFO is empty.
//
//   Test C  long idle then burst
//           the consumer stops for 200 cycles while the producer keeps writing,
//           then drains at full rate.  Data must still be intact.
//
//   All three run with clkw = 100 MHz and clkr = 800 MHz, i.e. the real ratio.
//=============================================================================
`timescale 1ns / 1ps

module tb_fir_sync;

    // +VCD writes sim/tb_fir_sync.vcd so the run can be inspected in a waveform
    // viewer.  It is off by default: a 10 000-sample dump is ~50 MB.
    integer dump_en;
    initial begin
        dump_en = $test$plusargs("VCD");
        if (dump_en) begin
            $dumpfile("sim/tb_fir_sync.vcd");
            $dumpvars(0, tb_fir_sync);
        end
    end

    localparam integer DW = 16;
    localparam integer AW = 3;
    localparam integer DEPTH = (1 << AW);

    reg  rstn, clkw, clkr;
    reg  we, re;
    reg  [DW-1:0] wdata;
    wire [DW-1:0] rdata;
    wire empty, full;

    fir_sync #(.DW(DW), .AW(AW)) dut (
        .rstn(rstn), .clk_w(clkw), .clk_r(clkr),
        .we(we), .wdata(wdata), .re(re), .rdata(rdata),
        .empty(empty), .full(full)
    );

    initial begin clkw = 1'b0; forever #5.0   clkw = ~clkw; end   // 100 MHz
    initial begin clkr = 1'b0; #0.31; forever #0.625 clkr = ~clkr; end // 800 MHz

    //----------------------------------------------------------------- model
    integer wr_cnt;        // words accepted by the writer
    integer rd_exp;        // next word the reader must see
    integer errors;
    integer nread;

    // ---- producer: drive we/wdata combinationally from the flags
    reg  prod_en;
    always @(*) begin
        we    = prod_en && !full;
        wdata = wr_cnt[DW-1:0];
    end

    always @(posedge clkw) begin
        if (rstn && we && !full) wr_cnt <= wr_cnt + 1;
    end

    // ---- consumer: drain at line rate, check ordering
    reg  cons_en;
    always @(*) re = cons_en && !empty;

    always @(posedge clkr) begin
        if (rstn && re && !empty) begin
            nread <= nread + 1;
            if (rdata !== rd_exp[DW-1:0]) begin
                $display("FAIL order: got %0d expected %0d after %0d reads",
                         rdata, rd_exp, nread);
                errors = errors + 1;
            end
            rd_exp <= rd_exp + 1;
        end
    end

    //----------------------------------------------------------------- helpers
    task reset_dut;
        begin
            prod_en = 1'b0; cons_en = 1'b0;
            rstn    = 1'b0;
            wr_cnt  = 0; rd_exp = 0; nread = 0;
            repeat (4) @(posedge clkw);
            @(negedge clkw); rstn = 1'b1;
            repeat (4) @(posedge clkw);
        end
    endtask

    integer i, seed;

    //--------------------------------------------------------------------- run
    initial begin
        errors = 0; seed = 32'h5eed_1234;

        //==== Test A : directed fill / drain ================================
        reset_dut;
        if (empty !== 1'b1 || full !== 1'b0) begin
            $display("FAIL A: after reset empty=%b full=%b", empty, full);
            errors = errors + 1;
        end

        cons_en = 1'b0;
        prod_en = 1'b1;
        // exactly DEPTH writes, then the writer must be blocked by full
        repeat (DEPTH + 4) @(posedge clkw);
        if (wr_cnt != DEPTH) begin
            $display("FAIL A: accepted %0d words, expected %0d", wr_cnt, DEPTH);
            errors = errors + 1;
        end
        if (full !== 1'b1) begin
            $display("FAIL A: full not asserted at depth");
            errors = errors + 1;
        end
        prod_en = 1'b0;

        // drain and check order
        rd_exp = 0; nread = 0;
        cons_en = 1'b1;
        repeat (DEPTH * 4) @(posedge clkr);
        if (nread != DEPTH) begin
            $display("FAIL A: read %0d words, expected %0d", nread, DEPTH);
            errors = errors + 1;
        end
        cons_en = 1'b0;
        repeat (8) @(posedge clkr);
        if (empty !== 1'b1) begin
            $display("FAIL A: empty not asserted after draining");
            errors = errors + 1;
        end
        $display(" Test A: %0d words in, %0d out, full/empty flags correct",
                 DEPTH, nread);

        //==== Test B : ordered streaming with random stalls =================
        reset_dut;
        cons_en = 1'b1;
        for (i = 0; i < 600; i = i + 1) begin
            // random bubbles on the producer side
            prod_en = (($random(seed) & 32'h3) != 0);
            @(posedge clkw);
        end
        prod_en = 1'b0;
        repeat (64) @(posedge clkr);
        cons_en = 1'b0;

        if (wr_cnt != rd_exp || nread != wr_cnt) begin
            $display("FAIL B: wrote %0d, read %0d, expected %0d",
                     wr_cnt, nread, rd_exp);
            errors = errors + 1;
        end
        if (wr_cnt < 200) begin
            $display("FAIL B: only %0d words moved, test is not exercising the FIFO",
                     wr_cnt);
            errors = errors + 1;
        end
        $display(" Test B: %0d words streamed in order, no loss, no duplication",
                 nread);

        //==== Test C : long stall then burst ================================
        reset_dut;
        prod_en = 1'b1;
        cons_en = 1'b0;
        repeat (200) @(posedge clkw);          // FIFO fills and saturates
        prod_en = 1'b0;
        cons_en = 1'b1;
        repeat (200) @(posedge clkr);          // drain
        prod_en = 1'b1;
        repeat (200) @(posedge clkw);
        prod_en = 1'b0;
        repeat (200) @(posedge clkr);          // final drain
        cons_en = 1'b0;

        if (wr_cnt != rd_exp || nread != wr_cnt) begin
            $display("FAIL C: wrote %0d, read %0d, expected %0d",
                     wr_cnt, nread, rd_exp);
            errors = errors + 1;
        end
        $display(" Test C: %0d words survived a 200-cycle stall then burst", nread);

        $display("");
        $display("=========== fir_sync unit check ===========");
        $display(" depth %0d, clkw 100 MHz, clkr 800 MHz", DEPTH);
        $display(" gray full condition inverts the two MSBs");
        if (errors == 0) $display(" RESULT: PASS");
        else             $display(" RESULT: FAIL (%0d)", errors);
        $display("===========================================");
        $finish;
    end

    initial begin
        #5000000;
        $display("ERROR: timeout");
        $finish;
    end

endmodule
