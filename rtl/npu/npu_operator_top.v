`timescale 1ns/1ps
// Same-clock functional operator endpoint. CDC/fabric are external.
module npu_operator_top (
    input wire clk_i,
    input wire rst_ni,
    input wire [31:0] s_axi_awaddr_i,
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
    input wire s_axi_arvalid_i,
    output wire s_axi_arready_o,
    output wire [31:0] s_axi_rdata_o,
    output wire [1:0] s_axi_rresp_o,
    output wire s_axi_rvalid_o,
    input wire s_axi_rready_i,
    output wire irq_o,
    output wire fault_o,
    output wire [3:0] m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [7:0] m_axi_arlen_o,
    output wire [2:0] m_axi_arsize_o,
    output wire [1:0] m_axi_arburst_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire [3:0] m_axi_rid_i,
    input wire [127:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,
    output wire [3:0] m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [7:0] m_axi_awlen_o,
    output wire [2:0] m_axi_awsize_o,
    output wire [1:0] m_axi_awburst_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [127:0] m_axi_wdata_o,
    output wire [15:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire [3:0] m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o
);
    wire start;
    wire engine_busy;
    wire engine_done;
    wire engine_error;
    wire [7:0] engine_error_code;
    wire [31:0] engine_total_cycles;
    wire [31:0] engine_compute_cycles;
    wire [31:0] engine_dma_wait_cycles;
    wire [31:0] frame_id;
    wire [31:0] generation;
    wire [31:0] op_tag;
    wire [31:0] cfg_input_base;
    wire [31:0] cfg_weight_base;
    wire [31:0] cfg_bias_base;
    wire [31:0] cfg_requant_base;
    wire [31:0] cfg_output_base;
    wire [15:0] cfg_input_width;
    wire [15:0] cfg_input_height;
    wire [15:0] cfg_output_width;
    wire [15:0] cfg_output_height;
    wire [15:0] cfg_input_channels;
    wire [15:0] cfg_output_channels;
    wire [1:0] cfg_kernel;
    wire [1:0] cfg_stride;
    wire [1:0] cfg_padding;
    wire cfg_depthwise;
    wire cfg_input_signed;
    wire [1:0] cfg_output_format;
    wire mem_req_valid;
    wire mem_req_write;
    wire [31:0] mem_req_addr;
    wire [127:0] mem_req_wdata;
    wire [15:0] mem_req_wstrb;
    wire mem_req_ready;
    wire mem_rsp_valid;
    wire [127:0] mem_rsp_rdata;
    wire mem_rsp_error;
    npu_operator_mmio u_mmio (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axi_awaddr_i(s_axi_awaddr_i),
        .s_axi_awvalid_i(s_axi_awvalid_i),
        .s_axi_awready_o(s_axi_awready_o),
        .s_axi_wdata_i(s_axi_wdata_i),
        .s_axi_wstrb_i(s_axi_wstrb_i),
        .s_axi_wvalid_i(s_axi_wvalid_i),
        .s_axi_wready_o(s_axi_wready_o),
        .s_axi_bresp_o(s_axi_bresp_o),
        .s_axi_bvalid_o(s_axi_bvalid_o),
        .s_axi_bready_i(s_axi_bready_i),
        .s_axi_araddr_i(s_axi_araddr_i),
        .s_axi_arvalid_i(s_axi_arvalid_i),
        .s_axi_arready_o(s_axi_arready_o),
        .s_axi_rdata_o(s_axi_rdata_o),
        .s_axi_rresp_o(s_axi_rresp_o),
        .s_axi_rvalid_o(s_axi_rvalid_o),
        .s_axi_rready_i(s_axi_rready_i),
        .engine_busy_i(engine_busy),
        .engine_done_i(engine_done),
        .engine_error_i(engine_error),
        .engine_error_code_i(engine_error_code),
        .engine_total_cycles_i(engine_total_cycles),
        .engine_compute_cycles_i(engine_compute_cycles),
        .engine_dma_wait_cycles_i(engine_dma_wait_cycles),
        .platform_fault_i(fault_o),
        .start_o(start),
        .irq_o(irq_o),
        .frame_id_o(frame_id),
        .generation_o(generation),
        .op_tag_o(op_tag),
        .cfg_input_base_o(cfg_input_base),
        .cfg_weight_base_o(cfg_weight_base),
        .cfg_bias_base_o(cfg_bias_base),
        .cfg_requant_base_o(cfg_requant_base),
        .cfg_output_base_o(cfg_output_base),
        .cfg_input_width_o(cfg_input_width),
        .cfg_input_height_o(cfg_input_height),
        .cfg_output_width_o(cfg_output_width),
        .cfg_output_height_o(cfg_output_height),
        .cfg_input_channels_o(cfg_input_channels),
        .cfg_output_channels_o(cfg_output_channels),
        .cfg_kernel_o(cfg_kernel),
        .cfg_stride_o(cfg_stride),
        .cfg_padding_o(cfg_padding),
        .cfg_depthwise_o(cfg_depthwise),
        .cfg_input_signed_o(cfg_input_signed),
        .cfg_output_format_o(cfg_output_format)
    );
    npu_scalar_conv u_compute (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .start_i(start),
        .cfg_input_base_i(cfg_input_base),
        .cfg_weight_base_i(cfg_weight_base),
        .cfg_bias_base_i(cfg_bias_base),
        .cfg_requant_base_i(cfg_requant_base),
        .cfg_output_base_i(cfg_output_base),
        .cfg_input_width_i(cfg_input_width),
        .cfg_input_height_i(cfg_input_height),
        .cfg_output_width_i(cfg_output_width),
        .cfg_output_height_i(cfg_output_height),
        .cfg_input_channels_i(cfg_input_channels),
        .cfg_output_channels_i(cfg_output_channels),
        .cfg_kernel_i(cfg_kernel),
        .cfg_stride_i(cfg_stride),
        .cfg_padding_i(cfg_padding),
        .cfg_depthwise_i(cfg_depthwise),
        .cfg_input_signed_i(cfg_input_signed),
        .cfg_output_format_i(cfg_output_format),
        .busy_o(engine_busy),
        .done_o(engine_done),
        .error_o(engine_error),
        .error_code_o(engine_error_code),
        .total_cycles_o(engine_total_cycles),
        .compute_cycles_o(engine_compute_cycles),
        .dma_wait_cycles_o(engine_dma_wait_cycles),
        .mem_req_valid_o(mem_req_valid),
        .mem_req_write_o(mem_req_write),
        .mem_req_addr_o(mem_req_addr),
        .mem_req_wdata_o(mem_req_wdata),
        .mem_req_wstrb_o(mem_req_wstrb),
        .mem_req_ready_i(mem_req_ready),
        .mem_rsp_valid_i(mem_rsp_valid),
        .mem_rsp_rdata_i(mem_rsp_rdata),
        .mem_rsp_error_i(mem_rsp_error)
    );
    npu_axi128_single u_dma (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_valid_i(mem_req_valid),
        .req_write_i(mem_req_write),
        .req_addr_i(mem_req_addr),
        .req_wdata_i(mem_req_wdata),
        .req_wstrb_i(mem_req_wstrb),
        .req_ready_o(mem_req_ready),
        .rsp_valid_o(mem_rsp_valid),
        .rsp_rdata_o(mem_rsp_rdata),
        .rsp_error_o(mem_rsp_error),
        .fault_o(fault_o),
        .m_axi_arid_o(m_axi_arid_o),
        .m_axi_araddr_o(m_axi_araddr_o),
        .m_axi_arlen_o(m_axi_arlen_o),
        .m_axi_arsize_o(m_axi_arsize_o),
        .m_axi_arburst_o(m_axi_arburst_o),
        .m_axi_arvalid_o(m_axi_arvalid_o),
        .m_axi_arready_i(m_axi_arready_i),
        .m_axi_rid_i(m_axi_rid_i),
        .m_axi_rdata_i(m_axi_rdata_i),
        .m_axi_rresp_i(m_axi_rresp_i),
        .m_axi_rlast_i(m_axi_rlast_i),
        .m_axi_rvalid_i(m_axi_rvalid_i),
        .m_axi_rready_o(m_axi_rready_o),
        .m_axi_awid_o(m_axi_awid_o),
        .m_axi_awaddr_o(m_axi_awaddr_o),
        .m_axi_awlen_o(m_axi_awlen_o),
        .m_axi_awsize_o(m_axi_awsize_o),
        .m_axi_awburst_o(m_axi_awburst_o),
        .m_axi_awvalid_o(m_axi_awvalid_o),
        .m_axi_awready_i(m_axi_awready_i),
        .m_axi_wdata_o(m_axi_wdata_o),
        .m_axi_wstrb_o(m_axi_wstrb_o),
        .m_axi_wlast_o(m_axi_wlast_o),
        .m_axi_wvalid_o(m_axi_wvalid_o),
        .m_axi_wready_i(m_axi_wready_i),
        .m_axi_bid_i(m_axi_bid_i),
        .m_axi_bresp_i(m_axi_bresp_i),
        .m_axi_bvalid_i(m_axi_bvalid_i),
        .m_axi_bready_o(m_axi_bready_o)
    );
endmodule
