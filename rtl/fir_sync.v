//=============================================================================
// fir_sync.v -- clock-domain-crossing synchroniser (asynchronous FIFO)
//
//   CSEE W4823 Advanced Logic Design -- 64-tap FIR filter project
//   Part of the final core (Project Report #4).
//
//   clk1 carries the input samples at 100 MS/s; the core runs on clk2 at
//   800 MHz.  The two clocks are specified to be phase-unsynchronised, so the
//   data path between them is closed with a dual-clock FIFO:
//
//       * gray-coded read/write pointers, so only one bit changes per
//         increment and a metastable sample can never produce a wrong binary
//         pointer, only an early/late one
//       * two flip-flop synchronisers on each pointer into the other domain
//       * registered full / empty flags, evaluated on the *registered*
//         pointers so there is no combinational path from a flag back into
//         its own next-state value
//
//   Depth 8.  The core consumes one sample every K = 8 clk2 cycles, i.e. at
//   exactly the rate clk1 produces them, so the steady-state occupancy is
//   bounded by the pointer synchroniser latency (2-3 cycles) plus any
//   start-up transient.  Depth 8 leaves a wide margin and costs 8 x 16 bits.
//
//   The flags are conservative by one cycle, which is harmless here because
//   the producer never needs to run at the exact full boundary.
//=============================================================================

module fir_sync #(
    parameter integer DW  = 16,     // data width
    parameter integer AW  = 3       // address width -> 2^AW entries
)(
    input  wire            rstn,
    input  wire            clk_w,   // write clock  (clk1, 100 MHz)
    input  wire            clk_r,   // read  clock  (clk2, 800 MHz)
    input  wire            we,      // push
    input  wire [DW-1:0]   wdata,
    input  wire            re,      // pop request
    output wire [DW-1:0]   rdata,   // head of FIFO (valid when !empty)
    output wire            empty,
    output wire            full
);

    localparam integer PW = AW + 1;            // pointer width (extra MSB bit)

    reg  [DW-1:0] mem [0:(1<<AW)-1];

    reg  [PW-1:0] wbin, wgray, rbin, rgray;
    reg  [PW-1:0] wq1, wq2;                    // wgray synchronised into clk_r
    reg  [PW-1:0] rq1, rq2;                    // rgray synchronised into clk_w

    wire [PW-1:0] wbin_nx, wgray_nx, rbin_nx, rgray_nx;
    wire          winc, rinc;

    function [PW-1:0] gray;                    // binary -> gray
        input [PW-1:0] b;
        begin
            gray = b ^ (b >> 1);
        end
    endfunction

    assign winc     = we && !full;
    assign rinc     = re && !empty;

    assign wbin_nx  = wbin  + {{(PW-1){1'b0}}, winc};
    assign wgray_nx = gray(wbin_nx);
    assign rbin_nx  = rbin  + {{(PW-1){1'b0}}, rinc};
    assign rgray_nx = gray(rbin_nx);

    // full / empty on the registered pointers: one cycle conservative, no loop.
    //
    // The full condition inverts the TWO most significant gray bits, not just
    // the top one: in gray code a pointer that is exactly 2^AW ahead differs
    // in the top two bits.  Inverting only the MSB makes the flag assert when
    // the FIFO is empty -- the writer then silently drops every word that
    // arrives, which is invisible in a gap-free testbench but loses ~3 % of
    // the samples as soon as the input is bursty.
    assign full  = (wgray == {~rq2[PW-1], ~rq2[PW-2], rq2[PW-3:0]});
    assign empty = (rgray == wq2);

    assign rdata = mem[rbin[AW-1:0]];

    // ---- write domain -----------------------------------------------------
    always @(posedge clk_w or negedge rstn) begin
        if (!rstn) begin
            wbin <= {PW{1'b0}};
            wgray <= {PW{1'b0}};
            rq1   <= {PW{1'b0}};
            rq2   <= {PW{1'b0}};
        end else begin
            if (winc) mem[wbin[AW-1:0]] <= wdata;
            wbin  <= wbin_nx;
            wgray <= wgray_nx;
            rq1   <= rgray;                    // 2-FF synchroniser
            rq2   <= rq1;
        end
    end

    // ---- read domain ------------------------------------------------------
    always @(posedge clk_r or negedge rstn) begin
        if (!rstn) begin
            rbin <= {PW{1'b0}};
            rgray <= {PW{1'b0}};
            wq1  <= {PW{1'b0}};
            wq2  <= {PW{1'b0}};
        end else begin
            rbin  <= rbin_nx;
            rgray <= rgray_nx;
            wq1   <= wgray;                    // 2-FF synchroniser
            wq2   <= wq1;
        end
    end

endmodule
