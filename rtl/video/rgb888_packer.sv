`timescale 1ns/1ps
`default_nettype none
// Backpressurable pixels only. Physical HDMI needs a separate sized FIFO/CDC.
// Increasing byte addresses contain R,G,B. flush deliberately cancels an old
// stream and is legal only after its DMA consumer has stopped taking data.
module rgb888_packer(
    input wire clk,reset_n,flush,
    input wire pixel_valid,input wire [23:0] pixel_rgb,input wire pixel_last,
    output wire pixel_ready,
    output wire s_valid,output wire [127:0] s_data,output wire [15:0] s_keep,
    output wire s_row_last,input wire s_ready
);
    reg [143:0] reservoir,next_reservoir;
    reg [4:0] count,next_count;
    reg ending,next_ending;
    wire output_take=s_valid&&s_ready;
    wire input_take=pixel_valid&&pixel_ready;
    assign s_valid=reset_n && !flush && (count>=16 || (ending && count!=0));
    assign s_data=reservoir[127:0];
    assign s_keep=count>=16?16'hffff:(16'hffff>>(16-count));
    assign s_row_last=ending && count<=16;
    assign pixel_ready=reset_n && !flush && !ending && (count<=15 || output_take);
    always @* begin
        next_reservoir=reservoir;next_count=count;next_ending=ending;
        if(output_take)begin
            next_reservoir=reservoir>>128;
            next_count=count>=16?count-16:0;
            if(s_row_last)next_ending=0;
        end
        if(input_take)begin
            next_reservoir[next_count*8+:24]={pixel_rgb[7:0],pixel_rgb[15:8],pixel_rgb[23:16]};
            next_count=next_count+3;
            if(pixel_last)next_ending=1;
        end
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin reservoir<=0;count<=0;ending<=0;end
        else if(flush)begin reservoir<=0;count<=0;ending<=0;end
        else begin reservoir<=next_reservoir;count<=next_count;ending<=next_ending;end
    end
endmodule
`default_nettype wire
