`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"
// One selected frame and one immutable record per coordinated port reset.
// Completion covers good EOF and all AXI B retirements, not CPU visibility.
module video_three_branch_capture #(
    parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600,PAD_TOP=40,PAD_BOTTOM=40,
    parameter integer TIMEOUT_CYCLES=625000000
)(
    input wire clk,reset_n,init_done,abort,
    input wire req_valid,output wire req_ready,input wire [1:0] req_slot,
    input wire [31:0] req_frame_id,req_preprocess_version,
    input wire m_valid,input wire [47:0] m_data,output wire m_ready,input wire source_fault,overflow,
    output reg arm_toggle,output wire cancel,busy,port_drained,
    output reg accepted_valid,input wire accepted_ready,
    output reg completion_valid,input wire completion_ready,output reg completion_success,
    output reg [7:0] completion_code,output reg error,output reg [7:0] error_code,
    output reg [31:0] frame_id,preprocess_version,raw_base,preview_base,input_base,output reg [1:0] slot,
    output reg [31:0] captured_pixels,preview_pixels,input_pixels,source_crc,preview_crc,fifo_peak,
    output reg [31:0] raw_written_bytes,preview_written_bytes,input_written_bytes,
    output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
    output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
    output wire [127:0] wdata,output wire [15:0] wstrb,output wire wlast,wvalid,input wire wready,
    input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
    localparam integer SW=(FRAME_WIDTH>=10&&FRAME_WIDTH<=800&&FRAME_WIDTH%10==0)?FRAME_WIDTH:10;
    localparam integer SH=(FRAME_HEIGHT>=10&&FRAME_HEIGHT<=600&&FRAME_HEIGHT%10==0)?FRAME_HEIGHT:10;
    localparam integer IW=SW*2/5,AH=SH*2/5;
    localparam integer PAD_OK=PAD_TOP>=0&&PAD_TOP<=2048&&PAD_BOTTOM>=0&&PAD_BOTTOM<=2048&&
        (64'd1*PAD_TOP+PAD_BOTTOM+AH<=2048);
    localparam integer TOP=PAD_OK?PAD_TOP:0,BOTTOM=PAD_OK?PAD_BOTTOM:0;
    localparam integer IH=TOP+AH+BOTTOM,ISTRIDE=(IW+15)/16*16,IPLANE=ISTRIDE*IH;
    localparam integer TIMER_WIDTH=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES)+1:1;
    localparam [31:0] RROW=SW*3,RSTRIDE=(SW*3+15)/16*16,PROW=SW/2*3,PSTRIDE=(SW/2*3+15)/16*16;
    localparam [31:0] RPIX=SW*SH,PPIX=SW*SH/4,IPIX=IW*AH;
    localparam [31:0] RBYTES=SW*SH*3,PBYTES=SW*SH/4*3,IBYTES=IW*IH*3;
    localparam GEOMETRY_OK=SW==FRAME_WIDTH&&SH==FRAME_HEIGHT&&PAD_OK&&TIMEOUT_CYCLES>0&&
        64'd1*RSTRIDE*SH<=`VIDEO_FRAME_PREVIEW_OFFSET&&
        64'd1*PSTRIDE*(SH/2)+`VIDEO_FRAME_PREVIEW_OFFSET<=`VIDEO_FRAME_SLOT_BYTES&&
        64'd3*IPLANE<=`VIDEO_INPUT_SLOT_BYTES;
    localparam [2:0] IDLE=0,DESCRIPTORS=1,CAPTURE=2,WAIT_EVENT=3,DRAIN=4,DONE=5;
    reg [2:0] state,requested,retired;
    reg seen_online,eof_seen,accepted_started,accepted_consumed;
    reg [TIMER_WIDTH-1:0] timer;
    reg [31:0] source_x,source_y,preview_x,input_x,raw_crc_state,preview_crc_state;
    wire [2:0] req_ready_vec,result_valid_vec,result_success_vec,writer_fault,result_bad;
    wire [23:0] result_codes;
    wire [95:0] result_tags,result_bytes;
    wire [11:0] s_awid;
    wire [95:0] s_awaddr;
    wire [23:0] s_awlen;
    wire [8:0] s_awsize;
    wire [5:0] s_awburst;
    wire [2:0] s_awvalid,s_awready,s_wlast,s_wvalid,s_wready,s_bvalid,s_bready;
    wire [383:0] s_wdata;
    wire [47:0] s_wstrb;
    wire arb_fault,arb_idle,owner_active;
    wire [7:0] arb_code;
    wire [1:0] owner;
    wire raw_pixel_ready,preview_input_ready,input_input_ready;
    wire preview_valid,preview_ready,preview_last,preview_fault,preview_pixel_ready;
    wire input_valid,input_ready,input_last,input_fault,input_pixel_ready;
    wire [23:0] preview_rgb,input_rgb;
    wire [1:0] stream_valid,stream_ready,stream_last;
    wire [255:0] stream_data;
    wire [31:0] stream_keep;
    wire pixel_kind=m_data[47:46]===2'b00,eof_kind=m_data[47:46]===2'b01;
    wire pixel_legal=m_data[44:24]===21'd0&&(^m_data[23:0])!==1'bx&&captured_pixels<RPIX&&
        m_data[45]===(source_x==SW-1);
    wire eof_legal=m_data[45]===1'b0&&m_data[44]===1'b1&&(^m_data[43:0])!==1'bx&&
        captured_pixels===RPIX&&source_x===0&&source_y===SH&&m_data[31:0]===(~raw_crc_state);
    wire all_pixels_ready=raw_pixel_ready&&preview_input_ready&&input_input_ready;
    wire packet_present=state==CAPTURE&&!eof_seen&&m_valid;
    wire count_good=captured_pixels===RPIX&&preview_pixels===PPIX&&input_pixels===IPIX&&preview_x===0&&input_x===0;
    reg [7:0] transport_fault,fault_now;
    wire transport_stop=error||transport_fault!=0;
    assign m_ready=reset_n&&state==CAPTURE&&!eof_seen&&!transport_stop&&
        (pixel_kind&&captured_pixels<RPIX?all_pixels_ready:1'b1);
    wire packet_take=packet_present&&m_ready;
    wire preview_take=preview_valid&&preview_ready,input_take=input_valid&&input_ready;
    wire preview_legal=preview_pixels<PPIX&&(^preview_rgb)!==1'bx&&preview_last===(preview_x==SW/2-1);
    wire input_legal=input_pixels<IPIX&&(^input_rgb)!==1'bx&&input_last===(input_x==IW-1);
    wire stopping=error||fault_now!=0;
    wire pixel_offer=packet_present&&pixel_kind&&pixel_legal&&!stopping;
    assign preview_ready=preview_pixel_ready&&!transport_stop;
    assign input_ready=input_pixel_ready&&!transport_stop;
    assign req_ready=reset_n&&state==IDLE&&init_done&&!abort&&!error&&!arb_fault&&!bvalid;
    assign cancel=error;
    assign busy=state!=IDLE&&state!=DONE;
    assign port_drained=reset_n&&((requested&~retired)==0)&&arb_idle;

    function automatic [31:0] frame_address(input [1:0] which);
        case(which)
            0:frame_address=`VIDEO_FRAME_SLOT_A;
            1:frame_address=`VIDEO_FRAME_SLOT_B;
            2:frame_address=`VIDEO_FRAME_SLOT_C;
            default:frame_address=0;
        endcase
    endfunction
    function automatic [31:0] input_address(input [1:0] which);
        case(which)
            0:input_address=`VIDEO_INPUT_SLOT_A;
            1:input_address=`VIDEO_INPUT_SLOT_B;
            2:input_address=`VIDEO_INPUT_SLOT_C;
            default:input_address=0;
        endcase
    endfunction
    function automatic [31:0] crc_byte(input [31:0] crc,input [7:0] value);
        reg [31:0] c;integer n;
        begin c=crc^{24'd0,value};for(n=0;n<8;n=n+1)c=(c>>1)^(c[0]?32'hedb88320:32'd0);crc_byte=c;end
    endfunction
    wire [31:0] raw_crc_next=crc_byte(crc_byte(crc_byte(raw_crc_state,m_data[23:16]),m_data[15:8]),m_data[7:0]);
    wire [31:0] preview_crc_next=crc_byte(crc_byte(crc_byte(preview_crc_state,preview_rgb[23:16]),preview_rgb[15:8]),preview_rgb[7:0]);
    always @* begin
        transport_fault=0;
        if(seen_online&&!init_done)transport_fault=8'h01;
        else if(arb_fault)transport_fault=8'h09;
        else if((|writer_fault)||(|result_bad))transport_fault=8'h06;
        else if(state!=IDLE&&state!=DONE&&state!=DRAIN)begin
            if(abort)transport_fault=8'h0c;
            else if(overflow)transport_fault=8'h02;
            else if(source_fault)transport_fault=8'h03;
        end
        fault_now=transport_fault;
        if(fault_now==0&&!error&&(state==CAPTURE||state==DESCRIPTORS))begin
            if(packet_take&&(pixel_kind?!pixel_legal:(eof_kind?!eof_legal:1'b1)))fault_now=eof_kind?8'h05:8'h04;
            else if(preview_fault||input_fault||(preview_take&&!preview_legal)||(input_take&&!input_legal))fault_now=8'h0a;
            else if(eof_seen&&(&retired)&&!count_good)fault_now=8'h0a;
            else if(timer>=TIMEOUT_CYCLES-1)fault_now=8'h07;
        end
    end
    rgb888_packer #(.ALLOW_SIMULTANEOUS_TRANSFER(0)) u_raw_packer(
        .clk(clk),.reset_n(reset_n),.flush(1'b0),
        .pixel_valid(pixel_offer&&preview_input_ready&&input_input_ready),.pixel_ready(raw_pixel_ready),
        .pixel_rgb(m_data[23:0]),.pixel_last(m_data[45]),.s_valid(stream_valid[0]),.s_ready(stream_ready[0]),
        .s_data(stream_data[0+:128]),.s_keep(stream_keep[0+:16]),.s_row_last(stream_last[0]));
    preview_downscale #(.FRAME_WIDTH(SW),.FRAME_HEIGHT(SH)) u_preview_scale(
        .clk(clk),.reset_n(reset_n),.clear(1'b0),.s_valid(pixel_offer&&raw_pixel_ready&&input_input_ready),
        .s_ready(preview_input_ready),.s_rgb(m_data[23:0]),.s_row_last(m_data[45]),
        .m_valid(preview_valid),.m_ready(preview_ready),.m_rgb(preview_rgb),.m_row_last(preview_last),.fault(preview_fault));
    detect_bilinear #(.FRAME_WIDTH(SW),.FRAME_HEIGHT(SH)) u_input_scale(
        .clk(clk),.reset_n(reset_n),.clear(1'b0),.s_valid(pixel_offer&&raw_pixel_ready&&preview_input_ready),
        .s_ready(input_input_ready),.s_rgb(m_data[23:0]),.s_row_last(m_data[45]),
        .m_valid(input_valid),.m_ready(input_ready),.m_rgb(input_rgb),.m_row_last(input_last),.fault(input_fault));
    rgb888_packer #(.ALLOW_SIMULTANEOUS_TRANSFER(0)) u_preview_packer(
        .clk(clk),.reset_n(reset_n),.flush(1'b0),.pixel_valid(preview_valid&&!stopping),.pixel_ready(preview_pixel_ready),
        .pixel_rgb(preview_rgb),.pixel_last(preview_last),.s_valid(stream_valid[1]),.s_ready(stream_ready[1]),
        .s_data(stream_data[128+:128]),.s_keep(stream_keep[16+:16]),.s_row_last(stream_last[1]));
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:g_dma
        localparam [3:0] ID=g+1;
        localparam [31:0] ROW=g==0?RROW:PROW,STRIDE=g==0?RSTRIDE:PSTRIDE;
        localparam [15:0] ROWS=g==0?SH:SH/2;
        video_write_dma #(.AXI_ID(ID)) u_dma(
            // Registered cancel breaks the READY -> payload validation ->
            // cancel -> READY feedback. Already buffered valid bytes may
            // enter a DMA on the detecting edge, then drain as a failed shot.
            .clk(clk),.reset_n(reset_n),.online(init_done),.abort(error),
            .req_valid(state==DESCRIPTORS&&!requested[g]&&!stopping),.req_ready(req_ready_vec[g]),
            .req_base(g==0?raw_base:preview_base),.req_row_bytes(ROW),.req_stride(STRIDE),.req_rows(ROWS),.req_tag(frame_id),
            .s_valid(stream_valid[g]),.s_ready(stream_ready[g]),.s_data(stream_data[g*128+:128]),
            .s_keep(stream_keep[g*16+:16]),.s_row_last(stream_last[g]),
            .result_valid(result_valid_vec[g]),.result_ready(1'b1),.result_success(result_success_vec[g]),
            .result_code(result_codes[g*8+:8]),.result_tag(result_tags[g*32+:32]),.written_bytes(result_bytes[g*32+:32]),
            .busy(),.fault(writer_fault[g]),.awid(s_awid[g*4+:4]),.awaddr(s_awaddr[g*32+:32]),
            .awlen(s_awlen[g*8+:8]),.awsize(s_awsize[g*3+:3]),.awburst(s_awburst[g*2+:2]),
            .awvalid(s_awvalid[g]),.awready(s_awready[g]),.wdata(s_wdata[g*128+:128]),.wstrb(s_wstrb[g*16+:16]),
            .wlast(s_wlast[g]),.wvalid(s_wvalid[g]),.wready(s_wready[g]),
            .bid(bid),.bresp(bresp),.bvalid(s_bvalid[g]),.bready(s_bready[g]));
    end endgenerate
    detect_nchw_dma #(.WIDTH(IW),.ACTIVE_HEIGHT(AH),.PAD_TOP(TOP),.PAD_BOTTOM(BOTTOM),
        .ROW_STRIDE(ISTRIDE),.PLANE_STRIDE(IPLANE),.AXI_ID(4'd3)) u_input_dma(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(error),
        .req_valid(state==DESCRIPTORS&&!requested[2]&&!stopping),.req_ready(req_ready_vec[2]),.req_base(input_base),.req_tag(frame_id),
        .s_valid(input_valid&&!stopping),.s_ready(input_pixel_ready),.s_rgb(input_rgb),.s_row_last(input_last),
        .result_valid(result_valid_vec[2]),.result_ready(1'b1),.result_success(result_success_vec[2]),
        .result_code(result_codes[16+:8]),.result_tag(result_tags[64+:32]),.written_bytes(result_bytes[64+:32]),
        .busy(),.fault(writer_fault[2]),.awid(s_awid[8+:4]),.awaddr(s_awaddr[64+:32]),
        .awlen(s_awlen[16+:8]),.awsize(s_awsize[6+:3]),.awburst(s_awburst[4+:2]),
        .awvalid(s_awvalid[2]),.awready(s_awready[2]),.wdata(s_wdata[256+:128]),.wstrb(s_wstrb[32+:16]),
        .wlast(s_wlast[2]),.wvalid(s_wvalid[2]),.wready(s_wready[2]),
        .bid(bid),.bresp(bresp),.bvalid(s_bvalid[2]),.bready(s_bready[2]));
    generate for(g=0;g<3;g=g+1)begin:g_result
        localparam [31:0] BYTES=g==0?RBYTES:g==1?PBYTES:IBYTES;
        assign result_bad[g]=requested[g]&&!retired[g]&&result_valid_vec[g]&&
            (result_success_vec[g]!==1'b1||result_codes[g*8+:8]!==8'd0||result_tags[g*32+:32]!==frame_id||result_bytes[g*32+:32]!==BYTES);
    end endgenerate
    axi_write_arbiter3 u_arbiter(
        .clk(clk),.reset_n(reset_n),.s_awid(s_awid),.s_awaddr(s_awaddr),.s_awlen(s_awlen),
        .s_awsize(s_awsize),.s_awburst(s_awburst),.s_awvalid(s_awvalid),.s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),
        .s_bvalid(s_bvalid),.s_bready(s_bready),.awid(awid),.awaddr(awaddr),.awlen(awlen),
        .awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),.fault(arb_fault),.fault_code(arb_code),
        .owner_active(owner_active),.owner(owner),.idle(arb_idle));

    integer branch;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;requested<=0;retired<=0;seen_online<=0;eof_seen<=0;timer<=0;arm_toggle<=0;
            accepted_valid<=0;accepted_started<=0;accepted_consumed<=0;completion_valid<=0;completion_success<=0;completion_code<=0;
            error<=0;error_code<=0;slot<=0;frame_id<=0;preprocess_version<=0;raw_base<=0;preview_base<=0;input_base<=0;
            captured_pixels<=0;preview_pixels<=0;input_pixels<=0;source_crc<=0;preview_crc<=0;fifo_peak<=0;
            raw_written_bytes<=0;preview_written_bytes<=0;input_written_bytes<=0;
            source_x<=0;source_y<=0;preview_x<=0;input_x<=0;raw_crc_state<=32'hffffffff;preview_crc_state<=32'hffffffff;
        end else begin
            if(init_done)seen_online<=1;
            if(accepted_valid&&accepted_ready)begin accepted_valid<=0;accepted_consumed<=1;end
            if(completion_valid&&completion_ready)completion_valid<=0;
            if((state==DESCRIPTORS||state==CAPTURE)&&!error&&timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            for(branch=0;branch<3;branch=branch+1)if(requested[branch]&&!retired[branch]&&result_valid_vec[branch])begin
                retired[branch]<=1;
                case(branch)
                    0:raw_written_bytes<=result_bytes[0+:32];
                    1:preview_written_bytes<=result_bytes[32+:32];
                    2:input_written_bytes<=result_bytes[64+:32];
                endcase
            end
            if(!error&&fault_now!=0)begin
                error<=1;error_code<=fault_now;
                if(state!=DONE)state<=DRAIN;
            end else if(!error)case(state)
                IDLE:if(req_valid&&req_ready)begin
                    slot<=req_slot;frame_id<=req_frame_id;preprocess_version<=req_preprocess_version;
                    raw_base<=frame_address(req_slot);preview_base<=frame_address(req_slot)+`VIDEO_FRAME_PREVIEW_OFFSET;
                    input_base<=input_address(req_slot);
                    if(!GEOMETRY_OK||(^req_slot===1'bx)||req_slot==3||(^req_frame_id===1'bx)||
                       req_preprocess_version!==`VIDEO_INPUT_PREPROCESS_VERSION)begin error<=1;error_code<=8'h08;state<=DRAIN;end
                    else state<=DESCRIPTORS;
                end
                DESCRIPTORS:begin
                    requested<=requested|req_ready_vec;
                    // Finish top-padding writes before selecting a physical
                    // frame: their initial stall can exceed the ingress FIFO.
                    if(&(requested|req_ready_vec)&&input_pixel_ready)begin arm_toggle<=~arm_toggle;state<=CAPTURE;end
                end
                CAPTURE:if(eof_seen&&(&retired)&&port_drained&&count_good)state<=WAIT_EVENT;
                WAIT_EVENT:if(accepted_consumed)begin completion_valid<=1;completion_success<=1;completion_code<=0;state<=DONE;end
                default:begin end
            endcase
            if(state==DRAIN&&port_drained)begin completion_valid<=1;completion_success<=0;completion_code<=error_code;state<=DONE;end
            if(packet_take&&!stopping)begin
                if(pixel_kind)begin
                    captured_pixels<=captured_pixels+1'b1;raw_crc_state<=raw_crc_next;
                    if(!accepted_started)begin accepted_started<=1;accepted_valid<=1;end
                    if(source_x==SW-1)begin source_x<=0;source_y<=source_y+1'b1;end else source_x<=source_x+1'b1;
                end else begin eof_seen<=1;source_crc<=m_data[31:0];fifo_peak<={20'd0,m_data[43:32]};end
            end
            if(preview_take&&!stopping)begin
                preview_pixels<=preview_pixels+1'b1;preview_crc_state<=preview_crc_next;preview_crc<=~preview_crc_next;
                if(preview_x==SW/2-1)preview_x<=0;else preview_x<=preview_x+1'b1;
            end
            if(input_take&&!stopping)begin
                input_pixels<=input_pixels+1'b1;if(input_x==IW-1)input_x<=0;else input_x<=input_x+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
