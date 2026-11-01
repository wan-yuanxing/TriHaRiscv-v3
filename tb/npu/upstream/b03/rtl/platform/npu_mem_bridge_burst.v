// One owner through local DONE acknowledgement; no combinational abort gating.
module npu_mem_bridge_burst #(
    parameter integer COLLECT_STALL_LIMIT=1000000,
    parameter integer NATIVE_STALL_LIMIT=1000000,
    parameter integer LOCAL_STALL_LIMIT=1000000,
    parameter [31:0] READ_INITIAL_TAG=32'd1
)(
    input wire compute_clk,ui_clk,compute_reset_n,ui_reset_n,
    input wire init_done,init_fail,align_error,
    input wire cmd_valid,output wire cmd_ready,input wire cmd_write,
    input wire [31:0] cmd_offset,cmd_id,cmd_epoch,input wire [4:0] cmd_beats,input wire [2:0] cmd_client,
    input wire write_valid,output wire write_ready,input wire [255:0] write_data,
    input wire [31:0] write_strb,input wire write_last,
    output wire read_valid,input wire read_ready,output wire [255:0] read_data,output wire read_last,
    input wire abort_req,output wire done_valid,input wire done_ready,output wire [3:0] done_status,
    output wire [31:0] done_id,done_epoch,output wire [2:0] done_client,
    output reg busy,owner_write,output wire compute_active,ui_active,
    output wire session_reset_req,ui_session_reset_req,output wire [3:0] write_fault_code,read_fault_code,
    output wire awvalid,input wire awready,output wire [27:0] awaddr,output wire [3:0] awlen,
    input wire wready,input wire [3:0] wid,input wire wlast,output wire [255:0] wdata,output wire [31:0] wstrb,
    output wire arvalid,input wire arready,output wire [27:0] araddr,output wire [3:0] arlen,
    input wire rvalid,input wire [255:0] rdata,input wire [3:0] rid,input wire rlast,
    output wire [5:0] tx_level_ui,rx_level_ui
);
    wire wc_ready,rc_ready,wd_valid,rd_valid,wd_ready,rd_ready,wr_ready,rr_valid,rr_ready;
    wire [3:0] wd_status,rd_status;
    wire [31:0] wd_id,rd_id,wd_epoch,rd_epoch;
    wire [2:0] wd_client,rd_client;
    wire wc_active,rc_active,wu_active,ru_active,wr_fault,rr_fault,wu_fault,ru_fault,wt_exhausted,rt_exhausted;
    wire eligible=!busy && !session_reset_req && compute_active;
    assign cmd_ready=eligible && (cmd_write ? wc_ready : rc_ready);
    assign write_ready=busy && owner_write && wr_ready;
    assign read_valid=busy && !owner_write && rr_valid;
    assign rr_ready=busy && !owner_write && read_ready;
    assign done_valid=busy && (owner_write ? wd_valid : rd_valid);
    assign wd_ready=busy && owner_write && done_ready;
    assign rd_ready=busy && !owner_write && done_ready;
    assign done_status=owner_write ? wd_status : rd_status;
    assign done_id=owner_write ? wd_id : rd_id;
    assign done_epoch=owner_write ? wd_epoch : rd_epoch;
    assign done_client=owner_write ? wd_client : rd_client;
    assign compute_active=wc_active && rc_active;
    assign ui_active=wu_active && ru_active;
    assign session_reset_req=wr_fault || rr_fault;
    assign ui_session_reset_req=wu_fault || ru_fault;
    wire arst_n=compute_reset_n && ui_reset_n;
    always @(posedge compute_clk or negedge arst_n)
        if(!arst_n)begin busy<=0;owner_write<=0;end
        else begin
            if(cmd_valid && cmd_ready)begin busy<=1;owner_write<=cmd_write;end
            if(done_valid && done_ready)busy<=0;
        end
    npu_write_bridge_burst #(.COLLECT_STALL_LIMIT(COLLECT_STALL_LIMIT),.NATIVE_STALL_LIMIT(NATIVE_STALL_LIMIT)) tx(
        .compute_clk(compute_clk),.ui_clk(ui_clk),.compute_reset_n(compute_reset_n),.ui_reset_n(ui_reset_n),
        .init_done(init_done),.init_fail(init_fail),.align_error(align_error),
        .cmd_valid(cmd_valid && eligible && cmd_write),.cmd_ready(wc_ready),
        .cmd_offset(cmd_offset),.cmd_id(cmd_id),.cmd_epoch(cmd_epoch),.cmd_beats(cmd_beats),.cmd_client(cmd_client),
        .data_valid(write_valid && busy && owner_write),.data_ready(wr_ready),.data(write_data),.strb(write_strb),.last(write_last),
        .abort_req(abort_req && busy && owner_write),
        .done_valid(wd_valid),.done_ready(wd_ready),.done_status(wd_status),.done_id(wd_id),.done_epoch(wd_epoch),.done_client(wd_client),
        .session_reset_req(wr_fault),.ui_session_reset_req(wu_fault),.ui_fault_code(write_fault_code),
        .compute_active(wc_active),.ui_active(wu_active),.tag_exhausted(wt_exhausted),
        .awvalid(awvalid),.awready(awready),.awaddr(awaddr),.awlen(awlen),
        .wready(wready),.wid(wid),.wlast(wlast),.wdata(wdata),.wstrb(wstrb),.tx_level_ui(tx_level_ui));
    npu_read_bridge_burst #(.NATIVE_STALL_LIMIT(NATIVE_STALL_LIMIT),.LOCAL_STALL_LIMIT(LOCAL_STALL_LIMIT),.INITIAL_TAG(READ_INITIAL_TAG)) rx(
        .compute_clk(compute_clk),.ui_clk(ui_clk),.compute_reset_n(compute_reset_n),.ui_reset_n(ui_reset_n),
        .init_done(init_done),.init_fail(init_fail),.align_error(align_error),
        .cmd_valid(cmd_valid && eligible && !cmd_write),.cmd_ready(rc_ready),
        .cmd_offset(cmd_offset),.cmd_id(cmd_id),.cmd_epoch(cmd_epoch),.cmd_beats(cmd_beats),.cmd_client(cmd_client),
        .data_valid(rr_valid),.data_ready(rr_ready),.data(read_data),.last(read_last),.abort_req(abort_req && busy && !owner_write),
        .done_valid(rd_valid),.done_ready(rd_ready),.done_status(rd_status),.done_id(rd_id),.done_epoch(rd_epoch),.done_client(rd_client),
        .session_reset_req(rr_fault),.ui_session_reset_req(ru_fault),.ui_fault_code(read_fault_code),
        .compute_active(rc_active),.ui_active(ru_active),.tag_exhausted(rt_exhausted),
        .arvalid(arvalid),.arready(arready),.araddr(araddr),.arlen(arlen),
        .rvalid(rvalid),.rdata(rdata),.rid(rid),.rlast(rlast),.rx_level_ui(rx_level_ui));
endmodule
