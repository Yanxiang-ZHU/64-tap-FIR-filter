
`timescale 1ns/1ps
module dbg_gap;
  localparam P=8,K=8,PW=20,NTEST=2000;
  reg clk1=0, clk2=0, rstn=0, dv=0; reg signed [15:0] din=0, cin=0; reg [5:0] caddr=0; reg cload=0;
  wire signed [15:0] dout; wire dvalid;
  always #5 clk1=~clk1;
  initial begin #0.31; forever #0.5555 clk2=~clk2; end
  fir_core #(.P(P),.K(K),.PW(PW)) u(.rstn(rstn),.clk1(clk1),.clk2(clk2),.din(din),.din_valid(dv),
    .cin(cin),.caddr(caddr),.cload(cload),.dout(dout),.dout_valid(dvalid));
  integer nwr=0, ndrop=0, nacc=0, i, nd=0, seed=99;
  always @(posedge clk1) if (u.u_sync.winc) nwr=nwr+1; else if (dv && u.u_sync.full) ndrop=ndrop+1;
  always @(posedge clk2) if (u.smp_accept) nacc=nacc+1;
  always @(posedge clk2) if (dvalid) nd=nd+1;
  initial begin
    #50 rstn=1;
    @(negedge clk2);
    for(i=0;i<64;i=i+1) begin cin=i; caddr=i[5:0]; cload=1; @(negedge clk2); end
    cload=0;
    for(i=0;i<NTEST;i=i+1) begin
      @(negedge clk1);
      if (($random(seed) & 32'h7) == 0) begin
        dv=0; repeat(1+($random(seed)&3)) @(negedge clk1);
      end
      din=$random(seed); dv=1;
    end
    @(negedge clk1); dv=0;
    repeat(40) @(negedge clk2);
    $display("writes=%0d drops=%0d accepts=%0d outputs=%0d steps=%0d", nwr, ndrop, nacc, nd, NTEST);
    $finish;
  end
  initial begin #2000000 $display("TIMEOUT w=%0d d=%0d a=%0d o=%0d",nwr,ndrop,nacc,nd); $finish; end
endmodule
