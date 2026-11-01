`timescale 1ns/1ps
// White-box boundary test of the real vector transfer task. The frame test
// separately exercises all public operator/DDR paths and arithmetic bytes.
module tb_b03_vector_transfer;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,run_ce=0,cancel_request=0;
 wire req,done; wire [31:0] status,detail,offset,req_tag;
 wire wr; integer cases=0,c,a;
 b03_vector_exec_compact dut(
  .clk(clk),.rst_n(rst_n),.run_ce(run_ce),.cancel_request(cancel_request),
  .start_valid(1'b0),.start_ready(),.op_words(1024'd0),
  .workspace_base(32'd0),.src0_base(32'd0),.src1_base(32'd0),.dst_base(32'd0),.epoch(32'd0),.tag(32'd0),
  .done_valid(done),.done_ready(1'b0),.done_status(status),.done_detail(detail),.done_tag(),.done_op_id(),.cycles(),.busy(),.debug_stage(),
  .mem_req_valid(req),.mem_req_ready(1'b0),.mem_req_write(wr),.mem_req_verify(),.mem_req_offset(offset),.mem_req_tag(req_tag),.mem_req_beats(),.mem_req_client(),
  .mem_w_valid(),.mem_w_ready(1'b0),.mem_w_data(),.mem_w_strb(),.mem_w_last(),
  .mem_r_valid(1'b0),.mem_r_ready(),.mem_r_data(256'd0),.mem_r_last(1'b0),
  .mem_rsp_valid(1'b0),.mem_rsp_ready(),.mem_rsp_status(4'd0),.mem_rsp_tag(32'd0),
  .q_in_valid(),.q_in_ready(1'b0),.q_in_mask(),.q_in_psum(),.q_in_psum_b(),.q_in_bias(),.q_in_multiplier(),.q_in_multiplier_b(),
  .q_in_add(),.q_in_dtype(),.q_in_shift(),.q_in_tag(),.q_out_valid(1'b0),.q_out_ready(),.q_out_mask(8'd0),
  .q_out_values(128'd0),.q_out_error(24'd0),.q_out_tag(128'd0));
 task tick; begin @(posedge clk); #1; end endtask
 task check_transfer;
  input [31:0] address; input [7:0] count; input [31:0] next_tag; input cancel;
  reg bad; reg [63:0] end_address;
  begin
   @(negedge clk); rst_n=0;run_ce=0;cancel_request=0;tick;
   @(negedge clk);rst_n=1;dut.active=1;dut.next_tag=next_tag;
   dut.transfer(cases[0],address,count,2'd1,8'd10); #1;
   // An accepted descriptor must be registered before its range can cause a
   // request/completion. This fails on the original combinational check.
   if(req||done)$fatal(1,"transfer lacks registered validation barrier");
   repeat(2)begin tick;if(req||done)$fatal(1,"validation advanced with CE0");end
   @(negedge clk);cancel_request=cancel;run_ce=!cancel;tick;
   end_address={32'd0,address}+{56'd0,count};
   bad=count<1||count>128||end_address>64'h100000000||next_tag==32'hffffffff;
   if(cancel)begin
    if(!done||status!=17||req)$fatal(1,"cancel before issue");
   end else if(bad)begin
    if(!done||status!=11||detail!=32'h43494f42||req||dut.next_tag!=next_tag)$fatal(1,"invalid transfer issued");
   end else begin
    if(!req||done||offset!={address[31:5],5'd0}||req_tag!=next_tag||wr!=cases[0]||
       dut.io_remaining!=count||dut.next_tag!=next_tag+1)$fatal(1,"valid transfer mismatch");
    @(negedge clk);run_ce=0;
    repeat(2)begin tick;if(!req||offset!={address[31:5],5'd0}||req_tag!=next_tag)$fatal(1,"request not held");end
   end
   cases=cases+1;
  end
 endtask
 initial begin
  for(c=0;c<256;c=c+1)begin
   check_transfer(32'h1234567,c,32'd10,0);
   for(a=0;a<=256;a=a+1)check_transfer(32'hffffffff-a,c,32'hfffffffe,0);
  end
  check_transfer(0,128,32'hffffffff,0);
  check_transfer(32'hffffff80,128,1,1);
  check_transfer(32'hffffffff,128,1,1);
  $display("PASS B03_VECTOR_TRANSFER cases=%0d",cases);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
