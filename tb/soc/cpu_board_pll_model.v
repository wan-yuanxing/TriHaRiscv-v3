/* Digital integration substitute only. Real vendor PLL is tested separately. */
`timescale 1ns/1ps
module cpu_board_pll (
    input wire clkin1,
    output reg clkout0 = 0,
    output reg lock = 0
);
    always #5 clkout0 = ~clkout0;
    initial begin repeat(12) @(posedge clkin1); lock = 1; end
endmodule
