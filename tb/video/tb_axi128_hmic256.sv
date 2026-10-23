`timescale 1ns/1ps
module tb_axi128_hmic256;
 reg clk=0; always #4 clk=!clk;
 reg rst_n=0,init_done=0;
 reg [3:0] awid=0,arid=0;
 reg [31:0] awaddr=0,araddr=0;
 reg [7:0] awlen=0,arlen=0;
 reg [2:0] awsize=4,arsize=4;
 reg [1:0] awburst=1,arburst=1;
 reg awvalid=0,arvalid=0,wvalid=0,wlast=0,bready=0,rready=0;
 reg [127:0] wdata=0; reg [15:0] wstrb=0;
 wire awready,arready,wready,bvalid,rvalid,rlast,fault;
 wire [7:0] fault_code;
 wire [3:0] bid,rid; wire [1:0] bresp,rresp; wire [127:0] rdata;
 wire [27:0] h_awaddr,h_araddr;
 wire [3:0] h_awlen,h_arlen,h_awid,h_arid,h_wid,h_rid;
 wire h_awvalid,h_arvalid,h_awready,h_arready,h_wready,h_rvalid,h_wlast,h_rlast;
 wire [255:0] h_wdata,h_rdata; wire [31:0] h_wstrb;
 reg gaps=0,hold_aw=0,hold_ar=0,hold_w=0,hold_r=0,idle_wready=0;
 reg [3:0] bad_wid=0,bad_rid=0;
 reg bad_wlast=0,bad_rlast=0,x_read=0,inject_r=0;
 reg [255:0] read_xor=0;
 integer aw_commands,ar_commands,write_beats,read_beats,first_w,first_r;
 integer cases=0,n,half,mode,k,j,seed,serial=0,before_aw,before_ar,before_w;
 reg [31:0] address;
 reg [7:0] overlap[0:255];
 reg [127:0] overlap_pattern,overlap_expected;
 reg [15:0] overlap_mask;
`ifdef LEGACY_BASELINE
 axi128_hmic256 dut(.*);
