`timescale 1ns/1ps
module tb_video_display_health #(parameter integer CASE_ID=0);
 reg clk_i=0,rst_ni=0;always #4 clk_i=~clk_i;
 reg [31:0] s_axi_awaddr_i=0,s_axi_wdata_i=0,s_axi_araddr_i=0;
 reg [2:0] s_axi_awprot_i=0,s_axi_arprot_i=0;reg [3:0] s_axi_wstrb_i=15;
 reg s_axi_awvalid_i=0,s_axi_wvalid_i=0,s_axi_bready_i=1,s_axi_arvalid_i=0,s_axi_rready_i=1;
 wire s_axi_awready_o,s_axi_wready_o,s_axi_bvalid_o,s_axi_arready_o,s_axi_rvalid_o;
 wire [1:0] s_axi_bresp_o,s_axi_rresp_o;wire [31:0] s_axi_rdata_o;
 reg [2:0] modes_i=7;reg asset_ready_i=1;reg [31:0] asset_id_i=7,asset_generation_i=71;
 reg submit_enable_i=1,external_fault_i=0;wire fault_o;wire [7:0] fault_code_o;
 wire cmd_valid_o,cmd_mode_only_o;reg cmd_ready_i=0;wire [1:0] cmd_slot_o,cmd_mode_o;
 wire [31:0] cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o;wire [5119:0] cmd_data_o;
 reg feedback_valid_i=0;wire feedback_ready_o;reg [1:0] feedback_slot_i=0,feedback_mode_i=0;
 reg [31:0] feedback_frame_i=1,feedback_generation_i=10,feedback_seq_i=1;
 reg retire_valid_i=0;wire retire_ready_o;reg [1:0] retire_slot_i=0;reg [31:0] retire_frame_i=0,retire_generation_i=0;
 wire irq_o;reg [31:0] value;integer checks=0,i;
 video_display_mmio #(.EXTERNAL_HEALTH(1)) dut(.*);
 task automatic wr(input [31:0] off,data,input [1:0] response);
  begin @(negedge clk_i);s_axi_awaddr_i=32'h20011000+off;s_axi_wdata_i=data;s_axi_awvalid_i=1;s_axi_wvalid_i=1;
   do @(posedge clk_i);while(!(s_axi_awready_o&&s_axi_wready_o));@(negedge clk_i);s_axi_awvalid_i=0;s_axi_wvalid_i=0;
   wait(s_axi_bvalid_o);if(s_axi_bresp_o!==response)$fatal(1,"HEALTH_WRITE off=%h got=%h wanted=%h",off,s_axi_bresp_o,response);@(negedge clk_i);checks=checks+1;end
 endtask
 task automatic rd(input [31:0] off);
  begin @(negedge clk_i);s_axi_araddr_i=32'h20011000+off;s_axi_arvalid_i=1;
   do @(posedge clk_i);while(!s_axi_arready_o);@(negedge clk_i);s_axi_arvalid_i=0;wait(s_axi_rvalid_o);
   if(s_axi_rresp_o)$fatal(1,"HEALTH_READ");value=s_axi_rdata_o;@(negedge clk_i);checks=checks+1;end
 endtask
 initial begin
  repeat(6)@(negedge clk_i);rst_ni=1;
  for(i=0;i<160;i=i+1)begin
   case(i)
    0:value=65536;1:value=640;3,10:value=1;4,11:value=10;5:value=32'h82000000;6:value=2400;7:value=800;8:value=600;9:value=3;default:value=0;
   endcase wr(32'h100+i*4,value,0);
  end
  wr('h24,0,0);wr('h28,1,0);wr('h10,8,0);
  if(CASE_ID==0||CASE_ID==5)begin
   external_fault_i=1;wr('h20,1,2);repeat(5)@(negedge clk_i);
  end else if(CASE_ID==1)begin
   submit_enable_i=0;wr('h20,1,2);rd('h14);if(value||fault_o||dut.submits)$fatal(1,"HEALTH_OFFLINE_SIDE_EFFECT");
   submit_enable_i=1;wr('h20,1,0);wait(cmd_valid_o);if(dut.submits!=1||fault_o)$fatal(1,"HEALTH_ONLINE_NOT_ACCEPTED");
  end else if(CASE_ID==2||CASE_ID==3)begin
   wr('h20,1,0);if(CASE_ID==3)wait(dut.phase==2);@(negedge clk_i);external_fault_i=1;repeat(40)@(negedge clk_i);
   if(dut.submits||cmd_valid_o||dut.slot_free!=7)$fatal(1,"HEALTH_RESERVED_AFTER_FAULT");wr('h100,123,2);
  end else if(CASE_ID==4)begin
   wr('h20,1,0);wait(cmd_valid_o);@(negedge clk_i);cmd_ready_i=1;@(negedge clk_i);cmd_ready_i=0;
   feedback_valid_i=1;do @(posedge clk_i);while(!feedback_ready_o);@(negedge clk_i);feedback_valid_i=0;
   rd('h14);if(value!=1)$fatal(1,"HEALTH_BASELINE_COMMIT");external_fault_i=1;repeat(5)@(negedge clk_i);
   rd('h14);if(value!=9)$fatal(1,"HEALTH_HISTORY_LOST");wr('h18,1,0);rd('h14);if(value!=8)$fatal(1,"HEALTH_ACK_BLOCKED");wr('h18,8,2);
  end
  if(CASE_ID!=1)begin
   if(CASE_ID==5)begin external_fault_i=0;repeat(5)@(negedge clk_i);end
   rd('h14);if(!(value&8)||!fault_o||fault_code_o!=8'hf0||!irq_o)$fatal(1,"HEALTH_FAULT_NOT_STICKY");
   rd('hc);if(value!=8'hf0)$fatal(1,"HEALTH_ERROR_CODE");wr('h20,1,2);
   if(CASE_ID!=4&&dut.slot_free!=7)$fatal(1,"HEALTH_FAULT_SLOT_RESERVED");
  end
  $display("VIDEO_DISPLAY_HEALTH_PASS case=%0d checks=%0d",CASE_ID,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"HEALTH_TIMEOUT");end
endmodule
