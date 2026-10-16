`timescale 1ns/1ps
`default_nettype none
// RAW_DMA_SELFTEST: synthetic backpressurable pixels through the production
// packer, DMA and AXI/native bridge, followed by an independent byte checker.
// This owns native exclusively. Recovery resets all three blocks and HMIC.
module video_axi_capture_bist #(
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600,
    parameter integer TIMEOUT_CYCLES=125000000
)(
    input wire clk,reset_n,init_done,
    output wire busy,output reg done,error,
    output wire [7:0] phase,output reg [7:0] error_code,
    output reg [31:0] compared_beats,
    output reg [27:0] first_error_addr,
    output reg [255:0] first_error_xor,
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
    localparam [31:0] RAW_BASE=32'h87300000,PROBE_BASE=32'h874fff00;
    localparam [63:0] ROW_BYTES_WIDE=64'd3*FRAME_WIDTH;
    localparam [63:0] STRIDE_WIDE=(ROW_BYTES_WIDE+15)&64'hfffffffffffffff0;
    localparam [63:0] END_WIDE=64'h87300000+(FRAME_HEIGHT-1)*STRIDE_WIDE+ROW_BYTES_WIDE;
    localparam [63:0] GUARD_WIDE=(END_WIDE+15)&64'hfffffffffffffff0;
    localparam [31:0] ROW_BYTES=ROW_BYTES_WIDE[31:0],STRIDE=STRIDE_WIDE[31:0];
    localparam [31:0] GUARD_BASE=GUARD_WIDE[31:0];
    localparam integer TIMER_WIDTH=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    localparam [4:0] INIT=0,PROBE=1,CONTROL_AW=2,CONTROL_W=3,CONTROL_B=4,
        CONTROL_AR=5,CONTROL_R=6,PROBE_NEXT=7,GUARD_WRITE=8,GUARD_NEXT=9,
        DMA_REQUEST=10,DMA_RUN=11,FRAME_SETUP=12,FRAME_AR=13,FRAME_R=14,
        FRAME_CHECK=15,GUARD_READ=16,GUARD_READ_NEXT=17,FINISHED=18,FAILED=19;
    reg [4:0] state,return_state;
    reg [7:0] phase_q;
    reg owner_dma,seen_online;
    reg [TIMER_WIDTH-1:0] timer;
    reg [4:0] previous_state;
    reg [3:0] probe_step;
    reg guard_index;
    reg [31:0] control_address;
    reg [127:0] control_data,control_expected;
    reg [15:0] control_mask;
    reg [31:0] source_x,source_y;
    reg [31:0] read_address,row_base,row_remaining,read_row;
    reg [4:0] read_burst_beats,read_burst_index,check_index,check_bytes;
    reg [127:0] read_hold;
    // These counters belong only to the reader; they never follow the writer
    // coordinates, its packed stream, its buffers, or its WDATA.
    reg [31:0] expected_x,expected_y;
    reg [1:0] expected_channel;
    reg [7:0] expected_byte;
    wire [7:0] actual_byte=read_hold[check_index*8+:8];
    always @* begin
        case(expected_channel)
            0:expected_byte=expected_x[7:0]^8'h93;
            1:expected_byte=expected_y[7:0]^8'h65;
            default:expected_byte=expected_x[7:0]+expected_y[7:0]+8'hb7;
        endcase
    end
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
    function automatic [127:0] probe_reference(input upper,updated);
        integer j;
        reg [7:0] b;
        begin
            probe_reference=0;
            for(j=0;j<16;j=j+1)begin
                b=(j+(upper?16:0))^8'h5a;
                if(updated && upper && j%2==0)b=8'hc0+j;
                if(updated && !upper && (j==0 || j==15))b=8'h40+j;
                probe_reference[j*8+:8]=b;
            end
        end
    endfunction
    function automatic [127:0] guard_reference(input upper);
        integer j;
        begin
            for(j=0;j<16;j=j+1)
                guard_reference[j*8+:8]=8'he7^(j+(upper?16:0));
        end
    endfunction
    wire pixel_ready,stream_valid,stream_ready,stream_last;
    wire [127:0] stream_data;
    wire [15:0] stream_keep;
    wire pixel_valid=state==DMA_RUN && !error && source_y<FRAME_HEIGHT;
    wire [7:0] source_red=source_x[7:0]^8'h93;
    wire [7:0] source_green=source_y[7:0]^8'h65;
    wire [7:0] source_blue=source_x[7:0]+source_y[7:0]+8'hb7;
    rgb888_packer packer(
        .clk(clk),.reset_n(reset_n),.flush(1'b0),.pixel_valid(pixel_valid),
        .pixel_rgb({source_red,source_green,source_blue}),
        .pixel_last(source_x==FRAME_WIDTH-1),.pixel_ready(pixel_ready),
        .s_valid(stream_valid),.s_data(stream_data),.s_keep(stream_keep),
        .s_row_last(stream_last),.s_ready(stream_ready)
    );
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
    video_write_dma dma(
        .clk(clk),.reset_n(reset_n),.online(init_done),.abort(error),
        .req_valid(state==DMA_REQUEST && !error),.req_ready(dma_req_ready),
        .req_base(RAW_BASE),.req_row_bytes(ROW_BYTES),.req_stride(STRIDE),
        .req_rows(FRAME_HEIGHT[15:0]),.req_tag(32'h52415731),
        .s_valid(stream_valid),.s_ready(stream_ready),.s_data(stream_data),
        .s_keep(stream_keep),.s_row_last(stream_last),
        .result_valid(dma_result_valid),.result_ready(state==DMA_RUN),
        .result_success(dma_success),.result_code(dma_code),.result_tag(dma_tag),
        .written_bytes(dma_bytes),.busy(dma_busy),.fault(dma_fault),
        .awid(dma_awid),.awaddr(dma_awaddr),.awlen(dma_awlen),.awsize(dma_awsize),
        .awburst(dma_awburst),.awvalid(dma_awvalid),.awready(bridge_awready&&owner_dma),
        .wdata(dma_wdata),.wstrb(dma_wstrb),.wlast(dma_wlast),.wvalid(dma_wvalid),
        .wready(bridge_wready&&owner_dma),.bid(bridge_bid),.bresp(bridge_bresp),
        .bvalid(bridge_bvalid&&owner_dma),.bready(dma_bready)
    );
    wire control_awvalid=state==CONTROL_AW;
    wire control_wvalid=state==CONTROL_W;
    wire control_arvalid=state==CONTROL_AR || state==FRAME_AR;
    wire bridge_bready=owner_dma?dma_bready:state==CONTROL_B;
    wire bridge_rready=!owner_dma && (state==CONTROL_R || state==FRAME_R);
    wire [31:0] bridge_read_address=state==FRAME_AR?read_address:control_address;
    axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) bridge(
        .clk(clk),.rst_n(reset_n),.init_done(init_done),
        .awid(owner_dma?dma_awid:4'h6),.awaddr(owner_dma?dma_awaddr:control_address),
        .awlen(owner_dma?dma_awlen:8'd0),.awsize(owner_dma?dma_awsize:3'd4),
        .awburst(owner_dma?dma_awburst:2'b01),.awvalid(owner_dma?dma_awvalid:control_awvalid),
        .awready(bridge_awready),.wdata(owner_dma?dma_wdata:control_data),
        .wstrb(owner_dma?dma_wstrb:control_mask),.wlast(owner_dma?dma_wlast:1'b1),
        .wvalid(owner_dma?dma_wvalid:control_wvalid),.wready(bridge_wready),
        .bid(bridge_bid),.bresp(bridge_bresp),.bvalid(bridge_bvalid),.bready(bridge_bready),
        .arid(4'h6),.araddr(bridge_read_address),
        .arlen(state==FRAME_AR?({3'd0,read_burst_beats}-8'd1):8'd0),
        .arsize(3'd4),.arburst(2'b01),.arvalid(!owner_dma&&control_arvalid),
        .arready(bridge_arready),.rdata(bridge_rdata),.rid(bridge_rid),
        .rresp(bridge_rresp),.rvalid(bridge_rvalid),.rlast(bridge_rlast),.rready(bridge_rready),
        .fault(bridge_fault),.fault_code(bridge_code),
        .h_awaddr(axi_awaddr),.h_awlen(axi_awlen),.h_awid(axi_awuser_id),
        .h_awvalid(axi_awvalid),.h_awready(axi_awready),
        .h_wdata(axi_wdata),.h_wstrb(axi_wstrb),.h_wready(axi_wready),
        .h_wid(axi_wusero_id),.h_wlast(axi_wusero_last),
        .h_araddr(axi_araddr),.h_arlen(axi_arlen),.h_arid(axi_aruser_id),
        .h_arvalid(axi_arvalid),.h_arready(axi_arready),
        .h_rdata(axi_rdata),.h_rid(axi_rid),.h_rlast(axi_rlast),.h_rvalid(axi_rvalid)
    );
    assign axi_awuser_ap=1'b0;
    assign axi_aruser_ap=1'b0;
    assign phase=error?8'he0:phase_q;
    assign busy=seen_online&&!done&&!error;
    wire progress=state!=previous_state ||
        (bridge_awready&&(owner_dma?dma_awvalid:control_awvalid)) ||
        (bridge_wready&&(owner_dma?dma_wvalid:control_wvalid)) ||
        (bridge_bvalid&&bridge_bready) || (bridge_arready&&control_arvalid) ||
        (bridge_rvalid&&bridge_rready) || (pixel_valid&&pixel_ready) || state==FRAME_CHECK ||
        (axi_awvalid&&axi_awready) || axi_wready || (axi_arvalid&&axi_arready) || axi_rvalid;
    integer j;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=INIT;return_state<=FAILED;phase_q<=0;done<=0;error<=0;error_code<=0;
            compared_beats<=0;first_error_addr<=0;first_error_xor<=0;
            owner_dma<=0;seen_online<=0;timer<=0;previous_state<=INIT;
            probe_step<=0;guard_index<=0;control_address<=PROBE_BASE;
            control_data<=0;control_expected<=0;control_mask<=0;
            source_x<=0;source_y<=0;read_address<=RAW_BASE;row_base<=RAW_BASE;
            row_remaining<=ROW_BYTES;read_row<=0;read_burst_beats<=1;read_burst_index<=0;
            read_hold<=0;check_index<=0;check_bytes<=0;
            expected_x<=0;expected_y<=0;expected_channel<=0;
        end else begin
            previous_state<=state;
            if(init_done)seen_online<=1;
            if(progress || state==INIT || done || error)timer<=0;
            else if(timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            // Latch failure without withdrawing any exposed AXI request. The
            // protocol state can retire; it may require coordinated reset if
            // the native controller never accepts the outstanding command.
            if(!error)begin
                if(seen_online&&!init_done)begin error<=1;done<=0;error_code<=8'h01;end
                else if(bridge_fault)begin error<=1;done<=0;error_code<=8'h80|bridge_code;end
                else if(dma_fault)begin error<=1;done<=0;error_code<=8'h06;end
                else if(state!=INIT && !done && !progress && timer>=TIMEOUT_CYCLES-1)begin
                    error<=1;done<=0;error_code<=8'h07;
                end
            end
            if(pixel_valid&&pixel_ready)begin
                if(source_x==FRAME_WIDTH-1)begin source_x<=0;source_y<=source_y+1'b1;end
                else source_x<=source_x+1'b1;
            end
            case(state)
                INIT:if(init_done)begin
                    if(FRAME_WIDTH<=0 || FRAME_HEIGHT<=0 || FRAME_HEIGHT>65535 ||
                        ROW_BYTES_WIDE>64'hffffffff || GUARD_WIDE+32>64'h874fff00)begin
                        error<=1;error_code<=8'h08;state<=FAILED;
                    end else begin phase_q<=8'h10;state<=PROBE;end
                end
                PROBE:if(error)state<=FAILED;else begin
                    return_state<=PROBE_NEXT;control_mask<=16'hffff;
                    control_address<=PROBE_BASE;
                    case(probe_step)
                        0,1:begin
                            control_address<=PROBE_BASE+(probe_step==1?16:0);
                            for(j=0;j<16;j=j+1)control_data[j*8+:8]<=(j+(probe_step==1?16:0))^8'h5a;
                            state<=CONTROL_AW;
                        end
                        2,3:begin
                            control_address<=PROBE_BASE+(probe_step==3?16:0);
                            control_expected<=probe_reference(probe_step==3,0);state<=CONTROL_AR;
                        end
                        4:begin control_mask<=0;control_data<={16{8'hff}};state<=CONTROL_AW;end
                        5:begin
                            control_address<=PROBE_BASE+16;control_mask<=16'h5555;
                            for(j=0;j<16;j=j+1)control_data[j*8+:8]<=8'hc0+j;
                            state<=CONTROL_AW;
                        end
                        6:begin
                            control_mask<=16'h8001;
                            for(j=0;j<16;j=j+1)control_data[j*8+:8]<=8'h40+j;
                            state<=CONTROL_AW;
                        end
                        7,8:begin
                            control_address<=PROBE_BASE+(probe_step==8?16:0);
                            control_expected<=probe_reference(probe_step==8,1);state<=CONTROL_AR;
                        end
                        default:begin phase_q<=8'h20;guard_index<=0;state<=GUARD_WRITE;end
                    endcase
                end
                PROBE_NEXT:begin probe_step<=probe_step+1'b1;state<=PROBE;end
                CONTROL_AW:if(bridge_awready)state<=CONTROL_W;
                CONTROL_W:if(bridge_wready)state<=CONTROL_B;
                CONTROL_B:if(bridge_bvalid)begin
                    if(!error && (bridge_bid!==4'h6 || bridge_bresp!==0))begin
                        error<=1;error_code<=8'h03;first_error_addr<=(control_address-32'h80000000)>>2;
                    end
                    state<=return_state;
                end
                CONTROL_AR:if(bridge_arready)state<=CONTROL_R;
                CONTROL_R:if(bridge_rvalid)begin
                    if(!error)begin
                        if(bridge_rid!==4'h6 || bridge_rresp!==0 || bridge_rlast!==1'b1)begin
                            error<=1;error_code<=8'h04;first_error_addr<=(control_address-32'h80000000)>>2;
                        end else if(bridge_rdata!==control_expected)begin
                            error<=1;error_code<=8'h05;first_error_addr<=(control_address-32'h80000000)>>2;
                            first_error_xor<={128'd0,bridge_rdata^control_expected};
                        end
                    end
                    state<=return_state;
                end
                GUARD_WRITE:if(error)state<=FAILED;else begin
                    control_address<=GUARD_BASE+(guard_index?16:0);
                    control_data<=guard_reference(guard_index);control_mask<=16'hffff;
                    return_state<=GUARD_NEXT;state<=CONTROL_AW;
                end
                GUARD_NEXT:if(error)state<=FAILED;else if(!guard_index)begin
                    guard_index<=1;state<=GUARD_WRITE;
                end else begin owner_dma<=1;phase_q<=8'h30;state<=DMA_REQUEST;end
                DMA_REQUEST:if(error)state<=FAILED;else if(dma_req_ready)state<=DMA_RUN;
                DMA_RUN:if(dma_result_valid)begin
                    // The DMA has consumed the final B before publishing its
                    // result. Ownership changes only at this retirement point.
                    owner_dma<=0;
                    if(error)state<=FAILED;
                    else if(!dma_success || dma_code!=0 || dma_tag!=32'h52415731 ||
                        dma_bytes!=ROW_BYTES*FRAME_HEIGHT || bridge_bvalid || bridge_rvalid)begin
                        error<=1;error_code<=8'h06;state<=FAILED;
                    end else begin phase_q<=8'h40;state<=FRAME_SETUP;end
                end
                FRAME_SETUP:if(error)state<=FAILED;else begin
                    read_burst_beats<=read_length(row_remaining,read_address);
                    read_burst_index<=0;state<=FRAME_AR;
                end
                FRAME_AR:if(bridge_arready)state<=FRAME_R;
                FRAME_R:if(bridge_rvalid)begin
                    read_hold<=bridge_rdata;check_index<=0;
                    check_bytes<=row_remaining>=16?5'd16:row_remaining[4:0];
                    if(!error && (bridge_rid!==4'h6 || bridge_rresp!==0 ||
                        bridge_rlast!==(read_burst_index==read_burst_beats-1)))begin
                        error<=1;error_code<=8'h04;first_error_addr<=(read_address-32'h80000000)>>2;
                    end
                    state<=FRAME_CHECK;
                end
                FRAME_CHECK:begin
                    if(!error && actual_byte!==expected_byte)begin
                        error<=1;error_code<=8'h05;
                        first_error_addr<=(read_address-32'h80000000)>>2;
                        first_error_xor<={128'd0,({120'd0,actual_byte^expected_byte}<<(check_index*8))};
                    end
                    if(expected_channel==2)begin
                        expected_channel<=0;
                        if(expected_x==FRAME_WIDTH-1)begin expected_x<=0;expected_y<=expected_y+1'b1;end
                        else expected_x<=expected_x+1'b1;
                    end else expected_channel<=expected_channel+1'b1;
                    if(check_index==check_bytes-1)begin
                        if(!error && actual_byte===expected_byte)compared_beats<=compared_beats+1'b1;
                        row_remaining<=row_remaining-check_bytes;
                        read_address<=read_address+16;
                        if(read_burst_index==read_burst_beats-1)begin
                            if(error || actual_byte!==expected_byte)state<=FAILED;
                            else if(row_remaining<=16)begin
                                if(read_row==FRAME_HEIGHT-1)begin
                                    guard_index<=0;phase_q<=8'h50;state<=GUARD_READ;
                                end else begin
                                    read_row<=read_row+1'b1;row_base<=row_base+STRIDE;
                                    read_address<=row_base+STRIDE;row_remaining<=ROW_BYTES;state<=FRAME_SETUP;
                                end
                            end else state<=FRAME_SETUP;
                        end else begin read_burst_index<=read_burst_index+1'b1;state<=FRAME_R;end
                    end else check_index<=check_index+1'b1;
                end
                GUARD_READ:if(error)state<=FAILED;else begin
                    control_address<=GUARD_BASE+(guard_index?16:0);
                    control_expected<=guard_reference(guard_index);
                    return_state<=GUARD_READ_NEXT;state<=CONTROL_AR;
                end
                GUARD_READ_NEXT:if(error)state<=FAILED;else if(!guard_index)begin
                    guard_index<=1;state<=GUARD_READ;
                end else state<=FINISHED;
                FINISHED:if(!error && !bridge_fault && !dma_fault && init_done)begin
                    phase_q<=8'ha5;done<=1;
                end
                FAILED:done<=0;
                default:begin error<=1;error_code<=8'h09;state<=FAILED;end
            endcase
        end
    end
endmodule
`default_nettype wire
