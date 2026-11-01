`timescale 1ns/1ps
`default_nettype none
// Application CPU, frame-level B03 endpoint and one shared compute AXI owner.
// All ports use the actual 100 MHz compute clock. Reset is system-coordinated.
// CPU model writes invalidate the B03 validation cache before any next task.
module triha_compute_system #(
    parameter ROM_FILE="rom.hex", SRAM_FILE="sram.hex",
    parameter integer CACHE_ENABLE=1, MINIMAL_CONTROL_CPU=0,
    parameter integer ENABLE_HARDWARE_POST=1, TRUSTED_MODEL=0, M_LANES=16, QUANTIZER_LANES=2
) (
    input wire clk_i,
    input wire rst_ni,
    input wire healthy_i,
    input wire memory_fault_i,
    input wire model_sealed_i,
    input wire video_irq_i,
    input wire [31:0] epoch_i,
    input wire [31:0] addr_version_i,
    output wire [31:0] video_axi_awaddr_o,
    output wire [2:0] video_axi_awprot_o,
    output wire video_axi_awvalid_o,
    input wire video_axi_awready_i,
    output wire [31:0] video_axi_wdata_o,
    output wire [3:0] video_axi_wstrb_o,
    output wire video_axi_wvalid_o,
    input wire video_axi_wready_i,
    input wire [1:0] video_axi_bresp_i,
    input wire video_axi_bvalid_i,
    output wire video_axi_bready_o,
    output wire [31:0] video_axi_araddr_o,
    output wire [2:0] video_axi_arprot_o,
    output wire video_axi_arvalid_o,
    input wire video_axi_arready_i,
    input wire [31:0] video_axi_rdata_i,
    input wire [1:0] video_axi_rresp_i,
    input wire video_axi_rvalid_i,
    output wire video_axi_rready_o,
    output wire m_awvalid_o,
    input wire m_awready_i,
    output wire [31:0] m_awaddr_o,
    output wire [3:0] m_awid_o,
    output wire [7:0] m_awlen_o,
    output wire [2:0] m_awsize_o,
    output wire [1:0] m_awburst_o,
    output wire m_wvalid_o,
    input wire m_wready_i,
    output wire [127:0] m_wdata_o,
    output wire [15:0] m_wstrb_o,
    output wire m_wlast_o,
    input wire m_bvalid_i,
    output wire m_bready_o,
    input wire [3:0] m_bid_i,
    input wire [1:0] m_bresp_i,
    output wire m_arvalid_o,
    input wire m_arready_i,
    output wire [31:0] m_araddr_o,
    output wire [3:0] m_arid_o,
    output wire [7:0] m_arlen_o,
    output wire [2:0] m_arsize_o,
    output wire [1:0] m_arburst_o,
    input wire m_rvalid_i,
    output wire m_rready_o,
    input wire [127:0] m_rdata_i,
    input wire [3:0] m_rid_i,
    input wire [1:0] m_rresp_i,
    input wire m_rlast_i,
    output wire fault_o,
    output wire npu_irq_o,
    output wire npu_idle_o,
    output wire compute_idle_o,
    output wire [7:0] npu_stage_o,
    output wire [7:0] npu_op_o
);
    wire cpu_fault;
    wire cpu_protocol_fault;
    wire [31:0] nl_awaddr;
    wire [2:0] nl_awprot;
    wire nl_awvalid;
    wire nl_awready;
    wire [31:0] nl_wdata;
    wire [3:0] nl_wstrb;
    wire nl_wvalid;
    wire nl_wready;
    wire [1:0] nl_bresp;
    wire nl_bvalid;
    wire nl_bready;
    wire [31:0] nl_araddr;
    wire [2:0] nl_arprot;
    wire nl_arvalid;
    wire nl_arready;
    wire [31:0] nl_rdata;
    wire [1:0] nl_rresp;
    wire nl_rvalid;
    wire nl_rready;
    wire cpu_awvalid;
    wire [31:0] cpu_awaddr;
    wire [3:0] cpu_awid;
    wire [7:0] cpu_awlen;
    wire [2:0] cpu_awsize;
    wire [1:0] cpu_awburst;
    wire cpu_awready;
    wire cpu_wvalid;
    wire [127:0] cpu_wdata;
    wire [15:0] cpu_wstrb;
    wire cpu_wlast;
    wire cpu_wready;
    wire cpu_bvalid;
    wire [1:0] cpu_bresp;
    wire [3:0] cpu_bid;
    wire cpu_bready;
    wire cpu_arvalid;
    wire [31:0] cpu_araddr;
    wire [3:0] cpu_arid;
    wire [7:0] cpu_arlen;
    wire [2:0] cpu_arsize;
    wire [1:0] cpu_arburst;
    wire cpu_arready;
    wire cpu_rvalid;
    wire [127:0] cpu_rdata;
    wire [1:0] cpu_rresp;
    wire [3:0] cpu_rid;
    wire cpu_rlast;
    wire cpu_rready;
    wire fabric_fault;
    wire npu_fault;
    wire svc_abort;
    wire svc_cmd_valid;
    wire svc_cmd_ready;
    wire svc_cmd_write;
    wire [31:0] svc_cmd_offset;
    wire [31:0] svc_cmd_id;
    wire [31:0] svc_cmd_epoch;
    wire [4:0] svc_cmd_beats;
    wire [2:0] svc_cmd_client;
    wire svc_write_valid;
    wire svc_write_ready;
    wire [255:0] svc_write_data;
    wire [31:0] svc_write_strb;
    wire svc_write_last;
    wire svc_read_valid;
    wire svc_read_ready;
    wire [255:0] svc_read_data;
    wire svc_read_last;
    wire svc_done_valid;
    wire svc_done_ready;
    wire [3:0] svc_done_status;
    wire [31:0] svc_done_id;
    wire [31:0] svc_done_epoch;
    wire [2:0] svc_done_client;
    wire adapter_idle;
    wire adapter_fault;
    wire [3:0] adapter_fault_code;
    wire npu_awvalid;
    wire npu_awready;
    wire [31:0] npu_awaddr;
    wire [3:0] npu_awid;
    wire [7:0] npu_awlen;
    wire [2:0] npu_awsize;
    wire [1:0] npu_awburst;
    wire npu_wvalid;
    wire npu_wready;
    wire [127:0] npu_wdata;
    wire [15:0] npu_wstrb;
    wire npu_wlast;
    wire npu_bvalid;
    wire npu_bready;
    wire [3:0] npu_bid;
    wire [1:0] npu_bresp;
    wire npu_arvalid;
    wire npu_arready;
    wire [31:0] npu_araddr;
    wire [3:0] npu_arid;
    wire [7:0] npu_arlen;
    wire [2:0] npu_arsize;
    wire [1:0] npu_arburst;
    wire npu_rvalid;
    wire npu_rready;
    wire [127:0] npu_rdata;
    wire [3:0] npu_rid;
    wire [1:0] npu_rresp;
    wire npu_rlast;
    wire arb_fault;
    wire [7:0] arb_fault_code;
    assign fabric_fault = cpu_fault || cpu_protocol_fault || adapter_fault || arb_fault;
    assign fault_o = fabric_fault || npu_fault;
    triha_application_cpu #(.ROM_FILE(ROM_FILE),.SRAM_FILE(SRAM_FILE),.CACHE_ENABLE(CACHE_ENABLE),.MINIMAL_CONTROL_CPU(MINIMAL_CONTROL_CPU)) u_cpu (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .external_irq_i(video_irq_i || npu_irq_o),
        .ddr_ready_i(healthy_i && !fault_o),
        .ddr_fault_i(memory_fault_i || adapter_fault || arb_fault || npu_fault),
        .ddr_fault_o(cpu_fault),
        .protocol_fault_o(cpu_protocol_fault),
        .npu_axi_awaddr_o(nl_awaddr),
        .npu_axi_awprot_o(nl_awprot),
        .npu_axi_awvalid_o(nl_awvalid),
        .npu_axi_awready_i(nl_awready),
        .npu_axi_wdata_o(nl_wdata),
        .npu_axi_wstrb_o(nl_wstrb),
        .npu_axi_wvalid_o(nl_wvalid),
        .npu_axi_wready_i(nl_wready),
        .npu_axi_bresp_i(nl_bresp),
        .npu_axi_bvalid_i(nl_bvalid),
        .npu_axi_bready_o(nl_bready),
        .npu_axi_araddr_o(nl_araddr),
        .npu_axi_arprot_o(nl_arprot),
        .npu_axi_arvalid_o(nl_arvalid),
        .npu_axi_arready_i(nl_arready),
        .npu_axi_rdata_i(nl_rdata),
        .npu_axi_rresp_i(nl_rresp),
        .npu_axi_rvalid_i(nl_rvalid),
        .npu_axi_rready_o(nl_rready),
        .video_axi_awaddr_o(video_axi_awaddr_o),
        .video_axi_awprot_o(video_axi_awprot_o),
        .video_axi_awvalid_o(video_axi_awvalid_o),
        .video_axi_awready_i(video_axi_awready_i),
        .video_axi_wdata_o(video_axi_wdata_o),
        .video_axi_wstrb_o(video_axi_wstrb_o),
        .video_axi_wvalid_o(video_axi_wvalid_o),
        .video_axi_wready_i(video_axi_wready_i),
        .video_axi_bresp_i(video_axi_bresp_i),
        .video_axi_bvalid_i(video_axi_bvalid_i),
        .video_axi_bready_o(video_axi_bready_o),
        .video_axi_araddr_o(video_axi_araddr_o),
        .video_axi_arprot_o(video_axi_arprot_o),
        .video_axi_arvalid_o(video_axi_arvalid_o),
        .video_axi_arready_i(video_axi_arready_i),
        .video_axi_rdata_i(video_axi_rdata_i),
        .video_axi_rresp_i(video_axi_rresp_i),
        .video_axi_rvalid_i(video_axi_rvalid_i),
        .video_axi_rready_o(video_axi_rready_o),
        .axi_awvalid_o(cpu_awvalid),
        .axi_awaddr_o(cpu_awaddr),
        .axi_awid_o(cpu_awid),
        .axi_awlen_o(cpu_awlen),
        .axi_awsize_o(cpu_awsize),
        .axi_awburst_o(cpu_awburst),
        .axi_awready_i(cpu_awready),
        .axi_wvalid_o(cpu_wvalid),
        .axi_wdata_o(cpu_wdata),
        .axi_wstrb_o(cpu_wstrb),
        .axi_wlast_o(cpu_wlast),
        .axi_wready_i(cpu_wready),
        .axi_bvalid_i(cpu_bvalid),
        .axi_bresp_i(cpu_bresp),
        .axi_bid_i(cpu_bid),
        .axi_bready_o(cpu_bready),
        .axi_arvalid_o(cpu_arvalid),
        .axi_araddr_o(cpu_araddr),
        .axi_arid_o(cpu_arid),
        .axi_arlen_o(cpu_arlen),
        .axi_arsize_o(cpu_arsize),
        .axi_arburst_o(cpu_arburst),
        .axi_arready_i(cpu_arready),
        .axi_rvalid_i(cpu_rvalid),
        .axi_rdata_i(cpu_rdata),
        .axi_rresp_i(cpu_rresp),
        .axi_rid_i(cpu_rid),
        .axi_rlast_i(cpu_rlast),
        .axi_rready_o(cpu_rready)
    );
    // The local AXI adapter registers every read/completion response and cannot
    // respond in its command-accept cycle. Avoid that unused ready-to-read bypass.
    npu_frame_top #(.ALLOW_COMMAND_CYCLE_RESPONSE(0),.ENABLE_HARDWARE_POST(ENABLE_HARDWARE_POST),.TRUSTED_MODEL(TRUSTED_MODEL),.M_LANES(M_LANES),.QUANTIZER_LANES(QUANTIZER_LANES)) u_npu (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .healthy_i(healthy_i && !fabric_fault),
        .memory_fault_i(memory_fault_i || fabric_fault),
        .model_sealed_i(model_sealed_i),
        .cancel_i(fabric_fault),
        .host_write_valid_i(cpu_awvalid && cpu_awready),
        .publish_permission_i(adapter_idle && healthy_i && !fabric_fault),
        .epoch_i(epoch_i),
        .addr_version_i(addr_version_i),
        .host_write_offset_i((cpu_awaddr-32'h80000000) & 32'hffffffe0),
        .host_write_beats_i(5'd1),
        .irq_o(npu_irq_o),
        .fault_o(npu_fault),
        .port_idle_o(npu_idle_o),
        .abort_req_o(svc_abort),
        .debug_stage_o(npu_stage_o),
        .debug_op_o(npu_op_o),
        .s_axi_awaddr_i(nl_awaddr),
        .s_axi_awvalid_i(nl_awvalid),
        .s_axi_awready_o(nl_awready),
        .s_axi_wdata_i(nl_wdata),
        .s_axi_wstrb_i(nl_wstrb),
        .s_axi_wvalid_i(nl_wvalid),
        .s_axi_wready_o(nl_wready),
        .s_axi_bresp_o(nl_bresp),
        .s_axi_bvalid_o(nl_bvalid),
        .s_axi_bready_i(nl_bready),
        .s_axi_araddr_i(nl_araddr),
        .s_axi_arvalid_i(nl_arvalid),
        .s_axi_arready_o(nl_arready),
        .s_axi_rdata_o(nl_rdata),
        .s_axi_rresp_o(nl_rresp),
        .s_axi_rvalid_o(nl_rvalid),
        .s_axi_rready_i(nl_rready),
        .c_cmd_valid_o(svc_cmd_valid),
        .c_cmd_ready_i(svc_cmd_ready),
        .c_cmd_write_o(svc_cmd_write),
        .c_cmd_offset_o(svc_cmd_offset),
        .c_cmd_id_o(svc_cmd_id),
        .c_cmd_epoch_o(svc_cmd_epoch),
        .c_cmd_beats_o(svc_cmd_beats),
        .c_cmd_client_o(svc_cmd_client),
        .c_write_valid_o(svc_write_valid),
        .c_write_ready_i(svc_write_ready),
        .c_write_data_o(svc_write_data),
        .c_write_strb_o(svc_write_strb),
        .c_write_last_o(svc_write_last),
        .c_read_valid_i(svc_read_valid),
        .c_read_ready_o(svc_read_ready),
        .c_read_data_i(svc_read_data),
        .c_read_last_i(svc_read_last),
        .c_done_valid_i(svc_done_valid),
        .c_done_ready_o(svc_done_ready),
        .c_done_status_i(svc_done_status),
        .c_done_id_i(svc_done_id),
        .c_done_epoch_i(svc_done_epoch),
        .c_done_client_i(svc_done_client)
    );
    npu_service_axi128 u_adapter (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .healthy_i(healthy_i && !fabric_fault),
        .p_cmd_valid(svc_cmd_valid),
        .p_cmd_ready(svc_cmd_ready),
        .p_cmd_write(svc_cmd_write),
        .p_cmd_offset(svc_cmd_offset),
        .p_cmd_id(svc_cmd_id),
        .p_cmd_epoch(svc_cmd_epoch),
        .p_cmd_beats(svc_cmd_beats),
        .p_cmd_client(svc_cmd_client),
        .p_write_valid(svc_write_valid),
        .p_write_ready(svc_write_ready),
        .p_write_data(svc_write_data),
        .p_write_strb(svc_write_strb),
        .p_write_last(svc_write_last),
        .p_read_valid(svc_read_valid),
        .p_read_ready(svc_read_ready),
        .p_read_data(svc_read_data),
        .p_read_last(svc_read_last),
        .p_abort_req(svc_abort),
        .p_done_valid(svc_done_valid),
        .p_done_ready(svc_done_ready),
        .p_done_status(svc_done_status),
        .p_done_id(svc_done_id),
        .p_done_epoch(svc_done_epoch),
        .p_done_client(svc_done_client),
        .idle_o(adapter_idle),
        .fault_o(adapter_fault),
        .fault_code_o(adapter_fault_code),
        .m_awvalid_o(npu_awvalid),
        .m_awready_i(npu_awready),
        .m_awaddr_o(npu_awaddr),
        .m_awid_o(npu_awid),
        .m_awlen_o(npu_awlen),
        .m_awsize_o(npu_awsize),
        .m_awburst_o(npu_awburst),
        .m_wvalid_o(npu_wvalid),
        .m_wready_i(npu_wready),
        .m_wdata_o(npu_wdata),
        .m_wstrb_o(npu_wstrb),
        .m_wlast_o(npu_wlast),
        .m_bvalid_i(npu_bvalid),
        .m_bready_o(npu_bready),
        .m_bid_i(npu_bid),
        .m_bresp_i(npu_bresp),
        .m_arvalid_o(npu_arvalid),
        .m_arready_i(npu_arready),
        .m_araddr_o(npu_araddr),
        .m_arid_o(npu_arid),
        .m_arlen_o(npu_arlen),
        .m_arsize_o(npu_arsize),
        .m_arburst_o(npu_arburst),
        .m_rvalid_i(npu_rvalid),
        .m_rready_o(npu_rready),
        .m_rdata_i(npu_rdata),
        .m_rid_i(npu_rid),
        .m_rresp_i(npu_rresp),
        .m_rlast_i(npu_rlast)
    );
    soc_axi128_arbiter #(.MASTERS(2)) u_compute_arbiter (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .healthy_i(healthy_i && !fault_o),
        .s_awvalid_i({npu_awvalid,cpu_awvalid}),
        .s_awready_o({npu_awready,cpu_awready}),
        .s_awaddr_i({npu_awaddr,cpu_awaddr}),
        .s_awid_i({npu_awid,cpu_awid}),
        .s_awlen_i({npu_awlen,cpu_awlen}),
        .s_awsize_i({npu_awsize,cpu_awsize}),
        .s_awburst_i({npu_awburst,cpu_awburst}),
        .s_wvalid_i({npu_wvalid,cpu_wvalid}),
        .s_wready_o({npu_wready,cpu_wready}),
        .s_wdata_i({npu_wdata,cpu_wdata}),
        .s_wstrb_i({npu_wstrb,cpu_wstrb}),
        .s_wlast_i({npu_wlast,cpu_wlast}),
        .s_bvalid_o({npu_bvalid,cpu_bvalid}),
        .s_bready_i({npu_bready,cpu_bready}),
        .s_bid_o({npu_bid,cpu_bid}),
        .s_bresp_o({npu_bresp,cpu_bresp}),
        .s_arvalid_i({npu_arvalid,cpu_arvalid}),
        .s_arready_o({npu_arready,cpu_arready}),
        .s_araddr_i({npu_araddr,cpu_araddr}),
        .s_arid_i({npu_arid,cpu_arid}),
        .s_arlen_i({npu_arlen,cpu_arlen}),
        .s_arsize_i({npu_arsize,cpu_arsize}),
        .s_arburst_i({npu_arburst,cpu_arburst}),
        .s_rvalid_o({npu_rvalid,cpu_rvalid}),
        .s_rready_i({npu_rready,cpu_rready}),
        .s_rdata_o({npu_rdata,cpu_rdata}),
        .s_rid_o({npu_rid,cpu_rid}),
        .s_rresp_o({npu_rresp,cpu_rresp}),
        .s_rlast_o({npu_rlast,cpu_rlast}),
        .m_awvalid_o(m_awvalid_o),
        .m_awready_i(m_awready_i),
        .m_awaddr_o(m_awaddr_o),
        .m_awid_o(m_awid_o),
        .m_awlen_o(m_awlen_o),
        .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o),
        .m_wvalid_o(m_wvalid_o),
        .m_wready_i(m_wready_i),
        .m_wdata_o(m_wdata_o),
        .m_wstrb_o(m_wstrb_o),
        .m_wlast_o(m_wlast_o),
        .m_bvalid_i(m_bvalid_i),
        .m_bready_o(m_bready_o),
        .m_bid_i(m_bid_i),
        .m_bresp_i(m_bresp_i),
        .m_arvalid_o(m_arvalid_o),
        .m_arready_i(m_arready_i),
        .m_araddr_o(m_araddr_o),
        .m_arid_o(m_arid_o),
        .m_arlen_o(m_arlen_o),
        .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o),
        .m_rvalid_i(m_rvalid_i),
        .m_rready_o(m_rready_o),
        .m_rdata_i(m_rdata_i),
        .m_rid_i(m_rid_i),
        .m_rresp_i(m_rresp_i),
        .m_rlast_i(m_rlast_i),
        .idle_o(compute_idle_o),
        .fault_o(arb_fault),
        .fault_code_o(arb_fault_code)
    );
endmodule
`default_nettype wire
