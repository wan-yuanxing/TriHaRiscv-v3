`timescale 1ns/1ps
/* Exercise only the board status boundary; CPU and PLL are controlled stubs. */
module tb_dual_board_led;
    reg clk = 0;
    reg rst_n = 0;
    wire [3:0] led;
    wire tx;
    always #5 clk = ~clk;
    triha_cpu_board_top u_dut (
        .ref_clk_pi(clk), .ref_clk_ni(~clk), .rst_ni(rst_n),
        .uart_tx_o(tx), .led_o(led)
    );
    initial begin
        #2; rst_n = 1;
        @(posedge clk); #1;
        if (led !== 4'b0010) $fatal(1, "BOARD_LED_FAIL released reset");
        #2; u_dut.u_soc.done_q = 1;
        #1;
        if (led !== 4'b0010) $fatal(1, "BOARD_LED_FAIL combinational success path");
        @(posedge clk); #1;
        if (led !== 4'b0110) $fatal(1, "BOARD_LED_FAIL registered success");
        #2; u_dut.u_soc.exit_q = 8'h80;
        #1;
        if (led !== 4'b0110) $fatal(1, "BOARD_LED_FAIL combinational error path");
        @(posedge clk); #1;
        if (led !== 4'b1010) $fatal(1, "BOARD_LED_FAIL registered error");
        #2; u_dut.u_soc.done_q = 0; u_dut.u_soc.exit_q = 0;
        #1;
        if (led !== 4'b1010) $fatal(1, "BOARD_LED_FAIL status not held");
        @(posedge clk); #1;
        if (led !== 4'b0010) $fatal(1, "BOARD_LED_FAIL registered idle");
        #2; rst_n = 0;
        #1;
        if (led !== 4'b0000) $fatal(1, "BOARD_LED_FAIL asynchronous reset");
        #2; rst_n = 1;
        @(posedge clk); #1;
        if (led !== 4'b0010) $fatal(1, "BOARD_LED_FAIL second release");
        $display("BOARD_LED_PASS registered_status=1 asynchronous_reset=1");
        $finish;
    end
endmodule

module triha_cpu_clock_reset (
    input wire ref_clk_pi, input wire ref_clk_ni, input wire rst_ni,
    output wire cpu_clk_o, output wire pll_locked_o, output wire cpu_rst_no
);
    assign cpu_clk_o = ref_clk_pi;
    assign pll_locked_o = 1'b1;
    assign cpu_rst_no = rst_ni;
endmodule

module triha_minimal_soc #(
    parameter ROM_FILE = "rom.hex", parameter SRAM_FILE = "sram.hex"
) (
    input wire clk_i, input wire rst_ni, input wire external_irq_i,
    output wire uart_tx_o, output wire done_o, output wire [7:0] exit_code_o
);
    reg done_q = 0;
    reg [7:0] exit_q = 0;
    assign done_o = done_q;
    assign exit_code_o = exit_q;
    assign uart_tx_o = 1'b1;
endmodule
