`timescale 1ns/1ps
`default_nettype none
`include "avatar_preset.vh"
// Shared application system: CPU/B03 100 MHz, Video/DDR 125 MHz, pixel 40 MHz.
// Exactly one native DDR bridge lives in u_memory. Board logic supplies clocks,
// coordinated resets, calibrated HMIC, verified model sealing and video ingress.
// Recovery requests never reset the DDR controller from the NPU independently.
module triha_face_system #(
    parameter ROM_FILE="rom.hex", SRAM_FILE="sram.hex",
    parameter integer CACHE_ENABLE=1, ENABLE_AVATAR=0, ENABLE_MODEL_LOADER=0, ENABLE_ROW_CACHE=1, ENABLE_MINIMAL_BOX=0, MINIMAL_CONTROL_CPU=0,
    parameter integer BOOT_AVATAR=0, ENABLE_MODE_KEY=0, MODE_KEY_CLOCK_HZ=125000000,
    parameter integer ENABLE_CAPTURE_PREVIEW=!ENABLE_MINIMAL_BOX,
    parameter integer ENABLE_HARDWARE_POST=1, TRUSTED_MODEL=0, M_LANES=16, QUANTIZER_LANES=2
) (
    input wire compute_clk_i,
    input wire video_clk_i,
    input wire pixel_clk,
    input wire rst_ni,
    input wire mode_button_n,
    input wire pixel_reset_n,
    input wire init_done_i,
    input wire model_sealed_i,
    input wire boot_rx_valid_i,
    input wire [7:0] boot_rx_data_i,
    input wire boot_rx_error_i,
    output wire boot_rx_ready_o,
    output wire boot_tx_valid_o,
    output wire [7:0] boot_tx_data_o,
    input wire boot_tx_ready_i,
    output wire model_sealed_o,
    input wire [31:0] epoch_i,
    input wire [31:0] addr_version_i,
    output wire fault_o,
    output wire recovery_request_o,
    output wire npu_idle_o,
    output wire compute_idle_o,
    output wire ddr_idle_o,
    output wire [7:0] npu_stage_o,
    output wire [7:0] npu_op_o,
    output wire [27:0] h_awaddr,
    output wire [27:0] h_araddr,
    output wire [3:0] h_awlen,
    output wire [3:0] h_arlen,
    output wire [3:0] h_awid,
    output wire [3:0] h_arid,
    output wire h_awvalid,
    output wire h_arvalid,
    input wire h_awready,
    input wire h_arready,
    input wire h_wready,
    input wire h_rvalid,
    output wire [255:0] h_wdata,
    output wire [31:0] h_wstrb,
    input wire [255:0] h_rdata,
    input wire [3:0] h_wid,
    input wire [3:0] h_rid,
    input wire h_wlast,
    input wire h_rlast,
    input wire source_fault,
    input wire overflow,
    input wire src_valid,
    input wire [47:0] src_data,
    output wire src_ready,
    output wire arm_toggle,
    output wire cancel,
    output wire capture_busy,
    output wire capture_port_drained,
    input wire [10:0] pixel_x,
    input wire [10:0] pixel_y,
    input wire pixel_de,
    input wire pixel_hs,
    input wire pixel_vs,
    input wire pixel_frame_start,
    output wire [23:0] out_rgb,
    output wire out_de,
    output wire out_hs,
    output wire out_vs,
    output wire [7:0] capture_code,
    output wire [7:0] display_code,
    output wire [31:0] raw_commits,
    output wire [31:0] raw_scans,
    output wire [31:0] underflows,
    output wire [31:0] raw_frame,
    input wire load_valid,
    output wire load_ready,
    input wire [31:0] load_base,
    input wire [31:0] load_bytes,
    input wire [31:0] load_asset_id,
    input wire [31:0] load_generation,
    input wire [31:0] expected_crc,
    output wire result_valid,
    input wire result_ready,
    output wire result_success,
    output wire [7:0] result_code,
    output wire [31:0] result_asset_id,
    output wire [31:0] result_generation,
    output wire [31:0] checked_bytes,
    output wire [31:0] crc,
    output wire asset_ready,
    output wire pixel_material_ready,
    output wire [31:0] asset_id,
    output wire [31:0] asset_generation,
    output wire [31:0] words_written,
    output wire raw_context_valid,
    output wire [1:0] raw_slot,
    output wire [31:0] raw_generation,
    output wire [10:0] raw_x,
    output wire [10:0] raw_y,
    output wire [23:0] raw_rgb,
    output wire raw_de,
    output wire raw_hs,
    output wire raw_vs,
    output wire raw_sof,
    output wire [10:0] out_x,
    output wire [10:0] out_y,
    output wire [31:0] out_frame,
    output wire [31:0] out_generation,
    output wire [31:0] out_seq,
    output wire [1:0] out_slot,
    output wire [1:0] out_mode,
    output wire out_sof,
    output wire out_box,
    output wire out_point,
    output wire out_avatar,
    output wire out_fault,
    output wire pixel_pending,
    output wire [1:0] pending_mode,
    output wire [1:0] pending_slot,
    output wire [31:0] pending_frame,
    output wire [31:0] pending_generation,
    output wire [2:0] render_faults,
    output wire [7:0] read_code,
    output wire [7:0] material_code,
    output wire [7:0] pixels_code,
    output wire port_drained,
    output wire [31:0] raw_grants,
    output wire [31:0] asset_grants,
    output wire asset_retire_valid,
    input wire asset_retire_ready,
    output wire [1:0] asset_retire_slot,
    output wire [31:0] asset_retire_frame,
    output wire [31:0] asset_retire_generation,
    output wire [31:0] asset_retire_seq,
    output wire [31:0] asset_retire_id,
    output wire [31:0] asset_retire_generation_id,
    output wire owner_error,
    output wire link_error,
    output wire raw_error,
    output wire [7:0] link_code,
    output wire [7:0] raw_code
);
    wire capture_irq;
    wire display_irq;
    wire [2:0] video_faults;
    wire [3:0] video_c_awid;
    wire [31:0] video_c_awaddr;
    wire [7:0] video_c_awlen;
    wire [2:0] video_c_awsize;
    wire [1:0] video_c_awburst;
    wire video_c_awvalid;
    wire video_c_awready;
    wire [127:0] video_c_wdata;
    wire [15:0] video_c_wstrb;
    wire video_c_wlast;
    wire video_c_wvalid;
    wire video_c_wready;
    wire [3:0] video_c_bid;
    wire [1:0] video_c_bresp;
    wire video_c_bvalid;
    wire video_c_bready;
    wire [3:0] video_d_arid;
    wire [31:0] video_d_araddr;
    wire [7:0] video_d_arlen;
    wire [2:0] video_d_arsize;
    wire [1:0] video_d_arburst;
    wire video_d_arvalid;
    wire video_d_arready;
    wire [3:0] video_d_rid;
    wire [127:0] video_d_rdata;
    wire [1:0] video_d_rresp;
    wire video_d_rlast;
    wire video_d_rvalid;
    wire video_d_rready;
    wire compute_reset_n;
    wire compute_ddr_ready;
    wire compute_ddr_fault;
    wire [31:0] ctrl100_awaddr;
    wire [2:0] ctrl100_awprot;
    wire ctrl100_awvalid;
    wire ctrl100_awready;
    wire [31:0] ctrl100_wdata;
    wire [3:0] ctrl100_wstrb;
    wire ctrl100_wvalid;
    wire ctrl100_wready;
    wire [1:0] ctrl100_bresp;
    wire ctrl100_bvalid;
    wire ctrl100_bready;
    wire [31:0] ctrl100_araddr;
    wire [2:0] ctrl100_arprot;
    wire ctrl100_arvalid;
    wire ctrl100_arready;
    wire [31:0] ctrl100_rdata;
    wire [1:0] ctrl100_rresp;
    wire ctrl100_rvalid;
    wire ctrl100_rready;
    wire compute_awvalid;
    wire compute_awready;
    wire [31:0] compute_awaddr;
    wire [3:0] compute_awid;
    wire [7:0] compute_awlen;
    wire [2:0] compute_awsize;
    wire [1:0] compute_awburst;
    wire compute_wvalid;
    wire compute_wready;
    wire [127:0] compute_wdata;
    wire [15:0] compute_wstrb;
    wire compute_wlast;
    wire compute_bvalid;
    wire compute_bready;
    wire [3:0] compute_bid;
    wire [1:0] compute_bresp;
    wire compute_arvalid;
    wire compute_arready;
    wire [31:0] compute_araddr;
    wire [3:0] compute_arid;
    wire [7:0] compute_arlen;
    wire [2:0] compute_arsize;
    wire [1:0] compute_arburst;
    wire compute_rvalid;
    wire compute_rready;
    wire [127:0] compute_rdata;
    wire [3:0] compute_rid;
    wire [1:0] compute_rresp;
    wire compute_rlast;
    wire compute_fault;
    wire npu_irq;
    wire video_reset_n;
    wire cross_awvalid;
    wire [31:0] cross_awaddr;
    wire [3:0] cross_awid;
    wire [7:0] cross_awlen;
    wire [2:0] cross_awsize;
    wire [1:0] cross_awburst;
    wire cross_awready;
    wire cross_wvalid;
    wire [127:0] cross_wdata;
    wire [15:0] cross_wstrb;
    wire cross_wlast;
    wire cross_wready;
    wire cross_bvalid;
    wire [3:0] cross_bid;
    wire [1:0] cross_bresp;
    wire cross_bready;
    wire cross_arvalid;
    wire [31:0] cross_araddr;
    wire [3:0] cross_arid;
    wire [7:0] cross_arlen;
    wire [2:0] cross_arsize;
    wire [1:0] cross_arburst;
    wire cross_arready;
    wire cross_rvalid;
    wire [127:0] cross_rdata;
    wire [3:0] cross_rid;
    wire [1:0] cross_rresp;
    wire cross_rlast;
    wire cross_rready;
    wire [31:0] ctrl125_awaddr;
    wire [2:0] ctrl125_awprot;
    wire ctrl125_awvalid;
    wire ctrl125_awready;
    wire [31:0] ctrl125_wdata;
    wire [3:0] ctrl125_wstrb;
    wire ctrl125_wvalid;
    wire ctrl125_wready;
    wire [1:0] ctrl125_bresp;
    wire ctrl125_bvalid;
    wire ctrl125_bready;
    wire [31:0] ctrl125_araddr;
    wire [2:0] ctrl125_arprot;
    wire ctrl125_arvalid;
    wire ctrl125_arready;
    wire [31:0] ctrl125_rdata;
    wire [1:0] ctrl125_rresp;
    wire ctrl125_rvalid;
    wire ctrl125_rready;
    wire [63:0] endpoints_awaddr;
    wire [5:0] endpoints_awprot;
    wire [1:0] endpoints_awvalid;
    wire [1:0] endpoints_awready;
    wire [63:0] endpoints_wdata;
    wire [7:0] endpoints_wstrb;
    wire [1:0] endpoints_wvalid;
    wire [1:0] endpoints_wready;
    wire [3:0] endpoints_bresp;
    wire [1:0] endpoints_bvalid;
    wire [1:0] endpoints_bready;
    wire [63:0] endpoints_araddr;
    wire [5:0] endpoints_arprot;
    wire [1:0] endpoints_arvalid;
    wire [1:0] endpoints_arready;
    wire [63:0] endpoints_rdata;
    wire [3:0] endpoints_rresp;
    wire [1:0] endpoints_rvalid;
    wire [1:0] endpoints_rready;
    wire unused_awready;
    wire unused_wready;
    wire unused_bvalid;
    wire [3:0] unused_bid;
    wire [1:0] unused_bresp;
    wire unused_arready;
    wire unused_rvalid;
    wire [127:0] unused_rdata;
    wire [3:0] unused_rid;
    wire [1:0] unused_rresp;
    wire unused_rlast;
    wire fabric_fault;
    wire [7:0] fabric_fault_code;
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [1:0] video_irq_sync,compute_fault_sync;
    wire loader_fault,loader_sealed;
    wire boot_awvalid,boot_awready,boot_wvalid,boot_wready,boot_wlast,boot_bvalid,boot_bready;
    wire [31:0] boot_awaddr;
    wire [127:0] boot_wdata;
    wire [1:0] boot_bresp;
    wire lane_awready,lane_wready,lane_bvalid;
    wire [3:0] lane_bid;
    wire [1:0] lane_bresp;
    reg boot_complete;
    // Ownership switches once, only after the loader's final verified B. A
    // later fault revokes the model seal but never steals an active Video port.
    always @(posedge video_clk_i or negedge video_reset_n)
        if(!video_reset_n)boot_complete<=0;else if(loader_sealed)boot_complete<=1;
    wire boot_owner=ENABLE_MODEL_LOADER&&!boot_complete;
    assign model_sealed_o=ENABLE_MODEL_LOADER?loader_sealed:model_sealed_i;
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [1:0] model_seal_sync;
    always @(posedge compute_clk_i or negedge compute_reset_n)
        if(!compute_reset_n)model_seal_sync<=0;else model_seal_sync<={model_seal_sync[0],model_sealed_o};
    generate if(ENABLE_MODEL_LOADER)begin:g_loader
        triha_model_loader #(.AVATAR_BYTES(BOOT_AVATAR?`TRIHA_AVATAR_BYTES:0),.AVATAR_CRC(`TRIHA_AVATAR_CRC32)) u_loader(
            .clk_i(video_clk_i),.rst_ni(video_reset_n),.healthy_i(init_done_i&&!fabric_fault&&!compute_fault_sync[1]),
            .rx_valid_i(boot_rx_valid_i),.rx_ready_o(boot_rx_ready_o),.rx_data_i(boot_rx_data_i),.rx_error_i(boot_rx_error_i),
            .tx_valid_o(boot_tx_valid_o),.tx_ready_i(boot_tx_ready_i),.tx_data_o(boot_tx_data_o),
            .model_sealed_o(loader_sealed),.fault_o(loader_fault),.m_awvalid_o(boot_awvalid),.m_awready_i(boot_awready),
            .m_awaddr_o(boot_awaddr),.m_wvalid_o(boot_wvalid),.m_wready_i(boot_wready),.m_wdata_o(boot_wdata),
            .m_wlast_o(boot_wlast),.m_bvalid_i(boot_bvalid),.m_bready_o(boot_bready),.m_bresp_i(boot_bresp));
    end else begin:g_external_model
        assign loader_fault=0;assign loader_sealed=0;
        assign boot_rx_ready_o=0;assign boot_tx_valid_o=0;assign boot_tx_data_o=0;
        assign boot_awvalid=0;assign boot_awaddr=0;assign boot_wvalid=0;assign boot_wdata=0;assign boot_wlast=0;assign boot_bready=1;
    end endgenerate
    wire material_load_ready;
    reg material_load_sent;
    // The shared boot writer has retired its verified final B before the seal.
    // Hand the immutable preset to the existing checked DDR reader exactly once.
    always @(posedge video_clk_i or negedge video_reset_n)
        if(!video_reset_n)material_load_sent<=0;
        else if(BOOT_AVATAR&&loader_sealed&&material_load_ready)material_load_sent<=1;
    assign load_ready=BOOT_AVATAR?1'b0:material_load_ready;
    assign boot_awready=boot_owner&&lane_awready;
    assign boot_wready=boot_owner&&lane_wready;
    assign boot_bvalid=boot_owner&&lane_bvalid;
    assign boot_bresp=lane_bresp;
    assign video_c_awready=!boot_owner&&lane_awready;
    assign video_c_wready=!boot_owner&&lane_wready;
    assign video_c_bvalid=!boot_owner&&lane_bvalid;
    assign video_c_bid=lane_bid;assign video_c_bresp=lane_bresp;
    // Observations stay reset until their receiving domain has been released.
    // Reuse the CDC's local release chains instead of bypassing them with the
    // board's asynchronous startup reset.
    always @(posedge compute_clk_i or negedge compute_reset_n)
        if(!compute_reset_n)video_irq_sync<=0;else video_irq_sync<={video_irq_sync[0],capture_irq||display_irq};
    always @(posedge video_clk_i or negedge video_reset_n)
        if(!video_reset_n)compute_fault_sync<=0;else compute_fault_sync<={compute_fault_sync[0],compute_fault};
    assign fault_o=compute_fault||compute_ddr_fault||loader_fault;
    assign recovery_request_o=fault_o;
    triha_compute_system #(.ROM_FILE(ROM_FILE),.SRAM_FILE(SRAM_FILE),.CACHE_ENABLE(CACHE_ENABLE),.MINIMAL_CONTROL_CPU(MINIMAL_CONTROL_CPU),.ENABLE_HARDWARE_POST(ENABLE_HARDWARE_POST),.TRUSTED_MODEL(TRUSTED_MODEL),.M_LANES(M_LANES),.QUANTIZER_LANES(QUANTIZER_LANES)) u_compute (
        .clk_i(compute_clk_i),
        .rst_ni(compute_reset_n),
        .healthy_i(compute_ddr_ready),
        .memory_fault_i(compute_ddr_fault),
        .model_sealed_i(model_seal_sync[1]),
        .video_irq_i(video_irq_sync[1]),
        .epoch_i(epoch_i),
        .addr_version_i(addr_version_i),
        .video_axi_awaddr_o(ctrl100_awaddr),
        .video_axi_awprot_o(ctrl100_awprot),
        .video_axi_awvalid_o(ctrl100_awvalid),
        .video_axi_awready_i(ctrl100_awready),
        .video_axi_wdata_o(ctrl100_wdata),
        .video_axi_wstrb_o(ctrl100_wstrb),
        .video_axi_wvalid_o(ctrl100_wvalid),
        .video_axi_wready_i(ctrl100_wready),
        .video_axi_bresp_i(ctrl100_bresp),
        .video_axi_bvalid_i(ctrl100_bvalid),
        .video_axi_bready_o(ctrl100_bready),
        .video_axi_araddr_o(ctrl100_araddr),
        .video_axi_arprot_o(ctrl100_arprot),
        .video_axi_arvalid_o(ctrl100_arvalid),
        .video_axi_arready_i(ctrl100_arready),
        .video_axi_rdata_i(ctrl100_rdata),
        .video_axi_rresp_i(ctrl100_rresp),
        .video_axi_rvalid_i(ctrl100_rvalid),
        .video_axi_rready_o(ctrl100_rready),
        .m_awvalid_o(compute_awvalid),
        .m_awready_i(compute_awready),
        .m_awaddr_o(compute_awaddr),
        .m_awid_o(compute_awid),
        .m_awlen_o(compute_awlen),
        .m_awsize_o(compute_awsize),
        .m_awburst_o(compute_awburst),
        .m_wvalid_o(compute_wvalid),
        .m_wready_i(compute_wready),
        .m_wdata_o(compute_wdata),
        .m_wstrb_o(compute_wstrb),
        .m_wlast_o(compute_wlast),
        .m_bvalid_i(compute_bvalid),
        .m_bready_o(compute_bready),
        .m_bid_i(compute_bid),
        .m_bresp_i(compute_bresp),
        .m_arvalid_o(compute_arvalid),
        .m_arready_i(compute_arready),
        .m_araddr_o(compute_araddr),
        .m_arid_o(compute_arid),
        .m_arlen_o(compute_arlen),
        .m_arsize_o(compute_arsize),
        .m_arburst_o(compute_arburst),
        .m_rvalid_i(compute_rvalid),
        .m_rready_o(compute_rready),
        .m_rdata_i(compute_rdata),
        .m_rid_i(compute_rid),
        .m_rresp_i(compute_rresp),
        .m_rlast_i(compute_rlast),
        .fault_o(compute_fault),
        .npu_irq_o(npu_irq),
        .npu_idle_o(npu_idle_o),
        .compute_idle_o(compute_idle_o),
        .npu_stage_o(npu_stage_o),
        .npu_op_o(npu_op_o)
    );
    triha_axi128_cdc u_compute_cdc (
        .cpu_clk_i(compute_clk_i),
        .ddr_clk_i(video_clk_i),
        .rst_ni(rst_ni),
        .cpu_rst_no(compute_reset_n),
        .ddr_rst_no(video_reset_n),
        .ddr_ready_i(init_done_i),
        .ddr_fault_i(fabric_fault || (|video_faults) || loader_fault),
        .cpu_ddr_ready_o(compute_ddr_ready),
        .cpu_ddr_fault_o(compute_ddr_fault),
        .s_awvalid_i(compute_awvalid),
        .s_awaddr_i(compute_awaddr),
        .s_awid_i(compute_awid),
        .s_awlen_i(compute_awlen),
        .s_awsize_i(compute_awsize),
        .s_awburst_i(compute_awburst),
        .s_awready_o(compute_awready),
        .m_awvalid_o(cross_awvalid),
        .m_awaddr_o(cross_awaddr),
        .m_awid_o(cross_awid),
        .m_awlen_o(cross_awlen),
        .m_awsize_o(cross_awsize),
        .m_awburst_o(cross_awburst),
        .m_awready_i(cross_awready),
        .s_wvalid_i(compute_wvalid),
        .s_wdata_i(compute_wdata),
        .s_wstrb_i(compute_wstrb),
        .s_wlast_i(compute_wlast),
        .s_wready_o(compute_wready),
        .m_wvalid_o(cross_wvalid),
        .m_wdata_o(cross_wdata),
        .m_wstrb_o(cross_wstrb),
        .m_wlast_o(cross_wlast),
        .m_wready_i(cross_wready),
        .s_bvalid_o(compute_bvalid),
        .s_bid_o(compute_bid),
        .s_bresp_o(compute_bresp),
        .s_bready_i(compute_bready),
        .m_bvalid_i(cross_bvalid),
        .m_bid_i(cross_bid),
        .m_bresp_i(cross_bresp),
        .m_bready_o(cross_bready),
        .s_arvalid_i(compute_arvalid),
        .s_araddr_i(compute_araddr),
        .s_arid_i(compute_arid),
        .s_arlen_i(compute_arlen),
        .s_arsize_i(compute_arsize),
        .s_arburst_i(compute_arburst),
        .s_arready_o(compute_arready),
        .m_arvalid_o(cross_arvalid),
        .m_araddr_o(cross_araddr),
        .m_arid_o(cross_arid),
        .m_arlen_o(cross_arlen),
        .m_arsize_o(cross_arsize),
        .m_arburst_o(cross_arburst),
        .m_arready_i(cross_arready),
        .s_rvalid_o(compute_rvalid),
        .s_rdata_o(compute_rdata),
        .s_rid_o(compute_rid),
        .s_rresp_o(compute_rresp),
        .s_rlast_o(compute_rlast),
        .s_rready_i(compute_rready),
        .m_rvalid_i(cross_rvalid),
        .m_rdata_i(cross_rdata),
        .m_rid_i(cross_rid),
        .m_rresp_i(cross_rresp),
        .m_rlast_i(cross_rlast),
        .m_rready_o(cross_rready)
    );
    soc_axil_cdc u_control_cdc (
        .s_clk_i(compute_clk_i),
        .m_clk_i(video_clk_i),
        .rst_ni(rst_ni),
        .s_axi_awaddr_i(ctrl100_awaddr),
        .s_axi_awprot_i(ctrl100_awprot),
        .s_axi_awvalid_i(ctrl100_awvalid),
        .s_axi_awready_o(ctrl100_awready),
        .s_axi_wdata_i(ctrl100_wdata),
        .s_axi_wstrb_i(ctrl100_wstrb),
        .s_axi_wvalid_i(ctrl100_wvalid),
        .s_axi_wready_o(ctrl100_wready),
        .s_axi_bresp_o(ctrl100_bresp),
        .s_axi_bvalid_o(ctrl100_bvalid),
        .s_axi_bready_i(ctrl100_bready),
        .s_axi_araddr_i(ctrl100_araddr),
        .s_axi_arprot_i(ctrl100_arprot),
        .s_axi_arvalid_i(ctrl100_arvalid),
        .s_axi_arready_o(ctrl100_arready),
        .s_axi_rdata_o(ctrl100_rdata),
        .s_axi_rresp_o(ctrl100_rresp),
        .s_axi_rvalid_o(ctrl100_rvalid),
        .s_axi_rready_i(ctrl100_rready),
        .m_axi_awaddr_o(ctrl125_awaddr),
        .m_axi_awprot_o(ctrl125_awprot),
        .m_axi_awvalid_o(ctrl125_awvalid),
        .m_axi_awready_i(ctrl125_awready),
        .m_axi_wdata_o(ctrl125_wdata),
        .m_axi_wstrb_o(ctrl125_wstrb),
        .m_axi_wvalid_o(ctrl125_wvalid),
        .m_axi_wready_i(ctrl125_wready),
        .m_axi_bresp_i(ctrl125_bresp),
        .m_axi_bvalid_i(ctrl125_bvalid),
        .m_axi_bready_o(ctrl125_bready),
        .m_axi_araddr_o(ctrl125_araddr),
        .m_axi_arprot_o(ctrl125_arprot),
        .m_axi_arvalid_o(ctrl125_arvalid),
        .m_axi_arready_i(ctrl125_arready),
        .m_axi_rdata_i(ctrl125_rdata),
        .m_axi_rresp_i(ctrl125_rresp),
        .m_axi_rvalid_i(ctrl125_rvalid),
        .m_axi_rready_o(ctrl125_rready)
    );
    video_axil_decode u_video_decode (
        .clk_i(video_clk_i),
        .rst_ni(video_reset_n),
        .s_axi_awaddr_i(ctrl125_awaddr),
        .m_axi_awaddr_o(endpoints_awaddr),
        .s_axi_awprot_i(ctrl125_awprot),
        .m_axi_awprot_o(endpoints_awprot),
        .s_axi_awvalid_i(ctrl125_awvalid),
        .m_axi_awvalid_o(endpoints_awvalid),
        .s_axi_awready_o(ctrl125_awready),
        .m_axi_awready_i(endpoints_awready),
        .s_axi_wdata_i(ctrl125_wdata),
        .m_axi_wdata_o(endpoints_wdata),
        .s_axi_wstrb_i(ctrl125_wstrb),
        .m_axi_wstrb_o(endpoints_wstrb),
        .s_axi_wvalid_i(ctrl125_wvalid),
        .m_axi_wvalid_o(endpoints_wvalid),
        .s_axi_wready_o(ctrl125_wready),
        .m_axi_wready_i(endpoints_wready),
        .s_axi_bresp_o(ctrl125_bresp),
        .m_axi_bresp_i(endpoints_bresp),
        .s_axi_bvalid_o(ctrl125_bvalid),
        .m_axi_bvalid_i(endpoints_bvalid),
        .s_axi_bready_i(ctrl125_bready),
        .m_axi_bready_o(endpoints_bready),
        .s_axi_araddr_i(ctrl125_araddr),
        .m_axi_araddr_o(endpoints_araddr),
        .s_axi_arprot_i(ctrl125_arprot),
        .m_axi_arprot_o(endpoints_arprot),
        .s_axi_arvalid_i(ctrl125_arvalid),
        .m_axi_arvalid_o(endpoints_arvalid),
        .s_axi_arready_o(ctrl125_arready),
        .m_axi_arready_i(endpoints_arready),
        .s_axi_rdata_o(ctrl125_rdata),
        .m_axi_rdata_i(endpoints_rdata),
        .s_axi_rresp_o(ctrl125_rresp),
        .m_axi_rresp_i(endpoints_rresp),
        .s_axi_rvalid_o(ctrl125_rvalid),
        .m_axi_rvalid_i(endpoints_rvalid),
        .s_axi_rready_i(ctrl125_rready),
        .m_axi_rready_o(endpoints_rready)
    );
    wire [1:0] requested_mode;
    generate if(ENABLE_MODE_KEY)begin:g_mode_key
        triha_face_mode_key #(.CLOCK_HZ(MODE_KEY_CLOCK_HZ)) u_key(
            .clk_i(video_clk_i),.rst_ni(video_reset_n),.button_ni(mode_button_n),.mode_o(requested_mode));
    end else begin:g_no_mode_key
        assign requested_mode=0;
    end endgenerate
    video_application_engine #(.ENABLE_AVATAR(ENABLE_AVATAR),.ENABLE_COMPACT(1),.ENABLE_ROW_CACHE(ENABLE_ROW_CACHE),.ENABLE_MINIMAL_BOX(ENABLE_MINIMAL_BOX),.ENABLE_MODE_KEY(ENABLE_MODE_KEY),.ENABLE_CAPTURE_PREVIEW(ENABLE_CAPTURE_PREVIEW)) u_video (
        .mode_request_i(requested_mode),
        .clk_i(video_clk_i),
        .rst_ni(video_reset_n),
        .pixel_clk(pixel_clk),
        .pixel_reset_n(pixel_reset_n),
        .online(init_done_i && !fabric_fault && !compute_fault_sync[1] && !boot_owner),
        .memory_fault(fabric_fault || compute_fault_sync[1]),
        .display_urgent(1'b1),
        .source_fault(source_fault),
        .overflow(overflow),
        .src_valid(src_valid),
        .src_data(src_data),
        .src_ready(src_ready),
        .arm_toggle(arm_toggle),
        .cancel(cancel),
        .capture_busy(capture_busy),
        .capture_port_drained(capture_port_drained),
        .c_s_axi_awaddr_i(endpoints_awaddr[0+:32]),
        .c_s_axi_awprot_i(endpoints_awprot[0+:3]),
        .c_s_axi_awvalid_i(endpoints_awvalid[0+:1]),
        .c_s_axi_awready_o(endpoints_awready[0+:1]),
        .c_s_axi_wdata_i(endpoints_wdata[0+:32]),
        .c_s_axi_wstrb_i(endpoints_wstrb[0+:4]),
        .c_s_axi_wvalid_i(endpoints_wvalid[0+:1]),
        .c_s_axi_wready_o(endpoints_wready[0+:1]),
        .c_s_axi_bresp_o(endpoints_bresp[0+:2]),
        .c_s_axi_bvalid_o(endpoints_bvalid[0+:1]),
        .c_s_axi_bready_i(endpoints_bready[0+:1]),
        .c_s_axi_araddr_i(endpoints_araddr[0+:32]),
        .c_s_axi_arprot_i(endpoints_arprot[0+:3]),
        .c_s_axi_arvalid_i(endpoints_arvalid[0+:1]),
        .c_s_axi_arready_o(endpoints_arready[0+:1]),
        .c_s_axi_rdata_o(endpoints_rdata[0+:32]),
        .c_s_axi_rresp_o(endpoints_rresp[0+:2]),
        .c_s_axi_rvalid_o(endpoints_rvalid[0+:1]),
        .c_s_axi_rready_i(endpoints_rready[0+:1]),
        .d_s_axi_awaddr_i(endpoints_awaddr[32+:32]),
        .d_s_axi_awprot_i(endpoints_awprot[3+:3]),
        .d_s_axi_awvalid_i(endpoints_awvalid[1+:1]),
        .d_s_axi_awready_o(endpoints_awready[1+:1]),
        .d_s_axi_wdata_i(endpoints_wdata[32+:32]),
        .d_s_axi_wstrb_i(endpoints_wstrb[4+:4]),
        .d_s_axi_wvalid_i(endpoints_wvalid[1+:1]),
        .d_s_axi_wready_o(endpoints_wready[1+:1]),
        .d_s_axi_bresp_o(endpoints_bresp[2+:2]),
        .d_s_axi_bvalid_o(endpoints_bvalid[1+:1]),
        .d_s_axi_bready_i(endpoints_bready[1+:1]),
        .d_s_axi_araddr_i(endpoints_araddr[32+:32]),
        .d_s_axi_arprot_i(endpoints_arprot[3+:3]),
        .d_s_axi_arvalid_i(endpoints_arvalid[1+:1]),
        .d_s_axi_arready_o(endpoints_arready[1+:1]),
        .d_s_axi_rdata_o(endpoints_rdata[32+:32]),
        .d_s_axi_rresp_o(endpoints_rresp[2+:2]),
        .d_s_axi_rvalid_o(endpoints_rvalid[1+:1]),
        .d_s_axi_rready_i(endpoints_rready[1+:1]),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pixel_de(pixel_de),
        .pixel_hs(pixel_hs),
        .pixel_vs(pixel_vs),
        .pixel_frame_start(pixel_frame_start),
        .out_rgb(out_rgb),
        .out_de(out_de),
        .out_hs(out_hs),
        .out_vs(out_vs),
        .irq_capture(capture_irq),
        .irq_display(display_irq),
        .faults(video_faults),
        .capture_code(capture_code),
        .display_code(display_code),
        .raw_commits(raw_commits),
        .raw_scans(raw_scans),
        .underflows(underflows),
        .raw_frame(raw_frame),
        .c_awid(video_c_awid),
        .c_awaddr(video_c_awaddr),
        .c_awlen(video_c_awlen),
        .c_awsize(video_c_awsize),
        .c_awburst(video_c_awburst),
        .c_awvalid(video_c_awvalid),
        .c_awready(video_c_awready),
        .c_wdata(video_c_wdata),
        .c_wstrb(video_c_wstrb),
        .c_wlast(video_c_wlast),
        .c_wvalid(video_c_wvalid),
        .c_wready(video_c_wready),
        .c_bid(video_c_bid),
        .c_bresp(video_c_bresp),
        .c_bvalid(video_c_bvalid),
        .c_bready(video_c_bready),
        .d_arid(video_d_arid),
        .d_araddr(video_d_araddr),
        .d_arlen(video_d_arlen),
        .d_arsize(video_d_arsize),
        .d_arburst(video_d_arburst),
        .d_arvalid(video_d_arvalid),
        .d_arready(video_d_arready),
        .d_rid(video_d_rid),
        .d_rdata(video_d_rdata),
        .d_rresp(video_d_rresp),
        .d_rlast(video_d_rlast),
        .d_rvalid(video_d_rvalid),
        .d_rready(video_d_rready),
        .load_valid(BOOT_AVATAR?(loader_sealed&&!material_load_sent):load_valid),
        .load_ready(material_load_ready),
        .load_base(BOOT_AVATAR?`TRIHA_AVATAR_BASE:load_base),
        .load_bytes(BOOT_AVATAR?`TRIHA_AVATAR_BYTES:load_bytes),
        .load_asset_id(BOOT_AVATAR?`TRIHA_AVATAR_ID:load_asset_id),
        .load_generation(BOOT_AVATAR?`TRIHA_AVATAR_GENERATION:load_generation),
        .expected_crc(BOOT_AVATAR?`TRIHA_AVATAR_CRC32:expected_crc),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_success(result_success),
        .result_code(result_code),
        .result_asset_id(result_asset_id),
        .result_generation(result_generation),
        .checked_bytes(checked_bytes),
        .crc(crc),
        .asset_ready(asset_ready),
        .pixel_material_ready(pixel_material_ready),
        .asset_id(asset_id),
        .asset_generation(asset_generation),
        .words_written(words_written),
        .raw_context_valid(raw_context_valid),
        .raw_slot(raw_slot),
        .raw_generation(raw_generation),
        .raw_x(raw_x),
        .raw_y(raw_y),
        .raw_rgb(raw_rgb),
        .raw_de(raw_de),
        .raw_hs(raw_hs),
        .raw_vs(raw_vs),
        .raw_sof(raw_sof),
        .out_x(out_x),
        .out_y(out_y),
        .out_frame(out_frame),
        .out_generation(out_generation),
        .out_seq(out_seq),
        .out_slot(out_slot),
        .out_mode(out_mode),
        .out_sof(out_sof),
        .out_box(out_box),
        .out_point(out_point),
        .out_avatar(out_avatar),
        .out_fault(out_fault),
        .pixel_pending(pixel_pending),
        .pending_mode(pending_mode),
        .pending_slot(pending_slot),
        .pending_frame(pending_frame),
        .pending_generation(pending_generation),
        .render_faults(render_faults),
        .read_code(read_code),
        .material_code(material_code),
        .pixels_code(pixels_code),
        .port_drained(port_drained),
        .raw_grants(raw_grants),
        .asset_grants(asset_grants),
        .asset_retire_valid(asset_retire_valid),
        .asset_retire_ready(asset_retire_ready),
        .asset_retire_slot(asset_retire_slot),
        .asset_retire_frame(asset_retire_frame),
        .asset_retire_generation(asset_retire_generation),
        .asset_retire_seq(asset_retire_seq),
        .asset_retire_id(asset_retire_id),
        .asset_retire_generation_id(asset_retire_generation_id),
        .owner_error(owner_error),
        .link_error(link_error),
        .raw_error(raw_error),
        .link_code(link_code),
        .raw_code(raw_code)
    );
    soc_ddr_fabric u_memory (
        .clk_i(video_clk_i),
        .rst_ni(video_reset_n),
        .healthy_i(init_done_i && !(|video_faults) && !compute_fault_sync[1]),
        .init_done_i(init_done_i),
        .s_awvalid_i({1'd0,boot_owner?boot_awvalid:video_c_awvalid,cross_awvalid}),
        .s_awready_o({unused_awready,lane_awready,cross_awready}),
        .s_awaddr_i({32'd0,boot_owner?boot_awaddr:video_c_awaddr,cross_awaddr}),
        .s_awid_i({4'd0,boot_owner?4'd0:video_c_awid,cross_awid}),
        .s_awlen_i({8'd0,boot_owner?8'd15:video_c_awlen,cross_awlen}),
        .s_awsize_i({3'd0,boot_owner?3'd4:video_c_awsize,cross_awsize}),
        .s_awburst_i({2'd0,boot_owner?2'd1:video_c_awburst,cross_awburst}),
        .s_wvalid_i({1'd0,boot_owner?boot_wvalid:video_c_wvalid,cross_wvalid}),
        .s_wready_o({unused_wready,lane_wready,cross_wready}),
        .s_wdata_i({128'd0,boot_owner?boot_wdata:video_c_wdata,cross_wdata}),
        .s_wstrb_i({16'd0,boot_owner?16'hffff:video_c_wstrb,cross_wstrb}),
        .s_wlast_i({1'd0,boot_owner?boot_wlast:video_c_wlast,cross_wlast}),
        .s_bvalid_o({unused_bvalid,lane_bvalid,cross_bvalid}),
        .s_bready_i({1'd1,boot_owner?boot_bready:video_c_bready,cross_bready}),
        .s_bid_o({unused_bid,lane_bid,cross_bid}),
        .s_bresp_o({unused_bresp,lane_bresp,cross_bresp}),
        .s_arvalid_i({video_d_arvalid,1'd0,cross_arvalid}),
        .s_arready_o({video_d_arready,unused_arready,cross_arready}),
        .s_araddr_i({video_d_araddr,32'd0,cross_araddr}),
        .s_arid_i({video_d_arid,4'd0,cross_arid}),
        .s_arlen_i({video_d_arlen,8'd0,cross_arlen}),
        .s_arsize_i({video_d_arsize,3'd0,cross_arsize}),
        .s_arburst_i({video_d_arburst,2'd0,cross_arburst}),
        .s_rvalid_o({video_d_rvalid,unused_rvalid,cross_rvalid}),
        .s_rready_i({video_d_rready,1'd1,cross_rready}),
        .s_rdata_o({video_d_rdata,unused_rdata,cross_rdata}),
        .s_rid_o({video_d_rid,unused_rid,cross_rid}),
        .s_rresp_o({video_d_rresp,unused_rresp,cross_rresp}),
        .s_rlast_o({video_d_rlast,unused_rlast,cross_rlast}),
        .idle_o(ddr_idle_o),
        .fault_o(fabric_fault),
        .fault_code_o(fabric_fault_code),
        .h_awaddr(h_awaddr),
        .h_araddr(h_araddr),
        .h_awlen(h_awlen),
        .h_arlen(h_arlen),
        .h_awid(h_awid),
        .h_arid(h_arid),
        .h_awvalid(h_awvalid),
        .h_arvalid(h_arvalid),
        .h_awready(h_awready),
        .h_arready(h_arready),
        .h_wready(h_wready),
        .h_rvalid(h_rvalid),
        .h_wdata(h_wdata),
        .h_wstrb(h_wstrb),
        .h_rdata(h_rdata),
        .h_wid(h_wid),
        .h_rid(h_rid),
        .h_wlast(h_wlast),
        .h_rlast(h_rlast)
    );
endmodule
`default_nettype wire
