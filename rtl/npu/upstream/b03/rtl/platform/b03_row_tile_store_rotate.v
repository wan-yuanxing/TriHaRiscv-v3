// Swizzled O tile -> contiguous NCHW rows. One 256-bit W skid only.
// O's request/response pipeline advances with o_run_ce; ordinary W retirement
// does not depend on compute CE. The block service owns all accepted debt.
module b03_row_tile_store_rotate(
 input wire clk,rst_n,run_ce,cancel_request,
 input wire start_valid,output wire start_ready,
 input wire [31:0] dst_base,plane_bytes,row_bytes,row_words,
 input wire [6:0] co_count,input wire [8:0] row_y,tile_rows,tile_capacity,input wire [31:0] tag,
 output reg done_valid,input wire done_ready,output reg [31:0] done_status,done_detail,done_tag,
 output wire o_run_ce,output reg [3:0] o_req_a,o_req_b,output reg [43:0] o_addr_a,o_addr_b,
 input wire [127:0] o_q_a,o_q_b,input wire [3:0] o_valid_a,o_valid_b,
 output wire mem_req_valid,input wire mem_req_ready,output wire mem_req_write,mem_req_verify,
 output wire [31:0] mem_req_offset,mem_req_tag,output wire [4:0] mem_req_beats,output wire [2:0] mem_req_client,
 output wire mem_w_valid,input wire mem_w_ready,output wire [255:0] mem_w_data,
 output wire [31:0] mem_w_strb,output wire mem_w_last,
 input wire mem_r_valid,output wire mem_r_ready,input wire [255:0] mem_r_data,input wire mem_r_last,
 input wire mem_rsp_valid,output wire mem_rsp_ready,input wire [3:0] mem_rsp_status,input wire [31:0] mem_rsp_tag,
 output wire [7:0] debug_state,output reg [31:0] bursts,stored_bytes
);
 localparam IDLE=0,CHECK=1,PLAN=2,OFFER=3,STREAM=4,WAIT=5,HELD=6;
 reg [7:0] state;reg active,aborting,offer,inflight,issue_done;
 reg [31:0] base,plane,saved_tag,channel_base,burst_base,burst_tag,sequence_tag;
 reg [12:0] rbytes,cursor;reg [10:0] pwords;reg [9:0] burst_bytes;
 reg bounds_ok;
 wire [18:0] start_cap_bytes=mul9n(row_bytes[9:0],tile_capacity);
 wire [18:0] start_actual_bytes=mul9n(row_bytes[9:0],tile_rows);
 wire [18:0] start_row_offset=mul9n(row_bytes[9:0],row_y);
 reg [6:0] channels,channel;reg [4:0] beats,sent,issue_beat;
 reg [5:0] prefix;reg [10:0] issue_word,issue_end;reg issue_first;
 reg [1:0] vp,fp,lp;reg [10:0] wp0,wp1;reg [3:0] np0,np1;reg [4:0] bp0,bp1;
 reg skid_valid,skid_last;reg [255:0] skid_data;reg [31:0] skid_mask;
 wire [31:0] physical=channel_base+cursor;
 wire [9:0] capacity=physical[11:5]>112?(13'd4096-{1'b0,physical[11:0]}):(10'd512-{5'd0,physical[4:0]});
 wire [12:0] remaining=rbytes-cursor;
 wire [9:0] valid_bytes=remaining<capacity?remaining[9:0]:capacity;
 wire [10:0] channel_word_base=mul4(pwords,channel[5:2]);
 wire [10:0] words_left=issue_end-issue_word;
 wire [3:0] issue_count=words_left>8?8:words_left[3:0];
 wire issue=state==STREAM&&!issue_done&&issue_count!=0;
 assign o_run_ce=rst_n&&run_ce&&state==STREAM&&(!skid_valid||mem_w_ready);
 assign start_ready=rst_n&&state==IDLE&&!done_valid&&!cancel_request;
 assign mem_req_valid=rst_n&&offer;assign mem_req_write=1;assign mem_req_verify=1;
 assign mem_req_offset=burst_base;assign mem_req_tag=burst_tag;assign mem_req_beats=beats;assign mem_req_client=3;
 assign mem_w_valid=rst_n&&inflight&&skid_valid;assign mem_w_data=skid_data;assign mem_w_strb=skid_mask;assign mem_w_last=skid_last;
 assign mem_r_ready=rst_n&&inflight;assign mem_rsp_ready=rst_n&&inflight;assign debug_state=state;
 function [18:0] mul9n;input [9:0] a;input [8:0] b;
 begin mul9n=a*b;end endfunction
 function [15:0] mul5n;input [10:0] a;input [4:0] b;
 begin mul5n=a*b;end endfunction
 function [12:0] beat_lo;input [5:0] n;
 begin beat_lo=n==0?cursor:cursor+(n<<5)-prefix;end endfunction
 function [12:0] beat_hi;input [5:0] n;reg [12:0] last;
 begin last=cursor+((n+1)<<5)-prefix;beat_hi=last>cursor+burst_bytes?cursor+burst_bytes:last;end endfunction
 task finish;input [31:0] s,d;
 begin done_valid<=1;done_status<=s;done_detail<=d;done_tag<=saved_tag;active<=0;state<=HELD;end endtask
 function [10:0] mul4;input [10:0] a;input [3:0] n;
 begin mul4=a*n;end endfunction
 integer l,bank,j;reg [1:0] rel_a;reg [2:0] rel_b;
 reg [255:0] returned,aligned_return;reg response_bad;
 reg signed [14:0] shift_wide,payload_end;
 reg signed [7:0] shift_bytes,segment_end;
 reg [4:0] rotate_right_bytes;
 reg [5:0] mask_low,mask_high,beat_start,beat_end;
 reg [31:0] response_mask;
 always @*begin
  o_req_a=0;o_req_b=0;o_addr_a=0;o_addr_b=0;rel_a=0;rel_b=0;
  if(issue&&o_run_ce)for(bank=0;bank<4;bank=bank+1)begin
   rel_a=bank[1:0]-channel[1:0]-issue_word[1:0];rel_b={1'b1,rel_a};
   o_req_a[bank]={2'd0,rel_a}<issue_count;o_req_b[bank]={1'b0,rel_b}<issue_count;
   o_addr_a[11*bank+:11]=channel_word_base+issue_word+{9'd0,rel_a};
   o_addr_b[11*bank+:11]=channel_word_base+issue_word+{8'd0,rel_b};
  end
  returned=0;response_bad=0;
  for(l=0;l<8;l=l+1)if(l<np1)begin
   bank=(channel[1:0]+wp1[1:0]+l)&3;
   if(l<4)begin returned[32*l+:32]=o_q_a[32*bank+:32];if(!o_valid_a[bank])response_bad=1;end
   else begin returned[32*l+:32]=o_q_b[32*bank+:32];if(!o_valid_b[bank])response_bad=1;end
  end
  // One bounded coordinate calculation per returned fragment, never one
  // 33-bit subtract/compare for every one of the 32 byte lanes.
  shift_wide=$signed({2'd0,wp1,2'b00})+$signed({9'd0,prefix})-
              $signed({2'd0,cursor})-$signed({5'd0,bp1,5'd0});
  shift_bytes=shift_wide[7:0];
  segment_end=shift_bytes+$signed({2'd0,np1,2'b00});
  payload_end=$signed({9'd0,prefix})+$signed({5'd0,burst_bytes})-$signed({5'd0,bp1,5'd0});
  beat_start=bp1==0?prefix:6'd0;
  beat_end=payload_end>32?6'd32:payload_end<0?6'd0:payload_end[5:0];
  mask_low=shift_bytes<0?beat_start:(shift_bytes>{2'd0,beat_start}?shift_bytes[5:0]:beat_start);
  mask_high=segment_end<0?6'd0:(segment_end<{2'd0,beat_end}?segment_end[5:0]:beat_end);
  // One byte rotate, then exact zero fill. The original negative amount
  // is eight bits wide; its <<3 retains five low byte-index bits.
  rotate_right_bytes=5'd0-shift_bytes[4:0];
  aligned_return={returned,returned}>>{rotate_right_bytes,3'b000};
  for(j=0;j<32;j=j+1)begin
   if(shift_bytes<0)begin
    if(j>=6'd32-{1'b0,rotate_right_bytes})aligned_return[8*j+:8]=0;
   end else if(shift_bytes>=32||j<shift_bytes)aligned_return[8*j+:8]=0;
  end
  response_mask=0;
  for(j=0;j<32;j=j+1)if(j>=mask_low&&j<mask_high)response_mask[j]=1;
 end

 integer b;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  state<=IDLE;active<=0;aborting<=0;offer<=0;inflight<=0;issue_done<=0;done_valid<=0;done_status<=0;done_detail<=0;done_tag<=0;
  base<=0;plane<=0;rbytes<=0;pwords<=0;saved_tag<=0;channel_base<=0;cursor<=0;burst_base<=0;burst_bytes<=0;burst_tag<=0;sequence_tag<=0;
  bounds_ok<=0;channels<=0;channel<=0;beats<=0;sent<=0;issue_beat<=0;prefix<=0;issue_word<=0;issue_end<=0;issue_first<=0;
  vp<=0;fp<=0;lp<=0;wp0<=0;wp1<=0;np0<=0;np1<=0;bp0<=0;bp1<=0;
  skid_valid<=0;skid_last<=0;skid_data<=0;skid_mask<=0;bursts<=0;stored_bytes<=0;
 end else begin
  if(done_valid&&done_ready)begin done_valid<=0;state<=IDLE;end
  if(start_valid&&start_ready)begin
   base<=dst_base;plane<=plane_bytes;rbytes<=start_actual_bytes[12:0];
   bounds_ok<=row_bytes[31:10]==0&&start_cap_bytes<=4096&&start_actual_bytes<=4096;
   pwords<=(start_cap_bytes+3)>>2;saved_tag<=tag;
   channel_base<=dst_base+{13'd0,start_row_offset};cursor<=0;channels<=co_count;channel<=0;
   active<=1;aborting<=0;vp<=0;skid_valid<=0;state<=CHECK;
  end
  if(mem_w_valid&&mem_w_ready)begin skid_valid<=0;sent<=sent+1;if(sent+1==beats)state<=WAIT;end
  if(o_run_ce)begin
   vp<={vp[0],issue};fp<={fp[0],issue_first};lp<={lp[0],issue_word+issue_count>=issue_end};
   wp0<=issue_word;wp1<=wp0;np0<=issue_count;np1<=np0;bp0<=issue_beat;bp1<=bp0;
   if(issue)begin
    if(issue_word+issue_count>=issue_end)begin
     if(issue_beat+1==beats)issue_done<=1;
     else begin issue_beat<=issue_beat+1;issue_word<=beat_lo({1'd0,issue_beat}+1)>>2;
      issue_end<=(beat_hi({1'd0,issue_beat}+1)+3)>>2;issue_first<=1;end
    end else begin issue_word<=issue_word+8;issue_first<=0;end
   end
   if(vp[1])begin
    if(response_bad)begin aborting<=1;finish(22,32'h4f545253);end
    else begin
     if(fp[1])begin skid_data<=aligned_return;skid_mask<=response_mask;end
     else begin
      for(b=0;b<32;b=b+1)if(response_mask[b])skid_data[8*b+:8]<=aligned_return[8*b+:8];
      skid_mask<=skid_mask|response_mask;
     end
     if(lp[1])begin skid_valid<=1;skid_last<=bp1+1==beats;end
    end
   end
  end
  if(active&&!aborting&&!cancel_request)case(state)
   CHECK:if(!bounds_ok||channels==0||channels>64||row_bytes==0||row_bytes>640||row_words!=((row_bytes+3)>>2)||
       tile_rows==0||tile_rows>tile_capacity||tile_capacity>320||mul5n(pwords,({1'b0,channels}+8'd3)>>2)>1024)
       finish(11,32'h4f54424e);else state<=PLAN;
   PLAN:if(sequence_tag==32'hffffffff)finish(22,32'h4f545447);else begin
    burst_base<=physical&32'hffffffe0;prefix<={1'b0,physical[4:0]};burst_bytes<=valid_bytes;
    beats<=(valid_bytes+{27'd0,physical[4:0]}+31)>>5;burst_tag<=sequence_tag+1;sequence_tag<=sequence_tag+1;
    offer<=1;state<=OFFER;
   end
   default:begin end
  endcase
  if(mem_req_valid&&mem_req_ready)begin
   offer<=0;inflight<=1;sent<=0;issue_beat<=0;issue_word<=cursor>>2;
   issue_end<=(beat_hi(0)+3)>>2;issue_first<=1;issue_done<=0;vp<=0;skid_valid<=0;state<=STREAM;bursts<=bursts+1;
  end
  if(mem_rsp_valid&&mem_rsp_ready)begin
   inflight<=0;
   if(mem_rsp_tag!=burst_tag||mem_rsp_status!=0||sent!=beats)finish(18,32'h4f545250);
   else if(aborting||cancel_request)finish(17,0);
   else begin
    stored_bytes<=stored_bytes+burst_bytes;
    if(cursor+burst_bytes==rbytes)begin
     if(channel+1==channels)finish(0,0);
     else begin channel<=channel+1;channel_base<=channel_base+plane;cursor<=0;state<=PLAN;end
    end else begin cursor<=cursor+burst_bytes;state<=PLAN;end
   end
  end
  if(mem_r_valid&&mem_r_ready)begin aborting<=1;finish(18,32'h4f545252);end
  if(active&&cancel_request)begin aborting<=1;if(!offer&&!inflight)finish(17,0);end
 end
 end
endmodule
