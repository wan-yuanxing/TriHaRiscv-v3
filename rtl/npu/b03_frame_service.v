`timescale 1ns/1ps
`default_nettype none
`include "frame_config.vh"
// B03 arithmetic and two service owners, with no DDR controller/reset ownership.
// Adapted from the main resource boundary; upstream arithmetic remains frozen.
module b03_frame_service #(
    parameter integer ALLOW_COMMAND_CYCLE_RESPONSE = 1,
    parameter integer ENABLE_HARDWARE_POST = 1,
    parameter integer TRUSTED_MODEL = 0,
    parameter integer PREVALIDATED_TASK_LAYOUT = 0,
    parameter integer M_LANES = 16,
    parameter integer QUANTIZER_LANES = 2
) (
    input wire clk_i,
    input wire rst_ni,
    input wire session_reset_ni,
    input wire compute_running_i,
    input wire cancel_i,
    input wire [31:0] epoch_i,
    input wire [31:0] addr_version_i,
    input wire host_write_valid_i,
    input wire [31:0] host_write_offset_i,
    input wire [4:0] host_write_beats_i,
    input wire [1023:0] task_words_i,
    output wire frame_done_valid_o,
    input wire done_ready_i,
    output wire [31:0] frame_done_status_o,
    output wire [31:0] frame_done_detail_o,
    output wire [31:0] frame_done_cmd_id_o,
    output wire [31:0] frame_done_epoch_o,
    output wire [63:0] frame_done_frame_id_o,
    output wire [11:0] frame_done_faces_o,
    output wire [31:0] frame_done_result_offset_o,
    output wire [31:0] frame_done_result_bytes_o,
    output wire [31:0] frame_done_crc_o,
    output wire [63:0] frame_done_total_cycles_o,
    output wire [63:0] frame_done_model_cycles_o,
    output wire [63:0] frame_done_post_cycles_o,
    output wire frame_done_live_o,
    output wire frame_busy_o,
    output wire select_post_o,
    output wire cancel_all_o,
    output wire frame_compute_fault_valid_o,
    output wire [175:0] frame_compute_fault_payload_o,
    output wire [7:0] frame_debug_stage_o,
    output wire [7:0] frame_debug_op_o,
    output wire post_abort_o,
    output wire post_quarantined_o,
    output wire [175:0] frame_post_fault_payload_o,
    output wire dma_quarantined_o,
    output wire dma_reset_required_o,
    output wire dma_abort_req_o,
    output wire dma_busy_o,
    output wire dma_fault_valid_o,
    output wire [175:0] dma_fault_payload_o,
    output wire [3:0] dma_debug_state_o,
    output wire [31:0] dma_commands_o,
    output wire [31:0] dma_read_beats_o,
    output wire [31:0] dma_write_beats_o,
    output wire [31:0] dma_verify_offset_o,
    output wire [31:0] dma_verify_expected_o,
    output wire [31:0] dma_verify_actual_o,
    input wire transport_fault_i,
    output wire c_cmd_valid_o,
    input wire c_cmd_ready_i,
    output wire c_cmd_write_o,
    output wire [31:0] c_cmd_offset_o,
    output wire [31:0] c_cmd_id_o,
    output wire [31:0] c_cmd_epoch_o,
    output wire [4:0] c_cmd_beats_o,
    output wire [2:0] c_cmd_client_o,
    output wire c_write_valid_o,
    input wire c_write_ready_i,
    output wire [255:0] c_write_data_o,
    output wire [31:0] c_write_strb_o,
    output wire c_write_last_o,
    input wire c_read_valid_i,
    output wire c_read_ready_o,
    input wire [255:0] c_read_data_i,
    input wire c_read_last_i,
    input wire c_done_valid_i,
    output wire c_done_ready_o,
    input wire [3:0] c_done_status_i,
    input wire [31:0] c_done_id_i,
    input wire [31:0] c_done_epoch_i,
    input wire [2:0] c_done_client_i,
    output wire phase_fault_valid_o,
    output wire [175:0] phase_fault_payload_o,
    output wire phase_quarantined_o,
    output wire phase_reset_required_o,
    output wire phase_abort_req_o,
    output wire phase_busy_o,
    output wire [1:0] phase_debug_owner_o,
    output wire [31:0] phase_debug_global_id_o,
    output wire [31:0] phase_commands_o,
    output wire [31:0] phase_completions_o,
    input wire start_i,
    output wire start_ready_o
);
    wire leaf_rst_n = rst_ni && session_reset_ni;
    wire combined_fault = transport_fault_i || dma_quarantined_o || phase_quarantined_o || post_quarantined_o;
    wire frame_start_ready;
    assign start_ready_o = frame_start_ready && !dma_busy_o && !phase_busy_o;
    wire f_req_valid;
    wire f_req_ready;
    wire f_req_write;
    wire f_req_verify;
    wire [31:0] f_req_offset;
    wire [31:0] f_req_tag;
    wire [4:0] f_req_beats;
    wire [2:0] f_req_client;
    wire f_w_valid;
    wire f_w_ready;
    wire [255:0] f_w_data;
    wire [31:0] f_w_strb;
    wire f_w_last;
    wire f_r_valid;
    wire f_r_ready;
    wire [255:0] f_r_data;
    wire f_r_last;
    wire f_rsp_valid;
    wire f_rsp_ready;
    wire [3:0] f_rsp_status;
    wire [31:0] f_rsp_tag;
    wire p_cmd_valid;
    wire p_cmd_ready;
    wire p_cmd_write;
    wire [31:0] p_cmd_offset;
    wire [31:0] p_cmd_id;
    wire [31:0] p_cmd_epoch;
    wire [4:0] p_cmd_beats;
    wire [2:0] p_cmd_client;
    wire p_write_valid;
    wire p_write_ready;
    wire [255:0] p_write_data;
    wire [31:0] p_write_strb;
    wire p_write_last;
    wire p_read_valid;
    wire p_read_ready;
    wire [255:0] p_read_data;
    wire p_read_last;
    wire p_done_valid;
    wire p_done_ready;
    wire [3:0] p_done_status;
    wire [31:0] p_done_id;
    wire [31:0] p_done_epoch;
    wire [2:0] p_done_client;
    wire d_cmd_valid;
    wire d_cmd_ready;
    wire d_cmd_write;
    wire [31:0] d_cmd_offset;
    wire [31:0] d_cmd_id;
    wire [31:0] d_cmd_epoch;
    wire [4:0] d_cmd_beats;
    wire [2:0] d_cmd_client;
    wire d_write_valid;
    wire d_write_ready;
    wire [255:0] d_write_data;
    wire [31:0] d_write_strb;
    wire d_write_last;
    wire d_read_valid;
    wire d_read_ready;
    wire [255:0] d_read_data;
    wire d_read_last;
    wire d_done_valid;
    wire d_done_ready;
    wire [3:0] d_done_status;
    wire [31:0] d_done_id;
    wire [31:0] d_done_epoch;
    wire [2:0] d_done_client;
    b03_frame_exec_payload #(.ENABLE_HARDWARE_POST(ENABLE_HARDWARE_POST),.TRUSTED_MODEL(TRUSTED_MODEL),.PREVALIDATED_TASK_LAYOUT(PREVALIDATED_TASK_LAYOUT),.M_LANES(M_LANES),.QUANTIZER_LANES(QUANTIZER_LANES)) u_frame (
        .clk(clk_i),
        .board_reset_n(rst_ni),
        .session_reset_n(session_reset_ni),
        .compute_running(compute_running_i),
        .run_ce(1'b1),
        .cancel_request(cancel_i),
        .bridge_fault(combined_fault),
        .epoch(epoch_i),
        .addr_cfg_version(addr_version_i),
        .cfg_window_base(`SOC_WINDOW_BASE),
        .cfg_window_bytes(`SOC_WINDOW_BYTES),
        .host_write_valid(host_write_valid_i),
        .host_write_offset(host_write_offset_i),
        .host_write_beats(host_write_beats_i),
        .start_valid(start_i && !dma_busy_o && !phase_busy_o),
        .start_ready(frame_start_ready),
        .task_words(task_words_i),
        .done_valid(frame_done_valid_o),
        .done_ready(done_ready_i),
        .done_status(frame_done_status_o),
        .done_detail(frame_done_detail_o),
        .done_cmd_id(frame_done_cmd_id_o),
        .done_epoch(frame_done_epoch_o),
        .done_frame_id(frame_done_frame_id_o),
        .done_faces(frame_done_faces_o),
        .done_result_offset(frame_done_result_offset_o),
        .done_result_bytes(frame_done_result_bytes_o),
        .done_crc(frame_done_crc_o),
        .done_total_cycles(frame_done_total_cycles_o),
        .done_model_cycles(frame_done_model_cycles_o),
        .done_post_cycles(frame_done_post_cycles_o),
        .done_live(frame_done_live_o),
        .busy(frame_busy_o),
        .select_post(select_post_o),
        .cancel_all(cancel_all_o),
        .compute_fault_valid(frame_compute_fault_valid_o),
        .compute_fault_payload(frame_compute_fault_payload_o),
        .debug_stage(frame_debug_stage_o),
        .debug_op(frame_debug_op_o),
        .mem_req_valid(f_req_valid),
        .mem_req_ready(f_req_ready),
        .mem_req_write(f_req_write),
        .mem_req_verify(f_req_verify),
        .mem_req_offset(f_req_offset),
        .mem_req_tag(f_req_tag),
        .mem_req_beats(f_req_beats),
        .mem_req_client(f_req_client),
        .mem_w_valid(f_w_valid),
        .mem_w_ready(f_w_ready),
        .mem_w_data(f_w_data),
        .mem_w_strb(f_w_strb),
        .mem_w_last(f_w_last),
        .mem_r_valid(f_r_valid),
        .mem_r_ready(f_r_ready),
        .mem_r_data(f_r_data),
        .mem_r_last(f_r_last),
        .mem_rsp_valid(f_rsp_valid),
        .mem_rsp_ready(f_rsp_ready),
        .mem_rsp_status(f_rsp_status),
        .mem_rsp_tag(f_rsp_tag),
        .p_cmd_valid(p_cmd_valid),
        .p_cmd_ready(p_cmd_ready),
        .p_cmd_write(p_cmd_write),
        .p_cmd_offset(p_cmd_offset),
        .p_cmd_id(p_cmd_id),
        .p_cmd_epoch(p_cmd_epoch),
        .p_cmd_beats(p_cmd_beats),
        .p_cmd_client(p_cmd_client),
        .p_write_valid(p_write_valid),
        .p_write_ready(p_write_ready),
        .p_write_data(p_write_data),
        .p_write_strb(p_write_strb),
        .p_write_last(p_write_last),
        .p_read_valid(p_read_valid),
        .p_read_ready(p_read_ready),
        .p_read_data(p_read_data),
        .p_read_last(p_read_last),
        .p_done_valid(p_done_valid),
        .p_done_ready(p_done_ready),
        .p_done_status(p_done_status),
        .p_done_id(p_done_id),
        .p_done_epoch(p_done_epoch),
        .p_done_client(p_done_client),
        .p_abort_req(post_abort_o),
        .p_quarantined(post_quarantined_o),
        .post_fault_payload(frame_post_fault_payload_o)
    );
    b03_block_dma_compact #(.ALLOW_COMMAND_CYCLE_RESPONSE(ALLOW_COMMAND_CYCLE_RESPONSE)) u_blocks (
        .clk(clk_i),
        .rst_n(leaf_rst_n),
        .cancel_request(cancel_i || cancel_all_o),
        .bridge_fault(phase_quarantined_o || transport_fault_i),
        .epoch(epoch_i),
        .req_valid(f_req_valid),
        .req_ready(f_req_ready),
        .req_write(f_req_write),
        .req_verify(f_req_verify),
        .req_offset(f_req_offset),
        .req_tag(f_req_tag),
        .req_beats(f_req_beats),
        .req_client(f_req_client),
        .w_valid(f_w_valid),
        .w_ready(f_w_ready),
        .w_data(f_w_data),
        .w_strb(f_w_strb),
        .w_last(f_w_last),
        .r_valid(f_r_valid),
        .r_ready(f_r_ready),
        .r_data(f_r_data),
        .r_last(f_r_last),
        .rsp_valid(f_rsp_valid),
        .rsp_ready(f_rsp_ready),
        .rsp_status(f_rsp_status),
        .rsp_tag(f_rsp_tag),
        .cmd_valid(d_cmd_valid),
        .cmd_ready(d_cmd_ready),
        .cmd_write(d_cmd_write),
        .cmd_offset(d_cmd_offset),
        .cmd_id(d_cmd_id),
        .cmd_epoch(d_cmd_epoch),
        .cmd_beats(d_cmd_beats),
        .cmd_client(d_cmd_client),
        .write_valid(d_write_valid),
        .write_ready(d_write_ready),
        .write_data(d_write_data),
        .write_strb(d_write_strb),
        .write_last(d_write_last),
        .read_valid(d_read_valid),
        .read_ready(d_read_ready),
        .read_data(d_read_data),
        .read_last(d_read_last),
        .mem_done_valid(d_done_valid),
        .mem_done_ready(d_done_ready),
        .mem_done_status(d_done_status),
        .mem_done_id(d_done_id),
        .mem_done_epoch(d_done_epoch),
        .mem_done_client(d_done_client),
        .quarantined(dma_quarantined_o),
        .reset_required(dma_reset_required_o),
        .abort_req(dma_abort_req_o),
        .busy(dma_busy_o),
        .fault_valid(dma_fault_valid_o),
        .fault_ready(1'b1),
        .fault_payload(dma_fault_payload_o),
        .debug_state(dma_debug_state_o),
        .commands(dma_commands_o),
        .read_beats(dma_read_beats_o),
        .write_beats(dma_write_beats_o),
        .verify_offset(dma_verify_offset_o),
        .verify_expected(dma_verify_expected_o),
        .verify_actual(dma_verify_actual_o)
    );
    b03_phase_mem_mux_burst u_phase (
        .clk(clk_i),
        .rst_n(leaf_rst_n),
        .select_post(select_post_o),
        .cancel_request(cancel_i || cancel_all_o),
        .bridge_fault(transport_fault_i),
        .epoch(epoch_i),
        .d_cmd_valid(d_cmd_valid),
        .d_cmd_ready(d_cmd_ready),
        .d_cmd_write(d_cmd_write),
        .d_cmd_offset(d_cmd_offset),
        .d_cmd_id(d_cmd_id),
        .d_cmd_epoch(d_cmd_epoch),
        .d_cmd_beats(d_cmd_beats),
        .d_cmd_client(d_cmd_client),
        .d_abort_req(dma_abort_req_o),
        .d_write_valid(d_write_valid),
        .d_write_ready(d_write_ready),
        .d_write_data(d_write_data),
        .d_write_strb(d_write_strb),
        .d_write_last(d_write_last),
        .d_read_valid(d_read_valid),
        .d_read_ready(d_read_ready),
        .d_read_data(d_read_data),
        .d_read_last(d_read_last),
        .d_done_valid(d_done_valid),
        .d_done_ready(d_done_ready),
        .d_done_status(d_done_status),
        .d_done_id(d_done_id),
        .d_done_epoch(d_done_epoch),
        .d_done_client(d_done_client),
        .p_cmd_valid(p_cmd_valid),
        .p_cmd_ready(p_cmd_ready),
        .p_cmd_write(p_cmd_write),
        .p_cmd_offset(p_cmd_offset),
        .p_cmd_id(p_cmd_id),
        .p_cmd_epoch(p_cmd_epoch),
        .p_cmd_beats(p_cmd_beats),
        .p_cmd_client(p_cmd_client),
        .p_abort_req(post_abort_o),
        .p_write_valid(p_write_valid),
        .p_write_ready(p_write_ready),
        .p_write_data(p_write_data),
        .p_write_strb(p_write_strb),
        .p_write_last(p_write_last),
        .p_read_valid(p_read_valid),
        .p_read_ready(p_read_ready),
        .p_read_data(p_read_data),
        .p_read_last(p_read_last),
        .p_done_valid(p_done_valid),
        .p_done_ready(p_done_ready),
        .p_done_status(p_done_status),
        .p_done_id(p_done_id),
        .p_done_epoch(p_done_epoch),
        .p_done_client(p_done_client),
        .cmd_valid(c_cmd_valid_o),
        .cmd_ready(c_cmd_ready_i),
        .cmd_write(c_cmd_write_o),
        .cmd_offset(c_cmd_offset_o),
        .cmd_id(c_cmd_id_o),
        .cmd_epoch(c_cmd_epoch_o),
        .cmd_beats(c_cmd_beats_o),
        .cmd_client(c_cmd_client_o),
        .write_valid(c_write_valid_o),
        .write_ready(c_write_ready_i),
        .write_data(c_write_data_o),
        .write_strb(c_write_strb_o),
        .write_last(c_write_last_o),
        .read_valid(c_read_valid_i),
        .read_ready(c_read_ready_o),
        .read_data(c_read_data_i),
        .read_last(c_read_last_i),
        .mem_done_valid(c_done_valid_i),
        .mem_done_ready(c_done_ready_o),
        .mem_done_status(c_done_status_i),
        .mem_done_id(c_done_id_i),
        .mem_done_epoch(c_done_epoch_i),
        .mem_done_client(c_done_client_i),
        .fault_valid(phase_fault_valid_o),
        .fault_ready(1'b1),
        .fault_payload(phase_fault_payload_o),
        .quarantined(phase_quarantined_o),
        .reset_required(phase_reset_required_o),
        .abort_req(phase_abort_req_o),
        .busy(phase_busy_o),
        .debug_owner(phase_debug_owner_o),
        .debug_global_id(phase_debug_global_id_o),
        .commands(phase_commands_o),
        .completions(phase_completions_o)
    );
endmodule
`default_nettype wire
