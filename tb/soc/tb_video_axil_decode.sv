`timescale 1ns/1ps
`default_nettype none
module tb_video_axil_decode;
 reg clk_i=0,rst_ni=0;always #4 clk_i=~clk_i;
 reg [31:0] s_axi_awaddr_i=0;
 wire [63:0] m_axi_awaddr_o;
 reg [2:0] s_axi_awprot_i=0;
 wire [5:0] m_axi_awprot_o;
 reg s_axi_awvalid_i=0;
 wire [1:0] m_axi_awvalid_o;
 wire s_axi_awready_o;
 reg [1:0] m_axi_awready_i=0;
 reg [31:0] s_axi_wdata_i=0;
 wire [63:0] m_axi_wdata_o;
 reg [3:0] s_axi_wstrb_i=0;
 wire [7:0] m_axi_wstrb_o;
 reg s_axi_wvalid_i=0;
 wire [1:0] m_axi_wvalid_o;
 wire s_axi_wready_o;
 reg [1:0] m_axi_wready_i=0;
 wire [1:0] s_axi_bresp_o;
 reg [3:0] m_axi_bresp_i=0;
 wire s_axi_bvalid_o;
 reg [1:0] m_axi_bvalid_i=0;
 reg s_axi_bready_i=0;
 wire [1:0] m_axi_bready_o;
 reg [31:0] s_axi_araddr_i=0;
 wire [63:0] m_axi_araddr_o;
 reg [2:0] s_axi_arprot_i=0;
 wire [5:0] m_axi_arprot_o;
 reg s_axi_arvalid_i=0;
 wire [1:0] m_axi_arvalid_o;
 wire s_axi_arready_o;
 reg [1:0] m_axi_arready_i=0;
 wire [31:0] s_axi_rdata_o;
 reg [63:0] m_axi_rdata_i=0;
 wire [1:0] s_axi_rresp_o;
 reg [3:0] m_axi_rresp_i=0;
 wire s_axi_rvalid_o;
 reg [1:0] m_axi_rvalid_i=0;
 reg s_axi_rready_i=0;
 wire [1:0] m_axi_rready_o;
 video_axil_decode dut(.*);
 integer ticks=0,checks=0,writes[0:1],reads[0:1],aw_counts[0:1],w_counts[0:1];
 integer i,j,lane,delays[0:1],rdelays[0:1];
 reg [1:0] ah=0,wh=0,rh=0;reg [31:0] probe_address;
 reg [31:0] addresses[0:1],payloads[0:1],raddresses[0:1];
 reg [3:0] strobes[0:1];reg [2:0] aprot[0:1],rprot[0:1];
 reg [1:0] held_aw=0,held_w=0,held_ar=0;
 reg [34:0] saved_aw[0:1],saved_ar[0:1];reg [35:0] saved_w[0:1];
 function automatic [31:0] pattern(input [31:0] address,input integer target);
  pattern=address^32'hdeca1234^(target?32'h13579bdf:32'h2468ace0);
 endfunction
 function automatic integer target(input [31:0] address);
  if(address[1:0]!=0)target=2;
  else if(address>=32'h20012000&&address<32'h20013000)target=0;
  else if(address>=32'h20011000&&address<32'h20012000)target=1;
  else target=2;
 endfunction
 always @*begin
  for(integer t=0;t<2;t=t+1)begin
   m_axi_awready_i[t]=rst_ni&&!ah[t]&&!m_axi_bvalid_i[t]&&(ticks%5==t);
   m_axi_wready_i[t]=rst_ni&&!wh[t]&&!m_axi_bvalid_i[t]&&(ticks%7==t+1);
   m_axi_arready_i[t]=rst_ni&&!rh[t]&&!m_axi_rvalid_i[t]&&(ticks%3==t);
  end
 end
 always @(posedge clk_i)begin
  ticks=ticks+1;
  if(!rst_ni)begin ah=0;wh=0;rh=0;m_axi_bvalid_i<=0;m_axi_rvalid_i<=0;held_aw=0;held_w=0;held_ar=0;end
  else for(integer t=0;t<2;t=t+1)begin
   if(held_aw[t]&&(!m_axi_awvalid_o[t]||{m_axi_awaddr_o[t*32+:32],m_axi_awprot_o[t*3+:3]}!==saved_aw[t]))$fatal(1,"DECODE_AW_HOLD");
   if(held_w[t]&&(!m_axi_wvalid_o[t]||{m_axi_wdata_o[t*32+:32],m_axi_wstrb_o[t*4+:4]}!==saved_w[t]))$fatal(1,"DECODE_W_HOLD");
   if(held_ar[t]&&(!m_axi_arvalid_o[t]||{m_axi_araddr_o[t*32+:32],m_axi_arprot_o[t*3+:3]}!==saved_ar[t]))$fatal(1,"DECODE_AR_HOLD");
   held_aw[t]=m_axi_awvalid_o[t]&&!m_axi_awready_i[t];saved_aw[t]={m_axi_awaddr_o[t*32+:32],m_axi_awprot_o[t*3+:3]};
   held_w[t]=m_axi_wvalid_o[t]&&!m_axi_wready_i[t];saved_w[t]={m_axi_wdata_o[t*32+:32],m_axi_wstrb_o[t*4+:4]};
   held_ar[t]=m_axi_arvalid_o[t]&&!m_axi_arready_i[t];saved_ar[t]={m_axi_araddr_o[t*32+:32],m_axi_arprot_o[t*3+:3]};
   if(m_axi_awvalid_o[t]&&m_axi_awready_i[t])begin
    if(ah[t]||target(m_axi_awaddr_o[t*32+:32])!=t)$fatal(1,"DECODE_WRONG_AW_TARGET");
    addresses[t]=m_axi_awaddr_o[t*32+:32];aprot[t]=m_axi_awprot_o[t*3+:3];ah[t]=1;aw_counts[t]++;
   end
   if(m_axi_wvalid_o[t]&&m_axi_wready_i[t])begin if(wh[t])$fatal(1,"DECODE_DUP_W");wh[t]=1;payloads[t]=m_axi_wdata_o[t*32+:32];strobes[t]=m_axi_wstrb_o[t*4+:4];w_counts[t]++;end
   if(ah[t]&&wh[t]&&!m_axi_bvalid_i[t])begin
    if(delays[t]==0)begin m_axi_bvalid_i[t]<=1;m_axi_bresp_i[t*2+:2]<=addresses[t][5:4]==3?2:0;delays[t]=9;writes[t]++;end
    else delays[t]--;
   end
   if(m_axi_bvalid_i[t]&&m_axi_bready_o[t])begin m_axi_bvalid_i[t]<=0;ah[t]=0;wh[t]=0;end
   if(m_axi_arvalid_o[t]&&m_axi_arready_i[t])begin
    if(rh[t]||target(m_axi_araddr_o[t*32+:32])!=t)$fatal(1,"DECODE_WRONG_AR_TARGET");
    raddresses[t]=m_axi_araddr_o[t*32+:32];rprot[t]=m_axi_arprot_o[t*3+:3];rh[t]=1;rdelays[t]=11;reads[t]++;
   end
   if(rh[t]&&!m_axi_rvalid_i[t])begin
    if(rdelays[t]==0)begin m_axi_rvalid_i[t]<=1;m_axi_rdata_i[t*32+:32]<=pattern(raddresses[t],t);m_axi_rresp_i[t*2+:2]<=raddresses[t][5:4]==3?2:0;end
    else rdelays[t]--;
   end
   if(m_axi_rvalid_i[t]&&m_axi_rready_o[t])begin m_axi_rvalid_i[t]<=0;rh[t]=0;end
  end
 end
 task automatic address_write(input [31:0] address,input [2:0] prot);
  begin @(negedge clk_i);s_axi_awaddr_i=address;s_axi_awprot_i=prot;s_axi_awvalid_i=1;
   do @(posedge clk_i);while(!s_axi_awready_o);@(negedge clk_i);s_axi_awvalid_i=0;s_axi_awaddr_i=32'hffffffff;end
 endtask
 task automatic data_write(input [31:0] value,input [3:0] strb);
  begin @(negedge clk_i);s_axi_wdata_i=value;s_axi_wstrb_i=strb;s_axi_wvalid_i=1;
   do @(posedge clk_i);while(!s_axi_wready_o);@(negedge clk_i);s_axi_wvalid_i=0;s_axi_wdata_i=32'hffffffff;end
 endtask
 task automatic wr(input [31:0] address,value,input [3:0] strb,input integer order,hold_cycles);
  integer t,old_aw,old_w;reg [1:0] response;reg [2:0] prot;
  begin t=target(address);prot=value[2:0];old_aw=aw_counts[0]+aw_counts[1];old_w=w_counts[0]+w_counts[1];
   if(order==0)begin address_write(address,prot);repeat(19)@(negedge clk_i);data_write(value,strb);end
   else if(order==1)begin data_write(value,strb);repeat(23)begin @(negedge clk_i);if(|m_axi_wvalid_o)$fatal(1,"DECODE_W_BEFORE_ADDRESS");end address_write(address,prot);end
   else fork address_write(address,prot);data_write(value,strb);join
   wait(s_axi_bvalid_o);response=t==2?3:address[5:4]==3?2:0;
   repeat(hold_cycles)begin @(negedge clk_i);if(!s_axi_bvalid_o||s_axi_bresp_o!==response)$fatal(1,"DECODE_B_HOLD_OR_RESP");end
   if(t==2)begin if(aw_counts[0]+aw_counts[1]!=old_aw||w_counts[0]+w_counts[1]!=old_w)$fatal(1,"DECODE_INVALID_WRITE_SIDE_EFFECT");end
   else if(addresses[t]!==address||payloads[t]!==value||strobes[t]!==strb||aprot[t]!==prot||aw_counts[0]+aw_counts[1]!=old_aw+1||w_counts[0]+w_counts[1]!=old_w+1)$fatal(1,"DECODE_WRITE_PAYLOAD");
   @(negedge clk_i);s_axi_bready_i=1;@(negedge clk_i);s_axi_bready_i=0;checks++;
  end
 endtask
 task automatic rd(input [31:0] address,input integer hold_cycles);
  integer t,old_reads;reg [31:0] wanted;reg [1:0] response;reg [2:0] prot;
  begin t=target(address);prot=address[4:2];old_reads=reads[0]+reads[1];
   @(negedge clk_i);s_axi_araddr_i=address;s_axi_arprot_i=prot;s_axi_arvalid_i=1;
   do @(posedge clk_i);while(!s_axi_arready_o);@(negedge clk_i);s_axi_arvalid_i=0;s_axi_araddr_i=32'hffffffff;
   wait(s_axi_rvalid_o);wanted=t==2?0:pattern(address,t);response=t==2?3:address[5:4]==3?2:0;
   repeat(hold_cycles)begin @(negedge clk_i);if(!s_axi_rvalid_o||s_axi_rdata_o!==wanted||s_axi_rresp_o!==response)$fatal(1,"DECODE_R_HOLD_OR_RESP");end
   if(t==2)begin if(reads[0]+reads[1]!=old_reads)$fatal(1,"DECODE_INVALID_READ_SIDE_EFFECT");end
   else if(reads[0]+reads[1]!=old_reads+1||raddresses[t]!==address||rprot[t]!==prot)$fatal(1,"DECODE_READ_PAYLOAD");
   @(negedge clk_i);s_axi_rready_i=1;@(negedge clk_i);s_axi_rready_i=0;checks++;
  end
 endtask
 initial begin
  for(i=0;i<2;i++)begin writes[i]=0;reads[i]=0;aw_counts[i]=0;w_counts[i]=0;delays[i]=7;end
  repeat(5)@(negedge clk_i);rst_ni=1;
  for(i=0;i<32;i++)begin wr((i%2?32'h20011000:32'h20012000)+i*4,32'h65ab0010+i,4'(i),i%3,i==0?1100:5);rd((i%2?32'h20012000:32'h20011000)+i*4,9);end
  for(i=0;i<8;i++)begin
   case(i)0:probe_address=32'h20010000;1:probe_address=32'h20010ffc;2:probe_address=32'h20013000;3:probe_address=32'h20011001;4:probe_address=32'h20012002;5:probe_address=32'h2001ffff;6:probe_address=32'h20001000;7:probe_address=32'hffffffff;endcase
   rd(probe_address,13);wr(probe_address,32'hfedcba98,15,i%3,7);
  end
  rd(32'h20011ffc,6);rd(32'h20012ffc,6);wr(32'h20011ffc,77,15,0,6);wr(32'h20012ffc,88,15,1,6);
  for(i=0;i<16;i++)fork wr(32'h20012080+i*4,32'h12340000+i,15,i%3,21);rd(32'h20011090+i*4,31);join
  // Coordinated endpoint/router reset with accepted but unpaired AW.
  address_write(32'h20012000,0);@(negedge clk_i);rst_ni=0;repeat(5)@(negedge clk_i);rst_ni=1;
  wr(32'h20011000,32'habcdef01,15,2,3);rd(32'h20012000,3);
  if(aw_counts[0]!=w_counts[0]||aw_counts[1]!=w_counts[1])$fatal(1,"DECODE_FINAL_COUNTS");
  $display("VIDEO_CONTROL_DECODE_PASS checks=%0d cap_w=%0d disp_w=%0d cap_r=%0d disp_r=%0d",checks,writes[0],writes[1],reads[0],reads[1]);$finish;
 end
 initial begin #10000000;$fatal(1,"DECODE_TIMEOUT");end
endmodule
`default_nettype wire
