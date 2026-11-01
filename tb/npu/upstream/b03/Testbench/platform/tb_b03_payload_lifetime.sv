`timescale 1ns/1ps
// Parent lifetime/control unit only: successful graph/POST completions are
// explicitly injected. Real full inference is verified in full_frame_proxy.
module tb_b03_payload_lifetime;
reg clk=0;always #5 clk=~clk;
reg board_reset_n=0,session_reset_n=0,compute_running=0,run_ce=1,cancel_request=0,bridge_fault=0;
reg [31:0] epoch=77,addr_cfg_version=1,cfg_window_base=0,cfg_window_bytes=16777216;
reg host_write_valid=0;reg[31:0]host_write_offset=0;reg[4:0]host_write_beats=0;
reg start_valid=0;wire start_ready;reg[1023:0] task_words=0;
wire done_valid;reg done_ready=0;
wire[31:0] done_status,done_detail,done_cmd_id,done_epoch;
wire[63:0]done_frame_id;wire[11:0]done_faces;
wire[31:0]done_result_offset,done_result_bytes,done_crc;
wire[63:0]done_total_cycles,done_model_cycles,done_post_cycles;
wire done_live,busy,select_post,cancel_all,compute_fault_valid;
wire[175:0]compute_fault_payload;wire[7:0]debug_stage,debug_op;
wire mem_req_valid;
wire mem_req_ready;
wire mem_req_write;
wire mem_req_verify;
wire [31:0] mem_req_offset;
wire [31:0] mem_req_tag;
wire [4:0] mem_req_beats;
wire [2:0] mem_req_client;
wire mem_w_valid;
wire mem_w_ready;
wire [255:0] mem_w_data;
wire [31:0] mem_w_strb;
wire mem_w_last;
wire mem_r_valid;
wire mem_r_ready;
wire [255:0] mem_r_data;
wire mem_r_last;
wire mem_rsp_valid;
wire mem_rsp_ready;
wire [3:0] mem_rsp_status;
wire [31:0] mem_rsp_tag;
wire p_cmd_valid;
wire p_cmd_ready;
wire p_cmd_write;
wire [31:0] p_cmd_offset;
wire [31:0] p_cmd_id;
wire [31:0] p_cmd_epoch;
wire [4:0] p_cmd_beats;
wire [2:0] p_cmd_client;
wire p_write_valid;
wire p_write_ready;
wire [255:0] p_write_data;
wire [31:0] p_write_strb;
wire p_write_last;
wire p_read_valid;
wire p_read_ready;
wire [255:0] p_read_data;
wire p_read_last;
wire p_done_valid;
wire p_done_ready;
wire [3:0] p_done_status;
wire [31:0] p_done_id;
wire [31:0] p_done_epoch;
wire [2:0] p_done_client;
wire p_abort_req,p_quarantined;wire [175:0] post_fault_payload;
b03_frame_exec_payload dut(.*);GTP_GRS GRS_INST(.GRS_N(1'b1));
reg serve_header=0,service_rsp_valid=0;reg[31:0]service_tag=0;
integer ticks=0,checks=0,header_beats=0,i,limit;
reg[1023:0]observed_header;reg[491:0]held;
wire[491:0]tuple={done_status,done_detail,done_cmd_id,done_epoch,done_frame_id,done_faces,
 done_result_offset,done_result_bytes,done_crc,done_total_cycles,done_model_cycles,done_post_cycles};
assign mem_req_ready=serve_header;assign mem_w_ready=serve_header&&(ticks%3!=1);
assign mem_r_valid=0;assign mem_r_data=0;assign mem_r_last=0;
assign mem_rsp_valid=service_rsp_valid;assign mem_rsp_status=0;assign mem_rsp_tag=service_tag;
assign p_cmd_ready=0;assign p_write_ready=0;assign p_read_valid=0;assign p_read_data=0;assign p_read_last=0;
assign p_done_valid=0;assign p_done_status=0;assign p_done_id=0;assign p_done_epoch=0;assign p_done_client=0;
always @(posedge clk)begin
 ticks=ticks+1;
 if(mem_req_valid&&mem_req_ready)begin
  if(!mem_req_write||!mem_req_verify||mem_req_beats!=4||mem_req_offset!=32'h900000)$fatal(1,"private header request");
  service_tag<=mem_req_tag;header_beats=0;
 end
 if(mem_w_valid&&mem_w_ready)begin
  if(mem_w_strb!==32'hffffffff||mem_w_last!==(header_beats==3))$fatal(1,"header W");
  observed_header[256*header_beats+:256]<=mem_w_data;header_beats=header_beats+1;
  if(mem_w_last)service_rsp_valid<=1;
 end
 if(service_rsp_valid&&mem_rsp_ready)service_rsp_valid<=0;
end
task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
task task_config;input[31:0]id,watch;begin
 task_words=0;
 task_words[0+:32]=32'h33444d42;task_words[32+:32]=1;task_words[64+:32]=128;task_words[96+:32]=1;
 task_words[128+:32]=8192;task_words[160+:32]=10240;task_words[192+:32]=65536;task_words[224+:32]=4876544;
 task_words[256+:32]=32'h600000;task_words[288+:32]=307200;task_words[320+:32]=32'h900000;task_words[352+:32]=67328;
 task_words[384+:32]=32'h700000;task_words[416+:32]=1572864;task_words[448+:32]=id;
 task_words[480+:64]={32'h12345678,id};task_words[544+:32]=epoch;task_words[576+:32]=1;
 task_words[608+:32]=320;task_words[640+:32]=320;task_words[672+:32]=320;task_words[704+:32]=320;
 task_words[800+:32]=2100;task_words[832+:32]=508041292;task_words[864+:32]=1157718071;task_words[896+:32]=32'h680000;
 task_words[928+:32]=1;task_words[960+:32]=watch;
end endtask
task start;begin
 start_valid=1;limit=0;
 while(!start_ready&&limit<100)begin tick;limit=limit+1;end
 if(!start_ready)$fatal(1,"frame START not ready state=%0d",debug_stage);
 tick;start_valid=0;
end endtask
task result;input[31:0]s;begin
 limit=0;while(!done_valid&&limit<1000)begin tick;limit=limit+1;end
 if(!done_valid||done_status!==s||done_cmd_id!==task_words[448+:32]||done_frame_id!==task_words[480+:64]||done_epoch!==task_words[544+:32])
  $fatal(1,"frame result want=%0d got=%0d detail=%h state=%0d",s,done_status,done_detail,debug_stage);
 held=tuple;repeat(4)begin tick;if(tuple!==held||!done_valid)$fatal(1,"offered tuple changed");end
 checks=checks+1;
end endtask
task ack;begin run_ce=0;done_ready=1;tick;done_ready=0;if(done_valid)$fatal(1,"ACK gated by CE");run_ce=1;end endtask
task reset_leaf;begin
 session_reset_n=0;compute_running=0;repeat(3)tick;
 if(done_valid&&(tuple!==held||done_live))$fatal(1,"session reset rewrote pending tuple or live");
 epoch=epoch+1;session_reset_n=1;compute_running=1;repeat(3)tick;
 if(done_valid&&(tuple!==held||done_live||start_ready))$fatal(1,"old result replayed after rearm");
end endtask
reg[74:0]offered;reg[31:0]crc;integer fd;string root_path;
initial begin
 if(!$value$plusargs("ROOT=%s",root_path))$fatal(1,"ROOT missing");
 repeat(4)tick;board_reset_n=1;session_reset_n=1;compute_running=1;repeat(3)tick;
 task_config(100,100000);task_words[0+:32]=0;start;result(11);
 if(done_result_bytes!=0||done_faces!=0||compute_fault_valid)$fatal(1,"bad package published data");ack;
 task_config(101,100000);start;wait(mem_req_valid);@(negedge clk);offered={mem_req_write,mem_req_verify,mem_req_offset,mem_req_tag,mem_req_beats,mem_req_client};
 run_ce=0;cancel_request=1;result(17);cancel_request=0;
 if(!compute_fault_valid||done_live||done_result_bytes!=0)$fatal(1,"CANCEL failed to poison session");
 // This unit has no blockDMA and no accepted external CMD: a never-accepted
 // local request may be withdrawn. External CMD lifetime is tested separately.
 repeat(5)begin tick;if(mem_req_valid&&{mem_req_write,mem_req_verify,mem_req_offset,mem_req_tag,mem_req_beats,mem_req_client}!==offered)$fatal(1,"CANCEL changed a still-valid local descriptor");end
 reset_leaf;ack;
 task_config(102,8);start;result(16);if(!compute_fault_valid||done_live)$fatal(1,"watchdog lacked global reset request");reset_leaf;ack;
 task_config(103,100000);start;wait(mem_req_valid);@(negedge clk);session_reset_n=0;compute_running=0;result(18);
 reset_leaf;ack;
 task_config(104,100000);start;wait(mem_req_valid);@(negedge clk);bridge_fault=1;result(18);bridge_fault=0;reset_leaf;ack;
 // Deliberately injected graph/POST completions isolate the parent header and
 // response lifetime. They do not constitute a model or NMS verification.
 force dut.graph.start_valid=1'b0;force dut.g_start_ready=1'b1;
 force dut.g_done_valid=1'b1;force dut.g_status=32'd0;force dut.g_cmd=task_words[448+:32];force dut.g_epoch=epoch;force dut.g_frame=task_words[480+:64];
 force dut.g_cycles=64'd3;force dut.g_heads=32'h680000;force dut.g_table=32'h700000;force dut.g_result=32'h900000;force dut.g_alloc=67328;
 force dut.g_capacity=2100;force dut.g_sw=320;force dut.g_sh=320;force dut.g_rw=320;force dut.g_rh=320;force dut.g_pl=0;force dut.g_pt=0;
 force dut.g_table_crc=32'h79d84bc8;force dut.g_model_tag=32'h654dbb39;force dut.table_cache_hit=1'b1;
 force dut.post.start_valid=1'b0;force dut.p_start_ready=1'b1;force dut.p_engine_done=1'b1;force dut.p_status=0;force dut.p_detail=0;
 force dut.p_faces=0;force dut.p_crc=0;force dut.p_cmd=task_words[448+:32];force dut.p_bridge_epoch=epoch;force dut.p_frame=task_words[480+:64];force dut.p_total=64'd4;
 task_config(105,100000);start;wait(debug_stage==10);@(negedge clk);serve_header=1;
 // Header W/request/DONE are ordinary even with all arithmetic held.
 run_ce=0;result(0);serve_header=0;run_ce=1;
 if(header_beats!=4||done_faces!=0||done_crc!=0||done_result_bytes!=128||done_result_offset!=32'h900000||!done_live)$fatal(1,"empty successful private result");
 fd=$fopen({root_path,"/header.hex"},"w");for(i=0;i<128;i=i+1)$fdisplay(fd,"%02h",observed_header[8*i+:8]);$fclose(fd);
 reset_leaf;if(done_status!=0||tuple!==held)$fatal(1,"successful offered result rewritten by reset");ack;
 $display("PASS B03_FRAME_LIFETIME cases=%0d headerbeats=%0d",checks,header_beats);$finish;
end
initial begin #500000;$fatal(1,"lifetime watchdog state=%0d",debug_stage);end
endmodule
