`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"
`include "video_display.vh"
// Leased record validator: caller holds record_i and mode_i unchanged from
// start acceptance through result acceptance. No buffer or external DMA here.
// Face-board profiles can omit landmarks. In that profile reject both the
// drawing flag and all point payloads; rectangle/primary/avatar fields retain
// their full ABI and all sixteen rectangle lanes remain available.
module display_record_guard #(parameter integer ENABLE_LANDMARKS=1)(
    input wire clk_i,rst_ni,input wire start_valid_i,output wire start_ready_o,
    input wire [`VDISP_RECORD_BITS-1:0] record_i,input wire [1:0] mode_i,
    input wire [2:0] modes_i,input wire asset_ready_i,input wire [31:0] asset_id_i,asset_generation_i,
    output reg result_valid_o,input wire result_ready_i,output reg [7:0] result_code_o
);
    reg busy,header;reg [3:0] lane;
    function automatic [31:0] word (input [5119:0] data,input integer n);word=data[n*32+:32];endfunction
    function automatic positive_rect(input [31:0] xy0,xy1);
        positive_rect=$signed(xy1[15:0])>$signed(xy0[15:0])&&$signed(xy1[31:16])>$signed(xy0[31:16]);
    endfunction
    wire [31:0] flags=word(record_i,`VDISP_FIELD_FLAGS),mask=word(record_i,`VDISP_FIELD_BOX_MASK);
    wire asset_wait=mode_i==2&&!flags[1]&&flags[3]&&flags[4]&&asset_ready_i===1'b0;
    wire [63:0] asset_end={32'd0,word(record_i,`VDISP_FIELD_ASSET_BASE)}+{32'd0,word(record_i,`VDISP_FIELD_ASSET_BYTES)};
    // Check fixed record slices before selecting a lane. Selecting the entire
    // 256-bit box first puts the lane mux in front of every geometry comparison.
    function automatic invalid_box(input [255:0] data,input present);
        integer point;
        begin
            invalid_box=0;
            if(!present)begin
                if(data!=0)invalid_box=1;
            end else begin
                if(!positive_rect(data[31:0],data[63:32])||data[95:69]!=0)invalid_box=1;
                if(!ENABLE_LANDMARKS&&data[255:64]!=0)invalid_box=1;
                for(point=0;point<5;point=point+1)
                    if(!data[64+point]&&data[(3+point)*32+:32]!=0)invalid_box=1;
            end
        end
    endfunction
    wire [15:0] invalid_lanes;
    genvar lane_index;
    generate for(lane_index=0;lane_index<16;lane_index=lane_index+1)begin:g_lane_check
        assign invalid_lanes[lane_index]=invalid_box(record_i[(32+lane_index*8)*32+:256],mask[lane_index]);
    end endgenerate
    // The record is leased unchanged until the result is accepted. Capture
    // all lane checks at start; the existing header cycle separates their
    // geometry/reduction logic from the lane mux without adding latency.
    reg [15:0] invalid_lanes_q;
    wire [7:0] lane_code=invalid_lanes_q[lane]?8'h12:8'h00;
    reg [7:0] head_code;
    integer h;
    always @* begin
        head_code=0;
        if((^{record_i,mode_i})===1'bx)head_code=1;
        else if(word(record_i,`VDISP_FIELD_VERSION)!=`VDISP_VERSION||word(record_i,`VDISP_FIELD_BYTES)!=`VDISP_RECORD_BYTES||
            word(record_i,`VDISP_FIELD_SLOT)>2||word(record_i,`VDISP_FIELD_FRAME)==0||
            word(record_i,`VDISP_FIELD_WIDTH)!=800||word(record_i,`VDISP_FIELD_HEIGHT)!=600||
            word(record_i,`VDISP_FIELD_RAW_STRIDE)!=`VIDEO_FRAME_RAW_STRIDE||
            word(record_i,`VDISP_FIELD_RAW_BASE)!=(word(record_i,`VDISP_FIELD_SLOT)==0?`VIDEO_FRAME_SLOT_A:
                word(record_i,`VDISP_FIELD_SLOT)==1?`VIDEO_FRAME_SLOT_B:`VIDEO_FRAME_SLOT_C))head_code=8'h10;
        else if(flags[31:5]!=0||(!ENABLE_LANDMARKS&&flags[2])||!flags[0]||word(record_i,`VDISP_FIELD_RESULT_FRAME)!=word(record_i,`VDISP_FIELD_FRAME)||
            word(record_i,`VDISP_FIELD_RESULT_GENERATION)!=word(record_i,`VDISP_FIELD_GENERATION)||mask[31:16]!=0||
            (flags[1]!=(mask==0))||(flags[1]&&flags[4:2]!=0)||
            word(record_i,`VDISP_FIELD_PRIMARY_INDEX)>15||(!flags[4]&&word(record_i,`VDISP_FIELD_PRIMARY_INDEX)!=0)||
            (flags[4]&&!mask[word(record_i,`VDISP_FIELD_PRIMARY_INDEX)]))head_code=8'h11;
        else begin
            for(h=23;h<32;h=h+1)if(word(record_i,h)!=0)head_code=8'h12;
            if(head_code==0)begin
                if(flags[3])begin
                    if(!flags[4]||(word(record_i,`VDISP_FIELD_ASSET_BASE)&15)!=0||
                        word(record_i,`VDISP_FIELD_ASSET_BASE)<32'h82600000||asset_end>64'h82800000||
                        word(record_i,`VDISP_FIELD_ASSET_BYTES)!=262144||word(record_i,`VDISP_FIELD_ASSET_WIDTH)!=256||
                        word(record_i,`VDISP_FIELD_ASSET_HEIGHT)!=256||word(record_i,`VDISP_FIELD_ASSET_STRIDE)!=1024||
                        !positive_rect(word(record_i,`VDISP_FIELD_AVATAR_XY0),word(record_i,`VDISP_FIELD_AVATAR_XY1)))head_code=8'h13;
                end else begin
                    for(h=14;h<=22;h=h+1)if(word(record_i,h)!=0)head_code=8'h13;
                end
            end
            if(head_code==0&&(mode_i==3||modes_i[mode_i]!==1'b1||
                (mode_i==2&&!flags[1]&&(!flags[3]||!flags[4]||
                  (asset_ready_i!==1'b0&&(asset_ready_i!==1'b1||
                   asset_id_i!==word(record_i,`VDISP_FIELD_ASSET_ID)||asset_generation_i!==word(record_i,`VDISP_FIELD_ASSET_GENERATION)))))))
                head_code=8'h14;
        end
    end
    assign start_ready_o=rst_ni&&!busy&&!result_valid_o;
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin busy<=0;header<=0;lane<=0;result_valid_o<=0;result_code_o<=0;invalid_lanes_q<=0;end
        else begin
            if(result_valid_o&&result_ready_i)result_valid_o<=0;
            if(start_valid_i&&start_ready_o)begin
                busy<=1;header<=1;lane<=0;invalid_lanes_q<=invalid_lanes;
            end
            if(busy)begin
                if(header)begin
                    if(!asset_wait)header<=0;
                    if(head_code!=0)begin busy<=0;result_valid_o<=1;result_code_o<=head_code;end
                end else if(lane_code!=0||lane==15)begin
                    busy<=0;result_valid_o<=1;result_code_o<=lane_code;
                end else lane<=lane+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
