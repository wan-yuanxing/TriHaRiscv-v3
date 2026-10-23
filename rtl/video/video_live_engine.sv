`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"
// Autonomous Video-only double buffering. Release, never commit alone, frees a slot.
module video_live_engine #(
    parameter integer FRAME_WIDTH=800,FRAME_HEIGHT=600,
    parameter integer TIMEOUT_CYCLES=625000000,
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
    output wire [31:0] ddr_crc,preview_ddr_crc,
    output wire [31:0] frame_id,commits,completed_scans,read_lines,underflows,
    output wire [31:0] input_pixels,raw_written_bytes,preview_written_bytes,input_written_bytes,
    output wire [31:0] preprocess_version,capture_frame_id,raw_base,preview_base,input_base,
    output wire [31:0] input_ddr_crc,input_checked_bytes,
    output wire capture_complete,output wire port_drained,
    output reg [31:0] captures,releases,
    output wire [27:0] axi_awaddr,axi_araddr,
    output wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_arvalid,
    output wire [3:0] axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen,
    input wire axi_awready,axi_arready,
    output wire [255:0] axi_wdata,output wire [31:0] axi_wstrb,
    input wire axi_wready,input wire [3:0] axi_wusero_id,input wire axi_wusero_last,
    input wire [255:0] axi_rdata,input wire [3:0] axi_rid,input wire axi_rlast,axi_rvalid
);
    localparam [2:0] CAPTURE_REQUEST=0,CAPTURE_WAIT=1,CAPTURE_DRAIN=2,SUBMIT=3,WAIT_COMMIT=4,FAILED=5;
    localparam [31:0] RAW_STRIDE=(FRAME_WIDTH*3+15)&32'hfffffff0;
    localparam [31:0] RAW_BYTES=FRAME_WIDTH*FRAME_HEIGHT*3;
    localparam [31:0] PREVIEW_BYTES=FRAME_WIDTH*FRAME_HEIGHT*3/4;
    localparam [31:0] INPUT_BYTES=(FRAME_WIDTH*2/5)*(FRAME_HEIGHT*2/5+PAD_TOP+PAD_BOTTOM)*3;
    localparam integer TW=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    reg [2:0] state;
    reg [1:0] next_slot,active_slot;
    reg [31:0] next_frame_id,active_frame_id;
    reg seen_online,accepted_seen,active_valid,commit_seen,release_seen;
    reg [TW-1:0] timer;
    wire capture_ready,capture_busy,capture_error,capture_cancel,accepted_valid,completion_valid,completion_success;
    wire capture_drained,memory_drained;
    wire [7:0] capture_code,completion_code;
    wire [1:0] capture_slot;
    wire [3:0] awid,bid;wire [31:0] awaddr;wire [7:0] awlen;
    wire [2:0] awsize;wire [1:0] awburst,bresp;
    wire awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    wire [127:0] wdata;wire [15:0] wstrb;
    wire bridge_fault;wire [7:0] bridge_code;
    wire [3:0] rid;wire [127:0] rdata;wire [1:0] rresp;
    wire rlast,rvalid;
    reg [7:0] fault_now;
    wire capture_result_good=completion_success&&completion_code==0&&accepted_seen&&
        capture_frame_id==next_frame_id&&capture_slot==next_slot&&preprocess_version==1&&
        raw_written_bytes==RAW_BYTES&&preview_written_bytes==PREVIEW_BYTES&&input_written_bytes==INPUT_BYTES;
    video_three_branch_capture #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
        .PAD_TOP(PAD_TOP),.PAD_BOTTOM(PAD_BOTTOM),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.ENABLE_REARM(1)) capture(
        .clk(clk),.reset_n(reset_n),.init_done(init_done),.abort(error),
        .req_valid(state==CAPTURE_REQUEST&&!error&&fault_now==0),.req_ready(capture_ready),
        .req_slot(next_slot),.req_frame_id(next_frame_id),.req_preprocess_version(32'd1),
        .m_valid(m_valid),.m_data(m_data),.m_ready(m_ready),.source_fault(source_fault),.overflow(overflow),
        .arm_toggle(arm_toggle),.cancel(capture_cancel),.busy(capture_busy),.port_drained(capture_drained),
        .accepted_valid(accepted_valid),.accepted_ready(1'b1),
        .completion_valid(completion_valid),.completion_ready(state==CAPTURE_WAIT),
        .completion_success(completion_success),.completion_code(completion_code),.error(capture_error),.error_code(capture_code),
        .frame_id(capture_frame_id),.preprocess_version(preprocess_version),.raw_base(raw_base),.preview_base(preview_base),.input_base(input_base),.slot(capture_slot),
        .captured_pixels(captured_pixels),.preview_pixels(preview_pixels),.input_pixels(input_pixels),.source_crc(source_crc),.preview_crc(preview_crc),.fifo_peak(fifo_peak),
        .raw_written_bytes(raw_written_bytes),.preview_written_bytes(preview_written_bytes),.input_written_bytes(input_written_bytes),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
    wire display_ready,display_error;wire [7:0] display_code;
    wire display_reject_valid;wire [7:0] display_reject_code;wire [31:0] display_rejected_records;
    wire display_commit_valid,display_release_valid;wire [31:0] commit_frame_id,release_frame_id;
    wire [1:0] commit_slot,release_slot;
    wire [3:0] display_arid;wire [31:0] display_araddr;wire [7:0] display_arlen;
    wire [2:0] display_arsize;wire [1:0] display_arburst;
    wire display_arvalid,display_arready,display_rready;
    raw_display #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) display(
        .core_clk(clk),.core_reset_n(reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .ddr_ready(init_done&&!error),.record_valid(state==SUBMIT&&!error&&fault_now==0),.record_ready(display_ready),
        .record_generation(32'd1),.record_base(raw_base),.record_stride(RAW_STRIDE),.record_frame_id(capture_frame_id),.record_slot(capture_slot),
        .record_reject_valid(display_reject_valid),.record_reject_ready(1'b1),
        .record_reject_code(display_reject_code),.rejected_records(display_rejected_records),
        .commit_valid(display_commit_valid),.commit_ready(1'b1),.commit_frame_id(commit_frame_id),.commit_slot(commit_slot),
        .release_valid(display_release_valid),.release_ready(1'b1),.release_frame_id(release_frame_id),.release_slot(release_slot),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_de(pixel_de),.pixel_hs(pixel_hs),.pixel_vs(pixel_vs),.pixel_frame_start(frame_start),
        .out_rgb(out_rgb),.out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),
        .error(display_error),.error_code(display_code),.commits(commits),.completed_scans(completed_scans),.read_lines(read_lines),.underflows(underflows),.frame_id(frame_id),
        .m_axi_arid(display_arid),.m_axi_araddr(display_araddr),.m_axi_arlen(display_arlen),.m_axi_arsize(display_arsize),.m_axi_arburst(display_arburst),
        .m_axi_arvalid(display_arvalid),.m_axi_arready(display_arready),.m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid),.m_axi_rready(display_rready));
    // The scheduler registers descriptors before the native bridge, preserving
    // the proven capture AW timing boundary. One exclusive Video-local port.
    wire memory_busy;wire [31:0] read_grants,write_grants;
    video_shared_ddr #(.NATIVE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) memory(
        .clk(clk),.reset_n(reset_n),.online(init_done),.display_urgent(1'b1),
        .c_awid(awid),.c_awaddr(awaddr),.c_awlen(awlen),.c_awsize(awsize),.c_awburst(awburst),
        .c_awvalid(awvalid),.c_awready(awready),.c_wdata(wdata),.c_wstrb(wstrb),.c_wlast(wlast),.c_wvalid(wvalid),.c_wready(wready),
        .c_bid(bid),.c_bresp(bresp),.c_bvalid(bvalid),.c_bready(bready),
        .d_arid(display_arid),.d_araddr(display_araddr),.d_arlen(display_arlen),.d_arsize(display_arsize),.d_arburst(display_arburst),
        .d_arvalid(display_arvalid),.d_arready(display_arready),.d_rid(rid),.d_rdata(rdata),.d_rresp(rresp),.d_rlast(rlast),.d_rvalid(rvalid),.d_rready(display_rready),
        .h_awaddr(axi_awaddr),.h_awlen(axi_awlen),.h_awid(axi_awuser_id),.h_awvalid(axi_awvalid),.h_awready(axi_awready),
        .h_wdata(axi_wdata),.h_wstrb(axi_wstrb),.h_wready(axi_wready),.h_wid(axi_wusero_id),.h_wlast(axi_wusero_last),
        .h_araddr(axi_araddr),.h_arlen(axi_arlen),.h_arid(axi_aruser_id),.h_arvalid(axi_arvalid),.h_arready(axi_arready),
        .h_rdata(axi_rdata),.h_rid(axi_rid),.h_rlast(axi_rlast),.h_rvalid(axi_rvalid),
        .fault(bridge_fault),.fault_code(bridge_code),.busy(memory_busy),.port_drained(memory_drained),
        .read_grants(read_grants),.write_grants(write_grants));
    assign axi_awuser_ap=0;assign axi_aruser_ap=0;
    assign port_drained=capture_drained&&memory_drained;
    assign capture_complete=captures!=0;
    // These compatibility pins are deliberately zero: live mode does not
    // perform full-frame DDR CRC readback. UART live type11 reports progress.
    assign ddr_crc=0;assign preview_ddr_crc=0;assign input_ddr_crc=0;assign input_checked_bytes=0;
    assign cancel=capture_cancel||error;
    assign done=commits>=2&&completed_scans>=2&&!error;
    assign busy=seen_online&&!error;
    assign phase=error?8'he0:done?8'ha5:8'h70+{5'd0,state};
    wire commit_event=display_commit_valid;
    wire release_event=display_release_valid;
    always @* begin
        fault_now=0;
        if(seen_online&&!init_done)fault_now=8'h01;
        else if(bridge_fault)fault_now=8'h80|bridge_code;
        else if(overflow)fault_now=8'h02;
        else if(source_fault)fault_now=8'h03;
        else if(capture_error)fault_now=capture_code;
        else if(display_reject_valid)fault_now=8'h69;
        else if(display_error)fault_now=8'h60|display_code;
        else if(commit_event&&(state!=WAIT_COMMIT||commit_seen||commit_frame_id!=next_frame_id||commit_slot!=next_slot))fault_now=8'h6a;
        else if(release_event&&(state!=WAIT_COMMIT||release_seen||!active_valid||release_frame_id!=active_frame_id||release_slot!=active_slot))fault_now=8'h6b;
        else if(seen_online&&timer>=TIMEOUT_CYCLES-1)fault_now=8'h07;
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=CAPTURE_REQUEST;seen_online<=0;accepted_seen<=0;timer<=0;
            next_slot<=0;next_frame_id<=1;active_valid<=0;active_slot<=0;active_frame_id<=0;
            commit_seen<=0;release_seen<=0;captures<=0;releases<=0;error<=0;error_code<=0;
        end else begin
            if(init_done)seen_online<=1;
            if(seen_online&&timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            if(accepted_valid)accepted_seen<=1;
            if(commit_event)commit_seen<=1;
            if(release_event)begin release_seen<=1;releases<=releases+1'b1;end
            if(fault_now!=0&&!error)begin error<=1;error_code<=fault_now;state<=FAILED;end
            else if(!error)case(state)
                CAPTURE_REQUEST:if(capture_ready)begin
                    accepted_seen<=0;commit_seen<=0;release_seen<=0;timer<=0;state<=CAPTURE_WAIT;
                end
                CAPTURE_WAIT:if(completion_valid)begin
                    if(!capture_result_good)begin error<=1;error_code<=completion_code!=0?completion_code:8'h06;state<=FAILED;end
                    else begin captures<=captures+1'b1;timer<=0;state<=CAPTURE_DRAIN;end
                end
                CAPTURE_DRAIN:if(capture_drained)begin timer<=0;state<=SUBMIT;end
                SUBMIT:if(display_ready)begin timer<=0;state<=WAIT_COMMIT;end
                WAIT_COMMIT:if((commit_seen||commit_event)&&(!active_valid||release_seen||release_event))begin
                    // The old display ownership, including RAM/pixel pipelines,
                    // has retired. Only now may the opposite slot be written.
                    active_valid<=1;active_slot<=next_slot;active_frame_id<=next_frame_id;
                    next_slot<=next_slot==0?2'd1:2'd0;next_frame_id<=next_frame_id+1'b1;
                    commit_seen<=0;release_seen<=0;timer<=0;state<=CAPTURE_REQUEST;
                end
                default:begin end
            endcase
        end
    end
endmodule
`default_nettype wire
