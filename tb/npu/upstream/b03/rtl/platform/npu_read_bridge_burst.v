// One read burst across compute/UI. Native completion is not local completion.
module npu_read_bridge_burst #(
    parameter integer NATIVE_STALL_LIMIT=1000000,
    parameter integer LOCAL_STALL_LIMIT=1000000,
    parameter [31:0] INITIAL_TAG=32'd1
)(
    input wire compute_clk,ui_clk,compute_reset_n,ui_reset_n,
    input wire init_done,init_fail,align_error,
    input wire cmd_valid,output wire cmd_ready,
    input wire [31:0] cmd_offset,cmd_id,cmd_epoch,
    input wire [4:0] cmd_beats,input wire [2:0] cmd_client,
    output wire data_valid,input wire data_ready,output wire [255:0] data,
    output wire last,input wire abort_req,
    output wire done_valid,input wire done_ready,output reg [3:0] done_status,
    output reg [31:0] done_id,done_epoch,output reg [2:0] done_client,
    output wire session_reset_req,ui_session_reset_req,output wire [3:0] ui_fault_code,
    output wire compute_active,ui_active,output reg tag_exhausted,
    output wire arvalid,input wire arready,output wire [27:0] araddr,output wire [3:0] arlen,
    input wire rvalid,input wire [255:0] rdata,input wire [3:0] rid,input wire rlast,
    output wire [5:0] rx_level_ui
);
    localparam IDLE=0,POST=1,ACTIVE=2,DONE=3;
    reg [1:0] state;
    wire arst_n=compute_reset_n && ui_reset_n;
    (* syn_preserve=1 *) reg [2:0] c_release,u_release;
    always @(posedge compute_clk or negedge arst_n)
        if(!arst_n)c_release<=0;else c_release<={c_release[1:0],1'b1};
    always @(posedge ui_clk or negedge arst_n)
        if(!arst_n)u_release<=0;else u_release<={u_release[1:0],1'b1};
    wire c_rst_n=c_release[2],u_rst_n=u_release[2];
    reg [31:0] offset,active_tag,next_tag,stalled;
    reg [4:0] beats,popped,returned_count;
    reg [3:0] returned_status;
    reg cancelled,cancel_sent,exposed,reply_seen,wrapper_fault;
    (* syn_preserve=1 *) reg fault_meta,fault_sync;
    always @(posedge compute_clk or negedge c_rst_n)
        if(!c_rst_n)begin fault_meta<=0;fault_sync<=0;end
        else begin fault_meta<=ui_session_reset_req;fault_sync<=fault_meta;end
    assign session_reset_req=wrapper_fault || fault_sync || (tag_exhausted && state==IDLE);
    wire [7:0] last_column={1'b0,cmd_offset[11:5]}+{3'b0,cmd_beats};
    wire legal=cmd_beats>=1 && cmd_beats<=16 && cmd_offset[4:0]==0 &&
        cmd_offset[31:30]==0 && last_column<=8'd128;
    assign cmd_ready=state==IDLE && compute_active && !session_reset_req && !tag_exhausted;
    wire cmd_fire=cmd_valid && cmd_ready;

    wire cmd_sready,cmd_dvalid,cmd_dready,cmd_sa,cmd_da;
    wire [68:0] cmd_bundle;
    cdc_payload_mailbox #(.WIDTH(69)) command_cdc(
        .sclk(compute_clk),.dclk(ui_clk),.srst_n(compute_reset_n),.drst_n(ui_reset_n),
        .s_valid(state==POST),.s_ready(cmd_sready),.s_data({active_tag,offset,beats}),
        .d_valid(cmd_dvalid),.d_ready(cmd_dready),.d_data(cmd_bundle),.s_active(cmd_sa),.d_active(cmd_da));
    wire cancel_svalid,cancel_sready,cancel_dvalid,cancel_sa,cancel_da;
    wire [31:0] cancel_tag;
    assign cancel_svalid=state==ACTIVE && cancelled && !cancel_sent;
    cdc_payload_mailbox #(.WIDTH(32)) cancel_cdc(
        .sclk(compute_clk),.dclk(ui_clk),.srst_n(compute_reset_n),.drst_n(ui_reset_n),
        .s_valid(cancel_svalid),.s_ready(cancel_sready),.s_data(active_tag),
        .d_valid(cancel_dvalid),.d_ready(ui_active),.d_data(cancel_tag),.s_active(cancel_sa),.d_active(cancel_da));
    wire rsp_svalid,rsp_sready,rsp_dvalid,rsp_sa,rsp_da;
    wire [31:0] rsp_tag;
    wire [3:0] rsp_status;
    wire [4:0] rsp_count;
    wire [40:0] response_bundle;
    wire [31:0] return_tag=response_bundle[40:9];
    wire [3:0] return_status=response_bundle[8:5];
    wire [4:0] return_count=response_bundle[4:0];
    cdc_payload_mailbox #(.WIDTH(41)) completion_cdc(
        .sclk(ui_clk),.dclk(compute_clk),.srst_n(ui_reset_n),.drst_n(compute_reset_n),
        .s_valid(rsp_svalid),.s_ready(rsp_sready),.s_data({rsp_tag,rsp_status,rsp_count}),
        .d_valid(rsp_dvalid),.d_ready(1'b1),.d_data(response_bundle),.s_active(rsp_sa),.d_active(rsp_da));
    wire reply_legal=state==ACTIVE && !reply_seen && return_tag==active_tag &&
        ((return_status==0 && return_count==beats) ||
         ((return_status==7 || return_status==8) && (return_count==0 || return_count==beats))) &&
        return_count>=popped;

    wire fwvalid,fwready,fwlast,frvalid,frready,frlast,fwactive,fractive;
    wire [255:0] fwdata,frdata;
    wire [31:0] unused_strb;
    wire [5:0] free_beats,unused_available;
    wire [4:0] unused_reserved;
    async_fifo256_probe rx_fifo(.wclk(ui_clk),.rclk(compute_clk),
        .wrst_n(ui_reset_n),.rrst_n(compute_reset_n),
        .wvalid(fwvalid),.wready(fwready),.wdata(fwdata),.wstrb(32'hffffffff),.wlast(fwlast),
        .rvalid(frvalid),.rready(frready),.rdata(frdata),.rstrb(unused_strb),.rlast(frlast),
        .wfree(free_beats),.ravailable(unused_available),.wactive(fwactive),.ractive(fractive));
    assign compute_active=fractive && cmd_sa && cancel_sa && rsp_da;
    assign ui_active=fwactive && cmd_da && cancel_da && rsp_sa;
    // A previously offered stalled beat remains externally visible after ABORT.
    wire discard=cancelled && !exposed;
    assign data_valid=state==ACTIVE && frvalid && !discard;
    assign data=frdata;
    assign last=frlast;
    assign frready=state==ACTIVE && popped<beats && (discard || data_ready);
    wire pop=frvalid && frready;
    wire data_fault=state==ACTIVE && frvalid &&
        (popped>=beats || (pop && frlast!=(popped==beats-1'b1)));
    wire progress=pop || rsp_dvalid || (state==POST && cmd_sready);
    wire timeout_now=(state==POST || state==ACTIVE) && !progress &&
        LOCAL_STALL_LIMIT>0 && stalled>=LOCAL_STALL_LIMIT-1;
    wire local_fault_now=data_fault || timeout_now || (rsp_dvalid && !reply_legal);
    assign done_valid=state==DONE && compute_active;

    native_rx_reserver #(.STALL_LIMIT(NATIVE_STALL_LIMIT)) reader(
        .clk(ui_clk),.rst_n(u_rst_n),.link_active(ui_active),.init_done(init_done),.init_fail(init_fail),.align_error(align_error),
        .cmd_valid(cmd_dvalid),.cmd_ready(cmd_dready),.cmd_tag(cmd_bundle[68:37]),
        .cmd_offset(cmd_bundle[36:5]),.cmd_beats(cmd_bundle[4:0]),
        .cancel_valid(cancel_dvalid && ui_active),.cancel_tag(cancel_tag),
        .fifo_free(free_beats),.fifo_ready(fwready),.fifo_valid(fwvalid),.fifo_data(fwdata),.fifo_last(fwlast),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arlen(arlen),
        .rvalid(rvalid),.rdata(rdata),.rid(rid),.rlast(rlast),
        .rsp_valid(rsp_svalid),.rsp_ready(rsp_sready),.rsp_tag(rsp_tag),.rsp_status(rsp_status),.rsp_count(rsp_count),
        .reserved_left(unused_reserved),.session_reset_req(ui_session_reset_req),.fault_code(ui_fault_code));

    always @(posedge compute_clk or negedge c_rst_n)begin
        if(!c_rst_n)begin
            state<=IDLE;offset<=0;active_tag<=0;next_tag<=INITIAL_TAG;tag_exhausted<=0;
            beats<=0;popped<=0;returned_count<=0;returned_status<=0;stalled<=0;
            cancelled<=0;cancel_sent<=0;exposed<=0;reply_seen<=0;wrapper_fault<=0;
            done_status<=0;done_id<=0;done_epoch<=0;done_client<=0;
        end else begin
            if(local_fault_now)wrapper_fault<=1;
            if(state==IDLE || state==DONE || progress)stalled<=0;
            else if(!timeout_now)stalled<=stalled+1'b1;
            if((state==POST || state==ACTIVE) && abort_req)cancelled<=1;
            if(cancel_svalid && cancel_sready)cancel_sent<=1;
            if(data_valid && !data_ready)exposed<=1;
            if(pop)begin popped<=popped+1'b1;exposed<=0;end
            if(rsp_dvalid && reply_legal)begin
                reply_seen<=1;returned_count<=return_count;returned_status<=return_status;
            end
            case(state)
            IDLE:if(cmd_fire)begin
                offset<=cmd_offset;beats<=cmd_beats;done_id<=cmd_id;done_epoch<=cmd_epoch;done_client<=cmd_client;
                active_tag<=next_tag;cancelled<=abort_req;cancel_sent<=0;exposed<=0;reply_seen<=0;popped<=0;
                returned_count<=0;returned_status<=0;done_status<=0;stalled<=0;
                if(next_tag==32'hffffffff)tag_exhausted<=1;else next_tag<=next_tag+1'b1;
                if(legal)state<=POST;else begin done_status<=1;state<=DONE;end
            end
            POST:if(cmd_sready)state<=ACTIVE;
            ACTIVE:if(reply_seen && popped==returned_count && !frvalid && !exposed &&
                      !wrapper_fault && !local_fault_now)begin
                done_status<=returned_status==0 && (cancelled || abort_req) ? 7 : returned_status;
                state<=DONE;
            end
            DONE:if(done_valid && done_ready)state<=IDLE;
            endcase
        end
    end
    assign rx_level_ui=6'd32-free_beats;
endmodule
