`timescale 1ns/1ps
module tb_display_record_link #(parameter integer CASE_ID=0);
 reg clk=0,reset_n=0;always #4 clk=~clk;
 reg cmd_valid=0,cmd_mode_only=0;wire cmd_ready;reg [1:0] cmd_slot=0,cmd_mode=0;
 reg [31:0] cmd_frame=1,cmd_generation=10,cmd_base=32'h82000000,cmd_stride=2400,cmd_seq=1;reg [5119:0] cmd_data=0;
 wire record_valid;reg record_ready=0;wire [31:0] record_base,record_stride,record_frame,record_generation;wire [1:0] record_slot;
 wire r_cmd_valid;reg r_cmd_ready=0;wire [1:0] r_cmd_mode,r_cmd_slot;wire [31:0] r_cmd_frame,r_cmd_generation,r_cmd_seq;wire [5119:0] r_cmd_data;
 reg raw_commit_valid=0;wire raw_commit_ready;reg [31:0] raw_commit_frame=1,raw_commit_generation=10;reg [1:0] raw_commit_slot=0;
 reg raw_release_valid=0;wire raw_release_ready;reg [31:0] raw_release_frame=1,raw_release_generation=10;reg [1:0] raw_release_slot=0;
 reg p_commit_valid=0;wire p_commit_ready;reg [1:0] p_commit_mode=0,p_commit_slot=0;reg [31:0] p_commit_frame=1,p_commit_generation=10,p_commit_seq=1;
 reg p_retire_valid=0,p_retire_raw=1,p_retire_asset=0;wire p_retire_ready;reg [1:0] p_retire_slot=0;
 reg [31:0] p_retire_frame=1,p_retire_generation=10,p_retire_seq=1,p_retire_asset_id=7,p_retire_asset_generation=71;
 wire feedback_valid;reg feedback_ready=0;wire [1:0] feedback_slot,feedback_mode;wire [31:0] feedback_frame,feedback_generation,feedback_seq;
 wire retire_valid;reg retire_ready=0;wire [1:0] retire_slot;wire [31:0] retire_frame,retire_generation;
 wire asset_retire_valid;reg asset_retire_ready=0;wire [1:0] asset_retire_slot;
 wire [31:0] asset_retire_frame,asset_retire_generation,asset_retire_seq,asset_retire_id,asset_retire_generation_id;
 reg raw_error=0,renderer_fault=0;wire fault;wire [7:0] fault_code;
 display_record_link dut(.*);
 integer commits=0,retires=0;
 task automatic offer(input integer slot,frame,generation,seq,mode,input bit only);
  begin @(negedge clk);cmd_slot=slot;cmd_frame=frame;cmd_generation=generation;cmd_seq=seq;cmd_mode=mode;cmd_mode_only=only;cmd_base=32'h82000000+slot*32'h200000;
   cmd_valid=1;do @(posedge clk);while(!cmd_ready);@(negedge clk);cmd_valid=0;
   wait(r_cmd_valid);repeat(4)begin @(negedge clk);if(!r_cmd_valid||r_cmd_generation!=generation||r_cmd_seq!=seq)$fatal(1,"LINK_RENDER_OFFER_HOLD");end
   r_cmd_ready=1;@(negedge clk);r_cmd_ready=0;
   if(!only)begin wait(record_valid);repeat(4)begin @(negedge clk);if(!record_valid||record_generation!=generation)$fatal(1,"LINK_RAW_OFFER_HOLD");end record_ready=1;@(negedge clk);record_ready=0;end
  end
 endtask
 task automatic raw_commit(input integer slot,frame,generation);
  begin @(negedge clk);raw_commit_slot=slot;raw_commit_frame=frame;raw_commit_generation=generation;raw_commit_valid=1;
   @(negedge clk);raw_commit_valid=0;end
 endtask
 task automatic pixel_commit(input integer slot,frame,generation,seq,mode);
  begin @(negedge clk);p_commit_slot=slot;p_commit_frame=frame;p_commit_generation=generation;p_commit_seq=seq;p_commit_mode=mode;p_commit_valid=1;
   @(negedge clk);p_commit_valid=0;end
 endtask
 task automatic feedback(input integer slot,frame,generation,seq,mode);
  begin wait(feedback_valid);repeat(10)begin @(negedge clk);if(!feedback_valid||{feedback_slot,feedback_frame,feedback_generation,feedback_seq,feedback_mode}!=={2'(slot),32'(frame),32'(generation),32'(seq),2'(mode)})$fatal(1,"LINK_FEEDBACK_HOLD");end
   feedback_ready=1;@(negedge clk);feedback_ready=0;commits=commits+1;end
 endtask
 initial begin
  repeat(5)@(negedge clk);reset_n=1;
  cmd_data[9*32+:32]=29;cmd_data[14*32+:32]=7;cmd_data[15*32+:32]=71;
  if(CASE_ID==6)begin
   // Every identity bit independently rejects the proof before any feedback.
   for(integer bitno=0;bitno<100;bitno=bitno+1)begin
    @(negedge clk);reset_n=0;raw_commit_valid=0;p_commit_valid=0;
    repeat(3)@(negedge clk);reset_n=1;
    offer(0,1,10,1,2,0);raw_commit(0,1,10);
    @(negedge clk);
    {p_commit_slot,p_commit_mode,p_commit_frame,p_commit_generation,p_commit_seq}=
      {2'd0,2'd2,32'd1,32'd10,32'd1}^(100'd1<<bitno);
    p_commit_valid=1;@(negedge clk);p_commit_valid=0;
    if(!fault||fault_code!=4||feedback_valid||retire_valid)$fatal(1,"IDENTITY_BIT_REJECTION %0d",bitno);
   end
   $display("DISPLAY_RECORD_LINK_PASS case=6 identity_bits=100");$finish;
  end
  offer(0,1,10,1,2,0);
  if(CASE_ID==1)begin raw_commit(0,1,11);wait(fault);if(feedback_valid)$fatal(1,"LINK_WRONG_COMMIT_PUBLISHED");end
  else begin
   if(CASE_ID==4)begin pixel_commit(0,1,10,1,2);repeat(10)begin @(negedge clk);if(feedback_valid)$fatal(1,"LINK_MISSING_RAW_COMMIT");end raw_commit(0,1,10);end
   else begin raw_commit(0,1,10);repeat(10)begin @(negedge clk);if(feedback_valid)$fatal(1,"LINK_MISSING_PIXEL_COMMIT");end pixel_commit(0,1,10,1,2);end
   feedback(0,1,10,1,2);
   if(CASE_ID==5)begin raw_commit(0,1,10);wait(fault);end
   else begin
    offer(1,2,20,2,0,0);fork raw_commit(1,2,20);pixel_commit(1,2,20,2,0);join
    if(CASE_ID!=4)begin @(negedge clk);raw_release_valid=1;raw_release_generation=CASE_ID==2?11:10;@(negedge clk);raw_release_valid=0;end
    if(CASE_ID==2)begin wait(fault);if(retire_valid)$fatal(1,"LINK_WRONG_RAW_RELEASE");end
    else begin
     repeat(10)begin @(negedge clk);if(retire_valid)$fatal(1,"LINK_EARLY_RETIRE_ONE_PROOF");end
     p_retire_generation=CASE_ID==3?11:10;p_retire_asset=1;p_retire_valid=1;@(negedge clk);p_retire_valid=0;
     if(CASE_ID==3)begin wait(fault);if(retire_valid)$fatal(1,"LINK_WRONG_PIXEL_RELEASE");end
     else begin
      if(CASE_ID==4)begin repeat(10)begin @(negedge clk);if(retire_valid)$fatal(1,"LINK_MISSING_RAW_RELEASE");end raw_release_valid=1;@(negedge clk);raw_release_valid=0;end
      repeat(10)begin @(negedge clk);if(retire_valid)$fatal(1,"LINK_RETIRE_BEFORE_OWNER_COMMIT");end
      feedback(1,2,20,2,0);wait(retire_valid);
      repeat(20)begin @(negedge clk);if(!retire_valid||{retire_slot,retire_frame,retire_generation}!=={2'd0,32'd1,32'd10}||!asset_retire_valid||asset_retire_id!=7||asset_retire_generation_id!=71)$fatal(1,"LINK_RETIRE_ID_HOLD");end
      retire_ready=1;@(negedge clk);retire_ready=0;retires=retires+1;asset_retire_ready=1;@(negedge clk);asset_retire_ready=0;
      offer(1,2,20,3,2,1);if(record_valid)$fatal(1,"LINK_MODE_ONLY_RAW_RESUBMIT");pixel_commit(1,2,20,3,2);feedback(1,2,20,3,2);
      repeat(20)begin @(negedge clk);if(retire_valid||fault)$fatal(1,"LINK_FINAL_HEALTH");end
      offer(1,2,20,4,0,1);pixel_commit(1,2,20,4,0);feedback(1,2,20,4,0);
      @(negedge clk);p_retire_slot=1;p_retire_frame=2;p_retire_generation=20;p_retire_seq=3;p_retire_raw=0;p_retire_asset=1;p_retire_valid=1;
      @(negedge clk);p_retire_valid=0;wait(asset_retire_valid);repeat(10)@(negedge clk);
      if(retire_valid||fault||asset_retire_seq!=3)$fatal(1,"LINK_ASSET_ONLY_RETIRE");asset_retire_ready=1;@(negedge clk);asset_retire_ready=0;
      p_retire_valid=1;@(negedge clk);p_retire_valid=0;wait(fault);if(asset_retire_valid)$fatal(1,"LINK_DUPLICATE_ASSET_FORWARDED");
     end
    end
   end
  end
  $display("DISPLAY_RECORD_LINK_PASS case=%0d commits=%0d retires=%0d fault=%0d",CASE_ID,commits,retires,fault);$finish;
 end
 initial begin #200000;$fatal(1,"LINK_TIMEOUT");end
endmodule
