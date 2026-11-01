`timescale 1ns/1ps
// AXI128 subset to the HMIC256 port. All addresses at AXI are full logical
// BYTE addresses. This issuer must exclusively own the native port: successful
// writes are acknowledged only after byte-masked readback through this port.
// This is observed readback, not a claim about physical DRAM durability.
//
// Recovery requires a COORDINATED master + bridge + controller rst_n reset.
// A native command already asserted is irrevocable: VALID/address/length/ID
// remain stable through faults until accepted. Its physical advertised count
// then drains (zero write masks / discarded read data), ignoring a broken LAST.
// An error response for that request is conditional on native retirement. If
// acceptance/data never resumes, only coordinated reset can recover. Faulted
// buffers are never reused. An owned AXI write always drains AWLEN+1 W beats;
// there is deliberately no timeout while waiting for the upstream master.
module axi128_hmic256 #(
 parameter integer NATIVE_TIMEOUT_CYCLES = 125000000
) (
 input wire clk,rst_n,init_done,
 input wire [3:0] awid,arid,
 input wire [31:0] awaddr,araddr,
 input wire [7:0] awlen,arlen,
 input wire [2:0] awsize,arsize,
 input wire [1:0] awburst,arburst,
 input wire awvalid,arvalid,wvalid,wlast,bready,rready,
 input wire [127:0] wdata,
 input wire [15:0] wstrb,
 output wire awready,arready,wready,bvalid,rvalid,rlast,
 output wire [3:0] bid,rid,
 output wire [1:0] bresp,rresp,
 output wire [127:0] rdata,
 output reg fault,
 output reg [7:0] fault_code,
 output wire [27:0] h_awaddr,h_araddr,
 output wire [3:0] h_awlen,h_arlen,h_awid,h_arid,
 output wire h_awvalid,h_arvalid,
 input wire h_awready,h_arready,h_wready,h_rvalid,
 output wire [255:0] h_wdata,
 output wire [31:0] h_wstrb,
 input wire [255:0] h_rdata,
 input wire [3:0] h_wid,h_rid,
 input wire h_wlast,h_rlast
);
 localparam [3:0] IDLE=0,COLLECT=1,WPRE=2,WADDR=3,WDATA=4,
                  VPRE=5,VADDR=6,VDATA=7,RADDR=8,RDATA=9,
                  RPRE=10,RRESP=11,BRESP=12,QUARANTINE=13;
 localparam integer TIMER_WIDTH = NATIVE_TIMEOUT_CYCLES>1 ? $clog2(NATIVE_TIMEOUT_CYCLES+1):1;
 localparam [31:0] WINDOW_BASE=32'h80000000,WINDOW_LAST=32'h87ffffff;
 reg [3:0] state,id_q,pos_q,span_q;
 reg [27:0] base_q;
 reg [8:0] beats_q,up_q;
 reg half_q,legal_q,seen_online;
 reg [1:0] response_q;
 reg [127:0] rdata_q;
 reg [TIMER_WIDTH-1:0] timer_q;
 // Independent 144-bit half-word banks use one full write port each.
 // Their synchronous read outputs replace payload_q/mask_q without adding
 // a cycle: WPRE/VPRE fetch beat zero, native retire fetches the next beat.
 (* syn_ramstyle="block_ram" *) reg [143:0] expected_low[0:8],expected_high[0:8];
 (* ram_style="distributed", syn_ramstyle="select_ram" *) reg [255:0] returned[0:8];
 reg [143:0] expected_low_q,expected_high_q;
 wire [255:0] payload_q={expected_high_q[127:0],expected_low_q[127:0]};
 wire [31:0] mask_q={expected_high_q[143:128],expected_low_q[143:128]};
 wire [8:0] lane=up_q+{8'b0,half_q};
 wire [8:0] next_lane=lane+9'd1;
 wire aw_take=awvalid&&awready;
 wire ar_take=arvalid&&arready;
 wire w_take=wvalid&&wready;
 wire native_write=(state==WDATA)||(state==WADDR && h_awready===1'b1);
 wire native_read=(state==RDATA)||(state==VDATA)||
                  ((state==RADDR||state==VADDR)&&h_arready===1'b1);
 wire nw_take=native_write && h_wready===1'b1;
 wire nr_take=native_read && h_rvalid===1'b1;
 wire native_wait=state==WADDR||state==WDATA||state==VADDR||state==VDATA||state==RADDR||state==RDATA;
 wire native_progress=nw_take||nr_take||(h_awvalid&&h_awready===1'b1)||(h_arvalid&&h_arready===1'b1);
 wire timed_out=native_wait&&!native_progress&&(timer_q>=NATIVE_TIMEOUT_CYCLES-1);
 function automatic legal(input [31:0] address,input [7:0] len,input [2:0] size,input [1:0] burst);
  reg [32:0] exclusive_end;
  reg [12:0] page_end;
  begin
   exclusive_end={1'b0,address}+(({25'b0,len}+33'd1)<<4);
   page_end={1'b0,address[11:0]}+(({5'b0,len}+13'd1)<<4);
   legal=address>=WINDOW_BASE && exclusive_end<=({1'b0,WINDOW_LAST}+33'd1) &&
         !exclusive_end[32] && len<16 && address[3:0]==0 &&
         size==4 && burst==1 && page_end<=4096;
  end
 endfunction
 function automatic [27:0] native_base(input [31:0] address);
  native_base=((address-WINDOW_BASE)&32'hffffffe0)>>2;
 endfunction
 function automatic [3:0] native_span(input [7:0] len,input upper);
  native_span=({1'b0,len}+9'd2+{8'b0,upper})>>1;
 endfunction
 function automatic masked_match(input [255:0] actual,input [255:0] wanted,input [31:0] mask);
  integer i;
  begin
   masked_match=1;
   for(i=0;i<32;i=i+1)
    if(mask[i] && actual[i*8+:8]!==wanted[i*8+:8]) masked_match=0;
  end
 endfunction
 reg [7:0] fault_now;
 always @* begin
  fault_now=0;
  if(seen_online && init_done!==1'b1) fault_now=8'h01;
  else if(w_take && wlast!==(up_q==beats_q-1)) fault_now=8'h02;
  else if(h_rvalid===1'b1 && !native_read) fault_now=8'h03;
  else if(nw_take && h_wid!==id_q) fault_now=8'h04;
  else if(nw_take && h_wlast!==(pos_q==span_q-1)) fault_now=8'h05;
  else if(nr_take && h_rid!==id_q) fault_now=8'h06;
  else if(nr_take && h_rlast!==(pos_q==span_q-1)) fault_now=8'h07;
  else if(nr_take && (^h_rdata===1'bx)) fault_now=8'h08;
  else if(timed_out) fault_now=8'h09;
  else if(nr_take && (state==VADDR||state==VDATA) && !masked_match(h_rdata,payload_q,mask_q)) fault_now=8'h0a;
  else if((h_rvalid!==1'b0 && h_rvalid!==1'b1)||
          (h_awvalid && h_awready!==1'b0 && h_awready!==1'b1)||
          (h_arvalid && h_arready!==1'b0 && h_arready!==1'b1)||
          (native_write && h_wready!==1'b0 && h_wready!==1'b1)) fault_now=8'h0b;
 end
 wire poisoned=fault||(fault_now!=0);
 // Use each guard directly in its phase; verification alone needs the
 // masked readback comparator. Case truth preserves procedural-if X handling.
 wire phase_init_fault=((seen_online && init_done!==1'b1)===1'b1);
 wire quiet_poisoned=fault||phase_init_fault||(h_rvalid!==1'b0);
 wire collect_phase_poisoned=quiet_poisoned||
     ((w_take && wlast!==(up_q==beats_q-1))===1'b1);
 wire write_phase_poisoned=quiet_poisoned||
     ((nw_take && h_wid!==id_q)===1'b1)||
     ((nw_take && h_wlast!==(pos_q==span_q-1))===1'b1)||
     (timed_out===1'b1)||
     (((h_awvalid && h_awready!==1'b0 && h_awready!==1'b1)||
       (native_write && h_wready!==1'b0 && h_wready!==1'b1))===1'b1);
 wire read_phase_poisoned=fault||phase_init_fault||
     ((h_rvalid===1'b1 && !native_read)===1'b1)||
     ((nr_take && h_rid!==id_q)===1'b1)||
     ((nr_take && h_rlast!==(pos_q==span_q-1))===1'b1)||
     ((nr_take && (^h_rdata===1'bx))===1'b1)||
     (timed_out===1'b1)||
     (((h_rvalid!==1'b0 && h_rvalid!==1'b1)||
       (h_arvalid && h_arready!==1'b0 && h_arready!==1'b1))===1'b1);

 // Only COLLECT writes this private scratch cache. All fault checks remain
 // on retirement and WPRE, before any native address can be offered. Thus a
 // faulted burst may still fill scratch while its owned AXI W beats drain:
 // these bytes are never published and quarantine prevents buffer reuse.
 // Do not fan immediate native health out to every scratch byte enable.
 // Read and write native phases are exclusive. Factor the write-mask guard
 // from that phase's faults so the 256-bit readback comparison cannot feed
 // native WSTRB. This is the same immediate first-fault suppression as
 // !poisoned during native_write, including unknown native controls.
 wire write_poisoned=fault||(seen_online && init_done!==1'b1)||
                     (h_rvalid!==1'b0)||
                     (nw_take && (h_wid!==id_q || h_wlast!==(pos_q==span_q-1)))||
                     timed_out||
                     (native_write && h_wready!==1'b0 && h_wready!==1'b1);
 // No fault-dependent gating on a pending native command. In particular, an
 // init loss or watchdog cannot withdraw a VALID which was already offered.
 assign h_awvalid=rst_n && state==WADDR;
 assign h_arvalid=rst_n && (state==RADDR||state==VADDR);
 assign h_awaddr=base_q;assign h_araddr=base_q;
 assign h_awlen=span_q-1'b1;assign h_arlen=span_q-1'b1;
 assign h_awid=id_q;assign h_arid=id_q;
 assign h_wdata=payload_q;
 assign h_wstrb=native_write&&!write_poisoned ? mask_q:32'b0;
 // In IDLE there are no W/native transfers or pending native commands.
 // Preserve all global diagnostics while pruning their irrelevant READY cone.
 wire idle_poisoned=fault||(seen_online && init_done!==1'b1)||(h_rvalid!==1'b0);
 assign awready=rst_n && init_done===1'b1 && state==IDLE && !idle_poisoned;
 assign arready=awready&&!awvalid;
 assign wready=rst_n && state==COLLECT;
 assign bvalid=state==BRESP;assign bid=id_q;assign bresp=response_q;
 assign rvalid=state==RRESP;assign rid=id_q;assign rresp=response_q;
 assign rdata=rdata_q;assign rlast=up_q==beats_q-1;
 // These private data banks are unreset. A complete legal AXI burst
 // overwrites all native lanes (including masked padding) before address VALID.
 wire expected_first=state==WPRE||state==VPRE;
 wire expected_next=((state==WADDR||state==WDATA)&&nw_take)||
                    ((state==VADDR||state==VDATA)&&nr_take);
 wire [3:0] expected_index=expected_first?4'd0:pos_q+4'd1;
 always @(posedge clk)begin
  if(rst_n&&w_take&&legal_q)begin
   expected_high[lane[4:1]]<=lane[0]?{wstrb,wdata}:144'd0;
   if(!lane[0]||up_q==0)expected_low[lane[4:1]]<=lane[0]?144'd0:{wstrb,wdata};
  end
  if(rst_n&&(expected_first||(expected_next&&pos_q!=span_q-1)))begin
   expected_low_q<=expected_low[expected_index];
   expected_high_q<=expected_high[expected_index];
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;id_q<=0;pos_q<=0;span_q<=1;base_q<=0;beats_q<=1;up_q<=0;
   half_q<=0;legal_q<=0;seen_online<=0;response_q<=0;rdata_q<=0;
   timer_q<=0;fault<=0;fault_code<=0;
  end else begin
   if(init_done===1'b1) seen_online<=1;
   if(!fault && fault_now!=0) begin fault<=1;fault_code<=fault_now;end
   if(!native_wait||native_progress) timer_q<=0;
   else if(!timed_out) timer_q<=timer_q+1'b1;
   case(state)
    IDLE:begin
     if(quiet_poisoned) state<=QUARANTINE;
     else if(aw_take) begin
      id_q<=awid;beats_q<={1'b0,awlen}+9'd1;up_q<=0;half_q<=awaddr[4];
      legal_q<=legal(awaddr,awlen,awsize,awburst);response_q<=0;state<=COLLECT;
      // Relative translation is used only after full logical validation.
      if(legal(awaddr,awlen,awsize,awburst)) begin
       base_q<=native_base(awaddr);span_q<=native_span(awlen,awaddr[4]);
      end
     end else if(ar_take) begin
      id_q<=arid;beats_q<={1'b0,arlen}+9'd1;up_q<=0;half_q<=araddr[4];pos_q<=0;
      if(legal(araddr,arlen,arsize,arburst)) begin
       base_q<=native_base(araddr);span_q<=native_span(arlen,araddr[4]);response_q<=0;state<=RADDR;
      end else begin response_q<=2'b11;state<=RPRE;end
     end
    end
    COLLECT:if(w_take) begin
     if(up_q==beats_q-1) begin
      if(collect_phase_poisoned) begin response_q<=2'b10;state<=BRESP;end
      else if(!legal_q) begin response_q<=2'b11;state<=BRESP;end
      else state<=WPRE;
     end else up_q<=up_q+1'b1;
    end
    WPRE:begin
     pos_q<=0;
     if(quiet_poisoned) begin response_q<=2'b10;state<=BRESP;end else state<=WADDR;
    end
    WADDR,WDATA:begin
     if(state==WADDR && h_awready===1'b1) state<=WDATA;
     if(nw_take) begin
      if(pos_q==span_q-1) begin
       if(write_phase_poisoned) begin response_q<=2'b10;state<=BRESP;end else state<=VPRE;
      end else begin
       pos_q<=pos_q+1'b1;
      end
     end
    end
    VPRE:begin
     pos_q<=0;
     if(quiet_poisoned) begin response_q<=2'b10;state<=BRESP;end else state<=VADDR;
    end
    VADDR,VDATA:begin
     if(state==VADDR && h_arready===1'b1) state<=VDATA;
     if(nr_take) begin
      if(pos_q==span_q-1) begin response_q<=poisoned ? 2'b10:2'b00;state<=BRESP;end
      else begin
       pos_q<=pos_q+1'b1;
      end
     end
    end
    RADDR,RDATA:begin
     if(state==RADDR && h_arready===1'b1) state<=RDATA;
     if(nr_take) begin
      if(!read_phase_poisoned) returned[pos_q]<=h_rdata;
      if(pos_q==span_q-1) begin response_q<=read_phase_poisoned ? 2'b10:2'b00;state<=RPRE;end
      else pos_q<=pos_q+1'b1;
     end
    end
    RPRE:begin
     up_q<=0;
     if(quiet_poisoned) begin response_q<=2'b10;rdata_q<=0;end
     else rdata_q<=response_q!=0 ? 128'b0:(half_q ? returned[0][255:128]:returned[0][127:0]);
     state<=RRESP;
    end
    RRESP:if(rready) begin
     if(up_q==beats_q-1) state<=quiet_poisoned ? QUARANTINE:IDLE;
     else begin
      up_q<=up_q+1'b1;
      rdata_q<=response_q!=0 ? 128'b0:(next_lane[0] ? returned[next_lane[4:1]][255:128]:returned[next_lane[4:1]][127:0]);
     end
    end
    BRESP:if(bready) state<=quiet_poisoned ? QUARANTINE:IDLE;
    default:state<=QUARANTINE;
   endcase
  end
 end
endmodule
