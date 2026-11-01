`timescale 1ns/1ps
`default_nettype none
// Minimal face-box pixel consumer.  It deliberately keeps only the RAW path
// and a fixed-width border test over the 16 record slots.  Keypoints, avatar
// sampling, alpha blending and their long combinational cones are absent.
// The output latency is 13 pixel clocks, matching display_record_pixels' retire
// marker so the existing frame commit protocol remains unchanged.
module display_box_only #(
    parameter integer LINE_WIDTH=2,
    parameter integer SINGLE_PRIMARY=0,
    parameter [23:0] BOX_COLOR=24'h00ff00,
    parameter [23:0] PRIMARY_COLOR=24'hff0000
)(
    input wire clk,
    input wire rst,
    input wire [31:0] pixel_frame_id,
    input wire [10:0] pixel_x,pixel_y,
    input wire [23:0] pixel_rgb,
    input wire pixel_de,pixel_hs,pixel_vs,pixel_sof,
    input wire [1:0] mode,
    input wire result_valid,result_has_face,
    input wire [31:0] result_frame_id,
    input wire primary_valid,
    input wire [3:0] primary_index,
    input wire [15:0] box_valid,
    input wire [255:0] box_x0,box_y0,box_x1,box_y1,
    output wire [23:0] out_rgb,
    output wire [10:0] out_x,out_y,
    output wire [31:0] out_frame_id,
    output wire out_de,out_hs,out_vs,out_sof,out_box,out_point,out_avatar,out_fault,
    output wire overlay_fault
);
    localparam integer PIPE=13;
    wire qualified=pixel_de && pixel_x<11'd800 && pixel_y<11'd600 &&
                   mode==2'd1 && result_valid && result_has_face &&
                   result_frame_id==pixel_frame_id;
    reg hit,primary_hit;
    reg [23:0] selected_rgb;
    integer i;
    reg [15:0] left,top,right,bottom;
    always @* begin
        hit=1'b0;
        primary_hit=1'b0;
        if(SINGLE_PRIMARY) begin
            left=box_x0[(primary_valid?primary_index:4'd0)*16+:16];
            top=box_y0[(primary_valid?primary_index:4'd0)*16+:16];
            right=box_x1[(primary_valid?primary_index:4'd0)*16+:16];
            bottom=box_y1[(primary_valid?primary_index:4'd0)*16+:16];
            if(box_valid[(primary_valid?primary_index:4'd0)] && left<right && top<bottom &&
               pixel_x>=left && pixel_x<right && pixel_y>=top && pixel_y<bottom &&
               ((pixel_x-left)<LINE_WIDTH || (right-pixel_x)<=LINE_WIDTH ||
                (pixel_y-top)<LINE_WIDTH || (bottom-pixel_y)<=LINE_WIDTH)) begin
                hit=1'b1; primary_hit=primary_valid;
            end
        end else for(i=0;i<16;i=i+1) begin
            left=box_x0[i*16+:16];
            top=box_y0[i*16+:16];
            right=box_x1[i*16+:16];
            bottom=box_y1[i*16+:16];
            if(box_valid[i] && left<right && top<bottom &&
               pixel_x>=left && pixel_x<right && pixel_y>=top && pixel_y<bottom &&
               ((pixel_x-left)<LINE_WIDTH || (right-pixel_x)<=LINE_WIDTH ||
                (pixel_y-top)<LINE_WIDTH || (bottom-pixel_y)<=LINE_WIDTH)) begin
                hit=1'b1;
                if(primary_valid && primary_index==i[3:0]) primary_hit=1'b1;
            end
        end
        selected_rgb=(qualified && hit) ? (primary_hit ? PRIMARY_COLOR : BOX_COLOR) : pixel_rgb;
    end

    reg [23:0] rgb_pipe[0:PIPE-1];
    reg [10:0] x_pipe[0:PIPE-1],y_pipe[0:PIPE-1];
    reg [31:0] frame_pipe[0:PIPE-1];
    reg de_pipe[0:PIPE-1],hs_pipe[0:PIPE-1],vs_pipe[0:PIPE-1],sof_pipe[0:PIPE-1];
    reg box_pipe[0:PIPE-1];
    integer p;
    always @(posedge clk) begin
        if(rst) begin
            for(p=0;p<PIPE;p=p+1) begin
                rgb_pipe[p]<=0;x_pipe[p]<=0;y_pipe[p]<=0;frame_pipe[p]<=0;
                de_pipe[p]<=0;hs_pipe[p]<=0;vs_pipe[p]<=0;sof_pipe[p]<=0;box_pipe[p]<=0;
            end
        end else begin
            rgb_pipe[0]<=selected_rgb;
            x_pipe[0]<=pixel_x;y_pipe[0]<=pixel_y;frame_pipe[0]<=pixel_frame_id;
            de_pipe[0]<=pixel_de;hs_pipe[0]<=pixel_hs;vs_pipe[0]<=pixel_vs;sof_pipe[0]<=pixel_sof;
            box_pipe[0]<=qualified&&hit;
            for(p=1;p<PIPE;p=p+1) begin
                rgb_pipe[p]<=rgb_pipe[p-1];x_pipe[p]<=x_pipe[p-1];y_pipe[p]<=y_pipe[p-1];
                frame_pipe[p]<=frame_pipe[p-1];de_pipe[p]<=de_pipe[p-1];hs_pipe[p]<=hs_pipe[p-1];
                vs_pipe[p]<=vs_pipe[p-1];sof_pipe[p]<=sof_pipe[p-1];box_pipe[p]<=box_pipe[p-1];
            end
        end
    end
    assign out_rgb=rgb_pipe[PIPE-1];
    assign out_x=x_pipe[PIPE-1];
    assign out_y=y_pipe[PIPE-1];
    assign out_frame_id=frame_pipe[PIPE-1];
    assign out_de=de_pipe[PIPE-1];
    assign out_hs=hs_pipe[PIPE-1];
    assign out_vs=vs_pipe[PIPE-1];
    assign out_sof=sof_pipe[PIPE-1];
    assign out_box=box_pipe[PIPE-1];
    assign out_point=1'b0;
    assign out_avatar=1'b0;
    assign out_fault=1'b0;
    assign overlay_fault=1'b0;
endmodule
`default_nettype wire
