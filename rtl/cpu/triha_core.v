/*
 * @file       triha_core.v
 * @brief      TriHa 顺序 CPU 核心封装
 * @module     triha_core
 * @details
 * - 固定 RV32、通用寄存器堆，使用新版双发射核的前端预译码
 * - 单发射为默认，双发射用于同边界评估
 * - 预译码结果随指令入 FIFO，缩短 FIFO 读出到发射的组合路径
 * - 保留完整取指、数据、缓存维护和分支预测配置
 */

`timescale 1ns / 1ps

module triha_core #(
    parameter [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter integer DUAL_ISSUE = 0,
    parameter integer MINIMAL_CONTROL_CPU = 0
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        external_irq_i,

    output wire        inst_req_o,
    output wire        inst_flush_o,
    output wire        inst_invalidate_o,
    output wire [31:0] inst_addr_o,
    input  wire        inst_accept_i,
    input  wire        inst_valid_i,
    input  wire        inst_error_i,
    input  wire [63:0] inst_rdata_i,

    output wire [31:0] data_addr_o,
    output wire [31:0] data_wdata_o,
    output wire        data_re_o,
    output wire [3:0]  data_wstrb_o,
    output wire        data_cacheable_o,
    output wire [10:0] data_req_tag_o,
    output wire        data_invalidate_o,
    output wire        data_writeback_o,
    output wire        data_flush_o,
    input  wire [31:0] data_rdata_i,
    input  wire        data_accept_i,
    input  wire        data_ack_i,
    input  wire        data_error_i,
    input  wire [10:0] data_resp_tag_i
);
    triha_cpu #(
        .SUPPORT_BRANCH_PREDICTION(MINIMAL_CONTROL_CPU ? 0 : 1),
        .SUPPORT_MULDIV(1),
        .SUPPORT_SUPER(0),
        .SUPPORT_MMU(0),
        .SUPPORT_DUAL_ISSUE(DUAL_ISSUE),
        .SUPPORT_LOAD_BYPASS(MINIMAL_CONTROL_CPU ? 0 : 1),
        .SUPPORT_MUL_BYPASS(MINIMAL_CONTROL_CPU ? 0 : 1),
        .EARLY_MUL_BYPASS(MINIMAL_CONTROL_CPU ? 0 : 1),
        .SUPPORT_REGFILE_XILINX(0),
        .EXTRA_DECODE_STAGE(0),
        .NUM_BTB_ENTRIES(MINIMAL_CONTROL_CPU ? 2 : 512),
        .NUM_BTB_ENTRIES_W(MINIMAL_CONTROL_CPU ? 1 : 9),
        .BTB_DIRECT_MAPPED(MINIMAL_CONTROL_CPU ? 0 : 1),
        .NUM_BHT_ENTRIES(MINIMAL_CONTROL_CPU ? 2 : 512),
        .NUM_BHT_ENTRIES_W(MINIMAL_CONTROL_CPU ? 1 : 9),
        .BHT_ENABLE(MINIMAL_CONTROL_CPU ? 0 : 1),
        .RAS_ENABLE(MINIMAL_CONTROL_CPU ? 0 : 1),
        .NUM_RAS_ENTRIES(4),
        .NUM_RAS_ENTRIES_W(2),
        .GSHARE_ENABLE(0)
    ) u_cpu (
        .clk_i(clk_i),
        .rst_i(!rst_ni),
        .intr_i(external_irq_i),
        .reset_vector_i(RESET_VECTOR),
        .cpu_id_i(32'd0),
        .mem_i_rd_o(inst_req_o),
        .mem_i_flush_o(inst_flush_o),
        .mem_i_invalidate_o(inst_invalidate_o),
        .mem_i_pc_o(inst_addr_o),
        .mem_i_accept_i(inst_accept_i),
        .mem_i_valid_i(inst_valid_i),
        .mem_i_error_i(inst_error_i),
        .mem_i_inst_i(inst_rdata_i),
        .mem_d_addr_o(data_addr_o),
        .mem_d_data_wr_o(data_wdata_o),
        .mem_d_rd_o(data_re_o),
        .mem_d_wr_o(data_wstrb_o),
        .mem_d_cacheable_o(data_cacheable_o),
        .mem_d_req_tag_o(data_req_tag_o),
        .mem_d_invalidate_o(data_invalidate_o),
        .mem_d_writeback_o(data_writeback_o),
        .mem_d_flush_o(data_flush_o),
        .mem_d_data_rd_i(data_rdata_i),
        .mem_d_accept_i(data_accept_i),
        .mem_d_ack_i(data_ack_i),
        .mem_d_error_i(data_error_i),
        .mem_d_resp_tag_i(data_resp_tag_i)
    );
endmodule
