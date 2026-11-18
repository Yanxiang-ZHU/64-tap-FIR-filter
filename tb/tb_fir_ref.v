//=============================================================================
// tb_fir_ref.v  --  self-checking testbench for the fixed-point reference model
//
//   CSEE W4823 Advanced Logic Design -- Project Report #1
//
//   Contents (as required by the assignment):
//     1. golden block      : fir_golden  (float32 reference, testbench only)
//     2. input stimulus    : rstn, clk1, clk2 (phase-unsynchronised), din,
//                            valid_in, cin / caddr / cload
//     3. DUT instantiation : fir_core_ref (behavioural, Report #1)
//     4. comparator        : per-sample subtraction, error accumulation
//     5. metrics           : worst-case and average NRMSE over NTEST samples
//
//   clk1 = 100 MHz, clk2 = 800 MHz, arbitrary phase offset between them.
//=============================================================================
`timescale 1ns / 1ps

module tb_fir_ref;

    localparam integer NTAP  = 64;
    localparam integer NTEST = 10000;
    parameter  integer PW    = 20;   // product width, overridable with -Ptb_fir_ref.PW=

    //---------------------------------------------------------------- clocks
    reg clk1, clk2;
    reg rstn;

    real phase_off = 0.31;      // ns; default, overridable with +PHASE=<ns>

    initial begin clk1 = 1'b0; forever #5.0  clk1 = ~clk1; end        // 100 MHz
    initial begin
        // clk2 = 800 MHz with an arbitrary phase offset w.r.t. clk1.
        //   +PHASE=<ns>   override (used for the CDC phase sweep)
        clk2 = 1'b0;
        void'($value$plusargs("PHASE=%f", phase_off));
        #(phase_off);
        forever #0.625 clk2 = ~clk2;
    end

    //-------------------------------------------------------------- stimulus
    reg  signed [15:0] din;
    reg                din_valid_in;
    reg  signed [15:0] cin;
    reg  [5:0]         caddr;
    reg                cload;

    reg  signed [15:0] coef_q [0:NTAP-1];
    reg  signed [15:0] stim_q [0:NTEST-1];

    integer seed;
    integer i, n;

    // DUT outputs
    wire signed [15:0] dout;
    wire               dout_valid;

    // golden outputs
    real               gout;
    reg                gvalid;

    //----------------------------------------------------------------- DUT/ref
    fir_core_ref #(.NTAP(NTAP), .PW(PW)) u_dut (
        .rstn(rstn), .clk1(clk1), .clk2(clk2),
        .din(din), .din_valid_in(din_valid_in),
        .cin(cin), .caddr(caddr), .cload(cload),
        .dout(dout), .dout_valid(dout_valid)
    );

    fir_golden #(.N(NTAP)) u_gold (
        .rst_n(rstn), .clk1(clk1), .clk2(clk2),
        .din_valid(din_valid_in), .din(din),
        .cin(cin), .caddr(caddr), .cload(cload),
        .yout(gout), .yvalid(gvalid)
    );

    //----------------------------------------------------------- scoreboard
    real    gq [0:NTEST+16];
    real    dq [0:NTEST+16];
    integer ng, nd;

    always @(posedge clk1) begin
        if (gvalid && ng < NTEST+16) begin
            gq[ng] = gout;
            ng = ng + 1;
        end
    end

    // fir_core_ref is a clk1-domain model, so its dout_valid is high for a
    // whole 10 ns input period.  It must be sampled on clk1; sampling it on
    // the 800 MHz clk2 would alias every output eight times.
    always @(posedge clk1) begin
        if (dout_valid && nd < NTEST) begin
            dq[nd] = $itor(dout) / 512.0;    // Q7.9 -> real
            nd = nd + 1;
        end
    end

    //------------------------------------------------------------ test flow
    real    ymax, ymin, span;
    real    sumsq, err, wc;
    real    nrmse_avg, nrmse_wc;

    // uniform 16-bit pattern, excludes 0x8000 (== -1.0, outside Q1.15 range)
    function signed [15:0] random_q15;
        reg [15:0] r;
        begin
            r = $random(seed);
            // 0x8000 = exactly -1.0; excluded to keep |x| < 1 strictly
            if (r == 16'h8000) r = 16'h7FFF;
            random_q15 = r;
        end
    endfunction

    initial begin
        // ---- init
        rstn = 1'b0; din = 0; din_valid_in = 0; cin = 0; caddr = 0; cload = 0;
        ng = 0; nd = 0; seed = 32'h4823_0001;

        // ---- random coefficient set (64 x 16-bit Q1.15)
        for (i = 0; i < NTAP; i = i + 1) begin
            coef_q[i] = random_q15();
        end
        // ---- random input stimulus (NTEST x 16-bit Q1.15)
        for (i = 0; i < NTEST; i = i + 1) begin
            stim_q[i] = random_q15();
        end

        // ---- reset
        #50 rstn = 1'b1;

        // ---- coefficient preload: one word per clk2, 64 cycles
        @(negedge clk2);
        for (i = 0; i < NTAP; i = i + 1) begin
            cin   = coef_q[i];
            caddr = i[5:0];
            cload = 1'b1;
            @(negedge clk2);
        end
        cload = 1'b0;

        // ---- stream NTEST samples at 100 MS/s
        for (i = 0; i < NTEST; i = i + 1) begin
            @(negedge clk1);
            din           = stim_q[i];
            din_valid_in  = 1'b1;
        end
        @(negedge clk1);
        din_valid_in = 1'b0;
        din          = 16'sd0;

        // ---- drain
        wait (nd >= NTEST);
        #20;

        // ---- metrics
        ymax = -1.0e30;  ymin = 1.0e30;
        for (i = 0; i < NTEST; i = i + 1) begin
            if (gq[i] > ymax) ymax = gq[i];
            if (gq[i] < ymin) ymin = gq[i];
        end
        span = ymax - ymin;

        sumsq = 0.0;  wc = 0.0;
        for (i = 0; i < NTEST; i = i + 1) begin
            err = dq[i] - gq[i];
            sumsq = sumsq + err*err;
            if (err < 0.0) err = -err;
            if (err > wc)  wc  = err;
        end

        if (nd != NTEST) begin
            $display("ERROR: DUT produced %0d outputs, golden produced %0d", nd, ng);
        end

        nrmse_avg = $sqrt(sumsq / NTEST) / span * 100.0;
        nrmse_wc  = wc / span * 100.0;

        $display("");
        $display("=========== 64-tap FIR self-checking testbench ===========");
        $display(" samples checked     : %0d", NTEST);
        $display(" golden y range      : %.4f .. %.4f  (span %.4f)", ymin, ymax, span);
        $display(" golden hw format    : binary32 (shortreal)");
        $display(" clk2 phase offset   : %.3f ns", phase_off);
        $display(" DUT product format  : Q2.%0d  (%0d-bit)", PW-2, PW);
        $display(" DUT output format   : Q7.9");
        $display(" ---------------------------------------------------------");
        $display(" NRMSE  average      : %.4f %%", nrmse_avg);
        $display(" NRMSE  worst case   : %.4f %%", nrmse_wc);
        $display(" max abs error       : %.6f  (%.3f LSB of Q7.9)", wc, wc*512.0);
        $display("==========================================================");
        if ((nd == NTEST) && (nrmse_wc < 2.0)) $display(" RESULT: PASS");
        else                                  $display(" RESULT: FAIL");
        $display("");
        $finish;
    end

    //----------------------------------------------------------------- timeout
    initial begin
        #(NTEST * 10 * 4 + 100000);
        $display("ERROR: timeout -- nd=%0d ng=%0d", nd, ng);
        $finish;
    end

endmodule
