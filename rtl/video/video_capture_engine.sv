`timescale 1ns/1ps
`default_nettype none
module video_capture_engine #(
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600,
    parameter integer TIMEOUT_CYCLES=625000000
)(
    input wire clk,reset_n,init_done,
    output wire busy,output reg done,error,
    output wire [7:0] phase,output reg [7:0] error_code,
    input wire m_valid,input wire [47:0] m_data,output wire m_ready,
    output reg arm_toggle,output wire cancel,input wire source_fault,overflow,
    output reg [31:0] captured_pixels,checked_bytes,source_crc,ddr_crc,fifo_peak,
    output wire [31:0] frame_tag,
    output wire [27:0] axi_awaddr,output wire axi_awuser_ap,
    output wire [3:0] axi_awuser_id,axi_awlen,
    input wire axi_awready,output wire axi_awvalid,
    output wire [255:0] axi_wdata,output wire [31:0] axi_wstrb,
    input wire axi_wready,input wire [3:0] axi_wusero_id,
    input wire axi_wusero_last,
    output wire [27:0] axi_araddr,output wire axi_aruser_ap,
    output wire [3:0] axi_aruser_id,axi_arlen,
    input wire axi_arready,output wire axi_arvalid,
    input wire [255:0] axi_rdata,input wire [3:0] axi_rid,
    input wire axi_rlast,axi_rvalid
);
    // Single-shot physical-source transport. Only coordinated global reset
    // clears the source FIFO, packer, DMA or bridge; an error drains ownership.
    localparam [31:0] RAW_BASE=32'h87300000;
    localparam [63:0] ROW_WIDE=64'd3*FRAME_WIDTH;
    localparam [63:0] STRIDE_WIDE=(ROW_WIDE+15)&64'hfffffffffffffff0;
    localparam [63:0] END_WIDE=64'h87300000+(FRAME_HEIGHT-1)*STRIDE_WIDE+ROW_WIDE;
    localparam [31:0] ROW_BYTES=ROW_WIDE[31:0],STRIDE=STRIDE_WIDE[31:0];
    localparam [31:0] FRAME_PIXELS=FRAME_WIDTH*FRAME_HEIGHT,FRAME_BYTES=FRAME_PIXELS*3;
    localparam integer TIMER_WIDTH=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    localparam [3:0] WAIT_INIT=0,DESCRIPTOR=1,CAPTURE=2,READ_SETUP=3,
        READ_AR=4,READ_R=5,READ_BYTE=6,FINISH=7,FAILED=8;
    reg [3:0] state;
    reg seen_online,eof_seen,dma_retired;
    reg [TIMER_WIDTH-1:0] timer;
    reg [31:0] expected_x,expected_y;
    reg [31:0] read_address,row_base,row_remaining,read_row,crc_state;
    reg [4:0] read_beats,read_index,byte_index,byte_count;
    reg [127:0] read_hold;
    wire dma_req_ready,dma_result_valid,dma_success,dma_busy,dma_fault;
    wire [7:0] dma_code;
    wire [31:0] dma_tag,dma_bytes;
    wire [3:0] dma_awid;
    wire [31:0] dma_awaddr;
    wire [7:0] dma_awlen;
    wire [2:0] dma_awsize;
    wire [1:0] dma_awburst;
    wire dma_awvalid,dma_wvalid,dma_wlast,dma_bready;
    wire [127:0] dma_wdata;
    wire [15:0] dma_wstrb;
    wire bridge_awready,bridge_wready,bridge_bvalid,bridge_arready,bridge_rvalid,bridge_rlast;
    wire [3:0] bridge_bid,bridge_rid;
    wire [1:0] bridge_bresp,bridge_rresp;
    wire [127:0] bridge_rdata;
    wire bridge_fault;
    wire [7:0] bridge_code;
    wire pixel_ready,stream_valid,stream_ready,stream_last;
    wire [127:0] stream_data;
    wire [15:0] stream_keep;
    wire pixel_kind=m_data[47:46]===2'b00;
    wire eof_kind=m_data[47:46]===2'b01;
    wire pixel_legal=m_data[44:24]===21'd0 && captured_pixels<FRAME_PIXELS &&
        m_data[45]===(expected_x==FRAME_WIDTH-1);
    wire eof_legal=m_data[45]===1'b0 && m_data[44]===1'b1 &&
        captured_pixels==FRAME_PIXELS && expected_x==0 && expected_y==FRAME_HEIGHT;
    reg [7:0] fault_now;
    wire stopping=error||fault_now!=0;
    // Asynchronously reset state already disables READY. Do not distribute
    // the board startup reset through the FIFO's data/enable cone.
    assign m_ready=state==CAPTURE && !eof_seen && !error &&
        (pixel_kind&&pixel_legal?pixel_ready:1'b1);
    wire packet_take=m_valid&&m_ready;
    // Illegal words are always consumable, so their fault decision does not
    // need READY. Including READY here would feed DMA abort back through the
    // packer's output readiness and form a combinational cycle.
    wire packet_present=m_valid && state==CAPTURE && !eof_seen && !error;
    wire pixel_valid=m_valid && state==CAPTURE && !eof_seen && pixel_kind && pixel_legal && !stopping;
    wire reader_arvalid=state==READ_AR;
    // RREADY can be low for sixteen byte clocks. After failure the same
    // advertised AXI burst is consumed before ownership is abandoned.
    wire reader_rready=state==READ_R;
    wire dma_result_bad=dma_result_valid && (dma_success!==1'b1 || dma_code!==8'd0 ||
        dma_tag!==32'd1 || dma_bytes!==FRAME_BYTES);
    always @* begin
        fault_now=0;
        if(seen_online&&!init_done)fault_now=8'h01;
        else if(bridge_fault)fault_now=8'h80|bridge_code;
        else if(dma_fault)fault_now=8'h06;
        else if(!done)begin
            if(overflow)fault_now=8'h02;
            else if(source_fault)fault_now=8'h03;
            else if(packet_present && (pixel_kind?!pixel_legal:(eof_kind?!eof_legal:1'b1)))
                fault_now=eof_kind?8'h05:8'h04;
            else if(dma_result_bad)fault_now=8'h06;
            else if(state==READ_R && bridge_rvalid && (bridge_rid!==4'h6 ||
                bridge_rresp!==2'b00 || bridge_rlast!==(read_index==read_beats-1)))fault_now=8'h09;
            else if(seen_online && timer>=TIMEOUT_CYCLES-1)fault_now=8'h07;
        end
    end
    rgb888_packer packer(
        .clk(clk),.reset_n(reset_n),.flush(1'b0),.pixel_valid(pixel_valid),
        .pixel_rgb(m_data[23:0]),.pixel_last(m_data[45]),.pixel_ready(pixel_ready),
        .s_valid(stream_valid),.s_data(stream_data),.s_keep(stream_keep),
        .s_row_last(stream_last),.s_ready(stream_ready));
    video_write_dma dma(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(stopping),
        .req_valid(state==DESCRIPTOR&&!stopping),.req_ready(dma_req_ready),
        .req_base(RAW_BASE),.req_row_bytes(ROW_BYTES),.req_stride(STRIDE),
        .req_rows(FRAME_HEIGHT[15:0]),.req_tag(32'd1),
        .s_valid(stream_valid),.s_ready(stream_ready),.s_data(stream_data),
        .s_keep(stream_keep),.s_row_last(stream_last),
        .result_valid(dma_result_valid),.result_ready(1'b1),.result_success(dma_success),
        .result_code(dma_code),.result_tag(dma_tag),.written_bytes(dma_bytes),
        .busy(dma_busy),.fault(dma_fault),
        .awid(dma_awid),.awaddr(dma_awaddr),.awlen(dma_awlen),.awsize(dma_awsize),
        .awburst(dma_awburst),.awvalid(dma_awvalid),.awready(bridge_awready),
        .wdata(dma_wdata),.wstrb(dma_wstrb),.wlast(dma_wlast),.wvalid(dma_wvalid),
        .wready(bridge_wready),.bid(bridge_bid),.bresp(bridge_bresp),
        .bvalid(bridge_bvalid),.bready(dma_bready));
    axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) bridge(
        .clk(clk),.rst_n(reset_n),.init_done(init_done),
        .awid(dma_awid),.awaddr(dma_awaddr),.awlen(dma_awlen),.awsize(dma_awsize),
        .awburst(dma_awburst),.awvalid(dma_awvalid),.awready(bridge_awready),
        .wdata(dma_wdata),.wstrb(dma_wstrb),.wlast(dma_wlast),.wvalid(dma_wvalid),
        .wready(bridge_wready),.bid(bridge_bid),.bresp(bridge_bresp),
        .bvalid(bridge_bvalid),.bready(dma_bready),
        .arid(4'h6),.araddr(read_address),.arlen({3'd0,read_beats}-8'd1),
        .arsize(3'd4),.arburst(2'b01),.arvalid(reader_arvalid),.arready(bridge_arready),
        .rdata(bridge_rdata),.rid(bridge_rid),.rresp(bridge_rresp),
        .rvalid(bridge_rvalid),.rlast(bridge_rlast),.rready(reader_rready),
        .fault(bridge_fault),.fault_code(bridge_code),
        .h_awaddr(axi_awaddr),.h_awlen(axi_awlen),.h_awid(axi_awuser_id),
        .h_awvalid(axi_awvalid),.h_awready(axi_awready),
        .h_wdata(axi_wdata),.h_wstrb(axi_wstrb),.h_wready(axi_wready),
        .h_wid(axi_wusero_id),.h_wlast(axi_wusero_last),
        .h_araddr(axi_araddr),.h_arlen(axi_arlen),.h_arid(axi_aruser_id),
        .h_arvalid(axi_arvalid),.h_arready(axi_arready),.h_rdata(axi_rdata),
        .h_rid(axi_rid),.h_rlast(axi_rlast),.h_rvalid(axi_rvalid));
    assign axi_awuser_ap=0;
    assign axi_aruser_ap=0;
    assign cancel=error;
    assign frame_tag=32'd1;
    assign busy=seen_online&&!done&&!error;
    assign phase=error?8'he0:done?8'ha5:state==WAIT_INIT?8'h00:
        state==DESCRIPTOR?8'h10:state==CAPTURE?8'h30:8'h40;
    function automatic [4:0] read_length(input [31:0] left,address);
        reg [32:0] beats;
        reg [8:0] page_beats;
        begin
            beats=({1'b0,left}+33'd15)>>4;
            page_beats=(13'd4096-{1'b0,address[11:0]})>>4;
            if(beats>16)beats=16;
            if(beats>page_beats)beats=page_beats;
            read_length=beats[4:0];
        end
    endfunction
    function automatic [31:0] crc_byte(input [31:0] crc,input [7:0] value);
        reg [31:0] c;integer i;
        begin
            c=crc^{24'd0,value};
            for(i=0;i<8;i=i+1)c=(c>>1)^(c[0]?32'hedb88320:32'd0);
            crc_byte=c;
        end
    endfunction
    wire [31:0] next_crc=crc_byte(crc_state,read_hold[byte_index*8+:8]);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=WAIT_INIT;seen_online<=0;eof_seen<=0;dma_retired<=0;timer<=0;
            done<=0;error<=0;error_code<=0;arm_toggle<=0;
            captured_pixels<=0;checked_bytes<=0;source_crc<=0;ddr_crc<=0;fifo_peak<=0;
            expected_x<=0;expected_y<=0;read_address<=RAW_BASE;row_base<=RAW_BASE;
            row_remaining<=ROW_BYTES;read_row<=0;crc_state<=32'hffffffff;
            read_beats<=1;read_index<=0;byte_index<=0;byte_count<=0;read_hold<=0;
        end else begin
            if(init_done)seen_online<=1;
            if(seen_online&&!done&&!error&&timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            if(!error&&fault_now!=0)begin error<=1;done<=0;error_code<=fault_now;end
            if(dma_result_valid)dma_retired<=1;
            if(packet_take&&!stopping)begin
                if(pixel_kind)begin
                    captured_pixels<=captured_pixels+1'b1;
                    if(expected_x==FRAME_WIDTH-1)begin expected_x<=0;expected_y<=expected_y+1'b1;end
                    else expected_x<=expected_x+1'b1;
                end else if(eof_kind)begin
                    eof_seen<=1;source_crc<=m_data[31:0];fifo_peak<={20'd0,m_data[43:32]};
                end
            end
            case(state)
                WAIT_INIT:if(init_done)begin
                    if(FRAME_WIDTH<1||FRAME_WIDTH>2048||FRAME_HEIGHT<1||FRAME_HEIGHT>2048||
                        END_WIDE>64'h87500000||END_WIDE<=64'h87300000)begin
                        if(!error&&fault_now==0)begin error<=1;error_code<=8'h08;end
                        state<=FAILED;
                    end else if(stopping)state<=FAILED;
                    else state<=DESCRIPTOR;
                end
                DESCRIPTOR:if(stopping)state<=FAILED;
                    else if(dma_req_ready)begin arm_toggle<=~arm_toggle;state<=CAPTURE;end
                CAPTURE:if(stopping)state<=FAILED;
                    else if(eof_seen&&dma_retired)state<=READ_SETUP;
                READ_SETUP:if(stopping)state<=FAILED;else begin
                    read_beats<=read_length(row_remaining,read_address);read_index<=0;state<=READ_AR;
                end
                // VALID is state-only: faults cannot withdraw an exposed AR.
                READ_AR:if(bridge_arready)state<=READ_R;
                READ_R:if(bridge_rvalid)begin
                    if(stopping)begin
                        if(read_index==read_beats-1)state<=FAILED;
                        else read_index<=read_index+1'b1;
                    end else begin
                        read_hold<=bridge_rdata;byte_index<=0;
                        byte_count<=row_remaining>=16?5'd16:row_remaining[4:0];state<=READ_BYTE;
                    end
                end
                READ_BYTE:if(stopping)begin
                    if(read_index==read_beats-1)state<=FAILED;
                    else begin read_index<=read_index+1'b1;state<=READ_R;end
                end else begin
                    crc_state<=next_crc;checked_bytes<=checked_bytes+1'b1;
                    if(byte_index==byte_count-1)begin
                        row_remaining<=row_remaining-byte_count;read_address<=read_address+16;
                        if(read_index==read_beats-1)begin
                            if(row_remaining<=16)begin
                                if(read_row==FRAME_HEIGHT-1)begin ddr_crc<=~next_crc;state<=FINISH;end
                                else begin
                                    read_row<=read_row+1'b1;row_base<=row_base+STRIDE;
                                    read_address<=row_base+STRIDE;row_remaining<=ROW_BYTES;state<=READ_SETUP;
                                end
                            end else state<=READ_SETUP;
                        end else begin read_index<=read_index+1'b1;state<=READ_R;end
                    end else byte_index<=byte_index+1'b1;
                end
                FINISH:if(!stopping&&!done)begin
                    if(checked_bytes!==FRAME_BYTES||ddr_crc!==source_crc)begin
                        error<=1;error_code<=8'h0b;state<=FAILED;
                    end else done<=1;
                end
                FAILED:done<=0;
                default:begin
                    if(!error&&fault_now==0)begin error<=1;error_code<=8'h0a;end
                    done<=0;state<=FAILED;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
