// Complete memory bridge under independent, bounded, whole-session recovery.
module npu_session_mem_bridge_burst #(
    parameter integer HEARTBEAT_HALF_CYCLES=1024,
    parameter integer COLLECT_STALL_LIMIT=1000000,NATIVE_STALL_LIMIT=1000000,LOCAL_STALL_LIMIT=1000000,
    parameter [31:0] RESET_HOLD_CYCLES=32'd270000,STARTUP_TIMEOUT_CYCLES=32'd270000000,
    parameter [31:0] ARM_TIMEOUT_CYCLES=32'd270000000,RUN_TIMEOUT_CYCLES=32'd3240000000,
    parameter [31:0] CLOCK_TIMEOUT_CYCLES=32'd270000,SNAPSHOT_TIMEOUT_CYCLES=32'd27000,
    parameter [31:0] SNAPSHOT_GRACE_CYCLES=32'd8,CALIB_STABLE_CYCLES=32'd8,
    parameter [31:0] MAX_AUTOMATIC_RECOVERIES=32'd3,INITIAL_EPOCH=32'd1
)(
    input wire free_clk,compute_clk,ui_clk,board_reset_n,compute_pll_lock,hmic_pll_lock,init_done,init_fail,align_error,
    input wire suite_done,force_recover,
    input wire compute_fault_valid,ui_fault_valid,input wire [175:0] compute_fault_payload,ui_fault_payload,
    output wire hmic_reset_n,session_reset_n,run_enabled,compute_running,terminal,
    output wire [31:0] session_epoch,compute_epoch,recovery_count,fault_count,stale_messages,
    output wire fault_event,first_fault_valid,output wire [7:0] first_reason,last_reason,
    output wire [31:0] first_epoch,last_epoch,output wire [1:0] first_detail_mask,last_detail_mask,
    output wire [175:0] first_compute_payload,first_ui_payload,last_compute_payload,last_ui_payload,
    input wire cmd_valid,output wire cmd_ready,input wire cmd_write,
    input wire [31:0] cmd_offset,cmd_id,cmd_epoch,input wire [4:0] cmd_beats,input wire [2:0] cmd_client,
    input wire write_valid,output wire write_ready,input wire [255:0] write_data,input wire [31:0] write_strb,input wire write_last,
    output wire read_valid,input wire read_ready,output wire [255:0] read_data,output wire read_last,
    input wire abort_req,output wire done_valid,input wire done_ready,output wire [3:0] done_status,
    output wire [31:0] done_id,done_epoch,output wire [2:0] done_client,
    output wire busy,owner_write,compute_active,ui_active,session_reset_req,ui_session_reset_req,
    output wire [3:0] write_fault_code,read_fault_code,
    output wire awvalid,input wire awready,output wire [27:0] awaddr,output wire [3:0] awlen,
    input wire wready,input wire [3:0] wid,input wire wlast,output wire [255:0] wdata,output wire [31:0] wstrb,
    output wire arvalid,input wire arready,output wire [27:0] araddr,output wire [3:0] arlen,
    input wire rvalid,input wire [255:0] rdata,input wire [3:0] rid,input wire rlast,
    output wire [5:0] tx_level_ui,rx_level_ui,output wire [31:0] monitor_ui_epoch,output wire monitor_ui_armed
);
    wire c_arm_valid,c_arm_ready,u_arm_valid,u_arm_ready,c_ack_valid,u_ack_valid,c_report_valid,u_report_valid;
    wire [31:0] c_ack_epoch,u_ack_epoch,ui_epoch,c_arm_epoch,u_arm_epoch;
    wire [207:0] c_report,u_report;
    wire c_heartbeat,u_heartbeat,c_armed,u_armed;
    (* syn_preserve=1 *) reg run_meta,run_sync;
    reg producer_rearmed;
    always @(posedge compute_clk or negedge session_reset_n)
        if(!session_reset_n)begin run_meta<=0;run_sync<=0;producer_rearmed<=0;end
        else begin
            run_meta<=run_enabled;run_sync<=run_meta;
            if(!run_sync)producer_rearmed<=0;
            else if(!cmd_valid)producer_rearmed<=1;
        end
    assign compute_running=run_sync && c_armed;
    wire allow_command=compute_running && producer_rearmed;
    wire bridge_cmd_ready;
    assign cmd_ready=allow_command && bridge_cmd_ready;
    reg [31:0] meta_offset,meta_id,meta_epoch;
    reg meta_write;
    reg [2:0] meta_client;
    always @(posedge compute_clk or negedge session_reset_n)
        if(!session_reset_n)begin meta_offset<=0;meta_id<=0;meta_epoch<=0;meta_write<=0;meta_client<=0;end
        else if(cmd_valid && cmd_ready)begin
            meta_offset<=cmd_offset;meta_id<=cmd_id;meta_epoch<=cmd_epoch;meta_write<=cmd_write;meta_client<=cmd_client;
        end
    wire c_fault=compute_fault_valid || session_reset_req;
    wire u_fault=ui_fault_valid || ui_session_reset_req;
    wire [175:0] c_payload=compute_fault_valid ? compute_fault_payload :
        {8'd1,{busy,3'd0,meta_write,meta_client},meta_offset,meta_id,meta_epoch,32'd0,32'd0};
    wire [175:0] u_payload=ui_fault_valid ? ui_fault_payload :
        {4'd0,(write_fault_code!=0 ? write_fault_code : read_fault_code),4'd0,(write_fault_code!=0),3'd0,
         32'd0,32'd0,32'd0,32'd0,32'd0};
    session_fault_endpoint #(.HEARTBEAT_HALF_CYCLES(HEARTBEAT_HALF_CYCLES)) compute_endpoint(
        .domain_clk(compute_clk),.free_clk(free_clk),.board_reset_n(board_reset_n),.session_reset_n(session_reset_n),
        .arm_valid(c_arm_valid),.arm_ready(c_arm_ready),.arm_epoch(c_arm_epoch),
        .ack_valid(c_ack_valid),.ack_ready(1'b1),.ack_epoch(c_ack_epoch),.fault_level(c_fault),.fault_payload(c_payload),
        .report_valid(c_report_valid),.report_ready(1'b1),.report_data(c_report),
        .heartbeat(c_heartbeat),.armed(c_armed),.domain_epoch(compute_epoch));
    session_fault_endpoint #(.HEARTBEAT_HALF_CYCLES(HEARTBEAT_HALF_CYCLES)) ui_endpoint(
        .domain_clk(ui_clk),.free_clk(free_clk),.board_reset_n(board_reset_n),.session_reset_n(session_reset_n),
        .arm_valid(u_arm_valid),.arm_ready(u_arm_ready),.arm_epoch(u_arm_epoch),
        .ack_valid(u_ack_valid),.ack_ready(1'b1),.ack_epoch(u_ack_epoch),.fault_level(u_fault),.fault_payload(u_payload),
        .report_valid(u_report_valid),.report_ready(1'b1),.report_data(u_report),
        .heartbeat(u_heartbeat),.armed(u_armed),.domain_epoch(ui_epoch));
    npu_session_supervisor #(.RESET_HOLD_CYCLES(RESET_HOLD_CYCLES),.STARTUP_TIMEOUT_CYCLES(STARTUP_TIMEOUT_CYCLES),
        .ARM_TIMEOUT_CYCLES(ARM_TIMEOUT_CYCLES),.RUN_TIMEOUT_CYCLES(RUN_TIMEOUT_CYCLES),.CLOCK_TIMEOUT_CYCLES(CLOCK_TIMEOUT_CYCLES),
        .SNAPSHOT_TIMEOUT_CYCLES(SNAPSHOT_TIMEOUT_CYCLES),.SNAPSHOT_GRACE_CYCLES(SNAPSHOT_GRACE_CYCLES),
        .CALIB_STABLE_CYCLES(CALIB_STABLE_CYCLES),.MAX_AUTOMATIC_RECOVERIES(MAX_AUTOMATIC_RECOVERIES),.INITIAL_EPOCH(INITIAL_EPOCH)) supervisor(
        .free_clk(free_clk),.board_reset_n(board_reset_n),.compute_pll_lock(compute_pll_lock),.hmic_pll_lock(hmic_pll_lock),
        .init_done(init_done),.init_fail(init_fail),.align_error(align_error),.compute_active(compute_active),.ui_active(ui_active),
        .compute_fault(c_fault),.ui_fault(u_fault),.compute_heartbeat(c_heartbeat),.ui_heartbeat(u_heartbeat),
        .suite_done(suite_done),.force_recover(force_recover),.compute_arm_valid(c_arm_valid),.compute_arm_ready(c_arm_ready),
        .compute_arm_epoch(c_arm_epoch),.ui_arm_valid(u_arm_valid),.ui_arm_ready(u_arm_ready),.ui_arm_epoch(u_arm_epoch),.session_epoch(session_epoch),
        .compute_ack_valid(c_ack_valid),.compute_ack_epoch(c_ack_epoch),.ui_ack_valid(u_ack_valid),.ui_ack_epoch(u_ack_epoch),
        .compute_report_valid(c_report_valid),.compute_report_data(c_report),.ui_report_valid(u_report_valid),.ui_report_data(u_report),
        .hmic_reset_n(hmic_reset_n),.session_reset_n(session_reset_n),.run_enabled(run_enabled),.terminal(terminal),
        .recovery_count(recovery_count),.fault_count(fault_count),.stale_messages(stale_messages),.fault_event(fault_event),
        .first_fault_valid(first_fault_valid),.first_reason(first_reason),.last_reason(last_reason),.first_epoch(first_epoch),.last_epoch(last_epoch),
        .first_detail_mask(first_detail_mask),.last_detail_mask(last_detail_mask),.first_compute_payload(first_compute_payload),
        .first_ui_payload(first_ui_payload),.last_compute_payload(last_compute_payload),.last_ui_payload(last_ui_payload));
    npu_mem_bridge_burst #(.COLLECT_STALL_LIMIT(COLLECT_STALL_LIMIT),.NATIVE_STALL_LIMIT(NATIVE_STALL_LIMIT),.LOCAL_STALL_LIMIT(LOCAL_STALL_LIMIT)) bridge(
        .compute_clk(compute_clk),.ui_clk(ui_clk),.compute_reset_n(session_reset_n),.ui_reset_n(session_reset_n),
        .init_done(init_done),.init_fail(init_fail),.align_error(align_error),
        .cmd_valid(cmd_valid && allow_command),.cmd_ready(bridge_cmd_ready),.cmd_write(cmd_write),
        .cmd_offset(cmd_offset),.cmd_id(cmd_id),.cmd_epoch(cmd_epoch),.cmd_beats(cmd_beats),.cmd_client(cmd_client),
        .write_valid(write_valid),.write_ready(write_ready),.write_data(write_data),.write_strb(write_strb),.write_last(write_last),
        .read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),.read_last(read_last),
        .abort_req(abort_req),.done_valid(done_valid),.done_ready(done_ready),.done_status(done_status),
        .done_id(done_id),.done_epoch(done_epoch),.done_client(done_client),.busy(busy),.owner_write(owner_write),
        .compute_active(compute_active),.ui_active(ui_active),.session_reset_req(session_reset_req),.ui_session_reset_req(ui_session_reset_req),
        .write_fault_code(write_fault_code),.read_fault_code(read_fault_code),
        .awvalid(awvalid),.awready(awready),.awaddr(awaddr),.awlen(awlen),.wready(wready),.wid(wid),.wlast(wlast),.wdata(wdata),.wstrb(wstrb),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arlen(arlen),.rvalid(rvalid),.rdata(rdata),.rid(rid),.rlast(rlast),.tx_level_ui(tx_level_ui),.rx_level_ui(rx_level_ui));
    assign monitor_ui_epoch=ui_epoch;
    assign monitor_ui_armed=u_armed;
endmodule
