// NPM3 autonomous model controller. All addresses are locked controller bytes.
// No model input/output access is permitted before complete table/parameter
// integrity checks and one successful numeric-parameter preflight per op.
module b03_graph_engine_cap #(
 parameter LATCH_TASK=1,
 // The board demonstration uses a hash-verified, immutable B03 package.
 // Keeping this opt-in preserves the full admission checks for development.
 parameter TRUSTED_MODEL=0,
 // Caller must already enforce immutable, aligned, bounded, disjoint regions.
 // Default keeps the full validator for every generic/direct engine caller.
 parameter PREVALIDATED_TASK_LAYOUT=0
)(
 input wire clk,rst_n,run_ce,cancel_request,bridge_fault,
 input wire [31:0] epoch,cfg_window_base,cfg_window_bytes,addr_cfg_version,
 input wire start_valid,output wire start_ready,input wire [1023:0] task_words,
 output reg done_valid,input wire done_ready,output reg [31:0] status,detail,cmd_id,
 output reg [63:0] frame_id,output reg [31:0] done_epoch,output reg [63:0] cycles,
 output reg [31:0] done_heads_offset,done_table_offset,done_result_offset,done_result_alloc,
 output reg [11:0] done_capacity,output reg [13:0] done_source_w,done_source_h,
 output reg [8:0] done_resized_w,done_resized_h,done_pad_left,done_pad_top,
 output reg [31:0] done_expected_table_crc32,done_model_tag,
 output wire busy,output wire [7:0] debug_stage,debug_op,
 output wire layer_start_valid,input wire layer_start_ready,
 output wire [1023:0] layer_op_words,output wire layer_preflight,
 output reg [31:0] layer_workspace_base,layer_src0_base,layer_src1_base,layer_dst_base,
 output wire [31:0] layer_epoch,layer_tag,
 input wire layer_done_valid,output wire layer_done_ready,
 input wire [31:0] layer_done_status,layer_done_detail,layer_done_tag,layer_done_op_id,
 input wire [63:0] layer_done_cycles,
 output wire mem_req_valid,input wire mem_req_ready,output wire mem_req_write,mem_req_verify,
 output wire [31:0] mem_req_offset,mem_req_tag,output wire [4:0] mem_req_beats,output wire [2:0] mem_req_client,
 output wire mem_w_valid,input wire mem_w_ready,output wire [255:0] mem_w_data,
 output wire [31:0] mem_w_strb,output wire mem_w_last,
 input wire mem_r_valid,output wire mem_r_ready,input wire [255:0] mem_r_data,input wire mem_r_last,
 input wire mem_rsp_valid,output wire mem_rsp_ready,input wire [3:0] mem_rsp_status,input wire [31:0] mem_rsp_tag,
 input wire layer_mem_req_valid,output wire layer_mem_req_ready,input wire layer_mem_req_write,layer_mem_req_verify,
 input wire [31:0] layer_mem_req_offset,layer_mem_req_tag,input wire [4:0] layer_mem_req_beats,input wire [2:0] layer_mem_req_client,
 input wire layer_mem_w_valid,output wire layer_mem_w_ready,input wire [255:0] layer_mem_w_data,
 input wire [31:0] layer_mem_w_strb,input wire layer_mem_w_last,
 output wire layer_mem_r_valid,input wire layer_mem_r_ready,output wire [255:0] layer_mem_r_data,output wire layer_mem_r_last,
 output wire layer_mem_rsp_valid,input wire layer_mem_rsp_ready,output wire [3:0] layer_mem_rsp_status,output wire [31:0] layer_mem_rsp_tag
);
 localparam IDLE=0,TASK_CHECK=1,HEADER_BEGIN=2,HEADER_PART=3,HEADER_CRC=4,HEADER_CHECK=5,
 PARAM_BEGIN=6,PARAM_PART=7,PARAM_CRC=8,OP_BEGIN=9,OP_PART=10,OP_CRC=11,OP_CHECK=12,
 MUL_STEP=13,GEOMETRY=14,LAYER_OFFER=15,LAYER_WAIT=16,NEXT_OP=17,MODEL_END=18,
 FETCH_OFFER=20,FETCH_READ=21,FETCH_RSP=22,TASK_REGION=23,TASK_PAIR=24,TASK_BIND=25,MUL_CHECK=26,HELD=31;
 reg [7:0] state,return_state;
 wire [31:0] t[0:31],h[0:31];reg [31:0] saved_task[0:31];
 reg [7:0] saved_op_count;reg [31:0] saved_workspace_bound,saved_parameter_origin,saved_parameter_crc,saved_body_crc;reg [1023:0] op_bits;wire [1023:0] record_bits=op_bits;reg [2:0] check_i,check_j;
 wire [31:0] o[0:31];genvar g;generate for(g=0;g<32;g=g+1)begin:OPS
 assign o[g]=op_bits[g*32+:32];assign h[g]=op_bits[g*32+:32];assign t[g]=LATCH_TASK?saved_task[g]:task_words[g*32+:32];end endgenerate
 reg [31:0] win_base,win_bytes,locked_version,watchdog,program_base,workspace_base,input_base,heads_base;
 reg [31:0] sequence_tag,fetch_tag,layer_sequence,active_layer_tag;
 reg [31:0] fetch_offset;reg [4:0] fetch_beats,received;
 reg [255:0] fetch_buffer;reg param_rx_valid;reg [2:0] param_word;
 wire param_fetch=return_state==PARAM_PART;wire [31:0] param_crc_next;
