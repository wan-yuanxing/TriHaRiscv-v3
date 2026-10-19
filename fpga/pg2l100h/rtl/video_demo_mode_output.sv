`timescale 1ns/1ps
`default_nettype none
// Standalone F3c diagnostic: one immutable raw frame per coordinated reset,
// artificial same-frame boxes/points and one deterministic test material.
// This is not the general multi-frame display owner or the formal CPU ABI.
module video_demo_mode_output #(
    parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600,
    parameter integer BUTTON_CLOCK_HZ=125000000,BUTTON_STABLE_MS=20
)(
    input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,mode_button_n,
    input wire context_valid,input wire [31:0] context_frame_id,context_generation,
    input wire [1:0] context_slot,
    input wire [10:0] raw_x,raw_y,input wire [23:0] raw_rgb,
    input wire raw_de,raw_hs,raw_vs,raw_sof,
    output reg [23:0] out_rgb,output reg [10:0] out_x,out_y,
    output reg [31:0] out_frame_id,
    output reg out_de,out_hs,out_vs,out_sof,mode_first_pixel,
    output wire [31:0] mode_state,request_seq,committed_seq,request_count,commit_count,coalesced_count,
    output wire mode_error,asset_ready
);
    generate if(FRAME_WIDTH<8||FRAME_WIDTH>800||FRAME_HEIGHT<8||FRAME_HEIGHT>600)begin:invalid_parameters
        initial $fatal(1,"demo geometry must fit 8..800 x 8..600");
    end endgenerate
    reg locked_valid,context_fault;
    reg [31:0] locked_frame,locked_generation;
    reg [1:0] locked_slot;
    wire context_known=(^context_frame_id!==1'bx)&&(^context_generation!==1'bx)&&(^context_slot!==1'bx);
    wire context_matches=context_frame_id==locked_frame&&context_generation==locked_generation&&context_slot==locked_slot;
    wire context_live=context_valid&&locked_valid&&context_matches&&!context_fault;
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin locked_valid<=0;locked_frame<=0;locked_generation<=0;locked_slot<=0;context_fault<=0;end
        else if(context_valid)begin
            if(!context_known||context_frame_id==0||context_slot>2)context_fault<=1;
            else if(!locked_valid)begin locked_valid<=1;locked_frame<=context_frame_id;
                locked_generation<=context_generation;locked_slot<=context_slot;end
            else if(!context_matches)context_fault<=1;
        end
    end

    // Test material stream, same arithmetic texture used by the independent
    // F3b oracle. This producer can be replaced by a checked source in F4.
    reg load_started;
    reg [15:0] fill_index;
    wire cache_load_ready,cache_stream_ready,cache_fault,cache_pixel_ready;
    wire [31:0] cache_asset_id,cache_generation,cache_words;
    wire cache_load_valid=!load_started;
    wire cache_stream_valid=load_started&&!asset_ready&&!cache_fault;
    wire [7:0] sx=fill_index[7:0],sy=fill_index[15:8];
    wire [7:0] material_r=sx*8'd37+sy*8'd13+8'd17;
    wire [7:0] material_g=sx^(sy*8'd7);
    wire [7:0] material_b=8'd255-sx+sy*8'd11;
    wire [7:0] material_a=sx+sy*8'd3;
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin load_started<=0;fill_index<=0;end
        else begin
            if(cache_load_valid&&cache_load_ready)load_started<=1;
            if(cache_stream_valid&&cache_stream_ready&&fill_index!=16'hffff)fill_index<=fill_index+1'b1;
        end
    end
    wire material_req_valid,material_valid,material_error;
    wire [17:0] material_addr;
    wire [31:0] material_rgba;
    avatar_texture_cache avatar_cache(
        .core_clk(core_clk),.core_reset_n(core_reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .load_valid(cache_load_valid),.load_ready(cache_load_ready),.load_asset_id(32'd1),.load_generation(32'd1),
        .s_valid(cache_stream_valid),.s_ready(cache_stream_ready),.s_rgba({material_r,material_g,material_b,material_a}),
        .s_last(fill_index==16'hffff),.asset_ready(asset_ready),.asset_id(cache_asset_id),
        .asset_generation(cache_generation),.words_written(cache_words),.load_fault(cache_fault),
        .pixel_asset_ready(cache_pixel_ready),.pixel_req_valid(material_req_valid),.pixel_req_addr(material_addr),
        .pixel_req_asset_id(32'd1),.pixel_req_generation(32'd1),
        .sample_valid(material_valid),.sample_error(material_error),.sample_rgba(material_rgba));

    wire pressed,press_pulse;
    video_button_debounce #(.CLOCK_HZ(BUTTON_CLOCK_HZ),.STABLE_MS(BUTTON_STABLE_MS)) mode_button(
        .clk(core_clk),.reset_n(core_reset_n),.button_async(mode_button_n),.pressed(pressed),.press_pulse(press_pulse));
    wire request_ready,ctl_protocol_error,bridge_protocol_error;
    wire [1:0] requested_mode,active_mode,active_slot;
    wire active_valid,pending,unavailable;
    wire [31:0] active_frame,active_generation,command_count,rejected_requests,ctl_errors;
    wire active_data,reject_valid;
    wire [1:0] rejected_mode;
    wire cmd_valid,cmd_ready,cmd_data;
    wire [1:0] cmd_mode,cmd_slot;
    wire [31:0] cmd_seq,cmd_frame_id,cmd_generation;
    wire feedback_valid,feedback_ready,feedback_data;
    wire [1:0] feedback_mode,feedback_slot;
    wire [31:0] feedback_seq,feedback_frame_id,feedback_generation;
    display_mode_control #(.CONTEXT_WIDTH(1)) mode_control(
        .clk(core_clk),.reset_n(core_reset_n),.request_valid(press_pulse),.request_ready(request_ready),
        .request_mode(requested_mode==2?2'd0:requested_mode+2'd1),
        .reject_valid(reject_valid),.reject_ready(1'b1),.rejected_mode(rejected_mode),.rejected_requests(rejected_requests),
        .context_valid(context_live),.context_frame_id(locked_frame),.context_generation(locked_generation),
        .context_slot(locked_slot),.context_data(1'b1),.capabilities(3'b111),
        .result_valid(context_live),.result_frame_id(locked_frame),.result_empty(1'b0),.avatar_ready(asset_ready),
        .requested_mode(requested_mode),.active_mode(active_mode),.request_seq(request_seq),.committed_seq(committed_seq),
        .active_valid(active_valid),.active_frame_id(active_frame),.active_generation(active_generation),
        .active_slot(active_slot),.active_data(active_data),.pending(pending),.unavailable(unavailable),
        .protocol_error(ctl_protocol_error),.request_count(request_count),.command_count(command_count),
        .commit_count(commit_count),.coalesced_count(coalesced_count),.protocol_errors(ctl_errors),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_mode(cmd_mode),.cmd_slot(cmd_slot),
        .cmd_seq(cmd_seq),.cmd_frame_id(cmd_frame_id),.cmd_generation(cmd_generation),.cmd_data(cmd_data),
        .commit_valid(feedback_valid),.commit_ready(feedback_ready),.commit_mode(feedback_mode),.commit_slot(feedback_slot),
        .commit_seq(feedback_seq),.commit_frame_id(feedback_frame_id),.commit_generation(feedback_generation));

    wire pixel_cmd_valid,pixel_cmd_ready,pixel_waiting_commit,pixel_protocol_error,pixel_cmd_data;
    wire [1:0] pixel_cmd_mode,pixel_cmd_slot;
    wire [31:0] pixel_cmd_seq,pixel_cmd_frame_id,pixel_cmd_generation;
    reg [12:0] retire_marker;
    display_mode_cdc #(.CONTEXT_WIDTH(1)) mode_cdc(
        .core_clk(core_clk),.core_reset_n(core_reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_mode(cmd_mode),.cmd_slot(cmd_slot),
        .cmd_seq(cmd_seq),.cmd_frame_id(cmd_frame_id),.cmd_generation(cmd_generation),.cmd_data(cmd_data),
        .commit_valid(feedback_valid),.commit_ready(feedback_ready),.commit_mode(feedback_mode),.commit_slot(feedback_slot),
        .commit_seq(feedback_seq),.commit_frame_id(feedback_frame_id),.commit_generation(feedback_generation),.commit_data(feedback_data),
        .pixel_cmd_valid(pixel_cmd_valid),.pixel_cmd_ready(pixel_cmd_ready),.pixel_commit(retire_marker[12]),
        .pixel_cmd_mode(pixel_cmd_mode),.pixel_cmd_slot(pixel_cmd_slot),.pixel_cmd_seq(pixel_cmd_seq),
        .pixel_cmd_frame_id(pixel_cmd_frame_id),.pixel_cmd_generation(pixel_cmd_generation),.pixel_cmd_data(pixel_cmd_data),
        .pixel_waiting_commit(pixel_waiting_commit),.pixel_protocol_error(pixel_protocol_error),.protocol_error(bridge_protocol_error));

    (* ASYNC_REG="TRUE" *) reg live_meta,live_sync,context_fault_meta,context_fault_sync;
    (* ASYNC_REG="TRUE" *) reg overlay_fault_meta,overlay_fault_sync,cache_ready_meta,cache_ready_sync;
    wire overlay_fault;
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin live_meta<=0;live_sync<=0;context_fault_meta<=0;context_fault_sync<=0;end
        else begin live_meta<=context_live;live_sync<=live_meta;
            context_fault_meta<=context_fault;context_fault_sync<=context_fault_meta;end
    end
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin overlay_fault_meta<=0;overlay_fault_sync<=0;cache_ready_meta<=0;cache_ready_sync<=0;end
        else begin overlay_fault_meta<=overlay_fault;overlay_fault_sync<=overlay_fault_meta;
            cache_ready_meta<=cache_pixel_ready;cache_ready_sync<=cache_ready_meta;end
    end
    assign pixel_cmd_ready=pixel_reset_n&&raw_sof&&live_sync&&!context_fault_sync&&
                           !pixel_waiting_commit&&(pixel_cmd_mode!=2||cache_pixel_ready);
    wire apply_now=pixel_cmd_valid&&pixel_cmd_ready;
    reg [1:0] pixel_active_mode;
    reg [31:0] pixel_active_frame;
    reg pixel_active_points;
    wire [1:0] selected_mode=apply_now?pixel_cmd_mode:pixel_active_mode;
    wire [31:0] selected_frame=apply_now?pixel_cmd_frame_id:pixel_active_frame;
    wire selected_points=apply_now?pixel_cmd_data:pixel_active_points;
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin pixel_active_mode<=0;pixel_active_frame<=0;pixel_active_points<=0;retire_marker<=0;end
        else begin
            retire_marker<={retire_marker[11:0],apply_now};
            if(apply_now)begin pixel_active_mode<=pixel_cmd_mode;
                pixel_active_frame<=pixel_cmd_frame_id;pixel_active_points<=pixel_cmd_data;end
        end
    end
    localparam [15:0] LEFT0=FRAME_WIDTH/4,TOP0=FRAME_HEIGHT/4,
        RIGHT0=FRAME_WIDTH*3/4,BOTTOM0=FRAME_HEIGHT*3/4,
        LEFT1=FRAME_WIDTH/8,TOP1=FRAME_HEIGHT/6,RIGHT1=FRAME_WIDTH/2,BOTTOM1=FRAME_HEIGHT/2,
        PX0=FRAME_WIDTH*3/8,PX1=FRAME_WIDTH*5/8,PXC=FRAME_WIDTH/2,
        PY0=FRAME_HEIGHT*3/8,PY1=FRAME_HEIGHT*5/8,PYC=FRAME_HEIGHT/2;
    wire [23:0] overlay_rgb;
    wire [10:0] overlay_x,overlay_y;
    wire [31:0] overlay_frame;
    wire overlay_de,overlay_hs,overlay_vs,overlay_sof,overlay_box,overlay_point,overlay_avatar,overlay_pixel_fault;
    display_overlay overlay(
        .clk(pixel_clk),.rst(!pixel_reset_n),.pixel_frame_id(selected_frame),.pixel_x(raw_x),.pixel_y(raw_y),
        .pixel_rgb(raw_rgb),.pixel_de(raw_de),.pixel_hs(raw_hs),.pixel_vs(raw_vs),.pixel_sof(raw_sof),
        .mode(selected_mode),.result_valid(live_sync&&!context_fault_sync&&selected_frame!=0),.result_has_face(1'b1),
        .result_frame_id(selected_frame),.primary_valid(1'b1),.primary_index(4'd0),.points_enable(selected_points),
        .box_valid(16'd3),.box_x0({224'd0,LEFT1,LEFT0}),.box_y0({224'd0,TOP1,TOP0}),
        .box_x1({224'd0,RIGHT1,RIGHT0}),.box_y1({224'd0,BOTTOM1,BOTTOM0}),
        .point_valid(80'h1f),.point_x({1200'd0,PX1,PX0,PXC,PX1,PX0}),
        .point_y({1200'd0,PY1,PY1,PYC,PY0,PY0}),
        .avatar_enable(1'b1),.avatar_x0(LEFT0),.avatar_y0(TOP0),.avatar_x1(RIGHT0),.avatar_y1(BOTTOM0),
        .avatar_req_valid(material_req_valid),.avatar_req_addr(material_addr),
        .sample_valid(material_valid),.sample_error(material_error),.sample_rgba(material_rgba),
        .out_rgb(overlay_rgb),.out_x(overlay_x),.out_y(overlay_y),.out_frame_id(overlay_frame),
        .out_de(overlay_de),.out_hs(overlay_hs),.out_vs(overlay_vs),.out_sof(overlay_sof),
        .out_box(overlay_box),.out_point(overlay_point),.out_avatar(overlay_avatar),
        .out_fault(overlay_pixel_fault),.overlay_fault(overlay_fault));
    // Registered pad stage. The matching marker acknowledges the first output
    // pixel on this exact edge, after all thirteen overlay register stages.
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin out_rgb<=0;out_x<=0;out_y<=0;out_frame_id<=0;
            out_de<=0;out_hs<=0;out_vs<=0;out_sof<=0;mode_first_pixel<=0;end
        else begin out_rgb<=overlay_rgb;out_x<=overlay_x;out_y<=overlay_y;out_frame_id<=overlay_frame;
            out_de<=overlay_de;out_hs<=overlay_hs;out_vs<=overlay_vs;out_sof<=overlay_sof;mode_first_pixel<=retire_marker[12];end
    end
    assign mode_error=context_fault||ctl_protocol_error||bridge_protocol_error||cache_fault||overlay_fault_sync;
    assign mode_state={16'd0,bridge_protocol_error,context_fault,!context_live,pressed,overlay_fault_sync,
        cache_fault,ctl_protocol_error,cache_ready_sync,asset_ready,unavailable,pending,active_valid,active_mode,requested_mode};
endmodule
`default_nettype wire
