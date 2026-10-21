/* TriHa local-memory / paired-cache router. All ports use clk_i.
 * Response ownership is captured on acceptance; target changes drain first.
 * DDR readiness gates new CPU requests only. Accepted cache/AXI transactions
 * and responses remain connected until completion or coordinated reset.
 * DDR fault is sticky. No CDC or physical DDR controller is implied. */
`include "cpu_cache_map.vh"
module triha_cpu_memory_router #(
    parameter ROM_FILE = "rom.hex",
    parameter SRAM_FILE = "sram.hex",
    parameter integer CACHE_ENABLE = 1
) (
    input wire clk_i,
    input wire rst_ni,
    input wire ddr_ready_i,
    input wire ddr_fault_i,
    output wire ddr_fault_o,
    output wire uart_tx_o,
    output wire done_o,
    output wire [7:0] exit_code_o,
    input wire inst_req_i,
    input wire inst_flush_i,
    input wire inst_invalidate_i,
    input wire [31:0] inst_addr_i,
    output wire inst_accept_o,
    output wire inst_valid_o,
    output wire inst_error_o,
    output wire [63:0] inst_rdata_o,
    input wire [31:0] data_addr_i,
    input wire [31:0] data_wdata_i,
    input wire data_re_i,
    input wire [3:0] data_wstrb_i,
    input wire data_cacheable_i,
    input wire [10:0] data_req_tag_i,
    input wire data_invalidate_i,
    input wire data_writeback_i,
    input wire data_flush_i,
    output wire [31:0] data_rdata_o,
    output wire data_accept_o,
    output wire data_ack_o,
    output wire data_error_o,
    output wire [10:0] data_resp_tag_o,
    output wire protocol_fault_o,
    output wire         axi_awvalid_o,
    output wire [31:0]  axi_awaddr_o,
    output wire [3:0]   axi_awid_o,
    output wire [7:0]   axi_awlen_o,
    output wire [2:0]   axi_awsize_o,
    output wire [1:0]   axi_awburst_o,
    input  wire         axi_awready_i,
    output wire         axi_wvalid_o,
    output wire [127:0] axi_wdata_o,
    output wire [15:0]  axi_wstrb_o,
    output wire         axi_wlast_o,
    input  wire         axi_wready_i,
    input  wire         axi_bvalid_i,
    input  wire [1:0]   axi_bresp_i,
    input  wire [3:0]   axi_bid_i,
    output wire         axi_bready_o,
    output wire         axi_arvalid_o,
    output wire [31:0]  axi_araddr_o,
    output wire [3:0]   axi_arid_o,
    output wire [7:0]   axi_arlen_o,
    output wire [2:0]   axi_arsize_o,
    output wire [1:0]   axi_arburst_o,
    input  wire         axi_arready_i,
    input  wire         axi_rvalid_i,
    input  wire [127:0] axi_rdata_i,
    input  wire [1:0]   axi_rresp_i,
    input  wire [3:0]   axi_rid_i,
    input  wire         axi_rlast_i,
    output wire         axi_rready_o
);
    wire  c_inst_accept;
    wire  c_inst_valid;
    wire  c_inst_error;
    wire [63:0] c_inst_rdata;
    wire [31:0] c_data_rdata;
    wire  c_data_accept;
    wire  c_data_ack;
    wire  c_data_error;
    wire [10:0] c_data_resp_tag;
    wire  l_inst_accept;
    wire  l_inst_valid;
    wire  l_inst_error;
    wire [63:0] l_inst_rdata;
    wire [31:0] l_data_rdata;
    wire  l_data_accept;
    wire  l_data_ack;
    wire  l_data_error;
    wire [10:0] l_data_resp_tag;
    localparam [1:0] LOCAL = 0, CACHE = 1, SYNTHETIC = 2;
    reg fault_q;
    reg [1:0] i_owner_q, d_owner_q;
    reg [2:0] i_pending_q, d_pending_q;
    reg s_inst_valid_q, s_data_ack_q, s_data_error_q;
    reg [31:0] s_data_q;
    reg [10:0] s_tag_q;
    wire fault_w = fault_q || ddr_fault_i || protocol_fault_o;
    wire ready_w = ddr_ready_i && !fault_w;
    assign ddr_fault_o = fault_w;
    wire i_ddr_w = inst_addr_i >= `TRIHA_CPU_DDR_BASE && inst_addr_i < `TRIHA_CPU_DDR_END;
    wire d_ddr_w = data_addr_i >= `TRIHA_CPU_DDR_BASE && data_addr_i < `TRIHA_CPU_DDR_END;
    wire d_status_w = data_addr_i == `TRIHA_CPU_DDR_STATUS_ADDR;
    wire d_maintenance_w = data_invalidate_i || data_writeback_i || data_flush_i;
    wire d_request_w = data_re_i || (|data_wstrb_i) || d_maintenance_w;
    wire [1:0] i_target_w = i_ddr_w ? (fault_w ? SYNTHETIC : CACHE) : LOCAL;
    wire [1:0] d_target_w = d_maintenance_w ? CACHE :
        d_status_w ? SYNTHETIC : d_ddr_w ? (fault_w ? SYNTHETIC : CACHE) : LOCAL;
    wire i_allow_w = rst_ni && i_pending_q != 7 &&
        (i_pending_q == 0 || i_owner_q == i_target_w) && (!i_ddr_w || ready_w || fault_w);
    wire d_allow_w = rst_ni && d_pending_q != 7 &&
        (d_pending_q == 0 || d_owner_q == d_target_w) &&
        (d_maintenance_w || !d_ddr_w || ready_w || fault_w);
    assign inst_accept_o = i_allow_w && (i_target_w == LOCAL ? l_inst_accept :
        i_target_w == CACHE ? c_inst_accept : 1'b1);
    assign data_accept_o = d_allow_w && (d_target_w == LOCAL ? l_data_accept :
        d_target_w == CACHE ? c_data_accept : 1'b1);
    wire i_fire_w = inst_req_i && inst_accept_o;
    wire d_fire_w = d_request_w && data_accept_o;
    assign inst_valid_o = (|i_pending_q) && (i_owner_q == LOCAL ? l_inst_valid :
        i_owner_q == CACHE ? c_inst_valid : s_inst_valid_q);
    assign inst_error_o = i_owner_q == LOCAL ? l_inst_error :
        i_owner_q == CACHE ? c_inst_error : 1'b1;
    assign inst_rdata_o = i_owner_q == LOCAL ? l_inst_rdata :
        i_owner_q == CACHE ? c_inst_rdata : 64'b0;
    assign data_ack_o = (|d_pending_q) && (d_owner_q == LOCAL ? l_data_ack :
        d_owner_q == CACHE ? c_data_ack : s_data_ack_q);
    assign data_error_o = d_owner_q == LOCAL ? l_data_error :
        d_owner_q == CACHE ? c_data_error : s_data_error_q;
    assign data_rdata_o = d_owner_q == LOCAL ? l_data_rdata :
        d_owner_q == CACHE ? c_data_rdata : s_data_q;
    assign data_resp_tag_o = d_owner_q == LOCAL ? l_data_resp_tag :
        d_owner_q == CACHE ? c_data_resp_tag : s_tag_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fault_q <= 0;
            i_owner_q <= LOCAL; d_owner_q <= LOCAL;
            i_pending_q <= 0; d_pending_q <= 0;
            s_inst_valid_q <= 0; s_data_ack_q <= 0; s_data_error_q <= 0;
            s_data_q <= 0; s_tag_q <= 0;
        end else begin
            fault_q <= fault_w;
            case ({i_fire_w, inst_valid_o})
                2'b10: i_pending_q <= i_pending_q + 1'b1;
                2'b01: i_pending_q <= i_pending_q - 1'b1;
                default: ;
            endcase
            case ({d_fire_w, data_ack_o})
                2'b10: d_pending_q <= d_pending_q + 1'b1;
                2'b01: d_pending_q <= d_pending_q - 1'b1;
                default: ;
            endcase
            if (i_fire_w) i_owner_q <= i_target_w;
            if (d_fire_w) d_owner_q <= d_target_w;
            s_inst_valid_q <= i_fire_w && i_target_w == SYNTHETIC;
            s_data_ack_q <= d_fire_w && d_target_w == SYNTHETIC;
            if (d_fire_w && d_target_w == SYNTHETIC) begin
                s_data_error_q <= !d_status_w || !data_re_i || (|data_wstrb_i);
                s_data_q <= (ready_w ? `TRIHA_CPU_DDR_READY : 32'b0) |
                    (fault_w ? `TRIHA_CPU_DDR_FAULT : 32'b0);
                s_tag_q <= data_req_tag_i;
            end
        end
    end
    triha_cache_subsystem #(.ICACHE_ENABLE(CACHE_ENABLE), .DCACHE_ENABLE(CACHE_ENABLE)) u_cache (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .inst_req_i(inst_req_i && i_allow_w && i_target_w == CACHE),
        .inst_flush_i(inst_flush_i),
        .inst_invalidate_i(inst_invalidate_i),
        .inst_addr_i(inst_addr_i),
        .inst_accept_o(c_inst_accept),
        .inst_valid_o(c_inst_valid),
        .inst_error_o(c_inst_error),
        .inst_rdata_o(c_inst_rdata),
        .data_addr_i(data_addr_i),
        .data_wdata_i(data_wdata_i),
        .data_re_i(data_re_i & {1{d_allow_w && d_target_w == CACHE}}),
        .data_wstrb_i(data_wstrb_i & {4{d_allow_w && d_target_w == CACHE}}),
        .data_cacheable_i(data_cacheable_i),
        .data_req_tag_i(data_req_tag_i),
        .data_invalidate_i(data_invalidate_i & {1{d_allow_w && d_target_w == CACHE}}),
        .data_writeback_i(data_writeback_i & {1{d_allow_w && d_target_w == CACHE}}),
        .data_flush_i(data_flush_i & {1{d_allow_w && d_target_w == CACHE}}),
        .data_rdata_o(c_data_rdata),
        .data_accept_o(c_data_accept),
        .data_ack_o(c_data_ack),
        .data_error_o(c_data_error),
        .data_resp_tag_o(c_data_resp_tag),
        .protocol_fault_o(protocol_fault_o),
        .axi_awvalid_o(axi_awvalid_o),
        .axi_awaddr_o(axi_awaddr_o),
        .axi_awid_o(axi_awid_o),
        .axi_awlen_o(axi_awlen_o),
        .axi_awsize_o(axi_awsize_o),
        .axi_awburst_o(axi_awburst_o),
        .axi_awready_i(axi_awready_i),
        .axi_wvalid_o(axi_wvalid_o),
        .axi_wdata_o(axi_wdata_o),
        .axi_wstrb_o(axi_wstrb_o),
        .axi_wlast_o(axi_wlast_o),
        .axi_wready_i(axi_wready_i),
        .axi_bvalid_i(axi_bvalid_i),
        .axi_bresp_i(axi_bresp_i),
        .axi_bid_i(axi_bid_i),
        .axi_bready_o(axi_bready_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arid_o(axi_arid_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arsize_o(axi_arsize_o),
        .axi_arburst_o(axi_arburst_o),
        .axi_arready_i(axi_arready_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rid_i(axi_rid_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rready_o(axi_rready_o)
    );
    triha_soc_memory #(.ROM_FILE(ROM_FILE), .SRAM_FILE(SRAM_FILE)) u_memory (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .inst_req_i(inst_req_i && i_allow_w && i_target_w == LOCAL),
        .inst_addr_i(inst_addr_i),
        .inst_accept_o(l_inst_accept),
        .inst_valid_o(l_inst_valid),
        .inst_error_o(l_inst_error),
        .inst_rdata_o(l_inst_rdata),
        .data_addr_i(data_addr_i),
        .data_wdata_i(data_wdata_i),
        .data_re_i(data_re_i & {1{d_allow_w && d_target_w == LOCAL}}),
        .data_wstrb_i(data_wstrb_i & {4{d_allow_w && d_target_w == LOCAL}}),
        .data_req_tag_i(data_req_tag_i),
        .data_invalidate_i(data_invalidate_i & {1{d_allow_w && d_target_w == LOCAL}}),
        .data_writeback_i(data_writeback_i & {1{d_allow_w && d_target_w == LOCAL}}),
        .data_flush_i(data_flush_i & {1{d_allow_w && d_target_w == LOCAL}}),
        .data_accept_o(l_data_accept),
        .data_ack_o(l_data_ack),
        .data_error_o(l_data_error),
        .data_rdata_o(l_data_rdata),
        .data_resp_tag_o(l_data_resp_tag),
        .uart_tx_o(uart_tx_o),
        .done_o(done_o),
        .exit_code_o(exit_code_o)
    );
endmodule
