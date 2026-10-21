/* TriHa local cached CPU -> asynchronous AXI128 -> exclusive native DDR port.
 * Both clocks must run for normal completion. Only rst_ni starts a new epoch;
 * init/fault never resets a local participant or withdraws owned traffic.
 * The native port has one owner through write/readback verification. This
 * opt-in boundary is not yet the CPU/NPU/Video shared fabric or a board top.
 */
`default_nettype none
module triha_cpu_ddr #(
    parameter ROM_FILE = "rom.hex",
    parameter SRAM_FILE = "sram.hex",
    parameter integer CACHE_ENABLE = 1
) (
    input wire cpu_clk_i,
    input wire ddr_clk_i,
    input wire rst_ni,
    input wire external_irq_i,
    input wire ddr_ready_i,
    input wire ddr_fault_i,
    output wire cpu_ddr_fault_o,
    output wire protocol_fault_o,
    output wire [7:0] bridge_fault_code_o,
    output wire uart_tx_o,
    output wire done_o,
    output wire [7:0] exit_code_o,
    output wire [27:0] h_awaddr_o,
    output wire [3:0] h_awlen_o,
    output wire [3:0] h_awid_o,
    output wire  h_awvalid_o,
    input wire  h_awready_i,
    output wire [255:0] h_wdata_o,
    output wire [31:0] h_wstrb_o,
    input wire  h_wready_i,
    input wire [3:0] h_wid_i,
    input wire  h_wlast_i,
    output wire [27:0] h_araddr_o,
    output wire [3:0] h_arlen_o,
    output wire [3:0] h_arid_o,
    output wire  h_arvalid_o,
    input wire  h_arready_i,
    input wire [255:0] h_rdata_i,
    input wire [3:0] h_rid_i,
    input wire  h_rlast_i,
    input wire  h_rvalid_i
);
    wire cpu_rst_n, ddr_rst_n, cpu_ready_w, cpu_fault_w, bridge_fault_w;
    wire [1:0] bridge_rresp_w;
    wire  cpu_awvalid_w;
    wire [31:0] cpu_awaddr_w;
    wire [3:0] cpu_awid_w;
    wire [7:0] cpu_awlen_w;
    wire [2:0] cpu_awsize_w;
    wire [1:0] cpu_awburst_w;
    wire  cpu_awready_w;
    wire  cpu_wvalid_w;
    wire [127:0] cpu_wdata_w;
    wire [15:0] cpu_wstrb_w;
    wire  cpu_wlast_w;
    wire  cpu_wready_w;
    wire  cpu_bvalid_w;
    wire [1:0] cpu_bresp_w;
    wire [3:0] cpu_bid_w;
    wire  cpu_bready_w;
    wire  cpu_arvalid_w;
    wire [31:0] cpu_araddr_w;
    wire [3:0] cpu_arid_w;
    wire [7:0] cpu_arlen_w;
    wire [2:0] cpu_arsize_w;
    wire [1:0] cpu_arburst_w;
    wire  cpu_arready_w;
    wire  cpu_rvalid_w;
    wire [127:0] cpu_rdata_w;
    wire [1:0] cpu_rresp_w;
    wire [3:0] cpu_rid_w;
    wire  cpu_rlast_w;
    wire  cpu_rready_w;
    wire  ddr_awvalid_w;
    wire [31:0] ddr_awaddr_w;
    wire [3:0] ddr_awid_w;
    wire [7:0] ddr_awlen_w;
    wire [2:0] ddr_awsize_w;
    wire [1:0] ddr_awburst_w;
    wire  ddr_awready_w;
    wire  ddr_wvalid_w;
    wire [127:0] ddr_wdata_w;
    wire [15:0] ddr_wstrb_w;
    wire  ddr_wlast_w;
    wire  ddr_wready_w;
    wire  ddr_bvalid_w;
    wire [1:0] ddr_bresp_w;
    wire [3:0] ddr_bid_w;
    wire  ddr_bready_w;
    wire  ddr_arvalid_w;
    wire [31:0] ddr_araddr_w;
    wire [3:0] ddr_arid_w;
    wire [7:0] ddr_arlen_w;
    wire [2:0] ddr_arsize_w;
    wire [1:0] ddr_arburst_w;
    wire  ddr_arready_w;
    wire  ddr_rvalid_w;
    wire [127:0] ddr_rdata_w;
    wire [1:0] ddr_rresp_w;
    wire [3:0] ddr_rid_w;
    wire  ddr_rlast_w;
    wire  ddr_rready_w;
    assign ddr_rresp_w = bridge_rresp_w;
    triha_cached_soc #(.ROM_FILE(ROM_FILE), .SRAM_FILE(SRAM_FILE), .CACHE_ENABLE(CACHE_ENABLE)) u_soc (
        .clk_i(cpu_clk_i),
        .rst_ni(cpu_rst_n),
        .external_irq_i(external_irq_i),
        .ddr_ready_i(cpu_ready_w),
        .ddr_fault_i(cpu_fault_w),
        .ddr_fault_o(cpu_ddr_fault_o),
        .uart_tx_o(uart_tx_o),
        .done_o(done_o),
        .exit_code_o(exit_code_o),
        .protocol_fault_o(protocol_fault_o),
        .axi_awvalid_o(cpu_awvalid_w),
        .axi_awaddr_o(cpu_awaddr_w),
        .axi_awid_o(cpu_awid_w),
        .axi_awlen_o(cpu_awlen_w),
        .axi_awsize_o(cpu_awsize_w),
        .axi_awburst_o(cpu_awburst_w),
        .axi_awready_i(cpu_awready_w),
        .axi_wvalid_o(cpu_wvalid_w),
        .axi_wdata_o(cpu_wdata_w),
        .axi_wstrb_o(cpu_wstrb_w),
        .axi_wlast_o(cpu_wlast_w),
        .axi_wready_i(cpu_wready_w),
        .axi_bvalid_i(cpu_bvalid_w),
        .axi_bresp_i(cpu_bresp_w),
        .axi_bid_i(cpu_bid_w),
        .axi_bready_o(cpu_bready_w),
        .axi_arvalid_o(cpu_arvalid_w),
        .axi_araddr_o(cpu_araddr_w),
        .axi_arid_o(cpu_arid_w),
        .axi_arlen_o(cpu_arlen_w),
        .axi_arsize_o(cpu_arsize_w),
        .axi_arburst_o(cpu_arburst_w),
        .axi_arready_i(cpu_arready_w),
        .axi_rvalid_i(cpu_rvalid_w),
        .axi_rdata_i(cpu_rdata_w),
        .axi_rresp_i(cpu_rresp_w),
        .axi_rid_i(cpu_rid_w),
        .axi_rlast_i(cpu_rlast_w),
        .axi_rready_o(cpu_rready_w)
    );
    triha_axi128_cdc u_cdc (
        .cpu_clk_i(cpu_clk_i),
        .ddr_clk_i(ddr_clk_i),
        .rst_ni(rst_ni),
        .cpu_rst_no(cpu_rst_n),
        .ddr_rst_no(ddr_rst_n),
        .ddr_ready_i(ddr_ready_i),
        .ddr_fault_i(ddr_fault_i || bridge_fault_w),
        .cpu_ddr_ready_o(cpu_ready_w),
        .cpu_ddr_fault_o(cpu_fault_w),
        .s_awvalid_i(cpu_awvalid_w),
        .s_awaddr_i(cpu_awaddr_w),
        .s_awid_i(cpu_awid_w),
        .s_awlen_i(cpu_awlen_w),
        .s_awsize_i(cpu_awsize_w),
        .s_awburst_i(cpu_awburst_w),
        .s_awready_o(cpu_awready_w),
        .m_awvalid_o(ddr_awvalid_w),
        .m_awaddr_o(ddr_awaddr_w),
        .m_awid_o(ddr_awid_w),
        .m_awlen_o(ddr_awlen_w),
        .m_awsize_o(ddr_awsize_w),
        .m_awburst_o(ddr_awburst_w),
        .m_awready_i(ddr_awready_w),
        .s_wvalid_i(cpu_wvalid_w),
        .s_wdata_i(cpu_wdata_w),
        .s_wstrb_i(cpu_wstrb_w),
        .s_wlast_i(cpu_wlast_w),
        .s_wready_o(cpu_wready_w),
        .m_wvalid_o(ddr_wvalid_w),
        .m_wdata_o(ddr_wdata_w),
        .m_wstrb_o(ddr_wstrb_w),
        .m_wlast_o(ddr_wlast_w),
        .m_wready_i(ddr_wready_w),
        .s_bvalid_o(cpu_bvalid_w),
        .s_bid_o(cpu_bid_w),
        .s_bresp_o(cpu_bresp_w),
        .s_bready_i(cpu_bready_w),
        .m_bvalid_i(ddr_bvalid_w),
        .m_bid_i(ddr_bid_w),
        .m_bresp_i(ddr_bresp_w),
        .m_bready_o(ddr_bready_w),
        .s_arvalid_i(cpu_arvalid_w),
        .s_araddr_i(cpu_araddr_w),
        .s_arid_i(cpu_arid_w),
        .s_arlen_i(cpu_arlen_w),
        .s_arsize_i(cpu_arsize_w),
        .s_arburst_i(cpu_arburst_w),
        .s_arready_o(cpu_arready_w),
        .m_arvalid_o(ddr_arvalid_w),
        .m_araddr_o(ddr_araddr_w),
        .m_arid_o(ddr_arid_w),
        .m_arlen_o(ddr_arlen_w),
        .m_arsize_o(ddr_arsize_w),
        .m_arburst_o(ddr_arburst_w),
        .m_arready_i(ddr_arready_w),
        .s_rvalid_o(cpu_rvalid_w),
        .s_rdata_o(cpu_rdata_w),
        .s_rid_o(cpu_rid_w),
        .s_rresp_o(cpu_rresp_w),
        .s_rlast_o(cpu_rlast_w),
        .s_rready_i(cpu_rready_w),
        .m_rvalid_i(ddr_rvalid_w),
        .m_rdata_i(ddr_rdata_w),
        .m_rid_i(ddr_rid_w),
        .m_rresp_i(ddr_rresp_w),
        .m_rlast_i(ddr_rlast_w),
        .m_rready_o(ddr_rready_w)
    );
    axi128_hmic256 u_bridge (
        .clk(ddr_clk_i),
        .rst_n(ddr_rst_n),
        .init_done(ddr_ready_i),
        .fault(bridge_fault_w),
        .fault_code(bridge_fault_code_o),
        .awvalid(ddr_awvalid_w),
        .awaddr(ddr_awaddr_w),
        .awid(ddr_awid_w),
        .awlen(ddr_awlen_w),
        .awsize(ddr_awsize_w),
        .awburst(ddr_awburst_w),
        .awready(ddr_awready_w),
        .wvalid(ddr_wvalid_w),
        .wdata(ddr_wdata_w),
        .wstrb(ddr_wstrb_w),
        .wlast(ddr_wlast_w),
        .wready(ddr_wready_w),
        .bvalid(ddr_bvalid_w),
        .bresp(ddr_bresp_w),
        .bid(ddr_bid_w),
        .bready(ddr_bready_w),
        .arvalid(ddr_arvalid_w),
        .araddr(ddr_araddr_w),
        .arid(ddr_arid_w),
        .arlen(ddr_arlen_w),
        .arsize(ddr_arsize_w),
        .arburst(ddr_arburst_w),
        .arready(ddr_arready_w),
        .rvalid(ddr_rvalid_w),
        .rdata(ddr_rdata_w),
        .rresp(bridge_rresp_w),
        .rid(ddr_rid_w),
        .rlast(ddr_rlast_w),
        .rready(ddr_rready_w),
        .h_awaddr(h_awaddr_o),
        .h_awlen(h_awlen_o),
        .h_awid(h_awid_o),
        .h_awvalid(h_awvalid_o),
        .h_awready(h_awready_i),
        .h_wdata(h_wdata_o),
        .h_wstrb(h_wstrb_o),
        .h_wready(h_wready_i),
        .h_wid(h_wid_i),
        .h_wlast(h_wlast_i),
        .h_araddr(h_araddr_o),
        .h_arlen(h_arlen_o),
        .h_arid(h_arid_o),
        .h_arvalid(h_arvalid_o),
        .h_arready(h_arready_i),
        .h_rdata(h_rdata_i),
        .h_rid(h_rid_i),
        .h_rlast(h_rlast_i),
        .h_rvalid(h_rvalid_i)
    );
endmodule
`default_nettype wire
