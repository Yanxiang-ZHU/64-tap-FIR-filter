
module t_pa;
  real p = 0.31; real q;
  initial begin
    q = 1.0;
    if ($value$plusargs("PHASE=%f", q)) $display("got q=%f", q); else $display("no arg, q=%f", q);
    $display("p=%f", p);
    $finish;
  end
endmodule
