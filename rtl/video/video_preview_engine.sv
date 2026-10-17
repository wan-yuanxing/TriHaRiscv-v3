`timescale 1ns/1ps
`default_nettype none
// Diagnostic task ownership is serial: dual writes -> both CRCs -> display.
// It is separate from the future CPU fabric and three-branch CAPTURE_DONE.
module video_preview_engine #(
    parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600,
    parameter integer WINDOW_Y=150,TIMEOUT_CYCLES=625000000
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
    output wire [27:0] axi_awaddr,axi_araddr,
    output wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_arvalid,
    output wire [3:0] axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen,
    input wire axi_awready,axi_arready,
    output wire [255:0] axi_wdata,output wire [31:0] axi_wstrb,
    input wire axi_wready,input wire [3:0] axi_wusero_id,input wire axi_wusero_last,
    input wire [255:0] axi_rdata,input wire [3:0] axi_rid,input wire axi_rlast,axi_rvalid
);
    localparam [3:0] CAPTURE=0,RAW_REQUEST=1,RAW_WAIT=2,PREVIEW_REQUEST=3,
        PREVIEW_WAIT=4,SUBMIT=5,DISPLAY=6,FAILED=7;
    localparam [31:0] RAW_ROW=FRAME_WIDTH*3,PREVIEW_ROW=(FRAME_WIDTH/2)*3;
    localparam [31:0] RAW_STRIDE=(RAW_ROW+15)&32'hfffffff0;
    localparam [31:0] PREVIEW_STRIDE=(PREVIEW_ROW+15)&32'hfffffff0;
    localparam integer TW=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    reg [3:0] state;
    reg seen_online,display_owns;
    reg [TW-1:0] timer;
    wire capture_busy,capture_done,capture_error,capture_cancel;
    wire [7:0] capture_code;
    wire [3:0] awid,bid;wire [31:0] awaddr;wire [7:0] awlen;
    wire [2:0] awsize;wire [1:0] awburst,bresp;
    wire awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    wire [127:0] wdata;wire [15:0] wstrb;
    wire bridge_fault;wire [7:0] bridge_code;
    reg [7:0] fault_now;
    video_preview_capture #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)) capture(
        .clk(clk),.reset_n(reset_n),.init_done(init_done),.m_valid(m_valid),.m_data(m_data),.m_ready(m_ready),
        .source_fault(source_fault),.overflow(overflow),.arm_toggle(arm_toggle),.cancel(capture_cancel),
        .busy(capture_busy),.done(capture_done),.error(capture_error),.error_code(capture_code),
        .captured_pixels(captured_pixels),.preview_pixels(preview_pixels),.source_crc(source_crc),
        .preview_crc(preview_crc),.fifo_peak(fifo_peak),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
    wire crc_ready,crc_valid,crc_success,crc_busy,crc_fault;
    wire [7:0] crc_code;wire [31:0] crc_tag,crc_bytes,crc_value;
    wire [3:0] crc_arid;wire [31:0] crc_araddr;wire [7:0] crc_arlen;
    wire [2:0] crc_arsize;wire [1:0] crc_arburst;
    wire crc_arvalid,crc_arready,crc_rready;
    wire preview_request=state==PREVIEW_REQUEST;
    wire [31:0] request_base=preview_request?32'h87460000:32'h87300000;
    wire [31:0] request_row=preview_request?PREVIEW_ROW:RAW_ROW;
    wire [31:0] request_stride=preview_request?PREVIEW_STRIDE:RAW_STRIDE;
    localparam [15:0] RAW_ROWS=FRAME_HEIGHT,PREVIEW_ROWS=FRAME_HEIGHT/2;
    wire [15:0] request_rows=preview_request?PREVIEW_ROWS:RAW_ROWS;
    wire [31:0] request_crc=preview_request?preview_crc:source_crc;
    wire [3:0] rid;wire [127:0] rdata;wire [1:0] rresp;
    wire rlast,rvalid,rready,arvalid,arready;
    wire [3:0] arid;wire [31:0] araddr;wire [7:0] arlen;
    wire [2:0] arsize;wire [1:0] arburst;
    video_frame_crc_reader #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) crc_reader(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(error||capture_error||bridge_fault),
        .req_valid((state==RAW_REQUEST||preview_request)&&!error&&fault_now==0),.req_ready(crc_ready),
        .req_base(request_base),.req_row_bytes(request_row),.req_stride(request_stride),.req_rows(request_rows),
        .req_tag(preview_request?32'd2:32'd1),.expected_crc(request_crc),
        .result_valid(crc_valid),.result_ready(state==RAW_WAIT||state==PREVIEW_WAIT),
        .result_success(crc_success),.result_code(crc_code),.result_tag(crc_tag),
        .checked_bytes(crc_bytes),.crc(crc_value),.busy(crc_busy),.fault(crc_fault),
        .arid(crc_arid),.araddr(crc_araddr),.arlen(crc_arlen),.arsize(crc_arsize),.arburst(crc_arburst),
        .arvalid(crc_arvalid),.arready(crc_arready),.rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),
        .rvalid(rvalid&&!display_owns),.rready(crc_rready));
    wire display_ready,display_error;wire [7:0] display_code;
    wire display_commit_valid,display_release_valid;
    wire [31:0] commit_frame_id,release_frame_id;
    wire [1:0] commit_slot,release_slot;
    wire [3:0] display_arid;wire [31:0] display_araddr;wire [7:0] display_arlen;
    wire [2:0] display_arsize;wire [1:0] display_arburst;
    wire display_arvalid,display_arready,display_rready;
    preview_display #(.PREVIEW_WIDTH(FRAME_WIDTH/2),.PREVIEW_HEIGHT(FRAME_HEIGHT/2),
        .WINDOW_Y(WINDOW_Y),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) display(
        .core_clk(clk),.core_reset_n(reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .ddr_ready(init_done&&!error),.record_valid(state==SUBMIT&&!error&&fault_now==0),.record_ready(display_ready),
        .record_base(32'h87460000),.record_stride(PREVIEW_STRIDE),.record_frame_id(32'd1),.record_slot(2'd0),
        .commit_valid(display_commit_valid),.commit_ready(1'b1),.commit_frame_id(commit_frame_id),.commit_slot(commit_slot),
        .release_valid(display_release_valid),.release_ready(1'b1),.release_frame_id(release_frame_id),.release_slot(release_slot),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_de(pixel_de),.pixel_hs(pixel_hs),.pixel_vs(pixel_vs),.pixel_frame_start(frame_start),
        .out_rgb(out_rgb),.out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),
        .error(display_error),.error_code(display_code),.commits(commits),.completed_scans(completed_scans),
        .read_lines(read_lines),.underflows(underflows),.frame_id(frame_id),
        .m_axi_arid(display_arid),.m_axi_araddr(display_araddr),.m_axi_arlen(display_arlen),
        .m_axi_arsize(display_arsize),.m_axi_arburst(display_arburst),.m_axi_arvalid(display_arvalid),.m_axi_arready(display_arready),
        .m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid&&display_owns),.m_axi_rready(display_rready));
    assign arid=display_owns?display_arid:crc_arid;
    assign araddr=display_owns?display_araddr:crc_araddr;
    assign arlen=display_owns?display_arlen:crc_arlen;
    assign arsize=display_owns?display_arsize:crc_arsize;
    assign arburst=display_owns?display_arburst:crc_arburst;
    assign arvalid=display_owns?display_arvalid:crc_arvalid;
    assign rready=display_owns?display_rready:crc_rready;
    assign crc_arready=arready&&!display_owns;
    assign display_arready=arready&&display_owns;
    axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) bridge(
        .clk(clk),.rst_n(reset_n),.init_done(init_done),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
        .fault(bridge_fault),.fault_code(bridge_code),
        .h_awaddr(axi_awaddr),.h_awlen(axi_awlen),.h_awid(axi_awuser_id),.h_awvalid(axi_awvalid),.h_awready(axi_awready),
        .h_wdata(axi_wdata),.h_wstrb(axi_wstrb),.h_wready(axi_wready),.h_wid(axi_wusero_id),.h_wlast(axi_wusero_last),
        .h_araddr(axi_araddr),.h_arlen(axi_arlen),.h_arid(axi_aruser_id),.h_arvalid(axi_arvalid),.h_arready(axi_arready),
        .h_rdata(axi_rdata),.h_rid(axi_rid),.h_rlast(axi_rlast),.h_rvalid(axi_rvalid));
    assign axi_awuser_ap=0;assign axi_aruser_ap=0;
    assign cancel=capture_cancel||error;
    assign done=state==DISPLAY&&commits==1&&completed_scans>=2&&!error;
    assign busy=seen_online&&!done&&!error;
    assign phase=error?8'he0:done?8'ha5:state==CAPTURE?8'h30:display_owns?8'h60:8'h40;
    always @* begin
        fault_now=0;
        if(seen_online&&!init_done)fault_now=8'h01;
        else if(bridge_fault)fault_now=8'h80|bridge_code;
        else if(overflow)fault_now=8'h02;
        else if(source_fault)fault_now=8'h03;
        else if(capture_error)fault_now=capture_code;
        else if(crc_fault)fault_now=8'h40|crc_code;
        else if(display_error)fault_now=8'h60|display_code;
        else if(!done&&seen_online&&timer>=TIMEOUT_CYCLES-1)fault_now=8'h07;
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=CAPTURE;seen_online<=0;display_owns<=0;timer<=0;error<=0;error_code<=0;ddr_crc<=0;preview_ddr_crc<=0;
        end else begin
            if(init_done)seen_online<=1;
            if(seen_online&&!done&&timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            if(fault_now!=0&&!error)begin error<=1;error_code<=fault_now;state<=FAILED;end
            else if(!error)case(state)
                CAPTURE:if(capture_done)state<=RAW_REQUEST;
                RAW_REQUEST:if(crc_ready)state<=RAW_WAIT;
                RAW_WAIT:if(crc_valid)begin
                    if(crc_success!==1'b1||crc_tag!==32'd1||crc_bytes!==(FRAME_WIDTH*FRAME_HEIGHT*3))begin
                        error<=1;error_code<=8'h4b;state<=FAILED;
                    end else begin ddr_crc<=crc_value;state<=PREVIEW_REQUEST;end
                end
                PREVIEW_REQUEST:if(crc_ready)state<=PREVIEW_WAIT;
                PREVIEW_WAIT:if(crc_valid)begin
                    if(crc_success!==1'b1||crc_tag!==32'd2||crc_bytes!==((FRAME_WIDTH/2)*(FRAME_HEIGHT/2)*3))begin
                        error<=1;error_code<=8'h4b;state<=FAILED;
                    end else begin preview_ddr_crc<=crc_value;display_owns<=1;state<=SUBMIT;end
                end
                SUBMIT:if(display_ready)state<=DISPLAY;
                default:begin end
            endcase
        end
    end
endmodule
`default_nettype wire
