`timescale 1ns/1ps
`default_nettype none
// Active RGB row -> padded B/G/R UINT8 planes. One row RAM, one DMA owner.
// Local completion includes every B response, but is not formal INPUT_READY.
// Abort drains exposed AXI. Failures require coordinated port/source reset.
module detect_nchw_dma #(
    parameter integer WIDTH=320,ACTIVE_HEIGHT=240,PAD_TOP=40,PAD_BOTTOM=40,
    parameter integer ROW_STRIDE=((WIDTH+15)/16)*16,
    parameter integer PLANE_STRIDE=ROW_STRIDE*(PAD_TOP+ACTIVE_HEIGHT+PAD_BOTTOM),
    parameter [3:0] AXI_ID=4'h3
)(
    input wire clk,reset_n,online,abort,
    input wire req_valid,output wire req_ready,input wire [31:0] req_base,req_tag,
    input wire s_valid,output wire s_ready,input wire [23:0] s_rgb,input wire s_row_last,
    output wire result_valid,input wire result_ready,output wire result_success,
    output reg [7:0] result_code,output reg [31:0] result_tag,written_bytes,
    output wire busy,output reg fault,
    output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
    output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
    output wire [127:0] wdata,output wire [15:0] wstrb,output wire wlast,wvalid,input wire wready,
    input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
    localparam integer HEIGHT=PAD_TOP+ACTIVE_HEIGHT+PAD_BOTTOM;
    localparam integer RAM_AW=WIDTH>1?$clog2(WIDTH):1;
    localparam [31:0] WIDTH32=WIDTH,STRIDE32=ROW_STRIDE,PLANE32=PLANE_STRIDE,TWO_PLANE32=2*PLANE_STRIDE;
    localparam [12:0] WIDTH13=WIDTH;
    localparam [63:0] TENSOR_SPAN=64'd2*PLANE_STRIDE+64'd1*(HEIGHT-1)*ROW_STRIDE+WIDTH;
    localparam [3:0] IDLE=0,COLLECT=1,ISSUE=2,READ=3,TAKE=4,SEND=5,WAIT_ROW=6,DRAIN=7,RESULT=8;
    localparam [7:0] BAD_DESCRIPTOR=1,BAD_STREAM=2,ABORTED=3,OFFLINE=4,STRAY_B=7;
    reg [3:0] state;
    reg [11:0] row_index,input_x,read_x;
    reg [1:0] plane;
    reg [3:0] lane;
    reg [31:0] row_base;
    // Keep the DMA descriptor base registered.  The previous combinational
    // row_base/plane mux became a very high fanout path after flattening.
    reg [31:0] dma_base_reg;
    reg [127:0] pack_data;
    reg [15:0] pack_keep;
    reg pack_last,inflight,seen_online;
    (* syn_ramstyle="block_ram" *) reg [23:0] row_memory[0:WIDTH-1];
    reg [23:0] row_q;
    wire padding=row_index<PAD_TOP || row_index>=PAD_TOP+ACTIVE_HEIGHT;
    wire dma_req_ready,dma_s_ready,dma_result_valid,dma_result_success,dma_fault;
    wire [7:0] dma_result_code;
    wire [31:0] dma_written,dma_tag;
    wire stopping=abort || !online || fault || dma_fault;
    wire dma_req_valid=state==ISSUE && !stopping;
    wire [7:0] selected_byte=plane==0?row_q[7:0]:plane==1?row_q[15:8]:row_q[23:16];
    wire [12:0] remaining=WIDTH13-{1'b0,read_x};

    initial begin
        if(WIDTH<1||WIDTH>2048||ACTIVE_HEIGHT<1||ACTIVE_HEIGHT>2048||
           PAD_TOP<0||PAD_TOP>2048||PAD_BOTTOM<0||PAD_BOTTOM>2048||HEIGHT<1||HEIGHT>2048||
           ROW_STRIDE<WIDTH||ROW_STRIDE%16!=0||ROW_STRIDE>65536||
           PLANE_STRIDE<ROW_STRIDE*HEIGHT||PLANE_STRIDE%16!=0||PLANE_STRIDE>134217728)
            $fatal(1,"invalid NCHW geometry/stride");
    end
    function automatic descriptor_ok(input [31:0] base,tag);
        reg [63:0] last_bus;
        begin
            last_bus=({32'd0,base}+TENSOR_SPAN+64'd15)&64'hfffffffffffffff0;
            descriptor_ok=(^base!==1'bx)&&(^tag!==1'bx)&&base[3:0]==0&&base>=32'h80000000&&last_bus<=64'h88000000;
        end
    endfunction
    assign req_ready=reset_n&&state==IDLE&&online&&!abort&&!fault&&dma_req_ready;
    assign s_ready=reset_n&&state==COLLECT&&!stopping;
    assign result_valid=reset_n&&state==RESULT;
    assign result_success=result_code==0;
    assign busy=state!=IDLE&&state!=RESULT;
    // No RAM reset: every active row is fully collected before any read.
    always @(posedge clk)begin
        if(s_valid&&s_ready)row_memory[input_x[RAM_AW-1:0]]<=s_rgb;
        if(state==READ)row_q<=row_memory[read_x[RAM_AW-1:0]];
    end
    video_write_dma #(.AXI_ID(AXI_ID)) u_dma(
        .clk(clk),.reset_n(reset_n),.online(online),.abort(abort||fault),
        .req_valid(dma_req_valid),.req_ready(dma_req_ready),.req_base(dma_base_reg),
        .req_row_bytes(WIDTH32),.req_stride(STRIDE32),.req_rows(16'd1),.req_tag(result_tag),
        .s_valid(state==SEND&&!stopping),.s_ready(dma_s_ready),.s_data(pack_data),.s_keep(pack_keep),.s_row_last(pack_last),
        .result_valid(dma_result_valid),.result_ready(inflight),.result_success(dma_result_success),
        .result_code(dma_result_code),.result_tag(dma_tag),.written_bytes(dma_written),.busy(),.fault(dma_fault),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));

    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;row_index<=0;input_x<=0;read_x<=0;plane<=0;lane<=0;row_base<=0;dma_base_reg<=0;
            pack_data<=0;pack_keep<=0;pack_last<=0;inflight<=0;seen_online<=0;
            result_code<=0;result_tag<=0;written_bytes<=0;fault<=0;
        end else begin
            if(online)seen_online<=1;
            if(dma_fault||(!online&&seen_online))fault<=1;
            if(inflight&&dma_result_valid)begin
                inflight<=0;written_bytes<=written_bytes+dma_written;
                if(state==DRAIN||stopping||!dma_result_success||dma_tag!==result_tag||dma_written!=WIDTH)begin
                    fault<=1;state<=RESULT;
                    // A failed DMA result was produced on an earlier edge.
                    // A later cancel/offline must not replace its first cause.
                    if(result_code==0)result_code<=!dma_result_success?dma_result_code:
                        abort?ABORTED:!online?OFFLINE:BAD_STREAM;
                end else if(plane!=2)begin
                    plane<=plane+1'b1;
                    dma_base_reg<=row_base+(plane==0?PLANE32:TWO_PLANE32);
                    state<=ISSUE;
                end
                else if(row_index==HEIGHT-1)state<=RESULT;
                else begin
                    plane<=0;row_index<=row_index+1'b1;row_base<=row_base+STRIDE32;
                    dma_base_reg<=row_base+STRIDE32;input_x<=0;
                    state<=(row_index+1>=PAD_TOP&&row_index+1<PAD_TOP+ACTIVE_HEIGHT)?COLLECT:ISSUE;
                end
            end else if(state!=IDLE&&state!=RESULT&&state!=DRAIN&&stopping)begin
                // BID/BRESP faults retire with a DMA result above. A port fault
                // without that result while online is an unsolicited response.
                fault<=1;result_code<=dma_fault?STRAY_B:abort?ABORTED:OFFLINE;
                state<=inflight?DRAIN:RESULT;
            end else case(state)
                IDLE:if(req_valid&&req_ready)begin
                    result_tag<=req_tag;written_bytes<=0;result_code<=0;plane<=0;row_index<=0;
                    row_base<=req_base;dma_base_reg<=req_base;input_x<=0;
                    if(!descriptor_ok(req_base,req_tag))begin fault<=1;result_code<=BAD_DESCRIPTOR;state<=RESULT;end
                    else state<=PAD_TOP==0?COLLECT:ISSUE;
                end
                COLLECT:if(s_valid&&s_ready)begin
                    if((^s_rgb===1'bx)||s_row_last!==(input_x==WIDTH-1))begin
                        fault<=1;result_code<=BAD_STREAM;state<=RESULT;
                    end else if(input_x==WIDTH-1)begin input_x<=0;state<=ISSUE;end
                    else input_x<=input_x+1'b1;
                end
                ISSUE:if(dma_req_valid&&dma_req_ready)begin
                    inflight<=1;read_x<=0;lane<=0;pack_data<=0;
                    if(padding)begin pack_keep<=16'hffff>>(16-(WIDTH>=16?16:WIDTH));pack_last<=WIDTH<=16;state<=SEND;end
                    else state<=READ;
                end
                READ:state<=TAKE;
                TAKE:begin
                    pack_data[lane*8+:8]<=selected_byte;
                    if(lane==15||read_x==WIDTH-1)begin
                        pack_keep<=16'hffff>>(4'd15-lane);pack_last<=read_x==WIDTH-1;state<=SEND;
                    end else begin lane<=lane+1'b1;read_x<=read_x+1'b1;state<=READ;end
                end
                SEND:if(dma_s_ready)begin
                    if(pack_last)state<=WAIT_ROW;
                    else if(padding)begin
                        read_x<=read_x+12'd16;
                        // A non-final padding beat has remaining >=17. At
                        // >=32 the next beat is full; for17..31 its byte count
                        // is remaining[3:0]. Keep the shift count five bits to
                        // avoid a 32-bit subtract/compare chain on read_x.
                        pack_keep<=remaining>=13'd32 ? 16'hffff :
                            16'hffff>>(5'd16-{1'b0,remaining[3:0]});
                        pack_last<=remaining<=13'd32;
                    end else begin read_x<=read_x+1'b1;lane<=0;pack_data<=0;state<=READ;end
                end
                RESULT:if(result_ready)state<=IDLE;
                default:begin end
            endcase
        end
    end
endmodule
`default_nettype wire
