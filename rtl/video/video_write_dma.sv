`timescale 1ns/1ps
`default_nettype none
// One descriptor, one fully buffered burst, one outstanding B response.
// This is a single-plane write engine; it does not publish CAPTURE_DONE.
// Abort stops stream intake, drops unpublished data, and drains any exposed
// AW/W/B. Producer must flush its old stream before the next descriptor.
module video_write_dma #(
    parameter [3:0] AXI_ID=4'h3
)(
    input wire clk,reset_n,online,abort,
    input wire req_valid,output wire req_ready,
    input wire [31:0] req_base,req_row_bytes,req_stride,req_tag,
    input wire [15:0] req_rows,
    input wire s_valid,output wire s_ready,
    input wire [127:0] s_data,input wire [15:0] s_keep,input wire s_row_last,
    output wire result_valid,input wire result_ready,
    output wire result_success,output reg [7:0] result_code,
    output reg [31:0] result_tag,written_bytes,
    output wire busy,output reg fault,
    output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
    output wire [2:0] awsize,output wire [1:0] awburst,
    output wire awvalid,input wire awready,
    output wire [127:0] wdata,output wire [15:0] wstrb,
    output wire wlast,wvalid,input wire wready,
    input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
    localparam [2:0] IDLE=0,FILL=1,AW=2,W=3,B=4,RESULT=5;
    localparam [7:0] BAD_DESCRIPTOR=1,BAD_STREAM=2,ABORTED=3,OFFLINE=4,
                     BAD_BID=5,BUS_ERROR=6,STRAY_B=7;
    reg [2:0] state;
    reg seen_online;
    reg [31:0] row_bytes_q,stride_q,row_base,address_q,row_remaining;
    reg [15:0] rows_q,row_index;
    reg [4:0] burst_beats,fill_index,write_index;
    reg [8:0] burst_bytes;
    (* syn_ramstyle="select_ram" *) reg [127:0] data_buffer[0:15];
    (* syn_ramstyle="select_ram" *) reg [15:0] keep_buffer[0:15];
    reg [127:0] data_hold;
    reg [15:0] keep_hold;
    wire [4:0] expected_bytes=row_remaining>=16?5'd16:row_remaining[4:0];
    wire [15:0] expected_keep=16'hffff>>(16-expected_bytes);
    wire stop_now=abort || !online;
    function automatic [4:0] choose_burst(input [31:0] bytes_left,input [31:0] address);
        reg [32:0] beats;
        reg [8:0] page_beats;
        begin
            beats=({1'b0,bytes_left}+33'd15)>>4;
            page_beats=(13'd4096-{1'b0,address[11:0]})>>4;
            if(beats>16)beats=16;
            if(beats>page_beats)beats=page_beats;
            choose_burst=beats[4:0];
        end
    endfunction
    function automatic descriptor_ok(input [31:0] base,bytes_per_row,stride,input [15:0] rows);
        reg [63:0] last_exclusive,last_bus_exclusive;
        begin
            last_exclusive={32'd0,base}+({48'd0,rows}-64'd1)*{32'd0,stride}+{32'd0,bytes_per_row};
            last_bus_exclusive=(last_exclusive+64'd15)&64'hfffffffffffffff0;
            descriptor_ok=rows!=0 && bytes_per_row!=0 && base[3:0]==0 && stride[3:0]==0 &&
                stride>=bytes_per_row && base>=32'h80000000 && last_bus_exclusive<=64'h88000000 &&
                last_exclusive>{32'd0,base};
        end
    endfunction
    assign req_ready=reset_n && online && !abort && !fault && !bvalid && state==IDLE;
    assign s_ready=reset_n && state==FILL && !stop_now && !fault && !bvalid;
    assign busy=state!=IDLE && state!=RESULT;
    assign result_valid=reset_n && state==RESULT;
    assign result_success=result_code==0;
    assign awid=AXI_ID;assign awaddr=address_q;
    assign awlen={3'd0,burst_beats}-8'd1;
    assign awsize=3'd4;assign awburst=2'b01;
    // Once exposed, neither online loss nor abort withdraws VALID or data.
    assign awvalid=reset_n && state==AW;
    assign wvalid=reset_n && state==W;
    assign wdata=data_hold;assign wstrb=keep_hold;
    assign wlast=write_index==burst_beats-1;
    assign bready=reset_n && state==B;
    wire store=reset_n && s_valid && s_ready;
    always @(posedge clk)begin
        if(store)begin data_buffer[fill_index[3:0]]<=s_data;keep_buffer[fill_index[3:0]]<=s_keep;end
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;fault<=0;seen_online<=0;result_code<=0;result_tag<=0;written_bytes<=0;
            row_bytes_q<=0;stride_q<=0;row_base<=0;address_q<=0;row_remaining<=0;
            rows_q<=0;row_index<=0;burst_beats<=0;fill_index<=0;write_index<=0;
            burst_bytes<=0;data_hold<=0;keep_hold<=0;
        end else begin
            if(online)seen_online<=1;
            if(!online && seen_online)fault<=1;
            if(bvalid && state==RESULT)fault<=1;
            if(bvalid && (state==AW || state==W))begin
                fault<=1;
                if(result_code==0)result_code<=STRAY_B;
            end
            if((state==IDLE || state==FILL) && bvalid)begin
                fault<=1;
                if(state==FILL)begin result_code<=STRAY_B;state<=RESULT;end
            end else case(state)
                IDLE:if(req_valid && req_ready)begin
                    result_tag<=req_tag;result_code<=0;written_bytes<=0;
                    if(!descriptor_ok(req_base,req_row_bytes,req_stride,req_rows))begin
                        result_code<=BAD_DESCRIPTOR;state<=RESULT;
                    end else begin
                        row_bytes_q<=req_row_bytes;stride_q<=req_stride;rows_q<=req_rows;
                        row_index<=0;row_base<=req_base;address_q<=req_base;
                        row_remaining<=req_row_bytes;burst_beats<=choose_burst(req_row_bytes,req_base);
                        fill_index<=0;burst_bytes<=0;state<=FILL;
                    end
                end
                FILL:begin
                    if(stop_now || fault)begin
                        result_code<=abort?ABORTED:OFFLINE;state<=RESULT;
                    end else if(store)begin
                        if(s_keep!==expected_keep || s_row_last!==(row_remaining<=16))begin
                            result_code<=BAD_STREAM;state<=RESULT;
                        end else begin
                            burst_bytes<=burst_bytes+expected_bytes;
                            row_remaining<=row_remaining-expected_bytes;
                            if(fill_index==burst_beats-1)begin
                                // First buffer word is already present except a one-beat burst.
                                data_hold<=fill_index==0?s_data:data_buffer[0];
                                keep_hold<=fill_index==0?s_keep:keep_buffer[0];
                                write_index<=0;state<=AW;
                            end else fill_index<=fill_index+1'b1;
                        end
                    end
                end
                AW:begin
                    if(stop_now && result_code==0)result_code<=abort?ABORTED:OFFLINE;
                    if(awready)state<=W;
                end
                W:begin
                    if(stop_now && result_code==0)result_code<=abort?ABORTED:OFFLINE;
                    if(wready)begin
                        if(wlast)state<=B;
                        else begin
                            write_index<=write_index+1'b1;
                            data_hold<=data_buffer[write_index[3:0]+4'd1];
                            keep_hold<=keep_buffer[write_index[3:0]+4'd1];
                        end
                    end
                end
                B:begin
                    if(stop_now && result_code==0)result_code<=abort?ABORTED:OFFLINE;
                    if(bvalid)begin
                        if(bid!==AXI_ID)begin fault<=1;result_code<=BAD_BID;state<=RESULT;end
                        else if(bresp!==2'b00)begin result_code<=BUS_ERROR;state<=RESULT;end
                        else begin
                            written_bytes<=written_bytes+burst_bytes;
                            if(result_code!=0 || stop_now || fault)begin
                                if(result_code==0)result_code<=abort?ABORTED:OFFLINE;
                                state<=RESULT;
                            end else if(row_remaining==0 && row_index==rows_q-1)state<=RESULT;
                            else begin
                                fill_index<=0;burst_bytes<=0;state<=FILL;
                                if(row_remaining==0)begin
                                    row_index<=row_index+1'b1;row_base<=row_base+stride_q;
                                    address_q<=row_base+stride_q;row_remaining<=row_bytes_q;
                                    burst_beats<=choose_burst(row_bytes_q,row_base+stride_q);
                                end else begin
                                    address_q<=address_q+{23'd0,burst_beats,4'd0};
                                    burst_beats<=choose_burst(row_remaining,address_q+{23'd0,burst_beats,4'd0});
                                end
                            end
                        end
                    end
                end
                RESULT:if(result_ready)state<=IDLE;
                default:begin fault<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
`default_nettype wire
