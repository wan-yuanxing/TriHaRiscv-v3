`timescale 1ns/1ps
`default_nettype none
// Post-quantization bytes only. req_zero is supplied explicitly by the owner
// of the model parameters; this module performs no scaling or quantization.
module detect_c8_pack #(
    parameter integer WIDTH=160,ACTIVE_HEIGHT=120,STORAGE_HEIGHT=128
)(
    input wire clk,reset_n,clear,
    input wire req_valid,output wire req_ready,input wire [7:0] req_zero,
    input wire s_valid,output wire s_ready,
    input wire [23:0] s_q_bgr,input wire s_row_last,s_frame_last,s_padding,
    output wire m_valid,input wire m_ready,
    output wire [127:0] m_data,output wire [15:0] m_keep,
    output wire m_row_last,m_frame_last,
    output reg done,fault
);
    localparam integer XB=WIDTH>1?$clog2(WIDTH):1;
    localparam integer YB=STORAGE_HEIGHT>1?$clog2(STORAGE_HEIGHT):1;
    localparam [XB-1:0] LAST_X=WIDTH-1;
    localparam [YB-1:0] LAST_Y=STORAGE_HEIGHT-1;
    initial begin
        if(WIDTH<1||WIDTH>2048||ACTIVE_HEIGHT<1||ACTIVE_HEIGHT>2048||
           STORAGE_HEIGHT<ACTIVE_HEIGHT||STORAGE_HEIGHT>2048)
            $fatal(1,"detect_c8_pack: invalid geometry");
    end
    reg active,complete,half_full,out_valid,out_row_last,out_frame_last;
    reg [XB-1:0] x;
    reg [YB-1:0] y;
    reg [7:0] zero_value;
    reg [63:0] first_pixel;
    reg [127:0] out_data;
    reg [15:0] out_keep;
    wire row_end=x==LAST_X;
    wire frame_end=row_end&&y==LAST_Y;
    wire padding=y>=ACTIVE_HEIGHT;
    wire take=s_valid&&s_ready;
    wire legal_payload=((^s_q_bgr)!==1'bx)&&(s_row_last===row_end)&&
        (s_frame_last===frame_end)&&(s_padding===padding)&&
        (!padding||(s_q_bgr==={3{zero_value}}));
    wire extra_input=complete&&s_valid;
    wire bad_input=take&&!legal_payload;
    wire stopping=fault||extra_input||bad_input;
    wire [63:0] pixel_bytes={{5{zero_value}},s_q_bgr[7:0],s_q_bgr[15:8],s_q_bgr[23:16]};
    assign req_ready=reset_n&&!clear&&!fault&&!active;
    assign s_ready=reset_n&&!clear&&!fault&&active&&!complete&&(!out_valid||m_ready);
    assign m_valid=reset_n&&!clear&&out_valid;
    assign m_data=out_data;
    assign m_keep=out_keep;
    assign m_row_last=out_row_last;
    assign m_frame_last=out_frame_last;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            active<=0;complete<=0;half_full<=0;out_valid<=0;x<=0;y<=0;zero_value<=0;
            first_pixel<=0;out_data<=0;out_keep<=0;out_row_last<=0;out_frame_last<=0;done<=0;fault<=0;
        end else if(clear)begin
            active<=0;complete<=0;half_full<=0;out_valid<=0;x<=0;y<=0;zero_value<=0;
            first_pixel<=0;out_data<=0;out_keep<=0;out_row_last<=0;out_frame_last<=0;done<=0;fault<=0;
        end else begin
            if(out_valid&&m_ready)begin
                out_valid<=0;
                if(out_frame_last&&!stopping)done<=1;
            end
            if(stopping)begin fault<=1;done<=0;end
            if(req_valid&&req_ready)begin
                if((^req_zero)===1'bx)fault<=1;
                else begin active<=1;zero_value<=req_zero;end
            end
            if(take&&legal_payload)begin
                if(half_full||row_end)begin
                    out_data<=half_full?{pixel_bytes,first_pixel}:{64'd0,pixel_bytes};
                    out_keep<=half_full?16'hffff:16'h00ff;
                    out_row_last<=row_end;out_frame_last<=frame_end;
                    out_valid<=1;half_full<=0;
                end else begin first_pixel<=pixel_bytes;half_full<=1;end
                if(row_end)begin
                    x<=0;
                    if(frame_end)complete<=1;
                    else y<=y+1'b1;
                end else x<=x+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
