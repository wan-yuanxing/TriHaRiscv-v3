/* TriHa single native DDR owner at the 125 MHz UI boundary.
 * AXI128 packed lanes: 0=compute (CPU/NPU after shared CDC), 1=capture write,
 * 2=display read (including its asset-read arbiter). Tie unused channels low.
 * This is the only AXI128/HMIC256 bridge in the assembled DDR path.
 * healthy_i gates admission only; init_done_i is the actual HMIC observation.
 */
`default_nettype none
module soc_ddr_fabric #(
    parameter integer NATIVE_TIMEOUT_CYCLES=125000000
)(
    input wire clk_i,rst_ni,healthy_i,init_done_i,
    input wire [2:0] s_awvalid_i,output wire [2:0] s_awready_o,
    input wire [95:0] s_awaddr_i,input wire [11:0] s_awid_i,
    input wire [23:0] s_awlen_i,input wire [8:0] s_awsize_i,input wire [5:0] s_awburst_i,
    input wire [2:0] s_wvalid_i,output wire [2:0] s_wready_o,
    input wire [383:0] s_wdata_i,input wire [47:0] s_wstrb_i,input wire [2:0] s_wlast_i,
    output wire [2:0] s_bvalid_o,input wire [2:0] s_bready_i,
    output wire [11:0] s_bid_o,output wire [5:0] s_bresp_o,
    input wire [2:0] s_arvalid_i,output wire [2:0] s_arready_o,
    input wire [95:0] s_araddr_i,input wire [11:0] s_arid_i,
    input wire [23:0] s_arlen_i,input wire [8:0] s_arsize_i,input wire [5:0] s_arburst_i,
    output wire [2:0] s_rvalid_o,input wire [2:0] s_rready_i,
    output wire [383:0] s_rdata_o,output wire [11:0] s_rid_o,
    output wire [5:0] s_rresp_o,output wire [2:0] s_rlast_o,
    output wire idle_o,output reg fault_o,output reg [7:0] fault_code_o,
    output wire [27:0] h_awaddr,h_araddr,output wire [3:0] h_awlen,h_arlen,h_awid,h_arid,
    output wire h_awvalid,h_arvalid,input wire h_awready,h_arready,h_wready,h_rvalid,
    output wire [255:0] h_wdata,output wire [31:0] h_wstrb,input wire [255:0] h_rdata,
    input wire [3:0] h_wid,h_rid,input wire h_wlast,h_rlast
);
    wire m_awvalid,m_awready,m_wvalid,m_wready,m_wlast,m_bvalid,m_bready;
    wire m_arvalid,m_arready,m_rvalid,m_rready,m_rlast;
    wire [31:0] m_awaddr,m_araddr;wire [3:0] m_awid,m_arid,m_bid,m_rid;
    wire [7:0] m_awlen,m_arlen;wire [2:0] m_awsize,m_arsize;
    wire [1:0] m_awburst,m_arburst,m_bresp,m_rresp;
    wire [127:0] m_wdata,m_rdata;wire [15:0] m_wstrb;
    wire arbiter_idle,arbiter_fault,bridge_fault;wire [7:0] arbiter_code,bridge_code;
    soc_axi128_arbiter #(.MASTERS(3)) u_arbiter(
        .clk_i(clk_i),.rst_ni(rst_ni),.healthy_i(healthy_i&&init_done_i&&!bridge_fault),
        .s_awvalid_i(s_awvalid_i),.s_awready_o(s_awready_o),.s_awaddr_i(s_awaddr_i),.s_awid_i(s_awid_i),
        .s_awlen_i(s_awlen_i),.s_awsize_i(s_awsize_i),.s_awburst_i(s_awburst_i),
        .s_wvalid_i(s_wvalid_i),.s_wready_o(s_wready_o),.s_wdata_i(s_wdata_i),.s_wstrb_i(s_wstrb_i),.s_wlast_i(s_wlast_i),
        .s_bvalid_o(s_bvalid_o),.s_bready_i(s_bready_i),.s_bid_o(s_bid_o),.s_bresp_o(s_bresp_o),
        .s_arvalid_i(s_arvalid_i),.s_arready_o(s_arready_o),.s_araddr_i(s_araddr_i),.s_arid_i(s_arid_i),
        .s_arlen_i(s_arlen_i),.s_arsize_i(s_arsize_i),.s_arburst_i(s_arburst_i),
        .s_rvalid_o(s_rvalid_o),.s_rready_i(s_rready_i),.s_rdata_o(s_rdata_o),.s_rid_o(s_rid_o),.s_rresp_o(s_rresp_o),.s_rlast_o(s_rlast_o),
        .m_awvalid_o(m_awvalid),.m_awready_i(m_awready),.m_awaddr_o(m_awaddr),.m_awid_o(m_awid),
        .m_awlen_o(m_awlen),.m_awsize_o(m_awsize),.m_awburst_o(m_awburst),
        .m_wvalid_o(m_wvalid),.m_wready_i(m_wready),.m_wdata_o(m_wdata),.m_wstrb_o(m_wstrb),.m_wlast_o(m_wlast),
        .m_bvalid_i(m_bvalid),.m_bready_o(m_bready),.m_bid_i(m_bid),.m_bresp_i(m_bresp),
        .m_arvalid_o(m_arvalid),.m_arready_i(m_arready),.m_araddr_o(m_araddr),.m_arid_o(m_arid),
        .m_arlen_o(m_arlen),.m_arsize_o(m_arsize),.m_arburst_o(m_arburst),
        .m_rvalid_i(m_rvalid),.m_rready_o(m_rready),.m_rdata_i(m_rdata),.m_rid_i(m_rid),.m_rresp_i(m_rresp),.m_rlast_i(m_rlast),
        .idle_o(arbiter_idle),.fault_o(arbiter_fault),.fault_code_o(arbiter_code));
    axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(NATIVE_TIMEOUT_CYCLES)) u_bridge(
        .clk(clk_i),.rst_n(rst_ni),.init_done(init_done_i),
        .awid(m_awid),.arid(m_arid),.awaddr(m_awaddr),.araddr(m_araddr),.awlen(m_awlen),.arlen(m_arlen),
        .awsize(m_awsize),.arsize(m_arsize),.awburst(m_awburst),.arburst(m_arburst),
        .awvalid(m_awvalid),.arvalid(m_arvalid),.wvalid(m_wvalid),.wlast(m_wlast),.bready(m_bready),.rready(m_rready),
        .wdata(m_wdata),.wstrb(m_wstrb),.awready(m_awready),.arready(m_arready),.wready(m_wready),
        .bvalid(m_bvalid),.rvalid(m_rvalid),.rlast(m_rlast),.bid(m_bid),.rid(m_rid),.bresp(m_bresp),.rresp(m_rresp),.rdata(m_rdata),
        .fault(bridge_fault),.fault_code(bridge_code),
        .h_awaddr(h_awaddr),.h_araddr(h_araddr),.h_awlen(h_awlen),.h_arlen(h_arlen),.h_awid(h_awid),.h_arid(h_arid),
        .h_awvalid(h_awvalid),.h_arvalid(h_arvalid),.h_awready(h_awready),.h_arready(h_arready),.h_wready(h_wready),.h_rvalid(h_rvalid),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_rdata(h_rdata),.h_wid(h_wid),.h_rid(h_rid),.h_wlast(h_wlast),.h_rlast(h_rlast));
    assign idle_o=arbiter_idle&&!m_bvalid&&!m_rvalid&&!h_awvalid&&!h_arvalid;
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin fault_o<=0;fault_code_o<=0;end
        else if(!fault_o&&(arbiter_fault||bridge_fault))begin
            fault_o<=1;fault_code_o<=bridge_fault?(8'h80|bridge_code):arbiter_code;
        end
    end
endmodule
`default_nettype wire