reg [1:0] part;reg [8:0] byte_index;
 reg [31:0] header_crc,program_crc,body_crc,record_crc,param_crc,param_cursor,param_remaining;
 b03_crc32_parallel4 param_crc_unit(.seed(param_crc),.data(fetch_buffer[31:0]),.value(param_crc_next));


 reg [7:0] op_index;reg execution_pass,abort_pending;reg [31:0] abort_status;
 reg [1:0] mul_phase;reg [5:0] mul_count;reg [63:0] mul_x,mul_acc;reg [31:0] mul_b,src_elements;
 wire [63:0] mul_next=mul_acc+(mul_b[0]?mul_x:64'd0);
 wire layer_owner=state==LAYER_OFFER||state==LAYER_WAIT;
 wire fetch_owner=state==FETCH_OFFER||state==FETCH_READ||state==FETCH_RSP;
 wire rf=mem_r_valid&&mem_r_ready;
 wire sf=mem_rsp_valid&&mem_rsp_ready;
 wire [5:0] after_received={1'b0,received}+{5'd0,rf};
 wire external_abort=cancel_request||bridge_fault||epoch!=done_epoch||addr_cfg_version!=locked_version||
                     cfg_window_base!=win_base||cfg_window_bytes!=win_bytes;
 wire timed_out=busy&&cycles>={32'd0,watchdog};
 assign start_ready=rst_n&&state==IDLE&&!done_valid&&!cancel_request&&!bridge_fault&&epoch!=0;
 assign busy=state!=IDLE||done_valid;assign debug_stage=state;assign debug_op=op_index;
 assign layer_start_valid=rst_n&&state==LAYER_OFFER&&!abort_pending&&!external_abort&&!timed_out;
 assign layer_op_words=op_bits;assign layer_preflight=!execution_pass;
 assign layer_epoch=done_epoch;assign layer_tag=active_layer_tag;
 assign layer_done_ready=rst_n&&state==LAYER_WAIT;
 assign mem_req_valid=rst_n&&(layer_owner?layer_mem_req_valid:state==FETCH_OFFER);
 assign mem_req_write=layer_owner?layer_mem_req_write:1'b0;
 assign mem_req_verify=layer_owner?layer_mem_req_verify:1'b0;
 assign mem_req_offset=layer_owner?layer_mem_req_offset:fetch_offset;
 assign mem_req_tag=layer_owner?layer_mem_req_tag:fetch_tag;
 assign mem_req_beats=layer_owner?layer_mem_req_beats:fetch_beats;
 assign mem_req_client=layer_owner?layer_mem_req_client:3'd0;
 assign layer_mem_req_ready=layer_owner&&mem_req_ready;
 assign mem_w_valid=layer_owner&&layer_mem_w_valid;assign mem_w_data=layer_mem_w_data;
 assign mem_w_strb=layer_mem_w_strb;assign mem_w_last=layer_mem_w_last;
 assign layer_mem_w_ready=layer_owner&&mem_w_ready;
 assign mem_r_ready=layer_owner?layer_mem_r_ready:(state==FETCH_READ&&(!param_fetch||!param_rx_valid));
 assign layer_mem_r_valid=layer_owner&&mem_r_valid;assign layer_mem_r_data=mem_r_data;assign layer_mem_r_last=mem_r_last;
 assign mem_rsp_ready=layer_owner?layer_mem_rsp_ready:((state==FETCH_READ||state==FETCH_RSP)&&(!param_fetch||(!param_rx_valid&&!rf)));
 assign layer_mem_rsp_valid=layer_owner&&mem_rsp_valid;assign layer_mem_rsp_status=mem_rsp_status;assign layer_mem_rsp_tag=mem_rsp_tag;

 function [31:0] crc_byte;input [31:0] value;input [7:0] data;reg [31:0] v;integer k;
 begin v=value^{24'd0,data};for(k=0;k<8;k=k+1)v=v[0]?((v>>1)^32'hedb88320):(v>>1);crc_byte=v;end endfunction
 function dtype_valid;input [31:0] d;begin dtype_valid=d>=1&&d<=4;end endfunction
 function [1:0] elem_bytes;input [31:0] d;begin elem_bytes=d>=3?2:1;end endfunction
 function region_ok;input [31:0] off,n;reg [32:0] last;
 begin last={1'b0,off}+{1'b0,n};region_ok=off[4:0]==0&&n!=0&&n[4:0]==0&&last<={1'b0,win_bytes};end endfunction
 function disjoint;input [31:0] a,n,b,m;begin disjoint=({1'b0,a}+{1'b0,n}<={1'b0,b})||({1'b0,b}+{1'b0,m}<={1'b0,a});end endfunction
 function ref_ok;input [31:0] tensor_ref,n,dtype;input destination;reg [32:0] last;reg [31:0] bound;
 begin
 last={3'd0,tensor_ref[29:0]}+{1'b0,n};
 case(tensor_ref[31:30])2'b00:bound=saved_parameter_origin;2'b10:bound=32'd307200;2'b01:bound=32'd26368;default:bound=0;endcase
 ref_ok=n!=0&&tensor_ref!=32'hffffffff&&tensor_ref[31:30]!=3&&last<={1'b0,bound}&&
        !(destination&&tensor_ref[31])&&!(elem_bytes(dtype)==2&&tensor_ref[0]);
 end endfunction
 function [31:0] resolve_ref;input [31:0] tensor_ref;
 begin case(tensor_ref[31:30])2'b10:resolve_ref=input_base+{2'd0,tensor_ref[29:0]};
 2'b01:resolve_ref=heads_base+{2'd0,tensor_ref[29:0]};default:resolve_ref=workspace_base+tensor_ref;endcase end endfunction
 function parameter_ok;input [31:0] off;begin parameter_ok=off>=saved_parameter_origin&&off<saved_workspace_bound&&off[1:0]==0;end endfunction
 function [15:0] mul_small;input [4:0] a;input [8:0] b;integer k;reg [15:0] v;
 begin v=0;for(k=0;k<5;k=k+1)if(a[k])v=v+({7'd0,b}<<k);mul_small=v;end endfunction
    function [10:0] capacity_words;input [4:0] groups;
    begin case(groups)
        5'd0:capacity_words=11'd2047;
        5'd1:capacity_words=11'd1024;
        5'd2:capacity_words=11'd512;
        5'd3:capacity_words=11'd341;
        5'd4:capacity_words=11'd256;
        5'd5:capacity_words=11'd204;
        5'd6:capacity_words=11'd170;
        5'd7:capacity_words=11'd146;
        5'd8:capacity_words=11'd128;
        5'd9:capacity_words=11'd113;
        5'd10:capacity_words=11'd102;
        5'd11:capacity_words=11'd93;
        5'd12:capacity_words=11'd85;
        5'd13:capacity_words=11'd78;
        5'd14:capacity_words=11'd73;
        5'd15:capacity_words=11'd68;
        5'd16:capacity_words=11'd64;
        5'd17:capacity_words=11'd60;
        5'd18:capacity_words=11'd56;
        5'd19:capacity_words=11'd53;
        5'd20:capacity_words=11'd51;
        5'd21:capacity_words=11'd48;
        5'd22:capacity_words=11'd46;
        5'd23:capacity_words=11'd44;
        5'd24:capacity_words=11'd42;
        5'd25:capacity_words=11'd40;
        5'd26:capacity_words=11'd39;
        5'd27:capacity_words=11'd37;
        5'd28:capacity_words=11'd36;
        5'd29:capacity_words=11'd35;
        5'd30:capacity_words=11'd34;
        5'd31:capacity_words=11'd33;
        default:capacity_words=11'd0;
    endcase end endfunction
 reg task_bad,task_alignment_bad,header_bad,op_bad,geometry_bad;
 reg [31:0] roff[0:5],rlen[0:5];integer i,j,k;
 wire [32:0] window_end={1'b0,win_base}+{1'b0,win_bytes};
 wire [32:0] padded_h={1'b0,o[10]}+{25'd0,o[18][7:0]}+{25'd0,o[18][23:16]};
 wire [32:0] padded_w={1'b0,o[11]}+{25'd0,o[18][15:8]}+{25'd0,o[18][31:24]};
 wire [32:0] hout_calc=((padded_h-{1'b0,o[14]})>>(o[16]==2))+1;
 wire [32:0] wout_calc=((padded_w-{1'b0,o[15]})>>(o[17]==2))+1;
 wire [31:0] expected_k=o[0]==2?(o[14]==3?9:1):(o[14]==3?((o[8]<<3)+o[8]):o[8]);
 wire [9:0] row_bytes=elem_bytes(o[7])==2?{o[13][8:0],1'b0}:{1'b0,o[13][8:0]};
 wire [8:0] row_words=({1'b0,row_bytes}+3)>>2;
 wire [4:0] co_groups=({1'b0,o[9][6:0]}+3)>>2;
 always @*begin
 task_bad=0;task_alignment_bad=0;
 roff[0]=t[4];rlen[0]=t[5];roff[1]=t[6];rlen[1]=t[7];roff[2]=t[8];rlen[2]=t[9];
 roff[3]=t[10];rlen[3]=t[11];roff[4]=t[12];rlen[4]=t[13];roff[5]=t[28];rlen[5]=26368;
 if (TRUSTED_MODEL) begin
   // The immutable package is checked before synthesis and again by the
   // software asset audit.  Preserve region addresses for the runtime bind,
   // but remove the wide header/op/geometry comparison cone from this profile.
   header_bad=0;op_bad=0;geometry_bad=0;
 end else begin
 if(t[0]!=32'h33444d42||t[1]!=1||t[2]!=128||t[3]!=1||t[29]!=1||t[30]==0||t[31]!=0||
    t[17]!=done_epoch||t[18]!=locked_version||t[25]<1||t[25]>2100||t[13]!=1572864||
    t[5]<256||t[5]>16512||t[5][6:0]!=0||t[19]<1||t[19]>16383||t[20]<1||t[20]>16383||
    t[21]<1||t[21]>320||t[22]<1||t[22]>320||t[23]>319||t[24]>319||
    {1'b0,t[21]}+{1'b0,t[23]}>320||{1'b0,t[22]}+{1'b0,t[24]}>320||
    {1'b0,t[11]}<(33'd128+({1'b0,t[25]}<<5))||win_bytes==0||win_base[4:0]!=0||
    win_bytes[4:0]!=0||window_end>33'h040000000)task_bad=1;
 for(i=0;i<6;i=i+1)begin
   if(roff[i][4:0]!=0||rlen[i][4:0]!=0)task_alignment_bad=1;

 end
 if(task_alignment_bad)task_bad=1;
 header_bad=h[0]!=32'h334d504e||h[1]!=1||h[2]!=128||h[3]!=128||h[4]<1||h[4]>128||
   h[5]!=(128+(h[4]<<7))||h[5]!=t[5]||h[6]!=t[7]||h[6][7:0]!=0||h[7][7:0]!=0||
   h[8]==0||h[8][7:0]!=0||{1'b0,h[7]}+{1'b0,h[8]}!={1'b0,h[6]}||
   h[9]!=3||h[10]!=320||h[11]!=320||h[12]!=307200||t[9]<h[12]||
   h[13]!=0||h[14]!=3328||h[15]!=4352||h[16]!=4608||h[17]!=7936||h[18]!=8960||
   h[19]!=9216||h[20]!=22016||h[21]!=25344||h[22]!=26368||h[23]!=1572864||
   h[24]!=127||h[25]!=t[27]||h[28]!=1||h[30]!=0;
 op_bad=o[0]<1||o[0]>8||o[29]!={24'd0,op_index}||!dtype_valid(o[5])||!dtype_valid(o[7])||
   !ref_ok(o[2],o[24],o[5],0)||!ref_ok(o[4],o[26],o[7],1)||o[8]==0||o[9]==0||
   o[10]==0||o[11]==0||o[12]==0||o[13]==0||o[24]==0||o[26]==0;
 if(o[0]==3)begin
   if(!dtype_valid(o[6])||!ref_ok(o[3],o[25],o[6],0)||o[24]!=o[25])op_bad=1;
 end else if(o[3]!=32'hffffffff||o[6]!=0||o[25]!=0)op_bad=1;
 if(o[0]==1||o[0]==2)begin
   if(!parameter_ok(o[19])||!parameter_ok(o[20])||!parameter_ok(o[21])||
      o[22]!=32'hffffffff||o[23]!=32'hffffffff||o[1]>1)op_bad=1;
 end else begin
   if(o[19]!=32'hffffffff||o[20]!=32'hffffffff||o[21]!=32'hffffffff||o[1]!=0)op_bad=1;
   if(o[0]==3||o[0]==8)begin if(!parameter_ok(o[22]))op_bad=1;end
   else if(o[22]!=32'hffffffff)op_bad=1;
   if(o[0]==8)begin if(!parameter_ok(o[23]))op_bad=1;end
   else if(o[23]!=32'hffffffff)op_bad=1;
 end
 geometry_bad=0;
 if(o[0]<=2||o[0]==4||o[0]==5)begin
   if(o[8]>64||o[9]>64||o[10]>320||o[11]>320||o[12]>320||o[13]>320||
      row_words>capacity_words(co_groups))geometry_bad=1;
 end
 if(o[0]==1||o[0]==2)begin
   if(o[14]!=o[15]||(o[14]!=1&&o[14]!=3)||(o[16]!=1&&o[16]!=2)||(o[17]!=1&&o[17]!=2)||
      padded_h<o[14]||padded_w<o[15]||hout_calc!={1'b0,o[12]}||wout_calc!={1'b0,o[13]}||
      o[28]!=expected_k||o[28]>128||(o[0]==2&&o[8]!=o[9])||
      (o[5]!=1&&o[5]!=2)||(o[1]==1?o[7]!=1:(o[7]!=2&&o[7]!=3)))geometry_bad=1;
 end else if(o[28]!=0)geometry_bad=1;
 if(o[0]==3&&(o[5]!=1||o[6]!=1||o[7]!=1||o[24]!=o[26]))geometry_bad=1;
 if(o[0]==4&&(o[5]!=1||o[7]!=1||o[8]!=o[9]||o[14]!=2||o[15]!=2||o[16]!=2||o[17]!=2||
    o[18]!=0||o[10][0]||o[11][0]||o[12]!=(o[10]>>1)||o[13]!=(o[11]>>1)))geometry_bad=1;
 if(o[0]==5&&(o[5]!=1||o[7]!=1||o[8]!=o[9]||{1'b0,o[12]}!=({1'b0,o[10]}<<1)||
    {1'b0,o[13]}!=({1'b0,o[11]}<<1)))geometry_bad=1;
 if((o[0]==6||o[0]==7)&&(o[5]!=o[7]||o[24]!=o[26]))geometry_bad=1;
 if(o[0]==6&&(o[30]!=32'h01030200||o[9]!=o[10]||o[12]!=o[11]||o[13]!=o[8]))geometry_bad=1;
 if(o[0]!=6&&o[30]!=0)geometry_bad=1;
 if(o[0]==8&&(o[5]!=2||o[7]!=4||o[8]!=o[9]||o[10]!=o[12]||o[11]!=o[13]||
    {1'b0,o[26]}!=({1'b0,o[24]}<<1)))geometry_bad=1;
 end
 end
 reg op_bad_latched,geometry_bad_latched,op_flags_ready;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin op_bad_latched<=0;geometry_bad_latched<=0;op_flags_ready<=0;end
  else if(state==OP_BEGIN)op_flags_ready<=0;
  else if(state==OP_CRC&&run_ce)begin
   op_bad_latched<=op_bad;geometry_bad_latched<=geometry_bad;
   if(byte_index==127)op_flags_ready<=1;
  end
 end
 task finish_error;input [31:0] code;input [7:0] reason;
 begin status<=code;detail<={8'hb3,state,op_index,reason};done_valid<=1;state<=HELD;end endtask
 task fetch;input [31:0] offset;input [4:0] beats;input [7:0] resume;
 begin
 if(sequence_tag==0)finish_error(22,8'h12);
 else begin fetch_offset<=offset;fetch_beats<=beats;return_state<=resume;fetch_tag<=sequence_tag;
 sequence_tag<=sequence_tag+1;received<=0;state<=FETCH_OFFER;end
 end endtask
 reg [31:0] next_crc;reg [4:0] planned_beats;
 always @*begin
 planned_beats=16;
 if(param_remaining<512)planned_beats=param_remaining[9:5];
 if((4096-{1'b0,param_cursor[11:0]})<({8'd0,planned_beats}<<5))planned_beats=(4096-{1'b0,param_cursor[11:0]})>>5;
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 state<=IDLE;return_state<=0;done_valid<=0;status<=0;detail<=0;cmd_id<=0;frame_id<=0;done_epoch<=0;cycles<=0;
 done_heads_offset<=0;done_table_offset<=0;done_result_offset<=0;done_result_alloc<=0;done_capacity<=0;
 done_source_w<=0;done_source_h<=0;done_resized_w<=0;done_resized_h<=0;done_pad_left<=0;done_pad_top<=0;
 done_expected_table_crc32<=0;done_model_tag<=0;
 win_base<=0;win_bytes<=0;locked_version<=0;watchdog<=0;program_base<=0;workspace_base<=0;input_base<=0;heads_base<=0;
 sequence_tag<=1;fetch_tag<=0;layer_sequence<=1;active_layer_tag<=0;fetch_offset<=0;fetch_beats<=0;received<=0;
 fetch_buffer<=0;param_rx_valid<=0;param_word<=0;check_i<=0;check_j<=0;op_bits<=0;part<=0;byte_index<=0;header_crc<=0;program_crc<=0;body_crc<=0;
 record_crc<=0;param_crc<=0;param_cursor<=0;param_remaining<=0;op_index<=0;execution_pass<=0;abort_pending<=0;abort_status<=0;
 mul_phase<=0;mul_count<=0;mul_x<=0;mul_acc<=0;mul_b<=0;src_elements<=0;
 layer_workspace_base<=0;layer_src0_base<=0;layer_src1_base<=0;layer_dst_base<=0;
 saved_op_count<=0;saved_workspace_bound<=0;saved_parameter_origin<=0;saved_parameter_crc<=0;saved_body_crc<=0;
 for(k=0;k<32;k=k+1)saved_task[k]<=0;
 end else begin
 if(busy&&!done_valid)cycles<=cycles+1;
 // Ordinary service reception is independent of arithmetic enable. A local
 // CRC skid is discarded on abort so service DONE cannot depend on run_ce.
 if(param_rx_valid)begin
   if(abort_pending||external_abort||timed_out)param_rx_valid<=0;
   else if(run_ce)begin
     param_crc<=param_crc_next;fetch_buffer<=fetch_buffer>>32;
     if(param_word==7)param_rx_valid<=0;else param_word<=param_word+1;
   end
 end
 if(busy&&!done_valid&&(external_abort||timed_out)&&!abort_pending)begin
   abort_pending<=1;abort_status<=bridge_fault?18:cancel_request?17:
       (epoch!=done_epoch||addr_cfg_version!=locked_version||cfg_window_base!=win_base||cfg_window_bytes!=win_bytes)?13:16;
 end
 if(done_valid&&done_ready)begin done_valid<=0;state<=IDLE;end
 if(state!=IDLE&&state!=HELD&&(abort_pending||external_abort||timed_out)&&
    state!=FETCH_READ&&state!=FETCH_RSP&&state!=LAYER_WAIT)begin
   // FETCH_OFFER is a local service request; no bridge ownership exists until
   // accepted. If acceptance coincides with cancellation, retire that service.
   if(state==FETCH_OFFER&&mem_req_valid&&mem_req_ready)state<=FETCH_READ;
   else finish_error(abort_pending?abort_status:bridge_fault?18:cancel_request?17:timed_out?16:13,8'h01);
 end else case(state)
 IDLE:if(start_valid&&start_ready)begin
   if(LATCH_TASK)for(k=0;k<32;k=k+1)saved_task[k]<=task_words[k*32+:32];
   win_base<=cfg_window_base;win_bytes<=cfg_window_bytes;locked_version<=addr_cfg_version;
   done_epoch<=epoch;cmd_id<=task_words[14*32+:32];frame_id<=task_words[15*32+:64];
   watchdog<=task_words[30*32+:32];cycles<=0;status<=0;detail<=0;op_index<=0;
   abort_pending<=0;abort_status<=0;execution_pass<=0;state<=TASK_CHECK;
 end
 TASK_CHECK:if(task_bad)finish_error(task_alignment_bad?10:11,8'h02);else begin
   check_i<=0;state<=PREVALIDATED_TASK_LAYOUT?TASK_BIND:TASK_REGION;
 end
 TASK_REGION:if(!region_ok(roff[check_i],rlen[check_i]))finish_error(11,8'h02);
 else if(check_i==5)begin check_i<=0;check_j<=1;state<=TASK_PAIR;end else check_i<=check_i+1;
 TASK_PAIR:if(!disjoint(roff[check_i],rlen[check_i],roff[check_j],rlen[check_j]))finish_error(11,8'h02);
 else if(check_i==4)state<=TASK_BIND;
 else if(check_j==5)begin check_i<=check_i+1;check_j<=check_i+2;end else check_j<=check_j+1;
 TASK_BIND:begin
   program_base<=win_base+t[4];workspace_base<=win_base+t[6];input_base<=win_base+t[8];heads_base<=win_base+t[28];
   layer_workspace_base<=win_base+t[6];done_heads_offset<=win_base+t[28];done_table_offset<=win_base+t[12];
   done_result_offset<=win_base+t[10];done_result_alloc<=t[11];done_capacity<=t[25][11:0];
   done_source_w<=t[19][13:0];done_source_h<=t[20][13:0];done_resized_w<=t[21][8:0];done_resized_h<=t[22][8:0];
   done_pad_left<=t[23][8:0];done_pad_top<=t[24][8:0];state<=HEADER_BEGIN;
 end
 HEADER_BEGIN:begin part<=0;fetch(program_base,1,HEADER_PART);end
 HEADER_PART:begin
   for(k=0;k<4;k=k+1)if(part==k)op_bits[k*256+:256]<=fetch_buffer[255:0];

   if(part==3)begin byte_index<=0;header_crc<=32'hffffffff;program_crc<=32'hffffffff;state<=HEADER_CRC;end
   else begin part<=part+1;fetch(program_base+(({30'd0,part}+1)<<5),1,HEADER_PART);end
 end
 HEADER_CRC:if(run_ce)begin
   program_crc<=crc_byte(program_crc,record_bits[byte_index[6:0]*8+:8]);
   if(byte_index<124)header_crc<=crc_byte(header_crc,record_bits[byte_index[6:0]*8+:8]);
   if(byte_index==127)state<=HEADER_CHECK;else byte_index<=byte_index+1;
 end
 HEADER_CHECK:if(~header_crc!=h[31])finish_error(3,8'h03);else if(header_bad)finish_error(11,8'h04);else begin
   saved_op_count<=h[4][7:0];saved_workspace_bound<=h[6];saved_parameter_origin<=h[7];saved_parameter_crc<=h[25];saved_body_crc<=h[26];
   done_expected_table_crc32<=h[29];done_model_tag<=h[27];param_cursor<=workspace_base+h[7];
   param_remaining<=h[8];param_crc<=32'hffffffff;state<=PARAM_BEGIN;
 end
 PARAM_BEGIN:fetch(param_cursor,planned_beats,PARAM_PART);
 PARAM_PART:begin
   if(param_remaining==({27'd0,fetch_beats}<<5))begin
     if(~param_crc!=saved_parameter_crc)finish_error(3,8'h05);else begin body_crc<=32'hffffffff;op_index<=0;state<=OP_BEGIN;end
   end else begin param_remaining<=param_remaining-({27'd0,fetch_beats}<<5);
     param_cursor<=param_cursor+({27'd0,fetch_beats}<<5);state<=PARAM_BEGIN;end
 end
 OP_BEGIN:begin part<=0;fetch(program_base+128+({24'd0,op_index}<<7),1,OP_PART);end
 OP_PART:begin
   for(k=0;k<4;k=k+1)if(part==k)op_bits[k*256+:256]<=fetch_buffer[255:0];
   if(part==3)begin byte_index<=0;record_crc<=32'hffffffff;state<=OP_CRC;end
   else begin part<=part+1;fetch(program_base+128+({24'd0,op_index}<<7)+(({30'd0,part}+1)<<5),1,OP_PART);end
 end
 OP_CRC:if(run_ce)begin
   if(!execution_pass)begin
     program_crc<=crc_byte(program_crc,op_bits[byte_index[6:0]*8+:8]);
     body_crc<=crc_byte(body_crc,op_bits[byte_index[6:0]*8+:8]);
   end
   if(byte_index<124)record_crc<=crc_byte(record_crc,op_bits[byte_index[6:0]*8+:8]);
   if(byte_index==127)state<=OP_CHECK;else byte_index<=byte_index+1;
 end
 OP_CHECK:if(~record_crc!=o[31])finish_error(3,8'h06);else if(!op_flags_ready)finish_error(22,8'h14);else if(op_bad_latched)finish_error(11,8'h07);else begin
   mul_phase<=0;mul_count<=0;mul_x<={32'd0,o[8]};mul_b<=o[10];mul_acc<=0;state<=MUL_STEP;
 end
 // The final add writes the existing accumulator. Check overflow and shape
 // on the following enabled cycle, off the 64-bit carry-chain endpoint.
 MUL_STEP:if(run_ce)begin
   mul_acc<=mul_next;
   if(mul_count==31)state<=MUL_CHECK;
   else begin mul_x<=mul_x<<1;mul_b<=mul_b>>1;mul_count<=mul_count+1;end
 end
 MUL_CHECK:if(run_ce)begin
   if(mul_acc[63:32]!=0)begin
     finish_error(8,8'h08);detail<={8'hb3,8'd13,op_index,8'h08};
   end else case(mul_phase)
     0:begin mul_phase<=1;mul_x<=mul_acc;mul_b<=o[11];mul_acc<=0;mul_count<=0;state<=MUL_STEP;end
     1:begin src_elements<=mul_acc[31:0];mul_phase<=2;mul_x<={32'd0,o[9]};mul_b<=o[12];mul_acc<=0;mul_count<=0;state<=MUL_STEP;end
     2:begin mul_phase<=3;mul_x<=mul_acc;mul_b<=o[13];mul_acc<=0;mul_count<=0;state<=MUL_STEP;end
     3:begin
       if(({1'b0,src_elements}<<(elem_bytes(o[5])==2))!={1'b0,o[24]}||
          ({1'b0,mul_acc[31:0]}<<(elem_bytes(o[7])==2))!={1'b0,o[26]}||mul_acc[31:0]!=o[27])begin
         finish_error(11,8'h09);detail<={8'hb3,8'd13,op_index,8'h09};
       end else state<=GEOMETRY;
     end
   endcase
 end
 GEOMETRY:if(geometry_bad_latched)finish_error(11,8'h0a);else if(layer_sequence==0)finish_error(22,8'h13);else begin
   layer_src0_base<=resolve_ref(o[2]);layer_src1_base<=o[0]==3?resolve_ref(o[3]):0;layer_dst_base<=resolve_ref(o[4]);
   active_layer_tag<=layer_sequence;layer_sequence<=layer_sequence+1;state<=LAYER_OFFER;
 end
 LAYER_OFFER:if(layer_start_valid&&layer_start_ready)state<=LAYER_WAIT;
 LAYER_WAIT:if(layer_done_valid&&layer_done_ready)begin
   if(layer_done_tag!=active_layer_tag||layer_done_op_id!=o[29])finish_error(22,8'h0b);
   else if(abort_pending||external_abort||timed_out)finish_error(abort_pending?abort_status:bridge_fault?18:cancel_request?17:timed_out?16:13,8'h0c);
   else if(layer_done_status!=0)begin status<=layer_done_status;detail<=layer_done_detail;done_valid<=1;state<=HELD;end
   else state<=NEXT_OP;
 end
 NEXT_OP:if(op_index+1==saved_op_count)begin
   if(!execution_pass)begin
     if(~body_crc!=saved_body_crc||~program_crc!=t[26])finish_error(3,8'h0d);
     else begin execution_pass<=1;op_index<=0;state<=OP_BEGIN;end
   end else state<=MODEL_END;
 end else begin op_index<=op_index+1;state<=OP_BEGIN;end
 MODEL_END:begin status<=0;detail<=0;done_valid<=1;state<=HELD;end
 FETCH_OFFER:if(mem_req_valid&&mem_req_ready)begin received<=0;state<=FETCH_READ;end
 FETCH_READ:begin
   if(rf)begin
     fetch_buffer<=mem_r_data;received<=received+1;
     if(param_fetch)begin param_rx_valid<=1;param_word<=0;end
     if(mem_r_last!=(after_received=={1'b0,fetch_beats})||received>=fetch_beats)begin
       abort_pending<=1;abort_status<=22;
     end
     if(after_received=={1'b0,fetch_beats})state<=FETCH_RSP;
   end
   if(sf)begin
     if(abort_pending||external_abort||timed_out)finish_error(abort_pending?abort_status:bridge_fault?18:cancel_request?17:timed_out?16:13,8'h0f);
     else if(mem_rsp_status!=0||mem_rsp_tag!=fetch_tag||after_received!={1'b0,fetch_beats})finish_error(22,8'h0e);
     else state<=return_state;
   end
 end
 FETCH_RSP:if(sf)begin
   if(abort_pending||external_abort||timed_out)finish_error(abort_pending?abort_status:bridge_fault?18:cancel_request?17:timed_out?16:13,8'h11);
   else if(mem_rsp_status!=0||mem_rsp_tag!=fetch_tag||received!=fetch_beats)finish_error(22,8'h10);
   else state<=return_state;
 end
 HELD:begin end
 default:finish_error(22,8'hff);
 endcase
 end
 end
endmodule
