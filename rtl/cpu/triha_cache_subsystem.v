/* TriHa paired I/D Cache and shared 128-bit DDR transport.
 * Instruction input is the CPU-private DDR path; local/uncached routing
 * remains at the enclosing CPU system boundary. No board acceptance implied.
 */
module triha_cache_subsystem #(
    parameter integer ICACHE_ENABLE = 1,
    parameter integer DCACHE_ENABLE = 1
) (
    input wire clk_i,
    input wire rst_ni,
    input wire inst_req_i,
    input wire inst_flush_i,
    input wire inst_invalidate_i,
    input wire [31:0] inst_addr_i,
    output wire inst_accept_o,
    output wire inst_valid_o,
    output wire inst_error_o,
    output wire [63:0] inst_rdata_o,
    input wire [31:0] data_addr_i,
    input wire [31:0] data_wdata_i,
    input wire data_re_i,
    input wire [3:0] data_wstrb_i,
    input wire data_cacheable_i,
    input wire [10:0] data_req_tag_i,
    input wire data_invalidate_i,
    input wire data_writeback_i,
    input wire data_flush_i,
    output wire [31:0] data_rdata_o,
    output wire data_accept_o,
    output wire data_ack_o,
    output wire data_error_o,
    output wire [10:0] data_resp_tag_o,
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
    wire i_arvalid, i_arready, i_rvalid, i_rready, i_rlast;
    wire [31:0] i_araddr, i_rdata;
    wire [3:0] i_arid, i_rid;
    wire [7:0] i_arlen;
    wire [1:0] i_rresp;
    wire p_rd, p_accept, p_ack, p_error;
    wire [3:0] p_wr;
    wire [7:0] p_len;
    wire [31:0] p_addr, p_wdata, p_rdata;
    wire want_cached_w = ICACHE_ENABLE && inst_addr_i >= 32'h80000000 && inst_addr_i < 32'h82000000;
    reg owner_cached_q;
    reg [2:0] pending_q;
    wire hold_target_w = |pending_q && owner_cached_q != want_cached_w;
    wire c_accept, c_valid, c_error, c_arvalid, c_rready;
    wire [63:0] c_data;
    wire [31:0] c_araddr;
    wire [3:0] c_arid;
    wire [7:0] c_arlen;
    wire u_accept, u_valid, u_error, u_arvalid, u_rready;
    wire [63:0] u_data;
    wire [31:0] u_araddr;
    wire accepted_w = inst_req_i && inst_accept_o;
    assign inst_accept_o = !hold_target_w && (want_cached_w ? c_accept : u_accept);
    assign inst_valid_o = owner_cached_q ? c_valid : u_valid;
    assign inst_error_o = owner_cached_q ? c_error : u_error;
    assign inst_rdata_o = owner_cached_q ? c_data : u_data;
    assign i_arvalid = owner_cached_q ? c_arvalid : u_arvalid;
    assign i_araddr = owner_cached_q ? c_araddr : u_araddr;
    assign i_arid = owner_cached_q ? c_arid : 4'd3;
    assign i_arlen = owner_cached_q ? c_arlen : 8'd1;
    assign i_rready = owner_cached_q ? c_rready : u_rready;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin pending_q <= 0; owner_cached_q <= ICACHE_ENABLE; end
        else begin
            if (accepted_w && !inst_valid_o) pending_q <= pending_q + 1'b1;
            else if (!accepted_w && inst_valid_o) pending_q <= pending_q - 1'b1;
            if (accepted_w) owner_cached_q <= want_cached_w;
        end
    end
    generate if (ICACHE_ENABLE) begin: g_cached_i
    triha_icache #(.AXI_ID(1)) u_icache (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_rd_i(inst_req_i && want_cached_w && !hold_target_w),
        .req_flush_i(inst_flush_i),
        .req_invalidate_i(inst_invalidate_i),
        .req_pc_i(inst_addr_i),
        .axi_awready_i(1'b0),
        .axi_wready_i(1'b0),
        .axi_bvalid_i(1'b0),
        .axi_bresp_i(2'b0),
        .axi_bid_i(4'b0),
        .axi_arready_i(i_arready && owner_cached_q),
        .axi_rvalid_i(i_rvalid && owner_cached_q),
        .axi_rdata_i(i_rdata),
        .axi_rresp_i(i_rresp),
        .axi_rid_i(i_rid),
        .axi_rlast_i(i_rlast),
        .req_accept_o(c_accept),
        .req_valid_o(c_valid),
        .req_error_o(c_error),
        .req_inst_o(c_data),
        .axi_awvalid_o(),
        .axi_awaddr_o(),
        .axi_awid_o(),
        .axi_awlen_o(),
        .axi_awburst_o(),
        .axi_wvalid_o(),
        .axi_wdata_o(),
        .axi_wstrb_o(),
        .axi_wlast_o(),
        .axi_bready_o(),
        .axi_arvalid_o(c_arvalid),
        .axi_araddr_o(c_araddr),
        .axi_arid_o(c_arid),
        .axi_arlen_o(c_arlen),
        .axi_arburst_o(),
        .axi_rready_o(c_rready)
    );
    end else begin: g_no_cached_i
        assign c_accept = 0;
        assign c_valid = 0;
        assign c_error = 0;
        assign c_data = 0;
        assign c_arvalid = 0;
        assign c_araddr = 0;
        assign c_arid = 0;
        assign c_arlen = 0;
        assign c_rready = 0;
    end endgenerate
    triha_ifetch_uncached u_uncached_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .req_rd_i(inst_req_i && !want_cached_w && !hold_target_w),
        .req_pc_i(inst_addr_i), .req_accept_o(u_accept), .req_valid_o(u_valid),
        .req_error_o(u_error), .req_inst_o(u_data), .arvalid_o(u_arvalid), .araddr_o(u_araddr),
        .arready_i(i_arready && !owner_cached_q), .rvalid_i(i_rvalid && !owner_cached_q),
        .rdata_i(i_rdata), .rresp_i(i_rresp), .rlast_i(i_rlast), .rready_o(u_rready)
    );
    triha_dcache #(.CACHE_ENABLE(DCACHE_ENABLE)) u_dcache (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .mem_addr_i(data_addr_i),
        .mem_data_wr_i(data_wdata_i),
        .mem_rd_i(data_re_i),
        .mem_wr_i(data_wstrb_i),
        .mem_cacheable_i(data_cacheable_i),
        .mem_req_tag_i(data_req_tag_i),
        .mem_invalidate_i(data_invalidate_i),
        .mem_writeback_i(data_writeback_i),
        .mem_flush_i(data_flush_i),
        .mem_data_rd_o(data_rdata_o),
        .mem_accept_o(data_accept_o),
        .mem_ack_o(data_ack_o),
        .mem_error_o(data_error_o),
        .mem_resp_tag_o(data_resp_tag_o),
        .outport_accept_i(p_accept),
        .outport_ack_i(p_ack),
        .outport_error_i(p_error),
        .outport_read_data_i(p_rdata),
        .outport_wr_o(p_wr),
        .outport_rd_o(p_rd),
        .outport_len_o(p_len),
        .outport_addr_o(p_addr),
        .outport_write_data_o(p_wdata)
    );
    triha_cpu_cache_axi u_transport (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .i_arvalid_i(i_arvalid),
        .i_araddr_i(i_araddr),
        .i_arid_i(i_arid),
        .i_arlen_i(i_arlen),
        .i_arready_o(i_arready),
        .i_rvalid_o(i_rvalid),
        .i_rdata_o(i_rdata),
        .i_rresp_o(i_rresp),
        .i_rid_o(i_rid),
        .i_rlast_o(i_rlast),
        .i_rready_i(i_rready),
        .d_rd_i(p_rd),
        .d_wr_i(p_wr),
        .d_len_i(p_len),
        .d_addr_i(p_addr),
        .d_wdata_i(p_wdata),
        .d_accept_o(p_accept),
        .d_ack_o(p_ack),
        .d_error_o(p_error),
        .d_rdata_o(p_rdata),
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
