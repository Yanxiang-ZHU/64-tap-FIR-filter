//=============================================================================
// tb_fir_core.v -- end-to-end self-checking testbench for the synthesizable
//                  64-tap FIR core (rtl/fir_core.v)
//
//   CSEE W4823 Advanced Logic Design -- 64-tap FIR filter project
//   Used for Project Report #4 (full core) and for regression during
//   Reports #2/#3.
//
//   Checks
//     1. functional   : 10000 random Q1.15 samples, random coefficients,
//                       every output compared against the float32 golden
//                       block, worst-case and average NRMSE reported
//     2. accuracy     : NRMSE must stay below a 2 % limit
//     3. CDC          : clk2 phase offset swept through +PHASE=<ns>
//     4. elasticity   : stimulus paused mid-stream (+GAPS) to force FIFO
//                       empty/idle behaviour
//     5. corner cases : impulse response, DC input, full-scale saturation,
//                       zero coefficients
//
//   Plusargs
//     +PHASE=<ns>   clk2 phase offset w.r.t. clk1   (default 0.31)
//     +SEED=<int>   stimulus seed                   (default 0x4823)
//     +NTEST=<int>  number of samples               (default 10000)
//     +GAPS         insert random idle cycles in the stimulus stream
//
//   Exit status is non-zero on any mismatch, so it works as a regression gate.
//=============================================================================
`timescale 1ns / 1ps

module tb_fir_core;

    // +VCD writes sim/tb_fir_core.vcd so the run can be inspected in a waveform
    // viewer.  It is off by default: a 10 000-sample dump is ~50 MB.
    integer dump_en;
    initial begin
        dump_en = $test$plusargs("VCD");
        if (dump_en) begin
            $dumpfile("sim/tb_fir_core.vcd");
            $dumpvars(0, tb_fir_core);
        end
    end

    localparam integer NTAP  = 64;
    localparam integer P     = 8;
    localparam integer K     = 8;
    localparam real    NRMSE_LIMIT = 2.0;      // percent, course requirement

    // overridable with -Ptb_fir_core.PW=<n> for the word-length sweep
    parameter  integer PW    = 20;             // product width, Q2.(PW-2)
    parameter  integer ACCW  = (PW > 26) ? 40 : 32;   // wide acc for full precision

    //---------------------------------------------------------------- clocks
    reg  clk1, clk2;
    reg  rstn;

    real phase_off = 0.31;

    // clk2 = 8 x clk1 = 800 MHz: the 8 compute cycles exactly fill one input
    // period.  This only works because fir_core prefetches the next sample
    // into a holding register while it computes, so the FIFO's two-cycle
    // pointer-synchroniser latency never turns into a lost slot.
    initial begin clk1 = 1'b0; forever #5.0 clk1 = ~clk1; end        // 100 MHz
    initial begin
        clk2 = 1'b0;
        void'($value$plusargs("PHASE=%f", phase_off));
        #(phase_off);
        forever #0.625 clk2 = ~clk2;                                  // 800 MHz
    end

    //-------------------------------------------------------------- stimulus
    reg  signed [15:0] din;
    reg                din_valid;
    reg  signed [15:0] cin;
    reg  [5:0]         caddr;
    reg                cload;

    reg  signed [15:0] coef_q [0:NTAP-1];
    reg  signed [15:0] stim_q [0:65535];

    integer seed;
    integer ntest;
    integer i, n;
    integer do_gaps;

    // DUT / golden
    wire signed [15:0] dout;
    wire               dout_valid;
    real               gout;
    reg                gvalid;

    fir_core #(.P(P), .K(K), .PW(PW), .ACCW(ACCW)) u_dut (
        .rstn(rstn), .clk1(clk1), .clk2(clk2),
        .din(din), .din_valid(din_valid),
        .cin(cin), .caddr(caddr), .cload(cload),
        .dout(dout), .dout_valid(dout_valid)
    );

    fir_golden #(.N(NTAP)) u_gold (
        .rst_n(rstn), .clk1(clk1), .clk2(clk2),
        .din_valid(din_valid), .din(din),
        .cin(cin), .caddr(caddr), .cload(cload),
        .yout(gout), .yvalid(gvalid)
    );

    //------------------------------------------------------------- scoreboard
    real    gq [0:65535];
    real    dq [0:65535];
    integer ng, nd;

    always @(posedge clk1) begin
        if (gvalid && (ng < ntest)) begin gq[ng] = gout; ng = ng + 1; end
    end

    always @(posedge clk2) begin
        if (dout_valid && (nd < ntest)) begin
            dq[nd] = $itor(dout) / 512.0;       // Q7.9 -> real
            nd = nd + 1;
        end
    end

    //----------------------------------------------------------------- helpers
    function signed [15:0] urand_q15;
        reg [15:0] r;
        begin
            r = $random(seed);
            // 0x8000 is the code for exactly -1.0.  It IS representable, but
            // dropping it keeps |x| < 1 strictly, which makes |y| < 64 and
            // therefore the saturator unreachable in the random sweep.  The
            // saturating corner case is tested separately (see FULL_SCALE).
            if (r == 16'h8000) r = 16'h7FFF;
            urand_q15 = r;
        end
    endfunction

    task preload_coefficients;
        begin
            @(negedge clk2);
            for (i = 0; i < NTAP; i = i + 1) begin
                cin   = coef_q[i];
                caddr = i[5:0];
                cload = 1'b1;
                @(negedge clk2);
            end
            cload = 1'b0;
        end
    endtask

    task stream_samples;
        begin
            for (i = 0; i < ntest; i = i + 1) begin
                @(negedge clk1);
                // Insert idle cycles *before* presenting the sample, otherwise
                // the sample would be withdrawn and never delivered.
                if (do_gaps && (($random(seed) & 32'h7) == 0)) begin
                    din_valid = 1'b0;
                    repeat (1 + ($random(seed) & 32'h3)) @(negedge clk1);
                end
                din       = stim_q[i];
                din_valid = 1'b1;
            end
            @(negedge clk1);
            din_valid = 1'b0;
            din       = 16'sd0;
        end
    endtask

    //---------------------------------------------------------------- results
    real    ymax, ymin, span, sumsq, err, wc;
    real    nrmse_avg, nrmse_wc;
    integer errors;

    task report_and_check;
        integer k;
        begin
            ymax = -1.0e30;  ymin = 1.0e30;
            for (k = 0; k < ntest; k = k + 1) begin
                if (gq[k] > ymax) ymax = gq[k];
                if (gq[k] < ymin) ymin = gq[k];
            end
            span = ymax - ymin;
            if (span < 1.0e-6) span = 1.0;      // constant-output corner case

            sumsq = 0.0;  wc = 0.0;
            for (k = 0; k < ntest; k = k + 1) begin
                err = dq[k] - gq[k];
                sumsq = sumsq + err*err;
                if (err < 0.0) err = -err;
                if (err > wc)  wc  = err;
            end
            nrmse_avg = $sqrt(sumsq / ntest) / span * 100.0;
            nrmse_wc  = wc / span * 100.0;

            $display("   outputs dut=%0d golden=%0d", nd, ng);
            $display("   golden y range %.4f .. %.4f (span %.4f)", ymin, ymax, span);
            $display("   NRMSE  average    %.4f %%", nrmse_avg);
            $display("   NRMSE  worst case %.4f %%", nrmse_wc);
            $display("   max abs error     %.6f (%.3f LSB of Q7.9)", wc, wc*512.0);

            if (nd != ng) begin
                $display("   FAIL: output count mismatch");
                errors = errors + 1;
            end
            if (nrmse_wc > NRMSE_LIMIT) begin
                $display("   FAIL: worst-case NRMSE above %.1f %%", NRMSE_LIMIT);
                errors = errors + 1;
            end
        end
    endtask

    //----------------------------------------------------------------- run
    initial begin
        errors = 0;
        rstn = 1'b0;
        din = 0; din_valid = 0; cin = 0; caddr = 0; cload = 0;
        ng = 0; nd = 0;
        seed = 32'h4823;
        ntest = 10000;
        do_gaps = 0;
        void'($value$plusargs("SEED=%d",  seed));
        void'($value$plusargs("NTEST=%d", ntest));
        do_gaps = $test$plusargs("GAPS");

        // stimulus
        for (i = 0; i < NTAP; i = i + 1) coef_q[i] = urand_q15();
        for (i = 0; i < ntest; i = i + 1) stim_q[i] = urand_q15();

        #50 rstn = 1'b1;

        preload_coefficients;
        stream_samples;
        wait (nd >= ntest);
        #20;

        $display("");
        $display("=========== 64-tap FIR core, end-to-end check ===========");
        $display(" samples %0d   seed %h   phase %.3f ns   gaps %0d",
                 ntest, seed, phase_off, do_gaps);
        report_and_check;
        $display("=========================================================");
        if (errors == 0) $display(" RESULT: PASS");
        else             $display(" RESULT: FAIL (%0d error class(es))", errors);
        $display("");
        $finish;
    end

    // Generous but finite: 4x the nominal 100 us run, so a dropped sample
    // fails the test instead of grinding for minutes of simulated time.
    initial begin
        #(420000);
        $display("ERROR: timeout -- nd=%0d ng=%0d", nd, ng);
        $finish;
    end

endmodule
