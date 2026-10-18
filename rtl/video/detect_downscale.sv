`timescale 1ns/1ps
`default_nettype none

// One explicitly cleared frame. Pixel groups and row groups are exactly five;
// no source coordinates are skipped. The cumulative RAM is overwritten by the
// first source row of each group before it is read by subsequent rows.
module detect_downscale #(
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
    localparam integer BLOCKS=FRAME_WIDTH>=5?FRAME_WIDTH/5:1;
    localparam integer A_BITS=BLOCKS>1?$clog2(BLOCKS):1;
    localparam integer Y_BITS=FRAME_HEIGHT>1?$clog2(FRAME_HEIGHT):1;
    localparam [A_BITS-1:0] LAST_BLOCK=BLOCKS-1;
    localparam [Y_BITS-1:0] LAST_ROW=FRAME_HEIGHT-1;
    initial begin
        if(FRAME_WIDTH<5||FRAME_WIDTH>2045||FRAME_WIDTH%5!=0||
           FRAME_HEIGHT<5||FRAME_HEIGHT>2045||FRAME_HEIGHT%5!=0)
            $fatal(1,"detect_downscale: invalid frame geometry");
    end

    reg [2:0] column_phase,row_phase;
    reg [A_BITS-1:0] block_x;
    reg [Y_BITS-1:0] row_y;
    reg complete,output_valid,output_last;
    reg [23:0] output_rgb;
    reg [10:0] horizontal_r,horizontal_g,horizontal_b;
    reg [38:0] column_sums [0:BLOCKS-1];
    reg [38:0] previous_rows;
    reg sum_pending,product_pending,pending_last;
    reg [38:0] rounded_sums;
    reg [25:0] product_r,product_g,product_b;
    wire block_end=column_phase==4;
    wire row_end=block_end&&block_x==LAST_BLOCK;
    wire input_take=s_valid&&s_ready;
    wire legal_payload=(s_row_last===row_end)&&((^s_rgb)!==1'bx);
    wire good_input=input_take&&legal_payload;
    wire [10:0] five_r=horizontal_r+{3'b0,s_rgb[23:16]};
    wire [10:0] five_g=horizontal_g+{3'b0,s_rgb[15:8]};
    wire [10:0] five_b=horizontal_b+{3'b0,s_rgb[7:0]};
    wire [12:0] total_r=(row_phase==0?13'd0:previous_rows[38:26])+{2'b0,five_r};
    wire [12:0] total_g=(row_phase==0?13'd0:previous_rows[25:13])+{2'b0,five_g};
    wire [12:0] total_b=(row_phase==0?13'd0:previous_rows[12:0])+{2'b0,five_b};
    wire [12:0] rounded_r=total_r+13'd12;
    wire [12:0] rounded_g=total_g+13'd12;
    wire [12:0] rounded_b=total_b+13'd12;
    // floor(n/25) == floor(n*5243/2^17) for the entire reachable
    // n=12..6387 range. The integer test exhausts every source sum 0..6375.
    // Separate RAM/add, constant multiply and output stages at the core clock.
    assign s_ready=reset_n&&!clear&&!fault&&!complete&&!sum_pending&&!product_pending&&
                   (!output_valid||m_ready);
    assign m_valid=reset_n&&!clear&&output_valid;
    assign m_rgb=output_rgb;
    assign m_row_last=output_last;

    // Clocked read at the first pixel, use at the fifth accepted pixel. These
    // registers have no reset so the memory can infer a block RAM read port.
    always @(posedge clk)begin
        if(good_input&&column_phase==0&&row_phase!=0)
            previous_rows<=column_sums[block_x];
        if(good_input&&block_end&&row_phase!=4)
            column_sums[block_x]<={total_r,total_g,total_b};
        if(good_input&&block_end&&row_phase==4)
            rounded_sums<={rounded_r,rounded_g,rounded_b};
        if(reset_n&&!clear&&sum_pending)begin
            product_r<=rounded_sums[38:26]*13'd5243;
            product_g<=rounded_sums[25:13]*13'd5243;
            product_b<=rounded_sums[12:0]*13'd5243;
        end
    end

    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            column_phase<=0;row_phase<=0;block_x<=0;row_y<=0;
            horizontal_r<=0;horizontal_g<=0;horizontal_b<=0;
            complete<=0;fault<=0;output_valid<=0;output_rgb<=0;output_last<=0;
            sum_pending<=0;product_pending<=0;pending_last<=0;
        end else if(clear)begin
            column_phase<=0;row_phase<=0;block_x<=0;row_y<=0;
            horizontal_r<=0;horizontal_g<=0;horizontal_b<=0;
            complete<=0;fault<=0;output_valid<=0;output_rgb<=0;output_last<=0;
            sum_pending<=0;product_pending<=0;pending_last<=0;
        end else begin
            if(output_valid&&m_ready)output_valid<=0;
            sum_pending<=0;
            product_pending<=sum_pending;
            if(product_pending)begin
                output_rgb<={product_r[24:17],product_g[24:17],product_b[24:17]};
                output_last<=pending_last;output_valid<=1;
            end
            if(complete&&s_valid)fault<=1;
            if(input_take)begin
                if(!legal_payload)fault<=1;
                else begin
                    if(block_end)begin
                        horizontal_r<=0;horizontal_g<=0;horizontal_b<=0;column_phase<=0;
                        if(row_phase==4)begin
                            pending_last<=row_end;sum_pending<=1;
                        end
                        if(row_end)begin
                            block_x<=0;
                            row_phase<=row_phase==4?3'd0:row_phase+1'b1;
                            if(row_y==LAST_ROW)complete<=1;
                            else row_y<=row_y+1'b1;
                        end else block_x<=block_x+1'b1;
                    end else begin
                        horizontal_r<=five_r;horizontal_g<=five_g;horizontal_b<=five_b;
                        column_phase<=column_phase+1'b1;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
