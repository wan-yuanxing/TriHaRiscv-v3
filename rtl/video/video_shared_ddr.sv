`timescale 1ns/1ps
`default_nettype none
// Exclusive Video-local DDR port. All AXI sources already share this core clock.
// This is not the production CPU/NPU fabric or a physical visibility fence.
module video_shared_ddr #(parameter integer MAX_READ_BURSTS=4,NATIVE_TIMEOUT_CYCLES=125000000)(
    input wire clk,reset_n,online,display_urgent,
    input wire [3:0] c_awid,d_arid,
    input wire [31:0] c_awaddr,d_araddr,
    input wire [7:0] c_awlen,d_arlen,
    input wire [2:0] c_awsize,d_arsize,
    input wire [1:0] c_awburst,d_arburst,
    input wire c_awvalid,output wire c_awready,
    input wire [127:0] c_wdata,input wire [15:0] c_wstrb,input wire c_wlast,c_wvalid,
    output wire c_wready,output wire [3:0] c_bid,output wire [1:0] c_bresp,
    output wire c_bvalid,input wire c_bready,
    input wire d_arvalid,output wire d_arready,
    output wire [3:0] d_rid,output wire [127:0] d_rdata,output wire [1:0] d_rresp,
    output wire d_rlast,d_rvalid,input wire d_rready,
    output wire [27:0] h_awaddr,h_araddr,output wire [3:0] h_awlen,h_arlen,h_awid,h_arid,
    output wire h_awvalid,h_arvalid,input wire h_awready,h_arready,h_wready,h_rvalid,
    output wire [255:0] h_wdata,output wire [31:0] h_wstrb,input wire [255:0] h_rdata,
    input wire [3:0] h_wid,h_rid,input wire h_wlast,h_rlast,
    output reg fault,output reg [7:0] fault_code,output wire busy,port_drained,
    output wire [31:0] read_grants,write_grants
);
    wire [3:0] m_awid,m_arid,m_bid,m_rid;
    wire [31:0] m_awaddr,m_araddr;wire [7:0] m_awlen,m_arlen;wire [2:0] m_awsize,m_arsize;
    wire [1:0] m_awburst,m_arburst,m_bresp,m_rresp;
    wire m_awvalid,m_awready,m_wvalid,m_wready,m_wlast,m_bvalid,m_bready;
    wire m_arvalid,m_arready,m_rvalid,m_rready,m_rlast;
    wire [127:0] m_wdata,m_rdata;wire [15:0] m_wstrb;
    wire scheduler_fault,memory_fault;wire [7:0] scheduler_code,bridge_code;
    video_memory_scheduler #(.MAX_READ_BURSTS(MAX_READ_BURSTS)) u_scheduler(
        .clk(clk),
        .reset_n(reset_n),
        .online(online),
        .memory_fault(memory_fault),
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
        .m_awid(m_awid),
        .m_arid(m_arid),
        .m_awaddr(m_awaddr),
        .m_araddr(m_araddr),
        .m_awlen(m_awlen),
        .m_arlen(m_arlen),
        .m_awsize(m_awsize),
        .m_arsize(m_arsize),
        .m_awburst(m_awburst),
        .m_arburst(m_arburst),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wlast(m_wlast),
        .m_wvalid(m_wvalid),
        .m_wready(m_wready),
        .m_bid(m_bid),
        .m_bresp(m_bresp),
        .m_bvalid(m_bvalid),
        .m_bready(m_bready),
        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_rid(m_rid),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_rlast(m_rlast),
        .m_rvalid(m_rvalid),
        .m_rready(m_rready),
        .fault(scheduler_fault),
        .fault_code(scheduler_code),
        .busy(busy),
        .port_drained(port_drained),
        .read_grants(read_grants),
        .write_grants(write_grants));
    axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(NATIVE_TIMEOUT_CYCLES)) u_bridge(
        .clk(clk),.rst_n(reset_n),.init_done(online),
        .awid(m_awid),.awaddr(m_awaddr),.awlen(m_awlen),.awsize(m_awsize),.awburst(m_awburst),
        .awvalid(m_awvalid),.awready(m_awready),.wdata(m_wdata),.wstrb(m_wstrb),.wlast(m_wlast),.wvalid(m_wvalid),.wready(m_wready),
        .bid(m_bid),.bresp(m_bresp),.bvalid(m_bvalid),.bready(m_bready),
        .arid(m_arid),.araddr(m_araddr),.arlen(m_arlen),.arsize(m_arsize),.arburst(m_arburst),.arvalid(m_arvalid),.arready(m_arready),
        .rid(m_rid),.rdata(m_rdata),.rresp(m_rresp),.rlast(m_rlast),.rvalid(m_rvalid),.rready(m_rready),.fault(memory_fault),.fault_code(bridge_code),
        .h_awaddr(h_awaddr),.h_awlen(h_awlen),.h_awid(h_awid),.h_awvalid(h_awvalid),.h_awready(h_awready),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_wready(h_wready),.h_wid(h_wid),.h_wlast(h_wlast),
        .h_araddr(h_araddr),.h_arlen(h_arlen),.h_arid(h_arid),.h_arvalid(h_arvalid),.h_arready(h_arready),
        .h_rdata(h_rdata),.h_rid(h_rid),.h_rlast(h_rlast),.h_rvalid(h_rvalid));
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin fault<=0;fault_code<=0;end
        else if(!fault&&(scheduler_fault||memory_fault))begin
            fault<=1;fault_code<=memory_fault?(8'h80|bridge_code):scheduler_code;
        end
    end
endmodule
`default_nettype wire
