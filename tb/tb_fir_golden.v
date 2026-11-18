`timescale 1ns / 1ps

module tb_fir_golden;
    localparam integer N = 64;

    reg clk1, clk2, rst_n, dv, cload;
    reg signed [15:0] din, cin;
    reg [5:0] caddr;
    real yout;
    reg yvalid;

    reg signed [15:0] coef [0:N-1];
    integer i, seed;

    fir_golden #(
        .N(N)
    ) dut (
        .rst_n(rst_n),
        .clk1(clk1),
        .clk2(clk2),
        .din_valid(dv),
        .din(din),
        .cin(cin),
        .caddr(caddr),
        .cload(cload),
        .yout(yout),
        .yvalid(yvalid)
    );

    initial begin
        clk1 = 1'b0;
        clk2 = 1'b0;
    end

    always #5 clk1 = ~clk1;
    always #0.625 clk2 = ~clk2;


    task reset_dut;
        begin
            dv = 1'b0;
            din = 16'sd0;
            rst_n = 1'b0;
            repeat (6) @(negedge clk1);
            rst_n = 1'b1;
            repeat (2) @(negedge clk1);
        end
    endtask

    task load_coefficients;
        begin
            @(negedge clk2);
            for (i = 0; i < N; i = i + 1) begin
                cin = coef[i];
                caddr = i[5:0];
                cload = 1;
                @(negedge clk2);
            end
            cload = 0;
        end
    endtask

    task push;
        input signed [15:0] value;
        begin
            @(negedge clk1);
            din = value;
            dv = 1;
        end
    endtask

    task stop;
        begin
            @(negedge clk1);
            dv = 0;
            din = 16'sd0;
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fir_golden);


        seed = 32'h9012_3456;
        rst_n = 1'b0;
        dv = 1'b0;
        cload = 0;
        din = 16'sd0;
        cin = 16'sd0;
        caddr = 6'd0;

        // Test 1
        for (i = 0; i < N; i=i+1) begin
            coef[i] = $random(seed);
            if (coef[i] == -16'sd32768)
                coef[i] = 16'sd32767;
        end
        load_coefficients;
        reset_dut;
        push(16'sd16384);
        stop;
        for (i = 0; i < N + 8; i = i + 1)
            push(16'sd0);

        stop;
    

        // Test 2
        reset_dut;
        for (i = 0; i < N; i = i + 1)
            coef[i] = 16'sd0;
        coef[0] = 16'sd8192;
        load_coefficients;
        reset_dut;
        for (i = 0; i < 40; i = i + 1)
            push($random(seed));

        stop;

        // Test 3
        reset_dut;
        for (i = 0; i < N; i = i + 1)
            coef[i] = 16'sd1024;
        load_coefficients;
        reset_dut;
        for (i = 0; i < N + 16; i = i + 1)
            push(16'sd2048);

        stop;

        #100;
        $finish;
    end

endmodule
