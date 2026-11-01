// Derived from frozen upstream TB SHA256 f9022e2bf1a74643d0e383e90d52a221c781383a4d9d53058bbc11fbb4efbbd2.
// All public outputs are compared cycle-for-cycle against the unchanged payload RTL.
`timescale 1ns/1ps
module tb_b03_input_plan #(parameter integer TRUSTED_MODEL=0);
    GTP_GRS GRS_INST(.GRS_N(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,run_ce=0,cancel_request=0;
    reg cmd_valid=0;wire cmd_ready;reg[1:0]cmd_kind=0;reg[1023:0]op_words=0;
    reg[31:0]workspace_base=32'h100000,resolved_src_base=32'h10000,epoch=1,cmd_tag=0;
    reg[8:0]row_y=0,x_begin=0;reg[4:0]m_count=0;
    wire done_valid;reg done_ready=0;wire[31:0]done_status,done_detail,done_tag;
    wire param_valid,rows_valid,a_valid;reg[2:0]param_group=0;wire[255:0]bias_flat,mult_flat;wire[47:0]shift_flat;wire[63:0]shadow_valid;wire[95:0]aux_coeff;
    reg a_req_valid=0,b_req_valid=0,dw_req_valid=0;wire a_req_ready,b_req_ready,dw_req_ready;
    reg[9:0]a_req_row=0,b_req_row=0;reg[31:0]a_req_tag=0,b_req_tag=0,dw_req_tag=0;
    wire a_rsp_valid,b_rsp_valid,dw_rsp_valid,a_rsp_error,b_rsp_error,dw_rsp_error;
    wire[127:0]a_rsp_data,b_rsp_data,dw_rsp_data;wire[31:0]a_rsp_tag,b_rsp_tag,dw_rsp_tag;
    reg[3:0]dw_req_tap=0;reg[8:0]dw_req_ox=0;reg[6:0]dw_req_co_base=0;
    wire mem_req_valid;wire mem_req_ready=0;wire mem_req_write,mem_req_verify;
    wire[31:0]mem_req_offset,mem_req_tag;wire[4:0]mem_req_beats;wire[2:0]mem_req_client;
    wire mem_w_valid,mem_w_last;reg mem_w_ready=0;wire[255:0]mem_w_data;wire[31:0]mem_w_strb;
    reg mem_r_valid=0,mem_r_last=0;wire mem_r_ready;reg[255:0]mem_r_data=0;
    reg mem_rsp_valid=0;wire mem_rsp_ready;reg[3:0]mem_rsp_status=0;reg[31:0]mem_rsp_tag=0;
    wire busy,reset_required;wire[7:0]debug_state;wire[31:0]cycles,read_bytes;
    b03_model_input_payload #(.TRUSTED_MODEL(TRUSTED_MODEL)) dut(.*);

integer n,page_left,left,beats,cases=0;
reg [31:0] base,bytes,offset,next_offset,seed=32'hfe1ca031;
reg [32:0] bound;
reg [22:0] remaining;
reg invalid;
function [31:0] rand32;
begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rand32=seed;end
endfunction
task tick;begin @(posedge clk);#1;end endtask
initial begin
 for(n=0;n<4096;n=n+1)begin
  @(negedge clk);rst_n=0;run_ce=0;repeat(2)@(negedge clk);rst_n=1;
  base=rand32()&32'h3fffffe0;bytes=rand32()&32'h007fffe0;offset=rand32()&32'h007fffe0;
  case(n%8)
   0:begin base=32'h100fe0;bytes=1024;offset=0;end
   1:begin base=32'h100000;bytes=512;offset=480;end
   2:begin base=32'h3fffffe0;bytes=32;offset=0;end
   3:begin base=32'h100000;bytes=32'h7fffe0;offset=32'h7fffc0;end
   4:begin base=32'h100000;bytes=32'h7fffe0;offset=32'h7fffe0;end
   5:begin base=32'h100fe0;bytes=1024;offset=992;end
   default:begin end
  endcase
  remaining=bytes-offset;page_left=128-(((base+offset)>>5)&127);left=remaining/32;
  beats=left;if(beats>16)beats=16;if(beats>page_left)beats=page_left;
  next_offset=offset+32*beats;bound={1'b0,base}+{1'b0,bytes};
  invalid=(bytes==0||bound>33'h040000000||beats==0);
  dut.state=4;dut.active=1;dut.captured_epoch=epoch;dut.kind=0;dut.part=0;
  dut.pbase=base;dut.pbytes=bytes;dut.region_done=offset;run_ce=1;
  tick();
  if(invalid)begin
   if(!done_valid||done_status!=8||done_detail!=9)$fatal(1,"PLAN rejection n=%0d",n);
  end else begin
   if(!mem_req_valid||mem_req_offset!==(base+offset)||mem_req_beats!==beats[4:0])$fatal(1,"PLAN burst n=%0d",n);
   @(negedge clk);dut.offer=0;dut.inflight=0;dut.rsp_seen=1;run_ce=0;
   tick();if(debug_state!==5)$fatal(1,"TRANSFER pause n=%0d",n);
   @(negedge clk);run_ce=1;tick();
   if(next_offset<bytes)begin
    if(debug_state!==4||dut.region_done!==next_offset[22:0])$fatal(1,"continue n=%0d",n);
   end else if(debug_state!==dut.PARAM_NEXT)$fatal(1,"end n=%0d",n);
  end
  cases=cases+1;
 end
 $display("INPUT_PLAN_PASS cases=%0d",cases);$finish;
end
initial begin #1000000;$fatal(1,"input plan timeout");end
endmodule
