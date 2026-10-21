`timescale 1ns/1ps
// Read-only digital native memory. No ownership or expected-pixel knowledge.
module video_renderer_memory(
 input wire clk,reset_n,input wire [27:0] h_araddr,input wire [3:0] h_arlen,h_arid,
 input wire h_arvalid,output wire h_arready,h_rvalid,output wire [255:0] h_rdata,
 output wire [3:0] h_rid,output wire h_rlast,output integer native_commands,native_beats
);
 reg [7:0] asset[0:262143],raw_page[0:4095];string directory;
 initial begin
  if(!$value$plusargs("DIR=%s",directory))$fatal(1,"RENDER_MEMORY_DIR");
  $readmemh({directory,"/asset_bytes.hex"},asset);$readmemh({directory,"/raw_bytes.hex"},raw_page);
 end
 integer ticks=0,index=0,count=0;reg active=0;reg [27:0] address=0;reg [3:0] identity=0;
 wire accept=h_arvalid&&h_arready;
 assign h_arready=reset_n&&!active&&ticks%5!=0;
 assign h_rvalid=reset_n&&(active||accept)&&ticks%4!=0;
 assign h_rid=active?identity:h_arid;
 assign h_rlast=active?index==count-1:h_arlen==0;
 function automatic [7:0] peek(input [31:0] addr);
  if(addr>=32'h82600ff0&&addr<32'h82640ff0)peek=asset[addr-32'h82600ff0];
  else if(addr>=32'h82000000&&addr<32'h82001000)peek=raw_page[addr-32'h82000000];
  else peek=8'ha5;
 endfunction
 function automatic [255:0] fetch(input [27:0] addr);
  integer k;begin for(k=0;k<32;k=k+1)fetch[k*8+:8]=peek(32'h80000000+({4'd0,addr}<<2)+k);end
 endfunction
 assign h_rdata=fetch(active?address:h_araddr);
 always @(posedge clk)begin
  if(!reset_n)begin active<=0;ticks<=0;index<=0;count<=0;native_commands<=0;native_beats<=0;end
  else begin
   ticks<=ticks+1;
   if(accept)begin active<=1;address<=h_araddr;identity<=h_arid;index<=0;count<=h_arlen+1;native_commands<=native_commands+1;end
   if(h_rvalid)begin
    native_beats<=native_beats+1;address<=(active?address:h_araddr)+8;index<=(active?index:0)+1;
    if(active?index==count-1:h_arlen==0)active<=0;
   end
  end
 end
endmodule
