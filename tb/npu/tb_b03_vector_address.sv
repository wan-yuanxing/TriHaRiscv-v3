`timescale 1ns/1ps
// Exercise the actual vector TREAD address register against an independent
// 64-bit multiply/add oracle, including wrap, dtype decode and CE stalls.
module tb_b03_vector_address;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,run_ce=0;
 b03_vector_exec_compact dut(.clk(clk),.rst_n(rst_n),.run_ce(run_ce),.cancel_request(1'b0),
 .start_valid(1'b0),.op_words(1024'd0),.workspace_base(32'd0),.src0_base(32'd0),.src1_base(32'd0),.dst_base(32'd0),.epoch(32'd0),.tag(32'd0),.done_ready(1'b0),
 .mem_req_ready(1'b0),.mem_w_ready(1'b0),.mem_r_valid(1'b0),.mem_r_data(256'd0),.mem_r_last(1'b0),.mem_rsp_valid(1'b0),.mem_rsp_status(4'd0),.mem_rsp_tag(32'd0),
 .start_ready(),.done_valid(),.done_status(),.done_detail(),.done_tag(),.done_op_id(),.cycles(),.busy(),.debug_stage(),.mem_req_valid(),.mem_req_write(),.mem_req_verify(),.mem_req_offset(),.mem_req_tag(),.mem_req_beats(),.mem_req_client(),.mem_w_valid(),.mem_w_data(),.mem_w_strb(),.mem_w_last(),.mem_r_ready(),.mem_rsp_ready(),.q_in_valid(),.q_in_mask(),.q_in_psum(),.q_in_psum_b(),.q_in_bias(),.q_in_multiplier(),.q_in_multiplier_b(),.q_in_add(),.q_in_dtype(),.q_in_shift(),.q_in_tag(),.q_out_ready(),
 .q_in_ready(1'b0),.q_out_valid(1'b0),.q_out_mask(8'd0),.q_out_values(128'd0),.q_out_error(24'd0),.q_out_tag(128'd0));
 integer n,d,c,cases=0;reg[31:0] seed=32'h8265ad01,p,x,base,old_address;reg[63:0] expected;integer scale,channel_scale;
 function[31:0] next_random(input[31:0] v);begin next_random=(v<<1)^((v[31])?32'h04c11db7:0);end endfunction
 initial begin
  repeat(2)@(negedge clk);rst_n=1;
  for(n=0;n<128;n=n+1)for(d=0;d<8;d=d+1)for(c=0;c<8;c=c+1)begin
   @(negedge clk);run_ce=0;
   seed=next_random(seed);p=n<8?(32'hffffffff>>n):seed;
   seed=next_random(seed);x=n<8?(32'h80000000>>n):seed;
   seed=next_random(seed);base=seed;
   dut.op=0;dut.op[160+:32]=d;dut.src0=base;dut.plane=p;dut.cursor=x;dut.channel=c;dut.chunk=16;dut.state=18;dut.active=1;
   old_address=dut.io_address;
   @(posedge clk);#1;if(dut.io_address!==old_address||dut.state!==18)$fatal(1,"VECTOR_ADDRESS CE0 advanced");
   @(negedge clk);run_ce=1;
   scale=(d==3||d==4)?2:1;channel_scale=c<3?c:3;
   expected={32'd0,base}+({32'd0,p}*channel_scale*scale)+({32'd0,x}*scale);
   @(posedge clk);#1;
   if(dut.io_address!==expected[31:0]||dut.state!==32||dut.io_remaining!==(d==3||d==4?8'd32:8'd16))
    $fatal(1,"VECTOR_ADDRESS dtype=%0d ch=%0d base=%h plane=%h cursor=%h actual=%h expected=%h",d,c,base,p,x,dut.io_address,expected[31:0]);
   cases=cases+1;
  end
  $display("PASS B03_VECTOR_ADDRESS cases=%0d",cases);$finish;
 end
 initial begin #1000000;$fatal(1,"VECTOR_ADDRESS timeout");end
endmodule
