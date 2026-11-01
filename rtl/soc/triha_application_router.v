/* Production CPU memory and control routing, all ports on clk_i.
 * Map: ROM [0,0x2000), SRAM [0x10000,0x18000), NPU 0x2000xxxx,
 * Video 0x2001xxxx, DDR [0x80000000,0x88000000). Only private DDR
 * [0x80000000,0x82000000) is cached by triha_cache_subsystem.
 * One accepted transaction per I/D port locks owner and D tag until response.
 * DDR ready/fault gate new requests only; accepted responses remain connected.
 * Global cache maintenance and FENCE.I retain the admitted cache semantics.
 * Coordinated CPU/cache/fabric reset is required to start a new failure epoch.
 */
`default_nettype none
module triha_application_router #(
    parameter ROM_FILE = "rom.hex",
    parameter SRAM_FILE = "sram.hex",
    parameter integer CACHE_ENABLE = 1
) (
    input wire clk_i,
    input wire rst_ni,
    input wire ddr_ready_i,
    input wire ddr_fault_i,
    output wire ddr_fault_o,
    output wire protocol_fault_o,
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
    output wire [31:0] npu_axi_awaddr_o,
    output wire [2:0] npu_axi_awprot_o,
    output wire npu_axi_awvalid_o,
    input wire npu_axi_awready_i,
    output wire [31:0] npu_axi_wdata_o,
    output wire [3:0] npu_axi_wstrb_o,
    output wire npu_axi_wvalid_o,
    input wire npu_axi_wready_i,
    input wire [1:0] npu_axi_bresp_i,
    input wire npu_axi_bvalid_i,
    output wire npu_axi_bready_o,
    output wire [31:0] npu_axi_araddr_o,
    output wire [2:0] npu_axi_arprot_o,
    output wire npu_axi_arvalid_o,
    input wire npu_axi_arready_i,
    input wire [31:0] npu_axi_rdata_i,
    input wire [1:0] npu_axi_rresp_i,
    input wire npu_axi_rvalid_i,
    output wire npu_axi_rready_o,
    output wire [31:0] video_axi_awaddr_o,
    output wire [2:0] video_axi_awprot_o,
    output wire video_axi_awvalid_o,
    input wire video_axi_awready_i,
    output wire [31:0] video_axi_wdata_o,
    output wire [3:0] video_axi_wstrb_o,
    output wire video_axi_wvalid_o,
    input wire video_axi_wready_i,
    input wire [1:0] video_axi_bresp_i,
    input wire video_axi_bvalid_i,
    output wire video_axi_bready_o,
    output wire [31:0] video_axi_araddr_o,
    output wire [2:0] video_axi_arprot_o,
    output wire video_axi_arvalid_o,
    input wire video_axi_arready_i,
    input wire [31:0] video_axi_rdata_i,
    input wire [1:0] video_axi_rresp_i,
    input wire video_axi_rvalid_i,
    output wire video_axi_rready_o,
    output wire axi_awvalid_o,
    output wire [31:0] axi_awaddr_o,
    output wire [3:0] axi_awid_o,
    output wire [7:0] axi_awlen_o,
    output wire [2:0] axi_awsize_o,
    output wire [1:0] axi_awburst_o,
    input wire axi_awready_i,
    output wire axi_wvalid_o,
    output wire [127:0] axi_wdata_o,
    output wire [15:0] axi_wstrb_o,
    output wire axi_wlast_o,
    input wire axi_wready_i,
    input wire axi_bvalid_i,
    input wire [1:0] axi_bresp_i,
    input wire [3:0] axi_bid_i,
    output wire axi_bready_o,
    output wire axi_arvalid_o,
    output wire [31:0] axi_araddr_o,
    output wire [3:0] axi_arid_o,
    output wire [7:0] axi_arlen_o,
    output wire [2:0] axi_arsize_o,
    output wire [1:0] axi_arburst_o,
    input wire axi_arready_i,
    input wire axi_rvalid_i,
    input wire [127:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire [3:0] axi_rid_i,
    input wire axi_rlast_i,
    output wire axi_rready_o
);
    localparam [2:0] LOCAL=3'd0, CACHE=3'd1, NPU=3'd2, VIDEO=3'd3, ERROR=3'd4;
    reg i_pending_q, d_pending_q, fault_q;
    reg [2:0] i_owner_q, d_owner_q;
    reg [10:0] d_tag_q;
    reg local_i_valid_q, local_i_rom_q, local_i_error_q;
    reg local_d_ack_q, local_d_rom_q, local_d_error_q, local_d_high_q, local_d_read_q;
    wire [63:0] rom_i_data, rom_d_data, sram_i_data, sram_d_data;
    wire c_i_accept,c_i_valid,c_i_error,c_d_accept,c_d_ack,c_d_error;
    wire [63:0] c_i_data;
    wire [31:0] c_d_data;
    wire [10:0] c_d_tag;
    wire n_accept,n_ack,n_error,v_accept,v_ack,v_error;
    wire [31:0] n_data,v_data;
    wire [10:0] n_tag,v_tag;
    wire failed = fault_q || ddr_fault_i || protocol_fault_o;
    wire ready = ddr_ready_i && !failed;
    assign ddr_fault_o = failed;
    wire i_aligned = inst_addr_i[2:0] == 3'b000;
    wire i_rom = i_aligned && inst_addr_i <= 32'h00001ff8;
    wire i_sram = i_aligned && inst_addr_i >= 32'h00010000 && inst_addr_i <= 32'h00017ff8;
    wire i_ddr = i_aligned && inst_addr_i >= 32'h80000000 && inst_addr_i <= 32'h87fffff8;
    wire d_rom = data_addr_i < 32'h00002000;
    wire d_sram = data_addr_i >= 32'h00010000 && data_addr_i < 32'h00018000;
    wire d_ddr = data_addr_i >= 32'h80000000 && data_addr_i < 32'h88000000;
    wire maintenance = data_invalidate_i || data_writeback_i || data_flush_i;
    wire d_request = data_re_i || (|data_wstrb_i) || maintenance;
    wire d_bad = data_addr_i[1:0] != 2'b00 || (data_re_i && (|data_wstrb_i));
    wire [2:0] i_target = i_rom || i_sram ? LOCAL : i_ddr && !failed ? CACHE : ERROR;
    wire [2:0] d_target = maintenance ? CACHE :
        d_rom || d_sram ? LOCAL :
        data_addr_i[31:16] == 16'h2000 ? NPU :
        data_addr_i[31:16] == 16'h2001 ? VIDEO :
        d_ddr && !failed ? CACHE : ERROR;
    wire d_allow = rst_ni && !d_pending_q && (maintenance || !d_ddr || ready || failed);
    assign data_accept_o = d_allow && (d_target == CACHE ? c_d_accept :
        d_target == NPU ? n_accept : d_target == VIDEO ? v_accept : 1'b1);
    wire d_fire = d_request && data_accept_o;
    wire sram_write = d_fire && d_target == LOCAL && d_sram && !d_bad && (|data_wstrb_i);
    wire collision = sram_write && i_sram && inst_addr_i[14:3] == data_addr_i[14:3];
    wire i_allow = rst_ni && !i_pending_q && (!i_ddr || ready || failed) && !collision;
    assign inst_accept_o = i_allow && (i_target == CACHE ? c_i_accept : 1'b1);
    wire i_fire = inst_req_i && inst_accept_o;
    assign inst_valid_o = i_pending_q && (i_owner_q == CACHE ? c_i_valid : local_i_valid_q);
    assign inst_error_o = i_owner_q == CACHE ? c_i_error : local_i_error_q;
    assign inst_rdata_o = i_owner_q == CACHE ? c_i_data :
        local_i_error_q ? 64'b0 : local_i_rom_q ? rom_i_data : sram_i_data;
    assign data_ack_o = d_pending_q && (d_owner_q == CACHE ? c_d_ack :
        d_owner_q == NPU ? n_ack : d_owner_q == VIDEO ? v_ack : local_d_ack_q);
    assign data_error_o = d_owner_q == CACHE ? c_d_error :
        d_owner_q == NPU ? n_error : d_owner_q == VIDEO ? v_error : local_d_error_q;
    wire [63:0] local_d_value = local_d_rom_q ? rom_d_data : sram_d_data;
    assign data_rdata_o = d_owner_q == CACHE ? c_d_data :
        d_owner_q == NPU ? n_data : d_owner_q == VIDEO ? v_data :
        !local_d_read_q || local_d_error_q ? 32'b0 :
        local_d_high_q ? local_d_value[63:32] : local_d_value[31:0];
    assign data_resp_tag_o = d_tag_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            i_pending_q <= 1'b0; d_pending_q <= 1'b0; fault_q <= 1'b0;
            i_owner_q <= ERROR; d_owner_q <= ERROR; d_tag_q <= 11'b0;
            local_i_valid_q <= 1'b0; local_i_rom_q <= 1'b0; local_i_error_q <= 1'b0;
            local_d_ack_q <= 1'b0; local_d_rom_q <= 1'b0; local_d_error_q <= 1'b0;
            local_d_high_q <= 1'b0; local_d_read_q <= 1'b0;
        end else begin
            fault_q <= failed;
            if (inst_valid_o) i_pending_q <= 1'b0;
            if (data_ack_o) d_pending_q <= 1'b0;
            if (i_fire) begin i_pending_q <= 1'b1; i_owner_q <= i_target; end
            if (d_fire) begin d_pending_q <= 1'b1; d_owner_q <= d_target; d_tag_q <= data_req_tag_i; end
            local_i_valid_q <= i_fire && i_target != CACHE;
            if (i_fire) begin local_i_rom_q <= i_rom; local_i_error_q <= i_target == ERROR; end
            local_d_ack_q <= d_fire && (d_target == LOCAL || d_target == ERROR);
            if (d_fire) begin
                local_d_rom_q <= d_rom; local_d_high_q <= data_addr_i[2]; local_d_read_q <= data_re_i;
                local_d_error_q <= d_target == ERROR || d_bad || (d_rom && (|data_wstrb_i));
            end
        end
    end
    triha_boot_rom #(.INIT_FILE(ROM_FILE)) u_rom (
        .clk_i(clk_i),.inst_en_i(i_fire && i_rom),.inst_addr_i(inst_addr_i[12:3]),.inst_rdata_o(rom_i_data),
        .data_en_i(d_fire && d_target == LOCAL && d_rom && !d_bad && data_re_i),
        .data_addr_i(data_addr_i[12:3]),.data_rdata_o(rom_d_data)
    );
    triha_sram #(.INIT_FILE(SRAM_FILE)) u_sram (
        .clk_i(clk_i),.inst_en_i(i_fire && i_sram),.inst_addr_i(inst_addr_i[14:3]),.inst_rdata_o(sram_i_data),
        .data_en_i(d_fire && d_target == LOCAL && d_sram && !d_bad),.data_addr_i(data_addr_i[14:3]),
        .data_wdata_i({data_wdata_i,data_wdata_i}),
        .data_wstrb_i(sram_write ? (data_addr_i[2] ? {data_wstrb_i,4'b0} : {4'b0,data_wstrb_i}) : 8'b0),
        .data_rdata_o(sram_d_data)
    );
    triha_cache_subsystem #(.ICACHE_ENABLE(CACHE_ENABLE),.DCACHE_ENABLE(CACHE_ENABLE)) u_cache (
        .clk_i(clk_i),.rst_ni(rst_ni),
        .inst_req_i(inst_req_i && i_allow && i_target == CACHE),.inst_addr_i(inst_addr_i),
        .inst_flush_i(inst_flush_i),.inst_invalidate_i(inst_invalidate_i),
        .inst_accept_o(c_i_accept),.inst_valid_o(c_i_valid),.inst_error_o(c_i_error),.inst_rdata_o(c_i_data),
        .data_addr_i(data_addr_i),.data_wdata_i(data_wdata_i),.data_cacheable_i(data_cacheable_i),.data_req_tag_i(data_req_tag_i),
        .data_re_i(data_re_i && d_allow && d_target == CACHE),
        .data_wstrb_i(data_wstrb_i & {4{d_allow && d_target == CACHE}}),
        .data_invalidate_i(data_invalidate_i && d_allow && d_target == CACHE),
        .data_writeback_i(data_writeback_i && d_allow && d_target == CACHE),
        .data_flush_i(data_flush_i && d_allow && d_target == CACHE),
        .data_accept_o(c_d_accept),.data_ack_o(c_d_ack),.data_error_o(c_d_error),.data_rdata_o(c_d_data),.data_resp_tag_o(c_d_tag),
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
    cpu_native_axil #(.MMIO_PREFIX(16'h2000)) u_npu_control (
        .clk_i(clk_i),.rst_ni(rst_ni),.cpu_addr_i(data_addr_i),.cpu_wdata_i(data_wdata_i),
        .cpu_re_i(data_re_i && d_allow && d_target == NPU),
        .cpu_wstrb_i(data_wstrb_i & {4{d_allow && d_target == NPU}}),
        .cpu_cacheable_i(data_cacheable_i),.cpu_req_tag_i(data_req_tag_i),
        .cpu_invalidate_i(1'b0),.cpu_writeback_i(1'b0),.cpu_flush_i(1'b0),
        .cpu_accept_o(n_accept),.cpu_ack_o(n_ack),.cpu_error_o(n_error),
        .cpu_rdata_o(n_data),.cpu_resp_tag_o(n_tag),
        .m_axi_awaddr_o(npu_axi_awaddr_o),
        .m_axi_awprot_o(npu_axi_awprot_o),
        .m_axi_awvalid_o(npu_axi_awvalid_o),
        .m_axi_awready_i(npu_axi_awready_i),
        .m_axi_wdata_o(npu_axi_wdata_o),
        .m_axi_wstrb_o(npu_axi_wstrb_o),
        .m_axi_wvalid_o(npu_axi_wvalid_o),
        .m_axi_wready_i(npu_axi_wready_i),
        .m_axi_bresp_i(npu_axi_bresp_i),
        .m_axi_bvalid_i(npu_axi_bvalid_i),
        .m_axi_bready_o(npu_axi_bready_o),
        .m_axi_araddr_o(npu_axi_araddr_o),
        .m_axi_arprot_o(npu_axi_arprot_o),
        .m_axi_arvalid_o(npu_axi_arvalid_o),
        .m_axi_arready_i(npu_axi_arready_i),
        .m_axi_rdata_i(npu_axi_rdata_i),
        .m_axi_rresp_i(npu_axi_rresp_i),
        .m_axi_rvalid_i(npu_axi_rvalid_i),
        .m_axi_rready_o(npu_axi_rready_o)
    );
    cpu_native_axil #(.MMIO_PREFIX(16'h2001)) u_video_control (
        .clk_i(clk_i),.rst_ni(rst_ni),.cpu_addr_i(data_addr_i),.cpu_wdata_i(data_wdata_i),
        .cpu_re_i(data_re_i && d_allow && d_target == VIDEO),
        .cpu_wstrb_i(data_wstrb_i & {4{d_allow && d_target == VIDEO}}),
        .cpu_cacheable_i(data_cacheable_i),.cpu_req_tag_i(data_req_tag_i),
        .cpu_invalidate_i(1'b0),.cpu_writeback_i(1'b0),.cpu_flush_i(1'b0),
        .cpu_accept_o(v_accept),.cpu_ack_o(v_ack),.cpu_error_o(v_error),
        .cpu_rdata_o(v_data),.cpu_resp_tag_o(v_tag),
        .m_axi_awaddr_o(video_axi_awaddr_o),
        .m_axi_awprot_o(video_axi_awprot_o),
        .m_axi_awvalid_o(video_axi_awvalid_o),
        .m_axi_awready_i(video_axi_awready_i),
        .m_axi_wdata_o(video_axi_wdata_o),
        .m_axi_wstrb_o(video_axi_wstrb_o),
        .m_axi_wvalid_o(video_axi_wvalid_o),
        .m_axi_wready_i(video_axi_wready_i),
        .m_axi_bresp_i(video_axi_bresp_i),
        .m_axi_bvalid_i(video_axi_bvalid_i),
        .m_axi_bready_o(video_axi_bready_o),
        .m_axi_araddr_o(video_axi_araddr_o),
        .m_axi_arprot_o(video_axi_arprot_o),
        .m_axi_arvalid_o(video_axi_arvalid_o),
        .m_axi_arready_i(video_axi_arready_i),
        .m_axi_rdata_i(video_axi_rdata_i),
        .m_axi_rresp_i(video_axi_rresp_i),
        .m_axi_rvalid_i(video_axi_rvalid_i),
        .m_axi_rready_o(video_axi_rready_o)
    );
endmodule
`default_nettype wire
