
`timescale 1ns/1ps
module dbg_ref;
  reg clk1=0, clk2=0, rstn=0, dv=0; reg signed [15:0] din=0, cin=0; reg [5:0] caddr=0; reg cload=0;
  wire signed [15:0] dout; wire dvalid; real gout; reg gvalid;
  always #5 clk1=~clk1;
  initial begin #0.31; forever #0.625 clk2=~clk2; end
  fir_core_ref #(.NTAP(64),.PW(20)) u(.rstn(rstn),.clk1(clk1),.clk2(clk2),.din(din),.din_valid_in(dv),
    .cin(cin),.caddr(caddr),.cload(cload),.dout(dout),.dout_valid(dvalid));
  fir_golden #(.NTAP(64)) g(.rstn(rstn),.clk1(clk1),.clk2(clk2),.din_valid(dv),.din(din),
    .cin(cin),.caddr(caddr),.cload(cload),.yout(gout),.yvalid(gvalid));
  integer i, seed=32'h4823; reg signed [15:0] coefq [0:63];
  always @(posedge clk1) if (gvalid) $display("t=%0t gold=%.6f dut=%0d (%.6f)", $time, gout, dout, $itor(dout)/512.0);
  reg signed [15:0] stimq [0:15];
  initial begin
    for(i=0;i<64;i=i+1) coefq[i]=$random(seed);
    for(i=0;i<16;i=i+1) stimq[i]=$random(seed);
    #50 rstn=1;
    @(negedge clk2);
    for(i=0;i<64;i=i+1) begin cin=coefq[i]; caddr=i[5:0]; cload=1; @(negedge clk2); end
    cload=0;
    for(i=0;i<10;i=i+1) begin @(negedge clk1); din=stimq[i]; dv=1; end
    @(negedge clk1); dv=0;
    #100 $finish;
  end
endmodule
