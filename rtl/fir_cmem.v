//=============================================================================
// fir_cmem.v -- coefficient memory, P banks x K entries x 16 bit
//
//   CSEE W4823 Advanced Logic Design -- 64-tap FIR filter project
//   Deliverable for Project Report #3 (memory block).
//
//   Capacity : 64 x 16 bit = 1 kb, organised as P banks of K words.
//   Ports    : one write port (preload), one read port per bank.
//
//   Address transpose
//       Externally the coefficients are addressed by their natural index
//           caddr = i,   i = 0 .. 63,   cin = b[i]
//       Internally they are stored transposed:
//           bank (i mod P), entry (i div P)      ==  b[i]
//       so that at group j every bank p supplies b[p + P*j] from its own
//       entry j.  Consequence: each bank needs exactly ONE read port and
//       every multiplier sees a flat P:1 mux instead of a 64:1 mux.  This is
//       what keeps the memory read cost at P x (K:1 mux) rather than
//       P x (64:1 mux).
//
//   The same transpose is applied to the sample window (fir_win.v) so that
//   bank p of both memories feeds multiplier p with the pair
//       ( x[n-p-P*j] , b[p+P*j] )   for the same tap index i = p + P*j.
//
//   Implementation note
//       1 kb is far below the smallest useful SRAM macro, and a 1-write /
//       8-read SRAM would need 8 replicas anyway.  Flip-flops plus a K:1
//       read mux per bank are both smaller and simpler here; Report #3
//       compares the two options with post-synthesis numbers.
//=============================================================================

module fir_cmem #(
    parameter integer P = 8,        // banks  (= parallel MACs)
    parameter integer K = 8         // entries per bank
)(
    input  wire                    clk,
    input  wire                    we,        // write enable (preload)
    input  wire [5:0]              waddr,     // coefficient index 0 .. P*K-1
    input  wire signed [15:0]      wdata,
    input  wire [2:0]              gidx,      // group index j
    output wire signed [P*16-1:0]  cg         // {b[P-1] ... b[0]} for group j
);

    //-------------------------------------------------------------------------
    // storage
    //-------------------------------------------------------------------------
    reg signed [15:0] mem [0:P-1][0:K-1];      // [bank][entry]

    // natural index -> transposed address
    wire [2:0] wbank = waddr[2:0];             // i mod P  -> bank
    wire [2:0] went  = waddr[5:3];             // i div P  -> entry

    always @(posedge clk) begin
        if (we) mem[wbank][went] <= wdata;
    end

    //-------------------------------------------------------------------------
    // one read port per bank
    //-------------------------------------------------------------------------
    reg [P*16-1:0] cg_r;
    integer p;

    always @(*) begin
        for (p = 0; p < P; p = p + 1)
            cg_r[p*16 +: 16] = mem[p][gidx];
    end

    assign cg = cg_r;

endmodule
