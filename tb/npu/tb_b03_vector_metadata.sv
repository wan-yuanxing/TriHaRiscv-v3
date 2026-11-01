`timescale 1ns/1ps
// Check terminal decisions and qualified quantizer tags at real stage boundaries.
// Independent wide arithmetic covers carry/wrap; CE/cancel/fault paths are kept.
module tb_b03_vector_metadata;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,run_ce=0,cancel=0;
 reg qready=0,qvalid=0;reg [127:0] qtag=0;reg [7:0] qmask=0;reg [23:0] qerror=0;
 b03_vector_exec_compact dut(.clk(clk),.rst_n(rst_n),.run_ce(run_ce),.cancel_request(cancel),
 .start_valid(1'b0),.op_words(1024'd0),.workspace_base(32'd0),.src0_base(32'd0),.src1_base(32'd0),.dst_base(32'd0),.epoch(32'd0),.tag(32'd0),.done_ready(1'b0),
 .mem_req_ready(1'b0),.mem_w_ready(1'b0),.mem_r_valid(1'b0),.mem_r_data(256'd0),.mem_r_last(1'b0),.mem_rsp_valid(1'b0),.mem_rsp_status(4'd0),.mem_rsp_tag(32'd0),
 .start_ready(),.done_valid(),.done_status(),.done_detail(),.done_tag(),.done_op_id(),.cycles(),.busy(),.debug_stage(),.mem_req_valid(),.mem_req_write(),.mem_req_verify(),.mem_req_offset(),.mem_req_tag(),.mem_req_beats(),.mem_req_client(),.mem_w_valid(),.mem_w_data(),.mem_w_strb(),.mem_w_last(),.mem_r_ready(),.mem_rsp_ready(),.q_in_valid(),.q_in_mask(),.q_in_psum(),.q_in_psum_b(),.q_in_bias(),.q_in_multiplier(),.q_in_multiplier_b(),.q_in_add(),.q_in_dtype(),.q_in_shift(),.q_in_tag(),.q_out_ready(),
 .q_in_ready(qready),.q_out_valid(qvalid),.q_out_mask(qmask),.q_out_values(128'd0),.q_out_error(qerror),.q_out_tag(qtag));

 // White-box stage-boundary stimulus; arithmetic oracle uses a 64-bit sum.
 // Full memory/quantizer integration is checked separately by face_system.
 integer n,c,lim,count,terminal_cases=0,quant_cases=0,j;
 reg [31:0] seed=32'h4ac861fa,cur,total,remaining,nextcur;
 reg [63:0] sum;reg terminal;reg [127:0] expected;
 function[31:0] rnd(input[31:0] v);rnd=(v<<1)^(v[31]?32'h04c11db7:0);endfunction
 task reset_case;begin
  @(negedge clk);rst_n=0;run_ce=0;cancel=0;qready=0;qvalid=0;qerror=0;
  @(negedge clk);rst_n=1;
 end endtask
 initial begin
  for(n=0;n<8192;n=n+1)begin
   reset_case(); seed=rnd(seed);cur=seed;
   c=n%4==0?3:n%4==1?6:n%4==2?7:8;lim=c==6?16:c==8?64:128;
   case(n%8)
    0:remaining=0;1:remaining=1;2:remaining=lim-1;3:remaining=lim;
    4:remaining=lim+1;5:remaining=32'hffffffff;
    default:begin seed=rnd(seed);remaining=seed;end
   endcase
   total=cur+remaining;count=remaining>lim?lim:remaining;
   sum={32'd0,cur}+count;nextcur=sum[31:0];terminal=nextcur==total;
   dut.op=0;dut.op[0+:32]=c;dut.op[768+:32]=total;
   dut.plane=total;dut.cursor=cur;dut.state=9;dut.active=1;
   repeat(2)begin @(posedge clk);#1;if(dut.state!==9||dut.cursor!==cur)$fatal(1,"NEXT CE hold");end
   @(negedge clk);run_ce=1;@(posedge clk);#1;
   if(dut.chunk!==count[7:0])$fatal(1,"chunk oracle n=%0d",n);
   @(negedge clk);run_ce=0;dut.state=22;
   repeat(2)begin @(posedge clk);#1;if(dut.state!==22||dut.done_valid)$fatal(1,"ADVANCE CE hold");end
   @(negedge clk);run_ce=1;@(posedge clk);#1;
   if(terminal)begin if(!dut.done_valid||dut.done_status!==0||dut.cursor!==cur)$fatal(1,"terminal oracle n=%0d",n);end
   else if(dut.done_valid||dut.state!==9||dut.cursor!==nextcur)$fatal(1,"advance oracle n=%0d",n);
   terminal_cases=terminal_cases+1;
  end
  for(n=0;n<2048;n=n+1)begin
   reset_case();seed=rnd(seed);cur=seed;dut.op=0;dut.op[0+:32]=3;
   dut.op[928+:32]=32'h9123abef;dut.cursor=cur;dut.group_pos=(n%16)*8;
   dut.chunk=128;dut.saved_epoch=n;dut.saved_tag=32'had123400+n;
   dut.active=1;dut.state=12;
   sum={32'd0,cur}+((n%16)*8);expected={32'had123400+n,32'(n),32'h9123abef,sum[31:0]};
   repeat(2)begin @(posedge clk);#1;if(dut.state!==12)$fatal(1,"QPREP CE hold");end
   @(negedge clk);run_ce=1;@(posedge clk);#1;
   if(dut.state!==13)$fatal(1,"QPREP latency");
   @(posedge clk);#1;if(!dut.q_in_valid||dut.q_in_tag!==expected)$fatal(1,"qualified tag n=%0d",n);
   @(negedge clk);run_ce=0;
   repeat(2)begin @(posedge clk);#1;if(!dut.q_in_valid||dut.q_in_tag!==expected)$fatal(1,"QISSUE hold");end
   @(negedge clk);run_ce=1;qready=1;
   @(posedge clk);#1;if(!dut.q_out_ready)$fatal(1,"QWAIT latency");
   @(negedge clk);qtag=expected;qmask=dut.q_in_mask;qvalid=1;
   if(n%5==1)qtag=qtag^128'h100000000;
   if(n%5==2)qmask=qmask^1;
   if(n%5==3)qerror=1;
   if(n%5==4)cancel=1;
   run_ce=0;
   repeat(2)begin @(posedge clk);#1;if(!dut.q_out_ready||dut.done_valid)$fatal(1,"QWAIT CE hold");end
   @(negedge clk);run_ce=1;@(posedge clk);#1;
   if(n%5>=1&&n%5<=3)begin if(!dut.done_valid||dut.done_status!==22)$fatal(1,"bad quantizer response admitted");end
   else begin
    if(dut.done_valid||dut.bw_a!==0)$fatal(1,"valid quantizer response rejected");
    if(n%5==4)begin @(posedge clk);#1;if(!dut.done_valid||dut.done_status!==17)$fatal(1,"cancel not retired");end
   end
   quant_cases=quant_cases+1;
  end
  $display("VECTOR_METADATA_PASS terminal=%0d quant=%0d",terminal_cases,quant_cases);$finish;
 end
 initial begin #3000000;$fatal(1,"metadata timeout");end
endmodule

