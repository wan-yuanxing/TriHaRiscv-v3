`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"
// Diagnostic one-shot ownership: three writes -> checked raw/preview -> input
// checksum -> display. Capture completion is historical, not SoC visibility.
module video_three_engine #(
    parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600,
    parameter integer WINDOW_Y=150,TIMEOUT_CYCLES=625000000,
    parameter integer PAD_TOP=40,PAD_BOTTOM=40
)(
    input wire clk,reset_n,init_done,pixel_clk,pixel_reset_n,
    input wire [10:0] pixel_x,pixel_y,input wire pixel_hs,pixel_vs,pixel_de,frame_start,
    output wire [23:0] out_rgb,output wire out_hs,out_vs,out_de,
    input wire m_valid,input wire [47:0] m_data,output wire m_ready,
    output wire arm_toggle,cancel,input wire source_fault,overflow,
    output wire busy,done,output reg error,output reg [7:0] error_code,
    output wire [7:0] phase,
    output wire [31:0] captured_pixels,preview_pixels,source_crc,preview_crc,fifo_peak,
    output reg [31:0] ddr_crc,preview_ddr_crc,
    output wire [31:0] frame_id,commits,completed_scans,read_lines,underflows,
    output wire [31:0] input_pixels,raw_written_bytes,preview_written_bytes,input_written_bytes,
    output wire [31:0] preprocess_version,capture_frame_id,raw_base,preview_base,input_base,
    output reg [31:0] input_ddr_crc,input_checked_bytes,
    output reg capture_complete,output wire port_drained,
    output wire [27:0] axi_awaddr,axi_araddr,
    output wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_arvalid,
    output wire [3:0] axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen,
    input wire axi_awready,axi_arready,
    output wire [255:0] axi_wdata,output wire [31:0] axi_wstrb,
    input wire axi_wready,input wire [3:0] axi_wusero_id,input wire axi_wusero_last,
    input wire [255:0] axi_rdata,input wire [3:0] axi_rid,input wire axi_rlast,axi_rvalid
);
    localparam [3:0] CAPTURE_REQUEST=0,CAPTURE_WAIT=1,CAPTURE_DRAIN=2,RAW_REQUEST=3,RAW_WAIT=4,
        PREVIEW_REQUEST=5,PREVIEW_WAIT=6,INPUT_REQUEST=7,INPUT_WAIT=8,SUBMIT=9,DISPLAY=10,FAILED=11;
    localparam [1:0] CHECKED_OWNER=0,INPUT_OWNER=1,DISPLAY_OWNER=2;
    localparam [31:0] RAW_ROW=FRAME_WIDTH*3,PREVIEW_ROW=(FRAME_WIDTH/2)*3,INPUT_ROW=FRAME_WIDTH*2/5;
    localparam [31:0] RAW_STRIDE=(RAW_ROW+15)&32'hfffffff0;
    localparam [31:0] PREVIEW_STRIDE=(PREVIEW_ROW+15)&32'hfffffff0;
    localparam [31:0] INPUT_STRIDE=(INPUT_ROW+15)&32'hfffffff0;
    localparam [15:0] RAW_ROWS=FRAME_HEIGHT,PREVIEW_ROWS=FRAME_HEIGHT/2;
    localparam [15:0] INPUT_ROWS=3*(FRAME_HEIGHT*2/5+PAD_TOP+PAD_BOTTOM);
    localparam [31:0] RAW_BYTES=FRAME_WIDTH*FRAME_HEIGHT*3,PREVIEW_BYTES=(FRAME_WIDTH/2)*(FRAME_HEIGHT/2)*3;
    localparam [31:0] INPUT_BYTES=(FRAME_WIDTH*2/5)*(FRAME_HEIGHT*2/5+PAD_TOP+PAD_BOTTOM)*3;
    localparam integer TW=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    reg [3:0] state;
    reg [1:0] read_owner;
    reg seen_online,accepted_seen;
    reg [TW-1:0] timer;
    wire capture_ready,capture_busy,capture_error,capture_cancel,accepted_valid,completion_valid,completion_success;
    wire [7:0] capture_code,completion_code;
    wire [1:0] capture_slot;
    wire [3:0] awid,bid;wire [31:0] awaddr;wire [7:0] awlen;
    wire [2:0] awsize;wire [1:0] awburst,bresp;
    wire awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    wire [127:0] wdata;wire [15:0] wstrb;
    wire bridge_fault;wire [7:0] bridge_code;
    reg [7:0] fault_now;
    wire capture_result_good=completion_success===1'b1&&completion_code===8'd0&&accepted_seen&&
        capture_frame_id===32'd1&&capture_slot===2'd0&&preprocess_version===32'd1&&
        raw_base===`VIDEO_FRAME_SLOT_A&&preview_base===(`VIDEO_FRAME_SLOT_A+`VIDEO_FRAME_PREVIEW_OFFSET)&&
        input_base===`VIDEO_INPUT_SLOT_A&&raw_written_bytes===RAW_BYTES&&preview_written_bytes===PREVIEW_BYTES&&input_written_bytes===INPUT_BYTES;
    video_three_branch_capture #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
        .PAD_TOP(PAD_TOP),.PAD_BOTTOM(PAD_BOTTOM),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) capture(
        .clk(clk),.reset_n(reset_n),.init_done(init_done),.abort(error),
        .req_valid(state==CAPTURE_REQUEST&&!error&&fault_now==0),.req_ready(capture_ready),
        .req_slot(2'd0),.req_frame_id(32'd1),.req_preprocess_version(32'd1),
        .m_valid(m_valid),.m_data(m_data),.m_ready(m_ready),.source_fault(source_fault),.overflow(overflow),
        .arm_toggle(arm_toggle),.cancel(capture_cancel),.busy(capture_busy),.port_drained(port_drained),
        .accepted_valid(accepted_valid),.accepted_ready(1'b1),
        .completion_valid(completion_valid),.completion_ready(1'b1),
        .completion_success(completion_success),.completion_code(completion_code),.error(capture_error),.error_code(capture_code),
        .frame_id(capture_frame_id),.preprocess_version(preprocess_version),.raw_base(raw_base),.preview_base(preview_base),.input_base(input_base),.slot(capture_slot),
        .captured_pixels(captured_pixels),.preview_pixels(preview_pixels),.input_pixels(input_pixels),.source_crc(source_crc),.preview_crc(preview_crc),.fifo_peak(fifo_peak),
        .raw_written_bytes(raw_written_bytes),.preview_written_bytes(preview_written_bytes),.input_written_bytes(input_written_bytes),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
    wire crc_ready,crc_valid,crc_success,crc_busy,crc_fault;
    wire [7:0] crc_code;wire [31:0] crc_tag,crc_bytes,crc_value;
    wire [3:0] crc_arid;wire [31:0] crc_araddr;wire [7:0] crc_arlen;
    wire [2:0] crc_arsize;wire [1:0] crc_arburst;
    wire crc_arvalid,crc_arready,crc_rready;
    wire preview_request=state==PREVIEW_REQUEST;
    wire [3:0] rid;wire [127:0] rdata;wire [1:0] rresp;
    wire rlast,rvalid,rready,arvalid,arready;
    wire [3:0] arid;wire [31:0] araddr;wire [7:0] arlen;
    wire [2:0] arsize;wire [1:0] arburst;
    video_frame_crc_reader #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) crc_reader(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(error),
        .req_valid((state==RAW_REQUEST||preview_request)&&!error&&fault_now==0),.req_ready(crc_ready),
        .req_base(preview_request?preview_base:raw_base),.req_row_bytes(preview_request?PREVIEW_ROW:RAW_ROW),
        .req_stride(preview_request?PREVIEW_STRIDE:RAW_STRIDE),.req_rows(preview_request?PREVIEW_ROWS:RAW_ROWS),
        .req_tag(preview_request?32'd2:32'd1),.expected_crc(preview_request?preview_crc:source_crc),
        .result_valid(crc_valid),.result_ready(state==RAW_WAIT||state==PREVIEW_WAIT),
        .result_success(crc_success),.result_code(crc_code),.result_tag(crc_tag),.checked_bytes(crc_bytes),.crc(crc_value),.busy(crc_busy),.fault(crc_fault),
        .arid(crc_arid),.araddr(crc_araddr),.arlen(crc_arlen),.arsize(crc_arsize),.arburst(crc_arburst),.arvalid(crc_arvalid),.arready(crc_arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid&&read_owner==CHECKED_OWNER),.rready(crc_rready));
    wire input_ready,input_valid,input_success,input_busy,input_fault;
    wire [7:0] input_code;wire [31:0] input_tag,input_bytes,input_crc;
    wire [3:0] input_arid;wire [31:0] input_araddr;wire [7:0] input_arlen;
    wire [2:0] input_arsize;wire [1:0] input_arburst;
    wire input_arvalid,input_arready,input_rready;
    video_frame_crc_reader #(.AXI_ID(4'd7),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.CHECK_EXPECTED_CRC(0)) input_reader(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(error),
        .req_valid(state==INPUT_REQUEST&&!error&&fault_now==0),.req_ready(input_ready),
        .req_base(input_base),.req_row_bytes(INPUT_ROW),.req_stride(INPUT_STRIDE),.req_rows(INPUT_ROWS),.req_tag(32'd3),.expected_crc(32'd0),
        .result_valid(input_valid),.result_ready(state==INPUT_WAIT),.result_success(input_success),.result_code(input_code),.result_tag(input_tag),
        .checked_bytes(input_bytes),.crc(input_crc),.busy(input_busy),.fault(input_fault),
        .arid(input_arid),.araddr(input_araddr),.arlen(input_arlen),.arsize(input_arsize),.arburst(input_arburst),.arvalid(input_arvalid),.arready(input_arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid&&read_owner==INPUT_OWNER),.rready(input_rready));
    wire display_ready,display_error;wire [7:0] display_code;
    wire display_commit_valid,display_release_valid;wire [31:0] commit_frame_id,release_frame_id;
    wire [1:0] commit_slot,release_slot;
    wire [3:0] display_arid;wire [31:0] display_araddr;wire [7:0] display_arlen;
    wire [2:0] display_arsize;wire [1:0] display_arburst;
    wire display_arvalid,display_arready,display_rready;
    preview_display #(.PREVIEW_WIDTH(FRAME_WIDTH/2),.PREVIEW_HEIGHT(FRAME_HEIGHT/2),.WINDOW_Y(WINDOW_Y),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) display(
        .core_clk(clk),.core_reset_n(reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .ddr_ready(init_done&&!error),.record_valid(state==SUBMIT&&!error&&fault_now==0),.record_ready(display_ready),
        .record_base(preview_base),.record_stride(PREVIEW_STRIDE),.record_frame_id(capture_frame_id),.record_slot(capture_slot),
        .commit_valid(display_commit_valid),.commit_ready(1'b1),.commit_frame_id(commit_frame_id),.commit_slot(commit_slot),
        .release_valid(display_release_valid),.release_ready(1'b1),.release_frame_id(release_frame_id),.release_slot(release_slot),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_de(pixel_de),.pixel_hs(pixel_hs),.pixel_vs(pixel_vs),.pixel_frame_start(frame_start),
        .out_rgb(out_rgb),.out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),
        .error(display_error),.error_code(display_code),.commits(commits),.completed_scans(completed_scans),.read_lines(read_lines),.underflows(underflows),.frame_id(frame_id),
        .m_axi_arid(display_arid),.m_axi_araddr(display_araddr),.m_axi_arlen(display_arlen),.m_axi_arsize(display_arsize),.m_axi_arburst(display_arburst),
        .m_axi_arvalid(display_arvalid),.m_axi_arready(display_arready),.m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid&&read_owner==DISPLAY_OWNER),.m_axi_rready(display_rready));
    // Ownership only advances after the preceding held result is consumed.
    // Faults never change this mux or withdraw an advertised VALID.
    assign arid=read_owner==DISPLAY_OWNER?display_arid:read_owner==INPUT_OWNER?input_arid:crc_arid;
    assign araddr=read_owner==DISPLAY_OWNER?display_araddr:read_owner==INPUT_OWNER?input_araddr:crc_araddr;
    assign arlen=read_owner==DISPLAY_OWNER?display_arlen:read_owner==INPUT_OWNER?input_arlen:crc_arlen;
    assign arsize=read_owner==DISPLAY_OWNER?display_arsize:read_owner==INPUT_OWNER?input_arsize:crc_arsize;
    assign arburst=read_owner==DISPLAY_OWNER?display_arburst:read_owner==INPUT_OWNER?input_arburst:crc_arburst;
    assign arvalid=read_owner==DISPLAY_OWNER?display_arvalid:read_owner==INPUT_OWNER?input_arvalid:crc_arvalid;
    assign rready=read_owner==DISPLAY_OWNER?display_rready:read_owner==INPUT_OWNER?input_rready:crc_rready;
    assign crc_arready=arready&&read_owner==CHECKED_OWNER;
    assign input_arready=arready&&read_owner==INPUT_OWNER;
    assign display_arready=arready&&read_owner==DISPLAY_OWNER;
    axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) bridge(
        .clk(clk),.rst_n(reset_n),.init_done(init_done),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),.fault(bridge_fault),.fault_code(bridge_code),
        .h_awaddr(axi_awaddr),.h_awlen(axi_awlen),.h_awid(axi_awuser_id),.h_awvalid(axi_awvalid),.h_awready(axi_awready),
        .h_wdata(axi_wdata),.h_wstrb(axi_wstrb),.h_wready(axi_wready),.h_wid(axi_wusero_id),.h_wlast(axi_wusero_last),
        .h_araddr(axi_araddr),.h_arlen(axi_arlen),.h_arid(axi_aruser_id),.h_arvalid(axi_arvalid),.h_arready(axi_arready),
        .h_rdata(axi_rdata),.h_rid(axi_rid),.h_rlast(axi_rlast),.h_rvalid(axi_rvalid));
    assign axi_awuser_ap=0;assign axi_aruser_ap=0;
    assign cancel=capture_cancel||error;
    assign done=state==DISPLAY&&commits==1&&completed_scans>=2&&!error;
    assign busy=seen_online&&!done&&!error;
    assign phase=error?8'he0:done?8'ha5:state<=CAPTURE_DRAIN?8'h30:
        read_owner==DISPLAY_OWNER?8'h60:read_owner==INPUT_OWNER?8'h50:8'h40;
    always @* begin
        fault_now=0;
        if(seen_online&&!init_done)fault_now=8'h01;
        else if(bridge_fault)fault_now=8'h80|bridge_code;
        else if(overflow)fault_now=8'h02;
        else if(source_fault)fault_now=8'h03;
        else if(capture_error)fault_now=capture_code;
        else if(crc_fault)fault_now=8'h40|crc_code;
        else if(input_fault)fault_now=8'h50|input_code;
        else if(display_error)fault_now=8'h60|display_code;
        else if(!done&&seen_online&&timer>=TIMEOUT_CYCLES-1)fault_now=8'h07;
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=CAPTURE_REQUEST;read_owner<=CHECKED_OWNER;seen_online<=0;accepted_seen<=0;timer<=0;
            error<=0;error_code<=0;capture_complete<=0;ddr_crc<=0;preview_ddr_crc<=0;input_ddr_crc<=0;input_checked_bytes<=0;
        end else begin
            if(init_done)seen_online<=1;
            if(accepted_valid)accepted_seen<=1;
            if(state==CAPTURE_WAIT&&completion_valid&&capture_result_good)capture_complete<=1;
            if(seen_online&&!done&&timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            if(fault_now!=0&&!error)begin error<=1;error_code<=fault_now;state<=FAILED;end
            else if(!error)case(state)
                CAPTURE_REQUEST:if(capture_ready)state<=CAPTURE_WAIT;
                CAPTURE_WAIT:if(completion_valid)begin
                    if(!capture_result_good)begin error<=1;error_code<=completion_code!=0?completion_code:8'h06;state<=FAILED;end
                    else state<=CAPTURE_DRAIN;
                end
                CAPTURE_DRAIN:if(port_drained)state<=RAW_REQUEST;
                RAW_REQUEST:if(crc_ready)state<=RAW_WAIT;
                RAW_WAIT:if(crc_valid)begin
                    if(crc_success!==1'b1||crc_tag!==32'd1||crc_bytes!==RAW_BYTES)begin error<=1;error_code<=8'h4b;state<=FAILED;end
                    else begin ddr_crc<=crc_value;state<=PREVIEW_REQUEST;end
                end
                PREVIEW_REQUEST:if(crc_ready)state<=PREVIEW_WAIT;
                PREVIEW_WAIT:if(crc_valid)begin
                    if(crc_success!==1'b1||crc_tag!==32'd2||crc_bytes!==PREVIEW_BYTES)begin error<=1;error_code<=8'h4b;state<=FAILED;end
                    else begin preview_ddr_crc<=crc_value;read_owner<=INPUT_OWNER;state<=INPUT_REQUEST;end
                end
                INPUT_REQUEST:if(input_ready)state<=INPUT_WAIT;
                INPUT_WAIT:if(input_valid)begin
                    if(input_success!==1'b1||input_tag!==32'd3||input_bytes!==INPUT_BYTES)begin error<=1;error_code<=8'h5b;state<=FAILED;end
                    else begin input_ddr_crc<=input_crc;input_checked_bytes<=input_bytes;read_owner<=DISPLAY_OWNER;state<=SUBMIT;end
                end
                SUBMIT:if(display_ready)state<=DISPLAY;
                default:begin end
            endcase
        end
    end
endmodule
`default_nettype wire
