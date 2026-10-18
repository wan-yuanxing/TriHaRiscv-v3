`timescale 1ns/1ps
`default_nettype none
// Geometry/ordering before quantization. Padding is RAW zero, not an INT8
// encoding. A later quantizer must preserve all three metadata bits.
module detect_input_pad #(
    parameter integer WIDTH=160,ACTIVE_HEIGHT=120,STORAGE_HEIGHT=128
)(
    input wire clk,reset_n,clear,
    input wire s_valid,output wire s_ready,
    input wire [23:0] s_rgb,input wire s_row_last,
    output wire m_valid,input wire m_ready,
    output wire [23:0] m_bgr,
    output wire m_row_last,m_frame_last,m_padding,
    output reg fault
);
    localparam integer XB=WIDTH>1?$clog2(WIDTH):1;
    localparam integer YB=STORAGE_HEIGHT>1?$clog2(STORAGE_HEIGHT):1;
    localparam [XB-1:0] LAST_X=WIDTH-1;
    localparam [YB-1:0] LAST_Y=STORAGE_HEIGHT-1,LAST_ACTIVE=ACTIVE_HEIGHT-1;
    initial begin
        if(WIDTH<1||WIDTH>2048||ACTIVE_HEIGHT<1||ACTIVE_HEIGHT>2048||
           STORAGE_HEIGHT<ACTIVE_HEIGHT||STORAGE_HEIGHT>2048)
            $fatal(1,"detect_input_pad: invalid geometry");
    end
    reg [XB-1:0] x;
    reg [YB-1:0] y;
    reg source_done,complete,out_valid,out_row_last,out_frame_last,out_padding;
    reg [23:0] out_bgr;
    wire row_end=x==LAST_X;
    wire frame_end=row_end&&y==LAST_Y;
    wire slot_free=!out_valid||m_ready;
    wire extra_input=source_done&&s_valid;
    wire stopping=fault||extra_input;
    wire take=s_valid&&s_ready;
    wire legal_payload=(s_row_last===row_end)&&((^s_rgb)!==1'bx);
    wire generate_pad=source_done&&!complete&&slot_free&&!stopping;
    assign s_ready=reset_n&&!clear&&!fault&&!source_done&&slot_free;
    assign m_valid=reset_n&&!clear&&out_valid;
    assign m_bgr=out_bgr;
    assign m_row_last=out_row_last;
    assign m_frame_last=out_frame_last;
    assign m_padding=out_padding;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            x<=0;y<=0;source_done<=0;complete<=0;fault<=0;
            out_valid<=0;out_bgr<=0;out_row_last<=0;out_frame_last<=0;out_padding<=0;
        end else if(clear)begin
            x<=0;y<=0;source_done<=0;complete<=0;fault<=0;
            out_valid<=0;out_bgr<=0;out_row_last<=0;out_frame_last<=0;out_padding<=0;
        end else begin
            if(out_valid&&m_ready)out_valid<=0;
            if(extra_input)fault<=1;
            if(take&&!legal_payload)fault<=1;
            if((take&&legal_payload)||generate_pad)begin
                out_valid<=1;
                out_bgr<=generate_pad?24'd0:{s_rgb[7:0],s_rgb[15:8],s_rgb[23:16]};
                out_padding<=generate_pad;out_row_last<=row_end;out_frame_last<=frame_end;
                if(take&&row_end&&y==LAST_ACTIVE)source_done<=1;
                if(row_end)begin
                    x<=0;
                    if(y==LAST_Y)complete<=1;
                    else y<=y+1'b1;
                end else x<=x+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
