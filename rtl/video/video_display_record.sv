`timescale 1ns/1ps
`default_nettype none
// Frozen software ABI, sole MMIO owner, actual RAW/material consumers.
module video_display_record #(parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600,TIMEOUT_CYCLES=125000000)(
 input wire  core_clk,
 input wire  core_reset_n,
 input wire  pixel_clk,
 input wire  pixel_reset_n,
 input wire  online,
 input wire  memory_fault,
 input wire  display_urgent,
 input wire  load_valid,
 output wire  load_ready,
 input wire [31:0] load_base,
 input wire [31:0] load_bytes,
 input wire [31:0] load_asset_id,
 input wire [31:0] load_generation,
 input wire [31:0] expected_crc,
 output wire  result_valid,
 input wire  result_ready,
 output wire  result_success,
 output wire [7:0] result_code,
 output wire [31:0] result_asset_id,
 output wire [31:0] result_generation,
 output wire [31:0] checked_bytes,
 output wire [31:0] crc,
 output wire  asset_ready,
 output wire  pixel_material_ready,
 output wire [31:0] asset_id,
 output wire [31:0] asset_generation,
 output wire [31:0] words_written,
 output wire  raw_context_valid,
 output wire [1:0] raw_slot,
 output wire [31:0] raw_frame,
 output wire [31:0] raw_generation,
 output wire [10:0] raw_x,
 output wire [10:0] raw_y,
 output wire [23:0] raw_rgb,
 output wire  raw_de,
 output wire  raw_hs,
 output wire  raw_vs,
 output wire  raw_sof,
 output wire [23:0] out_rgb,
 output wire [10:0] out_x,
 output wire [10:0] out_y,
 output wire [31:0] out_frame,
 output wire [31:0] out_generation,
 output wire [31:0] out_seq,
 output wire [1:0] out_slot,
 output wire [1:0] out_mode,
 output wire  out_de,
 output wire  out_hs,
 output wire  out_vs,
 output wire  out_sof,
 output wire  out_box,
 output wire  out_point,
 output wire  out_avatar,
 output wire  out_fault,
 output wire  pixel_pending,
 output wire [1:0] pending_mode,
 output wire [1:0] pending_slot,
 output wire [31:0] pending_frame,
 output wire [31:0] pending_generation,
 output wire [2:0] faults,
 output wire [7:0] read_code,
 output wire [7:0] material_code,
 output wire [7:0] pixels_code,
 output wire  port_drained,
 output wire [31:0] raw_grants,
 output wire [31:0] asset_grants,
 output wire [3:0] m_arid,
 output wire [31:0] m_araddr,
 output wire [7:0] m_arlen,
 output wire [2:0] m_arsize,
 output wire [1:0] m_arburst,
 output wire  m_arvalid,
 input wire  m_arready,
 input wire [3:0] m_rid,
 input wire [127:0] m_rdata,
 input wire [1:0] m_rresp,
 input wire  m_rlast,
 input wire  m_rvalid,
 output wire  m_rready,
 input wire [10:0] pixel_x,
 input wire [10:0] pixel_y,
 input wire  pixel_de,
 input wire  pixel_hs,
 input wire  pixel_vs,
 input wire  pixel_frame_start,
 output wire  asset_retire_valid,
 input wire  asset_retire_ready,
 output wire [1:0] asset_retire_slot,
 output wire [31:0] asset_retire_frame,
 output wire [31:0] asset_retire_generation,
 output wire [31:0] asset_retire_seq,
 output wire [31:0] asset_retire_id,
 output wire [31:0] asset_retire_generation_id,
 output wire  owner_error,
 output wire  link_error,
 output wire  raw_error,
 output wire  fault,
 output wire [7:0] owner_code,
 output wire [7:0] link_code,
 output wire [7:0] raw_code,
 output wire [31:0] raw_commits,
 output wire [31:0] raw_scans,
 output wire [31:0] raw_lines,
 output wire [31:0] underflows,
 input wire [31:0] s_axi_awaddr_i,
 input wire [2:0] s_axi_awprot_i,
 input wire  s_axi_awvalid_i,
 output wire  s_axi_awready_o,
 input wire [31:0] s_axi_wdata_i,
 input wire [3:0] s_axi_wstrb_i,
 input wire  s_axi_wvalid_i,
 output wire  s_axi_wready_o,
 output wire [1:0] s_axi_bresp_o,
 output wire  s_axi_bvalid_o,
 input wire  s_axi_bready_i,
 input wire [31:0] s_axi_araddr_i,
 input wire [2:0] s_axi_arprot_i,
 input wire  s_axi_arvalid_i,
 output wire  s_axi_arready_o,
 output wire [31:0] s_axi_rdata_o,
 output wire [1:0] s_axi_rresp_o,
 output wire  s_axi_rvalid_o,
 input wire  s_axi_rready_i,
 output wire  irq_o
);
 wire  cmd_valid;
 wire  cmd_ready;
 wire  cmd_mode_only;
 wire [1:0] cmd_slot;
 wire [1:0] cmd_mode;
 wire [31:0] cmd_frame;
 wire [31:0] cmd_generation;
 wire [31:0] cmd_base;
 wire [31:0] cmd_stride;
 wire [31:0] cmd_seq;
 wire [5119:0] cmd_data;
 wire  feedback_valid;
 wire  feedback_ready;
 wire [1:0] feedback_slot;
 wire [1:0] feedback_mode;
 wire [31:0] feedback_frame;
 wire [31:0] feedback_generation;
 wire [31:0] feedback_seq;
 wire  retire_valid;
 wire  retire_ready;
 wire [1:0] retire_slot;
 wire [31:0] retire_frame;
 wire [31:0] retire_generation;
 wire [31:0] active_base;
 wire [31:0] active_stride;
 wire [31:0] active_seq;
 wire [5119:0] active_data;
 wire [31:0] submits;
 wire [31:0] commits;
 wire [31:0] releases;
 wire [31:0] rejected;
 wire  record_valid;
 wire  record_ready;
 wire [31:0] record_base;
 wire [31:0] record_stride;
 wire [31:0] record_frame;
 wire [31:0] record_generation;
 wire [1:0] record_slot;
 wire  r_cmd_valid;
 wire  r_cmd_ready;
 wire [1:0] r_cmd_mode;
 wire [1:0] r_cmd_slot;
 wire [31:0] r_cmd_frame;
 wire [31:0] r_cmd_generation;
 wire [31:0] r_cmd_seq;
 wire [5119:0] r_cmd_data;
 wire  raw_commit_valid;
 wire  raw_commit_ready;
 wire [31:0] raw_commit_frame;
 wire [31:0] raw_commit_generation;
 wire [1:0] raw_commit_slot;
 wire  raw_release_valid;
 wire  raw_release_ready;
 wire [31:0] raw_release_frame;
 wire [31:0] raw_release_generation;
 wire [1:0] raw_release_slot;
 wire  p_commit_valid;
 wire  p_commit_ready;
 wire [1:0] p_commit_mode;
 wire [1:0] p_commit_slot;
 wire [31:0] p_commit_frame;
 wire [31:0] p_commit_generation;
 wire [31:0] p_commit_seq;
 wire  p_retire_valid;
 wire  p_retire_ready;
 wire  p_retire_raw;
 wire  p_retire_asset;
 wire [1:0] p_retire_slot;
 wire [31:0] p_retire_frame;
 wire [31:0] p_retire_generation;
 wire [31:0] p_retire_seq;
 wire [31:0] p_retire_asset_id;
 wire [31:0] p_retire_asset_generation;
 wire  renderer_fault;
 wire  scanner_online;
 wire  raw_reject;
 wire [7:0] scanner_record_reject_code;
 wire [31:0] scanner_rejected_records;
 wire [31:0] scanner_frame_id;
 wire [3:0] d_arid;
 wire [31:0] d_araddr;
 wire [7:0] d_arlen;
 wire [2:0] d_arsize;
 wire [1:0] d_arburst;
 wire  d_arvalid;
 wire  d_arready;
 wire [3:0] d_rid;
 wire [127:0] d_rdata;
 wire [1:0] d_rresp;
 wire  d_rlast;
 wire  d_rvalid;
 wire  d_rready;
 wire [1:0] p_retire_mode;
 wire inner_load_ready;
 wire downstream_fault=memory_fault||link_error||raw_error||raw_reject||renderer_fault;
 wire load_health=online===1'b1&&downstream_fault===1'b0&&owner_error===1'b0;
 assign load_ready=inner_load_ready&&load_health;
 assign scanner_online=online&&!memory_fault;
 assign renderer_fault=|faults;
 assign fault=owner_error||downstream_fault;
 video_display_mmio #(.EXTERNAL_HEALTH(1)) u_mmio(
  .clk_i(core_clk),
  .rst_ni(core_reset_n),
  .s_axi_awaddr_i(s_axi_awaddr_i),
  .s_axi_awprot_i(s_axi_awprot_i),
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
  .s_axi_arprot_i(s_axi_arprot_i),
  .s_axi_arvalid_i(s_axi_arvalid_i),
  .s_axi_arready_o(s_axi_arready_o),
  .s_axi_rdata_o(s_axi_rdata_o),
  .s_axi_rresp_o(s_axi_rresp_o),
  .s_axi_rvalid_o(s_axi_rvalid_o),
  .s_axi_rready_i(s_axi_rready_i),
  .modes_i(3'b111),
  .asset_ready_i(asset_ready),
  .asset_id_i(asset_id),
  .asset_generation_i(asset_generation),
  .cmd_valid_o(cmd_valid),
  .cmd_ready_i(cmd_ready),
  .cmd_mode_only_o(cmd_mode_only),
  .cmd_slot_o(cmd_slot),
  .cmd_mode_o(cmd_mode),
  .cmd_frame_o(cmd_frame),
  .cmd_generation_o(cmd_generation),
  .cmd_base_o(cmd_base),
  .cmd_stride_o(cmd_stride),
  .cmd_seq_o(cmd_seq),
  .cmd_data_o(cmd_data),
  .feedback_valid_i(feedback_valid),
  .feedback_ready_o(feedback_ready),
  .feedback_slot_i(feedback_slot),
  .feedback_mode_i(feedback_mode),
  .feedback_frame_i(feedback_frame),
  .feedback_generation_i(feedback_generation),
  .feedback_seq_i(feedback_seq),
  .retire_valid_i(retire_valid),
  .retire_ready_o(retire_ready),
  .retire_slot_i(retire_slot),
  .retire_frame_i(retire_frame),
  .retire_generation_i(retire_generation),
  .irq_o(irq_o),
  .submit_enable_i(load_health),
  .external_fault_i(downstream_fault),
  .fault_o(owner_error),
  .fault_code_o(owner_code)
 );
 display_record_link  u_link(
  .clk(core_clk),
  .reset_n(core_reset_n),
  .cmd_valid(cmd_valid),
  .cmd_ready(cmd_ready),
  .cmd_mode_only(cmd_mode_only),
  .cmd_slot(cmd_slot),
  .cmd_mode(cmd_mode),
  .cmd_frame(cmd_frame),
  .cmd_generation(cmd_generation),
  .cmd_base(cmd_base),
  .cmd_stride(cmd_stride),
  .cmd_seq(cmd_seq),
  .cmd_data(cmd_data),
  .record_valid(record_valid),
  .record_ready(record_ready),
  .record_base(record_base),
  .record_stride(record_stride),
  .record_frame(record_frame),
  .record_generation(record_generation),
  .record_slot(record_slot),
  .r_cmd_valid(r_cmd_valid),
  .r_cmd_ready(r_cmd_ready),
  .r_cmd_mode(r_cmd_mode),
  .r_cmd_slot(r_cmd_slot),
  .r_cmd_frame(r_cmd_frame),
  .r_cmd_generation(r_cmd_generation),
  .r_cmd_seq(r_cmd_seq),
  .r_cmd_data(r_cmd_data),
  .raw_commit_valid(raw_commit_valid),
  .raw_commit_ready(raw_commit_ready),
  .raw_commit_frame(raw_commit_frame),
  .raw_commit_generation(raw_commit_generation),
  .raw_commit_slot(raw_commit_slot),
  .raw_release_valid(raw_release_valid),
  .raw_release_ready(raw_release_ready),
  .raw_release_frame(raw_release_frame),
  .raw_release_generation(raw_release_generation),
  .raw_release_slot(raw_release_slot),
  .p_commit_valid(p_commit_valid),
  .p_commit_ready(p_commit_ready),
  .p_commit_mode(p_commit_mode),
  .p_commit_slot(p_commit_slot),
  .p_commit_frame(p_commit_frame),
  .p_commit_generation(p_commit_generation),
  .p_commit_seq(p_commit_seq),
  .p_retire_valid(p_retire_valid),
  .p_retire_ready(p_retire_ready),
  .p_retire_raw(p_retire_raw),
  .p_retire_asset(p_retire_asset),
  .p_retire_slot(p_retire_slot),
  .p_retire_frame(p_retire_frame),
  .p_retire_generation(p_retire_generation),
  .p_retire_seq(p_retire_seq),
  .p_retire_asset_id(p_retire_asset_id),
  .p_retire_asset_generation(p_retire_asset_generation),
  .feedback_valid(feedback_valid),
  .feedback_ready(feedback_ready),
  .feedback_slot(feedback_slot),
  .feedback_mode(feedback_mode),
  .feedback_frame(feedback_frame),
  .feedback_generation(feedback_generation),
  .feedback_seq(feedback_seq),
  .retire_valid(retire_valid),
  .retire_ready(retire_ready),
  .retire_slot(retire_slot),
  .retire_frame(retire_frame),
  .retire_generation(retire_generation),
  .asset_retire_valid(asset_retire_valid),
  .asset_retire_ready(asset_retire_ready),
  .asset_retire_slot(asset_retire_slot),
  .asset_retire_frame(asset_retire_frame),
  .asset_retire_generation(asset_retire_generation),
  .asset_retire_seq(asset_retire_seq),
  .asset_retire_id(asset_retire_id),
  .asset_retire_generation_id(asset_retire_generation_id),
  .raw_error(raw_error || raw_reject),
  .renderer_fault(renderer_fault),
  .fault(link_error),
  .fault_code(link_code)
 );
 raw_display #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_raw(
  .core_clk(core_clk),
  .core_reset_n(core_reset_n),
  .pixel_clk(pixel_clk),
  .pixel_reset_n(pixel_reset_n),
  .ddr_ready(scanner_online),
  .record_valid(record_valid),
  .record_ready(record_ready),
  .record_reject_valid(raw_reject),
  .record_reject_ready(1'b1),
  .record_reject_code(scanner_record_reject_code),
  .rejected_records(scanner_rejected_records),
  .record_base(record_base),
  .record_stride(record_stride),
  .record_frame_id(record_frame),
  .record_slot(record_slot),
  .commit_valid(raw_commit_valid),
  .commit_ready(raw_commit_ready),
  .commit_frame_id(raw_commit_frame),
  .commit_slot(raw_commit_slot),
  .release_valid(raw_release_valid),
  .release_ready(raw_release_ready),
  .release_frame_id(raw_release_frame),
  .release_slot(raw_release_slot),
  .pixel_x(pixel_x),
  .pixel_y(pixel_y),
  .pixel_de(pixel_de),
  .pixel_hs(pixel_hs),
  .pixel_vs(pixel_vs),
  .pixel_frame_start(pixel_frame_start),
  .out_rgb(raw_rgb),
  .out_de(raw_de),
  .out_hs(raw_hs),
  .out_vs(raw_vs),
  .error(raw_error),
  .error_code(raw_code),
  .commits(raw_commits),
  .completed_scans(raw_scans),
  .read_lines(raw_lines),
  .underflows(underflows),
  .frame_id(scanner_frame_id),
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
  .record_generation(record_generation),
  .commit_generation(raw_commit_generation),
  .release_generation(raw_release_generation),
  .out_context_valid(raw_context_valid),
  .out_frame_id(raw_frame),
  .out_generation(raw_generation),
  .out_slot(raw_slot),
  .out_x(raw_x),
  .out_y(raw_y),
  .out_sof(raw_sof)
 );
 video_record_renderer #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_renderer(
  .core_clk(core_clk),
  .core_reset_n(core_reset_n),
  .pixel_clk(pixel_clk),
  .pixel_reset_n(pixel_reset_n),
  .online(online),
  .memory_fault(memory_fault),
  .display_urgent(display_urgent),
  .load_valid(load_valid && load_health),
  .load_ready(inner_load_ready),
  .load_base(load_base),
  .load_bytes(load_bytes),
  .load_asset_id(load_asset_id),
  .load_generation(load_generation),
  .expected_crc(expected_crc),
  .result_valid(result_valid),
  .result_ready(result_ready),
  .result_success(result_success),
  .result_code(result_code),
  .result_asset_id(result_asset_id),
  .result_generation(result_generation),
  .checked_bytes(checked_bytes),
  .crc(crc),
  .asset_ready(asset_ready),
  .pixel_material_ready(pixel_material_ready),
  .asset_id(asset_id),
  .asset_generation(asset_generation),
  .words_written(words_written),
  .cmd_valid(r_cmd_valid),
  .cmd_ready(r_cmd_ready),
  .cmd_mode(r_cmd_mode),
  .cmd_slot(r_cmd_slot),
  .cmd_frame(r_cmd_frame),
  .cmd_generation(r_cmd_generation),
  .cmd_seq(r_cmd_seq),
  .cmd_data(r_cmd_data),
  .commit_valid(p_commit_valid),
  .commit_ready(p_commit_ready),
  .commit_mode(p_commit_mode),
  .commit_slot(p_commit_slot),
  .commit_frame(p_commit_frame),
  .commit_generation(p_commit_generation),
  .commit_seq(p_commit_seq),
  .retire_valid(p_retire_valid),
  .retire_ready(p_retire_ready),
  .retire_slot(p_retire_slot),
  .retire_mode(p_retire_mode),
  .retire_frame(p_retire_frame),
  .retire_generation(p_retire_generation),
  .retire_seq(p_retire_seq),
  .retire_raw(p_retire_raw),
  .retire_asset(p_retire_asset),
  .retire_asset_id(p_retire_asset_id),
  .retire_asset_generation(p_retire_asset_generation),
  .raw_context_valid(raw_context_valid),
  .raw_slot(raw_slot),
  .raw_frame(raw_frame),
  .raw_generation(raw_generation),
  .raw_x(raw_x),
  .raw_y(raw_y),
  .raw_rgb(raw_rgb),
  .raw_de(raw_de),
  .raw_hs(raw_hs),
  .raw_vs(raw_vs),
  .raw_sof(raw_sof),
  .out_rgb(out_rgb),
  .out_x(out_x),
  .out_y(out_y),
  .out_frame(out_frame),
  .out_generation(out_generation),
  .out_seq(out_seq),
  .out_slot(out_slot),
  .out_mode(out_mode),
  .out_de(out_de),
  .out_hs(out_hs),
  .out_vs(out_vs),
  .out_sof(out_sof),
  .out_box(out_box),
  .out_point(out_point),
  .out_avatar(out_avatar),
  .out_fault(out_fault),
  .pixel_pending(pixel_pending),
  .pending_mode(pending_mode),
  .pending_slot(pending_slot),
  .pending_frame(pending_frame),
  .pending_generation(pending_generation),
  .faults(faults),
  .read_code(read_code),
  .material_code(material_code),
  .pixels_code(pixels_code),
  .port_drained(port_drained),
  .raw_grants(raw_grants),
  .asset_grants(asset_grants),
  .d_arid(d_arid),
  .d_araddr(d_araddr),
  .d_arlen(d_arlen),
  .d_arsize(d_arsize),
  .d_arburst(d_arburst),
  .d_arvalid(d_arvalid),
  .d_arready(d_arready),
  .d_rid(d_rid),
  .d_rdata(d_rdata),
  .d_rresp(d_rresp),
  .d_rlast(d_rlast),
  .d_rvalid(d_rvalid),
  .d_rready(d_rready),
  .m_arid(m_arid),
  .m_araddr(m_araddr),
  .m_arlen(m_arlen),
  .m_arsize(m_arsize),
  .m_arburst(m_arburst),
  .m_arvalid(m_arvalid),
  .m_arready(m_arready),
  .m_rid(m_rid),
  .m_rdata(m_rdata),
  .m_rresp(m_rresp),
  .m_rlast(m_rlast),
  .m_rvalid(m_rvalid),
  .m_rready(m_rready)
 );
endmodule
`default_nettype wire
