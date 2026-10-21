`timescale 1ns/1ps
module tb_video_record_renderer #(parameter integer W=80,H=64,CASE_ID=0,parameter real PIXEL_HALF=12.5);
 reg core_clk=0,core_reset_n=0,pixel_clk=0,pixel_reset_n=0,online=1;
 always #4 core_clk=~core_clk;always #(PIXEL_HALF)pixel_clk=~pixel_clk;
 wire memory_fault;reg display_urgent=1;
 reg load_valid=0,result_ready=0;wire load_ready,result_valid,result_success;
 reg [31:0] load_base=32'h82600ff0,load_bytes=262144,load_asset_id=7,load_generation=71,expected_crc=0;
 wire [7:0] result_code;wire [31:0] result_asset_id,result_generation,checked_bytes,crc;
 wire asset_ready,pixel_material_ready;wire [31:0] asset_id,asset_generation,words_written;
 reg cmd_valid=0,commit_ready=0,retire_ready=0;wire cmd_ready,commit_valid,retire_valid;
 reg [1:0] cmd_mode=0,cmd_slot=0;reg [31:0] cmd_frame=1,cmd_generation=10,cmd_seq=0;reg [5119:0] cmd_data=0,records[0:8];
 wire [1:0] commit_mode,commit_slot,retire_slot,retire_mode;wire [31:0] commit_frame,commit_generation,commit_seq,retire_frame,retire_generation,retire_seq;
 wire retire_raw,retire_asset;wire [31:0] retire_asset_id,retire_asset_generation;
 reg raw_context_valid=0,stream=0;reg [10:0] raw_x=0,raw_y=0;
 wire [1:0] raw_slot=0;wire [31:0] raw_frame=1,raw_generation=10;
 wire raw_de=stream&&raw_x<W&&raw_y<H,raw_sof=stream&&raw_x==0&&raw_y==0;
 wire raw_hs=stream&&raw_x>=W+2,raw_vs=stream&&raw_y>=H+1;
 wire [23:0] raw_rgb={8'(raw_x*7+31),8'(raw_y*11+17),8'(raw_x*3+raw_y*13)};
 wire [23:0] out_rgb;wire [10:0] out_x,out_y;wire [31:0] out_frame,out_generation,out_seq;wire [1:0] out_slot,out_mode;
 wire out_de,out_hs,out_vs,out_sof,out_box,out_point,out_avatar,out_fault,pixel_pending;
 wire [1:0] pending_mode,pending_slot;wire [31:0] pending_frame,pending_generation;
 wire [2:0] faults;wire [7:0] read_code,material_code,pixels_code;
 wire port_drained;wire [31:0] raw_grants,asset_grants;
 reg [3:0] d_arid=0;reg [31:0] d_araddr=32'h82000000;reg [7:0] d_arlen=15;reg [2:0] d_arsize=4;reg [1:0] d_arburst=1;
 reg d_arvalid=0,d_rready=0;wire d_arready,d_rvalid,d_rlast;wire [3:0] d_rid;wire [127:0] d_rdata;wire [1:0] d_rresp;
 wire [3:0] m_arid;wire [31:0] m_araddr;wire [7:0] m_arlen;wire [2:0] m_arsize;wire [1:0] m_arburst;
 wire m_arvalid,m_arready,m_rvalid,m_rlast,m_rready;wire [3:0] m_rid;wire [127:0] m_rdata;wire [1:0] m_rresp;
 video_record_renderer dut(.*);
 wire [27:0] h_awaddr,h_araddr;wire [3:0] h_awlen,h_arlen,h_awid,h_arid;wire h_awvalid,h_arvalid,h_rvalid,h_arready;
 wire [255:0] h_wdata,h_rdata;wire [31:0] h_wstrb;wire [3:0] h_rid;wire h_rlast;
 wire shared_fault,shared_busy,shared_drained;wire [7:0] shared_code;wire [31:0] shared_reads,shared_writes;
 assign memory_fault=shared_fault;
 video_shared_ddr u_shared(.clk(core_clk),.reset_n(core_reset_n),.online(online),.display_urgent(display_urgent),
  .c_awid(4'd0),.c_awaddr(32'd0),.c_awlen(8'd0),.c_awsize(3'd4),.c_awburst(2'd1),.c_awvalid(1'b0),.c_awready(),
  .c_wdata(128'd0),.c_wstrb(16'd0),.c_wlast(1'b0),.c_wvalid(1'b0),.c_wready(),.c_bid(),.c_bresp(),.c_bvalid(),.c_bready(1'b1),
  .d_arid(m_arid),.d_araddr(m_araddr),.d_arlen(m_arlen),.d_arsize(m_arsize),.d_arburst(m_arburst),.d_arvalid(m_arvalid),.d_arready(m_arready),
  .d_rid(m_rid),.d_rdata(m_rdata),.d_rresp(m_rresp),.d_rlast(m_rlast),.d_rvalid(m_rvalid),.d_rready(m_rready),
  .h_awaddr(h_awaddr),.h_awlen(h_awlen),.h_awid(h_awid),.h_awvalid(h_awvalid),.h_awready(1'b1),.h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_wready(1'b1),.h_wid(4'd0),.h_wlast(1'b0),
  .h_araddr(h_araddr),.h_arlen(h_arlen),.h_arid(h_arid),.h_arvalid(h_arvalid),.h_arready(h_arready),.h_rvalid(h_rvalid),.h_rdata(h_rdata),.h_rid(h_rid),.h_rlast(h_rlast),
  .fault(shared_fault),.fault_code(shared_code),.busy(shared_busy),.port_drained(shared_drained),.read_grants(shared_reads),.write_grants(shared_writes));
 integer native_commands,native_beats;
 video_renderer_memory u_memory(.clk(core_clk),.reset_n(core_reset_n),.h_araddr(h_araddr),.h_arlen(h_arlen),.h_arid(h_arid),.h_arvalid(h_arvalid),.h_arready(h_arready),.h_rvalid(h_rvalid),.h_rdata(h_rdata),.h_rid(h_rid),.h_rlast(h_rlast),.native_commands(native_commands),.native_beats(native_beats));
 reg [127:0] raw_words[0:255];integer raw_submitted=0,raw_completed=0,raw_index=0,raw_checked=0,ct=0;reg raw_pending=0;
 always @(negedge core_clk)if(core_reset_n)begin
  d_rready=ct%5!=0;
  if(!asset_ready&&!result_valid&&!raw_pending&&!d_arvalid)begin d_arvalid=1;d_araddr=32'h82000000+(raw_submitted%16)*256;end
 end
 always @(posedge core_clk)if(!core_reset_n)begin ct<=0;raw_submitted<=0;raw_completed<=0;raw_index<=0;raw_checked<=0;raw_pending<=0;d_arvalid<=0;end else begin
  ct<=ct+1;
  if(commit_valid&&commit_seq!==proven_seq)$fatal(1,"RENDER_UNPROVEN_COMMIT");
  if(d_arvalid&&d_arready)begin d_arvalid<=0;raw_pending<=1;raw_submitted<=raw_submitted+1;raw_index<=0;end
  if(d_rvalid&&d_rready)begin
   if(!raw_pending||d_rid!=0||d_rresp!=0||d_rlast!==(raw_index==15)||d_rdata!==raw_words[((raw_completed%16)*16)+raw_index])$fatal(1,"RENDER_RAW_SHARED_DATA");
   raw_checked<=raw_checked+1;raw_index<=raw_index+1;if(d_rlast)begin raw_pending<=0;raw_completed<=raw_completed+1;end
  end
  if(shared_fault)$fatal(1,"RENDER_SHARED_FAULT %h",shared_code);
 end
 reg [27:0] expected[0:3*W*H-1];reg [31:0] crc_file[0:0];
 reg [31:0] proven_seq=0;
 integer mode_pixels[0:2],commits=0,retirements=0,issued_mode=0,issued_seq=0,reference_mode=0,reference_seq=0;
 reg reference_active=0;reg [13:0] valid_pipe=0;
 reg [10:0] xs[0:13],ys[0:13];reg [3:0] timing[0:13];reg [23:0] rgbs[0:13];integer modes[0:13],seqs[0:13];reg qualified[0:13];integer k;
 always @(posedge pixel_clk)begin
  if(!pixel_reset_n)begin valid_pipe<=0;raw_x<=0;raw_y<=0;reference_mode=0;reference_seq=0;reference_active=0;proven_seq=0;end
  else begin
   if(stream)begin if(raw_x==W+7)begin raw_x<=0;if(raw_y==H+3)raw_y<=0;else raw_y<=raw_y+1;end else raw_x<=raw_x+1;end
   if(pixel_pending&&raw_sof&&(issued_mode!=2||pixel_material_ready))begin reference_mode=issued_mode;reference_seq=issued_seq;reference_active=1;end
   for(k=13;k>0;k=k-1)begin xs[k]=xs[k-1];ys[k]=ys[k-1];timing[k]=timing[k-1];rgbs[k]=rgbs[k-1];modes[k]=modes[k-1];seqs[k]=seqs[k-1];qualified[k]=qualified[k-1];end
   xs[0]=raw_x;ys[0]=raw_y;timing[0]={raw_de,raw_hs,raw_vs,raw_sof};rgbs[0]=raw_rgb;modes[0]=reference_mode;seqs[0]=reference_seq;qualified[0]=reference_active;
   valid_pipe<={valid_pipe[12:0],1'b1};#1;
   if(valid_pipe[13])begin
    if({out_x,out_y,out_de,out_hs,out_vs,out_sof,out_frame,out_generation,out_slot,out_mode,out_seq}!==
       {xs[13],ys[13],timing[13],32'd1,32'd10,2'd0,2'(modes[13]),32'(seqs[13])})$fatal(1,"RENDER_PIXEL_METADATA");
    if(out_de&&out_sof&&qualified[13])proven_seq=out_seq;
    if(timing[13][3]&&qualified[13])begin
     if({out_fault,out_avatar,out_point,out_box,out_rgb}!==expected[modes[13]*W*H+ys[13]*W+xs[13]])$fatal(1,"RENDER_PIXEL_ORACLE m=%0d x=%0d y=%0d got=%h flags=%b",modes[13],xs[13],ys[13],out_rgb,{out_fault,out_avatar,out_point,out_box});
     mode_pixels[modes[13]]=mode_pixels[modes[13]]+1;
    end else if(out_rgb!==rgbs[13]||{out_fault,out_avatar,out_point,out_box}!==0)$fatal(1,"RENDER_PIXEL_BACKGROUND");
   end
  end
 end
 reg guard_start=0;wire guard_ready,guard_result;wire [7:0] guard_code;
 display_record_guard u_guard(.clk_i(core_clk),.rst_ni(core_reset_n),.start_valid_i(guard_start),.start_ready_o(guard_ready),.record_i(cmd_data),.mode_i(cmd_mode),.modes_i(3'b111),.asset_ready_i(1'b1),.asset_id_i(cmd_data[14*32+:32]),.asset_generation_i(cmd_data[15*32+:32]),.result_valid_o(guard_result),.result_ready_i(1'b1),.result_code_o(guard_code));
 task automatic submit(input integer mode);
  begin
   @(negedge core_clk);cmd_data=records[mode+1];cmd_mode=mode;cmd_slot=0;cmd_frame=1;cmd_generation=10;issued_mode=mode;issued_seq=issued_seq+1;cmd_seq=issued_seq;
   guard_start=1;do @(posedge core_clk);while(!guard_ready);@(negedge core_clk);guard_start=0;wait(guard_result);if(guard_code)$fatal(1,"RENDER_FIXTURE_GUARD %h",guard_code);
   @(negedge core_clk);cmd_valid=1;do @(posedge core_clk);while(!cmd_ready);@(negedge core_clk);cmd_valid=0;cmd_data='x;cmd_seq='x;
  end
 endtask
 task automatic start_load;
  begin
   @(negedge core_clk);load_base=32'h82600ff0;load_bytes=262144;load_asset_id=7;load_generation=71;expected_crc=crc_file[0]^(CASE_ID==4?1:0);
   load_valid=1;do @(posedge core_clk);while(!load_ready);@(negedge core_clk);load_valid=0;load_base='x;load_bytes='x;load_asset_id='x;load_generation='x;expected_crc='x;
  end
 endtask
 task automatic consume_commit;
  reg [99:0] snapshot;
  begin wait(commit_valid);snapshot={commit_slot,commit_mode,commit_frame,commit_generation,commit_seq};
   repeat(20)begin @(negedge core_clk);if(!commit_valid||{commit_slot,commit_mode,commit_frame,commit_generation,commit_seq}!==snapshot||cmd_ready)$fatal(1,"RENDER_COMMIT_HOLD");end
   if(snapshot!=={2'd0,2'(issued_mode),32'd1,32'd10,32'(issued_seq)})$fatal(1,"RENDER_COMMIT_IDENTITY");
   commit_ready=1;@(negedge core_clk);commit_ready=0;commits=commits+1;
  end
 endtask
 string directory;integer mode;
 initial begin
  for(mode=0;mode<3;mode=mode+1)mode_pixels[mode]=0;
  if(!$value$plusargs("DIR=%s",directory))$fatal(1,"RENDER_DIR");
  $readmemh({directory,"/records.hex"},records);$readmemh({directory,"/expected.hex"},expected);$readmemh({directory,"/crc.hex"},crc_file);$readmemh({directory,"/raw_words.hex"},raw_words);
  repeat(6)@(negedge core_clk);core_reset_n=1;pixel_reset_n=1;
  start_load();
  if(CASE_ID==5)begin wait(words_written>512);@(negedge core_clk);core_reset_n=0;pixel_reset_n=0;repeat(6)@(negedge core_clk);core_reset_n=1;pixel_reset_n=1;start_load();end
  if(CASE_ID==3||CASE_ID==4)begin submit(2);wait(pixel_pending);@(negedge pixel_clk);stream=1;raw_context_valid=1;end
  wait(result_valid);if(CASE_ID==4)begin repeat((W+8)*(H+4)*2)@(negedge pixel_clk);
   if(result_success||result_code!=5||asset_ready||pixel_material_ready||commit_valid||faults[1]!==1||faults[2:2]!==0)$fatal(1,"RENDER_FAILED_ASSET_COMMITTED");
  end else begin
   if(!result_success||checked_bytes!=262144||crc!==crc_file[0]||raw_checked==0||raw_grants==0||asset_grants!=1025)$fatal(1,"RENDER_DDR_LOAD");
   if(CASE_ID==3)begin consume_commit();wait(mode_pixels[2]>=W*H);end
   for(mode=0;mode<3;mode=mode+1)begin
    submit(mode);wait(pixel_pending);if(!stream)begin @(negedge pixel_clk);stream=1;raw_context_valid=1;end
    consume_commit();wait(mode_pixels[mode]>=W*H);
    if(retire_valid)begin if(retire_raw||!retire_asset||retire_asset_id!=7||retire_asset_generation!=71)$fatal(1,"RENDER_EARLY_RETIRE");@(negedge core_clk);retire_ready=1;@(negedge core_clk);retire_ready=0;retirements=retirements+1;end
   end
   submit(0);consume_commit();wait(retire_valid);
   repeat(20)begin @(negedge core_clk);if(!retire_valid||retire_raw||!retire_asset||retire_frame!=1||retire_generation!=10||retire_slot!=0||retire_asset_id!=7||retire_asset_generation!=71||cmd_ready)$fatal(1,"RENDER_RETIRE_HOLD");end
   retire_ready=1;@(negedge core_clk);retire_ready=0;retirements=retirements+1;
   wait(!raw_pending&&!d_arvalid);repeat(10)@(negedge core_clk);
   if(faults||!asset_ready||!port_drained||!shared_drained||shared_writes!=0)$fatal(1,"RENDER_FINAL_HEALTH");
  end
  $display("RECORD_RENDERER_PASS case=%0d w=%0d h=%0d raw_pixels=%0d box_pixels=%0d avatar_pixels=%0d commits=%0d retires=%0d raw_reads=%0d asset_reads=%0d native=%0d",CASE_ID,W,H,mode_pixels[0],mode_pixels[1],mode_pixels[2],commits,retirements,raw_checked,asset_grants,native_commands);$finish;
 end
 initial begin #150000000;$fatal(1,"RENDER_TIMEOUT");end
endmodule
