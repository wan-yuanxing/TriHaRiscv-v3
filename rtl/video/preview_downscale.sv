`timescale 1ns/1ps
`default_nettype none

// One explicitly cleared frame. clear is legal only with the producer idle.
// An even source row stores horizontal sums; the following odd row reads them
// synchronously. The RAM has no reset, and every location is written before use.
module preview_downscale #(
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600
)(
    input wire clk,reset_n,clear,
    input wire s_valid,
    output wire s_ready,
    input wire [23:0] s_rgb,
    input wire s_row_last,
    output wire m_valid,
    input wire m_ready,
    output wire [23:0] m_rgb,
    output wire m_row_last,
    output reg fault
);
    localparam integer HALF_WIDTH=FRAME_WIDTH>=2?FRAME_WIDTH/2:1;
    localparam integer X_BITS=FRAME_WIDTH>=2?$clog2(FRAME_WIDTH):1;
    localparam integer Y_BITS=FRAME_HEIGHT>=2?$clog2(FRAME_HEIGHT):1;
    localparam integer RAM_BITS=HALF_WIDTH>=2?$clog2(HALF_WIDTH):1;

    initial begin
        if(FRAME_WIDTH<2 || FRAME_WIDTH>2048 || FRAME_WIDTH%2!=0 ||
           FRAME_HEIGHT<2 || FRAME_HEIGHT>2048 || FRAME_HEIGHT%2!=0)
            $fatal(1,"preview_downscale: invalid frame geometry");
    end

    reg [X_BITS-1:0] x;
    reg [Y_BITS-1:0] y;
    reg complete;
    reg [23:0] left_pixel;
    reg [26:0] line_sums [0:HALF_WIDTH-1];
    reg [26:0] top_sums,bottom_sums;
    reg read_pending,pending_row_last;
    reg output_valid,output_row_last;
    reg [23:0] output_rgb;

    localparam [X_BITS-1:0] LAST_X=FRAME_WIDTH-1;
    localparam [Y_BITS-1:0] LAST_Y=FRAME_HEIGHT-1;
    wire row_end=x==LAST_X;
    wire last_row=y==LAST_Y;
    wire [RAM_BITS-1:0] pair_address=x>>1;
    wire input_take=s_valid && s_ready;
    wire good_input=input_take && (s_row_last===row_end);
    wire [8:0] horizontal_r={1'b0,left_pixel[23:16]}+{1'b0,s_rgb[23:16]};
    wire [8:0] horizontal_g={1'b0,left_pixel[15:8]}+{1'b0,s_rgb[15:8]};
    wire [8:0] horizontal_b={1'b0,left_pixel[7:0]}+{1'b0,s_rgb[7:0]};
    wire [9:0] rounded_r={1'b0,top_sums[26:18]}+{1'b0,bottom_sums[26:18]}+10'd2;
    wire [9:0] rounded_g={1'b0,top_sums[17:9]}+{1'b0,bottom_sums[17:9]}+10'd2;
    wire [9:0] rounded_b={1'b0,top_sums[8:0]}+{1'b0,bottom_sums[8:0]}+10'd2;

    assign m_valid=reset_n && !clear && output_valid;
    assign m_rgb=output_rgb;
    assign m_row_last=output_row_last;
    // A pending RAM read reserves the only output slot. A consumed output may
    // accept a new input on that same edge, without losing either transfer.
    assign s_ready=reset_n && !clear && !fault && !complete &&
                   !read_pending && (!output_valid || m_ready);

    // Keep RAM and its read data register separate from resettable state so
    // synthesis can infer a block RAM with a clocked read port.
    always @(posedge clk)begin
        if(good_input && x[0] && !y[0])
            line_sums[pair_address]<={horizontal_r,horizontal_g,horizontal_b};
        if(good_input && x[0] && y[0])
            top_sums<=line_sums[pair_address];
    end

    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            x<=0;y<=0;complete<=0;fault<=0;left_pixel<=0;
            bottom_sums<=0;read_pending<=0;pending_row_last<=0;
            output_valid<=0;output_rgb<=0;output_row_last<=0;
        end else if(clear)begin
            x<=0;y<=0;complete<=0;fault<=0;left_pixel<=0;
            bottom_sums<=0;read_pending<=0;pending_row_last<=0;
            output_valid<=0;output_rgb<=0;output_row_last<=0;
        end else begin
            if(output_valid && m_ready)output_valid<=0;
            if(read_pending)begin
                output_rgb<={rounded_r[9:2],rounded_g[9:2],rounded_b[9:2]};
                output_row_last<=pending_row_last;
                output_valid<=1;
                read_pending<=0;
            end
            // VALID after the final accepted source pixel is an attempted
            // excess pixel, even though READY remains low for the closed frame.
            if(complete && s_valid)fault<=1;
            if(input_take)begin
                if(s_row_last!==row_end)fault<=1;
                else begin
                    if(!x[0])left_pixel<=s_rgb;
                    else if(y[0])begin
                        bottom_sums<={horizontal_r,horizontal_g,horizontal_b};
                        pending_row_last<=row_end;
                        read_pending<=1;
                    end
                    if(row_end)begin
                        x<=0;
                        if(last_row)complete<=1;
                        else y<=y+1'b1;
                    end else x<=x+1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
