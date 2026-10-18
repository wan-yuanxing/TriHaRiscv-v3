`timescale 1ns/1ps
`default_nettype none
// Fixed 5:2 uint8 INTER_LINEAR. One explicitly cleared RGB frame, no padding
// or tensor layout conversion. The top row overwrites RAM before any read.
module detect_bilinear #(
    parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600
)(
    input wire clk,reset_n,clear,
    input wire s_valid,output wire s_ready,
    input wire [23:0] s_rgb,input wire s_row_last,
    output wire m_valid,input wire m_ready,
    output wire [23:0] m_rgb,output wire m_row_last,
    output reg fault
);
    localparam integer BLOCKS=FRAME_WIDTH>=5?FRAME_WIDTH/5:1;
    localparam integer OUT_WIDTH=BLOCKS*2;
    localparam integer XB=BLOCKS>1?$clog2(BLOCKS):1;
    localparam integer YB=FRAME_HEIGHT>1?$clog2(FRAME_HEIGHT):1;
    localparam integer AB=$clog2(OUT_WIDTH);
    localparam [XB-1:0] LAST_BLOCK=BLOCKS-1;
    localparam [YB-1:0] LAST_ROW=FRAME_HEIGHT-1;
    initial begin
        if(FRAME_WIDTH<5||FRAME_WIDTH>2045||FRAME_WIDTH%5!=0||
           FRAME_HEIGHT<5||FRAME_HEIGHT>2045||FRAME_HEIGHT%5!=0)
            $fatal(1,"detect_bilinear: invalid frame geometry");
    end
    reg [2:0] column_phase,row_phase;
    reg [XB-1:0] block_x;
    reg [YB-1:0] row_y;
    reg complete,calc_pending,round_pending,pending_last,pending_odd;
    reg [23:0] left_pixel,out_rgb;
    reg out_valid,out_last;
    reg [29:0] line_sums[0:OUT_WIDTH-1];
    reg [29:0] top_sums,bottom_sums,rounded_sums;
    wire row_end=column_phase==4&&block_x==LAST_BLOCK;
    wire pair_first=column_phase==0||column_phase==3;
    wire pair_last=column_phase==1||column_phase==4;
    wire top_row=row_phase==0||row_phase==3;
    wire bottom_row=row_phase==1||row_phase==4;
    wire [AB-1:0] line_address={block_x,1'b0}+(column_phase>=3?1'b1:1'b0);
    wire take=s_valid&&s_ready;
    wire legal_payload=(s_row_last===row_end)&&((^s_rgb)!==1'bx);
    wire good_input=take&&legal_payload;
    wire stopping=fault||(complete&&s_valid);

    function automatic [9:0] horizontal(input [7:0] left,right,input odd_column);
        reg [9:0] a,b;
        begin
            a={2'b0,left};b={2'b0,right};
            horizontal=odd_column?((a<<1)+a+b):(a+(b<<1)+b);
        end
    endfunction
    function automatic [9:0] vertical(input [9:0] upper,lower,input odd_row);
        reg [11:0] a,b,wa,wb;
        begin
            a={2'b0,upper};b={2'b0,lower};
            wa=odd_row?((a<<1)+a):a;wb=odd_row?b:((b<<1)+b);
            // Keep the two truncations before the final /4 rounding.
            vertical=wa[11:2]+wb[11:2]+10'd2;
        end
    endfunction
    wire [29:0] horizontal_sums={horizontal(left_pixel[23:16],s_rgb[23:16],column_phase==4),
        horizontal(left_pixel[15:8],s_rgb[15:8],column_phase==4),
        horizontal(left_pixel[7:0],s_rgb[7:0],column_phase==4)};
    assign s_ready=reset_n&&!clear&&!fault&&!complete&&!calc_pending&&!round_pending&&(!out_valid||m_ready);
    assign m_valid=reset_n&&!clear&&out_valid;
    assign m_rgb=out_rgb;assign m_row_last=out_last;

    // Clocked, unreset read register and memory permit block-RAM inference.
    // The first accepted pixel reserves the read; the second uses it later.
    always @(posedge clk)begin
        if(good_input&&pair_first&&bottom_row)top_sums<=line_sums[line_address];
        if(good_input&&pair_last&&top_row)line_sums[line_address]<=horizontal_sums;
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            column_phase<=0;row_phase<=0;block_x<=0;row_y<=0;complete<=0;fault<=0;
            calc_pending<=0;round_pending<=0;pending_last<=0;pending_odd<=0;
            left_pixel<=0;bottom_sums<=0;rounded_sums<=0;out_valid<=0;out_last<=0;out_rgb<=0;
        end else if(clear)begin
            column_phase<=0;row_phase<=0;block_x<=0;row_y<=0;complete<=0;fault<=0;
            calc_pending<=0;round_pending<=0;pending_last<=0;pending_odd<=0;
            left_pixel<=0;bottom_sums<=0;rounded_sums<=0;out_valid<=0;out_last<=0;out_rgb<=0;
        end else begin
            if(out_valid&&m_ready)out_valid<=0;
            if(stopping)begin fault<=1;calc_pending<=0;round_pending<=0;end
            else begin
                calc_pending<=0;round_pending<=calc_pending;
                if(calc_pending)rounded_sums<={vertical(top_sums[29:20],bottom_sums[29:20],pending_odd),
                    vertical(top_sums[19:10],bottom_sums[19:10],pending_odd),
                    vertical(top_sums[9:0],bottom_sums[9:0],pending_odd)};
                if(round_pending)begin
                    out_rgb<={rounded_sums[29:22],rounded_sums[19:12],rounded_sums[9:2]};
                    out_last<=pending_last;out_valid<=1;
                end
                if(take)begin
                    if(!legal_payload)fault<=1;
                    else begin
                        if(pair_first)left_pixel<=s_rgb;
                        if(pair_last&&bottom_row)begin
                            bottom_sums<=horizontal_sums;pending_last<=row_end;
                            pending_odd<=row_phase==4;calc_pending<=1;
                        end
                        if(column_phase==4)begin
                            column_phase<=0;
                            if(row_end)begin
                                block_x<=0;row_phase<=row_phase==4?3'd0:row_phase+1'b1;
                                if(row_y==LAST_ROW)complete<=1;
                                else row_y<=row_y+1'b1;
                            end else block_x<=block_x+1'b1;
                        end else column_phase<=column_phase+1'b1;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
