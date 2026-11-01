`timescale 1ns/1ps
`ifdef BASELINE
`define VAPP_DISPLAY dut.u_display
`elsif COMPACT_APPLICATION
`define VAPP_DISPLAY dut.g_compact.u_display
`else
`define VAPP_DISPLAY dut.g_standard.u_display
`endif
module tb_video_application_engine #(parameter integer H=600,CASE_ID=0,GAPS=1,QUOTA=4,ENABLE_AVATAR=0,ENABLE_COMPACT=0,parameter real PIXEL_HALF=12.5);
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
 reg [31:0] c_s_axi_awaddr_i=0;
 reg [2:0] c_s_axi_awprot_i=0;
 reg  c_s_axi_awvalid_i=0;
 wire  c_s_axi_awready_o;
 reg [31:0] c_s_axi_wdata_i=0;
 reg [3:0] c_s_axi_wstrb_i=0;
 reg  c_s_axi_wvalid_i=0;
 wire  c_s_axi_wready_o;
 wire [1:0] c_s_axi_bresp_o;
 wire  c_s_axi_bvalid_o;
 reg  c_s_axi_bready_i=0;
 reg [31:0] c_s_axi_araddr_i=0;
 reg [2:0] c_s_axi_arprot_i=0;
 reg  c_s_axi_arvalid_i=0;
 wire  c_s_axi_arready_o;
 wire [31:0] c_s_axi_rdata_o;
 wire [1:0] c_s_axi_rresp_o;
 wire  c_s_axi_rvalid_o;
 reg  c_s_axi_rready_i=0;
 reg [31:0] d_s_axi_awaddr_i=0;
 reg [2:0] d_s_axi_awprot_i=0;
 reg  d_s_axi_awvalid_i=0;
 wire  d_s_axi_awready_o;
 reg [31:0] d_s_axi_wdata_i=0;
 reg [3:0] d_s_axi_wstrb_i=0;
 reg  d_s_axi_wvalid_i=0;
 wire  d_s_axi_wready_o;
 wire [1:0] d_s_axi_bresp_o;
 wire  d_s_axi_bvalid_o;
 reg  d_s_axi_bready_i=0;
 reg [31:0] d_s_axi_araddr_i=0;
 reg [2:0] d_s_axi_arprot_i=0;
 reg  d_s_axi_arvalid_i=0;
 wire  d_s_axi_arready_o;
 wire [31:0] d_s_axi_rdata_o;
 wire [1:0] d_s_axi_rresp_o;
 wire  d_s_axi_rvalid_o;
 reg  d_s_axi_rready_i=0;
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
 always #4 clk_i=~clk_i;always #(PIXEL_HALF)pixel_clk=~pixel_clk;
 always @*begin pixel_de=pixel_x<800&&pixel_y<H;pixel_hs=pixel_x>=840&&pixel_x<968;pixel_vs=pixel_y>=H+1&&pixel_y<H+5;pixel_frame_start=pixel_x==0&&pixel_y==0;end
