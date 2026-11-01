// Independent free-clock supervisor; diagnostics are never session-reset.
module npu_session_supervisor #(
    parameter [31:0] RESET_HOLD_CYCLES=32'd270000,
    parameter [31:0] STARTUP_TIMEOUT_CYCLES=32'd270000000,
    parameter [31:0] ARM_TIMEOUT_CYCLES=32'd270000000,
    parameter [31:0] RUN_TIMEOUT_CYCLES=32'd3240000000,
    parameter [31:0] CLOCK_TIMEOUT_CYCLES=32'd270000,
    parameter [31:0] SNAPSHOT_TIMEOUT_CYCLES=32'd27000,
    parameter [31:0] SNAPSHOT_GRACE_CYCLES=32'd8,
    parameter [31:0] CALIB_STABLE_CYCLES=32'd8,
    parameter [31:0] MAX_AUTOMATIC_RECOVERIES=32'd3,
    parameter [31:0] INITIAL_EPOCH=32'd1
)(
    input wire free_clk,board_reset_n,compute_pll_lock,hmic_pll_lock,init_done,init_fail,align_error,
    input wire compute_active,ui_active,compute_fault,ui_fault,compute_heartbeat,ui_heartbeat,
    input wire suite_done,force_recover,
    output wire compute_arm_valid,input wire compute_arm_ready,output reg [31:0] compute_arm_epoch,
    output wire ui_arm_valid,input wire ui_arm_ready,output reg [31:0] ui_arm_epoch,output reg [31:0] session_epoch,
    input wire compute_ack_valid,input wire [31:0] compute_ack_epoch,
    input wire ui_ack_valid,input wire [31:0] ui_ack_epoch,
    input wire compute_report_valid,input wire [207:0] compute_report_data,
    input wire ui_report_valid,input wire [207:0] ui_report_data,
    output wire hmic_reset_n,session_reset_n,output wire run_enabled,terminal,
    output reg [31:0] recovery_count,fault_count,stale_messages,
    output reg fault_event,first_fault_valid,output reg [7:0] first_reason,last_reason,
    output reg [31:0] first_epoch,last_epoch,
    output reg [1:0] first_detail_mask,last_detail_mask,
    output reg [175:0] first_compute_payload,first_ui_payload,last_compute_payload,last_ui_payload
);
    localparam RESET=0,CALIBRATE=1,ARM=2,RUN=3,CAPTURE=4,TERMINAL=5;
    reg [2:0] state;
    (* syn_preserve=1 *) reg [2:0] release_pipe;
    always @(posedge free_clk or negedge board_reset_n)
        if(!board_reset_n)release_pipe<=0;else release_pipe<={release_pipe[1:0],1'b1};
    wire rst_n=release_pipe[2];
    (* syn_preserve=1 *) reg [10:0] status_meta,status_sync;
    reg [2:0] status_valid;
    always @(posedge free_clk or negedge rst_n)
        if(!rst_n)begin status_meta<=0;status_sync<=0;status_valid<=0;end
        else begin
            status_meta<={compute_heartbeat,ui_heartbeat,compute_fault,ui_fault,
                          compute_active,ui_active,align_error,init_fail,init_done,compute_pll_lock,hmic_pll_lock};
            status_sync<=status_meta;
            status_valid<={status_valid[1:0],1'b1};
        end
    assign hmic_reset_n=board_reset_n && rst_n && state!=RESET && state!=TERMINAL;
    assign session_reset_n=hmic_reset_n;
    assign run_enabled=rst_n && state==RUN;
    assign terminal=rst_n && state==TERMINAL;
    reg [31:0] timer,stable_count,c_dead,u_dead;
    reg c_hb,u_hb,saw_init_low,c_posted,u_posted,c_acked,u_acked,c_seen,u_seen,need_c,need_u;
    reg [175:0] c_payload,u_payload;
    reg [7:0] capture_reason;
    reg c_arm_pending,u_arm_pending;
    // Diagnostic mailboxes are board-reset only: keep even an old, unaccepted
    // offer stable across CAPTURE/session reset, then send the new epoch later.
    assign compute_arm_valid=c_arm_pending;
    assign ui_arm_valid=u_arm_pending;
    wire calibrated=status_sync[0] && status_sync[1] && status_sync[2] && !status_sync[3] && !status_sync[4];
    wire [7:0] health_reason=!status_sync[0] ? 8'd5 : !status_sync[1] ? 8'd6 :
        status_sync[3] ? 8'd8 : status_sync[4] ? 8'd9 : !status_sync[2] ? 8'd7 : 8'd0;
    wire c_report_match=compute_report_valid && compute_report_data[207:176]==session_epoch;
    wire u_report_match=ui_report_valid && ui_report_data[207:176]==session_epoch;
    wire c_available=c_seen || c_report_match,u_available=u_seen || u_report_match;
    wire [175:0] capture_c_payload=c_seen ? c_payload : compute_report_data[175:0];
    wire [175:0] capture_u_payload=u_seen ? u_payload : ui_report_data[175:0];
    wire [31:0] stale_now=(compute_ack_valid && compute_ack_epoch!=session_epoch)+
        (ui_ack_valid && ui_ack_epoch!=session_epoch)+
        (compute_report_valid && !c_report_match)+(ui_report_valid && !u_report_match);
    task begin_capture;
        input [7:0] reason;
        begin
            state<=CAPTURE;timer<=0;capture_reason<=reason;
            need_c<=status_sync[8] || reason==1;need_u<=status_sync[7] || reason==2;
        end
    endtask
    always @(posedge free_clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=RESET;timer<=0;stable_count<=0;c_dead<=0;u_dead<=0;c_hb<=0;u_hb<=0;saw_init_low<=0;
            c_posted<=0;u_posted<=0;c_acked<=0;u_acked<=0;c_seen<=0;u_seen<=0;need_c<=0;need_u<=0;
            c_payload<=0;u_payload<=0;capture_reason<=0;session_epoch<=INITIAL_EPOCH;
            c_arm_pending<=0;u_arm_pending<=0;compute_arm_epoch<=0;ui_arm_epoch<=0;
            recovery_count<=0;fault_count<=0;stale_messages<=0;fault_event<=0;first_fault_valid<=0;
            first_reason<=0;last_reason<=0;first_epoch<=0;last_epoch<=0;first_detail_mask<=0;last_detail_mask<=0;
            first_compute_payload<=0;first_ui_payload<=0;last_compute_payload<=0;last_ui_payload<=0;
        end else begin
            fault_event<=0;
            if(compute_arm_valid && compute_arm_ready)begin
                c_arm_pending<=0;
                if(state==ARM && compute_arm_epoch==session_epoch)c_posted<=1;
            end
            if(ui_arm_valid && ui_arm_ready)begin
                u_arm_pending<=0;
                if(state==ARM && ui_arm_epoch==session_epoch)u_posted<=1;
            end
            stale_messages<=stale_messages+stale_now;
            if(c_report_match && !c_seen)begin c_seen<=1;c_payload<=compute_report_data[175:0];end
            if(u_report_match && !u_seen)begin u_seen<=1;u_payload<=ui_report_data[175:0];end
            if(compute_ack_valid && compute_ack_epoch==session_epoch && state==ARM)c_acked<=1;
            if(ui_ack_valid && ui_ack_epoch==session_epoch && state==ARM)u_acked<=1;
            if(status_sync[10]!=c_hb)begin c_dead<=0;c_hb<=status_sync[10];end
            else if(c_dead!=32'hffffffff)c_dead<=c_dead+1'b1;
            if(status_sync[9]!=u_hb)begin u_dead<=0;u_hb<=status_sync[9];end
            else if(u_dead!=32'hffffffff)u_dead<=u_dead+1'b1;
            case(state)
            RESET:begin
                if(status_valid[2] && !status_sync[2])saw_init_low<=1;
                if(timer>=RESET_HOLD_CYCLES-1)begin state<=CALIBRATE;timer<=0;stable_count<=0;end
                else timer<=timer+1'b1;
            end
            CALIBRATE:begin
                if(status_valid[2] && !status_sync[2])saw_init_low<=1;
                if(status_sync[3] || status_sync[4])begin_capture(status_sync[3] ? 8'd8 : 8'd9);
                else if(timer>=STARTUP_TIMEOUT_CYCLES-1)begin_capture(8'd10);
                else if(saw_init_low && calibrated)begin
                    if(stable_count>=CALIB_STABLE_CYCLES-1)begin state<=ARM;timer<=0;c_posted<=0;u_posted<=0;c_acked<=0;u_acked<=0;end
                    else begin stable_count<=stable_count+1'b1;timer<=timer+1'b1;end
                end else begin stable_count<=0;timer<=timer+1'b1;end
            end
            ARM:begin
                if(!c_posted && !c_arm_pending)begin c_arm_pending<=1;compute_arm_epoch<=session_epoch;end
                if(!u_posted && !u_arm_pending)begin u_arm_pending<=1;ui_arm_epoch<=session_epoch;end
                if(status_sync[7] || u_seen || u_report_match)begin_capture(8'd2);
                else if(status_sync[8] || c_seen || c_report_match)begin_capture(8'd1);
                else if(!calibrated)begin_capture(health_reason);
                else if(c_acked && u_acked && status_sync[6] && status_sync[5])begin
                    state<=RUN;timer<=0;c_dead<=0;u_dead<=0;c_hb<=status_sync[10];u_hb<=status_sync[9];
                end else if(timer>=ARM_TIMEOUT_CYCLES-1)begin_capture(8'd11);
                else timer<=timer+1'b1;
            end
            RUN:begin
                if(status_sync[7] || u_seen || u_report_match)begin_capture(8'd2);
                else if(status_sync[8] || c_seen || c_report_match)begin_capture(8'd1);
                else if(!calibrated)begin_capture(health_reason);
                else if(c_dead>=CLOCK_TIMEOUT_CYCLES-1)begin_capture(8'd3);
                else if(u_dead>=CLOCK_TIMEOUT_CYCLES-1)begin_capture(8'd4);
                else if(force_recover)begin_capture(8'd13);
                else if(!suite_done && timer>=RUN_TIMEOUT_CYCLES-1)begin_capture(8'd12);
                else if(!suite_done)timer<=timer+1'b1;
            end
            CAPTURE:begin
                if(status_sync[8])need_c<=1;
                if(status_sync[7])need_u<=1;
                if((timer>=SNAPSHOT_GRACE_CYCLES-1 && (!need_c || c_available) && (!need_u || u_available)) ||
                    timer>=SNAPSHOT_TIMEOUT_CYCLES-1)begin
                    fault_event<=1;fault_count<=fault_count+1'b1;last_reason<=capture_reason;last_epoch<=session_epoch;
                    last_detail_mask<={u_available,c_available};last_compute_payload<=c_available ? capture_c_payload : 176'd0;
                    last_ui_payload<=u_available ? capture_u_payload : 176'd0;
                    if(!first_fault_valid)begin
                        first_fault_valid<=1;first_reason<=capture_reason;first_epoch<=session_epoch;
                        first_detail_mask<={u_available,c_available};first_compute_payload<=c_available ? capture_c_payload : 176'd0;
                        first_ui_payload<=u_available ? capture_u_payload : 176'd0;
                    end
                    if(session_epoch==32'hffffffff || recovery_count>=MAX_AUTOMATIC_RECOVERIES)state<=TERMINAL;
                    else begin
                        state<=RESET;recovery_count<=recovery_count+1'b1;session_epoch<=session_epoch+1'b1;
                        timer<=0;stable_count<=0;saw_init_low<=0;c_seen<=0;u_seen<=0;c_payload<=0;u_payload<=0;
                        c_posted<=0;u_posted<=0;c_acked<=0;u_acked<=0;
                    end
                end else timer<=timer+1'b1;
            end
            TERMINAL:state<=TERMINAL;
            default:state<=TERMINAL;
            endcase
        end
    end
endmodule
