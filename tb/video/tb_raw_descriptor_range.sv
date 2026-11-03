`timescale 1ns/1ps
`default_nettype none
// Python supplies an independent unbounded byte-address oracle. Clocks remain
// stopped: this test isolates admission; tb_raw_display covers the protocol.
module tb_raw_descriptor_range;
 parameter integer W=800,H=600,COUNT=1;
 reg [31:0] base,stride,frame;
 reg [1:0] slot;
 reg expected;
 reg [98:0] vectors[0:COUNT-1];
 reg [1023:0] filename;
 integer i;
 raw_display #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H)) dut(
  .core_clk(1'b0),.pixel_clk(1'b0),.core_reset_n(1'b0),.pixel_reset_n(1'b0),
  .record_base(base),.record_stride(stride),.record_frame_id(frame),.record_slot(slot));
 initial begin
  if(!$value$plusargs("VECTORS=%s",filename))$fatal(1,"missing vectors");
  $readmemh(filename,vectors);
  for(i=0;i<COUNT;i=i+1)begin
   {base,stride,frame,slot,expected}=vectors[i];#1;
   if(dut.descriptor_invalid!==expected)
    $fatal(1,"range mismatch W=%0d H=%0d case=%0d base=%h stride=%h expected=%b got=%b",
           W,H,i,base,stride,expected,dut.descriptor_invalid);
  end
  base=32'h80000000;stride=2400;frame=1;slot=0;
  base[7]=1'bx;#1;if(dut.descriptor_invalid!==1'b1)$fatal(1,"unknown base accepted");
  base=32'h80000000;stride[31]=1'bx;#1;if(dut.descriptor_invalid!==1'b1)$fatal(1,"unknown stride accepted");
  stride=2400;frame[0]=1'bx;#1;if(dut.descriptor_invalid!==1'b1)$fatal(1,"unknown frame accepted");
  frame=1;slot[0]=1'bx;#1;if(dut.descriptor_invalid!==1'b1)$fatal(1,"unknown slot accepted");
  $display("RAW_DESCRIPTOR_RANGE_PASS W=%0d H=%0d cases=%0d",W,H,COUNT);$finish;
 end
endmodule
