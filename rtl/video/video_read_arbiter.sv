`timescale 1ns/1ps
`default_nettype none
// One accepted read burst, one immutable owner. Never route by response RID.
// This client-side arbiter precedes the existing exclusive DDR read endpoint.
module video_read_arbiter #(parameter integer MAX_RAW_BURSTS=4)(
 input wire clk,reset_n,online,memory_fault,display_urgent,
 input wire [3:0] d_arid,a_arid,input wire [31:0] d_araddr,a_araddr,
 input wire [7:0] d_arlen,a_arlen,input wire [2:0] d_arsize,a_arsize,input wire [1:0] d_arburst,a_arburst,
 input wire d_arvalid,a_arvalid,output wire d_arready,a_arready,
 output wire [3:0] d_rid,a_rid,output wire [127:0] d_rdata,a_rdata,
 output wire [1:0] d_rresp,a_rresp,output wire d_rlast,a_rlast,d_rvalid,a_rvalid,input wire d_rready,a_rready,
 output reg [3:0] m_arid,output reg [31:0] m_araddr,output reg [7:0] m_arlen,
 output reg [2:0] m_arsize,output reg [1:0] m_arburst,output wire m_arvalid,input wire m_arready,
 input wire [3:0] m_rid,input wire [127:0] m_rdata,input wire [1:0] m_rresp,input wire m_rlast,m_rvalid,output wire m_rready,
 output reg fault,output reg [7:0] fault_code,output wire port_drained,output reg [31:0] raw_grants,asset_grants
);
 localparam [1:0] IDLE=0,ADDRESS=1,DATA=2;
 reg [1:0] state;reg owner_asset,last_raw,seen_online,uncertain;
 reg [4:0] streak,remaining;
 initial if(MAX_RAW_BURSTS<1||MAX_RAW_BURSTS>16)$fatal(1,"read arbiter quota requires 1..16");
 function automatic legal(input [3:0] id,input [31:0] addr,input [7:0] len,input [2:0] size,input [1:0] burst);
  // 16-byte aligned INCR bursts, at most 16 beats. Both ends of the
  // aperture are 4 KiB aligned, so an admitted start page and a last beat
  // on that same page also prove the exclusive end stays inside DDR.
  // Only the last 16 beats of a page can wrap: then beat_low + len <= 15.
  begin
   legal=(^{id,addr,len,size,burst})!==1'bx&&addr[3:0]==0&&len<16&&size==4&&burst==1&&
       addr[31:27]==5'b10000&&(addr[11:8]!=4'hf||addr[7:4]<=~len[3:0]);
  end
 endfunction
 wire d_wants=d_arvalid===1'b1,a_wants=a_arvalid===1'b1;
 wire invalid=(d_wants&&!legal(d_arid,d_araddr,d_arlen,d_arsize,d_arburst))||
              (a_wants&&!legal(a_arid,a_araddr,a_arlen,a_arsize,a_arburst));
 wire choose_raw=d_wants&&(!a_wants||(display_urgent===1'b1 ? streak<MAX_RAW_BURSTS : !last_raw));
 wire enabled=reset_n&&state==IDLE&&!fault&&online===1'b1&&memory_fault===1'b0&&m_rvalid===1'b0&&!invalid;
 assign d_arready=enabled&&choose_raw;assign a_arready=enabled&&a_wants&&!choose_raw;
 assign m_arvalid=reset_n&&state==ADDRESS;
 assign d_rvalid=reset_n&&state==DATA&&!owner_asset&&m_rvalid;
 assign a_rvalid=reset_n&&state==DATA&&owner_asset&&m_rvalid;
 assign d_rid=m_rid;assign a_rid=m_rid;assign d_rdata=m_rdata;assign a_rdata=m_rdata;
 assign d_rresp=m_rresp;assign a_rresp=m_rresp;assign d_rlast=m_rlast;assign a_rlast=m_rlast;
 assign m_rready=reset_n&&state==DATA&&(owner_asset?a_rready:d_rready);
 assign port_drained=reset_n&&state==IDLE&&!uncertain&&m_rvalid===1'b0;
 wire phase=state==DATA||(state==ADDRESS&&m_arready===1'b1);
 wire stray=m_rvalid===1'b1&&!phase;
 wire unknown_valid=m_rvalid!==1'b0&&m_rvalid!==1'b1;
 wire bad_id=m_rvalid===1'b1&&phase&&m_rid!==m_arid;
 wire bad_last=m_rvalid===1'b1&&state==DATA&&m_rlast!==(remaining==1);
 wire unknown_response=m_rvalid===1'b1&&phase&&(^{m_rid,m_rdata,m_rresp,m_rlast})===1'bx;
 reg [7:0] fault_now;
 always @*begin
  fault_now=0;
  if((seen_online||state!=IDLE)&&online!==1'b1)fault_now=1;
  else if(memory_fault!==1'b0)fault_now=2;
  else if(state==IDLE&&invalid)fault_now=3;
  else if(stray)fault_now=4;
  else if(bad_id)fault_now=5;
  else if(bad_last)fault_now=6;
  else if(unknown_response)fault_now=7;
  else if(unknown_valid||(d_arvalid!==1'b0&&d_arvalid!==1'b1)||(a_arvalid!==1'b0&&a_arvalid!==1'b1)||
          (m_arvalid&&m_arready!==1'b0&&m_arready!==1'b1))fault_now=8;
  else if(m_rvalid===1'b1&&phase&&m_rresp!==0)fault_now=9;
 end
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   state<=IDLE;owner_asset<=0;last_raw<=0;seen_online<=0;uncertain<=0;streak<=0;remaining<=0;
   m_arid<=0;m_araddr<=0;m_arlen<=0;m_arsize<=0;m_arburst<=0;fault<=0;fault_code<=0;raw_grants<=0;asset_grants<=0;
  end else begin
   if(online===1'b1)seen_online<=1;
   if(stray||unknown_valid||bad_id||bad_last||unknown_response)uncertain<=1;
   if(!fault&&fault_now!=0)begin fault<=1;fault_code<=fault_now;end
   case(state)
    IDLE:if(d_arvalid&&d_arready)begin
     owner_asset<=0;last_raw<=1;if(streak<MAX_RAW_BURSTS)streak<=streak+1'b1;
     m_arid<=d_arid;m_araddr<=d_araddr;m_arlen<=d_arlen;m_arsize<=d_arsize;m_arburst<=d_arburst;
     remaining<={1'b0,d_arlen[3:0]}+5'd1;raw_grants<=raw_grants+1'b1;state<=ADDRESS;
    end else if(a_arvalid&&a_arready)begin
     owner_asset<=1;last_raw<=0;streak<=0;
     m_arid<=a_arid;m_araddr<=a_araddr;m_arlen<=a_arlen;m_arsize<=a_arsize;m_arburst<=a_arburst;
     remaining<={1'b0,a_arlen[3:0]}+5'd1;asset_grants<=asset_grants+1'b1;state<=ADDRESS;
    end
    ADDRESS:if(m_arready)state<=DATA;
    DATA:if(m_rvalid&&m_rready)begin remaining<=remaining-1'b1;if(remaining==1)state<=IDLE;end
    default:begin fault<=1;fault_code<=8;end
   endcase
  end
 end
endmodule
`default_nettype wire
