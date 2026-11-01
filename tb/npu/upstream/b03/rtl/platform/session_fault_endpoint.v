// Diagnostic transport survives a session reset; only board reset clears it.
module session_fault_endpoint #(parameter integer HEARTBEAT_HALF_CYCLES=1024)(
    input wire domain_clk,free_clk,board_reset_n,session_reset_n,
    input wire arm_valid,output wire arm_ready,input wire [31:0] arm_epoch,
    output wire ack_valid,input wire ack_ready,output wire [31:0] ack_epoch,
    input wire fault_level,input wire [175:0] fault_payload,
    output wire report_valid,input wire report_ready,output wire [207:0] report_data,
    output reg heartbeat,output wire armed,output reg [31:0] domain_epoch
);
    (* syn_preserve=1 *) reg [2:0] release_pipe;
    always @(posedge domain_clk or negedge session_reset_n)
        if(!session_reset_n)release_pipe<=0;else release_pipe<={release_pipe[1:0],1'b1};
    wire local_session_n=release_pipe[2];
    wire arm_dvalid,arm_dready,arm_sa,arm_da;
    wire [31:0] arm_data;
    cdc_payload_mailbox #(.WIDTH(32)) arm_mailbox(
        .sclk(free_clk),.dclk(domain_clk),.srst_n(board_reset_n),.drst_n(board_reset_n),
        .s_valid(arm_valid),.s_ready(arm_ready),.s_data(arm_epoch),
        .d_valid(arm_dvalid),.d_ready(arm_dready),.d_data(arm_data),.s_active(arm_sa),.d_active(arm_da));
    reg armed_reg,ack_pending,fault_taken,fault_pending;
    reg [31:0] heartbeat_count;
    reg [207:0] saved_fault;
    wire ack_sready,ack_sa,ack_da,report_sready,report_sa,report_da;
    assign armed=armed_reg && local_session_n;
    assign arm_dready=local_session_n && !fault_pending && !ack_pending &&
                      (!armed_reg || arm_data!=domain_epoch);
    cdc_payload_mailbox #(.WIDTH(32)) ack_mailbox(
        .sclk(domain_clk),.dclk(free_clk),.srst_n(board_reset_n),.drst_n(board_reset_n),
        .s_valid(ack_pending),.s_ready(ack_sready),.s_data(domain_epoch),
        .d_valid(ack_valid),.d_ready(ack_ready),.d_data(ack_epoch),.s_active(ack_sa),.d_active(ack_da));
    cdc_payload_mailbox #(.WIDTH(208)) fault_mailbox(
        .sclk(domain_clk),.dclk(free_clk),.srst_n(board_reset_n),.drst_n(board_reset_n),
        .s_valid(fault_pending),.s_ready(report_sready),.s_data(saved_fault),
        .d_valid(report_valid),.d_ready(report_ready),.d_data(report_data),.s_active(report_sa),.d_active(report_da));
    always @(posedge domain_clk or negedge board_reset_n)begin
        if(!board_reset_n)begin
            armed_reg<=0;domain_epoch<=0;ack_pending<=0;fault_taken<=0;fault_pending<=0;
            saved_fault<=0;heartbeat_count<=0;heartbeat<=0;
        end else begin
            if(!local_session_n)begin armed_reg<=0;heartbeat_count<=0;heartbeat<=0;end
            else if(heartbeat_count==HEARTBEAT_HALF_CYCLES-1)begin heartbeat_count<=0;heartbeat<=~heartbeat;end
            else heartbeat_count<=heartbeat_count+1'b1;
            if(ack_pending && ack_sready)ack_pending<=0;
            if(fault_pending && report_sready)fault_pending<=0;
            if(arm_dvalid && arm_dready)begin
                armed_reg<=1;domain_epoch<=arm_data;ack_pending<=1;fault_taken<=0;
            end
            if(!(arm_dvalid && arm_dready) && armed && fault_level && !fault_taken && !fault_pending)begin
                saved_fault<={domain_epoch,fault_payload};fault_pending<=1;fault_taken<=1;
            end
        end
    end
endmodule
