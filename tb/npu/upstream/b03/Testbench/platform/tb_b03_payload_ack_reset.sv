`timescale 1ns/1ps
// Parent lifetime/control unit only: successful graph/POST completions are
// explicitly injected. Real full inference is verified in full_frame_proxy.
module tb_b03_payload_ack_reset;
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
wire[175:0]post_fault_payload;
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
wire p_abort_req,p_quarantined;
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
initial begin
 repeat(4)tick;board_reset_n=1;session_reset_n=1;compute_running=1;repeat(3)tick;
 task_config(201,100000);start;wait(mem_req_valid);@(negedge clk);cancel_request=1;result(17);cancel_request=0;
 if(!compute_fault_valid)$fatal(1,"setup did not hold frame fault");
 // One compute edge sees both complete session-reset level and result ACK.
 // This isolates the parent lifetime boundary; no external CMD was accepted.
 session_reset_n=0;compute_running=0;done_ready=1;tick;
 if(done_valid||compute_fault_valid)$fatal(1,"reset/ACK did not clear flags");
 session_reset_n=1;compute_running=1;done_ready=0;epoch=epoch+1;repeat(4)tick;
 if(!start_ready)$fatal(1,"ACK_RESET_OVERLAP_STUCK state=%0d done=%b fault=%b active=%b",dut.state,done_valid,compute_fault_valid,dut.active);
 $display("PASS B03_FRAME_ACK_RESET_OVERLAP");$finish;
end
initial begin #500000;$fatal(1,"overlap watchdog");end
endmodule
