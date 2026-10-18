`timescale 1ns/1ps
`default_nettype none
// Observation only. RGB values never gate the producer or qualify capture.
module video_rx_image_probe #(
    parameter integer WIDTH=800,HEIGHT=600
)(
    input wire clk,reset_n,pixel_valid,frame_start,frame_end,frame_good,
    input wire [10:0] x,y,input wire [23:0] rgb,
    output reg [31:0] frame_sequence,pixels,nonzero,x_bounds,y_bounds,crc,
    output reg [31:0] crc_frame128,crc_frame129,last_change_frame,crc_before_change,
    output reg [23:0] q0,q1,q2,q3
);
    initial begin
        if(WIDTH<4||HEIGHT<4||WIDTH>2048||HEIGHT>2048)
            $fatal(1,"RX image probe geometry must be 4..2048");
    end
    reg opened,bad;
    reg [31:0] count,lit,crc_state;
    reg [15:0] min_x,max_x,min_y,max_y;
    reg [23:0] sample0,sample1,sample2,sample3;
    wire take=pixel_valid&&(opened||frame_start);
    wire [31:0] base_count=frame_start?32'd0:count;
    wire [31:0] base_lit=frame_start?32'd0:lit;
    wire [31:0] next_count=base_count+(take?32'd1:32'd0);
    wire lit_take=take&&rgb!=0;
    wire [31:0] next_lit=base_lit+(lit_take?32'd1:32'd0);
    wire [15:0] bx0=frame_start?16'hffff:min_x,bx1=frame_start?16'd0:max_x;
    wire [15:0] by0=frame_start?16'hffff:min_y,by1=frame_start?16'd0:max_y;
    wire [15:0] nx0=lit_take&&{5'd0,x}<bx0?{5'd0,x}:bx0;
    wire [15:0] nx1=lit_take&&{5'd0,x}>bx1?{5'd0,x}:bx1;
    wire [15:0] ny0=lit_take&&{5'd0,y}<by0?{5'd0,y}:by0;
    wire [15:0] ny1=lit_take&&{5'd0,y}>by1?{5'd0,y}:by1;
    function automatic [31:0] crc_byte(input [31:0] seed,input [7:0] value);
        reg [31:0] c;integer k;
        begin
            c=seed^{24'd0,value};
            for(k=0;k<8;k=k+1)c=(c>>1)^(c[0]?32'hedb88320:32'd0);
            crc_byte=c;
        end
    endfunction
    wire [31:0] base_crc=frame_start?32'hffffffff:crc_state;
    wire [31:0] next_crc=take?crc_byte(crc_byte(crc_byte(base_crc,rgb[23:16]),rgb[15:8]),rgb[7:0]):base_crc;
    wire [23:0] s0=take&&x==WIDTH/4&&y==HEIGHT/4?rgb:frame_start?24'd0:sample0;
    wire [23:0] s1=take&&x==3*WIDTH/4&&y==HEIGHT/4?rgb:frame_start?24'd0:sample1;
    wire [23:0] s2=take&&x==WIDTH/4&&y==3*HEIGHT/4?rgb:frame_start?24'd0:sample2;
    wire [23:0] s3=take&&x==3*WIDTH/4&&y==3*HEIGHT/4?rgb:frame_start?24'd0:sample3;
    wire invalid_now=take&&(x>=WIDTH||y>=HEIGHT||next_count>WIDTH*HEIGHT);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            opened<=0;bad<=0;count<=0;lit<=0;crc_state<=32'hffffffff;
            min_x<=16'hffff;max_x<=0;min_y<=16'hffff;max_y<=0;
            sample0<=0;sample1<=0;sample2<=0;sample3<=0;
            frame_sequence<=0;pixels<=0;nonzero<=0;x_bounds<=32'hffffffff;y_bounds<=32'hffffffff;
            crc<=0;q0<=0;q1<=0;q2<=0;q3<=0;
            crc_frame128<=0;crc_frame129<=0;last_change_frame<=0;crc_before_change<=0;
        end else begin
            if(frame_start||take)begin
                if(frame_start)opened<=1;
                bad<=(frame_start?1'b0:bad)||invalid_now;
                count<=next_count;lit<=next_lit;crc_state<=next_crc;
                min_x<=nx0;max_x<=nx1;min_y<=ny0;max_y<=ny1;
                sample0<=s0;sample1<=s1;sample2<=s2;sample3<=s3;
            end
            if(frame_end)begin
                opened<=0;
                if((opened||frame_start)&&frame_good&&!(frame_start?1'b0:bad)&&
                   !invalid_now&&next_count==WIDTH*HEIGHT)begin
                    frame_sequence<=frame_sequence+1'b1;
                    pixels<=next_count;nonzero<=next_lit;
                    x_bounds<=next_lit==0?32'hffffffff:{nx1,nx0};
                    y_bounds<=next_lit==0?32'hffffffff:{ny1,ny0};
                    crc<=~next_crc;q0<=s0;q1<=s1;q2<=s2;q3<=s3;
                    if(frame_sequence==127)crc_frame128<=~next_crc;
                    if(frame_sequence==128)crc_frame129<=~next_crc;
                    if(frame_sequence==0||crc!=~next_crc)begin
                        last_change_frame<=frame_sequence+1'b1;crc_before_change<=crc;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
