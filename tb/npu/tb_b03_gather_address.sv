`timescale 1ns/1ps
module tb_b03_gather_address;
reg  clk=0;
reg  rst_n=0;
reg  clear=0;
reg  run_ce=0;
reg  start_valid=0;
wire  a_start_ready,b_start_ready;
reg [7:0] cfg_k_count=0;
reg [6:0] cfg_cin=0;
reg [8:0] cfg_win=0;
reg [8:0] cfg_x=0;
reg [4:0] cfg_m=0;
reg  cfg_kernel3=0;
reg  cfg_stride2=0;
reg [7:0] cfg_pad_left=0;
reg [191:0] cfg_row_present=0;
reg [32:0] cfg_row_offsets=0;
reg [10:0] cfg_group_stride=0;
reg [31:0] cfg_tag=0;
wire  a_done_valid,b_done_valid;
reg  done_ready=0;
wire [31:0] a_done_status,b_done_status;
wire [31:0] a_done_tag,b_done_tag;
wire [15:0] a_roi_req_a,b_roi_req_a;
wire [15:0] a_roi_req_b,b_roi_req_b;
wire [175:0] a_roi_addr_a,b_roi_addr_a;
wire [175:0] a_roi_addr_b,b_roi_addr_b;
reg [511:0] roi_q_a=0;
reg [511:0] roi_q_b=0;
reg [15:0] roi_valid_a=0;
reg [15:0] roi_valid_b=0;
wire  a_a_write_valid,b_a_write_valid;
wire [7:0] a_a_write_index,b_a_write_index;
wire [127:0] a_a_write_data,b_a_write_data;
wire  a_busy,b_busy;
wire [31:0] a_groups,b_groups;
wire [31:0] a_vectors,b_vectors;
b03_gather_old a(.clk(clk),.rst_n(rst_n),.clear(clear),.run_ce(run_ce),.start_valid(start_valid),.start_ready(a_start_ready),.cfg_k_count(cfg_k_count),.cfg_cin(cfg_cin),.cfg_win(cfg_win),.cfg_x(cfg_x),.cfg_m(cfg_m),.cfg_kernel3(cfg_kernel3),.cfg_stride2(cfg_stride2),.cfg_pad_left(cfg_pad_left),.cfg_row_present(cfg_row_present),.cfg_row_offsets(cfg_row_offsets),.cfg_group_stride(cfg_group_stride),.cfg_tag(cfg_tag),.done_valid(a_done_valid),.done_ready(done_ready),.done_status(a_done_status),.done_tag(a_done_tag),.roi_req_a(a_roi_req_a),.roi_req_b(a_roi_req_b),.roi_addr_a(a_roi_addr_a),.roi_addr_b(a_roi_addr_b),.roi_q_a(roi_q_a),.roi_q_b(roi_q_b),.roi_valid_a(roi_valid_a),.roi_valid_b(roi_valid_b),.a_write_valid(a_a_write_valid),.a_write_index(a_a_write_index),.a_write_data(a_a_write_data),.busy(a_busy),.groups(a_groups),.vectors(a_vectors));
b03_gather_lean b(.clk(clk),.rst_n(rst_n),.clear(clear),.run_ce(run_ce),.start_valid(start_valid),.start_ready(b_start_ready),.cfg_k_count(cfg_k_count),.cfg_cin(cfg_cin),.cfg_win(cfg_win),.cfg_x(cfg_x),.cfg_m(cfg_m),.cfg_kernel3(cfg_kernel3),.cfg_stride2(cfg_stride2),.cfg_pad_left(cfg_pad_left),.cfg_row_present(cfg_row_present),.cfg_row_offsets(cfg_row_offsets),.cfg_group_stride(cfg_group_stride),.cfg_tag(cfg_tag),.done_valid(b_done_valid),.done_ready(done_ready),.done_status(b_done_status),.done_tag(b_done_tag),.roi_req_a(b_roi_req_a),.roi_req_b(b_roi_req_b),.roi_addr_a(b_roi_addr_a),.roi_addr_b(b_roi_addr_b),.roi_q_a(roi_q_a),.roi_q_b(roi_q_b),.roi_valid_a(roi_valid_a),.roi_valid_b(roi_valid_b),.a_write_valid(b_a_write_valid),.a_write_index(b_a_write_index),.a_write_data(b_a_write_data),.busy(b_busy),.groups(b_groups),.vectors(b_vectors));
always #5 clk=~clk;
integer cases=0,i;reg [31:0] seed=32'h98734521;reg [31:0] val;
function [31:0] next_random(input [31:0] v);next_random=(v<<1)^(v[31]?32'h04c11db7:32'd0);endfunction
task compare_outputs;begin
if(a_start_ready!==b_start_ready)$fatal(1,"GATHER_MITER start_ready case=%0d",cases);
if(a_done_valid!==b_done_valid)$fatal(1,"GATHER_MITER done_valid case=%0d",cases);
if(a_done_status!==b_done_status)$fatal(1,"GATHER_MITER done_status case=%0d",cases);
if(a_done_tag!==b_done_tag)$fatal(1,"GATHER_MITER done_tag case=%0d",cases);
if(a_roi_req_a!==b_roi_req_a)$fatal(1,"GATHER_MITER roi_req_a case=%0d",cases);
if(a_roi_req_b!==b_roi_req_b)$fatal(1,"GATHER_MITER roi_req_b case=%0d",cases);
if(a_roi_addr_a!==b_roi_addr_a)$fatal(1,"GATHER_MITER roi_addr_a case=%0d",cases);
if(a_roi_addr_b!==b_roi_addr_b)$fatal(1,"GATHER_MITER roi_addr_b case=%0d",cases);
if(a_a_write_valid!==b_a_write_valid)$fatal(1,"GATHER_MITER a_write_valid case=%0d",cases);
if(a_a_write_index!==b_a_write_index)$fatal(1,"GATHER_MITER a_write_index case=%0d",cases);
if(a_a_write_data!==b_a_write_data)$fatal(1,"GATHER_MITER a_write_data case=%0d",cases);
if(a_busy!==b_busy)$fatal(1,"GATHER_MITER busy case=%0d",cases);
if(a_groups!==b_groups)$fatal(1,"GATHER_MITER groups case=%0d",cases);
if(a_vectors!==b_vectors)$fatal(1,"GATHER_MITER vectors case=%0d",cases);
end endtask
initial begin
 repeat(2)@(negedge clk);rst_n=1;run_ce=1;
 for(cases=0;cases<50000;cases=cases+1)begin
  @(negedge clk);seed=next_random(seed);val=seed;
  a.k_ci=val[6:0];b.k_ci=a.k_ci;a.cin=1+val[12:7]%64;b.cin=a.cin;
  a.k_ky=val[14:13]%3;b.k_ky=a.k_ky;a.k_kx=val[16:15]%3;b.k_kx=a.k_kx;
  a.win=1+val[25:17]%320;b.win=a.win;a.x=val[8:0];b.x=a.x;
  a.pad_left=val[16:9];b.pad_left=a.pad_left;a.m=1+val[20:17];b.m=a.m;
  a.stride2=val[21];b.stride2=a.stride2;a.kernel3=val[22];b.kernel3=a.kernel3;
  for(i=0;i<6;i=i+1)begin seed=next_random(seed);a.present[32*i+:32]=seed;end b.present=a.present;
  seed=next_random(seed);a.offsets={seed[0],seed};b.offsets=a.offsets;
  a.group_stride=seed[10:0];b.group_stride=a.group_stride;a.word_index=seed[14:11];b.word_index=a.word_index;
  a.active=1;b.active=1;a.current_k=0;b.current_k=0;a.count=128;b.count=128;
  a.done_valid=0;b.done_valid=0;run_ce=cases%5!=0;clear=cases%113==0;
  #1;compare_outputs();
  if(a.address_bad!==b.address_bad)$fatal(1,"GATHER_MITER address_bad case=%0d",cases);
  @(posedge clk);#1;compare_outputs();
 end
 $display("GATHER_ADDRESS_PASS cases=50000");$finish;
end
initial begin #1000000;$fatal(1,"GATHER_MITER timeout");end
endmodule
