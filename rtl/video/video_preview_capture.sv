`timescale 1ns/1ps
`default_nettype none
// A single selected ingress frame owns both planes until coordinated reset.
// The two one-outstanding DMAs share AXI at burst granularity; an exposed AW
// owns the port through B, including abort, timeout and DDR online loss.
module video_preview_capture #(
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600,
    parameter integer TIMEOUT_CYCLES=625000000
)(
    input wire clk,reset_n,init_done,
    input wire m_valid,input wire [47:0] m_data,output wire m_ready,
    input wire source_fault,overflow,
    output reg arm_toggle,output wire cancel,busy,
    output reg done,error,output reg [7:0] error_code,
    output reg [31:0] captured_pixels,preview_pixels,source_crc,preview_crc,fifo_peak,
    output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
    output wire [2:0] awsize,output wire [1:0] awburst,
    output wire awvalid,input wire awready,
    output wire [127:0] wdata,output wire [15:0] wstrb,
    output wire wlast,wvalid,input wire wready,
    input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
    localparam [31:0] RAW_BASE=32'h87300000,PREVIEW_BASE=32'h87460000;
    localparam [63:0] RAW_ROW_WIDE=64'd3*FRAME_WIDTH;
    localparam [63:0] PREVIEW_ROW_WIDE=64'd3*(FRAME_WIDTH/2);
    localparam [63:0] RAW_STRIDE_WIDE=(RAW_ROW_WIDE+15)&64'hfffffffffffffff0;
    localparam [63:0] PREVIEW_STRIDE_WIDE=(PREVIEW_ROW_WIDE+15)&64'hfffffffffffffff0;
    // Include the complete final bus beat in allocation/non-overlap checks.
    localparam [63:0] RAW_END_WIDE=64'h87300000+FRAME_HEIGHT*RAW_STRIDE_WIDE;
    localparam [63:0] PREVIEW_END_WIDE=64'h87460000+(FRAME_HEIGHT/2)*PREVIEW_STRIDE_WIDE;
    localparam [31:0] RAW_ROW=RAW_ROW_WIDE[31:0],RAW_STRIDE=RAW_STRIDE_WIDE[31:0];
    localparam [31:0] PREVIEW_ROW=PREVIEW_ROW_WIDE[31:0],PREVIEW_STRIDE=PREVIEW_STRIDE_WIDE[31:0];
    localparam [31:0] RAW_PIXELS=FRAME_WIDTH*FRAME_HEIGHT,PREVIEW_PIXELS=RAW_PIXELS/4;
    localparam [31:0] RAW_BYTES=RAW_PIXELS*3,PREVIEW_BYTES=PREVIEW_PIXELS*3;
    localparam integer TIMER_WIDTH=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    // The parent reports invalid descriptors before arming. Sanitize only
    // the unused scaler instance so its own parameter diagnostic cannot
    // terminate elaboration before the parent can report error_code 08.
    localparam integer SCALER_WIDTH=(FRAME_WIDTH>=2&&FRAME_WIDTH<=2048&&FRAME_WIDTH%2==0)?FRAME_WIDTH:2;
    localparam integer SCALER_HEIGHT=(FRAME_HEIGHT>=2&&FRAME_HEIGHT<=2048&&FRAME_HEIGHT%2==0)?FRAME_HEIGHT:2;
    localparam [2:0] WAIT_INIT=0,DESCRIPTORS=1,CAPTURE=2,COMPLETE=3,FAILED=4;
    reg [2:0] state;
    reg seen_online,eof_seen,raw_requested,preview_requested,raw_retired,preview_retired;
    reg [TIMER_WIDTH-1:0] timer;
    reg [31:0] expected_x,expected_y,preview_x,preview_crc_state;
    wire raw_pixel_ready,scale_input_ready,scale_valid,scale_ready,scale_last,scale_fault;
    wire [23:0] scale_rgb;
    wire raw_stream_valid,raw_stream_ready,raw_stream_last;
    wire preview_pixel_ready,preview_stream_valid,preview_stream_ready,preview_stream_last;
    wire [127:0] raw_stream_data,preview_stream_data;
    wire [15:0] raw_stream_keep,preview_stream_keep;
    wire raw_req_ready,preview_req_ready,raw_result_valid,preview_result_valid;
    wire raw_success,preview_success,raw_fault,preview_fault;
    wire [7:0] raw_code,preview_code;
    wire [31:0] raw_tag,preview_tag,raw_bytes,preview_bytes;
    wire [3:0] raw_awid,preview_awid;
    wire [31:0] raw_awaddr,preview_awaddr;
    wire [7:0] raw_awlen,preview_awlen;
    wire [2:0] raw_awsize,preview_awsize;
    wire [1:0] raw_awburst,preview_awburst;
    wire raw_awvalid,preview_awvalid,raw_awready,preview_awready;
    wire [127:0] raw_wdata,preview_wdata;
    wire [15:0] raw_wstrb,preview_wstrb;
    wire raw_wlast,preview_wlast,raw_wvalid,preview_wvalid,raw_wready,preview_wready;
    wire raw_bready,preview_bready;
    reg owner_valid,owner_preview,next_preview;
    wire pixel_kind=m_data[47:46]===2'b00;
    wire eof_kind=m_data[47:46]===2'b01;
    wire pixel_legal=m_data[44:24]===21'd0 && (^m_data[23:0])!==1'bx &&
        captured_pixels<RAW_PIXELS && m_data[45]===(expected_x==FRAME_WIDTH-1);
    wire eof_legal=m_data[45]===1'b0 && m_data[44]===1'b1 &&
        (^m_data[43:0])!==1'bx && captured_pixels===RAW_PIXELS &&
        expected_x===32'd0 && expected_y===FRAME_HEIGHT;
    wire packet_present=m_valid&&state==CAPTURE&&!eof_seen&&!error;
    wire raw_result_bad=raw_result_valid && (raw_success!==1'b1 || raw_code!==8'd0 ||
        raw_tag!==32'd1 || raw_bytes!==RAW_BYTES);
    wire preview_result_bad=preview_result_valid && (preview_success!==1'b1 || preview_code!==8'd0 ||
        preview_tag!==32'd1 || preview_bytes!==PREVIEW_BYTES);
    wire preview_legal=preview_pixels<PREVIEW_PIXELS && (^scale_rgb)!==1'bx &&
        scale_last===(preview_x==FRAME_WIDTH/2-1);
    reg [7:0] fault_now;
    // Every branch of fault_now assigns a nonzero constant. Keep priority
    // diagnostics intact, but use their parallel truth reduction for intake.
    // Case-equality to 1 preserves procedural-if handling of X/Z predicates.
    wire intake_fault =
        ((seen_online&&!init_done)===1'b1) ||
        ((bvalid && (!owner_valid || bid!==(owner_preview?4'd2:4'd1) || bresp!==2'b00))===1'b1) ||
        ((raw_fault||preview_fault)===1'b1) ||
        ((done===1'b0) && (
            (overflow===1'b1) || (source_fault===1'b1) ||
            ((packet_present&&(pixel_kind?!pixel_legal:(eof_kind?!eof_legal:1'b1)))===1'b1) ||
            ((scale_fault || (scale_valid&&!preview_legal))===1'b1) ||
            ((raw_result_bad||preview_result_bad)===1'b1) ||
            ((seen_online&&timer>=TIMEOUT_CYCLES-1)===1'b1)));
    wire stopping=error||intake_fault;
    wire pixel_valid=packet_present&&pixel_kind&&pixel_legal&&!stopping;
    // Each branch can take a PIX only if the other branch takes that same
    // PIX. Both READYs depend on storage state, never these gated VALIDs.
    assign m_ready=state==CAPTURE&&!eof_seen&&!error&&
        (pixel_kind&&pixel_legal?(raw_pixel_ready&&scale_input_ready):1'b1);
    wire packet_take=m_valid&&m_ready;
    assign scale_ready=preview_pixel_ready&&!stopping;
    wire preview_take=scale_valid&&scale_ready;
    always @* begin
        fault_now=0;
        if(seen_online&&!init_done)fault_now=8'h01;
        else if(bvalid && (!owner_valid || bid!==(owner_preview?4'd2:4'd1) || bresp!==2'b00))
            fault_now=8'h09;
        else if(raw_fault||preview_fault)fault_now=8'h06;
        else if(!done)begin
            if(overflow)fault_now=8'h02;
            else if(source_fault)fault_now=8'h03;
            else if(packet_present&&(pixel_kind?!pixel_legal:(eof_kind?!eof_legal:1'b1)))
                fault_now=eof_kind?8'h05:8'h04;
            else if(scale_fault || (scale_valid&&!preview_legal))fault_now=8'h0a;
            else if(raw_result_bad||preview_result_bad)fault_now=8'h06;
            else if(seen_online&&timer>=TIMEOUT_CYCLES-1)fault_now=8'h07;
        end
    end
    rgb888_packer #(.ALLOW_SIMULTANEOUS_TRANSFER(0)) raw_packer(
        .clk(clk),.reset_n(reset_n),.flush(1'b0),
        .pixel_valid(pixel_valid&&scale_input_ready),.pixel_ready(raw_pixel_ready),
        .pixel_rgb(m_data[23:0]),.pixel_last(m_data[45]),
        .s_valid(raw_stream_valid),.s_ready(raw_stream_ready),.s_data(raw_stream_data),
        .s_keep(raw_stream_keep),.s_row_last(raw_stream_last));
    preview_downscale #(.FRAME_WIDTH(SCALER_WIDTH),.FRAME_HEIGHT(SCALER_HEIGHT)) scaler(
        .clk(clk),.reset_n(reset_n),.clear(1'b0),
        .s_valid(pixel_valid&&raw_pixel_ready),.s_ready(scale_input_ready),
        .s_rgb(m_data[23:0]),.s_row_last(m_data[45]),
        .m_valid(scale_valid),.m_ready(scale_ready),.m_rgb(scale_rgb),.m_row_last(scale_last),.fault(scale_fault));
    rgb888_packer #(.ALLOW_SIMULTANEOUS_TRANSFER(0)) preview_packer(
        .clk(clk),.reset_n(reset_n),.flush(1'b0),
        .pixel_valid(scale_valid&&!stopping),.pixel_ready(preview_pixel_ready),
        .pixel_rgb(scale_rgb),.pixel_last(scale_last),
        .s_valid(preview_stream_valid),.s_ready(preview_stream_ready),.s_data(preview_stream_data),
        .s_keep(preview_stream_keep),.s_row_last(preview_stream_last));
    video_write_dma #(.AXI_ID(4'd1)) raw_dma(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(stopping),
        .req_valid(state==DESCRIPTORS&&!raw_requested&&!stopping),.req_ready(raw_req_ready),
        .req_base(RAW_BASE),.req_row_bytes(RAW_ROW),.req_stride(RAW_STRIDE),
        .req_rows(FRAME_HEIGHT[15:0]),.req_tag(32'd1),
        .s_valid(raw_stream_valid),.s_ready(raw_stream_ready),.s_data(raw_stream_data),
        .s_keep(raw_stream_keep),.s_row_last(raw_stream_last),
        .result_valid(raw_result_valid),.result_ready(1'b1),.result_success(raw_success),
        .result_code(raw_code),.result_tag(raw_tag),.written_bytes(raw_bytes),.busy(),.fault(raw_fault),
        .awid(raw_awid),.awaddr(raw_awaddr),.awlen(raw_awlen),.awsize(raw_awsize),.awburst(raw_awburst),
        .awvalid(raw_awvalid),.awready(raw_awready),.wdata(raw_wdata),.wstrb(raw_wstrb),
        .wlast(raw_wlast),.wvalid(raw_wvalid),.wready(raw_wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid&&owner_valid&&!owner_preview),.bready(raw_bready));
    localparam [15:0] PREVIEW_ROWS=FRAME_HEIGHT/2;
    video_write_dma #(.AXI_ID(4'd2)) preview_dma(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(stopping),
        .req_valid(state==DESCRIPTORS&&!preview_requested&&!stopping),.req_ready(preview_req_ready),
        .req_base(PREVIEW_BASE),.req_row_bytes(PREVIEW_ROW),.req_stride(PREVIEW_STRIDE),
        .req_rows(PREVIEW_ROWS),.req_tag(32'd1),
        .s_valid(preview_stream_valid),.s_ready(preview_stream_ready),.s_data(preview_stream_data),
        .s_keep(preview_stream_keep),.s_row_last(preview_stream_last),
        .result_valid(preview_result_valid),.result_ready(1'b1),.result_success(preview_success),
        .result_code(preview_code),.result_tag(preview_tag),.written_bytes(preview_bytes),.busy(),.fault(preview_fault),
        .awid(preview_awid),.awaddr(preview_awaddr),.awlen(preview_awlen),.awsize(preview_awsize),.awburst(preview_awburst),
        .awvalid(preview_awvalid),.awready(preview_awready),.wdata(preview_wdata),.wstrb(preview_wstrb),
        .wlast(preview_wlast),.wvalid(preview_wvalid),.wready(preview_wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid&&owner_valid&&owner_preview),.bready(preview_bready));
    // Select before exposing VALID. Selection is state-only once exposed;
    // neither errors nor online loss can withdraw or redirect a transaction.
    assign awid=owner_preview?preview_awid:raw_awid;
    assign awaddr=owner_preview?preview_awaddr:raw_awaddr;
    assign awlen=owner_preview?preview_awlen:raw_awlen;
    assign awsize=owner_preview?preview_awsize:raw_awsize;
    assign awburst=owner_preview?preview_awburst:raw_awburst;
    assign awvalid=owner_valid&&(owner_preview?preview_awvalid:raw_awvalid);
    assign raw_awready=owner_valid&&!owner_preview&&awready;
    assign preview_awready=owner_valid&&owner_preview&&awready;
    assign wdata=owner_preview?preview_wdata:raw_wdata;
    assign wstrb=owner_preview?preview_wstrb:raw_wstrb;
    assign wlast=owner_preview?preview_wlast:raw_wlast;
    assign wvalid=owner_valid&&(owner_preview?preview_wvalid:raw_wvalid);
    assign raw_wready=owner_valid&&!owner_preview&&wready;
    assign preview_wready=owner_valid&&owner_preview&&wready;
    assign bready=reset_n&&(owner_valid?(owner_preview?preview_bready:raw_bready):1'b1);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin owner_valid<=0;owner_preview<=0;next_preview<=0;end
        else if(owner_valid)begin
            if(bvalid&&bready)begin owner_valid<=0;next_preview<=!owner_preview;end
        end else if(raw_awvalid||preview_awvalid)begin
            owner_valid<=1;
            owner_preview<=preview_awvalid&&(!raw_awvalid||next_preview);
        end
    end
    function automatic [31:0] crc_byte(input [31:0] crc,input [7:0] value);
        reg [31:0] c;integer k;
        begin
            c=crc^{24'd0,value};
            for(k=0;k<8;k=k+1)c=(c>>1)^(c[0]?32'hedb88320:32'd0);
            crc_byte=c;
        end
    endfunction
    wire [31:0] preview_crc_next=crc_byte(crc_byte(crc_byte(preview_crc_state,
        scale_rgb[23:16]),scale_rgb[15:8]),scale_rgb[7:0]);
    assign cancel=error;
    assign busy=seen_online&&!done&&!error;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=WAIT_INIT;seen_online<=0;timer<=0;arm_toggle<=0;done<=0;error<=0;error_code<=0;
            raw_requested<=0;preview_requested<=0;raw_retired<=0;preview_retired<=0;eof_seen<=0;
            captured_pixels<=0;preview_pixels<=0;source_crc<=0;preview_crc<=0;fifo_peak<=0;
            expected_x<=0;expected_y<=0;preview_x<=0;preview_crc_state<=32'hffffffff;
        end else begin
            if(init_done)seen_online<=1;
            if(seen_online&&!done&&!error&&timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            if(!error&&fault_now!=0)begin error<=1;done<=0;error_code<=fault_now;end
            if(raw_result_valid&&!raw_result_bad)raw_retired<=1;
            if(preview_result_valid&&!preview_result_bad)preview_retired<=1;
            if(packet_take&&!stopping)begin
                if(pixel_kind)begin
                    captured_pixels<=captured_pixels+1'b1;
                    if(expected_x==FRAME_WIDTH-1)begin expected_x<=0;expected_y<=expected_y+1'b1;end
                    else expected_x<=expected_x+1'b1;
                end else if(eof_kind)begin
                    eof_seen<=1;source_crc<=m_data[31:0];fifo_peak<={20'd0,m_data[43:32]};
                end
            end
            if(preview_take)begin
                preview_pixels<=preview_pixels+1'b1;preview_crc_state<=preview_crc_next;
                preview_crc<=~preview_crc_next;
                if(preview_x==FRAME_WIDTH/2-1)preview_x<=0;else preview_x<=preview_x+1'b1;
            end
            case(state)
                WAIT_INIT:if(init_done)begin
                    if(FRAME_WIDTH<2||FRAME_WIDTH>2048||FRAME_HEIGHT<2||FRAME_HEIGHT>2048||
                        FRAME_WIDTH%2!=0||FRAME_HEIGHT%2!=0||TIMEOUT_CYCLES<1||
                        RAW_END_WIDE>64'h87460000||RAW_END_WIDE<=64'h87300000||
                        PREVIEW_END_WIDE>64'h87500000||PREVIEW_END_WIDE<=64'h87460000)begin
                        if(!error&&fault_now==0)begin error<=1;error_code<=8'h08;end
                        state<=FAILED;
                    end else if(stopping)state<=FAILED;else state<=DESCRIPTORS;
                end
                DESCRIPTORS:if(stopping)state<=FAILED;
                    else begin
                        if(raw_req_ready)raw_requested<=1;
                        if(preview_req_ready)preview_requested<=1;
                        if((raw_requested||raw_req_ready)&&(preview_requested||preview_req_ready))begin
                            arm_toggle<=~arm_toggle;state<=CAPTURE;
                        end
                    end
                CAPTURE:if(stopping)state<=FAILED;
                    else if(eof_seen&&raw_retired&&preview_retired)begin
                        if(captured_pixels!==RAW_PIXELS||preview_pixels!==PREVIEW_PIXELS||preview_x!==0)begin
                            error<=1;error_code<=8'h0a;state<=FAILED;
                        end else begin done<=1;state<=COMPLETE;end
                    end
                COMPLETE:if(stopping)begin done<=0;state<=FAILED;end
                FAILED:done<=0;
                default:begin error<=1;done<=0;error_code<=8'h0b;state<=FAILED;end
            endcase
        end
    end
endmodule
`default_nettype wire
