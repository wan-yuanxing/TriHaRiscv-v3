// Single outstanding write burst, compute 100 MHz <-> native UI 125 MHz.
// Reset inputs represent a coordinated whole native/FIFO session reset.
module npu_write_bridge_burst #(
    parameter integer COLLECT_STALL_LIMIT=1000000,
    parameter integer NATIVE_STALL_LIMIT=1000000,
    parameter [31:0] INITIAL_TAG=32'd1
)(
    input wire compute_clk,ui_clk,compute_reset_n,ui_reset_n,
    input wire init_done,init_fail,align_error,
    input wire cmd_valid,output wire cmd_ready,
    input wire [31:0] cmd_offset,cmd_id,cmd_epoch,
    input wire [4:0] cmd_beats,input wire [2:0] cmd_client,
    input wire data_valid,output wire data_ready,
    input wire [255:0] data,input wire [31:0] strb,input wire last,input wire abort_req,
    output wire done_valid,input wire done_ready,output wire [3:0] done_status,
    output wire [31:0] done_id,done_epoch,output wire [2:0] done_client,
    output wire session_reset_req,ui_session_reset_req,output wire [3:0] ui_fault_code,
    output wire compute_active,ui_active,output reg tag_exhausted,
    output wire awvalid,input wire awready,output wire [27:0] awaddr,output wire [3:0] awlen,
    input wire wready,input wire [3:0] wid,input wire wlast,
    output wire [255:0] wdata,output wire [31:0] wstrb,
    output wire [5:0] tx_level_ui
);
    wire arst_n=compute_reset_n && ui_reset_n;
    (* syn_preserve=1 *) reg [2:0] c_release,u_release;
    always @(posedge compute_clk or negedge arst_n)
        if(!arst_n)c_release<=0;else c_release<={c_release[1:0],1'b1};
    always @(posedge ui_clk or negedge arst_n)
        if(!arst_n)u_release<=0;else u_release<={u_release[1:0],1'b1};
    wire c_rst_n=c_release[2],u_rst_n=u_release[2];
    wire fwvalid,fwready,fwlast,frvalid,frready,frlast,fwactive,fractive;
    wire [255:0] fwdata,frdata;
    wire [31:0] fwstrb,frstrb;
    wire [5:0] wfree,available;
    async_fifo256_probe tx_fifo(.wclk(compute_clk),.rclk(ui_clk),
        .wrst_n(compute_reset_n),.rrst_n(ui_reset_n),
        .wvalid(fwvalid),.wready(fwready),.wdata(fwdata),.wstrb(fwstrb),.wlast(fwlast),
        .rvalid(frvalid),.rready(frready),.rdata(frdata),.rstrb(frstrb),.rlast(frlast),
        .wfree(wfree),.ravailable(available),.wactive(fwactive),.ractive(fractive));

    wire packet_valid,packet_ready,abort_pending,collector_req,collector_cmd_ready;
    wire [31:0] packet_offset,packet_id,packet_epoch;
    wire [4:0] packet_beats,collected;
    wire [2:0] packet_client;
    wire collector_release_valid,collector_release_ready;
    wire [135:0] cmd_bundle;
    wire cmd_dvalid,cmd_dready,cmd_sactive,cmd_dactive;
    reg [31:0] active_tag,next_tag;
    reg local_active,packet_posted,abort_sent,wrapper_fault;
    (* syn_preserve=1 *) reg ui_fault_meta,ui_fault_sync;
    always @(posedge compute_clk or negedge c_rst_n)
        if(!c_rst_n)begin ui_fault_meta<=0;ui_fault_sync<=0;end
        else begin ui_fault_meta<=ui_session_reset_req;ui_fault_sync<=ui_fault_meta;end
    assign session_reset_req=collector_req || wrapper_fault || ui_fault_sync ||
                             (tag_exhausted && !local_active);
    assign cmd_ready=collector_cmd_ready && !session_reset_req && !tag_exhausted;
    wire local_cmd_fire=cmd_valid && cmd_ready;

    cdc_payload_mailbox #(.WIDTH(136)) command_cdc(
        .sclk(compute_clk),.dclk(ui_clk),.srst_n(compute_reset_n),.drst_n(ui_reset_n),
        .s_valid(packet_valid),.s_ready(packet_ready),
        .s_data({active_tag,packet_offset,packet_beats,packet_id,packet_epoch,packet_client}),
        .d_valid(cmd_dvalid),.d_ready(cmd_dready),.d_data(cmd_bundle),
        .s_active(cmd_sactive),.d_active(cmd_dactive));

    wire cancel_svalid,cancel_sready,cancel_dvalid,cancel_sactive,cancel_dactive;
    wire [31:0] cancel_tag;
    assign cancel_svalid=local_active && packet_posted && abort_pending && !abort_sent;
    cdc_payload_mailbox #(.WIDTH(32)) cancel_cdc(
        .sclk(compute_clk),.dclk(ui_clk),.srst_n(compute_reset_n),.drst_n(ui_reset_n),
        .s_valid(cancel_svalid),.s_ready(cancel_sready),.s_data(active_tag),
        .d_valid(cancel_dvalid),.d_ready(ui_active),.d_data(cancel_tag),
        .s_active(cancel_sactive),.d_active(cancel_dactive));

    wire rsp_svalid,rsp_sready,rsp_dvalid,rsp_dready,rsp_sactive,rsp_dactive;
    wire [31:0] rsp_tag,rsp_id,rsp_epoch;
    wire [2:0] rsp_client;
    wire [3:0] rsp_status;
    wire [102:0] response_bundle;
    wire [31:0] return_tag,return_id,return_epoch;
    wire [2:0] return_client;
    wire [3:0] return_status;
    assign {return_tag,return_id,return_epoch,return_client,return_status}=response_bundle;
    wire tag_matches=local_active && packet_posted && return_tag==active_tag;
    assign collector_release_valid=rsp_dvalid && tag_matches;
    assign rsp_dready=tag_matches ? collector_release_ready : 1'b1;
    cdc_payload_mailbox #(.WIDTH(103)) completion_cdc(
        .sclk(ui_clk),.dclk(compute_clk),.srst_n(ui_reset_n),.drst_n(compute_reset_n),
        .s_valid(rsp_svalid),.s_ready(rsp_sready),
        .s_data({rsp_tag,rsp_id,rsp_epoch,rsp_client,rsp_status}),
        .d_valid(rsp_dvalid),.d_ready(rsp_dready),.d_data(response_bundle),
        .s_active(rsp_sactive),.d_active(rsp_dactive));
    assign compute_active=fwactive && cmd_sactive && rsp_dactive && cancel_sactive;
    assign ui_active=fractive && cmd_dactive && rsp_sactive && cancel_dactive;

    tx_packet_collector_burst #(.STALL_LIMIT(COLLECT_STALL_LIMIT)) collector(
        .clk(compute_clk),.rst_n(c_rst_n),.link_active(compute_active),
        .cmd_valid(cmd_valid && !session_reset_req && !tag_exhausted),.cmd_ready(collector_cmd_ready),
        .cmd_offset(cmd_offset),.cmd_beats(cmd_beats),.cmd_id(cmd_id),.cmd_epoch(cmd_epoch),.cmd_client(cmd_client),
        .data_valid(data_valid),.data_ready(data_ready),.data(data),.strb(strb),.last(last),
        .fifo_valid(fwvalid),.fifo_ready(fwready),.fifo_free(wfree),.fifo_data(fwdata),.fifo_strb(fwstrb),.fifo_last(fwlast),
        .packet_valid(packet_valid),.packet_ready(packet_ready),.packet_offset(packet_offset),.packet_beats(packet_beats),
        .packet_id(packet_id),.packet_epoch(packet_epoch),.packet_client(packet_client),
        .abort_req(abort_req),.abort_pending(abort_pending),
        .release_valid(collector_release_valid),.release_ready(collector_release_ready),
        .release_id(return_id),.release_epoch(return_epoch),.release_client(return_client),.release_status(return_status),
        .done_valid(done_valid),.done_ready(done_ready),.done_status(done_status),
        .session_reset_required(collector_req),.collected_beats(collected));
    assign done_id=packet_id;
    assign done_epoch=packet_epoch;
    assign done_client=packet_client;
    native_tx_writer #(.STALL_LIMIT(NATIVE_STALL_LIMIT)) writer(
        .clk(ui_clk),.rst_n(u_rst_n),.link_active(ui_active),
        .init_done(init_done),.init_fail(init_fail),.align_error(align_error),
        .cmd_valid(cmd_dvalid),.cmd_ready(cmd_dready),
        .cmd_tag(cmd_bundle[135:104]),.cmd_offset(cmd_bundle[103:72]),.cmd_beats(cmd_bundle[71:67]),
        .cmd_id(cmd_bundle[66:35]),.cmd_epoch(cmd_bundle[34:3]),.cmd_client(cmd_bundle[2:0]),
        .cancel_valid(cancel_dvalid && ui_active),.cancel_tag(cancel_tag),
        .fifo_valid(frvalid),.fifo_ready(frready),.fifo_available(available),
        .fifo_data(frdata),.fifo_strb(frstrb),.fifo_last(frlast),
        .awvalid(awvalid),.awready(awready),.awaddr(awaddr),.awlen(awlen),
        .wready(wready),.wid(wid),.wlast(wlast),.wdata(wdata),.wstrb(wstrb),
        .rsp_valid(rsp_svalid),.rsp_ready(rsp_sready),.rsp_tag(rsp_tag),.rsp_id(rsp_id),
        .rsp_epoch(rsp_epoch),.rsp_client(rsp_client),.rsp_status(rsp_status),
        .session_reset_req(ui_session_reset_req),.fault_code(ui_fault_code));

    always @(posedge compute_clk or negedge c_rst_n)begin
        if(!c_rst_n)begin
            active_tag<=0;next_tag<=INITIAL_TAG;tag_exhausted<=0;
            local_active<=0;packet_posted<=0;abort_sent<=0;wrapper_fault<=0;
        end else begin
            if(local_cmd_fire)begin
                active_tag<=next_tag;local_active<=1;packet_posted<=0;abort_sent<=0;
                if(next_tag==32'hffffffff)tag_exhausted<=1;
                else next_tag<=next_tag+1'b1;
            end
            if(packet_valid && packet_ready)packet_posted<=1;
            if(cancel_svalid && cancel_sready)abort_sent<=1;
            if(rsp_dvalid && rsp_dready && !tag_matches)wrapper_fault<=1;
            if(done_valid && done_ready)local_active<=0;
        end
    end
    assign tx_level_ui=available;
endmodule
