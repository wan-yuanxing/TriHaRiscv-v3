`timescale 1ns/1ps
`default_nettype none
// One DDR material per coordinated-reset epoch. Source DDR must remain immutable
// and visible for the whole load. This client needs arbitration before sharing
// the sole physical DDR port. It is not a global allocator or a visibility fence.
module avatar_ddr_cache #(
    parameter integer TEXELS=65536,TIMEOUT_CYCLES=125000000,COMPACT_PRESET=0,
    parameter [3:0] AXI_ID=4'h9
)(
    input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,online,
    input wire load_valid,output wire load_ready,
    input wire [31:0] load_base,load_bytes,load_asset_id,load_generation,expected_crc,
    output wire result_valid,input wire result_ready,output wire result_success,
    output reg [7:0] result_code,output reg [31:0] result_asset_id,result_generation,checked_bytes,crc,
    output reg fault,output reg [7:0] fault_code,output wire port_drained,
    output wire asset_ready,pixel_asset_ready,output wire [31:0] asset_id,asset_generation,words_written,
    input wire pixel_req_valid,input wire [17:0] pixel_req_addr,
    input wire [31:0] pixel_req_asset_id,pixel_req_generation,
    output wire sample_valid,sample_error,output wire [31:0] sample_rgba,
    output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
    output wire [2:0] arsize,output wire [1:0] arburst,
    output wire arvalid,input wire arready,input wire [3:0] rid,
    input wire [127:0] rdata,input wire [1:0] rresp,input wire rlast,rvalid,output wire rready
);
    `include "avatar_span_identity.vh"
    generate if(TEXELS<4||TEXELS>65536||TEXELS%4!=0||TIMEOUT_CYCLES<16)begin:invalid_parameters
        initial $fatal(1,"avatar_ddr_cache requires 4..65536 texels divisible by 4, timeout>=16");
    end endgenerate
    localparam [3:0] IDLE=0,OPEN=1,ADDRESS=2,RECEIVE=3,BYTES=4,EMIT=5,FINISH=6,RESULT=7;
    localparam integer TW=$clog2(TIMEOUT_CYCLES+1);
    reg [3:0] state;
    reg [TW-1:0] timer;
    reg [31:0] address_q,expected_q,crc_state,rgba_q;
    reg [127:0] data_q;
    reg [4:0] burst_beats,beat_index;
    reg [1:0] byte_index,word_index;
    reg burst_end,outstanding,uncertain;
    wire cache_load_ready,cache_stream_ready,cache_fault;
    function automatic descriptor_ok(input [31:0] base,bytes,id,generation,checksum);
        reg [32:0] last_byte;
        begin
            last_byte={1'b0,base}+{1'b0,bytes};
            descriptor_ok=(^{base,bytes,id,generation,checksum})!==1'bx&&base[3:0]==0&&
                bytes==TEXELS*4&&base>=32'h82600000&&last_byte<=33'h082800000&&
                (!COMPACT_PRESET||(id==AVATAR_SPAN_ID&&generation==AVATAR_SPAN_GENERATION&&checksum==AVATAR_SPAN_CRC));
        end
    endfunction
    function automatic [4:0] burst_length(input [31:0] address,left_bytes);
        reg [31:0] n,page;
        begin n=left_bytes>>4;page=(4096-{20'd0,address[11:0]})>>4;
            if(n>16)n=16;if(n>page)n=page;burst_length=n[4:0];end
    endfunction
    function automatic [31:0] crc_byte(input [31:0] old_crc,input [7:0] data);
        reg [31:0] value;integer i;
        begin value=old_crc^{24'd0,data};
            for(i=0;i<8;i=i+1)value=(value>>1)^(value[0]?32'hedb88320:32'd0);
            crc_byte=value;end
    endfunction
    wire [31:0] next_crc=crc_byte(crc_state,data_q[7:0]);
    // The final cache write is the completion proof. FINISH only publishes it;
    // a later online loss must not turn that historical load into a failure.
    wire busy=state!=IDLE&&state!=RESULT&&state!=FINISH;
    wire stray=rvalid&&!outstanding&&!(state==ADDRESS&&arready);
    wire timed_out=busy&&timer==TIMEOUT_CYCLES-1;
    wire stopping=fault||!online||timed_out||stray||cache_fault;
    wire bad_response=rid!==AXI_ID||rresp!==2'b00||rlast!==(beat_index==burst_beats-1)||
        (^{rid,rresp,rlast,rdata})===1'bx;
    wire cache_stream_valid=state==EMIT&&!stopping;
    assign load_ready=core_reset_n&&state==IDLE&&online&&!fault&&!rvalid&&cache_load_ready;
    assign arid=AXI_ID;assign araddr=address_q;assign arlen={3'd0,burst_beats}-8'd1;
    assign arsize=4;assign arburst=1;assign arvalid=core_reset_n&&state==ADDRESS;
    assign rready=core_reset_n&&state==RECEIVE;
    assign port_drained=core_reset_n&&!outstanding&&!arvalid&&!uncertain;
    assign result_valid=core_reset_n&&state==RESULT;assign result_success=result_code==0;
    avatar_texture_cache #(.TEXELS(TEXELS),.COMPACT_PRESET(COMPACT_PRESET)) u_cache(
        .core_clk(core_clk),.core_reset_n(core_reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .load_valid(state==OPEN&&!stopping),.load_ready(cache_load_ready),
        .load_asset_id(result_asset_id),.load_generation(result_generation),
        .s_valid(cache_stream_valid),.s_ready(cache_stream_ready),.s_rgba(rgba_q),.s_last(words_written==TEXELS-1),
        .asset_ready(asset_ready),.load_fault(cache_fault),.asset_id(asset_id),.asset_generation(asset_generation),.words_written(words_written),
        .pixel_asset_ready(pixel_asset_ready),.pixel_req_valid(pixel_req_valid),.pixel_req_addr(pixel_req_addr),
        .pixel_req_asset_id(pixel_req_asset_id),.pixel_req_generation(pixel_req_generation),
        .sample_valid(sample_valid),.sample_error(sample_error),.sample_rgba(sample_rgba));
    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin
            state<=IDLE;timer<=0;address_q<=0;expected_q<=0;crc_state<=32'hffffffff;rgba_q<=0;data_q<=0;
            burst_beats<=0;beat_index<=0;byte_index<=0;word_index<=0;burst_end<=0;outstanding<=0;uncertain<=0;
            result_code<=0;result_asset_id<=0;result_generation<=0;checked_bytes<=0;crc<=0;fault<=0;fault_code<=0;
        end else begin
            if(!busy||state==BYTES||(arvalid&&arready)||(rvalid&&rready)||(cache_stream_valid&&cache_stream_ready))timer<=0;
            else if(!timed_out)timer<=timer+1'b1;
            // Drain trust may still be lost after the first sticky fault.
            if(stray)uncertain<=1;
            if(!fault)begin
                if(stray)begin fault<=1;fault_code<=6;end
                else if(busy&&!online)begin fault<=1;fault_code<=3;end
                else if(timed_out)begin fault<=1;fault_code<=4;end
                else if(cache_fault)begin fault<=1;fault_code<=7;end
            end
            case(state)
                IDLE:if(load_valid&&load_ready)begin
                    result_asset_id<=load_asset_id;result_generation<=load_generation;
                    expected_q<=expected_crc;address_q<=load_base;
                    burst_beats<=burst_length(load_base,TEXELS*4);beat_index<=0;
                    if(!descriptor_ok(load_base,load_bytes,load_asset_id,load_generation,expected_crc))begin fault<=1;fault_code<=1;state<=FINISH;end
                    else state<=OPEN;
                end
                OPEN:if(stopping)state<=FINISH;else if(cache_load_ready)state<=ADDRESS;
                // Advertised VALID and payload survive online loss or timeout.
                ADDRESS:if(arready)begin outstanding<=1;beat_index<=0;state<=RECEIVE;end
                RECEIVE:if(rvalid)begin
                    burst_end<=beat_index==burst_beats-1;beat_index<=beat_index+1'b1;
                    if(beat_index==burst_beats-1)outstanding<=0;
                    if(bad_response&&!fault)begin fault<=1;fault_code<=2;end
                    if(rid!==AXI_ID||rlast!==(beat_index==burst_beats-1)||(^{rid,rresp,rlast,rdata})===1'bx)uncertain<=1;
                    if(stopping||bad_response)begin if(beat_index==burst_beats-1)state<=FINISH;end
                    else begin data_q<=rdata;byte_index<=0;word_index<=0;state<=BYTES;end
                end
                BYTES:if(stopping)state<=outstanding?RECEIVE:FINISH;
                    else begin
                        data_q<=data_q>>8;rgba_q<={rgba_q[23:0],data_q[7:0]};crc_state<=next_crc;
                        checked_bytes<=checked_bytes+1'b1;crc<=~next_crc;
                        if(byte_index==3)begin
                            byte_index<=0;
                            if(words_written==TEXELS-1&&~next_crc!=expected_q)begin fault<=1;fault_code<=5;state<=FINISH;end
                            else state<=EMIT;
                        end else byte_index<=byte_index+1'b1;
                    end
                EMIT:if(stopping)state<=outstanding?RECEIVE:FINISH;
                    else if(cache_stream_ready)begin
                        if(word_index!=3)begin word_index<=word_index+1'b1;state<=BYTES;end
                        else if(!burst_end)state<=RECEIVE;
                        else if(words_written==TEXELS-1)state<=FINISH;
                        else begin address_q<=address_q+{23'd0,burst_beats,4'd0};
                            burst_beats<=burst_length(address_q+{23'd0,burst_beats,4'd0},(TEXELS-words_written-1)*4);state<=ADDRESS;end
                    end
                FINISH:begin result_code<=fault?fault_code:8'd0;state<=RESULT;end
                RESULT:if(result_ready)state<=IDLE;
                default:begin fault<=1;fault_code<=7;state<=FINISH;end
            endcase
        end
    end
endmodule
`default_nettype wire
