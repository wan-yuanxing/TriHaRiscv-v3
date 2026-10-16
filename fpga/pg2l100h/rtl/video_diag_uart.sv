`timescale 1ns/1ps
`default_nettype none
// Diagnostic framing: ASCII TRV1,32 little-endian payload bytes,XOR of prior36.
// Capture the entire payload before sending so one packet is a coherent sample.
module video_diag_uart #(
    parameter integer CLOCK_HZ=10_000_000,
    parameter integer BAUD=115200,
    parameter integer INTERVAL_CYCLES=10_000_000
)(input wire clk,reset_n,input wire[255:0]payload,output wire tx,output reg busy);
    localparam integer DIVISOR=(CLOCK_HZ+BAUD/2)/BAUD;
    localparam integer BW=DIVISOR>1?$clog2(DIVISOR):1;
    localparam integer IW=INTERVAL_CYCLES>1?$clog2(INTERVAL_CYCLES):1;
    generate if(CLOCK_HZ<BAUD || BAUD<1 || INTERVAL_CYCLES<1)begin:invalid_parameters
        initial $fatal(1,"Unsupported UART clock,baud or interval");
    end endgenerate
    reg[IW-1:0] interval_count;
    reg[BW-1:0] bit_count;
    reg[5:0] byte_index;
    reg[3:0] bit_index;
    reg[9:0] shift;
    reg[255:0] snapshot;
    reg[7:0] checksum;
    assign tx=reset_n && busy ? shift[0] : 1'b1;
    function automatic[7:0] packet_byte(input[5:0] index,input[255:0] data,input[7:0] sum);
        begin
            case(index)
                0:packet_byte="T";1:packet_byte="R";2:packet_byte="V";3:packet_byte="1";
                36:packet_byte=sum;
                default:packet_byte=data[(index-4)*8+:8];
            endcase
        end
    endfunction
    wire[7:0] next_byte=packet_byte(byte_index+1'b1,snapshot,checksum);
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n)begin
            busy<=0;interval_count<=0;bit_count<=0;byte_index<=0;
            bit_index<=0;shift<=10'h3ff;snapshot<=0;checksum<=0;
        end else begin
            if(interval_count<INTERVAL_CYCLES-1)interval_count<=interval_count+1'b1;
            if(!busy)begin
                if(interval_count==INTERVAL_CYCLES-1)begin
                    interval_count<=0;snapshot<=payload;busy<=1;byte_index<=0;
                    bit_count<=0;bit_index<=0;shift<={1'b1,8'h54,1'b0};checksum<=8'h54;
                end
            end else if(bit_count==DIVISOR-1)begin
                bit_count<=0;
                if(bit_index==9)begin
                    bit_index<=0;
                    if(byte_index==36)begin busy<=0;shift<=10'h3ff;end
                    else begin
                        byte_index<=byte_index+1'b1;shift<={1'b1,next_byte,1'b0};
                        checksum<=checksum^next_byte;
                    end
                end else begin shift<={1'b1,shift[9:1]};bit_index<=bit_index+1'b1;end
            end else bit_count<=bit_count+1'b1;
        end
    end
endmodule
`default_nettype wire
