`timescale 1ns/1ps
`default_nettype none
// Read one retired image plane. No new task until all advertised reads drain.
module video_frame_crc_reader #(
    parameter [3:0] AXI_ID=4'h6,
    parameter integer TIMEOUT_CYCLES=625000000
)(
    input wire clk,reset_n,online,abort,req_valid,
    output wire req_ready,
    input wire [31:0] req_base,req_row_bytes,req_stride,req_tag,expected_crc,
    input wire [15:0] req_rows,
    output wire result_valid,input wire result_ready,
    output wire result_success,output reg [7:0] result_code,
    output reg [31:0] result_tag,checked_bytes,crc,
    output wire busy,output reg fault,
    output wire [3:0] arid,output wire [31:0] araddr,
    output wire [7:0] arlen,output wire [2:0] arsize,
    output wire [1:0] arburst,output wire arvalid,input wire arready,
    input wire [3:0] rid,input wire [127:0] rdata,
    input wire [1:0] rresp,input wire rlast,rvalid,output wire rready
);
    localparam [2:0] IDLE=0,PREPARE=1,ADDRESS=2,RECEIVE=3,BYTES=4,RESULT=5;
    localparam integer TW=TIMEOUT_CYCLES>1?$clog2(TIMEOUT_CYCLES+1):1;
    reg [2:0] state;
    reg [TW-1:0] timer;
    reg [31:0] row_base,address_q,row_bytes_q,stride_q,row_remaining,expected_q,crc_state;
    reg [15:0] rows_q,row_index;
    reg [4:0] burst_beats,beat_index,byte_index,byte_count;
    reg [127:0] data_q;
    function automatic descriptor_ok(input [31:0] base,row_bytes,stride,input [15:0] rows);
        reg [63:0] last_byte,bus_end;
        begin
            last_byte={32'd0,base}+({48'd0,rows}-64'd1)*{32'd0,stride}+{32'd0,row_bytes};
            bus_end=(last_byte+64'd15)&64'hfffffffffffffff0;
            descriptor_ok=rows!=0&&row_bytes!=0&&stride>=row_bytes&&base[3:0]==0&&stride[3:0]==0&&
                base>=32'h80000000&&last_byte>{32'd0,base}&&bus_end<=64'h88000000;
        end
    endfunction
    function automatic [4:0] burst_length(input [31:0] left,address);
        reg [32:0] beats;reg [8:0] page_beats;
        begin
            beats=({1'b0,left}+33'd15)>>4;
            page_beats=(13'd4096-{1'b0,address[11:0]})>>4;
            if(beats>16)beats=16;
            if(beats>page_beats)beats=page_beats;
            burst_length=beats[4:0];
        end
    endfunction
    function automatic [31:0] crc_byte(input [31:0] old_crc,input [7:0] data);
        reg [31:0] value;integer i;
        begin
            value=old_crc^{24'd0,data};
            for(i=0;i<8;i=i+1)value=(value>>1)^(value[0]?32'hedb88320:32'd0);
            crc_byte=value;
        end
    endfunction
    wire [31:0] next_crc=crc_byte(crc_state,data_q[byte_index*8+:8]);
    reg [7:0] fault_now;
    always @* begin
        fault_now=0;
        if(busy)begin
            if(!online)fault_now=8'h02;
            else if(abort)fault_now=8'h03;
            else if(state==RECEIVE&&rvalid&&(rid!==AXI_ID||rresp!==2'b00||rlast!==(beat_index==burst_beats-1)))fault_now=8'h05;
            else if(timer>=TIMEOUT_CYCLES-1)fault_now=8'h04;
        end
    end
    wire stopping=result_code!=0||fault_now!=0;
    assign req_ready=reset_n&&state==IDLE&&online&&!abort&&!fault&&!rvalid;
    assign result_valid=reset_n&&state==RESULT;
    assign result_success=result_code===8'd0;
    assign busy=state!=IDLE&&state!=RESULT;
    assign arid=AXI_ID;assign araddr=address_q;
    assign arlen={3'd0,burst_beats}-8'd1;
    assign arsize=3'd4;assign arburst=2'b01;
    assign arvalid=reset_n&&state==ADDRESS;
    assign rready=reset_n&&state==RECEIVE;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;timer<=0;result_code<=0;result_tag<=0;checked_bytes<=0;crc<=0;fault<=0;
            row_base<=0;address_q<=0;row_bytes_q<=0;stride_q<=0;row_remaining<=0;expected_q<=0;
            crc_state<=32'hffffffff;rows_q<=0;row_index<=0;burst_beats<=0;beat_index<=0;
            byte_index<=0;byte_count<=0;data_q<=0;
        end else begin
            if(busy&&timer<TIMEOUT_CYCLES-1)timer<=timer+1'b1;
            if(fault_now!=0)begin fault<=1;if(result_code==0)result_code<=fault_now;end
            if((state==IDLE||state==PREPARE||state==RESULT)&&rvalid)begin
                // A published result is immutable under backpressure. The
                // separate sticky fault revokes port health for its owner.
                fault<=1;if(state!=RESULT&&result_code==0)result_code<=8'h05;
            end
            case(state)
                IDLE:if(req_valid&&req_ready)begin
                    result_code<=0;result_tag<=(^req_tag===1'bx)?32'd0:req_tag;checked_bytes<=0;crc<=0;timer<=0;
                    crc_state<=32'hffffffff;row_index<=0;
                    if(descriptor_ok(req_base,req_row_bytes,req_stride,req_rows)!==1'b1 ||
                       (^req_tag===1'bx) || (^expected_crc===1'bx))begin
                        result_code<=8'h01;state<=RESULT;
                    end else begin
                        row_base<=req_base;address_q<=req_base;row_bytes_q<=req_row_bytes;
                        stride_q<=req_stride;rows_q<=req_rows;row_remaining<=req_row_bytes;
                        expected_q<=expected_crc;state<=PREPARE;
                    end
                end
                PREPARE:if(stopping||rvalid)state<=RESULT;
                    else begin burst_beats<=burst_length(row_remaining,address_q);beat_index<=0;state<=ADDRESS;end
                ADDRESS:if(arready)state<=RECEIVE;
                RECEIVE:if(rvalid)begin
                    if(stopping)begin
                        if(beat_index==burst_beats-1)state<=RESULT;
                        else beat_index<=beat_index+1'b1;
                    end else begin
                        data_q<=rdata;byte_index<=0;
                        byte_count<=row_remaining>=16?5'd16:row_remaining[4:0];state<=BYTES;
                    end
                end
                BYTES:if(stopping)begin
                    if(beat_index==burst_beats-1)state<=RESULT;
                    else begin beat_index<=beat_index+1'b1;state<=RECEIVE;end
                end else begin
                    crc_state<=next_crc;checked_bytes<=checked_bytes+1'b1;
                    if(byte_index==byte_count-1)begin
                        if(row_remaining<=16)begin
                            if(row_index==rows_q-1)begin
                                crc<=~next_crc;
                                if((^next_crc===1'bx)||(~next_crc)!==expected_q)begin result_code<=8'h0b;fault<=1;end
                                state<=RESULT;
                            end else begin
                                row_index<=row_index+1'b1;row_base<=row_base+stride_q;
                                address_q<=row_base+stride_q;row_remaining<=row_bytes_q;state<=PREPARE;
                            end
                        end else begin
                            address_q<=address_q+32'd16;row_remaining<=row_remaining-32'd16;
                            if(beat_index==burst_beats-1)state<=PREPARE;
                            else begin beat_index<=beat_index+1'b1;state<=RECEIVE;end
                        end
                    end else byte_index<=byte_index+1'b1;
                end
                RESULT:if(result_ready)state<=IDLE;
                default:begin fault<=1;result_code<=8'h0a;state<=RESULT;end
            endcase
        end
    end
    generate if(TIMEOUT_CYCLES<1)begin:invalid_parameters
        initial $fatal(1,"CRC reader timeout must be positive");
    end endgenerate
endmodule
`default_nettype wire
