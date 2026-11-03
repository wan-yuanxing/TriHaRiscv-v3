`timescale 1ns/1ps
module tb_face_mode_key;
 reg clk=0,rst=0,key=1;always #4 clk=~clk;
 wire [1:0] requested;
`ifdef LEGACY
 assign requested=0;
`else
 triha_face_mode_key #(.CLOCK_HZ(1000),.STABLE_MS(4)) key_owner(.clk_i(clk),.rst_ni(rst),.button_ni(key),.mode_o(requested));
`endif
 reg arvalid=0,rready=0,awvalid=0,wvalid=0,bready=0;
 reg [31:0] araddr=0,awaddr=0;
 wire arready,rvalid,awready,wready,bvalid;
 wire [31:0] rdata;wire [1:0] rresp,bresp;
 video_display_mmio_compact
`ifndef LEGACY
 #(.ENABLE_MODE_KEY(1))
`endif
 dut(.clk_i(clk),.rst_ni(rst),
`ifndef LEGACY
 .mode_request_i(requested),
`endif
 .s_axi_araddr_i(araddr),.s_axi_arprot_i(3'd0),.s_axi_arvalid_i(arvalid),.s_axi_arready_o(arready),
 .s_axi_rdata_o(rdata),.s_axi_rresp_o(rresp),.s_axi_rvalid_o(rvalid),.s_axi_rready_i(rready),
 .s_axi_awaddr_i(awaddr),.s_axi_awprot_i(3'd0),.s_axi_awvalid_i(awvalid),.s_axi_awready_o(awready),
 .s_axi_wdata_i(32'd2),.s_axi_wstrb_i(4'hf),.s_axi_wvalid_i(wvalid),.s_axi_wready_o(wready),
 .s_axi_bresp_o(bresp),.s_axi_bvalid_o(bvalid),.s_axi_bready_i(bready),
 .modes_i(3'b111),.asset_ready_i(1'b0),.asset_id_i(32'd1),.asset_generation_i(32'd1),
 .cmd_ready_i(1'b0),.feedback_valid_i(1'b0),.feedback_slot_i(2'd0),.feedback_mode_i(2'd0),
 .feedback_frame_i(32'd0),.feedback_generation_i(32'd0),.feedback_seq_i(32'd0),
 .retire_valid_i(1'b0),.retire_slot_i(2'd0),.retire_frame_i(32'd0),.retire_generation_i(32'd0),
 .submit_enable_i(1'b1),.external_fault_i(1'b0));
 integer checks=0,epoch;
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"FACE_MODE_KEY_FAIL %s",why);end endtask
 task read_word(input integer offset,input integer expected);begin
  @(negedge clk);araddr=32'h20011000+offset;arvalid=1;
  @(posedge clk);while(!arready)@(posedge clk);
  @(negedge clk);arvalid=0;wait(rvalid);#1;
  check(rresp==0&&rdata==expected,"CPU mode observation");
  repeat(5)begin @(negedge clk);check(rvalid&&rdata==expected&&rresp==0,"AXI response held");end
  rready=1;@(negedge clk);rready=0;
 end endtask
 task dwell(input bit level,input integer n);begin @(negedge clk);key=level;repeat(n)@(negedge clk);end endtask
 initial begin
  for(epoch=0;epoch<2;epoch++)begin
   rst=0;key=1;repeat(4)@(negedge clk);rst=1;repeat(170)@(negedge clk);
   read_word('h84,0);read_word(4,31);
   dwell(0,1);dwell(1,12);read_word('h84,0);
   dwell(0,25);read_word('h84,1);dwell(0,100);read_word('h84,1);
   dwell(1,1);dwell(0,25);read_word('h84,1); // release bounce cannot rearm
   dwell(1,12);dwell(0,12);read_word('h84,2);
   dwell(1,12);dwell(0,12);read_word('h84,0);dwell(1,12);
   @(negedge clk);awaddr=32'h20011084;awvalid=1;wvalid=1;
   @(posedge clk);while(!(awready&&wready))@(posedge clk);
   @(negedge clk);awvalid=0;wvalid=0;wait(bvalid);#1;check(bresp==2,"key observation is read-only");
   @(negedge clk);bready=1;@(negedge clk);bready=0;read_word('h84,0);
  end
  $display("FACE_MODE_KEY_PASS checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"FACE_MODE_KEY_TIMEOUT");end
endmodule
