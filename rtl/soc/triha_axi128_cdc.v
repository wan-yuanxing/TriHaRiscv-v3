/* TriHa AXI128 clock boundary. Five independent elastic asynchronous FIFOs.
 * A single coordinated reset starts a new epoch in both clock domains.
 * DDR ready/fault are observations only: accepted channel payloads and VALID
 * are never cancelled by online/fault changes. The enclosing CPU gates new work.
 * Pinned synchronous-read Gray-pointer FIFO is instantiated without modification.
 */
`default_nettype none
module triha_axi128_cdc (
    input wire cpu_clk_i,
    input wire ddr_clk_i,
    input wire rst_ni,
    output wire cpu_rst_no,
    output wire ddr_rst_no,
    input wire ddr_ready_i,
    input wire ddr_fault_i,
    output wire cpu_ddr_ready_o,
    output wire cpu_ddr_fault_o,
    input  wire s_awvalid_i,
    input  wire [31:0] s_awaddr_i,
    input  wire [3:0] s_awid_i,
    input  wire [7:0] s_awlen_i,
    input  wire [2:0] s_awsize_i,
    input  wire [1:0] s_awburst_i,
    output wire s_awready_o,
    output wire m_awvalid_o,
    output wire [31:0] m_awaddr_o,
    output wire [3:0] m_awid_o,
    output wire [7:0] m_awlen_o,
    output wire [2:0] m_awsize_o,
    output wire [1:0] m_awburst_o,
    input  wire m_awready_i,
    input  wire s_wvalid_i,
    input  wire [127:0] s_wdata_i,
    input  wire [15:0] s_wstrb_i,
    input  wire s_wlast_i,
    output wire s_wready_o,
    output wire m_wvalid_o,
    output wire [127:0] m_wdata_o,
    output wire [15:0] m_wstrb_o,
    output wire m_wlast_o,
    input  wire m_wready_i,
    output wire s_bvalid_o,
    output wire [3:0] s_bid_o,
    output wire [1:0] s_bresp_o,
    input  wire s_bready_i,
    input  wire m_bvalid_i,
    input  wire [3:0] m_bid_i,
    input  wire [1:0] m_bresp_i,
    output wire m_bready_o,
    input  wire s_arvalid_i,
    input  wire [31:0] s_araddr_i,
    input  wire [3:0] s_arid_i,
    input  wire [7:0] s_arlen_i,
    input  wire [2:0] s_arsize_i,
    input  wire [1:0] s_arburst_i,
    output wire s_arready_o,
    output wire m_arvalid_o,
    output wire [31:0] m_araddr_o,
    output wire [3:0] m_arid_o,
    output wire [7:0] m_arlen_o,
    output wire [2:0] m_arsize_o,
    output wire [1:0] m_arburst_o,
    input  wire m_arready_i,
    output wire s_rvalid_o,
    output wire [127:0] s_rdata_o,
    output wire [3:0] s_rid_o,
    output wire [1:0] s_rresp_o,
    output wire s_rlast_o,
    input  wire s_rready_i,
    input  wire m_rvalid_i,
    input  wire [127:0] m_rdata_i,
    input  wire [3:0] m_rid_i,
    input  wire [1:0] m_rresp_i,
    input  wire m_rlast_i,
    output wire m_rready_o
);
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [1:0] cpu_release_q, ddr_release_q;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg ready_meta_q, ready_sync_q;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg fault_meta_q, fault_sync_q;
    always @(posedge cpu_clk_i or negedge rst_ni) begin
        if (!rst_ni) cpu_release_q <= 0;
        else cpu_release_q <= {cpu_release_q[0], 1'b1};
    end
    always @(posedge ddr_clk_i or negedge rst_ni) begin
        if (!rst_ni) ddr_release_q <= 0;
        else ddr_release_q <= {ddr_release_q[0], 1'b1};
    end
    assign cpu_rst_no = cpu_release_q[1];
    assign ddr_rst_no = ddr_release_q[1];
    always @(posedge cpu_clk_i or negedge cpu_rst_no) begin
        if (!cpu_rst_no) begin
            ready_meta_q <= 0; ready_sync_q <= 0;
            fault_meta_q <= 0; fault_sync_q <= 0;
        end else begin
            ready_meta_q <= ddr_ready_i; ready_sync_q <= ready_meta_q;
            fault_meta_q <= ddr_fault_i; fault_sync_q <= fault_meta_q;
        end
    end
    assign cpu_ddr_ready_o = ready_sync_q && !fault_sync_q;
    assign cpu_ddr_fault_o = fault_sync_q;
    video_async_fifo #(.DATA_WIDTH(49), .ADDR_WIDTH(2)) u_aw_fifo (
        .wr_clk(cpu_clk_i), .wr_reset_n(cpu_rst_no),
        .wr_valid(s_awvalid_i), .wr_data({s_awaddr_i, s_awid_i, s_awlen_i, s_awsize_i, s_awburst_i}),
        .wr_ready(s_awready_o), .wr_occupancy(),
        .rd_clk(ddr_clk_i), .rd_reset_n(ddr_rst_no),
        .rd_valid(m_awvalid_o), .rd_data({m_awaddr_o, m_awid_o, m_awlen_o, m_awsize_o, m_awburst_o}), .rd_ready(m_awready_i)
    );
    video_async_fifo #(.DATA_WIDTH(145), .ADDR_WIDTH(2)) u_w_fifo (
        .wr_clk(cpu_clk_i), .wr_reset_n(cpu_rst_no),
        .wr_valid(s_wvalid_i), .wr_data({s_wdata_i, s_wstrb_i, s_wlast_i}),
        .wr_ready(s_wready_o), .wr_occupancy(),
        .rd_clk(ddr_clk_i), .rd_reset_n(ddr_rst_no),
        .rd_valid(m_wvalid_o), .rd_data({m_wdata_o, m_wstrb_o, m_wlast_o}), .rd_ready(m_wready_i)
    );
    video_async_fifo #(.DATA_WIDTH(6), .ADDR_WIDTH(2)) u_b_fifo (
        .wr_clk(ddr_clk_i), .wr_reset_n(ddr_rst_no),
        .wr_valid(m_bvalid_i), .wr_data({m_bid_i, m_bresp_i}),
        .wr_ready(m_bready_o), .wr_occupancy(),
        .rd_clk(cpu_clk_i), .rd_reset_n(cpu_rst_no),
        .rd_valid(s_bvalid_o), .rd_data({s_bid_o, s_bresp_o}), .rd_ready(s_bready_i)
    );
    video_async_fifo #(.DATA_WIDTH(49), .ADDR_WIDTH(2)) u_ar_fifo (
        .wr_clk(cpu_clk_i), .wr_reset_n(cpu_rst_no),
        .wr_valid(s_arvalid_i), .wr_data({s_araddr_i, s_arid_i, s_arlen_i, s_arsize_i, s_arburst_i}),
        .wr_ready(s_arready_o), .wr_occupancy(),
        .rd_clk(ddr_clk_i), .rd_reset_n(ddr_rst_no),
        .rd_valid(m_arvalid_o), .rd_data({m_araddr_o, m_arid_o, m_arlen_o, m_arsize_o, m_arburst_o}), .rd_ready(m_arready_i)
    );
    video_async_fifo #(.DATA_WIDTH(135), .ADDR_WIDTH(2)) u_r_fifo (
        .wr_clk(ddr_clk_i), .wr_reset_n(ddr_rst_no),
        .wr_valid(m_rvalid_i), .wr_data({m_rdata_i, m_rid_i, m_rresp_i, m_rlast_i}),
        .wr_ready(m_rready_o), .wr_occupancy(),
        .rd_clk(cpu_clk_i), .rd_reset_n(cpu_rst_no),
        .rd_valid(s_rvalid_o), .rd_data({s_rdata_o, s_rid_o, s_rresp_o, s_rlast_o}), .rd_ready(s_rready_i)
    );
endmodule
`default_nettype wire
