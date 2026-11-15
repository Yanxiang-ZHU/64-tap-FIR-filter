//=============================================================================
// fir_core.v -- 64-tap FIR filter core, top level
//
//   CSEE W4823 Advanced Logic Design -- 64-tap FIR filter project
//   Deliverable for Project Report #4 (full core).
//
//   Integrates
//       fir_sync  : dual-clock FIFO, 16b x 8          (clk1 -> clk2)
//       fir_win   : rotating sample window, 8 x 8 x 16
//       fir_cmem  : coefficient memory,     8 x 8 x 16
//       fir_alu   : 8-MAC pipelined datapath, Q2.18 products, Q7.9 output
//
//   Specification
//       clk1       100 MHz, one 16-bit Q1.15 sample per clock (100 MS/s)
//       clk2       8 x clk1 = 800 MHz, phase-unsynchronised with clk1.
//                  The 8 compute cycles exactly fill one 10 ns input
//                  period, so there is no rate margin.  That is only
//                  safe because the one-word prefetch stage below removes
//                  the synchroniser latency from the critical path: the
//                  next sample is already parked in `hold` when group 0
//                  starts, so a bursty input never costs a slot.
//       latency    ~K+4 clk2 cycles, unconstrained by the specification
//       throughput 100 MS/s, one output per K clk2 cycles
//
//   Control
//       A K-state cycle counter sequences the tap groups.  The next sample is
//       accepted on group 0 (state 0); if the FIFO is empty at that moment the
//       counter stalls in state 0 and the whole datapath simply waits, so the
//       core is fully elastic with respect to clk1.
//
//         state 0        : we = 1, start = 1, gidx = 0
//         states 1..K-1  : gidx = state, last at K-1
//
//       Because fir_alu is two-stage pipelined, group j's products are formed
//       in cycle j and consumed in cycle j+1.  Group K-1 is therefore consumed
//       exactly on state 0 of the following output, and y_valid rises there.
//
//   Coefficient preload
//       caddr is the natural coefficient index 0..63, cin the Q1.15 word, and
//       cload the write strobe; one word per clk2.  fir_cmem transposes the
//       address internally, so no software-side reordering is needed.
//=============================================================================

module fir_core #(
    parameter integer P    = 8,     // parallel MACs  / banks
    parameter integer K    = 8,     // clk2 cycles per output sample
    parameter integer PW   = 20,    // product width, Q2.(PW-2)
    parameter integer ACCW = 32,    // accumulator width
    parameter integer FAW  = 3      // FIFO address width (8 entries)
)(
    input  wire               rstn,
    input  wire               clk1,             // 100 MHz input domain
    input  wire               clk2,             // 9 x clk1 core domain
    input  wire signed [15:0] din,              // Q1.15 input sample
    input  wire               din_valid,        // sample valid this clk1
    input  wire signed [15:0] cin,              // coefficient write data
    input  wire [5:0]         caddr,            // coefficient index
    input  wire               cload,            // coefficient write strobe
    output wire signed [15:0] dout,             // Q7.9 output sample
    output wire               dout_valid        // output valid this clk2
);

    //-------------------------------------------------------------------------
    // 0. schedule nets (declared first: the FIFO pop depends on them)
    //-------------------------------------------------------------------------
    reg  [2:0] gcnt;                        // tap-group index, 0 .. K-1
    wire       smp_accept;                  // a new sample enters the window
    wire       advance;                     // the cycle counter moves on
    wire       alu_start;
    wire       alu_last;

    // one-word prefetch stage: hides the FIFO's pointer-synchroniser latency
    reg  signed [15:0] hold;
    reg                hold_v;
    wire               hold_pop;            // take the next word out of the FIFO

    localparam [2:0] KLAST = K[2:0] - 3'd1;  // index of the final group

    wire signed [P*16-1:0] xg;
    wire signed [P*16-1:0] cg;
    wire signed [ACCW-1:0] acc_dbg;   // running accumulator, unconnected

    //-------------------------------------------------------------------------
    // 1. clock domain crossing
    //-------------------------------------------------------------------------
    wire signed [15:0] sx_dout;
    wire               sx_empty;
    wire               sx_full;      // not consumed: the core is rate-matched

    fir_sync #(.DW(16), .AW(FAW)) u_sync (
        .rstn  (rstn),
        .clk_w (clk1),
        .clk_r (clk2),
        .we    (din_valid),
        .wdata (din),
        .re    (hold_pop),
        .rdata (sx_dout),
        .empty (sx_empty),
        .full  (sx_full)
    );

    //-------------------------------------------------------------------------
    // 2. schedule
    //-------------------------------------------------------------------------
    assign smp_accept = (gcnt == 3'd0) && hold_v;
    assign advance    = (gcnt != 3'd0) || smp_accept;
    assign hold_pop   = !hold_v && !sx_empty;

    always @(posedge clk2 or negedge rstn) begin
        if (!rstn) begin
            hold   <= 16'sd0;
            hold_v <= 1'b0;
        end else begin
            if (hold_pop) begin
                hold   <= sx_dout;
                hold_v <= 1'b1;
            end
            if (smp_accept && !hold_pop) hold_v <= 1'b0;
        end
    end

    always @(posedge clk2 or negedge rstn) begin
        if (!rstn) begin
            gcnt <= 3'd0;
        end else if (smp_accept) begin
            gcnt <= (K == 1) ? 3'd0 : 3'd1;
        end else if (advance) begin
            gcnt <= (gcnt == KLAST) ? 3'd0 : gcnt + 3'd1;
        end
    end

    assign alu_start = smp_accept;
    assign alu_last  = advance && (gcnt == KLAST);

    //-------------------------------------------------------------------------
    // 3. sample window and coefficient memory
    //-------------------------------------------------------------------------
    fir_win #(.P(P), .K(K)) u_win (
        .clk  (clk2),
        .rstn (rstn),
        .we   (smp_accept),
        .din  (hold),
        .gidx (gcnt),
        .xg   (xg)
    );

    fir_cmem #(.P(P), .K(K)) u_cmem (
        .clk   (clk2),
        .we    (cload),
        .waddr (caddr),
        .wdata (cin),
        .gidx  (gcnt),
        .cg    (cg)
    );

    //-------------------------------------------------------------------------
    // 4. datapath
    //-------------------------------------------------------------------------
    fir_alu #(.P(P), .PW(PW), .ACCW(ACCW)) u_alu (
        .clk     (clk2),
        .rstn    (rstn),
        .start   (alu_start),
        .last    (alu_last),
        .xg      (xg),
        .cg      (cg),
        .acc_o   (acc_dbg),
        .y       (dout),
        .y_valid (dout_valid)
    );

endmodule
