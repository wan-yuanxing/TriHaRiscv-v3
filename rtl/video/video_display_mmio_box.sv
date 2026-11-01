`timescale 1ns/1ps
`default_nettype none
`include "video_display.vh"
// Reduced display command endpoint for the face-box application.  It accepts
// the existing 640-byte software record ABI, but removes the shadow/history
// RAM, full record guard and archive copy.  The record is already validated by
// the CPU-side frame/NPU protocol; the pixel consumer still validates its
// frame identity before drawing.
module video_display_mmio_box(
    input wire clk_i,rst_ni,
    input wire [31:0] s_axi_awaddr_i,input wire [2:0] s_axi_awprot_i,
    input wire s_axi_awvalid_i,output wire s_axi_awready_o,
    input wire [31:0] s_axi_wdata_i,input wire [3:0] s_axi_wstrb_i,
    input wire s_axi_wvalid_i,output wire s_axi_wready_o,
    output reg [1:0] s_axi_bresp_o,output reg s_axi_bvalid_o,input wire s_axi_bready_i,
    input wire [31:0] s_axi_araddr_i,input wire [2:0] s_axi_arprot_i,
    input wire s_axi_arvalid_i,output wire s_axi_arready_o,
    output reg [31:0] s_axi_rdata_o,output reg [1:0] s_axi_rresp_o,
    output reg s_axi_rvalid_o,input wire s_axi_rready_i,
    input wire [2:0] modes_i,input wire asset_ready_i,input wire [31:0] asset_id_i,asset_generation_i,
    output wire cmd_valid_o,input wire cmd_ready_i,output wire cmd_mode_only_o,
    output wire [1:0] cmd_slot_o,cmd_mode_o,
    output wire [31:0] cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,
    output wire [5119:0] cmd_data_o,
    input wire feedback_valid_i,output wire feedback_ready_o,input wire [1:0] feedback_slot_i,feedback_mode_i,
    input wire [31:0] feedback_frame_i,feedback_generation_i,feedback_seq_i,
    input wire retire_valid_i,output wire retire_ready_o,input wire [1:0] retire_slot_i,
    input wire [31:0] retire_frame_i,retire_generation_i,
    output wire irq_o, input wire submit_enable_i,external_fault_i,
    output wire fault_o,output wire [7:0] fault_code_o
);
    localparam [1:0] OKAY=0,SLVERR=2,DECERR=3;
    localparam [2:0] E_COMMIT=1,E_RELEASE=2,E_REJECT=4;
    reg aw_full,w_full;
    reg [31:0] awaddr,wdata;
    reg [3:0] wstrb;
    reg [5119:0] record_data;
    reg [31:0] request_mode,request_seq;
    reg [3:0] irq_mask;
    reg cmd_pending,mode_only_pending,reject_pending;
    reg [7:0] reject_code;
    reg [31:0] reject_seq;
    reg external_error;
    wire consumer_healthy=submit_enable_i===1'b1&&external_fault_i===1'b0&&!external_error;
    wire owner_ready,owner_reject_valid,commit_valid,release_valid,active_valid,owner_error;
    wire [7:0] owner_reject_code,owner_error_code;
    wire [31:0] owner_reject_seq,owner_rejected,submits,commits,releases;
    wire [2:0] slot_free;
    wire commit_mode_only;
    wire [1:0] commit_slot,commit_mode,release_slot,active_slot,active_mode;
    wire [31:0] commit_frame,commit_generation,commit_seq,release_frame,release_generation;
    wire [31:0] active_frame,active_generation,active_base,active_stride,active_seq;
    wire [2:0] events={reject_pending,release_valid,commit_valid};
    assign irq_o=|(events&irq_mask);
    assign cmd_data_o=record_data;
    assign fault_o=owner_error||external_error;
    assign fault_code_o=owner_error?owner_error_code:external_error?8'hf0:8'd0;
    assign s_axi_awready_o=rst_ni&&!aw_full&&!s_axi_bvalid_o;
    assign s_axi_wready_o=rst_ni&&!w_full&&!s_axi_bvalid_o;
    assign s_axi_arready_o=rst_ni&&!s_axi_rvalid_o;
    wire [31:0] write_offset=awaddr-`VDISP_BASE;
    wire [31:0] read_offset=s_axi_araddr_i-`VDISP_BASE;
    wire shadow_write=write_offset>=`VDISP_SHADOW_OFFSET&&write_offset<`VDISP_SHADOW_OFFSET+`VDISP_RECORD_BYTES;
    wire shadow_read=read_offset>=`VDISP_SHADOW_OFFSET&&read_offset<`VDISP_SHADOW_OFFSET+`VDISP_RECORD_BYTES;
    wire execute_write=aw_full&&w_full&&!s_axi_bvalid_o;
    function automatic valid_address(input [31:0] address);
        valid_address=(^address)!==1'bx&&address>=`VDISP_BASE&&
            {32'd0,address}<(64'd0+`VDISP_BASE+`VDISP_REGION_BYTES)&&address[1:0]==0;
    endfunction
    function automatic [31:0] mask_word(input [3:0] strobe);
        mask_word={{8{strobe[3]}},{8{strobe[2]}},{8{strobe[1]}},{8{strobe[0]}}};
    endfunction
    wire [31:0] word_mask=mask_word(wstrb);
    reg [1:0] write_response;
    reg do_mode,do_seq,do_mask,do_submit,do_ack;
    reg [31:0] merged;
    reg [2:0] ack;
    always @* begin
        write_response=OKAY;merged=0;ack=0;
        do_mode=0;do_seq=0;do_mask=0;do_submit=0;do_ack=0;
        if(!valid_address(awaddr))write_response=DECERR;
        else if((^{wdata,wstrb})===1'bx)write_response=SLVERR;
        else if(shadow_write)begin end
        else case(write_offset)
            `VDISP_REG_MODE,`VDISP_REG_SEQ:begin
                merged=(((write_offset==`VDISP_REG_MODE) ? request_mode : request_seq)&~word_mask)|(wdata&word_mask);
                if(wstrb!=0)begin
                    if(cmd_pending||((write_offset==`VDISP_REG_MODE)&&merged>3))write_response=SLVERR;
                    else if(write_offset==`VDISP_REG_MODE)do_mode=1;else do_seq=1;
                end
            end
            `VDISP_REG_IRQ_MASK:begin merged=({28'd0,irq_mask}&~word_mask)|(wdata&word_mask);if(merged[31:4]!=0)write_response=SLVERR;else do_mask=1;end
            `VDISP_REG_SUBMIT:begin
                if(wstrb!=0)begin
                    if(wstrb!=15||(wdata!=1&&wdata!=3)||cmd_pending||!consumer_healthy||!owner_ready||reject_pending)write_response=SLVERR;
                    else do_submit=1;
                end
            end
            `VDISP_REG_ACK:begin
                if(wstrb!=0)begin
                    if(wstrb!=15||wdata[31:3]!=0||(wdata[2:0]&~events)!=0)write_response=SLVERR;
                    else begin do_ack=1;ack=wdata[2:0];end
                end
            end
            default:if(wstrb!=0)write_response=DECERR;
        endcase
    end
    wire ack_fire=execute_write&&write_response==OKAY&&do_ack;
    display_slot_owner #(.CONTEXT_WIDTH(1)) u_owner(
        .clk_i(clk_i),.rst_ni(rst_ni),.submit_valid_i(cmd_pending&&consumer_healthy),.submit_ready_o(owner_ready),
        .submit_mode_only_i(mode_only_pending),.submit_slot_i(record_data[`VDISP_FIELD_SLOT*32+:2]),
        .submit_mode_i(request_mode[1:0]),.submit_frame_i(record_data[`VDISP_FIELD_FRAME*32+:32]),
        .submit_generation_i(record_data[`VDISP_FIELD_GENERATION*32+:32]),.submit_base_i(record_data[`VDISP_FIELD_RAW_BASE*32+:32]),
        .submit_stride_i(record_data[`VDISP_FIELD_RAW_STRIDE*32+:32]),.submit_seq_i(request_seq),.submit_data_i(1'b0),
        .reject_valid_o(owner_reject_valid),.reject_ready_i(!reject_pending),.reject_code_o(owner_reject_code),.reject_seq_o(owner_reject_seq),
        .cmd_valid_o(cmd_valid_o),.cmd_ready_i(cmd_ready_i),.cmd_mode_only_o(),.cmd_slot_o(cmd_slot_o),.cmd_mode_o(cmd_mode_o),
        .cmd_frame_o(cmd_frame_o),.cmd_generation_o(cmd_generation_o),.cmd_base_o(cmd_base_o),.cmd_stride_o(cmd_stride_o),.cmd_seq_o(cmd_seq_o),.cmd_data_o(),
        .feedback_valid_i(feedback_valid_i),.feedback_ready_o(feedback_ready_o),.feedback_slot_i(feedback_slot_i),.feedback_mode_i(feedback_mode_i),
        .feedback_frame_i(feedback_frame_i),.feedback_generation_i(feedback_generation_i),.feedback_seq_i(feedback_seq_i),
        .commit_valid_o(commit_valid),.commit_ready_i(ack_fire&&ack[0]),.commit_mode_only_o(commit_mode_only),.commit_slot_o(commit_slot),
        .commit_mode_o(commit_mode),.commit_frame_o(commit_frame),.commit_generation_o(commit_generation),.commit_seq_o(commit_seq),
        .retire_valid_i(retire_valid_i),.retire_ready_o(retire_ready_o),.retire_slot_i(retire_slot_i),.retire_frame_i(retire_frame_i),.retire_generation_i(retire_generation_i),
        .release_valid_o(release_valid),.release_ready_i(ack_fire&&ack[1]),.release_slot_o(release_slot),.release_frame_o(release_frame),.release_generation_o(release_generation),
        .active_valid_o(active_valid),.active_slot_o(active_slot),.active_mode_o(active_mode),.active_frame_o(active_frame),
        .active_generation_o(active_generation),.active_base_o(active_base),.active_stride_o(active_stride),.active_seq_o(active_seq),.active_data_o(),
        .slot_free_o(slot_free),.protocol_error_o(owner_error),.error_code_o(owner_error_code),.submits_o(submits),.commits_o(commits),.releases_o(releases),.rejected_o(owner_rejected));
    reg [31:0] read_data;
    reg [1:0] read_response;
    always @* begin
        read_data=0;read_response=OKAY;
        if(!valid_address(s_axi_araddr_i))read_response=DECERR;
        else if(shadow_read)read_data=record_data[((read_offset-`VDISP_SHADOW_OFFSET)>>2)*32 +: 32];
        else case(read_offset)
            `VDISP_REG_VERSION:read_data=`VDISP_VERSION;
            `VDISP_REG_CAPABILITIES:read_data=`VDISP_CAPABILITIES;
            `VDISP_REG_STATUS:read_data={24'd0,active_valid,owner_error,reject_pending,release_valid,commit_valid,!owner_ready,cmd_pending,cmd_pending};
            `VDISP_REG_ERROR_CODE:read_data={24'd0,fault_code_o};
            `VDISP_REG_IRQ_MASK:read_data={28'd0,irq_mask};
            `VDISP_REG_EVENTS:read_data={29'd0,events};
            `VDISP_REG_SLOT_FREE:read_data={29'd0,slot_free};
            `VDISP_REG_MODE:read_data=request_mode;`VDISP_REG_SEQ:read_data=request_seq;
            `VDISP_REG_RECORD_BYTES:read_data=`VDISP_RECORD_BYTES;
            `VDISP_REG_ACTIVE_FRAME:read_data=active_frame;`VDISP_REG_ACTIVE_GENERATION:read_data=active_generation;
            `VDISP_REG_ACTIVE_SLOT:read_data={30'd0,active_slot};`VDISP_REG_ACTIVE_MODE:read_data={30'd0,active_mode};`VDISP_REG_ACTIVE_SEQ:read_data=active_seq;
            `VDISP_REG_COMMIT_FRAME:read_data=commit_frame;`VDISP_REG_COMMIT_GENERATION:read_data=commit_generation;
            `VDISP_REG_COMMIT_SLOT:read_data={30'd0,commit_slot};`VDISP_REG_COMMIT_MODE:read_data={30'd0,commit_mode};`VDISP_REG_COMMIT_SEQ:read_data=commit_seq;
            `VDISP_REG_COMMIT_MODE_ONLY:read_data={31'd0,commit_mode_only};`VDISP_REG_RELEASE_FRAME:read_data=release_frame;`VDISP_REG_RELEASE_GENERATION:read_data=release_generation;
            `VDISP_REG_RELEASE_SLOT:read_data={30'd0,release_slot};`VDISP_REG_REJECT_SEQ:read_data=reject_seq;`VDISP_REG_REJECT_CODE:read_data={24'd0,reject_code};
            `VDISP_REG_SUBMITS:read_data=submits;`VDISP_REG_COMMITS:read_data=commits;`VDISP_REG_RELEASES:read_data=releases;`VDISP_REG_REJECTED:read_data=owner_rejected;`VDISP_REG_MODES:read_data={29'd0,modes_i};
            default:read_response=DECERR;
        endcase
    end
    integer wi;
    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            aw_full<=0;w_full<=0;awaddr<=0;wdata<=0;wstrb<=0;s_axi_bvalid_o<=0;s_axi_bresp_o<=0;s_axi_rvalid_o<=0;s_axi_rresp_o<=0;
            record_data<=0;request_mode<=0;request_seq<=0;irq_mask<=0;cmd_pending<=0;mode_only_pending<=0;reject_pending<=0;reject_code<=0;reject_seq<=0;external_error<=0;
        end else begin
            if(external_fault_i!==1'b0)external_error<=1;
            if(s_axi_awvalid_i&&s_axi_awready_o)begin aw_full<=1;awaddr<=s_axi_awaddr_i;end
            if(s_axi_wvalid_i&&s_axi_wready_o)begin w_full<=1;wdata<=s_axi_wdata_i;wstrb<=s_axi_wstrb_i;end
            if(s_axi_bvalid_o&&s_axi_bready_i)s_axi_bvalid_o<=0;
            if(s_axi_rvalid_o&&s_axi_rready_i)s_axi_rvalid_o<=0;
            if(s_axi_arvalid_i&&s_axi_arready_o)begin s_axi_rvalid_o<=1;s_axi_rdata_o<=read_data;s_axi_rresp_o<=read_response;end
            if(owner_reject_valid&&!reject_pending)begin reject_pending<=1;reject_code<=owner_reject_code;reject_seq<=owner_reject_seq;end
            if(ack_fire&&ack[2])reject_pending<=0;
            if(cmd_pending&&cmd_valid_o&&cmd_ready_i)cmd_pending<=0;
            if(execute_write)begin
                aw_full<=0;w_full<=0;s_axi_bvalid_o<=1;s_axi_bresp_o<=write_response;
                if(write_response==OKAY)begin
                    if(shadow_write)begin
                        wi=(write_offset-`VDISP_SHADOW_OFFSET)>>2;
                        record_data[wi*32+:32]<= (record_data[wi*32+:32]&~word_mask)|(wdata&word_mask);
                    end
                    if(do_mode)request_mode<=merged;
                    if(do_seq)request_seq<=merged;
                    if(do_mask)irq_mask<=merged[3:0];
                    if(do_submit)begin cmd_pending<=1;mode_only_pending<=wdata[1];end
                end
            end
        end
    end
endmodule
`default_nettype wire
