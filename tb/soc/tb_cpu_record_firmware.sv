`timescale 1ns/1ps
module tb_cpu_record_firmware #(parameter integer H=600,CASE_ID=0,BAD_PIXEL=0,NO_CONTROL=0,GAPS=1,QUOTA=4,parameter real PIXEL_HALF=12.5);
 localparam integer N=800*H,HT=1056,VT=H+28;
 reg  clk_i=0;
 reg  rst_ni=0;
 reg  pixel_clk=0;
 reg  pixel_reset_n=0;
 reg  online=0;
 reg  display_urgent=0;
 reg  source_fault=0;
 reg  overflow=0;
 reg  src_valid=0;
 reg [47:0] src_data=0;
 wire  src_ready;
 wire  arm_toggle;
 wire  cancel;
 wire  capture_busy;
 wire  capture_port_drained;
 wire [31:0] c_s_axi_awaddr_i;
 wire [2:0] c_s_axi_awprot_i;
 wire  c_s_axi_awvalid_i;
 wire  c_s_axi_awready_o;
 wire [31:0] c_s_axi_wdata_i;
 wire [3:0] c_s_axi_wstrb_i;
 wire  c_s_axi_wvalid_i;
 wire  c_s_axi_wready_o;
 wire [1:0] c_s_axi_bresp_o;
 wire  c_s_axi_bvalid_o;
 wire  c_s_axi_bready_i;
 wire [31:0] c_s_axi_araddr_i;
 wire [2:0] c_s_axi_arprot_i;
 wire  c_s_axi_arvalid_i;
 wire  c_s_axi_arready_o;
 wire [31:0] c_s_axi_rdata_o;
 wire [1:0] c_s_axi_rresp_o;
 wire  c_s_axi_rvalid_o;
 wire  c_s_axi_rready_i;
 wire [31:0] d_s_axi_awaddr_i;
 wire [2:0] d_s_axi_awprot_i;
 wire  d_s_axi_awvalid_i;
 wire  d_s_axi_awready_o;
 wire [31:0] d_s_axi_wdata_i;
 wire [3:0] d_s_axi_wstrb_i;
 wire  d_s_axi_wvalid_i;
 wire  d_s_axi_wready_o;
 wire [1:0] d_s_axi_bresp_o;
 wire  d_s_axi_bvalid_o;
 wire  d_s_axi_bready_i;
 wire [31:0] d_s_axi_araddr_i;
 wire [2:0] d_s_axi_arprot_i;
 wire  d_s_axi_arvalid_i;
 wire  d_s_axi_arready_o;
 wire [31:0] d_s_axi_rdata_o;
 wire [1:0] d_s_axi_rresp_o;
 wire  d_s_axi_rvalid_o;
 wire  d_s_axi_rready_i;
 reg [10:0] pixel_x=0;
 reg [10:0] pixel_y=0;
 reg  pixel_de=0;
 reg  pixel_hs=0;
 reg  pixel_vs=0;
 reg  pixel_frame_start=0;
 wire [23:0] out_rgb;
 wire  out_de;
 wire  out_hs;
 wire  out_vs;
 wire  irq_capture;
 wire  irq_display;
 wire [2:0] faults;
 wire [7:0] capture_code;
 wire [7:0] display_code;
 wire [7:0] memory_code;
 wire [31:0] raw_commits;
 wire [31:0] raw_scans;
 wire [31:0] underflows;
 wire [31:0] raw_frame;
 wire [31:0] read_grants;
 wire [31:0] write_grants;
 wire [27:0] h_awaddr;
 wire [27:0] h_araddr;
 wire [3:0] h_awlen;
 wire [3:0] h_arlen;
 wire [3:0] h_awid;
 wire [3:0] h_arid;
 wire  h_awvalid;
 wire  h_arvalid;
 wire  h_awready;
 wire  h_arready;
 wire  h_wready;
 wire  h_rvalid;
 wire [255:0] h_wdata;
 wire [31:0] h_wstrb;
 wire [255:0] h_rdata;
 wire [3:0] h_wid;
 wire [3:0] h_rid;
 wire  h_wlast;
 wire  h_rlast;
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
 wire  raw_context_valid;
 wire [1:0] raw_slot;
 wire [31:0] raw_generation;
 wire [10:0] raw_x;
 wire [10:0] raw_y;
 wire [23:0] raw_rgb;
 wire  raw_de;
 wire  raw_hs;
 wire  raw_vs;
 wire  raw_sof;
 wire [10:0] out_x;
 wire [10:0] out_y;
 wire [31:0] out_frame;
 wire [31:0] out_generation;
 wire [31:0] out_seq;
 wire [1:0] out_slot;
 wire [1:0] out_mode;
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
 wire [2:0] render_faults;
 wire [7:0] read_code;
 wire [7:0] material_code;
 wire [7:0] pixels_code;
 wire  port_drained;
 wire [31:0] raw_grants;
 wire [31:0] asset_grants;
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
 wire [7:0] link_code;
 wire [7:0] raw_code;
 integer cycles=0;wire irq_o=1'b0;always #4 clk_i=~clk_i;always #(PIXEL_HALF)pixel_clk=~pixel_clk;
 always @*begin pixel_de=pixel_x<800&&pixel_y<H;pixel_hs=pixel_x>=840&&pixel_x<968;pixel_vs=pixel_y>=H+1&&pixel_y<H+5;pixel_frame_start=pixel_x==0&&pixel_y==0;end
    video_record_pipeline #(.FRAME_HEIGHT(H),.MAX_READ_BURSTS(QUOTA),.TIMEOUT_CYCLES(10000000)) dut(.*);
    reg [95:0] slot_tags=0;integer written,read_beats,aw_commands,ar_commands;
    video_record_pipeline_memory #(.H(H),.GAPS(GAPS),.CORRUPT(BAD_PIXEL!=0)) memory(
        .clk(clk_i),.reset_n(rst_ni),.slot_tags(slot_tags),
        .h_awaddr(h_awaddr),.h_araddr(h_araddr),.h_awlen(h_awlen),.h_arlen(h_arlen),.h_awid(h_awid),.h_arid(h_arid),
        .h_awvalid(h_awvalid),.h_arvalid(h_arvalid),.h_awready(h_awready),.h_arready(h_arready),.h_wready(h_wready),.h_rvalid(h_rvalid),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_rdata(h_rdata),.h_wid(h_wid),.h_rid(h_rid),.h_wlast(h_wlast),.h_rlast(h_rlast),
        .write_bytes(written),.read_beats(read_beats),.aw_commands(aw_commands),.ar_commands(ar_commands));
    function automatic [7:0] source_byte(input integer x,y,c,tag);
        source_byte=8'(37*x+19*y+83*c+((x*y)>>3)+tag*43+tag*x);
    endfunction
    reg [31:0] crcs[0:4];string crc_path;
    reg old_arm=0,enabled=0;integer sent=0;
    always @* begin
        src_valid=enabled&&sent<=N;
        if(sent<N)src_data={2'b00,(sent%800==799),21'd0,source_byte(sent%800,sent/800,0,int'(dut.capture_frame_id_i)),
            source_byte(sent%800,sent/800,1,int'(dut.capture_frame_id_i)),source_byte(sent%800,sent/800,2,int'(dut.capture_frame_id_i))};
        else src_data={2'b01,1'b0,(CASE_ID!=1),12'd37,crcs[dut.capture_frame_id_i]};
    end
 reg [31:0] shadow_model[0:159],mode_model=0,seq_model=0,proven_seq=0;
    reg [2:0] display_lease=0,completed_slot=0;reg [31:0] slot_frames[0:2];
    integer capture_requests=0,completions=0,records=0,feedbacks=0,retires=0,overlap=0,held_release_capture=0,contested=0,ticks=0;
    integer outstanding_reads=0,read_slot=0;reg [31:0] visible_frame=0;
    always @(posedge clk_i)if(rst_ni)begin
        ticks=ticks+1;
        if(CASE_ID==0&&faults!=0)$fatal(1,"PIPELINE_FAULT sources=%b codes=%h/%h/%h",faults,capture_code,display_code,memory_code);
        if(old_arm!=arm_toggle)begin enabled<=1;sent<=0;end old_arm<=arm_toggle;
        if(src_valid&&src_ready)begin sent<=sent+1;if(sent==N)enabled<=0;end
        if(dut.capture_req_valid_o&&dut.capture_req_ready_i)begin
            if(display_lease[dut.capture_req_slot_o]||!dut.u_display.u_mmio.slot_free[dut.capture_req_slot_o])$fatal(1,"PIPELINE_REQUEST_REUSED_REFERENCE");
            slot_tags[dut.capture_req_slot_o*32+:32]=dut.capture_req_frame_id_o;
            slot_frames[dut.capture_req_slot_o]=dut.capture_req_frame_id_o;completed_slot[dut.capture_req_slot_o]=0;
            capture_requests=capture_requests+1;
        end
        if(dut.completion_valid_i&&dut.completion_ready_o)begin
            if(dut.completion_success_i)begin
                if(!capture_port_drained||dut.c_bvalid)$fatal(1,"PIPELINE_COMPLETION_BEFORE_B");
                completed_slot[dut.capture_slot_i]=1;completions=completions+1;
            end
        end
        if(dut.c_awvalid&&dut.c_awready&&(!dut.u_display.u_mmio.slot_free[dut.capture_slot_i]||display_lease[dut.capture_slot_i]))
            $fatal(1,"PIPELINE_CAPTURE_OVERWROTE_DISPLAY");
        if(dut.u_display.record_valid&&dut.u_display.record_ready)begin
            if(display_lease[dut.u_display.record_slot]||!completed_slot[dut.u_display.record_slot]||
                slot_frames[dut.u_display.record_slot]!==dut.u_display.record_frame)$fatal(1,"PIPELINE_PRESENT_BEFORE_QUALIFIED_CAPTURE");
            display_lease[dut.u_display.record_slot]=1;records=records+1;
        end
        if(dut.u_display.raw_commit_valid)visible_frame=dut.u_display.raw_commit_frame;
        if(dut.u_display.feedback_valid&&dut.u_display.feedback_ready)feedbacks=feedbacks+1;
        if(dut.u_display.retire_valid&&dut.u_display.retire_ready)begin
            if(!display_lease[dut.u_display.retire_slot])$fatal(1,"RECORD_PIPELINE_RETIRE_UNLEASED");display_lease[dut.u_display.retire_slot]=0;retires=retires+1;end
        if(dut.u_display.raw_release_valid&&dut.u_display.raw_release_ready)begin
            if(outstanding_reads!=0&&read_slot==dut.u_display.raw_release_slot)$fatal(1,"PIPELINE_RELEASE_WITH_READ");
            if(!display_lease[dut.u_display.raw_release_slot])$fatal(1,"PIPELINE_RELEASE_UNOWNED");

        end
        if(dut.u_display.d_arvalid&&dut.u_display.d_arready)begin
            read_slot=int'((dut.u_display.d_araddr-32'h82000000)/32'h200000);
            if(outstanding_reads!=0||read_slot<0||read_slot>2||!display_lease[read_slot])$fatal(1,"PIPELINE_SCAN_READ_AFTER_RELEASE");
            outstanding_reads=int'(dut.u_display.d_arlen)+1;
        end
        if(dut.u_display.d_rvalid&&dut.u_display.d_rready)outstanding_reads=outstanding_reads-1;
        if(capture_busy&&raw_frame!=0)overlap=overlap+1;
        if(capture_busy&&dut.u_display.u_mmio.release_valid)held_release_capture=held_release_capture+1;
        if(dut.c_awvalid&&dut.u_display.d_arvalid)contested=contested+1;
        if(dut.u_display.u_mmio.commit_valid&&dut.u_display.u_mmio.commit_seq!==proven_seq)$fatal(1,"RECORD_PIPELINE_UNPROVEN_COMMIT");
        if(ticks%1000000==0)begin $display("PIPELINE_PROGRESS ticks=%0d requests=%0d completed=%0d records=%0d scans=%0d pixels=%0d",ticks,capture_requests,completions,records,raw_scans,checked_pixels);$fflush();end
    end
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==HT-1)begin pixel_x<=0;if(pixel_y==VT-1)pixel_y<=0;else pixel_y<=pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
 reg [27:0] expected[0:4*N-1];reg [31:0] crc_file[0:0];string directory;
 integer issued_mode=0,issued_slot=0,issued_frame=0,issued_generation=0,issued_seq=0,reference_mode=0,reference_seq=0;
 integer checked_pixels=0,mode_pixels[0:2],seq_pixels[0:4],asset_events=0,asset_hold=0;
 reg [13:0] vp=0;integer k;reg [10:0] xs[0:13],ys[0:13];reg [3:0] ts[0:13];reg [23:0] rgbs[0:13];reg qualified[0:13];
 reg [31:0] frames[0:13],gens[0:13];reg [1:0] slots[0:13];integer modes[0:13],seqs[0:13];reg [27:0] wanted;
 reg [10:0] x0=0,x1=0,y0=0,y1=0;reg [2:0] t0=0,t1=0;integer warmup=0;
 always @(posedge pixel_clk)begin
  if(!pixel_reset_n)begin vp<=0;reference_mode=0;reference_seq=0;proven_seq=0;warmup=0;end
  else begin
   if(pixel_pending&&raw_sof&&raw_context_valid&&raw_slot==issued_slot&&raw_frame==issued_frame&&raw_generation==issued_generation&&(issued_mode!=2||pixel_material_ready))begin reference_mode=issued_mode;reference_seq=issued_seq;end
   for(k=13;k>0;k=k-1)begin xs[k]=xs[k-1];ys[k]=ys[k-1];ts[k]=ts[k-1];rgbs[k]=rgbs[k-1];qualified[k]=qualified[k-1];frames[k]=frames[k-1];gens[k]=gens[k-1];slots[k]=slots[k-1];modes[k]=modes[k-1];seqs[k]=seqs[k-1];end
   xs[0]=raw_x;ys[0]=raw_y;ts[0]={raw_de,raw_hs,raw_vs,raw_sof};rgbs[0]=raw_rgb;qualified[0]=raw_context_valid&&reference_seq!=0;frames[0]=raw_frame;gens[0]=raw_generation;slots[0]=raw_slot;modes[0]=reference_mode;seqs[0]=reference_seq;
   x0<=pixel_x;x1<=x0;y0<=pixel_y;y1<=y0;t0<={pixel_de,pixel_hs,pixel_vs};t1<=t0;vp<={vp[12:0],1'b1};warmup=warmup+1;#1;
   if(warmup>4)begin
    if({raw_x,raw_y,raw_de,raw_hs,raw_vs}!=={x1,y1,t1})$fatal(1,"RECORD_PIPELINE_RAW_ALIGNMENT");
    if(raw_context_valid)begin
     if(raw_rgb!=={source_byte(raw_x,raw_y,0,raw_frame),source_byte(raw_x,raw_y,1,raw_frame),source_byte(raw_x,raw_y,2,raw_frame)}||raw_generation!=47||raw_frame<1||raw_frame>2||raw_slot!=raw_frame-1)$fatal(1,"RECORD_PIPELINE_RAW_BYTES_OR_ID");
    end else if(raw_rgb!==24'h101820||raw_sof)$fatal(1,"RECORD_PIPELINE_RAW_BACKGROUND");
   end
   if(vp[13])begin
    if({out_x,out_y,out_de,out_hs,out_vs,out_sof,out_frame,out_generation,out_slot,out_mode,out_seq}!=={xs[13],ys[13],ts[13],frames[13],gens[13],slots[13],2'(modes[13]),32'(seqs[13])})$fatal(1,"RECORD_PIPELINE_OUTPUT_METADATA");
    if(out_de&&out_sof&&qualified[13])proven_seq=out_seq;
    if(qualified[13])begin
     wanted=expected[(frames[13]==1?modes[13]:3)*N+ys[13]*800+xs[13]];
     if({out_fault,out_avatar,out_point,out_box,out_rgb}!==wanted)$fatal(1,"RECORD_PIPELINE_PIXEL_ORACLE frame=%0d mode=%0d x=%0d y=%0d got=%h wanted=%h",frames[13],modes[13],xs[13],ys[13],{out_fault,out_avatar,out_point,out_box,out_rgb},wanted);
     checked_pixels=checked_pixels+1;mode_pixels[modes[13]]=mode_pixels[modes[13]]+1;
     if(seqs[13]>=100&&seqs[13]<=104)seq_pixels[seqs[13]-100]=seq_pixels[seqs[13]-100]+1;
    end else if(out_rgb!==rgbs[13]||{out_fault,out_avatar,out_point,out_box}!==0)$fatal(1,"RECORD_PIPELINE_OUTPUT_BYPASS");
   end
  end
 end
 always @(posedge clk_i)if(rst_ni)begin
  if(asset_retire_valid)begin
   if(asset_retire_id!=7||asset_retire_generation_id!=71||asset_retire_frame!=1||asset_retire_generation!=47||asset_retire_seq!=102)$fatal(1,"RECORD_PIPELINE_ASSET_RETIRE");
   if(asset_retire_ready)begin asset_events=asset_events+1;asset_retire_ready<=0;asset_hold<=0;end
   else if(asset_hold==30)asset_retire_ready<=1;else asset_hold<=asset_hold+1;
  end
 end
 wire [31:0] s_axi_awaddr_i;
 wire [63:0] m_axi_awaddr_o;
 assign c_s_axi_awaddr_i = m_axi_awaddr_o[0 +: 32];
 assign d_s_axi_awaddr_i = m_axi_awaddr_o[32 +: 32];
 wire [2:0] s_axi_awprot_i;
 wire [5:0] m_axi_awprot_o;
 assign c_s_axi_awprot_i = m_axi_awprot_o[0 +: 3];
 assign d_s_axi_awprot_i = m_axi_awprot_o[3 +: 3];
 wire s_axi_awvalid_i;
 wire [1:0] m_axi_awvalid_o;
 assign c_s_axi_awvalid_i = m_axi_awvalid_o[0 +: 1];
 assign d_s_axi_awvalid_i = m_axi_awvalid_o[1 +: 1];
 wire s_axi_awready_o;
 wire [1:0] m_axi_awready_i;
 assign m_axi_awready_i[0 +: 1] = c_s_axi_awready_o;
 assign m_axi_awready_i[1 +: 1] = d_s_axi_awready_o;
 wire [31:0] s_axi_wdata_i;
 wire [63:0] m_axi_wdata_o;
 assign c_s_axi_wdata_i = m_axi_wdata_o[0 +: 32];
 assign d_s_axi_wdata_i = m_axi_wdata_o[32 +: 32];
 wire [3:0] s_axi_wstrb_i;
 wire [7:0] m_axi_wstrb_o;
 assign c_s_axi_wstrb_i = m_axi_wstrb_o[0 +: 4];
 assign d_s_axi_wstrb_i = m_axi_wstrb_o[4 +: 4];
 wire s_axi_wvalid_i;
 wire [1:0] m_axi_wvalid_o;
 assign c_s_axi_wvalid_i = m_axi_wvalid_o[0 +: 1];
 assign d_s_axi_wvalid_i = m_axi_wvalid_o[1 +: 1];
 wire s_axi_wready_o;
 wire [1:0] m_axi_wready_i;
 assign m_axi_wready_i[0 +: 1] = c_s_axi_wready_o;
 assign m_axi_wready_i[1 +: 1] = d_s_axi_wready_o;
 wire [1:0] s_axi_bresp_o;
 wire [3:0] m_axi_bresp_i;
 assign m_axi_bresp_i[0 +: 2] = c_s_axi_bresp_o;
 assign m_axi_bresp_i[2 +: 2] = d_s_axi_bresp_o;
 wire s_axi_bvalid_o;
 wire [1:0] m_axi_bvalid_i;
 assign m_axi_bvalid_i[0 +: 1] = c_s_axi_bvalid_o;
 assign m_axi_bvalid_i[1 +: 1] = d_s_axi_bvalid_o;
 wire s_axi_bready_i;
 wire [1:0] m_axi_bready_o;
 assign c_s_axi_bready_i = m_axi_bready_o[0 +: 1];
 assign d_s_axi_bready_i = m_axi_bready_o[1 +: 1];
 wire [31:0] s_axi_araddr_i;
 wire [63:0] m_axi_araddr_o;
 assign c_s_axi_araddr_i = m_axi_araddr_o[0 +: 32];
 assign d_s_axi_araddr_i = m_axi_araddr_o[32 +: 32];
 wire [2:0] s_axi_arprot_i;
 wire [5:0] m_axi_arprot_o;
 assign c_s_axi_arprot_i = m_axi_arprot_o[0 +: 3];
 assign d_s_axi_arprot_i = m_axi_arprot_o[3 +: 3];
 wire s_axi_arvalid_i;
 wire [1:0] m_axi_arvalid_o;
 assign c_s_axi_arvalid_i = m_axi_arvalid_o[0 +: 1];
 assign d_s_axi_arvalid_i = m_axi_arvalid_o[1 +: 1];
 wire s_axi_arready_o;
 wire [1:0] m_axi_arready_i;
 assign m_axi_arready_i[0 +: 1] = c_s_axi_arready_o;
 assign m_axi_arready_i[1 +: 1] = d_s_axi_arready_o;
 wire [31:0] s_axi_rdata_o;
 wire [63:0] m_axi_rdata_i;
 assign m_axi_rdata_i[0 +: 32] = c_s_axi_rdata_o;
 assign m_axi_rdata_i[32 +: 32] = d_s_axi_rdata_o;
 wire [1:0] s_axi_rresp_o;
 wire [3:0] m_axi_rresp_i;
 assign m_axi_rresp_i[0 +: 2] = c_s_axi_rresp_o;
 assign m_axi_rresp_i[2 +: 2] = d_s_axi_rresp_o;
 wire s_axi_rvalid_o;
 wire [1:0] m_axi_rvalid_i;
 assign m_axi_rvalid_i[0 +: 1] = c_s_axi_rvalid_o;
 assign m_axi_rvalid_i[1 +: 1] = d_s_axi_rvalid_o;
 wire s_axi_rready_i;
 wire [1:0] m_axi_rready_o;
 assign c_s_axi_rready_i = m_axi_rready_o[0 +: 1];
 assign d_s_axi_rready_i = m_axi_rready_o[1 +: 1];
 video_axil_decode u_decode(.*);
    reg [7:0] rom[0:32767],sram[0:32767];
    string image_path,signature_path;
    integer fd,image_size,lane,native_requests=0,native_responses=0,native_errors=0;
    integer axi_reads=0,axi_writes=0,axi_write_data=0,axi_read_errors=0,axi_write_errors=0;
    integer accepted_events=0,completion_events=0,retired=0,ifetch_stalls=0,data_stalls=0;
    integer eof_wait=0,final_wait=0,irq_rises=0,irq_falls=0;
    reg bus_pending=0,local_pending=0,local_ack=0,local_error=0;
    reg [31:0] local_data=0,saved_local_data=0;
    reg [10:0] local_tag=0,saved_local_tag=0,expected_native_tag=0;
    integer local_delay=0,fetch_delay=0;
    reg fetch_pending=0,fetch_valid=0;
    reg [63:0] fetch_data=0,saved_fetch_data=0;
    wire [31:0] d_addr,d_wdata,i_pc;
    wire [10:0] request_tag;
    wire d_rd,i_rd,d_cacheable,d_invalidate,d_writeback,d_flush;
    wire [3:0] d_wr;
    wire memory_select=d_addr<32768||(d_addr>=32'h10000&&d_addr<32'h18000);
    wire native_request_enable=!bus_pending&&!memory_select&&(NO_CONTROL==0);
    wire native_accept,native_ack,native_error;
    wire [31:0] native_rdata;
    wire [10:0] native_tag;
    wire d_accept=rst_ni&&!bus_pending&&(memory_select?(cycles%4!=0):native_accept);
    wire d_ack=local_ack||native_ack;
    wire d_error=local_ack?local_error:native_error;
    wire [31:0] d_data=local_ack?local_data:native_rdata;
    wire [10:0] d_tag=local_ack?local_tag:native_tag;
    wire i_accept=rst_ni&&!fetch_pending&&(cycles%3!=0);
    cpu_native_axil u_adapter(
        .clk_i(clk_i),.rst_ni(rst_ni),.cpu_addr_i(d_addr),.cpu_wdata_i(d_wdata),
        .cpu_re_i(d_rd&&native_request_enable),.cpu_wstrb_i(d_wr&{4{native_request_enable}}),
        .cpu_cacheable_i(d_cacheable),.cpu_req_tag_i(request_tag),
        .cpu_invalidate_i(d_invalidate&&native_request_enable),
        .cpu_writeback_i(d_writeback&&native_request_enable),.cpu_flush_i(d_flush&&native_request_enable),
        .cpu_rdata_o(native_rdata),.cpu_accept_o(native_accept),.cpu_ack_o(native_ack),
        .cpu_error_o(native_error),.cpu_resp_tag_o(native_tag),
        .m_axi_awaddr_o(s_axi_awaddr_i),.m_axi_awprot_o(s_axi_awprot_i),
        .m_axi_awvalid_o(s_axi_awvalid_i),.m_axi_awready_i(s_axi_awready_o),
        .m_axi_wdata_o(s_axi_wdata_i),.m_axi_wstrb_o(s_axi_wstrb_i),
        .m_axi_wvalid_o(s_axi_wvalid_i),.m_axi_wready_i(s_axi_wready_o),
        .m_axi_bresp_i(s_axi_bresp_o),.m_axi_bvalid_i(s_axi_bvalid_o),.m_axi_bready_o(s_axi_bready_i),
        .m_axi_araddr_o(s_axi_araddr_i),.m_axi_arprot_o(s_axi_arprot_i),
        .m_axi_arvalid_o(s_axi_arvalid_i),.m_axi_arready_i(s_axi_arready_o),
        .m_axi_rdata_i(s_axi_rdata_o),.m_axi_rresp_i(s_axi_rresp_o),
        .m_axi_rvalid_i(s_axi_rvalid_o),.m_axi_rready_o(s_axi_rready_i));
    triha_cpu #(.SUPPORT_DUAL_ISSUE(0),.SUPPORT_BRANCH_PREDICTION(1),
        .SUPPORT_MULDIV(0),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),
        .SUPPORT_REGFILE_XILINX(0),.SUPPORT_LOAD_BYPASS(1),.SUPPORT_MUL_BYPASS(1)) u_cpu(
        .clk_i(clk_i),.rst_i(!rst_ni),.intr_i(irq_o),.reset_vector_i(32'd0),.cpu_id_i(32'd0),
        .mem_i_accept_i(i_accept),.mem_i_valid_i(fetch_valid),.mem_i_error_i(1'b0),.mem_i_inst_i(fetch_data),
        .mem_i_rd_o(i_rd),.mem_i_pc_o(i_pc),.mem_i_flush_o(),.mem_i_invalidate_o(),
        .mem_d_accept_i(d_accept),.mem_d_ack_i(d_ack),.mem_d_error_i(d_error),
        .mem_d_data_rd_i(d_data),.mem_d_resp_tag_i(d_tag),.mem_d_addr_o(d_addr),
        .mem_d_data_wr_o(d_wdata),.mem_d_rd_o(d_rd),.mem_d_wr_o(d_wr),
        .mem_d_req_tag_o(request_tag),.mem_d_cacheable_o(d_cacheable),
        .mem_d_invalidate_o(d_invalidate),.mem_d_writeback_o(d_writeback),.mem_d_flush_o(d_flush));
    reg [31:0] held_native_addr;reg expected_native_error=0;
    always @(posedge clk_i) if(rst_ni)begin
        cycles<=cycles+1;
        local_ack<=0;fetch_valid<=0;
        if(i_rd&&!i_accept)ifetch_stalls<=ifetch_stalls+1;
        if((d_rd||(|d_wr))&&!d_accept)data_stalls<=data_stalls+1;
        if(i_rd&&i_accept)begin
            if(i_pc>=32768||i_pc[2:0]!=0)$fatal(1,"CPU_VIDEO_FAIL fetch address %h",i_pc);
            fetch_pending<=1;fetch_delay<=cycles%3;
            for(lane=0;lane<8;lane=lane+1)saved_fetch_data[lane*8+:8]<=rom[i_pc+lane];
        end else if(fetch_pending)begin
            if(fetch_delay==0)begin fetch_pending<=0;fetch_valid<=1;fetch_data<=saved_fetch_data;end
            else fetch_delay<=fetch_delay-1;
        end
        if((d_rd||(|d_wr))&&d_accept)begin
            if(bus_pending)$fatal(1,"CPU_VIDEO_FAIL duplicate acceptance");
            bus_pending<=1;
            if(memory_select)begin
                local_pending<=1;local_delay<=cycles%4;saved_local_tag<=request_tag;
                if(d_addr[1:0]!=0||d_cacheable||d_invalidate||d_writeback||d_flush)$fatal(1,"CPU_VIDEO_FAIL memory controls");
                for(lane=0;lane<4;lane=lane+1)begin
                    saved_local_data[lane*8+:8]<=d_addr<32768?rom[d_addr+lane]:sram[d_addr-32'h10000+lane];
                    if(d_wr[lane])begin
                        if(d_addr<32'h10000)$fatal(1,"CPU_VIDEO_FAIL ROM write");
                        sram[d_addr-32'h10000+lane]<=d_wdata[lane*8+:8];
                    end
                end
            end else begin
                native_requests<=native_requests+1;expected_native_tag<=request_tag;
                held_native_addr<=d_addr;
                expected_native_error<=d_addr==32'h20010000||d_addr==32'h20013000||(d_addr==32'h20011000&&|d_wr);
                $display("NATIVE_ACCEPT addr=%h re=%b strb=%h tag=%h",d_addr,d_rd,d_wr,request_tag);
            end
        end else if(local_pending)begin
            if(local_delay==0)begin local_pending<=0;local_ack<=1;local_data<=saved_local_data;local_tag<=saved_local_tag;end
            else local_delay<=local_delay-1;
        end
        if(d_ack)begin
            if(!bus_pending)$fatal(1,"CPU_VIDEO_FAIL unsolicited data ACK");
            bus_pending<=0;
        end
        if(native_ack)begin
            if(native_tag!==expected_native_tag||native_error!==expected_native_error)$fatal(1,"CPU_VIDEO_FAIL native tag/error addr%h",held_native_addr);
            native_responses<=native_responses+1;
            if(native_error)begin
                native_errors<=native_errors+1;
                if(native_rdata!==0)$fatal(1,"CPU_VIDEO_FAIL error data");
            end
            $display("NATIVE_ACK tag=%h error=%b data=%h",native_tag,native_error,native_rdata);
        end
    end
    reg seen_aw=0,seen_w=0;reg [31:0] saved_awaddr,saved_wdata;reg [3:0] saved_wstrb;
    always @(posedge clk_i)if(rst_ni)begin
        if(d_s_axi_awvalid_i&&d_s_axi_awready_o)begin seen_aw=1;saved_awaddr=d_s_axi_awaddr_i;end
        if(d_s_axi_wvalid_i&&d_s_axi_wready_o)begin seen_w=1;saved_wdata=d_s_axi_wdata_i;saved_wstrb=d_s_axi_wstrb_i;end
        if(d_s_axi_bvalid_o&&d_s_axi_bready_i)begin
            if(!seen_aw||!seen_w)$fatal(1,"CPU_RECORD_FAIL missing actual write");
            if(d_s_axi_bresp_o==0)begin
                if(saved_wstrb!=15)$fatal(1,"CPU_RECORD_FAIL driver byte mask");
                if(saved_awaddr>=32'h20011100&&saved_awaddr<32'h20011380)shadow_model[(saved_awaddr-32'h20011100)/4]=saved_wdata;
                if(saved_awaddr==32'h20011024)mode_model=saved_wdata;
                if(saved_awaddr==32'h20011028)seq_model=saved_wdata;
                if(saved_awaddr==32'h20011020)begin issued_mode=mode_model;issued_seq=seq_model;issued_slot=shadow_model[2];issued_frame=shadow_model[3];issued_generation=shadow_model[4];end
            end
            seen_aw=0;seen_w=0;
        end
    end
    function automatic [31:0] signature_word(input integer word_index);
        signature_word={sram[word_index*4+3],sram[word_index*4+2],sram[word_index*4+1],sram[word_index*4]};
    endfunction
    integer outfd,i,word_index;reg [31:0] outcome;
    initial begin
        for(i=0;i<5;i=i+1)seq_pixels[i]=0;for(i=0;i<3;i=i+1)mode_pixels[i]=0;
        for(i=0;i<3;i=i+1)slot_frames[i]=0;
        if(!$value$plusargs("DIR=%s",directory)||!$value$plusargs("CRC=%s",crc_path)||!$value$plusargs("ROM_IMAGE=%s",image_path)||!$value$plusargs("SIGNATURE=%s",signature_path))$fatal(1,"CPU_RECORD_FAIL arguments");
        $readmemh({directory,"/expected.hex"},expected);$readmemh({directory,"/crc.hex"},crc_file);$readmemh(crc_path,crcs);
        for(i=0;i<32768;i=i+1)begin rom[i]=0;sram[i]=0;end
        fd=$fopen(image_path,"rb");if(!fd)$fatal(1,"CPU_RECORD_FAIL ROM open");image_size=$fread(rom,fd);$fclose(fd);
        if(image_size!=32768)$fatal(1,"CPU_RECORD_FAIL ROM size");
        repeat(8)@(negedge clk_i);rst_ni=1;pixel_reset_n=1;online=1;display_urgent=1;
        load_base=32'h82600ff0;load_bytes=262144;load_asset_id=7;load_generation=71;expected_crc=crc_file[0];load_valid=1;
        do @(posedge clk_i);while(!load_ready);@(negedge clk_i);load_valid=0;result_ready=1;
    end
    always @(negedge clk_i)if(rst_ni)begin
        outcome=signature_word(0);
        if(outcome[31:20]==12'hbad)$fatal(1,"CPU_RECORD_FAIL signature=%h stage=%h cause=%h pc=%h",outcome,signature_word(1),u_cpu.u_csr.u_csrfile.csr_mcause_q,i_pc);
        if(cycles>(NO_CONTROL?30000:45000000))$fatal(1,"CPU_RECORD_FAIL timeout stage=%h pc=%h",signature_word(1),i_pc);
        if(outcome==32'h43505246&&!bus_pending&&!d_ack)begin
            if(signature_word(1)!=99||signature_word(2)!=3||native_errors!=3||native_requests!=native_responses||ifetch_stalls==0||data_stalls==0)$fatal(1,"CPU_RECORD_FAIL CPU bus/trap evidence");
            if(CASE_ID==0)begin
                if(capture_requests!=2||completions!=2||records!=2||feedbacks!=5||retires!=1||raw_commits!=2||asset_events!=1||asset_grants!=1025||faults!==0||underflows!==0)$fatal(1,"CPU_RECORD_FAIL actual pipeline counts");
                for(i=0;i<5;i=i+1)if(seq_pixels[i]<N)$fatal(1,"CPU_RECORD_FAIL incomplete raster seq=%0d pixels=%0d",100+i,seq_pixels[i]);
                if(signature_word(3)!=2||signature_word(4)!=3||signature_word(5)!=1)$fatal(1,"CPU_RECORD_FAIL software counts");
            end else if(faults===0||records||feedbacks||completions||!capture_port_drained||signature_word(3)||signature_word(4)||signature_word(5))$fatal(1,"CPU_RECORD_FAIL failed frame published");
            outfd=$fopen(signature_path,"w");if(!outfd)$fatal(1,"CPU_RECORD_FAIL signature open");
            for(word_index=0;word_index<16;word_index=word_index+1)$fdisplay(outfd,"%08h",signature_word(word_index));$fclose(outfd);
            $display("CPU_RECORD_FIRMWARE_PASS case=%0d cycles=%0d native=%0d errors=%0d captures=%0d feedbacks=%0d retires=%0d pixels=%0d raw=%0d box=%0d avatar=%0d bytes=%0d underflows=%0d",CASE_ID,cycles,native_responses,native_errors,completions,feedbacks,retires,checked_pixels,mode_pixels[0],mode_pixels[1],mode_pixels[2],written,underflows);
            $finish;
        end
    end
    initial begin #1000000000;$fatal(1,"CPU_RECORD_FAIL watchdog");end
endmodule
`default_nettype wire
