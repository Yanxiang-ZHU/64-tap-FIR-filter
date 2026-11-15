
`timescale 1ns/1ps
module t_gold;
  reg rstn=0, clk1=0, clk2=0, dv=0; reg signed [15:0] din=0, cin=0; reg [5:0] caddr=0; reg cload=0;
  real gout; reg gv;
  always #5 clk1=~clk1;
  initial begin #0.31; forever #0.625 clk2=~clk2; end
  fir_golden u(.rstn(rstn),.clk1(clk1),.clk2(clk2),.din_valid(dv),.din(din),.cin(cin),.caddr(caddr),.cload(cload),.yout(gout),.yvalid(gv));
  integer i;
  initial begin
    #50 rstn=1;
    @(negedge clk2);
    for(i=0;i<64;i=i+1) begin cin=i; caddr=i[5:0]; cload=1; @(negedge clk2); end
    cload=0;
    for(i=0;i<5;i=i+1) begin @(negedge clk1); din=i*100; dv=1; end
    @(negedge clk1); dv=0;
    #50 $display("golden ok last=%f", gout); $finish;
  end
  initial begin #5000 $display("timeout"); $finish; end
endmodule
