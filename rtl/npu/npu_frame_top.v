`timescale 1ns/1ps
`default_nettype none
// CPU frame endpoint and autonomous B03 engine in the same 100 MHz domain.
// The unified service connects to npu_service_axi128 in the shared SoC.
// Publication permission comes from task retirement, never the NPR3 scope bit.
module npu_frame_top #(
    parameter integer ALLOW_COMMAND_CYCLE_RESPONSE = 1,
    parameter integer ENABLE_HARDWARE_POST = 1,
    parameter integer TRUSTED_MODEL = 0,
    parameter integer M_LANES = 16,
    parameter integer QUANTIZER_LANES = 2
) (
    input wire clk_i,
    input wire rst_ni,
    input wire healthy_i,
    input wire memory_fault_i,
    input wire model_sealed_i,
    input wire cancel_i,
    input wire host_write_valid_i,
    input wire publish_permission_i,
    input wire [31:0] epoch_i,
    input wire [31:0] addr_version_i,
    input wire [31:0] host_write_offset_i,
    input wire [4:0] host_write_beats_i,
    output wire irq_o,
    output wire fault_o,
    output wire port_idle_o,
    output wire abort_req_o,
    output wire [7:0] debug_stage_o,
    output wire [7:0] debug_op_o,
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
    input wire [2:0] c_done_client_i
);
    wire start_valid,start_ready,done_ready,mmio_fault;
    wire [1023:0] task_words;
    wire f_frame_done_valid_o;
    wire [31:0] f_frame_done_status_o;
    wire [31:0] f_frame_done_detail_o;
    wire [31:0] f_frame_done_cmd_id_o;
    wire [31:0] f_frame_done_epoch_o;
    wire [63:0] f_frame_done_frame_id_o;
    wire [11:0] f_frame_done_faces_o;
    wire [31:0] f_frame_done_result_offset_o;
    wire [31:0] f_frame_done_result_bytes_o;
    wire [31:0] f_frame_done_crc_o;
    wire [63:0] f_frame_done_total_cycles_o;
    wire [63:0] f_frame_done_model_cycles_o;
    wire [63:0] f_frame_done_post_cycles_o;
    wire f_frame_done_live_o;
    wire f_frame_busy_o;
    wire f_select_post_o;
    wire f_cancel_all_o;
    wire f_frame_compute_fault_valid_o;
    wire [175:0] f_frame_compute_fault_payload_o;
    wire [7:0] f_frame_debug_stage_o;
    wire [7:0] f_frame_debug_op_o;
    wire f_post_abort_o;
    wire f_post_quarantined_o;
    wire [175:0] f_frame_post_fault_payload_o;
    wire f_dma_quarantined_o;
    wire f_dma_reset_required_o;
    wire f_dma_abort_req_o;
    wire f_dma_busy_o;
    wire f_dma_fault_valid_o;
    wire [175:0] f_dma_fault_payload_o;
    wire [3:0] f_dma_debug_state_o;
    wire [31:0] f_dma_commands_o;
    wire [31:0] f_dma_read_beats_o;
    wire [31:0] f_dma_write_beats_o;
    wire [31:0] f_dma_verify_offset_o;
    wire [31:0] f_dma_verify_expected_o;
    wire [31:0] f_dma_verify_actual_o;
    wire f_phase_fault_valid_o;
    wire [175:0] f_phase_fault_payload_o;
    wire f_phase_quarantined_o;
    wire f_phase_reset_required_o;
    wire f_phase_abort_req_o;
    wire f_phase_busy_o;
    wire [1:0] f_phase_debug_owner_o;
    wire [31:0] f_phase_debug_global_id_o;
    wire [31:0] f_phase_commands_o;
    wire [31:0] f_phase_completions_o;
    wire service_idle = !f_dma_busy_o && !f_phase_busy_o;
    wire service_fault = f_frame_compute_fault_valid_o || f_dma_quarantined_o || f_phase_quarantined_o || f_post_quarantined_o;
    assign fault_o = mmio_fault || service_fault;
    assign port_idle_o = service_idle && !f_frame_busy_o;
    assign abort_req_o = f_phase_abort_req_o;
    assign debug_stage_o = f_frame_debug_stage_o;
    assign debug_op_o = f_frame_debug_op_o;
    npu_frame_mmio #(.ENABLE_HARDWARE_POST(ENABLE_HARDWARE_POST)) u_control (
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
        .platform_healthy_i(healthy_i && model_sealed_i && !service_fault),
        .session_epoch_i(epoch_i),
        .addr_version_i(addr_version_i),
        .start_valid_o(start_valid),
        .start_ready_i(start_ready),
        .task_words_o(task_words),
        .done_valid_i(f_frame_done_valid_o && service_idle),
        .done_ready_o(done_ready),
        .done_status_i(f_frame_done_status_o),
        .done_detail_i(f_frame_done_detail_o),
        .done_cmd_i(f_frame_done_cmd_id_o),
        .done_epoch_i(f_frame_done_epoch_o),
        .done_frame_i(f_frame_done_frame_id_o),
        .done_faces_i(f_frame_done_faces_o),
        .done_result_offset_i(f_frame_done_result_offset_o),
        .done_result_bytes_i(f_frame_done_result_bytes_o),
        .done_crc_i(f_frame_done_crc_o),
        .done_total_cycles_i(f_frame_done_total_cycles_o),
        .done_model_cycles_i(f_frame_done_model_cycles_o),
        .done_post_cycles_i(f_frame_done_post_cycles_o),
        .done_live_i(f_frame_done_live_o),
        .done_publish_i(publish_permission_i && service_idle),
        .irq_o(irq_o),
        .fault_o(mmio_fault)
    );
    // MMIO admits only the three generated layouts and freezes the task.
    // The generated memory map independently enforces bounds/disjointness.
    b03_frame_service #(.ALLOW_COMMAND_CYCLE_RESPONSE(ALLOW_COMMAND_CYCLE_RESPONSE),.ENABLE_HARDWARE_POST(ENABLE_HARDWARE_POST),.TRUSTED_MODEL(TRUSTED_MODEL),.PREVALIDATED_TASK_LAYOUT(1),.M_LANES(M_LANES),.QUANTIZER_LANES(QUANTIZER_LANES)) u_service (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .session_reset_ni(rst_ni),
        .compute_running_i(healthy_i && model_sealed_i),
        .cancel_i(cancel_i || mmio_fault),
        .epoch_i(epoch_i),
        .addr_version_i(addr_version_i),
        .host_write_valid_i(host_write_valid_i),
        .host_write_offset_i(host_write_offset_i),
        .host_write_beats_i(host_write_beats_i),
        .task_words_i(task_words),
        .frame_done_valid_o(f_frame_done_valid_o),
        .done_ready_i(done_ready && service_idle),
        .frame_done_status_o(f_frame_done_status_o),
        .frame_done_detail_o(f_frame_done_detail_o),
        .frame_done_cmd_id_o(f_frame_done_cmd_id_o),
        .frame_done_epoch_o(f_frame_done_epoch_o),
        .frame_done_frame_id_o(f_frame_done_frame_id_o),
        .frame_done_faces_o(f_frame_done_faces_o),
        .frame_done_result_offset_o(f_frame_done_result_offset_o),
        .frame_done_result_bytes_o(f_frame_done_result_bytes_o),
        .frame_done_crc_o(f_frame_done_crc_o),
        .frame_done_total_cycles_o(f_frame_done_total_cycles_o),
        .frame_done_model_cycles_o(f_frame_done_model_cycles_o),
        .frame_done_post_cycles_o(f_frame_done_post_cycles_o),
        .frame_done_live_o(f_frame_done_live_o),
        .frame_busy_o(f_frame_busy_o),
        .select_post_o(f_select_post_o),
        .cancel_all_o(f_cancel_all_o),
        .frame_compute_fault_valid_o(f_frame_compute_fault_valid_o),
        .frame_compute_fault_payload_o(f_frame_compute_fault_payload_o),
        .frame_debug_stage_o(f_frame_debug_stage_o),
        .frame_debug_op_o(f_frame_debug_op_o),
        .post_abort_o(f_post_abort_o),
        .post_quarantined_o(f_post_quarantined_o),
        .frame_post_fault_payload_o(f_frame_post_fault_payload_o),
        .dma_quarantined_o(f_dma_quarantined_o),
        .dma_reset_required_o(f_dma_reset_required_o),
        .dma_abort_req_o(f_dma_abort_req_o),
        .dma_busy_o(f_dma_busy_o),
        .dma_fault_valid_o(f_dma_fault_valid_o),
        .dma_fault_payload_o(f_dma_fault_payload_o),
        .dma_debug_state_o(f_dma_debug_state_o),
        .dma_commands_o(f_dma_commands_o),
        .dma_read_beats_o(f_dma_read_beats_o),
        .dma_write_beats_o(f_dma_write_beats_o),
        .dma_verify_offset_o(f_dma_verify_offset_o),
        .dma_verify_expected_o(f_dma_verify_expected_o),
        .dma_verify_actual_o(f_dma_verify_actual_o),
        .transport_fault_i(memory_fault_i),
        .c_cmd_valid_o(c_cmd_valid_o),
        .c_cmd_ready_i(c_cmd_ready_i),
        .c_cmd_write_o(c_cmd_write_o),
        .c_cmd_offset_o(c_cmd_offset_o),
        .c_cmd_id_o(c_cmd_id_o),
        .c_cmd_epoch_o(c_cmd_epoch_o),
        .c_cmd_beats_o(c_cmd_beats_o),
        .c_cmd_client_o(c_cmd_client_o),
        .c_write_valid_o(c_write_valid_o),
        .c_write_ready_i(c_write_ready_i),
        .c_write_data_o(c_write_data_o),
        .c_write_strb_o(c_write_strb_o),
        .c_write_last_o(c_write_last_o),
        .c_read_valid_i(c_read_valid_i),
        .c_read_ready_o(c_read_ready_o),
        .c_read_data_i(c_read_data_i),
        .c_read_last_i(c_read_last_i),
        .c_done_valid_i(c_done_valid_i),
        .c_done_ready_o(c_done_ready_o),
        .c_done_status_i(c_done_status_i),
        .c_done_id_i(c_done_id_i),
        .c_done_epoch_i(c_done_epoch_i),
        .c_done_client_i(c_done_client_i),
        .phase_fault_valid_o(f_phase_fault_valid_o),
        .phase_fault_payload_o(f_phase_fault_payload_o),
        .phase_quarantined_o(f_phase_quarantined_o),
        .phase_reset_required_o(f_phase_reset_required_o),
        .phase_abort_req_o(f_phase_abort_req_o),
        .phase_busy_o(f_phase_busy_o),
        .phase_debug_owner_o(f_phase_debug_owner_o),
        .phase_debug_global_id_o(f_phase_debug_global_id_o),
        .phase_commands_o(f_phase_commands_o),
        .phase_completions_o(f_phase_completions_o),
        .start_i(start_valid),
        .start_ready_o(start_ready)
    );
endmodule
`default_nettype wire