`ifdef BASELINE
    video_record_pipeline #(.FRAME_HEIGHT(H),.MAX_READ_BURSTS(QUOTA),.TIMEOUT_CYCLES(10000000)) dut(.*);
`else
    wire [3:0] c_awid;
    wire [31:0] c_awaddr;
    wire [7:0] c_awlen;
    wire [2:0] c_awsize;
    wire [1:0] c_awburst;
    wire c_awvalid;
    wire c_awready;
    wire [127:0] c_wdata;
    wire [15:0] c_wstrb;
    wire c_wlast;
    wire c_wvalid;
    wire c_wready;
    wire [3:0] c_bid;
    wire [1:0] c_bresp;
    wire c_bvalid;
    wire c_bready;
    wire [3:0] d_arid;
    wire [31:0] d_araddr;
    wire [7:0] d_arlen;
    wire [2:0] d_arsize;
    wire [1:0] d_arburst;
    wire d_arvalid;
    wire d_arready;
    wire [3:0] d_rid;
    wire [127:0] d_rdata;
    wire [1:0] d_rresp;
    wire d_rlast;
    wire d_rvalid;
    wire d_rready;
    wire memory_fault,memory_busy,memory_drained;
    video_application_engine #(.FRAME_HEIGHT(H),.ENABLE_AVATAR(ENABLE_AVATAR),.ENABLE_COMPACT(ENABLE_COMPACT),.TIMEOUT_CYCLES(10000000)) dut(.*);
    video_shared_ddr #(.MAX_READ_BURSTS(QUOTA),.NATIVE_TIMEOUT_CYCLES(10000000)) u_test_transport(
        .clk(clk_i),
        .reset_n(rst_ni),
        .online(online),
        .display_urgent(display_urgent),
        .c_awid(c_awid),
        .d_arid(d_arid),
        .c_awaddr(c_awaddr),
        .d_araddr(d_araddr),
        .c_awlen(c_awlen),
        .d_arlen(d_arlen),
        .c_awsize(c_awsize),
        .d_arsize(d_arsize),
        .c_awburst(c_awburst),
        .d_arburst(d_arburst),
        .c_awvalid(c_awvalid),
        .c_awready(c_awready),
        .c_wdata(c_wdata),
        .c_wstrb(c_wstrb),
        .c_wlast(c_wlast),
        .c_wvalid(c_wvalid),
        .c_wready(c_wready),
        .c_bid(c_bid),
        .c_bresp(c_bresp),
        .c_bvalid(c_bvalid),
        .c_bready(c_bready),
        .d_arvalid(d_arvalid),
        .d_arready(d_arready),
        .d_rid(d_rid),
        .d_rdata(d_rdata),
        .d_rresp(d_rresp),
        .d_rlast(d_rlast),
        .d_rvalid(d_rvalid),
        .d_rready(d_rready),
        .h_awaddr(h_awaddr),
        .h_araddr(h_araddr),
        .h_awlen(h_awlen),
        .h_arlen(h_arlen),
        .h_awid(h_awid),
        .h_arid(h_arid),
        .h_awvalid(h_awvalid),
        .h_arvalid(h_arvalid),
        .h_awready(h_awready),
        .h_arready(h_arready),
        .h_wready(h_wready),
        .h_rvalid(h_rvalid),
        .h_wdata(h_wdata),
        .h_wstrb(h_wstrb),
        .h_rdata(h_rdata),
        .h_wid(h_wid),
        .h_rid(h_rid),
        .h_wlast(h_wlast),
        .h_rlast(h_rlast),
        .fault(memory_fault),
        .fault_code(memory_code),
        .busy(memory_busy),
        .port_drained(memory_drained),
        .read_grants(read_grants),
        .write_grants(write_grants));
