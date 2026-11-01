`timescale 1ns/1ps
// Compare every public signal with the immutable pre-optimization implementation.
// Capacity is private: it must remain independent of reset while public ready
// remains reset qualified. CE, clear, random data and long stalls are exercised.
module tb_b03_quant_capacity;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,clear=0,run_ce=1,in_valid=0,out_ready=1;
 reg [7:0] in_mask=0;
 reg [255:0] in_psum=0,in_psum_b=0,in_bias=0,in_multiplier=0,in_multiplier_b=0;
 reg [47:0] in_shift=0; reg [127:0] in_tag=0;
 reg in_add=0; reg [1:0] in_dtype=0;
 wire ready[0:1],valid[0:1],advance[0:1],busy[0:1],add[0:1];
 wire [7:0] mask[0:1]; wire [127:0] values[0:1],tag[0:1];
 wire [23:0] error[0:1]; wire [1:0] dtype[0:1]; wire capacity;
 `DUT dut(.clk(clk),.rst_n(rst_n),.clear(clear),.run_ce(run_ce),
  .in_valid(in_valid),.in_ready(ready[0]),
`ifndef LEGACY_CAPACITY
  .in_capacity(capacity),
`endif
  .in_mask(in_mask),.in_psum(in_psum),.in_psum_b(in_psum_b),.in_add(in_add),.in_dtype(in_dtype),
  .in_bias(in_bias),.in_multiplier(in_multiplier),.in_multiplier_b(in_multiplier_b),.in_shift(in_shift),.in_tag(in_tag),
  .out_valid(valid[0]),.out_ready(out_ready),.out_mask(mask[0]),.out_values(values[0]),.out_dtype(dtype[0]),
  .out_add(add[0]),.out_error(error[0]),.out_tag(tag[0]),.advance(advance[0]),.busy(busy[0]));
`ifdef LEGACY_CAPACITY
 assign capacity=ready[0];
`endif
 `REFERENCE reference(.clk(clk),.rst_n(rst_n),.clear(clear),.run_ce(run_ce),
  .in_valid(in_valid),.in_ready(ready[1]),.in_mask(in_mask),.in_psum(in_psum),.in_psum_b(in_psum_b),
  .in_add(in_add),.in_dtype(in_dtype),.in_bias(in_bias),.in_multiplier(in_multiplier),
  .in_multiplier_b(in_multiplier_b),.in_shift(in_shift),.in_tag(in_tag),
  .out_valid(valid[1]),.out_ready(out_ready),.out_mask(mask[1]),.out_values(values[1]),.out_dtype(dtype[1]),
  .out_add(add[1]),.out_error(error[1]),.out_tag(tag[1]),.advance(advance[1]),.busy(busy[1]));
 integer seed=731,m,n,checks=0,accepted=0,retired=0,stalls=0,reset_capacity=0;
 task check;
 begin
  if({ready[0],valid[0],advance[0],busy[0],mask[0],values[0],dtype[0],add[0],error[0],tag[0]} !==
     {ready[1],valid[1],advance[1],busy[1],mask[1],values[1],dtype[1],add[1],error[1],tag[1]})
   $fatal(1,"QUANT_PUBLIC_MISMATCH cycle=%0d",m);
  if(rst_n)begin
   if(capacity!==ready[0])$fatal(1,"active capacity/ready mismatch");
  end else begin
   if(ready[0]!==0)$fatal(1,"ready during reset");
   if(capacity!==(!clear&&run_ce))$fatal(1,"CAPACITY_RESET_FEEDBACK cycle=%0d",m);
   if(capacity)reset_capacity=reset_capacity+1;
  end
  checks=checks+1;
 end endtask
 initial begin
  repeat(3)@(negedge clk);
  for(m=0;m<20000;m=m+1)begin
   rst_n=(m%1021)>2;clear=rst_n&&(m%197==0);run_ce=!rst_n||(m%11<8);
   in_valid=(m%7!=0);out_ready=(m%131<79);in_mask=$random(seed);in_dtype=m%4;in_add=m%3==0;
   in_tag={96'd0,m[31:0]};
   for(n=0;n<8;n=n+1)begin
    in_psum[n*32+:32]=$random(seed);in_psum_b[n*32+:32]=$random(seed);
    in_bias[n*32+:32]=m%3==0?0:$random(seed);
    in_multiplier[n*32+:32]=$random(seed)&32'h7fffffff;
    in_multiplier_b[n*32+:32]=$random(seed)&32'h7fffffff;
    in_shift[n*6+:6]=(m+n)%64;
   end
   #1;check;
   if(ready[0]&&in_valid)accepted=accepted+1;
   if(advance[0]&&valid[0])retired=retired+1;
   if(valid[0]&&!advance[0])stalls=stalls+1;
   @(posedge clk);#1;check;@(negedge clk);
  end
  if(accepted<100||retired<100||stalls<100||reset_capacity<10)$fatal(1,"coverage");
  $display("PASS B03_QUANT_CAPACITY checks=%0d accepted=%0d retired=%0d stalls=%0d reset_capacity=%0d",checks,accepted,retired,stalls,reset_capacity);
  $finish;
 end
 initial begin #300000;$fatal(1,"timeout");end
endmodule
