/* Boot-only packet store: one byte-wide synchronous block RAM, assembled
 * into sixteen held AXI128 beats. Packing takes 32 core clocks per beat;
 * it is hidden by millisecond UART packet time and never used for inference.
 * The owner must not write or start a new packet while busy_o is asserted.
 */
module triha_boot_buffer(
    input wire clk_i,rst_ni,write_i,
    input wire [7:0] write_address_i,write_data_i,
    input wire start_i,
    output wire busy_o,valid_o,
    input wire ready_i,
    output wire [127:0] data_o,
    output wire last_o
);
    localparam IDLE=0,FETCH=1,PACK=2,SEND=3;
    reg [1:0] state;
    reg [3:0] beat,byte_index;
    (* syn_ramstyle="block_ram" *) reg [7:0] bytes[0:255];
    reg [7:0] read_byte;
    reg [127:0] word_data;
    // Data storage and read register are intentionally unreset. Every byte
    // must be written and every output beat fully assembled before valid.
    always @(posedge clk_i)begin
        if(write_i)bytes[write_address_i]<=write_data_i;
        if(state==FETCH)read_byte<=bytes[{beat,byte_index}];
        if(state==PACK)word_data<={read_byte,word_data[127:8]};
    end
    assign busy_o=state!=IDLE;
    assign valid_o=state==SEND;
    assign data_o=word_data;
    assign last_o=beat==15;
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin state<=IDLE;beat<=0;byte_index<=0;end
        else case(state)
            IDLE:if(start_i)begin beat<=0;byte_index<=0;state<=FETCH;end
            FETCH:state<=PACK;
            PACK:if(byte_index==15)state<=SEND;
                else begin byte_index<=byte_index+1'b1;state<=FETCH;end
            SEND:if(ready_i)begin
                if(beat==15)state<=IDLE;
                else begin beat<=beat+1'b1;byte_index<=0;state<=FETCH;end
            end
            default:state<=IDLE;
        endcase
    end
endmodule
