`timescale 1ns/1ps
`default_nettype none
module tb_video_record_compact #(parameter integer CASE_ID=0,parameter real PIXEL_HALF=12.5);
 reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0;
 always #4 core_clk=~core_clk;
 initial begin #3;forever #(PIXEL_HALF)pixel_clk=~pixel_clk;end
 reg cmd_valid=0,commit_ready=0,pixel_cmd_ready=0,pixel_commit=0;
 reg [1:0] cmd_mode=0,cmd_slot=0;
 reg [31:0] cmd_seq=0,cmd_frame_id=0,cmd_generation=0;
 reg [5119:0] cmd_data=0;
 wire cmd_ready,commit_valid,pixel_cmd_valid,pixel_waiting_commit,pixel_protocol_error,protocol_error;
 wire [1:0] commit_mode,commit_slot,pixel_cmd_mode,pixel_cmd_slot;
 wire [31:0] commit_seq,commit_frame_id,commit_generation,pixel_cmd_seq,pixel_cmd_frame_id,pixel_cmd_generation;
 wire [5119:0] commit_data,pixel_cmd_data;
`ifdef BASELINE
 display_mode_cdc #(.CONTEXT_WIDTH(5120)) dut(.*);
`else
 display_mode_cdc_held #(.CONTEXT_WIDTH(5120)) dut(.*);
`endif
 integer transactions=0,i;reg [5119:0] expected;
 task automatic offer(input integer n);
  begin
   @(negedge core_clk);cmd_seq=n;cmd_frame_id=n+10;cmd_generation=47;cmd_slot=n%3;cmd_mode=n%3;
   for(i=0;i<160;i=i+1)cmd_data[i*32+:32]=32'(n*901+i*7919);
   expected=cmd_data;cmd_valid=1;
   do @(posedge core_clk);while(!cmd_ready);
   @(negedge core_clk);cmd_valid=0;
  end
 endtask
 task automatic complete;
  begin
   wait(pixel_cmd_valid);repeat(11)@(negedge pixel_clk);
   if(cmd_ready||commit_valid||pixel_waiting_commit||pixel_cmd_data!==expected||pixel_cmd_seq!==cmd_seq)$fatal(1,"HELD_OFFER_PREMATURE_OR_CORRUPT");
   pixel_cmd_ready=1;@(negedge pixel_clk);pixel_cmd_ready=0;
   repeat(13)@(negedge pixel_clk);
   if(!pixel_waiting_commit||commit_valid)$fatal(1,"HELD_COMMIT_BEFORE_PIXEL_PROOF");
   pixel_commit=1;@(negedge pixel_clk);pixel_commit=0;
   wait(commit_valid);repeat(19)@(negedge core_clk);
   if(cmd_ready||commit_data!==expected||commit_seq!==cmd_seq||commit_frame_id!==cmd_frame_id)$fatal(1,"HELD_FEEDBACK_NOT_STABLE");
   commit_ready=1;@(negedge core_clk);commit_ready=0;
   repeat(3)@(negedge core_clk);if(!cmd_ready||commit_valid)$fatal(1,"HELD_RELEASE_STUCK");
   transactions=transactions+1;
  end
 endtask
 initial begin
  repeat(6)@(negedge core_clk);core_reset_n=1;repeat(4)@(negedge pixel_clk);pixel_reset_n=1;
  offer(1);
  if(CASE_ID==1)begin
   wait(pixel_cmd_valid);@(negedge core_clk);cmd_data[5119]=~cmd_data[5119];
   repeat(10)@(negedge core_clk);$fatal(1,"SOURCE_VIOLATION_NOT_DETECTED");
  end
  if(CASE_ID==2)begin
   wait(pixel_cmd_valid);@(negedge core_clk);core_reset_n=0;
   repeat(4)@(negedge pixel_clk);core_reset_n=1;
   repeat(8)@(negedge pixel_clk);
   if(pixel_cmd_valid||pixel_waiting_commit||commit_valid||protocol_error)$fatal(1,"RESET_RESURRECTED_PENDING_RECORD");
   @(negedge pixel_clk);pixel_reset_n=0;repeat(4)@(negedge core_clk);pixel_reset_n=1;
   repeat(8)@(negedge pixel_clk);offer(2);
  end
  complete();offer(3);complete();
  if(protocol_error||pixel_protocol_error)$fatal(1,"HELD_PROTOCOL_ERROR");
  $display("VIDEO_RECORD_COMPACT_CDC_PASS case=%0d transactions=%0d",CASE_ID,transactions);$finish;
 end
 initial begin #100000;$fatal(1,"HELD_WATCHDOG");end
endmodule
`default_nettype wire
