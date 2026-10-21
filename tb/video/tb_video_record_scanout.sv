`timescale 1ns/1ps
module tb_video_record_scanout #(parameter integer W=80,H=64,parameter real PIXEL_HALF=12.5);
 reg  core_clk=0;
 reg  core_reset_n=0;
 reg  pixel_clk=0;
 reg  pixel_reset_n=0;
 reg  online=0;
 wire  memory_fault;
 reg  display_urgent=0;
 reg  load_valid=0;
 wire  load_ready;
 reg [31:0] load_base=0;
 reg [31:0] load_bytes=0;
 reg [31:0] load_asset_id=0;
 reg [31:0] load_generation=0;
 reg [31:0] expected_crc=0;
 wire  result_valid;
 reg  result_ready=0;
 wire  result_success;
 wire [7:0] result_code;
 wire [31:0] result_asset_id;
 wire [31:0] result_generation;
 wire [31:0] checked_bytes;
 wire [31:0] crc;
 wire  asset_ready;
 wire  pixel_material_ready;
 wire [31:0] asset_id;
 wire [31:0] asset_generation;
 wire [31:0] words_written;
 wire  commit_valid;
 reg  commit_ready=0;
 wire [1:0] commit_mode;
 wire [1:0] commit_slot;
 wire [31:0] commit_frame;
 wire [31:0] commit_generation;
 wire [31:0] commit_seq;
 wire  raw_context_valid;
 wire [1:0] raw_slot;
 wire [31:0] raw_frame;
 wire [31:0] raw_generation;
 wire [10:0] raw_x;
 wire [10:0] raw_y;
 wire [23:0] raw_rgb;
 wire  raw_de;
 wire  raw_hs;
 wire  raw_vs;
 wire  raw_sof;
 wire [23:0] out_rgb;
 wire [10:0] out_x;
 wire [10:0] out_y;
 wire [31:0] out_frame;
 wire [31:0] out_generation;
 wire [31:0] out_seq;
 wire [1:0] out_slot;
 wire [1:0] out_mode;
 wire  out_de;
 wire  out_hs;
 wire  out_vs;
 wire  out_sof;
 wire  out_box;
 wire  out_point;
 wire  out_avatar;
 wire  out_fault;
 wire  pixel_pending;
 wire [1:0] pending_mode;
 wire [1:0] pending_slot;
 wire [31:0] pending_frame;
 wire [31:0] pending_generation;
 wire [2:0] faults;
 wire [7:0] read_code;
 wire [7:0] material_code;
 wire [7:0] pixels_code;
 wire  port_drained;
 wire [31:0] raw_grants;
 wire [31:0] asset_grants;
 wire [3:0] m_arid;
 wire [31:0] m_araddr;
 wire [7:0] m_arlen;
 wire [2:0] m_arsize;
 wire [1:0] m_arburst;
 wire  m_arvalid;
 wire  m_arready;
 wire [3:0] m_rid;
 wire [127:0] m_rdata;
 wire [1:0] m_rresp;
 wire  m_rlast;
 wire  m_rvalid;
 wire  m_rready;
 reg  submit_valid=0;
 wire  submit_ready;
 reg  submit_mode_only=0;
 reg [1:0] submit_slot=0;
 reg [1:0] submit_mode=0;
 reg [31:0] submit_frame=0;
 reg [31:0] submit_generation=0;
 reg [31:0] submit_base=0;
 reg [31:0] submit_stride=0;
 reg [31:0] submit_seq=0;
 reg [5120-1:0] submit_data=0;
 wire  reject_valid;
 reg  reject_ready=0;
 wire [7:0] reject_code;
 wire [31:0] reject_seq;
 wire  commit_mode_only;
 wire  release_valid;
 reg  release_ready=0;
 wire [1:0] release_slot;
 wire [31:0] release_frame;
 wire [31:0] release_generation;
 wire  active_valid;
 wire [1:0] active_slot;
 wire [1:0] active_mode;
 wire [31:0] active_frame;
 wire [31:0] active_generation;
 wire [2:0] slot_free;
 reg [10:0] pixel_x=0;
 reg [10:0] pixel_y=0;
 reg  pixel_de=0;
 reg  pixel_hs=0;
 reg  pixel_vs=0;
 reg  pixel_frame_start=0;
 wire  asset_retire_valid;
 reg  asset_retire_ready=0;
 wire [1:0] asset_retire_slot;
 wire [31:0] asset_retire_frame;
 wire [31:0] asset_retire_generation;
 wire [31:0] asset_retire_seq;
 wire [31:0] asset_retire_id;
 wire [31:0] asset_retire_generation_id;
 wire  owner_error;
 wire  link_error;
 wire  raw_error;
 wire  fault;
 wire [7:0] owner_code;
 wire [7:0] link_code;
 wire [7:0] raw_code;
 wire [31:0] raw_commits;
 wire [31:0] raw_scans;
 wire [31:0] raw_lines;
 wire [31:0] underflows;
 always #4 core_clk=~core_clk;always #(PIXEL_HALF) pixel_clk=~pixel_clk;
 video_record_scanout #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(100000)) dut(.*);
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
 integer native_commands,raw_commands,asset_commands;
 video_scanout_memory u_memory(.clk(core_clk),.reset_n(core_reset_n),.h_araddr(h_araddr),.h_arlen(h_arlen),.h_arid(h_arid),.h_arvalid(h_arvalid),.h_arready(h_arready),.h_rvalid(h_rvalid),.h_rdata(h_rdata),.h_rid(h_rid),.h_rlast(h_rlast),.native_commands(native_commands),.raw_commands(raw_commands),.asset_commands(asset_commands));
 localparam integer HT=W+256,VT=H+28;
 always @(posedge pixel_clk)begin
  if(!pixel_reset_n)begin pixel_x<=0;pixel_y<=0;end
  else if(pixel_x==HT-1)begin pixel_x<=0;if(pixel_y==VT-1)pixel_y<=0;else pixel_y<=pixel_y+1;end
  else pixel_x<=pixel_x+1;
 end
 always @*begin pixel_de=pixel_x<W&&pixel_y<H;pixel_hs=pixel_x>=W+40&&pixel_x<W+168;pixel_vs=pixel_y>=H+1&&pixel_y<H+5;pixel_frame_start=pixel_x==0&&pixel_y==0;end
 reg [5119:0] records[0:8],next_record;reg [27:0] expected[0:3*W*H-1];reg [31:0] crc_file[0:0];
 function automatic [23:0] raw_pixel(input integer slot,x,y);
  raw_pixel={8'(x*7+31+slot*77),8'(y*11+17+slot*47),8'(x*3+y*13+slot*93)};
 endfunction
 integer issued_mode=0,issued_slot=0,issued_frame=1,issued_generation=10,issued_seq=0,reference_mode=0,reference_seq=0;
 integer mode_pixels[0:2],seq_pixels[0:5],commits=0,releases=0,checked_raw=0,overlap=0;
 reg [31:0] proven_seq=0;reg [13:0] valid_pipe=0;integer k;
 reg [10:0] xs[0:13],ys[0:13];reg [3:0] timings[0:13];reg [23:0] rgbs[0:13];reg qualified[0:13];
 reg [31:0] frames[0:13],generations[0:13];reg [1:0] slots[0:13];integer modes[0:13],seqs[0:13];reg [27:0] wanted;
 reg [10:0] x0=0,x1=0,y0=0,y1=0;reg [2:0] timing0=0,timing1=0;integer warmup=0;
 always @(posedge pixel_clk)begin
  if(!pixel_reset_n)begin valid_pipe<=0;reference_mode=0;reference_seq=0;proven_seq=0;warmup=0;end
  else begin
   if(pixel_pending&&raw_sof&&raw_context_valid&&raw_slot==issued_slot&&raw_frame==issued_frame&&raw_generation==issued_generation&&(issued_mode!=2||pixel_material_ready))begin reference_mode=issued_mode;reference_seq=issued_seq;end
   for(k=13;k>0;k=k-1)begin xs[k]=xs[k-1];ys[k]=ys[k-1];timings[k]=timings[k-1];rgbs[k]=rgbs[k-1];qualified[k]=qualified[k-1];frames[k]=frames[k-1];generations[k]=generations[k-1];slots[k]=slots[k-1];modes[k]=modes[k-1];seqs[k]=seqs[k-1];end
   xs[0]=raw_x;ys[0]=raw_y;timings[0]={raw_de,raw_hs,raw_vs,raw_sof};rgbs[0]=raw_rgb;qualified[0]=raw_context_valid&&reference_seq!=0;frames[0]=raw_frame;generations[0]=raw_generation;slots[0]=raw_slot;modes[0]=reference_mode;seqs[0]=reference_seq;
   x0<=pixel_x;x1<=x0;y0<=pixel_y;y1<=y0;timing0<={pixel_de,pixel_hs,pixel_vs};timing1<=timing0;
   valid_pipe<={valid_pipe[12:0],1'b1};warmup=warmup+1;#1;
   if(warmup>4)begin
    if({raw_x,raw_y,raw_de,raw_hs,raw_vs}!=={x1,y1,timing1})$fatal(1,"SCAN_RAW_ALIGNMENT");
    if(raw_context_valid)begin
     if(!raw_de||raw_rgb!==raw_pixel(raw_slot,raw_x,raw_y)||raw_sof!==(raw_x==0&&raw_y==0))$fatal(1,"SCAN_RAW_BYTE_ORACLE x=%0d y=%0d rgb=%h",raw_x,raw_y,raw_rgb);
     if((raw_slot==0&&(raw_frame!=1||(raw_generation!=10&&raw_generation!=11)))||(raw_slot==1&&(raw_frame!=2||raw_generation!=20))||raw_slot>1)$fatal(1,"SCAN_RAW_IDENTITY");
     checked_raw=checked_raw+1;
    end else if(raw_rgb!==24'h101820||raw_sof)$fatal(1,"SCAN_RAW_INVALID_RGB");
   end
   if(valid_pipe[13])begin
    if({out_x,out_y,out_de,out_hs,out_vs,out_sof,out_frame,out_generation,out_slot,out_mode,out_seq}!==
       {xs[13],ys[13],timings[13],frames[13],generations[13],slots[13],2'(modes[13]),32'(seqs[13])})$fatal(1,"SCAN_OUTPUT_METADATA");
    if(out_de&&out_sof&&qualified[13])proven_seq=out_seq;
    if(qualified[13])begin
     wanted=slots[13]==0?expected[modes[13]*W*H+ys[13]*W+xs[13]]:{4'b0,raw_pixel(slots[13],xs[13],ys[13])};
     if({out_fault,out_avatar,out_point,out_box,out_rgb}!==wanted)$fatal(1,"SCAN_OUTPUT_ORACLE m=%0d x=%0d y=%0d got=%h expected=%h",modes[13],xs[13],ys[13],{out_fault,out_avatar,out_point,out_box,out_rgb},wanted);
     mode_pixels[modes[13]]=mode_pixels[modes[13]]+1;if(seqs[13]<=5)seq_pixels[seqs[13]]=seq_pixels[seqs[13]]+1;
    end else if(out_rgb!==rgbs[13]||{out_fault,out_avatar,out_point,out_box}!==0)$fatal(1,"SCAN_OUTPUT_BYPASS");
   end
  end
 end
 always @(posedge core_clk)if(core_reset_n)begin
  if(commit_valid&&commit_seq!==proven_seq)$fatal(1,"SCAN_UNPROVEN_COMMIT");
  if(fault||shared_fault)$fatal(1,"SCAN_HEALTH owner=%h link=%h raw=%h render=%b shared=%h",owner_code,link_code,raw_code,faults,shared_code);
  if(raw_grants>0&&!asset_ready)overlap=overlap+1;
 end
 reg guard_start=0;wire guard_ready,guard_result;wire [7:0] guard_code;
 display_record_guard u_guard(.clk_i(core_clk),.rst_ni(core_reset_n),.start_valid_i(guard_start),.start_ready_o(guard_ready),.record_i(submit_data),.mode_i(submit_mode),.modes_i(3'b111),.asset_ready_i(1'b1),.asset_id_i(32'd7),.asset_generation_i(32'd71),.result_valid_o(guard_result),.result_ready_i(1'b1),.result_code_o(guard_code));
 task automatic submit(input integer slot,frame,generation,mode,seq,input bit only,accepted);
  begin
   @(negedge core_clk);submit_slot=slot;submit_frame=frame;submit_generation=generation;submit_mode=mode;submit_seq=seq;submit_base=32'h82000000+slot*32'h200000;submit_stride=2400;submit_mode_only=only;
   next_record=records[1];next_record[2*32+:32]=slot;next_record[3*32+:32]=frame;next_record[4*32+:32]=generation;next_record[5*32+:32]=submit_base;next_record[10*32+:32]=frame;next_record[11*32+:32]=generation;submit_data=next_record;
   guard_start=1;do @(posedge core_clk);while(!guard_ready);@(negedge core_clk);guard_start=0;wait(guard_result);if(guard_code)$fatal(1,"SCAN_FIXTURE_GUARD");
   if(accepted)begin issued_slot=slot;issued_frame=frame;issued_generation=generation;issued_mode=mode;issued_seq=seq;end
   @(negedge core_clk);submit_valid=1;do @(posedge core_clk);while(!submit_ready);@(negedge core_clk);submit_valid=0;submit_data='x;
  end
 endtask
 task automatic consume_commit;
  reg [100:0] snapshot;begin wait(commit_valid);snapshot={commit_mode_only,commit_slot,commit_mode,commit_frame,commit_generation,commit_seq};
   repeat(20)begin @(negedge core_clk);if(!commit_valid||{commit_mode_only,commit_slot,commit_mode,commit_frame,commit_generation,commit_seq}!==snapshot)$fatal(1,"SCAN_COMMIT_HOLD");end
   if({commit_slot,commit_mode,commit_frame,commit_generation,commit_seq}!=={2'(issued_slot),2'(issued_mode),32'(issued_frame),32'(issued_generation),32'(issued_seq)})$fatal(1,"SCAN_COMMIT_KEY");
   commit_ready=1;@(negedge core_clk);commit_ready=0;commits=commits+1;end
 endtask
 task automatic consume_release(input integer slot,frame,generation);
  begin wait(release_valid);repeat(20)begin @(negedge core_clk);if(!release_valid||{release_slot,release_frame,release_generation}!=={2'(slot),32'(frame),32'(generation)}||slot_free[slot])$fatal(1,"SCAN_RELEASE_HOLD");end
   release_ready=1;@(negedge core_clk);release_ready=0;releases=releases+1;repeat(2)@(negedge core_clk);if(!slot_free[slot])$fatal(1,"SCAN_SLOT_NOT_FREED");end
 endtask
 string directory;integer i;
 initial begin
  for(i=0;i<3;i=i+1)mode_pixels[i]=0;for(i=0;i<6;i=i+1)seq_pixels[i]=0;
  if(!$value$plusargs("DIR=%s",directory))$fatal(1,"SCAN_DIR");$readmemh({directory,"/records.hex"},records);$readmemh({directory,"/expected.hex"},expected);$readmemh({directory,"/crc.hex"},crc_file);
  online=1;display_urgent=1;result_ready=0;reject_ready=0;asset_retire_ready=0;
  repeat(8)@(negedge core_clk);core_reset_n=1;pixel_reset_n=1;
  @(negedge core_clk);load_valid=1;load_base=32'h82600ff0;load_bytes=262144;load_asset_id=7;load_generation=71;expected_crc=crc_file[0];
  do @(posedge core_clk);while(!load_ready);@(negedge core_clk);load_valid=0;
  submit(0,1,10,0,1,0,1);consume_commit();wait(seq_pixels[1]>=W*H);
  submit(0,1,10,1,2,1,1);consume_commit();wait(seq_pixels[2]>=W*H);
  wait(result_valid);if(!result_success||checked_bytes!=262144||crc!=crc_file[0])$fatal(1,"SCAN_MATERIAL_LOAD");
  submit(0,1,10,2,3,1,1);consume_commit();wait(seq_pixels[3]>=W*H);
  if(raw_commits!=1||release_valid)$fatal(1,"SCAN_MODE_CHANGED_RAW");
  submit(1,2,20,0,4,0,1);consume_commit();wait(seq_pixels[4]>=W*H);wait(release_valid);
  if(!asset_retire_valid||asset_retire_id!=7||asset_retire_generation_id!=71||asset_retire_generation!=10||asset_retire_frame!=1)$fatal(1,"SCAN_ASSET_RETIRE");
  submit(0,1,11,0,99,0,0);wait(reject_valid);if(reject_code!=5||reject_seq!=99||slot_free[0])$fatal(1,"SCAN_REUSE_BEFORE_ACK");
  @(negedge core_clk);reject_ready=1;@(negedge core_clk);reject_ready=0;consume_release(0,1,10);
  @(negedge core_clk);asset_retire_ready=1;@(negedge core_clk);asset_retire_ready=0;
  submit(0,1,11,0,5,0,1);consume_commit();wait(seq_pixels[5]>=W*H);consume_release(1,2,20);
  if(raw_commits!=3||underflows||!overlap||!raw_commands||asset_grants!=1025)$fatal(1,"SCAN_FINAL_COUNTS");
  $display("VIDEO_RECORD_SCANOUT_PASS w=%0d h=%0d raw_pixels=%0d box_pixels=%0d avatar_pixels=%0d commits=%0d releases=%0d scanner_pixels=%0d raw_commits=%0d overlap=%0d raw_reads=%0d asset_reads=%0d native=%0d",W,H,mode_pixels[0],mode_pixels[1],mode_pixels[2],commits,releases,checked_raw,raw_commits,overlap,raw_commands,asset_commands,native_commands);$finish;
 end
 initial begin #350000000;$fatal(1,"SCAN_TIMEOUT");end
endmodule
