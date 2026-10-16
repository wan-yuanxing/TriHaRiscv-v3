`timescale 1ns/1ps
// Test-only byte-addressed memory. Addresses are native 32-bit-word addresses;
// no AXI lane, burst, or legality calculation is shared with the bridge.
module axi_bridge_native_model (
 input wire clk,rst_n,
 input wire gaps,hold_aw,hold_ar,hold_w,hold_r,idle_wready,
 input wire [3:0] bad_wid,bad_rid,
 input wire bad_wlast,bad_rlast,x_read,inject_r,
 input wire [255:0] read_xor,
 input wire [27:0] h_awaddr,h_araddr,
 input wire [3:0] h_awlen,h_arlen,h_awid,h_arid,
 input wire h_awvalid,h_arvalid,
 output wire h_awready,h_arready,h_wready,h_rvalid,
 input wire [255:0] h_wdata,
 input wire [31:0] h_wstrb,
 output wire [255:0] h_rdata,
 output wire [3:0] h_wid,h_rid,
 output wire h_wlast,h_rlast,
 output integer aw_commands,ar_commands,write_beats,read_beats,first_w,first_r
);
 reg [27:0] tags[0:2047];
 reg [7:0] memory[0:65535];
 integer used,ticks,wi,ri,wn,rn;
 reg writing,reading;
 reg [27:0] wa,ra;
 reg [3:0] wid_q,rid_q;
 wire aw=h_awvalid && h_awready;
 wire ar=h_arvalid && h_arready;
 wire wg=!gaps || ticks%4!=0;
 wire rg=!gaps || ticks%3!=0;
 assign h_awready=rst_n && !writing && !reading && !hold_aw && (!gaps || ticks%5==1);
 assign h_arready=rst_n && !writing && !reading && !hold_ar && (!gaps || ticks%7==2);
 assign h_wready=rst_n && ((idle_wready && !writing && !aw) || ((writing || aw) && !hold_w && wg));
 assign h_rvalid=rst_n && (inject_r || ((reading || ar) && !hold_r && rg));
 assign h_wid=(writing ? wid_q:h_awid)^bad_wid;
 assign h_rid=(reading ? rid_q:h_arid)^bad_rid;
 assign h_wlast=((writing ? wi==wn-1:h_awlen==0)^bad_wlast);
 assign h_rlast=((reading ? ri==rn-1:h_arlen==0)^bad_rlast);
 function automatic [7:0] byte_at(input [31:0] byte_address);
  integer s;
  begin
   byte_at=0;
   for(s=0;s<used;s=s+1)
    if(tags[s]==(byte_address>>5)*8)
     byte_at=memory[s*32+byte_address[4:0]];
  end
 endfunction
 function automatic [255:0] fetch(input [27:0] word_address,input integer revision);
  integer j,s;
  begin
   fetch=0;
   for(s=0;s<used;s=s+1)
    if(tags[s]==word_address)
     for(j=0;j<32;j=j+1) fetch[j*8+:8]=memory[s*32+j];
  end
 endfunction
 // Explicit revision input refreshes an unchanged read address after stores.
 // This avoids simulator-specific implicit sensitivity to memory in functions.
 assign h_rdata=x_read ? {256{1'bx}}:fetch(reading ? ra:h_araddr,ticks)^read_xor;
 task automatic store(input [27:0] word_address);
  integer s,slot,j;
  begin
   slot=-1;
   for(s=0;s<used;s=s+1) if(tags[s]==word_address) slot=s;
   if(slot<0) begin
    if(used==2048) $fatal(1,"MODEL capacity");
    slot=used; used=used+1; tags[slot]=word_address;
    for(j=0;j<32;j=j+1) memory[slot*32+j]=0;
   end
   for(j=0;j<32;j=j+1)
    if(h_wstrb[j]) memory[slot*32+j]=h_wdata[j*8+:8];
  end
 endtask
 always @(posedge clk) begin
  if(!rst_n) begin
   used=0;ticks<=0;writing<=0;reading<=0;wi<=0;ri<=0;wn<=0;rn<=0;
   wa<=0;ra<=0;wid_q<=0;rid_q<=0;
   aw_commands<=0;ar_commands<=0;write_beats<=0;read_beats<=0;first_w<=0;first_r<=0;
  end else begin
   ticks<=ticks+1;
   if(aw) begin
    aw_commands<=aw_commands+1;writing<=1;wa<=h_awaddr;wid_q<=h_awid;wn<=h_awlen+1;wi<=0;
   end
   if((writing || aw) && h_wready) begin
    store(writing ? wa:h_awaddr);
    write_beats<=write_beats+1;
    if(aw) first_w<=first_w+1;
    wa<=(writing ? wa:h_awaddr)+8;
    wi<=(writing ? wi:0)+1;
    if(writing ? wi==wn-1:h_awlen==0) writing<=0;
   end
   if(ar) begin
    ar_commands<=ar_commands+1;reading<=1;ra<=h_araddr;rid_q<=h_arid;rn<=h_arlen+1;ri<=0;
   end
   if((reading || ar) && h_rvalid) begin
    read_beats<=read_beats+1;
    if(ar) first_r<=first_r+1;
    ra<=(reading ? ra:h_araddr)+8;
    ri<=(reading ? ri:0)+1;
    if(reading ? ri==rn-1:h_arlen==0) reading<=0;
   end
  end
 end
endmodule
