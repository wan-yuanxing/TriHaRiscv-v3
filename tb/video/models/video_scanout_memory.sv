`timescale 1ns/1ps
// Digital byte memory: RAW pixels and immutable RGBA share the real native bus.
module video_scanout_memory(
 input wire clk,reset_n,input wire [27:0] h_araddr,input wire [3:0] h_arlen,h_arid,
 input wire h_arvalid,output wire h_arready,h_rvalid,output wire [255:0] h_rdata,
 output wire [3:0] h_rid,output wire h_rlast,output integer native_commands,raw_commands,asset_commands
);
 reg [7:0] asset[0:262143];string directory;
 initial begin if(!$value$plusargs("DIR=%s",directory))$fatal(1,"SCAN_MEMORY_DIR");$readmemh({directory,"/asset_bytes.hex"},asset);end
 integer ticks=0,index=0,count=0;reg active=0;reg [27:0] address=0;reg [3:0] identity=0;
 wire accept=h_arvalid&&h_arready;
 assign h_arready=reset_n&&!active&&ticks%5!=0;
 assign h_rvalid=reset_n&&(active||accept)&&ticks%4!=0;
 assign h_rid=active?identity:h_arid;
 assign h_rlast=active?index==count-1:h_arlen==0;
 function automatic [7:0] peek(input [31:0] addr);
  integer slot,offset,x,y;begin
   if(addr>=32'h82600ff0&&addr<32'h82640ff0)peek=asset[addr-32'h82600ff0];
   else if(addr>=32'h82000000&&addr<32'h82600000)begin
    slot=(addr-32'h82000000)/32'h200000;offset=(addr-32'h82000000)%32'h200000;y=offset/2400;x=(offset%2400)/3;
    case(offset%3)
     0:peek=8'(x*7+31+slot*77);
     1:peek=8'(y*11+17+slot*47);
     2:peek=8'(x*3+y*13+slot*93);
    endcase
   end else peek=8'ha5;
  end
 endfunction
 function automatic [255:0] fetch(input [27:0] addr);
  integer k;begin for(k=0;k<32;k=k+1)fetch[k*8+:8]=peek(32'h80000000+({4'd0,addr}<<2)+k);end
 endfunction
 assign h_rdata=fetch(active?address:h_araddr);
 always @(posedge clk)begin
  if(!reset_n)begin active<=0;ticks<=0;index<=0;count<=0;native_commands<=0;raw_commands<=0;asset_commands<=0;end
  else begin
   ticks<=ticks+1;
   if(accept)begin active<=1;address<=h_araddr;identity<=h_arid;index<=0;count<=h_arlen+1;native_commands<=native_commands+1;
    if(h_araddr>=28'h980000)asset_commands<=asset_commands+1;else raw_commands<=raw_commands+1;end
   if(h_rvalid)begin address<=(active?address:h_araddr)+8;index<=(active?index:0)+1;if(active?index==count-1:h_arlen==0)active<=0;end
  end
 end
endmodule
