
`timescale 1ns/1ps
module dbg_win;
  localparam P=8,K=8,NS=6;
  reg clk=0, rstn=0, we=0; reg signed [15:0] din=0; reg [2:0] gidx=0;
  wire signed [P*16-1:0] xg;
  always #5 clk=~clk;
  fir_win #(.P(P),.K(K)) dut(.clk(clk),.rstn(rstn),.we(we),.din(din),.gidx(gidx),.xg(xg));
  integer n,j,p; reg signed [15:0] stim[0:NS-1];
  function signed [15:0] xs; input integer i; begin xs = (i<0)?0:stim[i]; end endfunction
  initial begin
    for(n=0;n<NS;n=n+1) stim[n]=n*100+1;
    repeat(3) @(posedge clk); @(negedge clk); rstn=1; @(negedge clk);
    for(n=0;n<NS;n=n+1) begin
      din=stim[n]; we=1; gidx=0; #1;
      $write("n=%0d j=0 rot=%0d got",n,dut.rot); for(p=0;p<P;p=p+1) $write(" %0d",xg[p*16+:16]);
      $write("  exp"); for(p=0;p<P;p=p+1) $write(" %0d",xs(n-p)); $write("\n");
      @(posedge clk); we=0;
      for(j=1;j<K;j=j+1) begin
        @(negedge clk); gidx=j[2:0]; #1;
        $write("n=%0d j=%0d rot=%0d got",n,j,dut.rot); for(p=0;p<P;p=p+1) $write(" %0d",xg[p*16+:16]);
        $write("  exp"); for(p=0;p<P;p=p+1) $write(" %0d",xs(n-p-P*j)); $write("\n");
        @(posedge clk);
      end
      @(negedge clk);
    end
    $finish;
  end
endmodule
