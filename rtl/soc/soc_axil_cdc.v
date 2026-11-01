`timescale 1ns/1ps
`default_nettype none
// AXI-Lite channel ordering is preserved across the compute/Video clocks.
// One coordinated reset covers both endpoints; online/fault never clears FIFOs.
module soc_axil_cdc (
    input wire s_clk_i,m_clk_i,rst_ni,
    input wire [31:0] s_axi_awaddr_i,
    input wire [2:0] s_axi_awprot_i,
    input wire s_axi_awvalid_i,
    output wire s_axi_awready_o,
    input wire [31:0] s_axi_wdata_i,
    input wire [3:0] s_axi_wstrb_i,
    input wire s_axi_wvalid_i,
    output wire s_axi_wready_o,
    output wire [1:0] s_axi_bresp_o,
    output wire s_axi_bvalid_o,
    input wire s_axi_bready_i,
    input wire [31:0] s_axi_araddr_i,
    input wire [2:0] s_axi_arprot_i,
    input wire s_axi_arvalid_i,
    output wire s_axi_arready_o,
    output wire [31:0] s_axi_rdata_o,
    output wire [1:0] s_axi_rresp_o,
    output wire s_axi_rvalid_o,
    input wire s_axi_rready_i,
    output wire [31:0] m_axi_awaddr_o,
    output wire [2:0] m_axi_awprot_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [31:0] m_axi_wdata_o,
    output wire [3:0] m_axi_wstrb_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [2:0] m_axi_arprot_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire [31:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o
);
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [1:0] s_release,m_release;
    always @(posedge s_clk_i or negedge rst_ni)
        if(!rst_ni)s_release<=0;else s_release<={s_release[0],1'b1};
    always @(posedge m_clk_i or negedge rst_ni)
        if(!rst_ni)m_release<=0;else m_release<={m_release[0],1'b1};
    video_async_fifo #(.DATA_WIDTH(35),.ADDR_WIDTH(2)) u_aw (
        .wr_clk(s_clk_i),.wr_reset_n(s_release[1]),.wr_valid(s_axi_awvalid_i),.wr_ready(s_axi_awready_o),
        .wr_data({s_axi_awaddr_i,s_axi_awprot_i}),.wr_occupancy(),
        .rd_clk(m_clk_i),.rd_reset_n(m_release[1]),.rd_valid(m_axi_awvalid_o),.rd_ready(m_axi_awready_i),
        .rd_data({m_axi_awaddr_o,m_axi_awprot_o}));
    video_async_fifo #(.DATA_WIDTH(36),.ADDR_WIDTH(2)) u_w (
        .wr_clk(s_clk_i),.wr_reset_n(s_release[1]),.wr_valid(s_axi_wvalid_i),.wr_ready(s_axi_wready_o),
        .wr_data({s_axi_wdata_i,s_axi_wstrb_i}),.wr_occupancy(),
        .rd_clk(m_clk_i),.rd_reset_n(m_release[1]),.rd_valid(m_axi_wvalid_o),.rd_ready(m_axi_wready_i),
        .rd_data({m_axi_wdata_o,m_axi_wstrb_o}));
    video_async_fifo #(.DATA_WIDTH(2),.ADDR_WIDTH(2)) u_b (
        .wr_clk(m_clk_i),.wr_reset_n(m_release[1]),.wr_valid(m_axi_bvalid_i),.wr_ready(m_axi_bready_o),
        .wr_data(m_axi_bresp_i),.wr_occupancy(),
        .rd_clk(s_clk_i),.rd_reset_n(s_release[1]),.rd_valid(s_axi_bvalid_o),.rd_ready(s_axi_bready_i),.rd_data(s_axi_bresp_o));
    video_async_fifo #(.DATA_WIDTH(35),.ADDR_WIDTH(2)) u_ar (
        .wr_clk(s_clk_i),.wr_reset_n(s_release[1]),.wr_valid(s_axi_arvalid_i),.wr_ready(s_axi_arready_o),
        .wr_data({s_axi_araddr_i,s_axi_arprot_i}),.wr_occupancy(),
        .rd_clk(m_clk_i),.rd_reset_n(m_release[1]),.rd_valid(m_axi_arvalid_o),.rd_ready(m_axi_arready_i),
        .rd_data({m_axi_araddr_o,m_axi_arprot_o}));
    video_async_fifo #(.DATA_WIDTH(34),.ADDR_WIDTH(2)) u_r (
        .wr_clk(m_clk_i),.wr_reset_n(m_release[1]),.wr_valid(m_axi_rvalid_i),.wr_ready(m_axi_rready_o),
        .wr_data({m_axi_rdata_i,m_axi_rresp_i}),.wr_occupancy(),
        .rd_clk(s_clk_i),.rd_reset_n(s_release[1]),.rd_valid(s_axi_rvalid_o),.rd_ready(s_axi_rready_i),
        .rd_data({s_axi_rdata_o,s_axi_rresp_o}));
endmodule
`default_nettype wire