`endif
    reg [95:0] slot_tags=0;integer written,read_beats,aw_commands,ar_commands;
    video_record_pipeline_memory #(.H(H),.GAPS(GAPS),.CORRUPT(CASE_ID==2)) memory(
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
    reg [2:0] display_lease=0,completed_slot=0;reg [31:0] slot_frames[0:2];
    integer capture_requests=0,completions=0,records=0,feedbacks=0,retires=0,overlap=0,held_release_capture=0,contested=0,ticks=0;
    integer outstanding_reads=0,read_slot=0;reg [31:0] visible_frame=0;
    always @(posedge clk_i)if(rst_ni)begin
        ticks=ticks+1;
        if(CASE_ID==0&&faults!=0)$fatal(1,"PIPELINE_FAULT sources=%b codes=%h/%h/%h",faults,capture_code,display_code,memory_code);
        if(old_arm!=arm_toggle)begin enabled<=1;sent<=0;end old_arm<=arm_toggle;
        if(src_valid&&src_ready)begin sent<=sent+1;if(sent==N)enabled<=0;end
        if(dut.capture_req_valid_o&&dut.capture_req_ready_i)begin
            if(display_lease[dut.capture_req_slot_o]||!`VAPP_DISPLAY.u_mmio.slot_free[dut.capture_req_slot_o])$fatal(1,"PIPELINE_REQUEST_REUSED_REFERENCE");
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
        if(dut.c_awvalid&&dut.c_awready&&(!`VAPP_DISPLAY.u_mmio.slot_free[dut.capture_slot_i]||display_lease[dut.capture_slot_i]))
            $fatal(1,"PIPELINE_CAPTURE_OVERWROTE_DISPLAY");
        if(`VAPP_DISPLAY.record_valid&&`VAPP_DISPLAY.record_ready)begin
            if(display_lease[`VAPP_DISPLAY.record_slot]||!completed_slot[`VAPP_DISPLAY.record_slot]||
                slot_frames[`VAPP_DISPLAY.record_slot]!==`VAPP_DISPLAY.record_frame)$fatal(1,"PIPELINE_PRESENT_BEFORE_QUALIFIED_CAPTURE");
            display_lease[`VAPP_DISPLAY.record_slot]=1;records=records+1;
        end
        if(`VAPP_DISPLAY.raw_commit_valid)visible_frame=`VAPP_DISPLAY.raw_commit_frame;
        if(`VAPP_DISPLAY.feedback_valid&&`VAPP_DISPLAY.feedback_ready)feedbacks=feedbacks+1;
        if(`VAPP_DISPLAY.retire_valid&&`VAPP_DISPLAY.retire_ready)begin
            if(!display_lease[`VAPP_DISPLAY.retire_slot])$fatal(1,"RECORD_PIPELINE_RETIRE_UNLEASED");display_lease[`VAPP_DISPLAY.retire_slot]=0;retires=retires+1;end
        if(`VAPP_DISPLAY.raw_release_valid&&`VAPP_DISPLAY.raw_release_ready)begin
            if(outstanding_reads!=0&&read_slot==`VAPP_DISPLAY.raw_release_slot)$fatal(1,"PIPELINE_RELEASE_WITH_READ");
            if(!display_lease[`VAPP_DISPLAY.raw_release_slot])$fatal(1,"PIPELINE_RELEASE_UNOWNED");

        end
        if(`VAPP_DISPLAY.d_arvalid&&`VAPP_DISPLAY.d_arready)begin
            read_slot=int'((`VAPP_DISPLAY.d_araddr-32'h82000000)/32'h200000);
            if(outstanding_reads!=0||read_slot<0||read_slot>2||!display_lease[read_slot])$fatal(1,"PIPELINE_SCAN_READ_AFTER_RELEASE");
            outstanding_reads=int'(`VAPP_DISPLAY.d_arlen)+1;
        end
        if(`VAPP_DISPLAY.d_rvalid&&`VAPP_DISPLAY.d_rready)outstanding_reads=outstanding_reads-1;
        if(capture_busy&&raw_frame!=0)overlap=overlap+1;
        if(capture_busy&&`VAPP_DISPLAY.u_mmio.release_valid)held_release_capture=held_release_capture+1;
        if(dut.c_awvalid&&`VAPP_DISPLAY.d_arvalid)contested=contested+1;
        if(`VAPP_DISPLAY.u_mmio.commit_valid&&`VAPP_DISPLAY.u_mmio.commit_seq!==proven_seq)$fatal(1,"RECORD_PIPELINE_UNPROVEN_COMMIT");
        if(ticks%1000000==0)begin $display("PIPELINE_PROGRESS ticks=%0d requests=%0d completed=%0d records=%0d scans=%0d pixels=%0d",ticks,capture_requests,completions,records,raw_scans,checked_pixels);$fflush();end
    end
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==HT-1)begin pixel_x<=0;if(pixel_y==VT-1)pixel_y<=0;else pixel_y<=pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
 reg [27:0] expected[0:4*N-1];reg [31:0] crc_file[0:0];string directory;
 integer issued_mode=0,issued_slot=0,issued_frame=0,issued_generation=0,issued_seq=0,reference_mode=0,reference_seq=0;
 reg [31:0] shadow_model[0:159],mode_model=0,seq_model=0,proven_seq=0;
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
   if(!ENABLE_AVATAR)$fatal(1,"DISABLED_AVATAR_RETIRE");
   if(asset_retire_id!=7||asset_retire_generation_id!=71||asset_retire_frame!=1||asset_retire_generation!=47||asset_retire_seq!=102)$fatal(1,"RECORD_PIPELINE_ASSET_RETIRE");
   if(asset_retire_ready)begin asset_events=asset_events+1;asset_retire_ready<=0;asset_hold<=0;end
   else if(asset_hold==30)asset_retire_ready<=1;else asset_hold<=asset_hold+1;
  end
 end
    task automatic bus_read(input bit disp,input [31:0] off,output reg [31:0] value);
        begin
            @(negedge clk_i);
            if(disp)begin d_s_axi_araddr_i=32'h20011000+off;d_s_axi_arvalid_i=1;end
            else begin c_s_axi_araddr_i=32'h20012000+off;c_s_axi_arvalid_i=1;end
            do @(posedge clk_i);while(!(disp?d_s_axi_arready_o:c_s_axi_arready_o));
            @(negedge clk_i);if(disp)d_s_axi_arvalid_i=0;else c_s_axi_arvalid_i=0;
            while(!(disp?d_s_axi_rvalid_o:c_s_axi_rvalid_o))@(negedge clk_i);
            if((disp?d_s_axi_rresp_o:c_s_axi_rresp_o)!==0)$fatal(1,"PIPELINE_RPC_READ_ERROR");
            value=disp?d_s_axi_rdata_o:c_s_axi_rdata_o;@(negedge clk_i);
        end
    endtask
    task automatic bus_write(input bit disp,input [31:0] off,value,output reg [31:0] response);
        begin
            @(negedge clk_i);
            if(disp)begin d_s_axi_awaddr_i=32'h20011000+off;d_s_axi_wdata_i=value;d_s_axi_awvalid_i=1;d_s_axi_wvalid_i=1;end
            else begin c_s_axi_awaddr_i=32'h20012000+off;c_s_axi_wdata_i=value;c_s_axi_awvalid_i=1;c_s_axi_wvalid_i=1;end
            do @(posedge clk_i);while(!(disp?(d_s_axi_awready_o&&d_s_axi_wready_o):(c_s_axi_awready_o&&c_s_axi_wready_o)));
            @(negedge clk_i);if(disp)begin d_s_axi_awvalid_i=0;d_s_axi_wvalid_i=0;end else begin c_s_axi_awvalid_i=0;c_s_axi_wvalid_i=0;end
            while(!(disp?d_s_axi_bvalid_o:c_s_axi_bvalid_o))@(negedge clk_i);
            response={30'd0,(disp?d_s_axi_bresp_o:c_s_axi_bresp_o)};
            if(disp&&response==0)begin
                if(off>=32'h100&&off<32'h380)shadow_model[(off-32'h100)/4]=value;
                if(off==32'h24)mode_model=value;if(off==32'h28)seq_model=value;
                if(off==32'h20)begin issued_mode=mode_model;issued_seq=seq_model;issued_slot=shadow_model[2];issued_frame=shadow_model[3];issued_generation=shadow_model[4];end
            end
            @(negedge clk_i);
        end
    endtask
    reg [7:0] op,target;reg [31:0] a,b,result;integer rc,loops,i,commands=0;
    initial begin
        for(i=0;i<5;i=i+1)seq_pixels[i]=0;for(i=0;i<3;i=i+1)mode_pixels[i]=0;
        for(i=0;i<3;i=i+1)slot_frames[i]=0;
        if(!$value$plusargs("CRC=%s",crc_path))$fatal(1,"PIPELINE_CRC_REQUIRED");$readmemh(crc_path,crcs);
        if(!$value$plusargs("DIR=%s",directory))$fatal(1,"RECORD_PIPELINE_DIR");
        $readmemh({directory,"/expected.hex"},expected);$readmemh({directory,"/crc.hex"},crc_file);
        c_s_axi_bready_i=1;c_s_axi_rready_i=1;c_s_axi_wstrb_i=15;d_s_axi_bready_i=1;d_s_axi_rready_i=1;d_s_axi_wstrb_i=15;display_urgent=1;
        repeat(8)@(negedge clk_i);rst_ni=1;pixel_reset_n=1;online=1;
        bus_read(1,32'h80,result);
        if(result!==(ENABLE_AVATAR?7:3))$fatal(1,"APPLICATION_SUPPORTED_MODES got=%h",result);
        if(ENABLE_AVATAR)begin
        @(negedge clk_i);load_valid=1;load_base=32'h82600ff0;load_bytes=262144;load_asset_id=7;load_generation=71;expected_crc=crc_file[0];
        do @(posedge clk_i);while(!load_ready);@(negedge clk_i);load_valid=0;
        end else begin
            load_valid=1;repeat(8)@(posedge clk_i);
            if(load_ready||result_valid||asset_ready||pixel_material_ready||asset_grants!=0)$fatal(1,"DISABLED_AVATAR_FALSE_SUCCESS");
            @(negedge clk_i);load_valid=0;
        end
        $display("PIPELINE_RPC_READY");$fflush();
        forever begin
            rc=$fscanf(32'h80000000,"%s %s %h %h",op,target,a,b);
            if(rc!=4)$fatal(1,"PIPELINE_RPC_FORMAT %0d",rc);commands=commands+1;result=0;
            case(op)
                "R":bus_read(target=="D",a,result);
                "W":bus_write(target=="D",a,b,result);
                "F":@(negedge clk_i);
                "A","S":begin
                    loops=0;
                    do begin
                        bus_read(target=="D",op=="S"?'hc:target=="D"?'h14:'h14,result);
                        if(op=="S"?(result&a)==b:(result&a)==a)loops=100000;
                        else begin repeat(1024)@(posedge clk_i);loops=loops+1;end
                    end while(loops<100000);
                    if(op=="S"?(result&a)!=b:(result&a)!=a)$fatal(1,"PIPELINE_RPC_WAIT_TIMEOUT %s %h",target,result);
                end
                "T":repeat(a)@(posedge clk_i);
                "V":begin
                    if(b==99)begin
                        bus_write(1,32'h24,2,result);if(result!=0)$fatal(1,"REJECT_MODE_WRITE");
                        bus_write(1,32'h28,99,result);if(result!=0)$fatal(1,"REJECT_SEQ_WRITE");
                        bus_write(1,32'h20,3,result);if(result!=0)$fatal(1,"REJECT_SUBMIT_WRITE");
                        loops=0;do begin bus_read(1,32'h14,result);loops=loops+1;end while(!result[2]&&loops<100);
                        if(!result[2]||result[0]||`VAPP_DISPLAY.cmd_valid)$fatal(1,"DISABLED_AVATAR_NOT_REJECTED");
                        bus_read(1,32'h6c,result);if(result!=32'h14)$fatal(1,"DISABLED_AVATAR_REJECT_CODE");
                        bus_write(1,32'h18,4,result);if(result!=0)$fatal(1,"REJECT_ACK");
                        issued_mode=0;issued_seq=100;result=0;
                    end else if(b!=0)begin if(b<100||b>104)$fatal(1,"RECORD_PIPELINE_SEQ");wait(seq_pixels[b-100]>=N);end
                    else if(!capture_port_drained||dut.c_bvalid||memory.raw_by_frame[a]!=2400*H||memory.preview_by_frame[a]!=600*H||memory.input_by_frame[a]!=960*(H*2/5+80))$fatal(1,"PIPELINE_NATIVE_COMPLETION_COUNTS frame=%0d",a);
                end
                "E":begin
                    if(a==0)begin
                        wait(seq_pixels[4]>=N);
                        if(H!=600||capture_requests!=2||completions!=2||records!=2||feedbacks!=(ENABLE_AVATAR?5:4)||retires!=1||
                            underflows!=0||faults!=0||overlap==0||read_grants==0||write_grants==0||asset_events!=(ENABLE_AVATAR?1:0)||raw_commits!=2||asset_grants!=(ENABLE_AVATAR?1025:0))
                            $fatal(1,"PIPELINE_FINAL_COVERAGE requests=%0d completed=%0d records=%0d feedbacks=%0d retires=%0d overlap=%0d held=%0d",capture_requests,completions,records,feedbacks,retires,overlap,held_release_capture);
                    end else if(faults==0||completions!=0||records!=0||!capture_port_drained)$fatal(1,"PIPELINE_FAILURE_NOT_CONSERVATIVE");
                    $display("VIDEO_RECORD_PIPELINE_RTL_PASS case=%0d requests=%0d captures=%0d records=%0d feedbacks=%0d retires=%0d bytes=%0d pixels=%0d overlap=%0d held=%0d contested=%0d Rgrants=%0d Wgrants=%0d underflows=%0d commands=%0d",CASE_ID,capture_requests,completions,records,feedbacks,retires,written,checked_pixels,overlap,held_release_capture,contested,read_grants,write_grants,underflows,commands);
                    $display("RECORD_MODE_PIXELS raw=%0d box=%0d avatar=%0d assets=%0d",mode_pixels[0],mode_pixels[1],mode_pixels[2],asset_events);
                    $display("RPC_REPLY 00000000");$fflush();$finish;
                end
                default:$fatal(1,"PIPELINE_RPC_UNKNOWN %s",op);
            endcase
            $display("RPC_REPLY %08x",result);$fflush();
        end
    end
    initial begin #2000000000;$fatal(1,"PIPELINE_WATCHDOG");end
endmodule
`undef VAPP_DISPLAY
`default_nettype wire
