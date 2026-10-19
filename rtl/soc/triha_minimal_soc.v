/* TriHa six-stage single-issue CPU with local ROM/SRAM and MMIO.
 * The CPU buses remain internal. No DDR, NPU, Video, cache or CDC is implied.
 * clk_i is a supplied 100MHz system clock; board PLL/pins are a separate target. */
module triha_minimal_soc #(
    parameter ROM_FILE = "rom.hex",
    parameter SRAM_FILE = "sram.hex"
) (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire       external_irq_i,
    output wire       uart_tx_o,
    output wire       done_o,
    output wire [7:0] exit_code_o
);
    wire inst_req, inst_flush, inst_invalidate, inst_accept, inst_valid, inst_error;
    wire [31:0] inst_addr;
    wire [63:0] inst_rdata;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire data_re, data_cacheable, data_invalidate, data_writeback, data_flush;
    wire data_accept, data_ack, data_error;
    wire [3:0] data_wstrb;
    wire [10:0] data_req_tag, data_resp_tag;
    triha_core #(.RESET_VECTOR(32'h00000000), .DUAL_ISSUE(0)) u_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .external_irq_i(external_irq_i),
        .inst_req_o(inst_req), .inst_flush_o(inst_flush), .inst_invalidate_o(inst_invalidate),
        .inst_addr_o(inst_addr), .inst_accept_i(inst_accept), .inst_valid_i(inst_valid),
        .inst_error_i(inst_error), .inst_rdata_i(inst_rdata),
        .data_addr_o(data_addr), .data_wdata_o(data_wdata), .data_re_o(data_re),
        .data_wstrb_o(data_wstrb), .data_cacheable_o(data_cacheable), .data_req_tag_o(data_req_tag),
        .data_invalidate_o(data_invalidate), .data_writeback_o(data_writeback), .data_flush_o(data_flush),
        .data_rdata_i(data_rdata), .data_accept_i(data_accept), .data_ack_i(data_ack),
        .data_error_i(data_error), .data_resp_tag_i(data_resp_tag)
    );
    triha_soc_memory #(.ROM_FILE(ROM_FILE), .SRAM_FILE(SRAM_FILE)) u_memory (
        .clk_i(clk_i), .rst_ni(rst_ni), .inst_req_i(inst_req), .inst_addr_i(inst_addr),
        .inst_accept_o(inst_accept), .inst_valid_o(inst_valid), .inst_error_o(inst_error), .inst_rdata_o(inst_rdata),
        .data_addr_i(data_addr), .data_wdata_i(data_wdata), .data_re_i(data_re), .data_wstrb_i(data_wstrb),
        .data_req_tag_i(data_req_tag), .data_invalidate_i(data_invalidate), .data_writeback_i(data_writeback),
        .data_flush_i(data_flush), .data_rdata_o(data_rdata), .data_accept_o(data_accept),
        .data_ack_o(data_ack), .data_error_o(data_error), .data_resp_tag_o(data_resp_tag),
        .uart_tx_o(uart_tx_o), .done_o(done_o), .exit_code_o(exit_code_o)
    );
endmodule
