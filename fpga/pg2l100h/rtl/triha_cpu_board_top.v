/* CPU-only board deployment boundary: fixed pins, real PLL and local SRAM. */
module triha_cpu_board_top #(
    parameter ROM_FILE = "rom.hex",
    parameter SRAM_FILE = "sram.hex"
) (
    input  wire       ref_clk_pi,
    input  wire       ref_clk_ni,
    input  wire       rst_ni,
    output wire       uart_tx_o,
    output reg  [3:0] led_o
);
    wire cpu_clk;
    wire cpu_reset_n;
    wire done;
    wire [7:0] exit_code;
    triha_cpu_clock_reset u_clocks (
        .ref_clk_pi(ref_clk_pi), .ref_clk_ni(ref_clk_ni), .rst_ni(rst_ni),
        .cpu_clk_o(cpu_clk), .pll_locked_o(), .cpu_rst_no(cpu_reset_n)
    );
    triha_minimal_soc #(.ROM_FILE(ROM_FILE), .SRAM_FILE(SRAM_FILE)) u_soc (
        .clk_i(cpu_clk), .rst_ni(cpu_reset_n), .external_irq_i(1'b0),
        .uart_tx_o(uart_tx_o), .done_o(done), .exit_code_o(exit_code)
    );
    reg [25:0] heartbeat_q;
    always @(posedge cpu_clk or negedge cpu_reset_n) begin
        if (!cpu_reset_n)
            heartbeat_q <= 26'b0;
        else
            heartbeat_q <= heartbeat_q + 1'b1;
    end
    // Register the status decode before the slow physical LED outputs.
    always @(posedge cpu_clk or negedge cpu_reset_n) begin
        if (!cpu_reset_n)
            led_o <= 4'b0;
        else
            led_o <= {done && (exit_code != 8'b0), done && (exit_code == 8'b0),
                      1'b1, heartbeat_q[25]};
    end
endmodule
