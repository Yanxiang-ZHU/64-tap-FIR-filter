
`timescale 1ns/1ps
module t_sat;
  localparam P=8,K=8,PW=20;
  reg clk1=0, clk2=0, rstn=0, dv=0; reg signed [15:0] din=0, cin=0; reg [5:0] caddr=0; reg cload=0;
  wire signed [15:0] dout; wire dvalid;
  always #5 clk1=~clk1;
  initial begin #0.31; forever #0.625 clk2=~clk2; end
  fir_core #(.P(P),.K(K),.PW(PW)) u(.rstn(rstn),.clk1(clk1),.clk2(clk2),.din(din),.din_valid(dv),
    .cin(cin),.caddr(caddr),.cload(cload),.dout(dout),.dout_valid(dvalid));
  integer i, n=0; reg signed [15:0] maxout; integer maxn;
  always @(posedge clk2) if (dvalid) begin
     n=n+1;
     if (n>=63 && n<=65) $display("  out[n-1] = %0d  (= %.6f)   <-- window full, all 64 taps", dout, $itor(dout)/512.0);
  end
  task run_case;
    input signed [15:0] xv, cv;
    input [255:0] label;
    begin
      rstn=0; repeat(6) @(negedge clk1); rstn=1; repeat(6) @(negedge clk2); n=0;
      for(i=0;i<64;i=i+1) begin cin=cv; caddr=i[5:0]; cload=1; @(negedge clk2); end
      cload=0;
      for(i=0;i<70;i=i+1) begin @(negedge clk1); din=xv; dv=1; end
      @(negedge clk1); dv=0;
      repeat(30) @(negedge clk2);
      $display("  [%0s] outputs seen = %0d", label, n);
    end
  endtask
  initial begin
    $display("--- all x = b = -32768 (exact -1.0) ---");
    run_case(-16'sd32768, -16'sd32768, "neg");
    $display("--- all x = b = +32767 (max positive) ---");
    run_case(16'sd32767, 16'sd32767, "pos");
    $finish;
  end
endmodule