`else
 axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(24)) dut(.*);
`endif
 axi_bridge_native_model memory(.*);
 task automatic check(input bit condition,input string message);
  if(condition!==1'b1) $fatal(1,"AXI bridge FAIL case=%0d %s fault=%b code=%h B=%b/%h native AW/AR/W/R=%0d/%0d/%0d/%0d @%0t",cases,message,fault,fault_code,bresp,bid,aw_commands,ar_commands,write_beats,read_beats,$time);
 endtask
 function automatic [127:0] pattern(input integer beat,input integer salt);
  integer b;
  begin for(b=0;b<16;b=b+1) pattern[b*8+:8]=(salt*37+beat*19+b*7+1)&255; end
 endfunction
 function automatic [15:0] strobe(input integer beat,input integer selected);
  case(selected)
   0:strobe=16'hffff;
   1:strobe=16'h1 << (beat%16);
   2:strobe=beat%2 ? 16'h3c96:16'ha55a;
   default:strobe=0;
  endcase
 endfunction
 task automatic restart;
  begin
   @(negedge clk);rst_n=0;init_done=0;awvalid=0;arvalid=0;wvalid=0;bready=0;rready=0;
   gaps=0;hold_aw=0;hold_ar=0;hold_w=0;hold_r=0;idle_wready=0;
   bad_wid=0;bad_rid=0;bad_wlast=0;bad_rlast=0;x_read=0;inject_r=0;read_xor=0;
   repeat(4) @(negedge clk);
   rst_n=1;repeat(3) @(negedge clk);
   check(!awready&&!arready&&!wready&&!h_awvalid&&!h_arvalid,"access before init");
   init_done=1;repeat(2) @(negedge clk);
   check(awready&&arready&&!fault,"online after coordinated reset");
   cases=cases+1;
  end
 endtask
 task automatic start_write(input [31:0] a,input integer count,input [3:0] id,input [2:0] size,input [1:0] burst);
  integer t; bit accepted;
  begin
   @(negedge clk);awaddr=a;awlen=count-1;awid=id;awsize=size;awburst=burst;awvalid=1;
   t=0;accepted=0;
   while(!accepted&&t<200) begin @(posedge clk);accepted=awready;t=t+1;end
   check(accepted,"AW blocked");@(negedge clk);awvalid=0;
  end
 endtask
 task automatic send_write(input integer count,input integer salt,input integer selected,input integer last_error,input bit pauses);
  integer b,t;bit accepted;
  begin
   for(b=0;b<count;b=b+1) begin
    @(negedge clk);wvalid=1;wdata=pattern(b,salt);wstrb=strobe(b,selected);
    wlast=last_error==1 ? (b==0) : last_error==2 ? 1'b0:(b==count-1);
    t=0;accepted=0;
    while(!accepted&&t<500) begin @(posedge clk);accepted=wready;t=t+1;end
    check(accepted,"W drain blocked");
    @(negedge clk);wvalid=0;
    if(pauses) repeat(b%3) @(negedge clk);
   end
  end
 endtask
 task automatic finish_b(input [1:0] response,input [3:0] id,input integer stalls);
  integer t;
  begin
   t=0;
   while(!bvalid&&t<1000) begin @(negedge clk);t=t+1;end
   check(bvalid,"B missing (native retirement or timeout)");
   check(bresp===response&&bid===id,"B response or ID");
   repeat(stalls) begin @(negedge clk);check(bvalid&&bresp===response&&bid===id,"stalled B changed");end
   bready=1;@(negedge clk);bready=0;
  end
 endtask
 task automatic start_read(input [31:0] a,input integer count,input [3:0] id,input [2:0] size,input [1:0] burst);
  integer t;bit accepted;
  begin
   @(negedge clk);araddr=a;arlen=count-1;arid=id;arsize=size;arburst=burst;arvalid=1;
   t=0;accepted=0;
   while(!accepted&&t<200) begin @(posedge clk);accepted=arready;t=t+1;end
   check(accepted,"AR blocked");@(negedge clk);arvalid=0;
  end
 endtask
 task automatic finish_read(input integer count,input [1:0] response,input [3:0] id,input integer salt,input integer selected,input bit zeros,input bit pauses);
  integer b,t,byte_index;reg [127:0] expected,data;
  reg [15:0] mask;
  begin
   for(b=0;b<count;b=b+1) begin
    t=0;
    while(!rvalid&&t<1000) begin @(negedge clk);t=t+1;end
    check(rvalid,"R missing");
    expected=pattern(b,salt);mask=strobe(b,selected);
    for(byte_index=0;byte_index<16;byte_index=byte_index+1)
     if(zeros||!mask[byte_index]) expected[byte_index*8+:8]=0;
    check(rdata===expected&&rresp===response&&rid===id&&rlast===(b==count-1),"R bytes/ID/response/LAST");
    data=rdata;
    if(pauses) repeat(2+b%3) begin @(negedge clk);check(rvalid&&rdata===data,"R data hold");end
    rready=1;@(negedge clk);rready=0;
   end
  end
 endtask
 task automatic good_burst(input [31:0] a,input integer count,input integer selected,input integer salt);
  integer b,q,wb,rb,aw0,ar0;reg [127:0] p;reg [15:0] m;reg [7:0] guard_lo,guard_hi;
  begin
   cases=cases+1;wb=write_beats;rb=read_beats;aw0=aw_commands;ar0=ar_commands;
   guard_lo=memory.byte_at(a-32'h80000000-1);guard_hi=memory.byte_at(a-32'h80000000+count*16);
   start_write(a,count,salt%16,4,1);
   send_write(count,salt,selected,0,1);
   finish_b(0,salt%16,3);
   check(aw_commands==aw0+1&&ar_commands==ar0+1,"one write + mandatory verification command");
   check(write_beats-wb==((count+(a[4]?1:0)+1)/2),"native write count");
   check(read_beats-rb==write_beats-wb,"B preceded verification read completion");
   for(b=0;b<count;b=b+1) begin
    p=pattern(b,salt);m=strobe(b,selected);
    for(q=0;q<16;q=q+1)
     check(memory.byte_at(a-32'h80000000+b*16+q)===(m[q]?p[q*8+:8]:8'b0),"independent byte memory");
   end
   check(memory.byte_at(a-32'h80000000-1)===guard_lo&&memory.byte_at(a-32'h80000000+count*16)===guard_hi,"guard bytes preserved");
   start_read(a,count,(salt+7)%16,4,1);
   finish_read(count,0,(salt+7)%16,salt,selected,0,1);
   check(!fault,"good burst faulted");
  end
 endtask
 task automatic reject(input [31:0] a,input integer count,input [2:0] size,input [1:0] burst);
  integer aw0,ar0,wb;
  begin
   cases=cases+1;aw0=aw_commands;ar0=ar_commands;wb=write_beats;
   start_write(a,count,9,size,burst);send_write(count,44,0,0,1);finish_b(3,9,2);
   check(aw_commands==aw0&&ar_commands==ar0&&write_beats==wb&&!fault,"rejected write touched native or faulted");
   start_read(a,count,11,size,burst);finish_read(count,3,11,0,0,1,1);
   check(aw_commands==aw0&&ar_commands==ar0&&!fault,"rejected read touched native or faulted");
  end
 endtask
 // Independent protocol hold monitors (all payload fields, including ID/LAST).
 reg hb=0,hr=0,haw=0,har=0,owned_write=0;
 integer collected_w=0,advertised_w=0;
 reg [5:0] bp;reg [134:0] rp;reg [35:0] awp,arp;
 always @(posedge clk) begin
  if(!rst_n) begin hb<=0;hr<=0;haw<=0;har<=0;owned_write<=0;collected_w<=0;advertised_w<=0;end
  else begin
   if(awvalid&&awready) begin owned_write<=1;advertised_w<=awlen+1;collected_w<=0;end
   if(wvalid&&wready) begin check(owned_write,"W accepted before AW");collected_w<=collected_w+1;end
   if(h_awvalid) check(owned_write&&collected_w==advertised_w,"native AW before full AXI burst buffered");
   if(bvalid&&bready) begin check(collected_w==advertised_w,"B before full W drain");owned_write<=0;end
   if(hb) check(bvalid&&{bid,bresp}===bp,"B hold monitor");
   if(hr) check(rvalid&&{rid,rresp,rlast,rdata}===rp,"R hold monitor");
   if(haw) check(h_awvalid&&{h_awaddr,h_awlen,h_awid}===awp,"native AW hold monitor");
   if(har) check(h_arvalid&&{h_araddr,h_arlen,h_arid}===arp,"native AR hold monitor");
   hb<=bvalid&&!bready;bp<={bid,bresp};hr<=rvalid&&!rready;rp<={rid,rresp,rlast,rdata};
   haw<=h_awvalid&&!h_awready;awp<={h_awaddr,h_awlen,h_awid};
   har<=h_arvalid&&!h_arready;arp<={h_araddr,h_arlen,h_arid};
  end
 end
 initial begin
  restart;
  // Earliest acceptance-cycle W and R, then continuous beats; full/lane masks.
  good_burst(32'h80000000,1,0,1);
  for(n=1;n<=16;n=n+1)
   for(half=0;half<2;half=half+1)
    for(mode=0;mode<4;mode=mode+1) begin
     gaps=serial%2;address=32'h80010000+serial*512+half*16;
     good_burst(address,n,mode,serial+2);serial=serial+1;
    end
  gaps=0;good_burst(32'h87fffff0,1,0,201);
  good_burst(32'h87ffff00,15,2,202);
  good_burst(32'h80000ff0,1,0,203);
  check(first_w>0&&first_r>0,"earliest native beats covered");
  // Logical alias, wrap, overflow, both window boundaries, size/burst/alignment.
  reject(32'h00000000,1,4,1);reject(32'h7ffffff0,1,4,1);
  reject(32'h88000000,1,4,1);reject(32'hffffffff,1,4,1);
  reject(32'hfffffff0,16,4,1);reject(32'h87fffff0,2,4,1);
  reject(32'h80000ff0,2,4,1);reject(32'h80000001,1,4,1);
  reject(32'h80001000,17,4,1);reject(32'h80001000,256,4,1);
  reject(32'h80001000,1,3,1);reject(32'h80001000,1,4,0);reject(32'h80001000,1,4,2);
  // W may be offered early but must not be consumed without AW ownership.
  restart;wvalid=1;wdata=pattern(0,4);wstrb=16'hffff;wlast=1;
  repeat(7) begin @(negedge clk);check(!wready&&!h_awvalid,"early W consumption");end
  wvalid=0;good_burst(32'h80000010,1,1,4);
  // Write priority when AW and AR are both offered.
  @(negedge clk);awvalid=1;arvalid=1;awaddr=32'h80001000;araddr=32'h80002000;awlen=0;arlen=0;awid=3;arid=8;awsize=4;arsize=4;awburst=1;arburst=1;
  @(posedge clk);check(awready&&!arready,"simultaneous request priority");
  @(negedge clk);awvalid=0;arvalid=0;
  send_write(1,5,0,0,0);finish_b(0,3,0);
  // B cannot appear until real readback arrives; upstream W/B/R stalls do not time out.
  restart;hold_r=1;start_write(32'h80000100,4,6,4,1);send_write(4,6,0,0,0);
  repeat(12) begin @(negedge clk);check(!bvalid,"B before verification R");end
  hold_r=0;finish_b(0,6,60);check(!fault,"B stall triggered watchdog");
  start_read(32'h80000100,4,7,4,1);finish_read(4,0,7,6,0,0,1);
  start_write(32'h80000200,1,3,4,1);repeat(60) @(negedge clk);
  check(!fault&&wready,"upstream W wait triggered watchdog");send_write(1,8,0,0,0);finish_b(0,3,0);
  start_read(32'h80000200,1,4,4,1);while(!rvalid) @(negedge clk);
  repeat(60) @(negedge clk);check(!fault,"R stall triggered watchdog");finish_read(1,0,4,8,0,0,0);
  // Masked comparison: noise in an unstrobed byte is irrelevant, a written bit fails.
  restart;read_xor=256'h100;start_write(32'h80000000,1,2,4,1);send_write(1,9,1,0,0);finish_b(0,2,0);check(!fault,"unstrobed noise rejected");
  restart;read_xor=1;start_write(32'h80000000,1,2,4,1);send_write(1,9,1,0,0);finish_b(2,2,0);check(fault&&!awready&&!arready,"masked corruption not quarantined");
  // Early and missing WLAST drain the advertised AXI count, never native write.
  for(k=1;k<=2;k=k+1) begin
   restart;start_write(32'h80000000,4,3,4,1);send_write(4,3,0,k,1);finish_b(2,3,0);
   check(fault&&aw_commands==0&&write_beats==0,"WLAST violation escaped");
  end
  // Init loss while collecting: WREADY remains available to drain ownership.
  restart;start_write(32'h80000000,4,3,4,1);@(negedge clk);init_done=0;
  send_write(4,4,0,0,1);finish_b(2,3,0);check(fault&&aw_commands==0,"collect abort/native side effects");
  // Scratch writes may continue during a faulted COLLECT drain. No contents
  // from that request may reach native DDR, including a fault at the last W.
  for(mode=0;mode<3;mode=mode+1) for(half=0;half<2;half=half+1)
   for(k=0;k<4;k=k+1) begin
    restart;start_write(32'h80000000+half*16,4,3,4,1);
    fork
     send_write(4,44,2,0,1);
     begin
      wait(collected_w==k);@(negedge clk);
      case(mode)
       0:init_done=0;
       1:inject_r=1;
       2:inject_r=1'bx;
      endcase
     end
    join
    finish_b(2,3,2);
    check(fault&&fault_code==(mode==0?8'h01:mode==1?8'h03:8'h0b),"collect first fault code");
    check(aw_commands==0&&ar_commands==0&&write_beats==0&&!awready&&!arready,
          "faulted scratch cache published or reused");
   end
  restart;@(negedge clk);init_done=0;repeat(3) @(negedge clk);
  check(fault&&!awready&&!arready,"idle init loss");init_done=1;repeat(4) @(negedge clk);check(fault&&!awready,"fault cleared without reset");
  // Keep a completed B and R stable when initialization subsequently drops.
  restart;start_write(32'h80000000,1,5,4,1);send_write(1,5,0,0,0);while(!bvalid) @(negedge clk);
  init_done=0;finish_b(0,5,6);check(fault&&!awready,"completed B abort behavior");
  restart;start_read(32'h80000000,3,8,4,1);while(!rvalid) @(negedge clk);
  init_done=0;finish_read(3,0,8,0,3,1,1);check(fault&&!arready,"completed R abort behavior");
  // Native pending VALID survives timeout and init loss until handshake.
  restart;hold_aw=1;start_write(32'h80000010,3,6,4,1);send_write(3,6,0,0,0);
  repeat(35) @(negedge clk);check(fault&&h_awvalid&&!bvalid,"timed-out AW retracted or falsely retired");
  init_done=0;hold_aw=0;finish_b(2,6,0);check(write_beats==2&&ar_commands==0,"late AW zero-mask drain");
  for(j=0;j<64;j=j+1) check(memory.byte_at(j)==0,"late AW wrote bytes after fault");
  restart;hold_ar=1;start_read(32'h80000000,4,7,4,1);repeat(35) @(negedge clk);
  check(fault&&h_arvalid&&!rvalid,"timed-out AR retracted or falsely retired");hold_ar=0;finish_read(4,2,7,0,0,1,1);
  // Init loss, native bad ID/LAST/X, and timeout during physical native work.
  for(k=0;k<9;k=k+1) begin
   restart;hold_w=1;start_write(32'h80000000,6,9,4,1);send_write(6,2,0,0,0);
   while(aw_commands==0) @(negedge clk);
   case(k)
    0:init_done=0;
    1:bad_wid=1;
    2:bad_wlast=1;
    3:bad_wid=4'bxxxx;
    4:bad_wlast=1'bx;
    5:begin repeat(35) @(negedge clk);end
    default:begin end
   endcase
   if(k<6) begin hold_w=0;finish_b(2,9,0);check(fault&&write_beats==3,"write fault drainage");end
   else begin
    hold_ar=1;hold_w=0;while(!h_arvalid) @(negedge clk);
    if(k==6) init_done=0;
    if(k==7) begin repeat(35) @(negedge clk);check(fault&&h_arvalid,"verify AR timeout persistence");end
    if(k==8) begin hold_ar=0;hold_r=1;while(ar_commands==0) @(negedge clk);repeat(35) @(negedge clk);end
    hold_ar=0;hold_r=0;finish_b(2,9,0);check(fault,"verify abort");
   end
  end
  for(k=0;k<7;k=k+1) begin
   restart;hold_r=1;start_read(32'h80000010,6,12,4,1);while(ar_commands==0) @(negedge clk);
   case(k)
    0:init_done=0;
    1:bad_rid=1;
    2:bad_rlast=1;
    3:bad_rid=4'bxxxx;
    4:bad_rlast=1'bx;
    5:x_read=1;
    6:begin repeat(35) @(negedge clk);end
   endcase
   hold_r=0;finish_read(6,2,12,0,0,1,1);check(fault&&read_beats==4,"read fault drainage");
  end
  restart;idle_wready=1;repeat(60) @(negedge clk);check(!fault,"idle WREADY interpreted as write");
  inject_r=1;@(negedge clk);inject_r=0;repeat(2) @(negedge clk);check(fault&&!arready&&!awready,"unsolicited R not quarantined");
  repeat(3) begin inject_r=1;@(negedge clk);inject_r=0;repeat(2) @(negedge clk);check(!bvalid&&!rvalid&&!h_awvalid&&!h_arvalid,"late R resurrected a quarantined request");end
  // Repeated partial writes preserve bytes written by a different logical ID.
  restart;good_burst(32'h80000410,16,0,101);
  for(j=0;j<256;j=j+1) overlap[j]=memory.byte_at(32'h410+j);
  start_write(32'h80000410,16,14,4,1);send_write(16,102,2,0,1);finish_b(0,14,2);
  for(j=0;j<256;j=j+1) begin
   overlap_pattern=pattern(j/16,102);overlap_mask=strobe(j/16,2);
   if(overlap_mask[j%16]) overlap[j]=overlap_pattern[(j%16)*8+:8];
   check(memory.byte_at(32'h410+j)===overlap[j],"partial overwrite byte preservation");
  end
  start_read(32'h80000410,16,15,4,1);
  for(k=0;k<16;k=k+1) begin
   while(!rvalid) @(negedge clk);
   for(j=0;j<16;j=j+1) overlap_expected[j*8+:8]=overlap[k*16+j];
   check(rdata===overlap_expected&&rid==15&&rresp==0&&rlast==(k==15),"cross-ID read after B");
   rready=1;@(negedge clk);rready=0;
  end
  // Faults on the boundary before address VALID cannot create a new command.
`ifndef LEGACY_BASELINE
  restart;start_write(32'h80000010,2,6,4,1);send_write(2,7,0,0,0);
  check(dut.state==dut.WPRE,"write prefetch phase stimulus");init_done=0;
  finish_b(2,6,0);check(aw_commands==0&&fault,"write prefetch init loss");
  restart;start_write(32'h80000010,2,6,4,1);send_write(2,7,0,0,0);
  while(dut.state!=dut.VPRE) @(negedge clk);init_done=0;
  finish_b(2,6,0);check(aw_commands==1&&ar_commands==0&&fault,"verify prefetch init loss");
  restart;start_read(32'h80000010,2,7,4,1);
  while(dut.state!=dut.RPRE) @(negedge clk);init_done=0;
  finish_read(2,2,7,0,0,1,1);check(fault,"read prefetch init loss");
`endif
  // Init loss during a stalled native address (without relying on timeout).
  restart;hold_aw=1;start_write(32'h80000010,3,6,4,1);send_write(3,6,0,0,0);
  while(!h_awvalid) @(negedge clk);init_done=0;repeat(5) @(negedge clk);
  check(h_awvalid&&fault&&!bvalid,"init loss withdrew AW");hold_aw=0;finish_b(2,6,0);
  restart;hold_ar=1;start_read(32'h80000010,3,7,4,1);
  while(!h_arvalid) @(negedge clk);init_done=0;repeat(5) @(negedge clk);
  check(h_arvalid&&fault&&!rvalid,"init loss withdrew AR");hold_ar=0;finish_read(3,2,7,0,0,1,1);
  // Verification IDs/LAST/data X and corruption on the upper lane are faults.
  for(k=0;k<6;k=k+1) begin
   restart;hold_ar=1;start_write(32'h80000010,16,10,4,1);send_write(16,7,0,0,0);
   while(!h_arvalid) @(negedge clk);
   case(k)
    0:bad_rid=1;
    1:bad_rlast=1;
    2:bad_rid=4'bxxxx;
    3:bad_rlast=1'bx;
    4:x_read=1;
    5:read_xor=256'h1<<128;
   endcase
   hold_ar=0;finish_b(2,10,0);check(fault&&read_beats==9,"verify physical-length fault drain");
  end
  restart;good_burst(32'h80000010,16,0,239);
  $display("AXI128_HMIC256_PASS cases=%0d",cases);$finish;
 end
 initial begin #20000000;$fatal(1,"AXI bridge global timeout");end
endmodule
