
`timescale 1ns/1ps
module dbg_win2;
  localparam P=8,K=8;
  reg clk=0, rstn=0, we=0; reg signed [15:0] din=0; reg [2:0] gidx=0;
  wire signed [P*16-1:0] xg;
  always #5 clk=~clk;
  fir_win #(.P(P),.K(K)) dut(.clk(clk),.rstn(rstn),.we(we),.din(din),.gidx(gidx),.xg(xg));
  always @(posedge clk) $display("t=%0t we=%b rot=%0d bank7_0=%0d", $time, we, dut.rot, dut.bank[7][0]);
  initial begin
    din = 111;
    repeat(3) @(posedge clk);
    @(negedge clk); rstn=1;
    @(negedge clk); we=1;
    @(posedge clk); we=0;
    @(posedge clk);
    @(posedge clk);
    $display("final rot=%0d b7_0=%0d b7_1=%0d", dut.rot, dut.bank[7][0], dut.bank[7][1]);
    $finish;
  end
endmodule
