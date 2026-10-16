`timescale 1ns/1ps
// Integration-only clock model. Actual generated GPLL is tested by tb_pll.
module video_pll(input wire clkin1, output reg clkout0=0,
                 output reg clkout1=0, output reg lock=0);
    integer count=0;
    always #12.5 clkout0=~clkout0;
    always #50 clkout1=~clkout1;
    always @(posedge clkin1) begin
        if(count==7) lock<=1;
        else count<=count+1;
    end
endmodule
