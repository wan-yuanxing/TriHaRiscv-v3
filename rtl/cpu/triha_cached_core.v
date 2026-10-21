/* TriHa six-stage single-issue CPU with paired I/D Cache and AXI128.
 * Opt-in DDR-execution boundary. Local ROM/SRAM/MMIO routing, DDR init and
 * CDC/fabric/board admission remain enclosing-system responsibilities.
 */
module triha_cached_core #(
    parameter [31:0] RESET_VECTOR = 32'h80000000,
    parameter integer CACHE_ENABLE = 1
) (
    input wire clk_i,
    input wire rst_ni,
    input wire external_irq_i,
    output wire protocol_fault_o,
    output wire         axi_awvalid_o,
    output wire [31:0]  axi_awaddr_o,
    output wire [3:0]   axi_awid_o,
    output wire [7:0]   axi_awlen_o,
    output wire [2:0]   axi_awsize_o,
    output wire [1:0]   axi_awburst_o,
    input  wire         axi_awready_i,
    output wire         axi_wvalid_o,
    output wire [127:0] axi_wdata_o,
    output wire [15:0]  axi_wstrb_o,
    output wire         axi_wlast_o,
    input  wire         axi_wready_i,
    input  wire         axi_bvalid_i,
    input  wire [1:0]   axi_bresp_i,
    input  wire [3:0]   axi_bid_i,
    output wire         axi_bready_o,
    output wire         axi_arvalid_o,
    output wire [31:0]  axi_araddr_o,
    output wire [3:0]   axi_arid_o,
    output wire [7:0]   axi_arlen_o,
    output wire [2:0]   axi_arsize_o,
    output wire [1:0]   axi_arburst_o,
    input  wire         axi_arready_i,
    input  wire         axi_rvalid_i,
    input  wire [127:0] axi_rdata_i,
    input  wire [1:0]   axi_rresp_i,
    input  wire [3:0]   axi_rid_i,
    input  wire         axi_rlast_i,
    output wire         axi_rready_o
);
    wire inst_req;
    wire inst_flush;
    wire inst_invalidate;
    wire [31:0] inst_addr;
    wire inst_accept;
    wire inst_valid;
    wire inst_error;
    wire [63:0] inst_rdata;
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire data_re;
    wire [3:0] data_wstrb;
    wire data_cacheable;
    wire [10:0] data_req_tag;
    wire data_invalidate;
    wire data_writeback;
    wire data_flush;
    wire [31:0] data_rdata;
    wire data_accept;
    wire data_ack;
    wire data_error;
    wire [10:0] data_resp_tag;
    triha_core #(.RESET_VECTOR(RESET_VECTOR), .DUAL_ISSUE(0)) u_core (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .external_irq_i(external_irq_i),
        .inst_req_o(inst_req),
        .inst_flush_o(inst_flush),
        .inst_invalidate_o(inst_invalidate),
        .inst_addr_o(inst_addr),
        .inst_accept_i(inst_accept),
        .inst_valid_i(inst_valid),
        .inst_error_i(inst_error),
        .inst_rdata_i(inst_rdata),
        .data_addr_o(data_addr),
        .data_wdata_o(data_wdata),
        .data_re_o(data_re),
        .data_wstrb_o(data_wstrb),
        .data_cacheable_o(data_cacheable),
        .data_req_tag_o(data_req_tag),
        .data_invalidate_o(data_invalidate),
        .data_writeback_o(data_writeback),
        .data_flush_o(data_flush),
        .data_rdata_i(data_rdata),
        .data_accept_i(data_accept),
        .data_ack_i(data_ack),
        .data_error_i(data_error),
        .data_resp_tag_i(data_resp_tag)
    );
    triha_cache_subsystem #(.ICACHE_ENABLE(CACHE_ENABLE), .DCACHE_ENABLE(CACHE_ENABLE)) u_cache (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .inst_req_i(inst_req),
        .inst_flush_i(inst_flush),
        .inst_invalidate_i(inst_invalidate),
        .inst_addr_i(inst_addr),
        .inst_accept_o(inst_accept),
        .inst_valid_o(inst_valid),
        .inst_error_o(inst_error),
        .inst_rdata_o(inst_rdata),
        .data_addr_i(data_addr),
        .data_wdata_i(data_wdata),
        .data_re_i(data_re),
        .data_wstrb_i(data_wstrb),
        .data_cacheable_i(data_cacheable),
        .data_req_tag_i(data_req_tag),
        .data_invalidate_i(data_invalidate),
        .data_writeback_i(data_writeback),
        .data_flush_i(data_flush),
        .data_rdata_o(data_rdata),
        .data_accept_o(data_accept),
        .data_ack_o(data_ack),
        .data_error_o(data_error),
        .data_resp_tag_o(data_resp_tag),
        .protocol_fault_o(protocol_fault_o),
        .axi_awvalid_o(axi_awvalid_o),
        .axi_awaddr_o(axi_awaddr_o),
        .axi_awid_o(axi_awid_o),
        .axi_awlen_o(axi_awlen_o),
        .axi_awsize_o(axi_awsize_o),
        .axi_awburst_o(axi_awburst_o),
        .axi_awready_i(axi_awready_i),
        .axi_wvalid_o(axi_wvalid_o),
        .axi_wdata_o(axi_wdata_o),
        .axi_wstrb_o(axi_wstrb_o),
        .axi_wlast_o(axi_wlast_o),
        .axi_wready_i(axi_wready_i),
        .axi_bvalid_i(axi_bvalid_i),
        .axi_bresp_i(axi_bresp_i),
        .axi_bid_i(axi_bid_i),
        .axi_bready_o(axi_bready_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arid_o(axi_arid_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arsize_o(axi_arsize_o),
        .axi_arburst_o(axi_arburst_o),
        .axi_arready_i(axi_arready_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rid_i(axi_rid_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rready_o(axi_rready_o)
    );
endmodule
