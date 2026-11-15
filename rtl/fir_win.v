//=============================================================================
// fir_win.v -- rotating sample window, P banks x K entries x 16 bit
//
//   CSEE W4823 Advanced Logic Design -- 64-tap FIR filter project
//   Deliverable for Project Report #3 (register / memory block).
//
//   Holds the last P*K = 64 input samples.  For output index n the invariant
//   maintained by the module is
//
//       bank[(p + rot) mod P][j]  ==  x[n - p - P*j]
//
//   so tap group j (taps i = p + P*j, p = 0..P-1) is available as
//   entry j of every bank, one word per bank.  That is what makes a single
//   read port per bank sufficient: at step j all P multipliers read the same
//   address j, each from its own bank.
//
//   Why a rotating register file
//       A shift register of 64 samples shifts every word on every new sample,
//       64 x 16 bits of mux per sample.  Re-labelling which bank serves which
//       tap group costs nothing (it is one rotating read address) and leaves
//       only ONE physical bank to rewrite per accepted sample -- the bank that
//       is being retired from tap group P-1 to tap group 0.  rot decrements by
//       one on every accepted sample and all other banks keep their data.
//
//   Read/write hazard
//       The accepted sample is written at the same clock edge in which tap
//       group 0 is read, and the bank being written is exactly the bank that
//       serves tap group 0.  Only tap p = 0 of group j = 0 collides with the
//       write, and the value it needs is precisely the incoming sample, so a
//       single 2:1 write-through bypass on that one tap resolves it.  Entries
//       j >= 1 are not read in the write cycle (they are read on later
//       cycles), so they are safe.
//=============================================================================

module fir_win #(
    parameter integer P = 8,        // banks  (= parallel MACs)
    parameter integer K = 8         // entries per bank (= groups per output)
)(
    input  wire                    clk,
    input  wire                    rstn,
    input  wire                    we,        // accept a new sample
    input  wire signed [15:0]      din,       // the new sample
    input  wire [2:0]              gidx,      // group index j
    output wire signed [P*16-1:0]  xg         // {x[n-P+1] ... x[n]} for group j
);

    //-------------------------------------------------------------------------
    // storage + rotation state
    //-------------------------------------------------------------------------
    reg signed [15:0] bank [0:P-1][0:K-1];     // [bank][entry]
    reg        [2:0]  rot;                     // bank serving tap group 0

    // The rotation in effect for the *current* output sample.  On the accept
    // cycle the register still holds the previous rotation, so the read side
    // uses the post-update value directly.
    wire [2:0] rsel = we ? (rot - 3'd1) : rot;
    wire [2:0] wbnk = rot - 3'd1;              // bank retired this cycle

    integer b, e, p;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rot <= 3'd0;
            for (b = 0; b < P; b = b + 1)
                for (e = 0; e < K; e = e + 1) bank[b][e] <= 16'sd0;
        end else if (we) begin
            rot <= wbnk;
            // shift the retired bank down by one entry, new sample at entry 0
            for (e = K-1; e > 0; e = e - 1)
                bank[wbnk][e] <= bank[wbnk][e - 1];
            bank[wbnk][0] <= din;
        end
    end

    //-------------------------------------------------------------------------
    // read side: one K:1 mux per bank, plus the group-0 / tap-0 bypass
    //
    // Tap p of group j comes from bank (p + rsel) mod P.  rsel rotates the
    // bank role, so this is a variable read address per bank, not a data move.
    //-------------------------------------------------------------------------
    reg [P*16-1:0] xg_r;

    always @(*) begin
        for (p = 0; p < P; p = p + 1) begin
            if ((p == 0) && we && (gidx == 3'd0))
                xg_r[p*16 +: 16] = din;            // write-through bypass
            else
                xg_r[p*16 +: 16] = bank[(p + rsel) % P][gidx];
        end
    end

    assign xg = xg_r;

endmodule
