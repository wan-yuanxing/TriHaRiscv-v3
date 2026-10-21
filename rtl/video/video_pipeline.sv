`timescale 1ns/1ps
`default_nettype none
// Video-local integration. CPU retains global frame/graph ownership.
// Source PIX/EOF is already in the core clock domain and accepts backpressure.
// Both resets must belong to a coordinated epoch; no local recovery is implied.
// Production geometry is 800x600. Smaller height is for failure probes only.
module video_pipeline #(parameter integer FRAME_HEIGHT=600,MAX_READ_BURSTS=4,TIMEOUT_CYCLES=125000000)(
    input wire clk_i,
    input wire rst_ni,
    input wire pixel_clk,
    input wire pixel_reset_n,
    input wire online,
    input wire display_urgent,
    input wire source_fault,
    input wire overflow,
    input wire src_valid,
    input wire [47:0] src_data,
    output wire src_ready,
    output wire arm_toggle,
    output wire cancel,
    output wire capture_busy,
    output wire capture_port_drained,
    input wire [31:0] c_s_axi_awaddr_i,
    input wire [2:0] c_s_axi_awprot_i,
    input wire c_s_axi_awvalid_i,
    output wire c_s_axi_awready_o,
    input wire [31:0] c_s_axi_wdata_i,
    input wire [3:0] c_s_axi_wstrb_i,
    input wire c_s_axi_wvalid_i,
    output wire c_s_axi_wready_o,
    output wire [1:0] c_s_axi_bresp_o,
    output wire c_s_axi_bvalid_o,
    input wire c_s_axi_bready_i,
    input wire [31:0] c_s_axi_araddr_i,
    input wire [2:0] c_s_axi_arprot_i,
    input wire c_s_axi_arvalid_i,
    output wire c_s_axi_arready_o,
    output wire [31:0] c_s_axi_rdata_o,
    output wire [1:0] c_s_axi_rresp_o,
    output wire c_s_axi_rvalid_o,
    input wire c_s_axi_rready_i,
    input wire [31:0] d_s_axi_awaddr_i,
    input wire [2:0] d_s_axi_awprot_i,
    input wire d_s_axi_awvalid_i,
    output wire d_s_axi_awready_o,
    input wire [31:0] d_s_axi_wdata_i,
    input wire [3:0] d_s_axi_wstrb_i,
    input wire d_s_axi_wvalid_i,
    output wire d_s_axi_wready_o,
    output wire [1:0] d_s_axi_bresp_o,
    output wire d_s_axi_bvalid_o,
    input wire d_s_axi_bready_i,
    input wire [31:0] d_s_axi_araddr_i,
    input wire [2:0] d_s_axi_arprot_i,
    input wire d_s_axi_arvalid_i,
    output wire d_s_axi_arready_o,
    output wire [31:0] d_s_axi_rdata_o,
    output wire [1:0] d_s_axi_rresp_o,
    output wire d_s_axi_rvalid_o,
    input wire d_s_axi_rready_i,
    input wire [10:0] pixel_x,
    input wire [10:0] pixel_y,
    input wire pixel_de,
    input wire pixel_hs,
    input wire pixel_vs,
    input wire pixel_frame_start,
    output wire [23:0] out_rgb,
    output wire out_de,
    output wire out_hs,
    output wire out_vs,
    output wire irq_capture,
    output wire irq_display,
    output wire [2:0] faults,
    output wire [7:0] capture_code,
    output wire [7:0] display_code,
    output wire [7:0] memory_code,
    output wire [31:0] raw_commits,
    output wire [31:0] raw_scans,
    output wire [31:0] underflows,
    output wire [31:0] raw_frame,
    output wire [31:0] read_grants,
    output wire [31:0] write_grants,
    output wire [27:0] h_awaddr,
    output wire [27:0] h_araddr,
    output wire [3:0] h_awlen,
    output wire [3:0] h_arlen,
    output wire [3:0] h_awid,
    output wire [3:0] h_arid,
    output wire h_awvalid,
    output wire h_arvalid,
    input wire h_awready,
    input wire h_arready,
    input wire h_wready,
    input wire h_rvalid,
    output wire [255:0] h_wdata,
    output wire [31:0] h_wstrb,
    input wire [255:0] h_rdata,
    input wire [3:0] h_wid,
    input wire [3:0] h_rid,
    input wire h_wlast,
    input wire h_rlast
);
    wire capture_req_valid_o;
    wire capture_req_ready_i;
    wire [1:0] capture_req_slot_o;
    wire [31:0] capture_req_frame_id_o;
    wire [31:0] capture_req_version_o;
    wire [31:0] capture_req_generation_o;
    wire accepted_valid_i;
    wire accepted_ready_o;
    wire completion_valid_i;
    wire completion_ready_o;
    wire completion_success_i;
    wire [7:0] completion_code_i;
    wire [1:0] capture_slot_i;
    wire [31:0] capture_frame_id_i;
    wire [31:0] capture_version_i;
    wire [31:0] capture_raw_base_i;
    wire [31:0] capture_preview_base_i;
    wire [31:0] capture_input_base_i;
    wire [31:0] capture_raw_pixels_i;
    wire [31:0] capture_preview_pixels_i;
    wire [31:0] capture_input_pixels_i;
    wire [31:0] capture_raw_bytes_i;
    wire [31:0] capture_preview_bytes_i;
    wire [31:0] capture_input_bytes_i;
    wire [31:0] capture_raw_crc_i;
    wire [31:0] capture_preview_crc_i;
    wire [31:0] capture_fifo_peak_i;
    wire capture_live_fault_i;
    wire [7:0] capture_live_code_i;
    wire capture_port_drained_i;
    wire capture_abort_o;
    wire [3:0] c_awid;
    wire [31:0] c_awaddr;
    wire [7:0] c_awlen;
    wire [2:0] c_awsize;
    wire [1:0] c_awburst;
    wire c_awvalid;
    wire c_awready;
    wire [127:0] c_wdata;
    wire [15:0] c_wstrb;
    wire c_wlast;
    wire c_wvalid;
    wire c_wready;
    wire [3:0] c_bid;
    wire [1:0] c_bresp;
    wire c_bvalid;
    wire c_bready;
    wire [3:0] d_arid;
    wire [31:0] d_araddr;
    wire [7:0] d_arlen;
    wire [2:0] d_arsize;
    wire [1:0] d_arburst;
    wire d_arvalid;
    wire d_arready;
    wire [3:0] d_rid;
    wire [127:0] d_rdata;
    wire [1:0] d_rresp;
    wire d_rlast;
    wire d_rvalid;
    wire d_rready;
    wire display_fault,memory_fault,memory_busy,memory_drained;
    wire [31:0] raw_lines;
    video_capture_mmio_v2 #(.FRAME_HEIGHT(FRAME_HEIGHT)) u_capture_mmio(
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axi_awaddr_i(c_s_axi_awaddr_i),
        .s_axi_awprot_i(c_s_axi_awprot_i),
        .s_axi_awvalid_i(c_s_axi_awvalid_i),
        .s_axi_awready_o(c_s_axi_awready_o),
        .s_axi_wdata_i(c_s_axi_wdata_i),
        .s_axi_wstrb_i(c_s_axi_wstrb_i),
        .s_axi_wvalid_i(c_s_axi_wvalid_i),
        .s_axi_wready_o(c_s_axi_wready_o),
        .s_axi_bresp_o(c_s_axi_bresp_o),
        .s_axi_bvalid_o(c_s_axi_bvalid_o),
        .s_axi_bready_i(c_s_axi_bready_i),
        .s_axi_araddr_i(c_s_axi_araddr_i),
        .s_axi_arprot_i(c_s_axi_arprot_i),
        .s_axi_arvalid_i(c_s_axi_arvalid_i),
        .s_axi_arready_o(c_s_axi_arready_o),
        .s_axi_rdata_o(c_s_axi_rdata_o),
        .s_axi_rresp_o(c_s_axi_rresp_o),
        .s_axi_rvalid_o(c_s_axi_rvalid_o),
        .s_axi_rready_i(c_s_axi_rready_i),
        .capture_req_valid_o(capture_req_valid_o),
        .capture_req_ready_i(capture_req_ready_i),
        .capture_req_slot_o(capture_req_slot_o),
        .capture_req_frame_id_o(capture_req_frame_id_o),
        .capture_req_version_o(capture_req_version_o),
        .capture_req_generation_o(capture_req_generation_o),
        .accepted_valid_i(accepted_valid_i),
        .accepted_ready_o(accepted_ready_o),
        .completion_valid_i(completion_valid_i),
        .completion_ready_o(completion_ready_o),
        .completion_success_i(completion_success_i),
        .completion_code_i(completion_code_i),
        .capture_slot_i(capture_slot_i),
        .capture_frame_id_i(capture_frame_id_i),
        .capture_version_i(capture_version_i),
        .capture_raw_base_i(capture_raw_base_i),
        .capture_preview_base_i(capture_preview_base_i),
        .capture_input_base_i(capture_input_base_i),
        .capture_raw_pixels_i(capture_raw_pixels_i),
        .capture_preview_pixels_i(capture_preview_pixels_i),
        .capture_input_pixels_i(capture_input_pixels_i),
        .capture_raw_bytes_i(capture_raw_bytes_i),
        .capture_preview_bytes_i(capture_preview_bytes_i),
        .capture_input_bytes_i(capture_input_bytes_i),
        .capture_raw_crc_i(capture_raw_crc_i),
        .capture_preview_crc_i(capture_preview_crc_i),
        .capture_fifo_peak_i(capture_fifo_peak_i),
        .capture_live_fault_i(capture_live_fault_i),
        .capture_live_code_i(capture_live_code_i),
        .capture_port_drained_i(capture_port_drained_i),
        .capture_abort_o(capture_abort_o),
        .irq_o(irq_capture));
    video_three_branch_capture #(.FRAME_HEIGHT(FRAME_HEIGHT),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.ENABLE_REARM(1)) u_capture(
        .clk(clk_i),
        .reset_n(rst_ni),
        .init_done(online),
        .abort(capture_abort_o),
        .req_valid(capture_req_valid_o),
        .req_ready(capture_req_ready_i),
        .req_slot(capture_req_slot_o),
        .req_frame_id(capture_req_frame_id_o),
        .req_preprocess_version(capture_req_version_o),
        .m_valid(src_valid),
        .m_data(src_data),
        .m_ready(src_ready),
        .source_fault(source_fault),
        .overflow(overflow),
        .arm_toggle(arm_toggle),
        .cancel(cancel),
        .busy(capture_busy),
        .port_drained(capture_port_drained_i),
        .accepted_valid(accepted_valid_i),
        .accepted_ready(accepted_ready_o),
        .completion_valid(completion_valid_i),
        .completion_ready(completion_ready_o),
        .completion_success(completion_success_i),
        .completion_code(completion_code_i),
        .error(capture_live_fault_i),
        .error_code(capture_live_code_i),
        .frame_id(capture_frame_id_i),
        .preprocess_version(capture_version_i),
        .raw_base(capture_raw_base_i),
        .preview_base(capture_preview_base_i),
        .input_base(capture_input_base_i),
        .slot(capture_slot_i),
        .captured_pixels(capture_raw_pixels_i),
        .preview_pixels(capture_preview_pixels_i),
        .input_pixels(capture_input_pixels_i),
        .source_crc(capture_raw_crc_i),
        .preview_crc(capture_preview_crc_i),
        .fifo_peak(capture_fifo_peak_i),
        .raw_written_bytes(capture_raw_bytes_i),
        .preview_written_bytes(capture_preview_bytes_i),
        .input_written_bytes(capture_input_bytes_i),
        .awid(c_awid),
        .awaddr(c_awaddr),
        .awlen(c_awlen),
        .awsize(c_awsize),
        .awburst(c_awburst),
        .awvalid(c_awvalid),
        .awready(c_awready),
        .wdata(c_wdata),
        .wstrb(c_wstrb),
        .wlast(c_wlast),
        .wvalid(c_wvalid),
        .wready(c_wready),
        .bid(c_bid),
        .bresp(c_bresp),
        .bvalid(c_bvalid),
        .bready(c_bready));
    video_display_scanout #(.FRAME_HEIGHT(FRAME_HEIGHT),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_display(
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .s_axi_awaddr_i(d_s_axi_awaddr_i),
        .s_axi_awprot_i(d_s_axi_awprot_i),
        .s_axi_awvalid_i(d_s_axi_awvalid_i),
        .s_axi_awready_o(d_s_axi_awready_o),
        .s_axi_wdata_i(d_s_axi_wdata_i),
        .s_axi_wstrb_i(d_s_axi_wstrb_i),
        .s_axi_wvalid_i(d_s_axi_wvalid_i),
        .s_axi_wready_o(d_s_axi_wready_o),
        .s_axi_bresp_o(d_s_axi_bresp_o),
        .s_axi_bvalid_o(d_s_axi_bvalid_o),
        .s_axi_bready_i(d_s_axi_bready_i),
        .s_axi_araddr_i(d_s_axi_araddr_i),
        .s_axi_arprot_i(d_s_axi_arprot_i),
        .s_axi_arvalid_i(d_s_axi_arvalid_i),
        .s_axi_arready_o(d_s_axi_arready_o),
        .s_axi_rdata_o(d_s_axi_rdata_o),
        .s_axi_rresp_o(d_s_axi_rresp_o),
        .s_axi_rvalid_o(d_s_axi_rvalid_o),
        .s_axi_rready_i(d_s_axi_rready_i),
        .pixel_clk(pixel_clk),
        .pixel_reset_n(pixel_reset_n),
        .ddr_ready(online),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_de(pixel_de),
        .pixel_hs(pixel_hs),
        .pixel_vs(pixel_vs),
        .pixel_frame_start(pixel_frame_start),
        .out_rgb(out_rgb),
        .out_de(out_de),
        .out_hs(out_hs),
        .out_vs(out_vs),
        .fault(display_fault),
        .fault_code(display_code),
        .raw_commits(raw_commits),
        .raw_scans(raw_scans),
        .raw_lines(raw_lines),
        .underflows(underflows),
        .raw_frame(raw_frame),
        .m_axi_arid(d_arid),
        .m_axi_araddr(d_araddr),
        .m_axi_arlen(d_arlen),
        .m_axi_arsize(d_arsize),
        .m_axi_arburst(d_arburst),
        .m_axi_arvalid(d_arvalid),
        .m_axi_arready(d_arready),
        .m_axi_rid(d_rid),
        .m_axi_rdata(d_rdata),
        .m_axi_rresp(d_rresp),
        .m_axi_rlast(d_rlast),
        .m_axi_rvalid(d_rvalid),
        .m_axi_rready(d_rready),
        .irq_o(irq_display));
    video_shared_ddr #(.MAX_READ_BURSTS(MAX_READ_BURSTS),.NATIVE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_memory(
        .clk(clk_i),
        .reset_n(rst_ni),
        .online(online),
        .display_urgent(display_urgent),
        .c_awid(c_awid),
        .d_arid(d_arid),
        .c_awaddr(c_awaddr),
        .d_araddr(d_araddr),
        .c_awlen(c_awlen),
        .d_arlen(d_arlen),
        .c_awsize(c_awsize),
        .d_arsize(d_arsize),
        .c_awburst(c_awburst),
        .d_arburst(d_arburst),
        .c_awvalid(c_awvalid),
        .c_awready(c_awready),
        .c_wdata(c_wdata),
        .c_wstrb(c_wstrb),
        .c_wlast(c_wlast),
        .c_wvalid(c_wvalid),
        .c_wready(c_wready),
        .c_bid(c_bid),
        .c_bresp(c_bresp),
        .c_bvalid(c_bvalid),
        .c_bready(c_bready),
        .d_arvalid(d_arvalid),
        .d_arready(d_arready),
        .d_rid(d_rid),
        .d_rdata(d_rdata),
        .d_rresp(d_rresp),
        .d_rlast(d_rlast),
        .d_rvalid(d_rvalid),
        .d_rready(d_rready),
        .h_awaddr(h_awaddr),
        .h_araddr(h_araddr),
        .h_awlen(h_awlen),
        .h_arlen(h_arlen),
        .h_awid(h_awid),
        .h_arid(h_arid),
        .h_awvalid(h_awvalid),
        .h_arvalid(h_arvalid),
        .h_awready(h_awready),
        .h_arready(h_arready),
        .h_wready(h_wready),
        .h_rvalid(h_rvalid),
        .h_wdata(h_wdata),
        .h_wstrb(h_wstrb),
        .h_rdata(h_rdata),
        .h_wid(h_wid),
        .h_rid(h_rid),
        .h_wlast(h_wlast),
        .h_rlast(h_rlast),
        .fault(memory_fault),
        .fault_code(memory_code),
        .busy(memory_busy),
        .port_drained(memory_drained),
        .read_grants(read_grants),
        .write_grants(write_grants));
    assign faults={memory_fault,display_fault,capture_live_fault_i};
    assign capture_code=capture_live_code_i;
    assign capture_port_drained=capture_port_drained_i;
endmodule
`default_nettype wire
