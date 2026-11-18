`timescale 1ns / 1ps

module fir_golden #(
    parameter integer N = 64
)(
    input  wire rst_n,
    input  wire clk1,
    input  wire clk2,
    input  wire din_valid,
    input  wire signed [15:0] din,
    input  wire signed [15:0] cin,
    input  wire [5:0] caddr,
    input  wire cload,

    output real yout,
    output reg yvalid
);
    integer i;
    integer j;

    shortreal coef [0:N-1];
    shortreal xbuf [0:N-1];
    shortreal acc;
    

    always @(posedge clk2) begin
        if (cload) begin
            coef[caddr] <= $itor(cin) * 3.0517578125e-05;
        end
    end

    initial begin
        yvalid = 0;
        yout = 0.0;
        for (i = 0; i < N; i = i + 1) begin
            xbuf[i] = 0.0;
        end
    end


    always @(posedge clk1) begin
        yout <= 0.0;
        yvalid <= 0;
        acc <= 0.0;
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) 
                xbuf[i] = 0.0;
        end 
        else if (din_valid) begin
            acc <= 0.0;
            for (i = N-1; i > 0; i = i - 1) begin
                xbuf[i] = xbuf[i-1];
            end
            xbuf[0] = $itor(din) * 3.0517578125e-05; 

            for (j = 0; j < N; j = j + 1) begin
                acc = acc + coef[j]*xbuf[j];
            end
            yout <= acc;
            yvalid <= 1;
        end
    end

endmodule
