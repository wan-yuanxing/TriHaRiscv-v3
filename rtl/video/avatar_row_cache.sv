`timescale 1ns/1ps
`default_nettype none
// Bounded material cache for the production Video path. The asset is verified
// as a complete immutable stream, but only two 256-texel rows are retained in
// on-chip RAM. Pixel misses stop the request channel until a complete AXI row
// has arrived; no stale or fabricated sample is ever reported as valid.
module avatar_row_cache #(
    parameter integer TEXELS=65536,
    parameter integer ROW_TEXELS=256,
    parameter integer TIMEOUT_CYCLES=125000000,
    parameter [3:0] AXI_ID=4'h9
)(
    input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,online,
    input wire load_valid,output wire load_ready,
    input wire [31:0] load_base,load_bytes,load_asset_id,load_generation,expected_crc,
    output reg result_valid,input wire result_ready,output reg result_success,
    output reg [7:0] result_code,output reg [31:0] result_asset_id,result_generation,
    output reg [31:0] checked_bytes,crc,
    output reg fault,output reg [7:0] fault_code,output wire port_drained,
    output reg asset_ready,output wire pixel_asset_ready,
    output reg [31:0] asset_id,asset_generation,words_written,
    input wire sample_req_valid,output wire sample_req_ready,
    input wire [17:0] sample_req_addr,input wire [31:0] sample_req_asset_id,sample_req_generation,
    input wire prefetch_valid,output wire prefetch_ready,input wire [17:0] prefetch_addr,
    input wire [31:0] prefetch_asset_id,prefetch_generation,
    output reg sample_rsp_valid,output reg sample_rsp_error,output reg [31:0] sample_rgba,
    output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
    output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
    input wire [3:0] rid,input wire [127:0] rdata,input wire [1:0] rresp,input wire rlast,
    input wire rvalid,output wire rready
);
    localparam integer ROW_BYTES=ROW_TEXELS*4;
    localparam integer ROWS=TEXELS/ROW_TEXELS;
    localparam integer LOAD_BEATS=(TEXELS*4)/16;
    localparam integer LOAD_BURSTS=(LOAD_BEATS+15)/16;
    localparam integer CW=$clog2(TIMEOUT_CYCLES+1);
    localparam [3:0] S_IDLE=0,S_LOAD_ADDR=1,S_LOAD_READ=2,S_FINISH=3,S_RESULT=4,
                     S_ROW_ADDR=5,S_ROW_READ=6,S_FAULT=7;
    generate
        if(TEXELS<4||ROW_TEXELS<4||TEXELS%ROW_TEXELS!=0||
           (TEXELS*4)%16!=0||ROW_TEXELS*4>4096||TIMEOUT_CYCLES<16) begin:bad_params
            initial $fatal(1,"avatar_row_cache geometry or timeout is invalid");
        end
    endgenerate

    (* syn_ramstyle = "block_ram" *) reg [31:0] row0 [0:ROW_TEXELS-1];
    (* syn_ramstyle = "block_ram" *) reg [31:0] row1 [0:ROW_TEXELS-1];
    reg row0_valid,row1_valid;
    reg [31:0] row0_number,row1_number;
    reg [31:0] base_q,expected_q,crc_state,asset_id_q,generation_q;
    reg [31:0] row_request_number,row_request_asset,row_request_generation;
    reg [31:0] row_word_base;
    reg [CW-1:0] timer;
    reg [3:0] state;
    reg [9:0] load_burst;
    reg [4:0] load_beat,row_beat;
    reg [1:0] row_burst;
    reg row_bank,row_pending,row_outstanding,row_bad;
    reg [31:0] sample_request_hold;
    reg [31:0] request_asset_hold,request_generation_hold;
    reg request_toggle,response_toggle,response_bank;
    // Request metadata is launched in the pixel domain with the toggle. The
    // prefetch bit is synchronized independently before core-domain use.
    reg request_prefetch_pixel;
    reg request_prefetch_meta_core,request_prefetch_sync_core;
    reg pixel_request_token,pixel_request_prefetch_token,pixel_request_pending;
    (* ASYNC_REG="TRUE" *) reg request_meta_core,request_sync_core;
    (* ASYNC_REG="TRUE" *) reg request_meta_pixel,request_sync_pixel,response_meta_pixel,response_sync_pixel;
    reg response_bank_hold;
    wire [31:0] sample_texel={14'd0,sample_req_addr[17:2]};
    wire [31:0] sample_row=sample_texel/ROW_TEXELS;
    wire [31:0] sample_x=sample_texel%ROW_TEXELS;
    wire sample_identity_ok=pixel_asset_ready&&sample_req_asset_id===asset_id&&
        sample_req_generation===asset_generation;

    function automatic [31:0] crc_byte(input [31:0] old_crc,input [7:0] byte_value);
        reg [31:0] value;integer bit_index;
        begin
            value=old_crc^{24'd0,byte_value};
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                value=(value>>1)^(value[0]?32'hedb88320:32'd0);
            crc_byte=value;
        end
    endfunction
    function automatic [31:0] crc_word(input [31:0] old_crc,input [127:0] word_value);
        reg [31:0] value;integer byte_index;
        begin
            value=old_crc;
            for(byte_index=0;byte_index<16;byte_index=byte_index+1)
                value=crc_byte(value,word_value[byte_index*8+:8]);
            crc_word=value;
        end
    endfunction
    wire [31:0] next_crc=crc_word(crc_state,rdata);
    wire load_last=(load_burst==LOAD_BURSTS-1&&load_beat==15);
    wire row_last=(row_beat==15);
    wire response_fire=rvalid&&rready;
    wire bad_response=(rid!==AXI_ID)||(rresp!==2'b00)||(rlast!==(state==S_LOAD_READ?load_beat==15:row_last))||
                      ((^{rid,rresp,rlast,rdata})===1'bx);
    wire timeout_hit=(state!=S_IDLE&&state!=S_RESULT&&timer==TIMEOUT_CYCLES-1);
    wire transport_fault=!online||timeout_hit||bad_response;
    wire [31:0] request_row_current=sample_request_hold/ROW_TEXELS;

    assign load_ready=core_reset_n&&state==S_IDLE&&!fault&&!asset_ready;
    assign arid=AXI_ID;
    assign araddr=state==S_LOAD_ADDR?base_q+{20'd0,load_burst,8'd0}:
                  base_q+row_request_number*ROW_BYTES+{23'd0,row_burst,8'd0};
    assign arlen=8'd15;
    assign arsize=3'd4;assign arburst=2'b01;
    assign arvalid=core_reset_n&&(state==S_LOAD_ADDR||state==S_ROW_ADDR);
    assign rready=core_reset_n&&(state==S_LOAD_READ||state==S_ROW_READ);
    assign port_drained=core_reset_n&&!row_outstanding&&!arvalid&&state!=S_LOAD_READ&&state!=S_ROW_READ;
    assign pixel_asset_ready=pixel_reset_n&&asset_ready;
    assign sample_req_ready=pixel_reset_n&&pixel_asset_ready&&!pixel_request_pending&&!sample_rsp_valid&&sample_identity_ok&&!fault;
    assign prefetch_ready=pixel_reset_n&&pixel_asset_ready&&!pixel_request_pending&&!sample_rsp_valid&&
        prefetch_asset_id===asset_id&&prefetch_generation===asset_generation&&!fault;

    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            request_meta_pixel<=0;request_sync_pixel<=0;response_meta_pixel<=0;response_sync_pixel<=0;
            request_toggle<=0;request_prefetch_pixel<=0;sample_request_hold<=0;request_asset_hold<=0;request_generation_hold<=0;
            pixel_request_pending<=0;pixel_request_token<=0;pixel_request_prefetch_token<=0;
            sample_rsp_valid<=0;sample_rsp_error<=0;sample_rgba<=0;
        end else begin
            request_meta_pixel<=request_toggle;request_sync_pixel<=request_meta_pixel;
            response_meta_pixel<=response_toggle;response_sync_pixel<=response_meta_pixel;
            sample_rsp_valid<=0;sample_rsp_error<=0;
            if(sample_req_valid&&sample_req_ready) begin
                sample_request_hold<=sample_texel;request_asset_hold<=sample_req_asset_id;
                request_generation_hold<=sample_req_generation;request_toggle<=~request_toggle;
                pixel_request_token<=~request_toggle;
                request_prefetch_pixel<=0;pixel_request_prefetch_token<=0;
                pixel_request_pending<=1;
            end else if(prefetch_valid&&prefetch_ready) begin
                sample_request_hold<={14'd0,prefetch_addr[17:2]};request_asset_hold<=prefetch_asset_id;
                request_generation_hold<=prefetch_generation;request_toggle<=~request_toggle;
                pixel_request_token<=~request_toggle;request_prefetch_pixel<=1;
                pixel_request_prefetch_token<=1;pixel_request_pending<=1;
            end
            if(pixel_request_pending&&response_sync_pixel==pixel_request_token) begin
                // A row response is acknowledged by the core only after all
                // 64 AXI beats and all row words have been committed.
                if(!pixel_request_prefetch_token) begin
                    if(response_bank_hold)sample_rgba<=row1[sample_request_hold%ROW_TEXELS];
                    else sample_rgba<=row0[sample_request_hold%ROW_TEXELS];
                    sample_rsp_valid<=1;sample_rsp_error<=row_bad;
                end
                pixel_request_pending<=0;
            end
        end
    end

    always @(posedge core_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin
            request_meta_core<=0;request_sync_core<=0;response_toggle<=0;response_bank_hold<=0;
            request_prefetch_meta_core<=0;request_prefetch_sync_core<=0;
            state<=S_IDLE;fault<=0;fault_code<=0;asset_ready<=0;asset_id<=0;asset_generation<=0;
            result_valid<=0;result_success<=0;result_code<=0;result_asset_id<=0;result_generation<=0;
            checked_bytes<=0;crc<=0;crc_state<=32'hffffffff;words_written<=0;timer<=0;
            base_q<=0;expected_q<=0;asset_id_q<=0;generation_q<=0;load_burst<=0;load_beat<=0;
            row0_valid<=0;row1_valid<=0;row0_number<=0;row1_number<=0;row_request_number<=0;
            row_request_asset<=0;row_request_generation<=0;row_word_base<=0;row_beat<=0;row_burst<=0;
            row_bank<=0;row_pending<=0;row_outstanding<=0;row_bad<=0;
        end else begin
            request_meta_core<=request_toggle;request_sync_core<=request_meta_core;
            request_prefetch_meta_core<=request_prefetch_pixel;
            request_prefetch_sync_core<=request_prefetch_meta_core;
            if(result_valid&&result_ready)result_valid<=0;
            if(state==S_IDLE||state==S_RESULT||response_fire)timer<=0;
            else if(!timeout_hit)timer<=timer+1'b1;
            if(!fault&&transport_fault&&state!=S_IDLE&&state!=S_RESULT) begin
                fault<=1;fault_code<=(!online?8'd3:timeout_hit?8'd4:8'd2);row_bad<=1;state<=S_FAULT;
                if(row_pending) begin
                    row_pending<=0;response_bank_hold<=0;response_toggle<=request_sync_core;
                end
            end
            if(load_valid&&load_ready) begin
                result_asset_id<=load_asset_id;result_generation<=load_generation;
                asset_id_q<=load_asset_id;generation_q<=load_generation;base_q<=load_base;expected_q<=expected_crc;
                checked_bytes<=0;crc_state<=32'hffffffff;crc<=0;words_written<=0;
                asset_ready<=0;load_burst<=0;load_beat<=0;
                if((^{load_base,load_bytes,load_asset_id,load_generation,expected_crc})===1'bx||
                   load_base[3:0]!=0||load_bytes!=TEXELS*4||load_base<32'h82600000||
                   {33'd0,load_base}+{33'd0,load_bytes}>33'h082800000) begin
                    fault<=1;fault_code<=1;state<=S_FAULT;
                end else state<=S_LOAD_ADDR;
            end
            if(request_sync_core!=response_toggle&&!row_pending&&!fault) begin
                row_request_number<=request_row_current;
                row_request_asset<=request_asset_hold;row_request_generation<=request_generation_hold;
                row_bad<=0;
                if(request_asset_hold!==asset_id_q||request_generation_hold!==generation_q||!asset_ready) begin
                    row_bad<=1;response_bank_hold<=0;response_toggle<=request_sync_core;
                end else if(request_row_current==row0_number&&row0_valid) begin
                    response_bank_hold<=0;response_toggle<=request_sync_core;
                end else if(request_row_current==row1_number&&row1_valid) begin
                    response_bank_hold<=1;response_toggle<=request_sync_core;
                end else begin
                    row_bank<=!row1_valid?1'b1:(!row0_valid?1'b0:~response_bank_hold);
                    row_pending<=1;row_burst<=0;row_beat<=0;state<=S_ROW_ADDR;
                end
            end
            case(state)
                S_LOAD_ADDR:if(arready)begin row_outstanding<=1;load_beat<=0;state<=S_LOAD_READ;end
                S_LOAD_READ:if(response_fire)begin
                    if(bad_response)begin row_outstanding<=0;fault<=1;fault_code<=2;state<=S_FAULT;end
                    else begin
                        crc_state<=next_crc;crc<=~next_crc;checked_bytes<=checked_bytes+16;
                        load_beat<=load_beat+1'b1;
                        if(load_last)begin
                            row_outstanding<=0;
                            if(~next_crc!==expected_q)begin fault<=1;fault_code<=5;state<=S_FAULT;end
                            else begin asset_ready<=1;asset_id<=asset_id_q;asset_generation<=generation_q;state<=S_FINISH;end
                        end else if(load_beat==15)begin
                            load_burst<=load_burst+1'b1;state<=S_LOAD_ADDR;
                        end
                    end
                end
                S_ROW_ADDR:if(arready)begin row_outstanding<=1;row_beat<=0;state<=S_ROW_READ;end
                S_ROW_READ:if(response_fire)begin
                    if(bad_response)begin
                        row_outstanding<=0;row_pending<=0;fault<=1;fault_code<=2;row_bad<=1;
                        response_bank_hold<=0;response_toggle<=request_sync_core;state<=S_FAULT;
                    end else begin
                        if(row_bank)begin
                            row1[row_beat*4+0]<=rdata[31:0];row1[row_beat*4+1]<=rdata[63:32];
                            row1[row_beat*4+2]<=rdata[95:64];row1[row_beat*4+3]<=rdata[127:96];
                        end else begin
                            row0[row_beat*4+0]<=rdata[31:0];row0[row_beat*4+1]<=rdata[63:32];
                            row0[row_beat*4+2]<=rdata[95:64];row0[row_beat*4+3]<=rdata[127:96];
                        end
                        row_beat<=row_beat+1'b1;
                        if(row_last)begin
                            row_outstanding<=0;row_pending<=0;
                            if(row_bank)begin row1_valid<=1;row1_number<=row_request_number;end
                            else begin row0_valid<=1;row0_number<=row_request_number;end
                            response_bank_hold<=row_bank;response_toggle<=request_sync_core;
                            state<=S_IDLE;
                        end
                    end
                end
                S_FINISH:begin result_code<=0;result_success<=1;result_valid<=1;state<=S_RESULT;end
                S_FAULT:begin result_code<=fault_code;result_success<=0;result_valid<=1;state<=S_RESULT;end
                default:begin end
            endcase
        end
    end
endmodule
`default_nettype wire
