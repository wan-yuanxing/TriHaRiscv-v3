`timescale 1ns/1ps
`default_nettype none
`include "video_display.vh"
// Same 640-byte software ABI with RAM shadow/history and one leased record.
// Record preparation is serialized (160 synchronous reads, two cycles each).
// The downstream owner lease lasts through actual feedback. A completed new
// frame is archived into history RAM; one next submission may wait behind that
// copy. Mode-only content equality is exact over all 160 words, not a hash.
// RAM is cleared after reset before MMIO accepts traffic.
// Actual commit and full retirement are supplied by external consumers.
module video_display_mmio_compact #(parameter integer EXTERNAL_HEALTH=0,SKIP_GUARD=0,ENABLE_MODE_KEY=0)(
    input wire clk_i,rst_ni,
    input wire [1:0] mode_request_i,
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
    input wire [31:0] retire_frame_i,retire_generation_i,output wire irq_o,
    // Opt-in consumer health. Legacy instances preserve the original behavior.
    input wire submit_enable_i,external_fault_i,output wire fault_o,output wire [7:0] fault_code_o
);

    localparam [2:0] IDLE=0,FETCH=1,LOAD=2,CHECK=3,OFFER=4,ARCHIVE=5,INIT=6;
    reg [2:0] phase;
    (* syn_ramstyle = "block_ram" *) reg [31:0] shadow[0:159];
    (* syn_ramstyle = "block_ram" *) reg [31:0] active_words[0:159];
    reg [31:0] shadow_q,active_q;
    reg [5119:0] record_data;
    reg [7:0] word_index;
    reg compare_changed,shadow_read_pending,deferred_submit,lease_inflight;
    wire owner_data;
    assign cmd_data_o=record_data;
    reg [31:0] request_mode,request_seq;reg mode_only;
    reg [3:0] irq_mask;
    reg guard_start,reject_pending;reg [7:0] reject_code;
    reg [31:0] reject_seq,guard_rejected;
    wire guard_ready,guard_valid;wire [7:0] guard_code;
    wire owner_ready,owner_reject_valid,commit_valid,release_valid,active_valid,protocol_error,owner_protocol_error;
    wire [7:0] owner_reject_code,error_code,owner_error_code;
    reg external_error;
    wire consumer_healthy=EXTERNAL_HEALTH==0||
        (submit_enable_i===1'b1&&external_fault_i===1'b0&&!external_error);
    assign protocol_error=owner_protocol_error||external_error;
    assign error_code=owner_protocol_error?owner_error_code:external_error?8'hf0:8'd0;
    assign fault_o=protocol_error;assign fault_code_o=error_code;
    wire [31:0] owner_reject_seq,owner_rejected,submits,commits,releases;
    wire [2:0] slot_free;
    wire commit_mode_only;
    wire [1:0] commit_slot,commit_mode,release_slot,active_slot,active_mode;
    wire [31:0] commit_frame,commit_generation,commit_seq,release_frame,release_generation;
    wire [31:0] active_frame,active_generation,active_base,active_stride,active_seq;
    wire active_data;
    wire [3:0] events={protocol_error,reject_pending,release_valid,commit_valid};
    assign irq_o=|(events&irq_mask);
    wire locked=(phase!=IDLE&&phase!=ARCHIVE)||deferred_submit;
    wire [31:0] status_word={24'd0,active_valid,protocol_error,reject_pending,release_valid,
        commit_valid,(!owner_ready||!consumer_healthy),phase==OFFER,(phase==CHECK||phase==FETCH||phase==LOAD||deferred_submit)};
    reg aw_full,w_full;reg [31:0] awaddr,wdata;reg [3:0] wstrb;
    assign s_axi_awready_o=rst_ni&&phase!=INIT&&!aw_full&&!s_axi_bvalid_o;
    assign s_axi_wready_o=rst_ni&&phase!=INIT&&!w_full&&!s_axi_bvalid_o;
    wire shadow_read_address=s_axi_araddr_i>=`VDISP_BASE+`VDISP_SHADOW_OFFSET&&
        s_axi_araddr_i<`VDISP_BASE+`VDISP_SHADOW_OFFSET+`VDISP_RECORD_BYTES&&s_axi_araddr_i[1:0]==0;
    assign s_axi_arready_o=rst_ni&&phase!=INIT&&!s_axi_rvalid_o&&!shadow_read_pending&&
        (!(phase==FETCH||phase==LOAD)||!shadow_read_address);
    function automatic valid_address(input [31:0] address);
        valid_address=(^address)!==1'bx&&address>=`VDISP_BASE&&
            {32'd0,address}<(64'd0+`VDISP_BASE+`VDISP_REGION_BYTES)&&address[1:0]===0;
    endfunction
    function automatic [31:0] mask_word(input [3:0] strobe);
        mask_word={{8{strobe[3]}},{8{strobe[2]}},{8{strobe[1]}},{8{strobe[0]}}};
    endfunction
    wire [31:0] write_offset=awaddr-`VDISP_BASE;
    wire [31:0] read_offset=s_axi_araddr_i-`VDISP_BASE;
    wire execute_write=aw_full&&w_full&&!s_axi_bvalid_o;
    reg [1:0] write_response,read_response;
    reg do_shadow,do_mode,do_seq,do_mask,do_submit,do_ack;
    reg [31:0] merged,read_data;reg [2:0] ack;
    always @* begin
        write_response=0;merged=0;ack=0;
        do_shadow=0;do_mode=0;do_seq=0;do_mask=0;do_submit=0;do_ack=0;
        if(!valid_address(awaddr))write_response=3;
        else if((^{wdata,wstrb})===1'bx)write_response=2;
        else if({32'd0,awaddr}>=(64'd0+`VDISP_BASE+`VDISP_SHADOW_OFFSET)&&
                {32'd0,awaddr}<(64'd0+`VDISP_BASE+`VDISP_SHADOW_OFFSET+`VDISP_RECORD_BYTES))begin
            if(wstrb!=0)begin
                if(locked)write_response=2;
                else do_shadow=1;
            end
        end else case(write_offset)
            `VDISP_REG_MODE,`VDISP_REG_SEQ:begin
                merged=((write_offset==`VDISP_REG_MODE ? request_mode:request_seq)&~mask_word(wstrb))|(wdata&mask_word(wstrb));
                if(wstrb!=0)begin
                    if(locked||(write_offset==`VDISP_REG_MODE&&merged>3))write_response=2;
                    else if(write_offset==`VDISP_REG_MODE)do_mode=1;else do_seq=1;
                end
            end
            `VDISP_REG_IRQ_MASK:begin
                merged=({28'd0,irq_mask}&~mask_word(wstrb))|(wdata&mask_word(wstrb));
                if(merged[31:4]!=0)write_response=2;else do_mask=1;
            end
            `VDISP_REG_SUBMIT:if(wstrb!=0)begin
                if(wstrb!=15||(wdata!=1&&wdata!=3)||locked||!owner_ready||!consumer_healthy||reject_pending||owner_reject_valid||!guard_ready)
                    write_response=2;
                else do_submit=1;
            end
            `VDISP_REG_ACK:if(wstrb!=0)begin
                if(wstrb!=15||wdata[31:3]!=0||(wdata[2:0]&~events[2:0])!=0)write_response=2;
                else begin do_ack=1;ack=wdata[2:0];end
            end
            default:begin
                if(write_offset<=`VDISP_REG_MODES||(ENABLE_MODE_KEY&&write_offset==`VDISP_REG_MODE_REQUEST))write_response=2;else write_response=3;
            end
        endcase
    end
    wire ack_fire=execute_write&&write_response==0&&do_ack;
    generate
        if(SKIP_GUARD) begin : g_skip_guard
            // Minimal BOX records are built and range-checked by the CPU before
            // submission.  Keep the same one-cycle completion handshake while
            // removing the duplicate 160-word guard datapath from the FPGA.
            assign guard_ready=1'b1;
            assign guard_valid=guard_start;
            assign guard_code=8'd0;
        end else begin : g_record_guard
            display_record_guard u_guard(.clk_i(clk_i),.rst_ni(rst_ni),.start_valid_i(guard_start),.start_ready_o(guard_ready),
                .record_i(record_data),.mode_i(request_mode[1:0]),.modes_i(modes_i),.asset_ready_i(asset_ready_i),
                .asset_id_i(asset_id_i),.asset_generation_i(asset_generation_i),.result_valid_o(guard_valid),
                .result_ready_i(phase==CHECK&&!reject_pending),.result_code_o(guard_code));
        end
    endgenerate
    display_slot_owner #(.CONTEXT_WIDTH(1)) u_owner(
        .clk_i(clk_i),.rst_ni(rst_ni),.submit_valid_i(phase==OFFER&&consumer_healthy),.submit_ready_o(owner_ready),
        .submit_mode_only_i(mode_only),.submit_slot_i(record_data[`VDISP_FIELD_SLOT*32+:2]),
        .submit_mode_i(request_mode[1:0]),.submit_frame_i(record_data[`VDISP_FIELD_FRAME*32+:32]),
        .submit_generation_i(record_data[`VDISP_FIELD_GENERATION*32+:32]),.submit_base_i(record_data[`VDISP_FIELD_RAW_BASE*32+:32]),
        .submit_stride_i(record_data[`VDISP_FIELD_RAW_STRIDE*32+:32]),.submit_seq_i(request_seq),.submit_data_i(1'b0),
        .reject_valid_o(owner_reject_valid),.reject_ready_i(!reject_pending),.reject_code_o(owner_reject_code),
        .reject_seq_o(owner_reject_seq),.cmd_valid_o(cmd_valid_o),.cmd_ready_i(cmd_ready_i),
        .cmd_mode_only_o(cmd_mode_only_o),.cmd_slot_o(cmd_slot_o),.cmd_mode_o(cmd_mode_o),.cmd_frame_o(cmd_frame_o),
        .cmd_generation_o(cmd_generation_o),.cmd_base_o(cmd_base_o),.cmd_stride_o(cmd_stride_o),.cmd_seq_o(cmd_seq_o),.cmd_data_o(owner_data),
        .feedback_valid_i(feedback_valid_i),.feedback_ready_o(feedback_ready_o),.feedback_slot_i(feedback_slot_i),
        .feedback_mode_i(feedback_mode_i),.feedback_frame_i(feedback_frame_i),.feedback_generation_i(feedback_generation_i),.feedback_seq_i(feedback_seq_i),
        .commit_valid_o(commit_valid),.commit_ready_i(ack_fire&&ack[0]),.commit_mode_only_o(commit_mode_only),
        .commit_slot_o(commit_slot),.commit_mode_o(commit_mode),.commit_frame_o(commit_frame),.commit_generation_o(commit_generation),.commit_seq_o(commit_seq),
        .retire_valid_i(retire_valid_i),.retire_ready_o(retire_ready_o),.retire_slot_i(retire_slot_i),.retire_frame_i(retire_frame_i),.retire_generation_i(retire_generation_i),
        .release_valid_o(release_valid),.release_ready_i(ack_fire&&ack[1]),.release_slot_o(release_slot),.release_frame_o(release_frame),.release_generation_o(release_generation),
        .active_valid_o(active_valid),.active_slot_o(active_slot),.active_mode_o(active_mode),.active_frame_o(active_frame),
        .active_generation_o(active_generation),.active_base_o(active_base),.active_stride_o(active_stride),.active_seq_o(active_seq),.active_data_o(active_data),
        .slot_free_o(slot_free),.protocol_error_o(owner_protocol_error),.error_code_o(owner_error_code),
        .submits_o(submits),.commits_o(commits),.releases_o(releases),.rejected_o(owner_rejected));
    always @* begin
        read_data=0;read_response=0;
        if(!valid_address(s_axi_araddr_i))read_response=3;
        else if(read_offset>=`VDISP_SHADOW_OFFSET&&read_offset<`VDISP_SHADOW_OFFSET+`VDISP_RECORD_BYTES)
            read_data=0; // The synchronous shadow port completes separately.
        else case(read_offset)
            `VDISP_REG_VERSION:read_data=`VDISP_VERSION;
            `VDISP_REG_CAPABILITIES:read_data=`VDISP_CAPABILITIES|(ENABLE_MODE_KEY?`VDISP_CAP_MODE_KEY:32'd0);
            `VDISP_REG_STATUS:read_data=status_word;
            `VDISP_REG_ERROR_CODE:read_data={24'd0,error_code};
            `VDISP_REG_IRQ_MASK:read_data={28'd0,irq_mask};
            `VDISP_REG_EVENTS:read_data={28'd0,events};
            `VDISP_REG_ACK,`VDISP_REG_SUBMIT:read_response=2;
            `VDISP_REG_SLOT_FREE:read_data={29'd0,slot_free};
            `VDISP_REG_MODE:read_data=request_mode;
            `VDISP_REG_SEQ:read_data=request_seq;
            `VDISP_REG_RECORD_BYTES:read_data=`VDISP_RECORD_BYTES;
            `VDISP_REG_ACTIVE_FRAME:read_data=active_frame;
            `VDISP_REG_ACTIVE_GENERATION:read_data=active_generation;
            `VDISP_REG_ACTIVE_SLOT:read_data={30'd0,active_slot};
            `VDISP_REG_ACTIVE_MODE:read_data={30'd0,active_mode};
            `VDISP_REG_ACTIVE_SEQ:read_data=active_seq;
            `VDISP_REG_COMMIT_FRAME:read_data=commit_frame;
            `VDISP_REG_COMMIT_GENERATION:read_data=commit_generation;
            `VDISP_REG_COMMIT_SLOT:read_data={30'd0,commit_slot};
            `VDISP_REG_COMMIT_MODE:read_data={30'd0,commit_mode};
            `VDISP_REG_COMMIT_SEQ:read_data=commit_seq;
            `VDISP_REG_COMMIT_MODE_ONLY:read_data={31'd0,commit_mode_only};
            `VDISP_REG_RELEASE_FRAME:read_data=release_frame;
            `VDISP_REG_RELEASE_GENERATION:read_data=release_generation;
            `VDISP_REG_RELEASE_SLOT:read_data={30'd0,release_slot};
            `VDISP_REG_REJECT_SEQ:read_data=reject_seq;
            `VDISP_REG_REJECT_CODE:read_data={24'd0,reject_code};
            `VDISP_REG_SUBMITS:read_data=submits;
            `VDISP_REG_COMMITS:read_data=commits;
            `VDISP_REG_RELEASES:read_data=releases;
            `VDISP_REG_REJECTED:read_data=owner_rejected+guard_rejected;
            `VDISP_REG_MODES:read_data={29'd0,modes_i};
            `VDISP_REG_MODE_REQUEST:begin
                if(ENABLE_MODE_KEY)read_data={30'd0,mode_request_i};else read_response=3;
            end
            default:read_response=3;
        endcase
    end
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            aw_full<=0;w_full<=0;awaddr<=0;wdata<=0;wstrb<=0;
            s_axi_bvalid_o<=0;s_axi_bresp_o<=0;s_axi_rvalid_o<=0;s_axi_rresp_o<=0;s_axi_rdata_o<=0;
            request_mode<=0;request_seq<=0;mode_only<=0;phase<=INIT;guard_start<=0;
            word_index<=0;record_data<=0;compare_changed<=0;shadow_read_pending<=0;deferred_submit<=0;lease_inflight<=0;
            irq_mask<=0;reject_pending<=0;reject_code<=0;reject_seq<=0;guard_rejected<=0;external_error<=0;
        end else begin
            if(EXTERNAL_HEALTH!=0&&external_fault_i!==1'b0)external_error<=1;
            guard_start<=0;
            if(s_axi_awvalid_i&&s_axi_awready_o)begin aw_full<=1;awaddr<=s_axi_awaddr_i;end
            if(s_axi_wvalid_i&&s_axi_wready_o)begin w_full<=1;wdata<=s_axi_wdata_i;wstrb<=s_axi_wstrb_i;end
            if(s_axi_bvalid_o&&s_axi_bready_i)s_axi_bvalid_o<=0;
            if(s_axi_rvalid_o&&s_axi_rready_i)s_axi_rvalid_o<=0;
            if(shadow_read_pending)begin
                shadow_read_pending<=0;s_axi_rvalid_o<=1;s_axi_rdata_o<=shadow_q;s_axi_rresp_o<=0;
            end
            if(s_axi_arvalid_i&&s_axi_arready_o)begin
                if(shadow_read_address&&read_response==0)shadow_read_pending<=1;
                else begin s_axi_rvalid_o<=1;s_axi_rdata_o<=read_data;s_axi_rresp_o<=read_response;end
            end
            if(ack_fire&&ack[2])reject_pending<=0;
            if(execute_write)begin
                aw_full<=0;w_full<=0;s_axi_bvalid_o<=1;s_axi_bresp_o<=write_response;
                if(write_response==0)begin
                    if(do_mode)request_mode<=merged;
                    if(do_seq)request_seq<=merged;
                    if(do_mask)irq_mask<=merged[3:0];
                    if(do_submit)begin
                        mode_only<=wdata[1];compare_changed<=0;
                        if(phase==ARCHIVE)deferred_submit<=1;
                        else begin phase<=FETCH;word_index<=0;end
                    end
                end
            end
            case(phase)
                INIT:if(word_index==159)begin phase<=IDLE;word_index<=0;end else word_index<=word_index+1'b1;
                FETCH:phase<=LOAD;
                LOAD:begin
                    record_data<={shadow_q,record_data[5119:32]};
                    compare_changed<=compare_changed||(shadow_q!=active_q);
                    if(word_index==159)begin phase<=CHECK;guard_start<=1;end
                    else begin word_index<=word_index+1'b1;phase<=FETCH;end
                end
                ARCHIVE:begin
                    record_data<={32'd0,record_data[5119:32]};
                    if(word_index==159)begin
                        word_index<=0;deferred_submit<=0;
                        if(deferred_submit||(execute_write&&write_response==0&&do_submit))phase<=FETCH;
                        else phase<=IDLE;
                    end else word_index<=word_index+1'b1;
                end
                default:begin end
            endcase
            if(cmd_valid_o&&cmd_ready_i)lease_inflight<=1;
            if(feedback_valid_i&&feedback_ready_o&&lease_inflight&&
                {feedback_slot_i,feedback_mode_i,feedback_frame_i,feedback_generation_i,feedback_seq_i}===
                {cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,cmd_seq_o})begin
                lease_inflight<=0;
                if(!cmd_mode_only_o)begin phase<=ARCHIVE;word_index<=0;end
            end
            if(phase==CHECK&&guard_valid&&!reject_pending)begin
                if(guard_code!=0)begin
                    phase<=IDLE;reject_pending<=1;reject_seq<=request_seq;reject_code<=guard_code;guard_rejected<=guard_rejected+1'b1;
                end else if(mode_only&&compare_changed)begin
                    phase<=IDLE;reject_pending<=1;reject_seq<=request_seq;reject_code<=6;guard_rejected<=guard_rejected+1'b1;
                end else phase<=OFFER;
            end
            if(phase==OFFER&&owner_ready&&consumer_healthy)phase<=IDLE;
            if(owner_reject_valid&&!reject_pending)begin
                reject_pending<=1;reject_seq<=owner_reject_seq;reject_code<=owner_reject_code;
            end
        end
    end
    wire [7:0] shadow_write_index=(write_offset-`VDISP_SHADOW_OFFSET)>>2;
    wire [7:0] shadow_read_index=(read_offset-`VDISP_SHADOW_OFFSET)>>2;
    wire [7:0] ram_write_index=phase==INIT?word_index:shadow_write_index;
    wire [31:0] ram_write_data=phase==INIT?32'd0:wdata;
    wire [3:0] ram_write_enable=phase==INIT?4'hf:(execute_write&&do_shadow?wstrb:4'd0);
    integer byte_lane;
    always @(posedge clk_i)begin
        for(byte_lane=0;byte_lane<4;byte_lane=byte_lane+1)
            if(ram_write_enable[byte_lane])shadow[ram_write_index][8*byte_lane+:8]<=ram_write_data[8*byte_lane+:8];
        if(phase==FETCH)begin shadow_q<=shadow[word_index];active_q<=active_words[word_index];end
        else if(s_axi_arvalid_i&&s_axi_arready_o&&shadow_read_address)shadow_q<=shadow[shadow_read_index];
        if(phase==ARCHIVE)active_words[word_index]<=record_data[31:0];
    end
endmodule
`default_nettype wire
