`timescale 1ns/1ps
module tb_b03_graph_regions;
reg  clk=0;
reg  rst_n=0;
reg  run_ce=0;
reg  cancel_request=0;
reg  bridge_fault=0;
reg [31:0] epoch=0;
reg [31:0] cfg_window_base=0;
reg [31:0] cfg_window_bytes=0;
reg [31:0] addr_cfg_version=0;
reg  start_valid=0;
wire  start_ready;
reg [1023:0] task_words=0;
wire  done_valid;
reg  done_ready=0;
wire [31:0] status;
wire [31:0] detail;
wire [31:0] cmd_id;
wire [63:0] frame_id;
wire [31:0] done_epoch;
wire [63:0] cycles;
wire [31:0] done_heads_offset;
wire [31:0] done_table_offset;
wire [31:0] done_result_offset;
wire [31:0] done_result_alloc;
wire [11:0] done_capacity;
wire [13:0] done_source_w;
wire [13:0] done_source_h;
wire [8:0] done_resized_w;
wire [8:0] done_resized_h;
wire [8:0] done_pad_left;
wire [8:0] done_pad_top;
wire [31:0] done_expected_table_crc32;
wire [31:0] done_model_tag;
wire  busy;
wire [7:0] debug_stage;
wire [7:0] debug_op;
wire  layer_start_valid;
reg  layer_start_ready=0;
wire [1023:0] layer_op_words;
wire  layer_preflight;
wire [31:0] layer_workspace_base;
wire [31:0] layer_src0_base;
wire [31:0] layer_src1_base;
wire [31:0] layer_dst_base;
wire [31:0] layer_epoch;
wire [31:0] layer_tag;
reg  layer_done_valid=0;
wire  layer_done_ready;
reg [31:0] layer_done_status=0;
reg [31:0] layer_done_detail=0;
reg [31:0] layer_done_tag=0;
reg [31:0] layer_done_op_id=0;
reg [63:0] layer_done_cycles=0;
wire  mem_req_valid;
reg  mem_req_ready=0;
wire  mem_req_write;
wire  mem_req_verify;
wire [31:0] mem_req_offset;
wire [31:0] mem_req_tag;
wire [4:0] mem_req_beats;
wire [2:0] mem_req_client;
wire  mem_w_valid;
reg  mem_w_ready=0;
wire [255:0] mem_w_data;
wire [31:0] mem_w_strb;
wire  mem_w_last;
reg  mem_r_valid=0;
wire  mem_r_ready;
reg [255:0] mem_r_data=0;
reg  mem_r_last=0;
reg  mem_rsp_valid=0;
wire  mem_rsp_ready;
reg [3:0] mem_rsp_status=0;
reg [31:0] mem_rsp_tag=0;
reg  layer_mem_req_valid=0;
wire  layer_mem_req_ready;
reg  layer_mem_req_write=0;
reg  layer_mem_req_verify=0;
reg [31:0] layer_mem_req_offset=0;
reg [31:0] layer_mem_req_tag=0;
reg [4:0] layer_mem_req_beats=0;
reg [2:0] layer_mem_req_client=0;
reg  layer_mem_w_valid=0;
wire  layer_mem_w_ready;
reg [255:0] layer_mem_w_data=0;
reg [31:0] layer_mem_w_strb=0;
reg  layer_mem_w_last=0;
wire  layer_mem_r_valid;
reg  layer_mem_r_ready=0;
wire [255:0] layer_mem_r_data;
wire  layer_mem_r_last;
wire  layer_mem_rsp_valid;
reg  layer_mem_rsp_ready=0;
wire [3:0] layer_mem_rsp_status;
wire [31:0] layer_mem_rsp_tag;
b03_graph_engine_cap #(.TRUSTED_MODEL(1)) dut(.clk(clk),.rst_n(rst_n),.run_ce(run_ce),.cancel_request(cancel_request),.bridge_fault(bridge_fault),.epoch(epoch),.cfg_window_base(cfg_window_base),.cfg_window_bytes(cfg_window_bytes),.addr_cfg_version(addr_cfg_version),.start_valid(start_valid),.start_ready(start_ready),.task_words(task_words),.done_valid(done_valid),.done_ready(done_ready),.status(status),.detail(detail),.cmd_id(cmd_id),.frame_id(frame_id),.done_epoch(done_epoch),.cycles(cycles),.done_heads_offset(done_heads_offset),.done_table_offset(done_table_offset),.done_result_offset(done_result_offset),.done_result_alloc(done_result_alloc),.done_capacity(done_capacity),.done_source_w(done_source_w),.done_source_h(done_source_h),.done_resized_w(done_resized_w),.done_resized_h(done_resized_h),.done_pad_left(done_pad_left),.done_pad_top(done_pad_top),.done_expected_table_crc32(done_expected_table_crc32),.done_model_tag(done_model_tag),.busy(busy),.debug_stage(debug_stage),.debug_op(debug_op),.layer_start_valid(layer_start_valid),.layer_start_ready(layer_start_ready),.layer_op_words(layer_op_words),.layer_preflight(layer_preflight),.layer_workspace_base(layer_workspace_base),.layer_src0_base(layer_src0_base),.layer_src1_base(layer_src1_base),.layer_dst_base(layer_dst_base),.layer_epoch(layer_epoch),.layer_tag(layer_tag),.layer_done_valid(layer_done_valid),.layer_done_ready(layer_done_ready),.layer_done_status(layer_done_status),.layer_done_detail(layer_done_detail),.layer_done_tag(layer_done_tag),.layer_done_op_id(layer_done_op_id),.layer_done_cycles(layer_done_cycles),.mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),.mem_req_write(mem_req_write),.mem_req_verify(mem_req_verify),.mem_req_offset(mem_req_offset),.mem_req_tag(mem_req_tag),.mem_req_beats(mem_req_beats),.mem_req_client(mem_req_client),.mem_w_valid(mem_w_valid),.mem_w_ready(mem_w_ready),.mem_w_data(mem_w_data),.mem_w_strb(mem_w_strb),.mem_w_last(mem_w_last),.mem_r_valid(mem_r_valid),.mem_r_ready(mem_r_ready),.mem_r_data(mem_r_data),.mem_r_last(mem_r_last),.mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),.mem_rsp_status(mem_rsp_status),.mem_rsp_tag(mem_rsp_tag),.layer_mem_req_valid(layer_mem_req_valid),.layer_mem_req_ready(layer_mem_req_ready),.layer_mem_req_write(layer_mem_req_write),.layer_mem_req_verify(layer_mem_req_verify),.layer_mem_req_offset(layer_mem_req_offset),.layer_mem_req_tag(layer_mem_req_tag),.layer_mem_req_beats(layer_mem_req_beats),.layer_mem_req_client(layer_mem_req_client),.layer_mem_w_valid(layer_mem_w_valid),.layer_mem_w_ready(layer_mem_w_ready),.layer_mem_w_data(layer_mem_w_data),.layer_mem_w_strb(layer_mem_w_strb),.layer_mem_w_last(layer_mem_w_last),.layer_mem_r_valid(layer_mem_r_valid),.layer_mem_r_ready(layer_mem_r_ready),.layer_mem_r_data(layer_mem_r_data),.layer_mem_r_last(layer_mem_r_last),.layer_mem_rsp_valid(layer_mem_rsp_valid),.layer_mem_rsp_ready(layer_mem_rsp_ready),.layer_mem_rsp_status(layer_mem_rsp_status),.layer_mem_rsp_tag(layer_mem_rsp_tag));
always #5 clk=~clk;
integer n,i,j,k,limit,cases=0;reg [31:0] base[0:5],size[0:5];reg [63:0] ending[0:5];reg good;reg [31:0] seed=32'h125627ab;
function [31:0] random_next(input [31:0] value);random_next=(value<<1)^(value[31]?32'h04c11db7:32'd0);endfunction
initial begin
 for(n=0;n<1024;n=n+1)begin
  @(negedge clk);rst_n=0;start_valid=0;cancel_request=0;run_ce=n[0];task_words=0;
  repeat(2)@(negedge clk);rst_n=1;epoch=1;addr_cfg_version=1;cfg_window_base=0;cfg_window_bytes=32'h100000;
  for(i=0;i<6;i=i+1)begin base[i]=i*32'h10000;size[i]=32'h100;end
  size[5]=26368;
  if(n%8==1)begin k=0;for(i=0;i<6;i=i+1)for(j=i+1;j<6;j=j+1)begin if(k==(n/8)%15)base[j]=base[i];k=k+1;end end
  if(n%8==2)begin i=(n/8)%5;base[i+1]=base[i]+size[i];end
  if(n%8==3)begin i=(n/8)%6;base[i]=32'hffffffe0;end
  if(n%8==4)begin i=(n/8)%5;size[i]=32'hffffffe0;end
  if(n%8==5)begin i=(n/8)%6;base[i]=base[i]+1;end
  if(n%8==6)begin i=(n/8)%5;size[i]=0;end
  if(n%8==7)begin
   for(i=0;i<6;i=i+1)begin seed=random_next(seed);base[i]={12'd0,seed[14:0],5'd0};end
  end
  good=1;
  for(i=0;i<6;i=i+1)begin
   ending[i]={32'd0,base[i]}+{32'd0,size[i]};
   if(base[i]%32||size[i]==0||size[i]%32||ending[i]>cfg_window_bytes)good=0;
  end
  for(i=0;i<6;i=i+1)for(j=i+1;j<6;j=j+1)if(!(ending[i]<={32'd0,base[j]}||ending[j]<={32'd0,base[i]}))good=0;
  for(i=0;i<5;i=i+1)begin task_words[(4+2*i)*32+:32]=base[i];task_words[(5+2*i)*32+:32]=size[i];end
  task_words[28*32+:32]=base[5];task_words[30*32+:32]=100000;start_valid=1;
  @(posedge clk);#1;@(negedge clk);start_valid=0;
  limit=0;
  while(!done_valid&&!mem_req_valid&&limit<100)begin @(posedge clk);#1;limit=limit+1;end
  if(limit==100)$fatal(1,"GRAPH_PAIR timeout case=%0d",n);
  if(good)begin
   if(done_valid||!mem_req_valid||mem_req_offset!==base[0]||mem_req_write)$fatal(1,"GRAPH_PAIR valid rejected case=%0d status=%h",n,status);
  end else if(!done_valid||status!==11||mem_req_valid)$fatal(1,"GRAPH_PAIR invalid admitted case=%0d status=%h",n,status);
  cases=cases+1;
 end
 $display("GRAPH_PAIR_PASS cases=%0d",cases);$finish;
end
initial begin #2000000;$fatal(1,"GRAPH_PAIR global timeout");end
endmodule
