`timescale 1ns/1ps
`default_nettype none
`include "video_display.vh"
// Full record pixel consumer. Caller has already passed display_record_guard.
// The source must supply the actual pixel-domain RAW identity. All resets are
// coordinated. pixel retirement is only one contribution to global retirement;
// scanner reads, owner events and software ACK must also finish independently.
module display_record_pixels #(parameter integer BOX_ONLY=0)(
    input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,
    input wire cmd_valid,output wire cmd_ready,
    input wire [1:0] cmd_mode,cmd_slot,
    input wire [31:0] cmd_frame,cmd_generation,cmd_seq,input wire [5119:0] cmd_data,
    output wire commit_valid,input wire commit_ready,
    output wire [1:0] commit_mode,commit_slot,
    output wire [31:0] commit_frame,commit_generation,commit_seq,
    output reg retire_valid,input wire retire_ready,
    output reg [1:0] retire_slot,retire_mode,
    output reg [31:0] retire_frame,retire_generation,retire_seq,
    output reg retire_raw,retire_asset,output reg [31:0] retire_asset_id,retire_asset_generation,
    input wire raw_context_valid,input wire [1:0] raw_slot,
    input wire [31:0] raw_frame,raw_generation,
    input wire [10:0] raw_x,raw_y,input wire [23:0] raw_rgb,
    input wire raw_de,raw_hs,raw_vs,raw_sof,
    input wire asset_ready,input wire [31:0] asset_id,asset_generation,
    output wire avatar_req_valid,output wire [17:0] avatar_req_addr,
    output wire [31:0] avatar_req_asset_id,avatar_req_generation,
    input wire sample_valid,sample_error,input wire [31:0] sample_rgba,
    output reg [23:0] out_rgb,output reg [10:0] out_x,out_y,
    output reg [31:0] out_frame,out_generation,out_seq,output reg [1:0] out_slot,out_mode,
    output reg out_de,out_hs,out_vs,out_sof,out_box,out_point,out_avatar,out_fault,
    output wire pixel_pending,output wire [1:0] pending_mode,pending_slot,
    output wire [31:0] pending_frame,pending_generation,
    output reg fault,output reg [7:0] fault_code
);
    function automatic [31:0] word(input [5119:0] record_data,input integer index);
        word=record_data[index*32+:32];
    endfunction
    function automatic uses_asset(input [1:0] mode,input [5119:0] record_data);
        reg [31:0] flags;
        begin flags=word(record_data,`VDISP_FIELD_FLAGS);uses_asset=mode==2&&!flags[1]&&flags[3]&&flags[4];end
    endfunction
    wire header_ok=(^{cmd_data,cmd_mode,cmd_slot,cmd_frame,cmd_generation,cmd_seq})!==1'bx&&
        cmd_mode<3&&cmd_slot<3&&cmd_frame!=0&&
        word(cmd_data,`VDISP_FIELD_VERSION)==`VDISP_VERSION&&word(cmd_data,`VDISP_FIELD_BYTES)==640&&
        word(cmd_data,`VDISP_FIELD_WIDTH)==800&&word(cmd_data,`VDISP_FIELD_HEIGHT)==600&&
        word(cmd_data,`VDISP_FIELD_RAW_STRIDE)==2400&&word(cmd_data,`VDISP_FIELD_RAW_BASE)==32'h82000000+{30'd0,cmd_slot}*32'h200000&&
        word(cmd_data,`VDISP_FIELD_SLOT)=={30'd0,cmd_slot}&&word(cmd_data,`VDISP_FIELD_FRAME)==cmd_frame&&
        word(cmd_data,`VDISP_FIELD_GENERATION)==cmd_generation&&
        word(cmd_data,`VDISP_FIELD_RESULT_FRAME)==cmd_frame&&word(cmd_data,`VDISP_FIELD_RESULT_GENERATION)==cmd_generation;
    wire cdc_ready,cdc_commit,pixel_waiting,cdc_error,pixel_cdc_error;
    wire [5119:0] committed_data,pending_data;
    wire [31:0] pending_seq;
    wire pixel_accept,pixel_commit;
    reg pixel_fault;
    (* ASYNC_REG="TRUE" *) reg core_fault_meta,core_fault_sync;
    wire overlay_error,overlay_pixel_fault;
    (* ASYNC_REG="TRUE" *) reg fault_meta,fault_sync;
    assign cmd_ready=core_reset_n&&cdc_ready&&!retire_valid&&!fault;
    assign commit_valid=cdc_commit;
    display_mode_cdc #(.CONTEXT_WIDTH(5120)) u_context(
        .core_clk(core_clk),.core_reset_n(core_reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .cmd_valid(cmd_valid&&cmd_ready&&header_ok),.cmd_ready(cdc_ready),
        .cmd_mode(cmd_mode),.cmd_slot(cmd_slot),.cmd_seq(cmd_seq),.cmd_frame_id(cmd_frame),
        .cmd_generation(cmd_generation),.cmd_data(cmd_data),
        .commit_valid(cdc_commit),.commit_ready(commit_ready),.commit_mode(commit_mode),.commit_slot(commit_slot),
        .commit_seq(commit_seq),.commit_frame_id(commit_frame),.commit_generation(commit_generation),.commit_data(committed_data),
        .pixel_cmd_valid(pixel_pending),.pixel_cmd_ready(pixel_accept),.pixel_commit(pixel_commit),
        .pixel_cmd_mode(pending_mode),.pixel_cmd_slot(pending_slot),.pixel_cmd_seq(pending_seq),
        .pixel_cmd_frame_id(pending_frame),.pixel_cmd_generation(pending_generation),.pixel_cmd_data(pending_data),
        .pixel_waiting_commit(pixel_waiting),.pixel_protocol_error(pixel_cdc_error),.protocol_error(cdc_error));
    // A core commit means the first selected output pixel has actually retired.
    // Only after the feedback handshake may the old local proof be published.
    reg active_core;
    reg [1:0] core_slot,core_mode;
    reg [31:0] core_frame,core_generation,core_seq,core_asset_id,core_asset_generation;
    reg core_has_asset;
    wire next_has_asset=uses_asset(commit_mode,committed_data);
    wire old_raw_done=active_core&&(core_slot!=commit_slot||core_frame!=commit_frame||core_generation!=commit_generation);
    wire old_asset_done=active_core&&core_has_asset&&(!next_has_asset||
        core_asset_id!=word(committed_data,`VDISP_FIELD_ASSET_ID)||core_asset_generation!=word(committed_data,`VDISP_FIELD_ASSET_GENERATION));
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin fault_meta<=0;fault_sync<=0;end
        else begin fault_meta<=pixel_fault||overlay_error||pixel_cdc_error;fault_sync<=fault_meta;end
    end
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin
            fault<=0;fault_code<=0;active_core<=0;core_slot<=0;core_mode<=0;core_frame<=0;core_generation<=0;
            core_seq<=0;core_asset_id<=0;core_asset_generation<=0;core_has_asset<=0;
            retire_valid<=0;retire_raw<=0;retire_asset<=0;retire_slot<=0;retire_mode<=0;
            retire_frame<=0;retire_generation<=0;retire_seq<=0;retire_asset_id<=0;retire_asset_generation<=0;
        end else begin
            if(!fault)begin
                if(cmd_valid!==1'b0&&cmd_valid!==1'b1)begin fault<=1;fault_code<=1;end
                else if(cmd_valid&&cmd_ready&&!header_ok)begin fault<=1;fault_code<=2;end
                else if(cdc_error||fault_sync)begin fault<=1;fault_code<=3;end
            end
            if(retire_valid&&retire_ready)retire_valid<=0;
            if(cdc_commit&&commit_ready)begin
                if(old_raw_done||old_asset_done)begin
                    retire_valid<=1;retire_raw<=old_raw_done;retire_asset<=old_asset_done;
                    retire_slot<=core_slot;retire_frame<=core_frame;retire_generation<=core_generation;
                    retire_mode<=core_mode;retire_seq<=core_seq;
                    retire_asset_id<=core_asset_id;retire_asset_generation<=core_asset_generation;
                end
                active_core<=1;core_slot<=commit_slot;core_mode<=commit_mode;core_frame<=commit_frame;
                core_generation<=commit_generation;core_seq<=commit_seq;core_has_asset<=next_has_asset;
                core_asset_id<=word(committed_data,`VDISP_FIELD_ASSET_ID);
                core_asset_generation<=word(committed_data,`VDISP_FIELD_ASSET_GENERATION);
            end
        end
    end
    reg pixel_active;
    reg [5119:0] active_data;
    reg [1:0] active_mode,active_slot;
    reg [31:0] active_frame,active_generation,active_seq;
    wire source_known=(^{raw_slot,raw_frame,raw_generation})!==1'bx;
    wire pending_matches=raw_context_valid===1'b1&&source_known&&raw_slot==pending_slot&&
        raw_frame==pending_frame&&raw_generation==pending_generation;
    wire pending_asset=uses_asset(pending_mode,pending_data);
    wire asset_matches=asset_ready===1'b1&&asset_id===word(pending_data,`VDISP_FIELD_ASSET_ID)&&
        asset_generation===word(pending_data,`VDISP_FIELD_ASSET_GENERATION);
    wire active_matches=raw_context_valid===1'b1&&source_known&&raw_slot==active_slot&&
        raw_frame==active_frame&&raw_generation==active_generation;
    assign pixel_accept=pixel_reset_n&&pixel_pending&&!pixel_waiting&&raw_sof&&pending_matches&&
        (!pending_asset||asset_matches)&&!pixel_fault&&!overlay_error&&!pixel_cdc_error&&!core_fault_sync;
    wire apply_now=pixel_pending&&pixel_accept;
    wire [5119:0] selected=apply_now?pending_data:active_data;
    wire [1:0] selected_mode=apply_now?pending_mode:active_mode;
    wire [31:0] selected_seq=apply_now?pending_seq:active_seq;
    wire qualified_context=apply_now||(pixel_active&&active_matches);
    reg [12:0] retire_marker;
    assign pixel_commit=retire_marker[12]&&!pixel_fault&&!overlay_error&&!overlay_pixel_fault&&!pixel_cdc_error&&!core_fault_sync;
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin core_fault_meta<=0;core_fault_sync<=0;end
        else begin core_fault_meta<=fault;core_fault_sync<=core_fault_meta;end
    end
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin
            pixel_active<=0;active_data<=0;active_mode<=0;active_slot<=0;active_frame<=0;active_generation<=0;
            active_seq<=0;retire_marker<=0;pixel_fault<=0;
        end else begin
            retire_marker<={retire_marker[11:0],apply_now};
            if(apply_now)begin
                pixel_active<=1;active_data<=pending_data;active_mode<=pending_mode;active_slot<=pending_slot;
                active_frame<=pending_frame;active_generation<=pending_generation;active_seq<=pending_seq;
            end
            if(raw_context_valid!==1'b0&&raw_context_valid!==1'b1)pixel_fault<=1;
            if(raw_context_valid&&!source_known)pixel_fault<=1;
            // A known pending source may arrive before its material is ready.
            // Keep the old reference, bypass its mismatching overlay and wait
            // for a later matching SOF; do not invent a commit or retirement.
            if(raw_sof&&pixel_active&&!apply_now&&!active_matches&&!(pixel_pending&&pending_matches))pixel_fault<=1;
            if(raw_sof&&pixel_pending&&pending_matches&&pending_asset&&asset_ready===1'b1&&!asset_matches)pixel_fault<=1;
        end
    end
    wire [31:0] selected_flags=word(selected,`VDISP_FIELD_FLAGS);
    wire [255:0] box_x0,box_y0,box_x1,box_y1;
    wire [79:0] point_valid;wire [1279:0] point_x,point_y;
    genvar lane,point_index;
    generate for(lane=0;lane<16;lane=lane+1)begin:g_box
        assign box_x0[lane*16+:16]=selected[(32+lane*8)*32+:16];
        assign box_y0[lane*16+:16]=selected[(32+lane*8)*32+16+:16];
        assign box_x1[lane*16+:16]=selected[(33+lane*8)*32+:16];
        assign box_y1[lane*16+:16]=selected[(33+lane*8)*32+16+:16];
        for(point_index=0;point_index<5;point_index=point_index+1)begin:g_point
            assign point_valid[lane*5+point_index]=selected[(34+lane*8)*32+point_index];
            assign point_x[(lane*5+point_index)*16+:16]=selected[(35+lane*8+point_index)*32+:16];
            assign point_y[(lane*5+point_index)*16+:16]=selected[(35+lane*8+point_index)*32+16+:16];
        end
    end endgenerate
    reg [63:0] asset_tags[0:8];reg [67:0] pixel_tags[0:12];integer delay_index;
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin
            for(delay_index=0;delay_index<9;delay_index=delay_index+1)asset_tags[delay_index]<=0;
            for(delay_index=0;delay_index<13;delay_index=delay_index+1)pixel_tags[delay_index]<=0;
        end else begin
            asset_tags[0]<={word(selected,`VDISP_FIELD_ASSET_ID),word(selected,`VDISP_FIELD_ASSET_GENERATION)};
            for(delay_index=1;delay_index<9;delay_index=delay_index+1)asset_tags[delay_index]<=asset_tags[delay_index-1];
            pixel_tags[0]<={raw_generation,selected_seq,raw_slot,selected_mode};
            for(delay_index=1;delay_index<13;delay_index=delay_index+1)pixel_tags[delay_index]<=pixel_tags[delay_index-1];
        end
    end
    assign {avatar_req_asset_id,avatar_req_generation}=asset_tags[8];
    wire [23:0] overlay_rgb;wire [10:0] overlay_x,overlay_y;wire [31:0] overlay_frame;
    wire overlay_de,overlay_hs,overlay_vs,overlay_sof,overlay_box,overlay_point,overlay_avatar;
    generate if(!BOX_ONLY) begin:g_full_overlay
    display_overlay u_overlay(
        .clk(pixel_clk),.rst(!pixel_reset_n),.pixel_frame_id(raw_frame),.pixel_x(raw_x),.pixel_y(raw_y),
        .pixel_rgb(raw_rgb),.pixel_de(raw_de),.pixel_hs(raw_hs),.pixel_vs(raw_vs),.pixel_sof(raw_sof),
        .mode(selected_mode),.result_valid(qualified_context&&selected_flags[0]),.result_has_face(!selected_flags[1]),
        .result_frame_id(word(selected,`VDISP_FIELD_RESULT_FRAME)),.primary_valid(selected_flags[4]),
        .primary_index(selected[13*32+:4]),.points_enable(selected_flags[2]),.box_valid(selected[12*32+:16]),
        .box_x0(box_x0),.box_y0(box_y0),.box_x1(box_x1),.box_y1(box_y1),.point_valid(point_valid),.point_x(point_x),.point_y(point_y),
        .avatar_enable(selected_flags[3]),.avatar_x0(selected[21*32+:16]),.avatar_y0(selected[21*32+16+:16]),
        .avatar_x1(selected[22*32+:16]),.avatar_y1(selected[22*32+16+:16]),
        .avatar_req_valid(avatar_req_valid),.avatar_req_addr(avatar_req_addr),.sample_valid(sample_valid),.sample_error(sample_error),.sample_rgba(sample_rgba),
        .out_rgb(overlay_rgb),.out_x(overlay_x),.out_y(overlay_y),.out_frame_id(overlay_frame),
        .out_de(overlay_de),.out_hs(overlay_hs),.out_vs(overlay_vs),.out_sof(overlay_sof),
        .out_box(overlay_box),.out_point(overlay_point),.out_avatar(overlay_avatar),.out_fault(overlay_pixel_fault),.overlay_fault(overlay_error));
    end else begin:g_box_only
    display_box_only #(.SINGLE_PRIMARY(BOX_ONLY)) u_overlay(
            .clk(pixel_clk),.rst(!pixel_reset_n),.pixel_frame_id(raw_frame),.pixel_x(raw_x),.pixel_y(raw_y),
            .pixel_rgb(raw_rgb),.pixel_de(raw_de),.pixel_hs(raw_hs),.pixel_vs(raw_vs),.pixel_sof(raw_sof),
            .mode(selected_mode),.result_valid(qualified_context&&selected_flags[0]),.result_has_face(!selected_flags[1]),
            .result_frame_id(word(selected,`VDISP_FIELD_RESULT_FRAME)),.primary_valid(selected_flags[4]),
            .primary_index(selected[13*32+:4]),.box_valid(selected[12*32+:16]),.box_x0(box_x0),.box_y0(box_y0),
            .box_x1(box_x1),.box_y1(box_y1),.out_rgb(overlay_rgb),.out_x(overlay_x),.out_y(overlay_y),
            .out_frame_id(overlay_frame),.out_de(overlay_de),.out_hs(overlay_hs),.out_vs(overlay_vs),
            .out_sof(overlay_sof),.out_box(overlay_box),.out_point(overlay_point),.out_avatar(overlay_avatar),
            .out_fault(overlay_pixel_fault),.overlay_fault(overlay_error));
        assign avatar_req_valid=1'b0;
        assign avatar_req_addr=18'd0;
    end endgenerate
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin
            out_rgb<=0;out_x<=0;out_y<=0;out_frame<=0;out_generation<=0;out_seq<=0;out_slot<=0;out_mode<=0;
            out_de<=0;out_hs<=0;out_vs<=0;out_sof<=0;out_box<=0;out_point<=0;out_avatar<=0;out_fault<=0;
        end else begin
            out_rgb<=overlay_rgb;out_x<=overlay_x;out_y<=overlay_y;out_frame<=overlay_frame;
            {out_generation,out_seq,out_slot,out_mode}<=pixel_tags[12];
            out_de<=overlay_de;out_hs<=overlay_hs;out_vs<=overlay_vs;out_sof<=overlay_sof;
            out_box<=overlay_box;out_point<=overlay_point;out_avatar<=overlay_avatar;out_fault<=overlay_pixel_fault;
        end
    end
endmodule
`default_nettype wire
