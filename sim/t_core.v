
`timescale 1ns/1ps
module t_core;
  reg rstn=0, clk1=0, clk2=0, dv=0; reg signed [15:0] din=0, cin=0; reg [5:0] caddr=0; reg cload=0;
  wire signed [15:0] dout; wire dvalid;
  always #5 clk1=~clk1;
  initial begin #0.31; forever #0.625 clk2=~clk2; end
  fir_core #(.NTAP(64),.P(8),.K(8),.PW(20)) u(.rstn(rstn),.clk1(clk1),.clk2(clk2),.din(din),.din_valid_in(dv),
     .cin(cin),.caddr(caddr),.cload(cload),.dout(dout),.dout_valid(dvalid));
  integer i; integer nout=0;
  always @(posedge clk2) if (dvalid) begin nout=nout+1; if (nout<6) $display("t=%0t out=%0d", $time, dout); end
  initial begin
    #50 rstn=1;
    @(negedge clk2);
    for(i=0;i<64;i=i+1) begin cin=i; caddr=i[5:0]; cload=1; @(negedge clk2); end
    cload=0;
    for(i=0;i<200;i=i+1) begin @(negedge clk1); din=i*37; dv=1; end
    @(negedge clk1); dv=0;
    #200 $display("DONE nout=%0d", nout); $finish;
  end
  initial begin #500000 $display("TIMEOUT nout=%0d", nout); $finish; end
endmodule
