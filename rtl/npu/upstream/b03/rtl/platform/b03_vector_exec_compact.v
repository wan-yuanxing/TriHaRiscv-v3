// Compact general vector path: eight byte-interleaved physical TDP banks.
// A/B/O each use sixteen rows per bank. R staging writes 8 bytes/CE; Q reads
// fixed banks. No multi-writer FF byte arrays and no additional APMs.
module b03_vector_exec_compact(
 input wire clk,rst_n,run_ce,cancel_request,
 input wire start_valid,output wire start_ready,input wire [1023:0] op_words,
 input wire [31:0] workspace_base,src0_base,src1_base,dst_base,epoch,tag,
 output reg done_valid,input wire done_ready,
 output reg [31:0] done_status,done_detail,done_tag,done_op_id,output reg [63:0] cycles,
 output wire busy,output wire [7:0] debug_stage,
 output wire mem_req_valid,input wire mem_req_ready,output wire mem_req_write,mem_req_verify,
 output wire [31:0] mem_req_offset,mem_req_tag,output wire [4:0] mem_req_beats,output wire [2:0] mem_req_client,
 output wire mem_w_valid,input wire mem_w_ready,output wire [255:0] mem_w_data,
 output reg [31:0] mem_w_strb,output wire mem_w_last,
 input wire mem_r_valid,output wire mem_r_ready,input wire [255:0] mem_r_data,input wire mem_r_last,
 input wire mem_rsp_valid,output wire mem_rsp_ready,input wire [3:0] mem_rsp_status,input wire [31:0] mem_rsp_tag,
 output wire q_in_valid,input wire q_in_ready,output reg [7:0] q_in_mask,
 output reg [255:0] q_in_psum,q_in_psum_b,output wire [255:0] q_in_bias,q_in_multiplier,q_in_multiplier_b,
 output wire q_in_add,output wire [1:0] q_in_dtype,output wire [47:0] q_in_shift,output wire [127:0] q_in_tag,
 input wire q_out_valid,output wire q_out_ready,input wire [7:0] q_out_mask,
 input wire [127:0] q_out_values,input wire [23:0] q_out_error,input wire [127:0] q_out_tag
);
 localparam IDLE=0,CHECK=1,AUX=2,AUXRQ=3,AUXCAP=4,AUXCHECK=5,LUTLOAD=6,LUTRQ=7,LUTCAP=8,
 NEXT=9,READA=10,READB=11,QPREP=12,QCAP=13,QISSUE=14,QWAIT=15,SLREQ=16,SLWAIT=17,
 TREAD=18,TCRQ=19,TCCAP=20,WRITE=21,ADVANCE=22,HELD=23,
 IOREQ=24,IOWINIT=25,IOWRQ=26,IOWCAP=27,IOW=28,IOR=29,IORCOPY=30,IORSP=31,IOCHECK=32;
 reg [7:0] state,return_state;
 reg active,cancel_pending,aux_phase;
 reg [1023:0] op;
 reg [31:0] workspace,src0,src1,dst,saved_epoch,saved_tag,cursor,plane;
 reg [7:0] chunk,group_pos;
 // Prepared in existing states; no additional memory or arithmetic cycles.
 reg final_chunk;reg [31:0] quant_position;
 reg [2:0] channel,quant_lane;
 reg [4:0] point;
 reg [31:0] multiplier,multiplier_b,shift_amount;
 reg [127:0] quant_values;
 reg [13:0] lut_index;
 reg cache_valid;reg [31:0] cache_epoch,cache_address;reg [15:0] cache_last;
 reg [14:0] lut_cursor;reg [1:0] lut_pair;
 reg [31:0] io_address,io_tag,next_tag,io_error;
 reg [7:0] io_remaining,io_position;
 reg [5:0] io_copy_pos;
 reg io_write;reg [1:0] io_target;
 reg [255:0] read_skid,write_packed;
 wire [31:0] code=op[0+:32],sdt=op[160+:32],bdt=op[192+:32],ddt=op[224+:32];
 wire [31:0] channels=op[256+:32],total=op[768+:32],out_total=op[832+:32],opid=op[928+:32];
 wire wide_element=sdt==3||sdt==4;
 wire [31:0] plane_bytes=wide_element?(plane<<1):plane;
 // Resolve chunk and channel offsets in parallel before the final address add.
 // All arithmetic remains modulo 2^32; no state or transfer cycle is added.
 (* syn_keep=1 *) wire [31:0] transpose_chunk_base=src0+(wide_element?(cursor<<1):cursor);
 (* syn_keep=1 *) wire [31:0] transpose_plane_three=plane_bytes+(plane_bytes<<1);
 (* syn_keep=1 *) wire [31:0] transpose_channel_offset=channel==0?32'd0:channel==1?plane_bytes:
  channel==2?(plane_bytes<<1):transpose_plane_three;
 wire [31:0] t_cursor_bytes=channels==4?(wide_element?(cursor<<3):(cursor<<2)):(wide_element?(cursor<<1):cursor);
 wire [7:0] t_chunk_bytes=channels==4?(wide_element?(chunk<<3):(chunk<<2)):(wide_element?(chunk<<1):chunk);
 wire [7:0] t_point_byte=wide_element?({3'd0,point}<<1):{3'd0,point};
 wire [7:0] t_out_element=(channels==4?({3'd0,point}<<2):{3'd0,point})+{5'd0,channel};
 wire [7:0] t_out_byte=wide_element?(t_out_element<<1):t_out_element;
 wire [7:0] s_out_byte=(group_pos+{5'd0,quant_lane})<<1;
 wire [5:0] io_lane={1'b0,io_address[4:0]};
 wire [5:0] io_count=io_remaining<(32-io_lane)?io_remaining[5:0]:(32-io_lane);
 wire [5:0] io_copy_left=io_count-io_copy_pos;
 wire [3:0] io_take=io_copy_left>8?4'd8:io_copy_left[3:0];
 wire [7:0] buf_linear=io_position+{2'd0,io_copy_pos};
 wire [2:0] first_bank=buf_linear[2:0];
 wire [2:0] r_rotate=3'd0-first_bank;
 wire [127:0] r_rotated={read_skid[63:0],read_skid[63:0]}>>{r_rotate,3'b0};
 wire memory_active=state>=IOREQ&&state<=IORSP;
 assign busy=active||done_valid;assign debug_stage=state;
 assign start_ready=rst_n&&state==IDLE&&!done_valid&&!cancel_request;
 assign mem_req_valid=state==IOREQ;assign mem_req_write=io_write;assign mem_req_verify=io_write;
 assign mem_req_offset={io_address[31:5],5'd0};assign mem_req_tag=io_tag;
 assign mem_req_beats=1;assign mem_req_client=4;
 assign mem_w_valid=state==IOW;assign mem_w_last=1;
 assign mem_w_data=write_packed<<{io_address[4:0],3'b0};
 assign mem_r_ready=state==IOR;assign mem_rsp_ready=state==IORSP;
 assign q_in_valid=state==QISSUE;assign q_out_ready=state==QWAIT;
 assign q_in_add=code==3;assign q_in_dtype=code==8?2'd2:ddt[1:0]-1'b1;
 assign q_in_bias=0;assign q_in_multiplier={8{multiplier}};assign q_in_multiplier_b={8{multiplier_b}};
 assign q_in_shift={8{shift_amount[5:0]}};
 assign q_in_tag={saved_tag,saved_epoch,opid,quant_position};
 wire q_good=q_out_tag==q_in_tag&&q_out_mask==q_in_mask&&q_out_error==0;

 reg [7:0] br_a,bw_a,br_b,bw_b;
 reg [87:0] ba_a,ba_b;reg [127:0] bd_a,bd_b;reg [15:0] bm_a,bm_b;
 wire [127:0] bq_a,bq_b;wire [7:0] bv_a,bv_b;wire buffer_busy,buffer_conflict,buffer_range;
 wire [63:0] bytes_a,bytes_b;
 genvar b;
 generate for(b=0;b<8;b=b+1)begin:buffer_lane
  assign bytes_a[8*b+:8]=bq_a[16*b+:8];assign bytes_b[8*b+:8]=bq_b[16*b+:8];
 end endgenerate
 b03_bank_array #(.BANKS(8),.WIDTH(16),.DEPTH(1024)) buffers(
  .clk(clk),.rst_n(rst_n),.run_ce(run_ce),.req_a(br_a),.we_a(bw_a),.req_b(br_b),.we_b(bw_b),
  .addr_a(ba_a),.addr_b(ba_b),.data_a(bd_a),.data_b(bd_b),.mask_a(bm_a),.mask_b(bm_b),
  .q_a(bq_a),.q_b(bq_b),.valid_a(bv_a),.valid_b(bv_b),.busy(buffer_busy),.conflict(buffer_conflict),.range_error(buffer_range));
 wire [127:0] b_rotated={bytes_b,bytes_b}>>{first_bank,3'b0};
 wire [63:0] t_shifted=bytes_b>>{t_point_byte[2:0],3'b0};
 wire lut_write=state==LUTCAP&&lut_cursor<16384&&bv_b==8'hff;
 wire [14:0] lut_write_offset=lut_cursor+{10'd0,lut_pair,3'b0};
 wire lut_read=state==SLREQ&&lut_index<8192;
 wire [31:0] lq0,lq1;wire lv0,lv1;
 generate for(b=0;b<2;b=b+1)begin:lut_bank
  wire wr=lut_write&&lut_write_offset[13]==b;
  wire rd=lut_read&&lut_index[12]==b;
  wire [31:0] q;wire valid;
  b03_tdp2048_loan_bank ram(.clk(clk),.rst_n(rst_n),.run_ce(run_ce),
   .req_a(wr||rd),.we_a(wr),.addr_a(wr?lut_write_offset[12:2]:lut_index[11:1]),.data_a(bytes_b[31:0]),.mask_a(4'hf),
   .req_b(wr),.we_b(wr),.addr_b(lut_write_offset[12:2]+11'd1),.data_b(bytes_b[63:32]),.mask_b(4'hf),
   .q_a(q),.q_b(),.valid_a(valid),.valid_b(),.conflict(),.busy());
  if(b==0)begin assign lq0=q;assign lv0=valid;end
  else begin assign lq1=q;assign lv1=valid;end
 end endgenerate
 wire [31:0] lword=lut_index[12]?lq1:lq0;
 wire [15:0] lut_value=lut_index==8192?cache_last:(lut_index[0]?lword[31:16]:lword[15:0]);
 wire sigmoid_store=(state==SLREQ&&lut_index==8192)||(state==SLWAIT&&(lut_index[12]?lv1:lv0));
 integer i;reg [2:0] delta;reg [7:0] logical_index;
 always @*begin
  br_a=0;bw_a=0;br_b=0;bw_b=0;ba_a=0;ba_b=0;bd_a=0;bd_b=0;bm_a=0;bm_b=0;
  delta=0;logical_index=0;
  for(i=0;i<8;i=i+1)begin
   if(state==QPREP)begin
    br_a[i]=1;ba_a[11*i+:11]={7'd0,group_pos[6:3]};
    if(code==3)begin br_b[i]=1;ba_b[11*i+:11]={6'd0,1'b1,group_pos[6:3]};end
   end
   if(state==AUXRQ||state==LUTRQ||state==TCRQ)begin
    br_b[i]=1;
    if(state==AUXRQ)ba_b[11*i+:11]={10'd0,aux_phase};
    else if(state==LUTRQ)ba_b[11*i+:11]={9'd0,lut_pair};
    else ba_b[11*i+:11]={7'd0,t_point_byte[6:3]};
   end
   if(state==IOWRQ||state==IORCOPY)begin
    delta=i-first_bank;logical_index=buf_linear+{5'd0,delta};
    if(state==IOWRQ)begin br_b[i]=1;ba_b[11*i+:11]={5'd0,2'd2,logical_index[6:3]};end
    else if({1'b0,delta}<io_take)begin
     br_a[i]=1;bw_a[i]=1;ba_a[11*i+:11]={5'd0,io_target,logical_index[6:3]};
     bm_a[2*i+:2]=1;bd_a[16*i+:8]=r_rotated[8*i+:8];
    end
   end
   if(state==QWAIT&&q_out_valid&&q_good&&code==3&&q_in_mask[i])begin
    br_a[i]=1;bw_a[i]=1;ba_a[11*i+:11]={5'd0,2'd2,group_pos[6:3]};
    bm_a[2*i+:2]=1;bd_a[16*i+:8]=q_out_values[16*i+:8];
   end
   if(sigmoid_store)begin
    if(i==s_out_byte[2:0]||i==s_out_byte[2:0]+1)begin
     br_a[i]=1;bw_a[i]=1;ba_a[11*i+:11]={5'd0,2'd2,s_out_byte[6:3]};
     bm_a[2*i+:2]=1;bd_a[16*i+:8]=i==s_out_byte[2:0]?lut_value[7:0]:lut_value[15:8];
    end
   end
   if(state==TCCAP&&bv_b==8'hff)begin
    if(i==t_out_byte[2:0]||(wide_element&&i==t_out_byte[2:0]+1))begin
     br_a[i]=1;bw_a[i]=1;ba_a[11*i+:11]={5'd0,2'd2,t_out_byte[6:3]};
     bm_a[2*i+:2]=1;bd_a[16*i+:8]=i==t_out_byte[2:0]?t_shifted[7:0]:t_shifted[15:8];
    end
   end
  end
  mem_w_strb=0;
  for(i=0;i<32;i=i+1)if(i>=io_lane&&i<io_lane+io_count)mem_w_strb[i]=1;
 end
 function [13:0] index_value;input [15:0] v;begin
  if($signed(v)<-4096)index_value=0;else if($signed(v)>4096)index_value=8192;else index_value=$signed(v)+4096;
 end endfunction
 task finish;input [31:0] status,detail;begin
  done_valid<=1;done_status<=status;done_detail<=detail;done_tag<=saved_tag;done_op_id<=opid;
  active<=0;state<=HELD;
 end endtask
 task transfer;input wr;input [31:0] address;input [7:0] count;input [1:0] target;input [7:0] resume;begin
  // Separate multi-add address generation from range checking and completion.
  // No request or tag consumption occurs until the registered check succeeds.
  io_write<=wr;io_address<=address;io_remaining<=count;io_position<=0;io_target<=target;
  io_error<=0;io_tag<=next_tag;return_state<=resume;state<=IOCHECK;
 end endtask
 task next_sigmoid;begin
  if(quant_lane==7||{1'b0,group_pos}+quant_lane+1=={1'b0,chunk})begin
   if({1'b0,group_pos}+9'd8>={1'b0,chunk})state<=WRITE;
   else begin group_pos<=group_pos+8;state<=QPREP;end
  end else begin quant_lane<=quant_lane+1;lut_index<=index_value(quant_values[16*(quant_lane+1)+:16]);state<=SLREQ;end
 end endtask
 integer n;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;return_state<=IDLE;active<=0;cancel_pending<=0;aux_phase<=0;op<=0;
   workspace<=0;src0<=0;src1<=0;dst<=0;saved_epoch<=0;saved_tag<=0;cursor<=0;plane<=0;
   chunk<=0;group_pos<=0;final_chunk<=0;quant_position<=0;channel<=0;quant_lane<=0;point<=0;
   multiplier<=0;multiplier_b<=0;shift_amount<=0;quant_values<=0;lut_index<=0;
   cache_valid<=0;cache_epoch<=0;cache_address<=0;cache_last<=0;lut_cursor<=0;lut_pair<=0;
   io_address<=0;io_tag<=0;next_tag<=1;io_error<=0;io_remaining<=0;io_position<=0;io_copy_pos<=0;io_write<=0;io_target<=0;
   read_skid<=0;write_packed<=0;q_in_mask<=0;q_in_psum<=0;q_in_psum_b<=0;
   done_valid<=0;done_status<=0;done_detail<=0;done_tag<=0;done_op_id<=0;cycles<=0;
  end else begin
   if(active)cycles<=cycles+1;
   if(active&&cancel_request)cancel_pending<=1;
   case(state)
   IDLE:if(start_valid&&start_ready)begin
    op<=op_words;workspace<=workspace_base;src0<=src0_base;src1<=src1_base;dst<=dst_base;saved_epoch<=epoch;saved_tag<=tag;
    active<=1;cancel_pending<=0;cycles<=0;cursor<=0;state<=CHECK;
   end
   CHECK:if(run_ce)begin
    if((code!=3&&code!=6&&code!=7&&code!=8)||total==0||total>409600||out_total==0||out_total>819200)finish(21,32'h434f5043);
    else if((code==3&&(sdt!=1||bdt!=1||ddt!=1||total!=op[800+:32]||total!=out_total))||
       ((code==6||code==7)&&(sdt!=ddt||total!=out_total))||
       (code==6&&(sdt==0||sdt>4||(channels!=1&&channels!=4)||op[960+:32]!=32'h01030200))||
       (code==8&&(sdt!=2||ddt!=4||out_total!=(total<<1))))finish(11,32'h43445459);
    else if(code==3||code==8)state<=AUX;
    else begin plane<=channels==4?(wide_element?(total>>3):(total>>2)):(wide_element?(total>>1):total);state<=NEXT;end
   end
   AUX:if(run_ce)begin aux_phase<=0;transfer(0,workspace+op[704+:32],code==3?8'd12:8'd8,0,AUXRQ);end
   AUXRQ:if(run_ce)state<=AUXCAP;
   AUXCAP:if(run_ce)begin
    if(bv_b!=8'hff)finish(22,32'h43415241);
    else if(!aux_phase)begin
     multiplier<=bytes_b[31:0];multiplier_b<=code==3?bytes_b[63:32]:0;
     if(code==3)begin aux_phase<=1;state<=AUXRQ;end else begin shift_amount<=bytes_b[63:32];state<=AUXCHECK;end
    end else begin shift_amount<=bytes_b[31:0];state<=AUXCHECK;end
   end
   AUXCHECK:if(run_ce)begin
    if(multiplier==0||multiplier[31]||shift_amount==0||shift_amount>62||(code==3&&(multiplier_b==0||multiplier_b[31])))finish(11,32'h43415558);
    else if(code==8&&!(cache_valid&&cache_epoch==saved_epoch&&cache_address==workspace+op[736+:32]))begin
     cache_valid<=0;lut_cursor<=0;state<=LUTLOAD;
    end else state<=NEXT;
   end
   LUTLOAD:if(run_ce)begin lut_pair<=0;transfer(0,workspace+op[736+:32]+{17'd0,lut_cursor},lut_cursor==16384?8'd2:8'd32,0,LUTRQ);end
   LUTRQ:if(run_ce)state<=LUTCAP;
   LUTCAP:if(run_ce)begin
    if(bv_b!=8'hff)finish(22,32'h434c5241);
    else if(lut_cursor==16384)begin
     cache_last<=bytes_b[15:0];cache_valid<=1;cache_epoch<=saved_epoch;cache_address<=workspace+op[736+:32];state<=NEXT;
    end else if(lut_pair==3)begin lut_cursor<=lut_cursor+32;state<=LUTLOAD;end else begin lut_pair<=lut_pair+1;state<=LUTRQ;end
   end
   NEXT:if(run_ce)begin
    group_pos<=0;
    final_chunk<=code==6?(plane-cursor<=32'd16):(total-cursor<=(code==8?32'd64:32'd128));
    if(code==6)begin chunk<=plane-cursor>16?8'd16:plane-cursor;channel<=0;state<=TREAD;end
    else begin chunk<=total-cursor>(code==8?64:128)?(code==8?8'd64:8'd128):total-cursor;state<=READA;end
   end
   READA:if(run_ce)transfer(0,src0+cursor,chunk,code==7?2'd2:2'd0,code==3?READB:code==8?QPREP:WRITE);
   READB:if(run_ce)transfer(0,src1+cursor,chunk,1,QPREP);
   QPREP:if(run_ce)begin quant_position<=cursor+{24'd0,group_pos};state<=QCAP;end
   QCAP:if(run_ce)begin
    if(bv_a!=8'hff||(code==3&&bv_b!=8'hff))finish(22,32'h43515241);
    else begin
     for(n=0;n<8;n=n+1)begin
      q_in_mask[n]<={1'b0,group_pos}+n<{1'b0,chunk};
      q_in_psum[32*n+:32]<=({1'b0,group_pos}+n<{1'b0,chunk})?(sdt==2?{{24{bytes_a[8*n+7]}},bytes_a[8*n+:8]}:{24'd0,bytes_a[8*n+:8]}):32'd0;
      q_in_psum_b[32*n+:32]<=code==3&&({1'b0,group_pos}+n<{1'b0,chunk})?{24'd0,bytes_b[8*n+:8]}:32'd0;
     end
     state<=QISSUE;
    end
   end
   QISSUE:if(run_ce&&q_in_ready)state<=QWAIT;
   QWAIT:if(run_ce&&q_out_valid)begin
    if(!q_good)finish(22,32'h43515253);
    else if(code==3)begin
     if({1'b0,group_pos}+9'd8>={1'b0,chunk})state<=WRITE;else begin group_pos<=group_pos+8;state<=QPREP;end
    end else begin quant_values<=q_out_values;quant_lane<=0;lut_index<=index_value(q_out_values[15:0]);state<=SLREQ;end
   end
   SLREQ:if(run_ce)begin if(lut_index==8192)next_sigmoid();else state<=SLWAIT;end
   SLWAIT:if(run_ce)begin if(!(lut_index[12]?lv1:lv0))finish(22,32'h43534c55);else next_sigmoid();end
   TREAD:if(run_ce)begin
    point<=0;transfer(0,transpose_chunk_base+transpose_channel_offset,
     wide_element?(chunk<<1):chunk,0,TCRQ);
   end
   TCRQ:if(run_ce)state<=TCCAP;
   TCCAP:if(run_ce)begin
    if(bv_b!=8'hff)finish(22,32'h43545241);
    else if({3'd0,point}+8'd1==chunk)begin
     if(channel+1==channels)state<=WRITE;else begin channel<=channel+1;state<=TREAD;end
    end else begin point<=point+1;state<=TCRQ;end
   end
   WRITE:if(run_ce)transfer(1,dst+(code==8?(cursor<<1):code==6?t_cursor_bytes:cursor),code==8?(chunk<<1):code==6?t_chunk_bytes:chunk,0,ADVANCE);
   ADVANCE:if(run_ce)begin
    if(final_chunk)finish(0,0);else begin cursor<=cursor+{24'd0,chunk};state<=NEXT;end
   end
   IOCHECK:if(run_ce)begin
    if(io_remaining==0||io_remaining>128||{1'b0,io_address}+io_remaining>33'h100000000||next_tag==32'hffffffff)
     finish(11,32'h43494f42);
    else begin next_tag<=next_tag+1;state<=IOREQ;end
   end
   IOREQ:if(mem_req_ready)state<=io_write?IOWINIT:IOR;
   IOWINIT:if(run_ce)begin write_packed<=0;io_copy_pos<=0;state<=IOWRQ;end
   IOWRQ:if(run_ce)state<=IOWCAP;
   IOWCAP:if(run_ce)begin
    if(bv_b!=8'hff)io_error<=22;
    write_packed[64*io_copy_pos[4:3]+:64]<=b_rotated[63:0];
    if(io_copy_pos+6'd8>=io_count)state<=IOW;else begin io_copy_pos<=io_copy_pos+8;state<=IOWRQ;end
   end
   IOW:if(mem_w_ready)state<=IORSP;
   IOR:if(mem_r_valid)begin
    read_skid<=mem_r_data>>{io_address[4:0],3'b0};io_copy_pos<=0;state<=IORCOPY;
    if(!mem_r_last)io_error<=22;
   end
   IORCOPY:if(run_ce)begin
    read_skid<=read_skid>>64;
    if(io_copy_pos+6'd8>=io_count)state<=IORSP;else io_copy_pos<=io_copy_pos+8;
   end
   IORSP:if(mem_rsp_valid)begin
    if(mem_rsp_tag!=io_tag||mem_rsp_status!=0||io_error!=0)finish(mem_rsp_status!=0?{28'd0,mem_rsp_status}:22,32'h434d454d);
    else if(cancel_pending||cancel_request)finish(17,32'h4343414e);
    else if(io_remaining=={2'd0,io_count})state<=return_state;
    else if(next_tag==32'hffffffff)finish(22,32'h43544147);
    else begin
     io_address<=io_address+{26'd0,io_count};io_position<=io_position+{2'd0,io_count};io_remaining<=io_remaining-{2'd0,io_count};
     io_tag<=next_tag;next_tag<=next_tag+1;state<=IOREQ;
    end
   end
   HELD:if(done_ready)begin done_valid<=0;state<=IDLE;end
   default:finish(22,32'h43535441);
   endcase
   if(active&&(cancel_pending||cancel_request)&&!memory_active&&state!=QISSUE&&state!=QWAIT)finish(17,32'h4343414e);
  end
 end
endmodule
