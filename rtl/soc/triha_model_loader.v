`default_nettype none
`include "frame_config.vh"
// Boot-only, fixed-range loader. Packet: "THB1", segment LE32, offset LE32,
// payload CRC32 LE32, 256 payload bytes. Reply: "THA1", status, next segment,
// two zero bytes, next offset LE32. Only the last committed packet may retry.
// Segment order: program, parameter image, POST table, HEAD A/B/C, optional
// fixed avatar at SOC_AVATAR_BASE. AVATAR_BYTES=0 preserves model-only boot.
// Avatar-enabled boot seals only after its CRC and final B also retire. The shared
// AXI/HMIC bridge must verify writes before returning B. A model is sealed only
// after every complete segment CRC and every B retire; faults require a common
// system reset. No address from the serial wire reaches DDR without validation.
module triha_model_loader #(
 parameter PROGRAM_BYTES=`B03_PROGRAM_BYTES,PARAMETER_BYTES=`B03_PARAMETER_BYTES,
 parameter TABLE_BYTES=`B03_POST_TABLE_BYTES,HEADS_BYTES=`B03_HEADS_BYTES,
 parameter PROGRAM_CRC=`B03_PROGRAM_CRC32,PARAMETER_CRC=`B03_PARAMETER_CRC32,
 parameter TABLE_CRC=`B03_POST_TABLE_CRC32,HEADS_CRC=32'hed5ca9c5,
 parameter AVATAR_BYTES=0,AVATAR_CRC=32'd0,
 parameter RX_TIMEOUT_CYCLES=125000000
)(input wire clk_i,rst_ni,healthy_i,rx_valid_i,input wire[7:0] rx_data_i,input wire rx_error_i,
 output wire rx_ready_o,tx_valid_o,input wire tx_ready_i,output wire[7:0] tx_data_o,
 output reg model_sealed_o,fault_o,output wire m_awvalid_o,input wire m_awready_i,output reg[31:0] m_awaddr_o,
 output wire m_wvalid_o,input wire m_wready_i,output wire[127:0] m_wdata_o,output wire m_wlast_o,
 input wire m_bvalid_i,output wire m_bready_o,input wire[1:0] m_bresp_i);
 localparam SEARCH=0,HEADER=1,PAYLOAD=2,CHECK=3,AW=4,WRITE=5,RESP=6,TX=7;
 reg[2:0] state;
 reg[31:0] magic,packet_segment,packet_offset,packet_expected;
 reg[95:0] header;
 reg[3:0] header_index,tx_index;
 reg[7:0] byte_index,status;
 reg[2:0] segment;
 reg[31:0] offset,packet_crc,segment_crc,pending_crc,timeout_count;
 reg[31:0] last_segment,last_offset,last_crc;
 reg last_valid,started;
 wire buffer_valid,buffer_last;
 wire [127:0] buffer_data;
 function[31:0] crc_byte(input[31:0] c,input[7:0] b);
   integer n;reg[31:0] v;begin
     v=c^{24'd0,b};for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;
     crc_byte=v;
   end
 endfunction
 function[31:0] base(input[2:0] s);begin case(s)
   0:base=`B03_PROGRAM_BASE;
   1:base=`B03_WORKSPACE_BASE+`B03_PARAMETER_ORIGIN;
   2:base=`B03_POST_TABLE_BASE;
   3:base=`B03_OUTPUT_BASES_0+`B03_HEADS_OFFSET;
   4:base=`B03_OUTPUT_BASES_1+`B03_HEADS_OFFSET;
   5:base=`B03_OUTPUT_BASES_2+`B03_HEADS_OFFSET;
   default:base=`SOC_AVATAR_BASE;
 endcase end endfunction
 localparam [2:0] FINAL_SEGMENT=AVATAR_BYTES!=0?3'd6:3'd5;
 wire[31:0] segment_bytes=segment==0?PROGRAM_BYTES:segment==1?PARAMETER_BYTES:segment==2?TABLE_BYTES:segment==6?AVATAR_BYTES:HEADS_BYTES;
 wire[31:0] segment_expected=segment==0?PROGRAM_CRC:segment==1?PARAMETER_CRC:segment==2?TABLE_CRC:segment==6?AVATAR_CRC:HEADS_CRC;
 wire last_block=offset+32'd256==segment_bytes;
 wire duplicate=last_valid&&packet_segment==last_segment&&packet_offset==last_offset&&packet_expected==last_crc;
 assign rx_ready_o=(state==SEARCH||state==HEADER||state==PAYLOAD)&&healthy_i;
 assign tx_valid_o=state==TX;
 wire[95:0] reply={offset,16'd0,5'd0,segment,status,32'h31414854};
 assign tx_data_o=reply[tx_index*8+:8];
 assign m_awvalid_o=state==AW;
 assign m_wvalid_o=state==WRITE&&buffer_valid;
 assign m_wdata_o=buffer_data;
 assign m_wlast_o=buffer_last;
 assign m_bready_o=state==RESP;
 task answer(input[7:0] code);begin status<=code;tx_index<=0;state<=TX;magic<=0;end endtask
 // Only packet ingress writes RAM; packing begins after validated AW retires.
 // Buffer backpressure preserves AXI data/last through stalls and fault drain.
 triha_boot_buffer u_packet_buffer(
   .clk_i(clk_i),.rst_ni(rst_ni),
   .write_i(rx_valid_i&&rx_ready_o&&state==PAYLOAD),
   .write_address_i(byte_index),.write_data_i(rx_data_i),
   .start_i(m_awvalid_o&&m_awready_i),.busy_o(),.valid_o(buffer_valid),
   .ready_i(state==WRITE&&m_wready_i),.data_o(buffer_data),.last_o(buffer_last));
 always @(posedge clk_i or negedge rst_ni)begin
   if(!rst_ni)begin
     state<=SEARCH;magic<=0;header<=0;header_index<=0;tx_index<=0;byte_index<=0;status<=0;
     segment<=0;offset<=0;packet_crc<=32'hffffffff;segment_crc<=32'hffffffff;pending_crc<=32'hffffffff;
     packet_segment<=0;packet_offset<=0;packet_expected<=0;timeout_count<=0;
     last_segment<=0;last_offset<=0;last_crc<=0;last_valid<=0;started<=0;
     model_sealed_o<=0;fault_o<=0;m_awaddr_o<=0;
   end else begin
     if(started&&!healthy_i)begin fault_o<=1;model_sealed_o<=0;end
     if(state==HEADER||state==PAYLOAD)begin
       if(rx_valid_i&&rx_ready_o)timeout_count<=0;else timeout_count<=timeout_count+1;
     end else timeout_count<=0;
     case(state)
       SEARCH:if(rx_valid_i&&rx_ready_o)begin
         magic<={rx_data_i,magic[31:8]};
         if({rx_data_i,magic[31:8]}==32'h31424854)begin
           state<=HEADER;header_index<=0;header<=0;started<=1;
         end
       end
       HEADER:if(rx_valid_i&&rx_ready_o)begin
         header[header_index*8+:8]<=rx_data_i;
         if(header_index==11)begin
           packet_segment<=header[31:0];packet_offset<=header[63:32];packet_expected<={rx_data_i,header[87:64]};
           state<=PAYLOAD;byte_index<=0;packet_crc<=32'hffffffff;pending_crc<=segment_crc;
         end else header_index<=header_index+1'b1;
       end
       PAYLOAD:if(rx_valid_i&&rx_ready_o)begin
         packet_crc<=crc_byte(packet_crc,rx_data_i);pending_crc<=crc_byte(pending_crc,rx_data_i);
         if(byte_index==255)state<=CHECK;else byte_index<=byte_index+1'b1;
       end
       CHECK:begin
         if(fault_o||!healthy_i)answer(4);
         else if((~packet_crc)!=packet_expected)answer(1);
         else if(duplicate)answer(0);
         else if(model_sealed_o)answer(5);
         else if(packet_segment!={29'd0,segment}||packet_offset!=offset||offset>=segment_bytes||offset[7:0]!=0)answer(2);
         else if(last_block&&(~pending_crc)!=segment_expected)answer(3);
         else begin m_awaddr_o<=base(segment)+offset;state<=AW;end
       end
       AW:if(m_awready_i)state<=WRITE;
       WRITE:if(m_wvalid_o&&m_wready_i&&buffer_last)state<=RESP;
       RESP:if(m_bvalid_i)begin
         if(m_bresp_i!=0||fault_o||!healthy_i)begin fault_o<=1;model_sealed_o<=0;answer(4);end
         else begin
           last_valid<=1;last_segment<=packet_segment;last_offset<=packet_offset;last_crc<=packet_expected;
           if(last_block)begin
             offset<=0;segment<=segment+1'b1;segment_crc<=32'hffffffff;
             if(segment==FINAL_SEGMENT)model_sealed_o<=1;
           end else begin offset<=offset+32'd256;segment_crc<=pending_crc;end
           answer(0);
         end
       end
       TX:if(tx_ready_i)begin if(tx_index==11)state<=SEARCH;else tx_index<=tx_index+1'b1;end
       default:begin fault_o<=1;model_sealed_o<=0;state<=SEARCH;end
     endcase
     // Byte framing/timeout never cancels an offered AXI transaction. Its B
     // still retires in RESP; only pre-write parsing may be discarded here.
     if((state==HEADER||state==PAYLOAD)&&(rx_error_i||timeout_count==RX_TIMEOUT_CYCLES-1))answer(6);
     if(rx_error_i&&(state==AW||state==WRITE||state==RESP))begin fault_o<=1;model_sealed_o<=0;end
   end
 end
endmodule
`default_nettype wire
