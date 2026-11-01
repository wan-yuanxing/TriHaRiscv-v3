//-----------------------------------------------------------------
//                         biRISC-V CPU
//                            V0.8.1
//                     Ultra-Embedded.com
//                     Copyright 2019-2020
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------

// TriHa maintained integration derivative; see ADAPTATIONS.json.
module triha_cpu
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_BRANCH_PREDICTION = 1
    ,parameter SUPPORT_MULDIV   = 1
    ,parameter SUPPORT_SUPER    = 0
    ,parameter SUPPORT_MMU      = 0
    ,parameter REGISTER_REDIRECT = 1
    ,parameter REGISTER_TRAINING = 1
    ,parameter REGISTER_DIVIDER_INPUT = 1
    ,parameter SUPPORT_DUAL_ISSUE = 1
    ,parameter SUPPORT_LOAD_BYPASS = 1
    ,parameter SUPPORT_MUL_BYPASS = 1
    ,parameter EARLY_MUL_BYPASS = 1
    ,parameter SUPPORT_REGFILE_XILINX = 0
    ,parameter EXTRA_DECODE_STAGE = 0
    ,parameter MEM_CACHE_ADDR_MIN = 32'h80000000
    ,parameter MEM_CACHE_ADDR_MAX = 32'h8fffffff
    ,parameter NUM_BTB_ENTRIES  = 32
    ,parameter NUM_BTB_ENTRIES_W = 5
    ,parameter BTB_DIRECT_MAPPED = 0
    ,parameter NUM_BHT_ENTRIES  = 512
    ,parameter NUM_BHT_ENTRIES_W = 9
    ,parameter RAS_ENABLE       = 1
    ,parameter GSHARE_ENABLE    = 0
    ,parameter BHT_ENABLE       = 1
    ,parameter NUM_RAS_ENTRIES  = 8
    ,parameter NUM_RAS_ENTRIES_W = 3
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input  [ 31:0]  mem_d_data_rd_i
    ,input           mem_d_accept_i
    ,input           mem_d_ack_i
    ,input           mem_d_error_i
    ,input  [ 10:0]  mem_d_resp_tag_i
    ,input           mem_i_accept_i
    ,input           mem_i_valid_i
    ,input           mem_i_error_i
    ,input  [ 63:0]  mem_i_inst_i
    ,input           intr_i
    ,input  [ 31:0]  reset_vector_i
    ,input  [ 31:0]  cpu_id_i

    // Outputs
    ,output [ 31:0]  mem_d_addr_o
    ,output [ 31:0]  mem_d_data_wr_o
    ,output          mem_d_rd_o
    ,output [  3:0]  mem_d_wr_o
    ,output          mem_d_cacheable_o
    ,output [ 10:0]  mem_d_req_tag_o
    ,output          mem_d_invalidate_o
    ,output          mem_d_writeback_o
    ,output          mem_d_flush_o
    ,output          mem_i_rd_o
    ,output          mem_i_flush_o
    ,output          mem_i_invalidate_o
    ,output [ 31:0]  mem_i_pc_o
);

wire           mmu_lsu_writeback_w;
wire  [  4:0]  csr_opcode_rd_idx_w;
wire  [  4:0]  mul_opcode_rd_idx_w;
wire           fetch1_instr_csr_w;
wire           branch_d_exec1_request_w;
wire           mmu_flush_w;
wire  [ 31:0]  lsu_opcode_pc_w;
wire  [ 31:0]  branch_exec0_source_w;
wire  [  1:0]  fetch_in_priv_w;
wire  [ 31:0]  csr_opcode_rb_operand_w;
wire  [ 31:0]  writeback_mem_value_w;
wire [31:0] writeback_mem_bypass_w;
wire writeback_mem_bypass_zero_w;
wire  [ 31:0]  writeback_div_value_w;
wire           csr_opcode_valid_w;
wire           branch_csr_request_w;
wire  [ 63:0]  mmu_ifetch_inst_w;
wire           mmu_lsu_error_w;
wire  [ 31:0]  fetch0_pc_w;
wire           branch_exec0_is_call_w;
wire           mul_opcode_valid_w;
wire           branch_exec0_request_w;
wire           mmu_mxr_w;
wire  [ 31:0]  branch_exec0_pc_w;
wire  [ 31:0]  opcode0_pc_w;
wire  [ 31:0]  opcode0_ra_operand_w;
wire           opcode0_ra_zero_w;
wire           opcode1_ra_zero_w;
wire           opcode1_rb_zero_w;
wire           mmu_ifetch_valid_w;
wire           csr_opcode_invalid_w;
wire  [  5:0]  csr_writeback_exception_w;
wire           branch_exec1_is_call_w;
wire           branch_exec1_is_not_taken_w;
wire  [  1:0]  branch_d_exec0_priv_w;
wire           branch_exec1_is_taken_w;
wire  [  4:0]  opcode1_rd_idx_w;
wire  [ 31:0]  opcode0_rb_operand_w;
wire           opcode0_rb_zero_w;
wire  [ 31:0]  fetch1_instr_w;
wire  [ 31:0]  csr_writeback_exception_addr_w;
wire           fetch1_instr_invalid_w;
wire  [  3:0]  mmu_lsu_wr_w;
wire           fetch_in_fault_w;
wire           fetch0_instr_rd_valid_w;
wire           branch_request_w;
wire  [ 31:0]  csr_opcode_pc_w;
wire           mmu_lsu_ack_w;
wire           writeback_mem_valid_w;
wire  [  5:0]  csr_result_e1_exception_w;
wire           fetch0_instr_div_w;
wire           fetch0_fault_fetch_w;
wire  [ 31:0]  branch_info_pc_w;
wire           fetch1_fault_page_w;
wire  [ 31:0]  mmu_lsu_data_wr_w;
wire  [ 10:0]  mmu_lsu_resp_tag_w;
wire  [ 10:0]  mmu_lsu_req_tag_w;
wire           fetch1_instr_div_w;
wire  [ 31:0]  branch_exec1_source_w;
wire  [ 31:0]  mul_opcode_opcode_w;
wire  [ 31:0]  branch_d_exec0_pc_w;
wire  [ 31:0]  branch_pc_w;
wire  [  4:0]  mul_opcode_ra_idx_w;
wire  [  4:0]  csr_opcode_rb_idx_w;
wire           lsu_stall_w;
wire  [ 31:0]  opcode1_pc_w;
wire           branch_info_is_not_taken_w;
wire  [ 31:0]  branch_csr_pc_w;
wire  [  4:0]  opcode0_ra_idx_w;
wire           branch_info_is_taken_w;
wire  [ 31:0]  mul_opcode_pc_w;
wire  [ 31:0]  mul_opcode_rb_operand_w;
wire           branch_info_is_ret_w;
wire           branch_exec0_is_taken_w;
wire  [ 31:0]  mul_opcode_ra_operand_w;
wire           fetch1_instr_exec_w;
wire           fetch0_instr_exec_w;
wire           exec1_hold_w;
wire           exec0_opcode_valid_w;
wire  [ 31:0]  writeback_exec1_value_w;
wire           branch_info_is_jmp_w;
wire  [ 31:0]  opcode1_rb_operand_w;
wire           fetch1_instr_lsu_w;
wire           branch_exec1_request_w;
wire           lsu_opcode_invalid_w;
wire  [ 31:0]  mmu_lsu_addr_w;
wire           mul_hold_w;
wire           mmu_ifetch_accept_w;
wire           branch_exec1_is_jmp_w;
wire           mmu_ifetch_invalidate_w;
wire  [  1:0]  branch_csr_priv_w;
wire  [ 31:0]  lsu_opcode_ra_operand_w;
wire           mmu_lsu_rd_w;
wire           fetch0_instr_mul_w;
wire           fetch0_accept_w;
wire  [  1:0]  branch_priv_w;
wire           div_opcode_valid_w;
wire           fetch0_instr_lsu_w;
wire           interrupt_inhibit_w;
wire           mmu_ifetch_error_w;
wire  [ 31:0]  branch_exec1_pc_w;
wire           fetch0_instr_csr_w;
wire  [  5:0]  writeback_mem_exception_w;
wire           fetch1_instr_branch_w;
wire           fetch0_valid_w;
wire           csr_result_e1_write_w;
wire  [ 31:0]  csr_opcode_ra_operand_w;
wire  [ 31:0]  opcode0_opcode_w;
wire  [  1:0]  branch_d_exec1_priv_w;
wire           branch_exec0_is_not_taken_w;
wire           branch_exec1_is_ret_w;
wire           writeback_div_valid_w;
wire  [ 31:0]  opcode1_ra_operand_w;
wire  [  4:0]  mul_opcode_rb_idx_w;
wire  [ 31:0]  mmu_ifetch_pc_w;
wire           mmu_ifetch_rd_w;
wire           fetch0_fault_page_w;
wire           mmu_ifetch_flush_w;
wire  [ 31:0]  opcode1_opcode_w;
wire  [  4:0]  lsu_opcode_rd_idx_w;
wire  [ 31:0]  lsu_opcode_opcode_w;
wire           mmu_load_fault_w;
wire  [ 31:0]  mmu_satp_w;
wire  [ 31:0]  csr_result_e1_wdata_w;
wire  [  4:0]  opcode1_ra_idx_w;
wire           mmu_lsu_invalidate_w;
wire  [ 31:0]  writeback_exec0_value_w;
wire  [  4:0]  csr_opcode_ra_idx_w;
wire           ifence_w;
wire           exec1_opcode_valid_w;
wire           branch_exec0_is_jmp_w;
wire  [ 31:0]  fetch1_pc_w;
wire  [ 31:0]  csr_writeback_wdata_w;
wire           fetch1_accept_w;
wire           csr_writeback_write_w;
wire           take_interrupt_w;
wire  [ 31:0]  csr_result_e1_value_w;
wire  [  4:0]  opcode1_rb_idx_w;
wire           fetch0_instr_invalid_w;
wire  [ 11:0]  csr_writeback_waddr_w;
wire           fetch1_fault_fetch_w;
wire           fetch1_valid_w;
wire  [ 31:0]  fetch0_instr_w;
wire           mmu_lsu_cacheable_w;
wire           branch_d_exec0_request_w;
wire           opcode1_invalid_w;
wire           exec0_hold_w;
wire  [  4:0]  opcode0_rb_idx_w;
wire           opcode0_invalid_w;
wire           lsu_opcode_valid_w;
wire           branch_info_request_w;
wire  [  1:0]  mmu_priv_d_w;
wire  [ 31:0]  csr_opcode_opcode_w;
wire           fetch0_instr_branch_w;
wire           mul_opcode_invalid_w;
wire           branch_exec0_is_ret_w;
wire  [ 31:0]  mmu_lsu_data_rd_w;
wire  [ 31:0]  writeback_mul_value_w;
wire  [ 31:0]  writeback_mul_early_w;
wire           writeback_mul_early_valid_w;
wire           writeback_mul_early_zero_w;
wire           mmu_lsu_flush_w;
wire  [  4:0]  lsu_opcode_rb_idx_w;
wire           mmu_lsu_accept_w;
wire           fetch1_instr_rd_valid_w;
wire  [ 31:0]  lsu_opcode_rb_operand_w;
wire           mmu_sum_w;
wire  [ 31:0]  branch_info_source_w;
wire           branch_info_is_call_w;
wire  [  4:0]  opcode0_rd_idx_w;
wire  [ 31:0]  branch_d_exec1_pc_w;
wire  [  4:0]  lsu_opcode_ra_idx_w;
wire  [ 31:0]  csr_writeback_exception_pc_w;
wire           fetch1_instr_mul_w;
wire           mmu_store_fault_w;


wire [31:0] fetch0_pred_pc_w,fetch1_pred_pc_w;
wire fetch0_simple_exec_w,fetch1_simple_exec_w;
wire [8:0] fetch0_alu_decode_w,fetch1_alu_decode_w,opcode0_alu_decode_w,opcode1_alu_decode_w;
wire [2:0] fetch0_roles_w,fetch1_roles_w;

triha_frontend
#(
     .EXTRA_DECODE_STAGE(EXTRA_DECODE_STAGE)
    ,.REGISTER_REDIRECT(REGISTER_REDIRECT)
    ,.REGISTER_TRAINING(REGISTER_TRAINING)
    ,.NUM_BTB_ENTRIES(NUM_BTB_ENTRIES)
    ,.BTB_DIRECT_MAPPED(BTB_DIRECT_MAPPED)
    ,.SUPPORT_BRANCH_PREDICTION(SUPPORT_BRANCH_PREDICTION)
    ,.GSHARE_ENABLE(GSHARE_ENABLE)
    ,.NUM_RAS_ENTRIES_W(NUM_RAS_ENTRIES_W)
    ,.NUM_BHT_ENTRIES_W(NUM_BHT_ENTRIES_W)
    ,.BHT_ENABLE(BHT_ENABLE)
    ,.SUPPORT_MULDIV(SUPPORT_MULDIV)
    ,.NUM_BTB_ENTRIES_W(NUM_BTB_ENTRIES_W)
    ,.SUPPORT_MMU(SUPPORT_MMU)
    ,.NUM_BHT_ENTRIES(NUM_BHT_ENTRIES)
    ,.RAS_ENABLE(RAS_ENABLE)
    ,.NUM_RAS_ENTRIES(NUM_RAS_ENTRIES)
)
u_frontend
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.icache_accept_i(mmu_ifetch_accept_w)
    ,.icache_valid_i(mmu_ifetch_valid_w)
    ,.icache_error_i(mmu_ifetch_error_w)
    ,.icache_inst_i(mmu_ifetch_inst_w)
    ,.icache_page_fault_i(fetch_in_fault_w)
    ,.fetch0_accept_i(fetch0_accept_w)
    ,.fetch1_accept_i(fetch1_accept_w)
    ,.fetch_invalidate_i(ifence_w)
    ,.branch_request_i(branch_request_w)
    ,.branch_pc_i(branch_pc_w)
    ,.branch_priv_i(branch_priv_w)
    ,.branch_info_request_i(branch_info_request_w)
    ,.branch_info_is_taken_i(branch_info_is_taken_w)
    ,.branch_info_is_not_taken_i(branch_info_is_not_taken_w)
    ,.branch_info_source_i(branch_info_source_w)
    ,.branch_info_is_call_i(branch_info_is_call_w)
    ,.branch_info_is_ret_i(branch_info_is_ret_w)
    ,.branch_info_is_jmp_i(branch_info_is_jmp_w)
    ,.branch_info_pc_i(branch_info_pc_w)

    // Outputs
    ,.icache_rd_o(mmu_ifetch_rd_w)
    ,.icache_flush_o(mmu_ifetch_flush_w)
    ,.icache_invalidate_o(mmu_ifetch_invalidate_w)
    ,.icache_pc_o(mmu_ifetch_pc_w)
    ,.icache_priv_o(fetch_in_priv_w)
    ,.fetch0_valid_o(fetch0_valid_w)
    ,.fetch0_instr_o(fetch0_instr_w)
    ,.fetch0_alu_decode_o(fetch0_alu_decode_w)
    ,.fetch0_roles_o(fetch0_roles_w)
    ,.fetch0_pred_pc_o(fetch0_pred_pc_w)
    ,.fetch0_pc_o(fetch0_pc_w)
    ,.fetch0_fault_fetch_o(fetch0_fault_fetch_w)
    ,.fetch0_fault_page_o(fetch0_fault_page_w)
    ,.fetch0_instr_simple_exec_o(fetch0_simple_exec_w)
    ,.fetch0_instr_exec_o(fetch0_instr_exec_w)
    ,.fetch0_instr_lsu_o(fetch0_instr_lsu_w)
    ,.fetch0_instr_branch_o(fetch0_instr_branch_w)
    ,.fetch0_instr_mul_o(fetch0_instr_mul_w)
    ,.fetch0_instr_div_o(fetch0_instr_div_w)
    ,.fetch0_instr_csr_o(fetch0_instr_csr_w)
    ,.fetch0_instr_rd_valid_o(fetch0_instr_rd_valid_w)
    ,.fetch0_instr_invalid_o(fetch0_instr_invalid_w)
    ,.fetch1_valid_o(fetch1_valid_w)
    ,.fetch1_instr_o(fetch1_instr_w)
    ,.fetch1_alu_decode_o(fetch1_alu_decode_w)
    ,.fetch1_roles_o(fetch1_roles_w)
    ,.fetch1_pred_pc_o(fetch1_pred_pc_w)
    ,.fetch1_pc_o(fetch1_pc_w)
    ,.fetch1_fault_fetch_o(fetch1_fault_fetch_w)
    ,.fetch1_fault_page_o(fetch1_fault_page_w)
    ,.fetch1_instr_simple_exec_o(fetch1_simple_exec_w)
    ,.fetch1_instr_exec_o(fetch1_instr_exec_w)
    ,.fetch1_instr_lsu_o(fetch1_instr_lsu_w)
    ,.fetch1_instr_branch_o(fetch1_instr_branch_w)
    ,.fetch1_instr_mul_o(fetch1_instr_mul_w)
    ,.fetch1_instr_div_o(fetch1_instr_div_w)
    ,.fetch1_instr_csr_o(fetch1_instr_csr_w)
    ,.fetch1_instr_rd_valid_o(fetch1_instr_rd_valid_w)
    ,.fetch1_instr_invalid_o(fetch1_instr_invalid_w)
);


biriscv_mmu
#(
     .MEM_CACHE_ADDR_MAX(MEM_CACHE_ADDR_MAX)
    ,.SUPPORT_MMU(SUPPORT_MMU)
    ,.MEM_CACHE_ADDR_MIN(MEM_CACHE_ADDR_MIN)
)
u_mmu
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.priv_d_i(mmu_priv_d_w)
    ,.sum_i(mmu_sum_w)
    ,.mxr_i(mmu_mxr_w)
    ,.flush_i(mmu_flush_w)
    ,.satp_i(mmu_satp_w)
    ,.fetch_in_rd_i(mmu_ifetch_rd_w)
    ,.fetch_in_flush_i(mmu_ifetch_flush_w)
    ,.fetch_in_invalidate_i(mmu_ifetch_invalidate_w)
    ,.fetch_in_pc_i(mmu_ifetch_pc_w)
    ,.fetch_in_priv_i(fetch_in_priv_w)
    ,.fetch_out_accept_i(mem_i_accept_i)
    ,.fetch_out_valid_i(mem_i_valid_i)
    ,.fetch_out_error_i(mem_i_error_i)
    ,.fetch_out_inst_i(mem_i_inst_i)
    ,.lsu_in_addr_i(mmu_lsu_addr_w)
    ,.lsu_in_data_wr_i(mmu_lsu_data_wr_w)
    ,.lsu_in_rd_i(mmu_lsu_rd_w)
    ,.lsu_in_wr_i(mmu_lsu_wr_w)
    ,.lsu_in_cacheable_i(mmu_lsu_cacheable_w)
    ,.lsu_in_req_tag_i(mmu_lsu_req_tag_w)
    ,.lsu_in_invalidate_i(mmu_lsu_invalidate_w)
    ,.lsu_in_writeback_i(mmu_lsu_writeback_w)
    ,.lsu_in_flush_i(mmu_lsu_flush_w)
    ,.lsu_out_data_rd_i(mem_d_data_rd_i)
    ,.lsu_out_accept_i(mem_d_accept_i)
    ,.lsu_out_ack_i(mem_d_ack_i)
    ,.lsu_out_error_i(mem_d_error_i)
    ,.lsu_out_resp_tag_i(mem_d_resp_tag_i)

    // Outputs
    ,.fetch_in_accept_o(mmu_ifetch_accept_w)
    ,.fetch_in_valid_o(mmu_ifetch_valid_w)
    ,.fetch_in_error_o(mmu_ifetch_error_w)
    ,.fetch_in_inst_o(mmu_ifetch_inst_w)
    ,.fetch_out_rd_o(mem_i_rd_o)
    ,.fetch_out_flush_o(mem_i_flush_o)
    ,.fetch_out_invalidate_o(mem_i_invalidate_o)
    ,.fetch_out_pc_o(mem_i_pc_o)
    ,.fetch_in_fault_o(fetch_in_fault_w)
    ,.lsu_in_data_rd_o(mmu_lsu_data_rd_w)
    ,.lsu_in_accept_o(mmu_lsu_accept_w)
    ,.lsu_in_ack_o(mmu_lsu_ack_w)
    ,.lsu_in_error_o(mmu_lsu_error_w)
    ,.lsu_in_resp_tag_o(mmu_lsu_resp_tag_w)
    ,.lsu_out_addr_o(mem_d_addr_o)
    ,.lsu_out_data_wr_o(mem_d_data_wr_o)
    ,.lsu_out_rd_o(mem_d_rd_o)
    ,.lsu_out_wr_o(mem_d_wr_o)
    ,.lsu_out_cacheable_o(mem_d_cacheable_o)
    ,.lsu_out_req_tag_o(mem_d_req_tag_o)
    ,.lsu_out_invalidate_o(mem_d_invalidate_o)
    ,.lsu_out_writeback_o(mem_d_writeback_o)
    ,.lsu_out_flush_o(mem_d_flush_o)
    ,.lsu_in_load_fault_o(mmu_load_fault_w)
    ,.lsu_in_store_fault_o(mmu_store_fault_w)
);


triha_lsu
#(
     .MEM_CACHE_ADDR_MAX(MEM_CACHE_ADDR_MAX)
    ,.MEM_CACHE_ADDR_MIN(MEM_CACHE_ADDR_MIN)
)
u_lsu
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(lsu_opcode_valid_w)
    ,.opcode_opcode_i(lsu_opcode_opcode_w)
    ,.opcode_pc_i(lsu_opcode_pc_w)
    ,.opcode_invalid_i(lsu_opcode_invalid_w)
    ,.opcode_rd_idx_i(lsu_opcode_rd_idx_w)
    ,.opcode_ra_idx_i(lsu_opcode_ra_idx_w)
    ,.opcode_rb_idx_i(lsu_opcode_rb_idx_w)
    ,.opcode_ra_operand_i(lsu_opcode_ra_operand_w)
    ,.opcode_rb_operand_i(lsu_opcode_rb_operand_w)
    ,.mem_data_rd_i(mmu_lsu_data_rd_w)
    ,.mem_accept_i(mmu_lsu_accept_w)
    ,.mem_ack_i(mmu_lsu_ack_w)
    ,.mem_error_i(mmu_lsu_error_w)
    ,.mem_resp_tag_i(mmu_lsu_resp_tag_w)
    ,.mem_load_fault_i(mmu_load_fault_w)
    ,.mem_store_fault_i(mmu_store_fault_w)

    // Outputs
    ,.mem_addr_o(mmu_lsu_addr_w)
    ,.mem_data_wr_o(mmu_lsu_data_wr_w)
    ,.mem_rd_o(mmu_lsu_rd_w)
    ,.mem_wr_o(mmu_lsu_wr_w)
    ,.mem_cacheable_o(mmu_lsu_cacheable_w)
    ,.mem_req_tag_o(mmu_lsu_req_tag_w)
    ,.mem_invalidate_o(mmu_lsu_invalidate_w)
    ,.mem_writeback_o(mmu_lsu_writeback_w)
    ,.mem_flush_o(mmu_lsu_flush_w)
    ,.writeback_valid_o(writeback_mem_valid_w)
    ,.writeback_value_o(writeback_mem_value_w)
    ,.writeback_bypass_zero_o(writeback_mem_bypass_zero_w)
    ,.writeback_bypass_o(writeback_mem_bypass_w)
    ,.writeback_exception_o(writeback_mem_exception_w)
    ,.stall_o(lsu_stall_w)
);


triha_csr
#(
     .SUPPORT_SUPER(SUPPORT_SUPER)
    ,.SUPPORT_MULDIV(SUPPORT_MULDIV)
)
u_csr
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.intr_i(intr_i)
    ,.opcode_valid_i(csr_opcode_valid_w)
    ,.opcode_opcode_i(csr_opcode_opcode_w)
    ,.opcode_pc_i(csr_opcode_pc_w)
    ,.opcode_invalid_i(csr_opcode_invalid_w)
    ,.opcode_rd_idx_i(csr_opcode_rd_idx_w)
    ,.opcode_ra_idx_i(csr_opcode_ra_idx_w)
    ,.opcode_rb_idx_i(csr_opcode_rb_idx_w)
    ,.opcode_ra_operand_i(csr_opcode_ra_operand_w)
    ,.opcode_rb_operand_i(csr_opcode_rb_operand_w)
    ,.csr_writeback_write_i(csr_writeback_write_w)
    ,.csr_writeback_waddr_i(csr_writeback_waddr_w)
    ,.csr_writeback_wdata_i(csr_writeback_wdata_w)
    ,.csr_writeback_exception_i(csr_writeback_exception_w)
    ,.csr_writeback_exception_pc_i(csr_writeback_exception_pc_w)
    ,.csr_writeback_exception_addr_i(csr_writeback_exception_addr_w)
    ,.cpu_id_i(cpu_id_i)
    ,.reset_vector_i(reset_vector_i)
    ,.interrupt_inhibit_i(interrupt_inhibit_w)

    // Outputs
    ,.csr_result_e1_value_o(csr_result_e1_value_w)
    ,.csr_result_e1_write_o(csr_result_e1_write_w)
    ,.csr_result_e1_wdata_o(csr_result_e1_wdata_w)
    ,.csr_result_e1_exception_o(csr_result_e1_exception_w)
    ,.branch_csr_request_o(branch_csr_request_w)
    ,.branch_csr_pc_o(branch_csr_pc_w)
    ,.branch_csr_priv_o(branch_csr_priv_w)
    ,.take_interrupt_o(take_interrupt_w)
    ,.ifence_o(ifence_w)
    ,.mmu_priv_d_o(mmu_priv_d_w)
    ,.mmu_sum_o(mmu_sum_w)
    ,.mmu_mxr_o(mmu_mxr_w)
    ,.mmu_flush_o(mmu_flush_w)
    ,.mmu_satp_o(mmu_satp_w)
);


triha_multiplier
u_mul
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(mul_opcode_valid_w)
    ,.opcode_opcode_i(mul_opcode_opcode_w)
    ,.opcode_pc_i(mul_opcode_pc_w)
    ,.opcode_invalid_i(mul_opcode_invalid_w)
    ,.opcode_rd_idx_i(mul_opcode_rd_idx_w)
    ,.opcode_ra_idx_i(mul_opcode_ra_idx_w)
    ,.opcode_rb_idx_i(mul_opcode_rb_idx_w)
    ,.opcode_ra_operand_i(mul_opcode_ra_operand_w)
    ,.opcode_rb_operand_i(mul_opcode_rb_operand_w)
    ,.hold_i(mul_hold_w)

    // Outputs
    ,.writeback_value_o(writeback_mul_value_w)
    ,.early_low_value_o(writeback_mul_early_w)
    ,.early_low_zero_o(writeback_mul_early_zero_w)
    ,.early_low_valid_o(writeback_mul_early_valid_w)
);


triha_divider
#(.REGISTER_INPUT(REGISTER_DIVIDER_INPUT))
u_div
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(div_opcode_valid_w)
    ,.opcode_opcode_i(opcode0_opcode_w)
    ,.opcode_pc_i(opcode0_pc_w)
    ,.opcode_invalid_i(opcode0_invalid_w)
    ,.opcode_rd_idx_i(opcode0_rd_idx_w)
    ,.opcode_ra_idx_i(opcode0_ra_idx_w)
    ,.opcode_rb_idx_i(opcode0_rb_idx_w)
    ,.opcode_ra_operand_i(opcode0_ra_operand_w)
    ,.opcode_rb_operand_i(opcode0_rb_operand_w)

    // Outputs
    ,.writeback_valid_o(writeback_div_valid_w)
    ,.writeback_value_o(writeback_div_value_w)
);


triha_issue
#(
     .SUPPORT_REGFILE_XILINX(SUPPORT_REGFILE_XILINX)
    ,.SUPPORT_LOAD_BYPASS(SUPPORT_LOAD_BYPASS)
    ,.SUPPORT_MULDIV(SUPPORT_MULDIV)
    ,.SUPPORT_MUL_BYPASS(SUPPORT_MUL_BYPASS)
    ,.EARLY_MUL_BYPASS(EARLY_MUL_BYPASS)
    ,.SUPPORT_DUAL_ISSUE(SUPPORT_DUAL_ISSUE)
)
u_issue
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.fetch0_valid_i(fetch0_valid_w)
    ,.fetch0_instr_i(fetch0_instr_w)
    ,.fetch0_alu_decode_i(fetch0_alu_decode_w)
    ,.fetch0_roles_i(fetch0_roles_w)
    ,.fetch0_pred_pc_i(fetch0_pred_pc_w)
    ,.fetch0_pc_i(fetch0_pc_w)
    ,.fetch0_fault_fetch_i(fetch0_fault_fetch_w)
    ,.fetch0_fault_page_i(fetch0_fault_page_w)
    ,.fetch0_instr_exec_i(fetch0_instr_exec_w)
    ,.fetch0_instr_lsu_i(fetch0_instr_lsu_w)
    ,.fetch0_instr_branch_i(fetch0_instr_branch_w)
    ,.fetch0_instr_mul_i(fetch0_instr_mul_w)
    ,.fetch0_instr_div_i(fetch0_instr_div_w)
    ,.fetch0_instr_csr_i(fetch0_instr_csr_w)
    ,.fetch0_instr_rd_valid_i(fetch0_instr_rd_valid_w)
    ,.fetch0_instr_invalid_i(fetch0_instr_invalid_w)
    ,.fetch1_valid_i(fetch1_valid_w)
    ,.fetch1_instr_i(fetch1_instr_w)
    ,.fetch1_alu_decode_i(fetch1_alu_decode_w)
    ,.fetch1_roles_i(fetch1_roles_w)
    ,.fetch1_pred_pc_i(fetch1_pred_pc_w)
    ,.fetch1_pc_i(fetch1_pc_w)
    ,.fetch1_fault_fetch_i(fetch1_fault_fetch_w)
    ,.fetch1_fault_page_i(fetch1_fault_page_w)
    ,.fetch1_instr_simple_exec_i(fetch1_simple_exec_w)
    ,.fetch1_instr_exec_i(fetch1_instr_exec_w)
    ,.fetch1_instr_lsu_i(fetch1_instr_lsu_w)
    ,.fetch1_instr_branch_i(fetch1_instr_branch_w)
    ,.fetch1_instr_mul_i(fetch1_instr_mul_w)
    ,.fetch1_instr_div_i(fetch1_instr_div_w)
    ,.fetch1_instr_csr_i(fetch1_instr_csr_w)
    ,.fetch1_instr_rd_valid_i(fetch1_instr_rd_valid_w)
    ,.fetch1_instr_invalid_i(fetch1_instr_invalid_w)
    ,.branch_exec0_request_i(branch_exec0_request_w)
    ,.branch_exec0_is_taken_i(branch_exec0_is_taken_w)
    ,.branch_exec0_is_not_taken_i(branch_exec0_is_not_taken_w)
    ,.branch_exec0_source_i(branch_exec0_source_w)
    ,.branch_exec0_is_call_i(branch_exec0_is_call_w)
    ,.branch_exec0_is_ret_i(branch_exec0_is_ret_w)
    ,.branch_exec0_is_jmp_i(branch_exec0_is_jmp_w)
    ,.branch_exec0_pc_i(branch_exec0_pc_w)
    ,.branch_d_exec0_request_i(branch_d_exec0_request_w)
    ,.branch_d_exec0_pc_i(branch_d_exec0_pc_w)
    ,.branch_d_exec0_priv_i(branch_d_exec0_priv_w)
    ,.branch_exec1_request_i(branch_exec1_request_w)
    ,.branch_exec1_is_taken_i(branch_exec1_is_taken_w)
    ,.branch_exec1_is_not_taken_i(branch_exec1_is_not_taken_w)
    ,.branch_exec1_source_i(branch_exec1_source_w)
    ,.branch_exec1_is_call_i(branch_exec1_is_call_w)
    ,.branch_exec1_is_ret_i(branch_exec1_is_ret_w)
    ,.branch_exec1_is_jmp_i(branch_exec1_is_jmp_w)
    ,.branch_exec1_pc_i(branch_exec1_pc_w)
    ,.branch_d_exec1_request_i(branch_d_exec1_request_w)
    ,.branch_d_exec1_pc_i(branch_d_exec1_pc_w)
    ,.branch_d_exec1_priv_i(branch_d_exec1_priv_w)
    ,.branch_csr_request_i(branch_csr_request_w)
    ,.branch_csr_pc_i(branch_csr_pc_w)
    ,.branch_csr_priv_i(branch_csr_priv_w)
    ,.writeback_exec0_value_i(writeback_exec0_value_w)
    ,.writeback_exec1_value_i(writeback_exec1_value_w)
    ,.writeback_mem_valid_i(writeback_mem_valid_w)
    ,.writeback_mem_value_i(writeback_mem_value_w)
    ,.writeback_mem_bypass_zero_i(writeback_mem_bypass_zero_w)
    ,.writeback_mem_bypass_i(writeback_mem_bypass_w)
    ,.writeback_mem_exception_i(writeback_mem_exception_w)
    ,.writeback_mul_value_i(writeback_mul_value_w)
    ,.writeback_mul_early_i(writeback_mul_early_w)
    ,.writeback_mul_early_zero_i(writeback_mul_early_zero_w)
    ,.writeback_mul_early_valid_i(writeback_mul_early_valid_w)
    ,.writeback_div_valid_i(writeback_div_valid_w)
    ,.writeback_div_value_i(writeback_div_value_w)
    ,.csr_result_e1_value_i(csr_result_e1_value_w)
    ,.csr_result_e1_write_i(csr_result_e1_write_w)
    ,.csr_result_e1_wdata_i(csr_result_e1_wdata_w)
    ,.csr_result_e1_exception_i(csr_result_e1_exception_w)
    ,.lsu_stall_i(lsu_stall_w)
    ,.take_interrupt_i(take_interrupt_w)

    // Outputs
    ,.fetch0_accept_o(fetch0_accept_w)
    ,.fetch1_accept_o(fetch1_accept_w)
    ,.branch_request_o(branch_request_w)
    ,.branch_pc_o(branch_pc_w)
    ,.branch_priv_o(branch_priv_w)
    ,.branch_info_request_o(branch_info_request_w)
    ,.branch_info_is_taken_o(branch_info_is_taken_w)
    ,.branch_info_is_not_taken_o(branch_info_is_not_taken_w)
    ,.branch_info_source_o(branch_info_source_w)
    ,.branch_info_is_call_o(branch_info_is_call_w)
    ,.branch_info_is_ret_o(branch_info_is_ret_w)
    ,.branch_info_is_jmp_o(branch_info_is_jmp_w)
    ,.branch_info_pc_o(branch_info_pc_w)
    ,.exec0_opcode_valid_o(exec0_opcode_valid_w)
    ,.exec1_opcode_valid_o(exec1_opcode_valid_w)
    ,.lsu_opcode_valid_o(lsu_opcode_valid_w)
    ,.csr_opcode_valid_o(csr_opcode_valid_w)
    ,.mul_opcode_valid_o(mul_opcode_valid_w)
    ,.div_opcode_valid_o(div_opcode_valid_w)
    ,.opcode0_opcode_o(opcode0_opcode_w)
    ,.opcode0_alu_decode_o(opcode0_alu_decode_w)
    ,.opcode0_pc_o(opcode0_pc_w)
    ,.opcode0_invalid_o(opcode0_invalid_w)
    ,.opcode0_rd_idx_o(opcode0_rd_idx_w)
    ,.opcode0_ra_idx_o(opcode0_ra_idx_w)
    ,.opcode0_rb_idx_o(opcode0_rb_idx_w)
    ,.opcode0_ra_operand_o(opcode0_ra_operand_w)
    ,.opcode0_rb_operand_o(opcode0_rb_operand_w)
    ,.opcode0_ra_zero_o(opcode0_ra_zero_w)
    ,.opcode0_rb_zero_o(opcode0_rb_zero_w)
    ,.opcode1_ra_zero_o(opcode1_ra_zero_w)
    ,.opcode1_rb_zero_o(opcode1_rb_zero_w)
    ,.opcode1_opcode_o(opcode1_opcode_w)
    ,.opcode1_alu_decode_o(opcode1_alu_decode_w)
    ,.opcode1_pc_o(opcode1_pc_w)
    ,.opcode1_invalid_o(opcode1_invalid_w)
    ,.opcode1_rd_idx_o(opcode1_rd_idx_w)
    ,.opcode1_ra_idx_o(opcode1_ra_idx_w)
    ,.opcode1_rb_idx_o(opcode1_rb_idx_w)
    ,.opcode1_ra_operand_o(opcode1_ra_operand_w)
    ,.opcode1_rb_operand_o(opcode1_rb_operand_w)
    ,.lsu_opcode_opcode_o(lsu_opcode_opcode_w)
    ,.lsu_opcode_pc_o(lsu_opcode_pc_w)
    ,.lsu_opcode_invalid_o(lsu_opcode_invalid_w)
    ,.lsu_opcode_rd_idx_o(lsu_opcode_rd_idx_w)
    ,.lsu_opcode_ra_idx_o(lsu_opcode_ra_idx_w)
    ,.lsu_opcode_rb_idx_o(lsu_opcode_rb_idx_w)
    ,.lsu_opcode_ra_operand_o(lsu_opcode_ra_operand_w)
    ,.lsu_opcode_rb_operand_o(lsu_opcode_rb_operand_w)
    ,.mul_opcode_opcode_o(mul_opcode_opcode_w)
    ,.mul_opcode_pc_o(mul_opcode_pc_w)
    ,.mul_opcode_invalid_o(mul_opcode_invalid_w)
    ,.mul_opcode_rd_idx_o(mul_opcode_rd_idx_w)
    ,.mul_opcode_ra_idx_o(mul_opcode_ra_idx_w)
    ,.mul_opcode_rb_idx_o(mul_opcode_rb_idx_w)
    ,.mul_opcode_ra_operand_o(mul_opcode_ra_operand_w)
    ,.mul_opcode_rb_operand_o(mul_opcode_rb_operand_w)
    ,.csr_opcode_opcode_o(csr_opcode_opcode_w)
    ,.csr_opcode_pc_o(csr_opcode_pc_w)
    ,.csr_opcode_invalid_o(csr_opcode_invalid_w)
    ,.csr_opcode_rd_idx_o(csr_opcode_rd_idx_w)
    ,.csr_opcode_ra_idx_o(csr_opcode_ra_idx_w)
    ,.csr_opcode_rb_idx_o(csr_opcode_rb_idx_w)
    ,.csr_opcode_ra_operand_o(csr_opcode_ra_operand_w)
    ,.csr_opcode_rb_operand_o(csr_opcode_rb_operand_w)
    ,.csr_writeback_write_o(csr_writeback_write_w)
    ,.csr_writeback_waddr_o(csr_writeback_waddr_w)
    ,.csr_writeback_wdata_o(csr_writeback_wdata_w)
    ,.csr_writeback_exception_o(csr_writeback_exception_w)
    ,.csr_writeback_exception_pc_o(csr_writeback_exception_pc_w)
    ,.csr_writeback_exception_addr_o(csr_writeback_exception_addr_w)
    ,.exec0_hold_o(exec0_hold_w)
    ,.exec1_hold_o(exec1_hold_w)
    ,.mul_hold_o(mul_hold_w)
    ,.interrupt_inhibit_o(interrupt_inhibit_w)
);


triha_branch_exec #(.SUPPORT_ALU_PREDECODE(1))
u_exec0
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(exec0_opcode_valid_w)
    ,.opcode_opcode_i(opcode0_opcode_w)
    ,.alu_decode_i(opcode0_alu_decode_w)
    ,.opcode_pc_i(opcode0_pc_w)
    ,.opcode_invalid_i(opcode0_invalid_w)
    ,.opcode_rd_idx_i(opcode0_rd_idx_w)
    ,.opcode_ra_idx_i(opcode0_ra_idx_w)
    ,.opcode_rb_idx_i(opcode0_rb_idx_w)
    ,.opcode_ra_operand_i(opcode0_ra_operand_w)
    ,.opcode_rb_operand_i(opcode0_rb_operand_w)
    ,.opcode_ra_zero_i(opcode0_ra_zero_w)
    ,.opcode_rb_zero_i(opcode0_rb_zero_w)
    ,.hold_i(exec0_hold_w)

    // Outputs
    ,.branch_request_o(branch_exec0_request_w)
    ,.branch_is_taken_o(branch_exec0_is_taken_w)
    ,.branch_is_not_taken_o(branch_exec0_is_not_taken_w)
    ,.branch_source_o(branch_exec0_source_w)
    ,.branch_is_call_o(branch_exec0_is_call_w)
    ,.branch_is_ret_o(branch_exec0_is_ret_w)
    ,.branch_is_jmp_o(branch_exec0_is_jmp_w)
    ,.branch_pc_o(branch_exec0_pc_w)
    ,.branch_d_request_o(branch_d_exec0_request_w)
    ,.branch_d_pc_o(branch_d_exec0_pc_w)
    ,.branch_d_priv_o(branch_d_exec0_priv_w)
    ,.writeback_value_o(writeback_exec0_value_w)
);


// Single issue never accepts an instruction into execution lane 1.
// Keep the shared issue/CSR/exception control intact; only specialize EX1.
generate
if (SUPPORT_DUAL_ISSUE) begin : gen_dual_exec
triha_branch_exec #(.SUPPORT_ALU_PREDECODE(1),.SUPPORT_REGISTER_SHIFT(0))
u_exec1
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.opcode_valid_i(exec1_opcode_valid_w)
    ,.opcode_opcode_i(opcode1_opcode_w)
    ,.alu_decode_i(opcode1_alu_decode_w)
    ,.opcode_pc_i(opcode1_pc_w)
    ,.opcode_invalid_i(opcode1_invalid_w)
    ,.opcode_rd_idx_i(opcode1_rd_idx_w)
    ,.opcode_ra_idx_i(opcode1_ra_idx_w)
    ,.opcode_rb_idx_i(opcode1_rb_idx_w)
    ,.opcode_ra_operand_i(opcode1_ra_operand_w)
    ,.opcode_rb_operand_i(opcode1_rb_operand_w)
    ,.opcode_ra_zero_i(opcode1_ra_zero_w)
    ,.opcode_rb_zero_i(opcode1_rb_zero_w)
    ,.hold_i(exec1_hold_w)

    // Outputs
    ,.branch_request_o(branch_exec1_request_w)
    ,.branch_is_taken_o(branch_exec1_is_taken_w)
    ,.branch_is_not_taken_o(branch_exec1_is_not_taken_w)
    ,.branch_source_o(branch_exec1_source_w)
    ,.branch_is_call_o(branch_exec1_is_call_w)
    ,.branch_is_ret_o(branch_exec1_is_ret_w)
    ,.branch_is_jmp_o(branch_exec1_is_jmp_w)
    ,.branch_pc_o(branch_exec1_pc_w)
    ,.branch_d_request_o(branch_d_exec1_request_w)
    ,.branch_d_pc_o(branch_d_exec1_pc_w)
    ,.branch_d_priv_o(branch_d_exec1_priv_w)
    ,.writeback_value_o(writeback_exec1_value_w)
);
end else begin : gen_single_exec
    assign branch_exec1_request_w = 1'b0;
    assign branch_exec1_is_taken_w = 1'b0;
    assign branch_exec1_is_not_taken_w = 1'b0;
    assign branch_exec1_source_w = 32'b0;
    assign branch_exec1_is_call_w = 1'b0;
    assign branch_exec1_is_ret_w = 1'b0;
    assign branch_exec1_is_jmp_w = 1'b0;
    assign branch_exec1_pc_w = 32'b0;
    assign branch_d_exec1_request_w = 1'b0;
    assign branch_d_exec1_pc_w = 32'b0;
    assign branch_d_exec1_priv_w = 2'b0;
    assign writeback_exec1_value_w = 32'b0;
end
endgenerate



endmodule

// Local execution derivative for the isolated signed-comparison diagnostic.
// The original licensed vendor translation unit remains unchanged.
//-----------------------------------------------------------------
//                         biRISC-V CPU
//                            V0.8.1
//                     Ultra-Embedded.com
//                     Copyright 2019-2020
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------

module triha_branch_exec #(parameter SUPPORT_ALU_PREDECODE=0,parameter SUPPORT_REGISTER_SHIFT=1)
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           opcode_valid_i
    ,input  [ 31:0]  opcode_opcode_i
    ,input [8:0] alu_decode_i
    ,input  [ 31:0]  opcode_pc_i
    ,input           opcode_invalid_i
    ,input  [  4:0]  opcode_rd_idx_i
    ,input  [  4:0]  opcode_ra_idx_i
    ,input  [  4:0]  opcode_rb_idx_i
    ,input  [ 31:0]  opcode_ra_operand_i
    ,input  [ 31:0]  opcode_rb_operand_i
    ,input           opcode_ra_zero_i
    ,input           opcode_rb_zero_i
    ,input           hold_i

    // Outputs
    ,output          branch_request_o
    ,output          branch_is_taken_o
    ,output          branch_is_not_taken_o
    ,output [ 31:0]  branch_source_o
    ,output          branch_is_call_o
    ,output          branch_is_ret_o
    ,output          branch_is_jmp_o
    ,output [ 31:0]  branch_pc_o
    ,output          branch_d_request_o
    ,output [ 31:0]  branch_d_pc_o
    ,output [  1:0]  branch_d_priv_o
    ,output [ 31:0]  writeback_value_o
);



//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "biriscv_defs.v"

//-------------------------------------------------------------
// Opcode decode
//-------------------------------------------------------------
reg [31:0]  imm20_r;
reg [31:0]  imm12_r;
reg [31:0]  bimm_r;
reg [31:0]  jimm20_r;
reg [4:0]   shamt_r;

always @ *
begin
    imm20_r     = {opcode_opcode_i[31:12], 12'b0};
    imm12_r     = {{20{opcode_opcode_i[31]}}, opcode_opcode_i[31:20]};
    bimm_r      = {{19{opcode_opcode_i[31]}}, opcode_opcode_i[31], opcode_opcode_i[7], opcode_opcode_i[30:25], opcode_opcode_i[11:8], 1'b0};
    jimm20_r    = {{12{opcode_opcode_i[31]}}, opcode_opcode_i[19:12], opcode_opcode_i[20], opcode_opcode_i[30:25], opcode_opcode_i[24:21], 1'b0};
    shamt_r     = opcode_opcode_i[24:20];
end

//-------------------------------------------------------------
// Execute - ALU operations
//-------------------------------------------------------------
reg [3:0]  alu_func_r;
reg [31:0] alu_input_a_r;
reg [31:0] alu_input_b_r;

generate if(SUPPORT_ALU_PREDECODE)begin:g_alu_predecoded
    always @* begin
        alu_func_r=alu_decode_i[8:5];
        alu_input_a_r=0;alu_input_b_r=0;
        case(alu_decode_i[4:3])
            2'd1:alu_input_a_r=opcode_ra_operand_i;
            2'd2:alu_input_a_r=imm20_r;
            2'd3:alu_input_a_r=opcode_pc_i;
            default:;
        endcase
        case(alu_decode_i[2:0])
            3'd1:alu_input_b_r=opcode_rb_operand_i;
            3'd2:alu_input_b_r=imm12_r;
            3'd3:alu_input_b_r=imm20_r;
            3'd4:alu_input_b_r={27'b0,shamt_r};
            3'd5:alu_input_b_r=32'd4;
            default:;
        endcase
    end
end else begin:g_alu_legacy
always @ *
begin
    alu_func_r     = `ALU_NONE;
    alu_input_a_r  = 32'b0;
    alu_input_b_r  = 32'b0;

    if ((opcode_opcode_i & `INST_ADD_MASK) == `INST_ADD) // add
    begin
        alu_func_r     = `ALU_ADD;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_AND_MASK) == `INST_AND) // and
    begin
        alu_func_r     = `ALU_AND;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_OR_MASK) == `INST_OR) // or
    begin
        alu_func_r     = `ALU_OR;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_SLL_MASK) == `INST_SLL) // sll
    begin
        alu_func_r     = `ALU_SHIFTL;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_SRA_MASK) == `INST_SRA) // sra
    begin
        alu_func_r     = `ALU_SHIFTR_ARITH;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_SRL_MASK) == `INST_SRL) // srl
    begin
        alu_func_r     = `ALU_SHIFTR;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_SUB_MASK) == `INST_SUB) // sub
    begin
        alu_func_r     = `ALU_SUB;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_XOR_MASK) == `INST_XOR) // xor
    begin
        alu_func_r     = `ALU_XOR;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_SLT_MASK) == `INST_SLT) // slt
    begin
        alu_func_r     = `ALU_LESS_THAN_SIGNED;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_SLTU_MASK) == `INST_SLTU) // sltu
    begin
        alu_func_r     = `ALU_LESS_THAN;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = opcode_rb_operand_i;
    end
    else if ((opcode_opcode_i & `INST_ADDI_MASK) == `INST_ADDI) // addi
    begin
        alu_func_r     = `ALU_ADD;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = imm12_r;
    end
    else if ((opcode_opcode_i & `INST_ANDI_MASK) == `INST_ANDI) // andi
    begin
        alu_func_r     = `ALU_AND;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = imm12_r;
    end
    else if ((opcode_opcode_i & `INST_SLTI_MASK) == `INST_SLTI) // slti
    begin
        alu_func_r     = `ALU_LESS_THAN_SIGNED;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = imm12_r;
    end
    else if ((opcode_opcode_i & `INST_SLTIU_MASK) == `INST_SLTIU) // sltiu
    begin
        alu_func_r     = `ALU_LESS_THAN;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = imm12_r;
    end
    else if ((opcode_opcode_i & `INST_ORI_MASK) == `INST_ORI) // ori
    begin
        alu_func_r     = `ALU_OR;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = imm12_r;
    end
    else if ((opcode_opcode_i & `INST_XORI_MASK) == `INST_XORI) // xori
    begin
        alu_func_r     = `ALU_XOR;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = imm12_r;
    end
    else if ((opcode_opcode_i & `INST_SLLI_MASK) == `INST_SLLI) // slli
    begin
        alu_func_r     = `ALU_SHIFTL;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = {27'b0, shamt_r};
    end
    else if ((opcode_opcode_i & `INST_SRLI_MASK) == `INST_SRLI) // srli
    begin
        alu_func_r     = `ALU_SHIFTR;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = {27'b0, shamt_r};
    end
    else if ((opcode_opcode_i & `INST_SRAI_MASK) == `INST_SRAI) // srai
    begin
        alu_func_r     = `ALU_SHIFTR_ARITH;
        alu_input_a_r  = opcode_ra_operand_i;
        alu_input_b_r  = {27'b0, shamt_r};
    end
    else if ((opcode_opcode_i & `INST_LUI_MASK) == `INST_LUI) // lui
    begin
        alu_input_a_r  = imm20_r;
    end
    else if ((opcode_opcode_i & `INST_AUIPC_MASK) == `INST_AUIPC) // auipc
    begin
        alu_func_r     = `ALU_ADD;
        alu_input_a_r  = opcode_pc_i;
        alu_input_b_r  = imm20_r;
    end     
    else if (((opcode_opcode_i & `INST_JAL_MASK) == `INST_JAL) || ((opcode_opcode_i & `INST_JALR_MASK) == `INST_JALR)) // jal, jalr
    begin
        alu_func_r     = `ALU_ADD;
        alu_input_a_r  = opcode_pc_i;
        alu_input_b_r  = 32'd4;
    end
end


end endgenerate

//-------------------------------------------------------------
// ALU
//-------------------------------------------------------------
wire [31:0]  alu_p_w;
generate if(SUPPORT_REGISTER_SHIFT)begin:g_full_shift
    biriscv_alu u_alu(.alu_op_i(alu_func_r),.alu_a_i(alu_input_a_r),.alu_b_i(alu_input_b_r),.alu_p_o(alu_p_w));
end else begin:g_immediate_shift
    // Unsupported B register shifts cannot issue. Immediate shamt needs no RF.
    triha_immediate_shift_alu u_alu(.alu_op_i(alu_func_r),.alu_a_i(alu_input_a_r),
        .alu_b_i(alu_input_b_r),.shift_amount_i(opcode_opcode_i[24:20]),.alu_p_o(alu_p_w));
end endgenerate

//-------------------------------------------------------------
// Flop ALU output
//-------------------------------------------------------------
reg [31:0] result_q;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    result_q  <= 32'b0;
else if (~hold_i)
    result_q <= alu_p_w;

assign writeback_value_o  = result_q;

//-----------------------------------------------------------------
// less_than_signed: Less than operator (signed)
// Inputs: x = left operand, y = right operand
// Return: (int)x < (int)y
//-----------------------------------------------------------------
function [0:0] less_than_signed;
    input  [31:0] x;
    input  [31:0] y;
    reg [31:0] v;
begin
    v = (x - y);
    if (x[31] != y[31])
        less_than_signed = x[31];
    else
        less_than_signed = v[31];
end
endfunction



//-------------------------------------------------------------
// Execute - Branch operations
//-------------------------------------------------------------
reg        branch_r;
reg        branch_taken_r;
reg [31:0] branch_target_r;
reg        branch_call_r;
reg        branch_ret_r;
reg        branch_jmp_r;

always @ *
begin
    branch_r        = 1'b0;
    branch_taken_r  = 1'b0;
    branch_call_r   = 1'b0;
    branch_ret_r    = 1'b0;
    branch_jmp_r    = 1'b0;

    // Default branch_r target is relative to current PC
    branch_target_r = opcode_pc_i + bimm_r;

    if ((opcode_opcode_i & `INST_JAL_MASK) == `INST_JAL) // jal
    begin
        branch_r        = 1'b1;
        branch_taken_r  = 1'b1;
        branch_target_r = opcode_pc_i + jimm20_r;
        branch_call_r   = (opcode_rd_idx_i == 5'd1); // RA
        branch_jmp_r    = 1'b1;
    end
    else if ((opcode_opcode_i & `INST_JALR_MASK) == `INST_JALR) // jalr
    begin
        branch_r            = 1'b1;
        branch_taken_r      = 1'b1;
        branch_target_r     = opcode_ra_operand_i + imm12_r;
        branch_target_r[0]  = 1'b0;
        branch_ret_r        = (opcode_ra_idx_i == 5'd1 && imm12_r[11:0] == 12'b0); // RA
        branch_call_r       = ~branch_ret_r && (opcode_rd_idx_i == 5'd1); // RA
        branch_jmp_r        = ~(branch_call_r | branch_ret_r);
    end
    else if ((opcode_opcode_i & `INST_BEQ_MASK) == `INST_BEQ) // beq
    begin
        branch_r      = 1'b1;
        if (opcode_ra_idx_i == 5'b0)
            branch_taken_r = opcode_rb_zero_i;
        else if (opcode_rb_idx_i == 5'b0)
            branch_taken_r = opcode_ra_zero_i;
        else
            branch_taken_r = (opcode_ra_operand_i == opcode_rb_operand_i);
    end
    else if ((opcode_opcode_i & `INST_BNE_MASK) == `INST_BNE) // bne
    begin
        branch_r      = 1'b1;    
        if (opcode_ra_idx_i == 5'b0)
            branch_taken_r = ~opcode_rb_zero_i;
        else if (opcode_rb_idx_i == 5'b0)
            branch_taken_r = ~opcode_ra_zero_i;
        else
            branch_taken_r = (opcode_ra_operand_i != opcode_rb_operand_i);
    end
    else if ((opcode_opcode_i & `INST_BLT_MASK) == `INST_BLT) // blt
    begin
        branch_r      = 1'b1;
        branch_taken_r= less_than_signed(opcode_ra_operand_i, opcode_rb_operand_i);
    end
    else if ((opcode_opcode_i & `INST_BGE_MASK) == `INST_BGE) // bge
    begin
        branch_r      = 1'b1;    
        branch_taken_r= ~less_than_signed(opcode_ra_operand_i, opcode_rb_operand_i);
    end
    else if ((opcode_opcode_i & `INST_BLTU_MASK) == `INST_BLTU) // bltu
    begin
        branch_r      = 1'b1;    
        branch_taken_r= (opcode_ra_operand_i < opcode_rb_operand_i);
    end
    else if ((opcode_opcode_i & `INST_BGEU_MASK) == `INST_BGEU) // bgeu
    begin
        branch_r      = 1'b1;
        branch_taken_r= (opcode_ra_operand_i >= opcode_rb_operand_i);
    end
end

reg        branch_taken_q;
reg        branch_ntaken_q;
reg [31:0] pc_x_q;
reg [31:0] pc_m_q;
reg        branch_call_q;
reg        branch_ret_q;
reg        branch_jmp_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    branch_taken_q   <= 1'b0;
    branch_ntaken_q  <= 1'b0;
    pc_x_q           <= 32'b0;
    pc_m_q           <= 32'b0;
    branch_call_q    <= 1'b0;
    branch_ret_q     <= 1'b0;
    branch_jmp_q     <= 1'b0;
end
else if (opcode_valid_i)
begin
    branch_taken_q   <= branch_r && opcode_valid_i & branch_taken_r;
    branch_ntaken_q  <= branch_r && opcode_valid_i & ~branch_taken_r;
    pc_x_q           <= branch_taken_r ? branch_target_r : opcode_pc_i + 32'd4;
    branch_call_q    <= branch_r && opcode_valid_i && branch_call_r;
    branch_ret_q     <= branch_r && opcode_valid_i && branch_ret_r;
    branch_jmp_q     <= branch_r && opcode_valid_i && branch_jmp_r;
    pc_m_q           <= opcode_pc_i;
end

assign branch_request_o   = branch_taken_q | branch_ntaken_q;
assign branch_is_taken_o  = branch_taken_q;
assign branch_is_not_taken_o = branch_ntaken_q;
assign branch_source_o    = pc_m_q;
assign branch_pc_o        = pc_x_q;
assign branch_is_call_o   = branch_call_q;
assign branch_is_ret_o    = branch_ret_q;
assign branch_is_jmp_o    = branch_jmp_q;

assign branch_d_request_o = (branch_r && opcode_valid_i && branch_taken_r);
assign branch_d_pc_o      = branch_target_r;
assign branch_d_priv_o    = 2'b0; // don't care



endmodule

//-----------------------------------------------------------------
//                         biRISC-V CPU
//                            V0.8.1
//                     Ultra-Embedded.com
//                     Copyright 2019-2020
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------
// Maintained shift-amount port derivative; original vendor file is unchanged.
module triha_immediate_shift_alu
(
    // Inputs
     input  [  3:0]  alu_op_i
    ,input  [ 31:0]  alu_a_i
    ,input [4:0] shift_amount_i
    ,input  [ 31:0]  alu_b_i

    // Outputs
    ,output [ 31:0]  alu_p_o
);

//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "biriscv_defs.v"

//-----------------------------------------------------------------
// Registers
//-----------------------------------------------------------------
reg [31:0]      result_r;

reg [31:16]     shift_right_fill_r;
reg [31:0]      shift_right_1_r;
reg [31:0]      shift_right_2_r;
reg [31:0]      shift_right_4_r;
reg [31:0]      shift_right_8_r;

reg [31:0]      shift_left_1_r;
reg [31:0]      shift_left_2_r;
reg [31:0]      shift_left_4_r;
reg [31:0]      shift_left_8_r;

// Preserve the two useful arithmetic results before operation selection.
// ADS must not feed the subtraction result through a second addition carry.
wire [31:0] add_res_w /* synthesis syn_keep=1 */;
wire [31:0] sub_res_w /* synthesis syn_keep=1 */;
assign add_res_w=alu_a_i+alu_b_i;
assign sub_res_w=alu_a_i-alu_b_i;

//-----------------------------------------------------------------
// ALU
//-----------------------------------------------------------------
always @ (alu_op_i or alu_a_i or alu_b_i or sub_res_w or add_res_w or shift_amount_i)
begin
    shift_right_fill_r = 16'b0;
    shift_right_1_r = 32'b0;
    shift_right_2_r = 32'b0;
    shift_right_4_r = 32'b0;
    shift_right_8_r = 32'b0;

    shift_left_1_r = 32'b0;
    shift_left_2_r = 32'b0;
    shift_left_4_r = 32'b0;
    shift_left_8_r = 32'b0;

    case (alu_op_i)
       //----------------------------------------------
       // Shift Left
       //----------------------------------------------   
       `ALU_SHIFTL :
       begin
            if (shift_amount_i[0] == 1'b1)
                shift_left_1_r = {alu_a_i[30:0],1'b0};
            else
                shift_left_1_r = alu_a_i;

            if (shift_amount_i[1] == 1'b1)
                shift_left_2_r = {shift_left_1_r[29:0],2'b00};
            else
                shift_left_2_r = shift_left_1_r;

            if (shift_amount_i[2] == 1'b1)
                shift_left_4_r = {shift_left_2_r[27:0],4'b0000};
            else
                shift_left_4_r = shift_left_2_r;

            if (shift_amount_i[3] == 1'b1)
                shift_left_8_r = {shift_left_4_r[23:0],8'b00000000};
            else
                shift_left_8_r = shift_left_4_r;

            if (shift_amount_i[4] == 1'b1)
                result_r = {shift_left_8_r[15:0],16'b0000000000000000};
            else
                result_r = shift_left_8_r;
       end
       //----------------------------------------------
       // Shift Right
       //----------------------------------------------
       `ALU_SHIFTR, `ALU_SHIFTR_ARITH:
       begin
            // Arithmetic shift? Fill with 1's if MSB set
            if (alu_a_i[31] == 1'b1 && alu_op_i == `ALU_SHIFTR_ARITH)
                shift_right_fill_r = 16'b1111111111111111;
            else
                shift_right_fill_r = 16'b0000000000000000;

            if (shift_amount_i[0] == 1'b1)
                shift_right_1_r = {shift_right_fill_r[31], alu_a_i[31:1]};
            else
                shift_right_1_r = alu_a_i;

            if (shift_amount_i[1] == 1'b1)
                shift_right_2_r = {shift_right_fill_r[31:30], shift_right_1_r[31:2]};
            else
                shift_right_2_r = shift_right_1_r;

            if (shift_amount_i[2] == 1'b1)
                shift_right_4_r = {shift_right_fill_r[31:28], shift_right_2_r[31:4]};
            else
                shift_right_4_r = shift_right_2_r;

            if (shift_amount_i[3] == 1'b1)
                shift_right_8_r = {shift_right_fill_r[31:24], shift_right_4_r[31:8]};
            else
                shift_right_8_r = shift_right_4_r;

            if (shift_amount_i[4] == 1'b1)
                result_r = {shift_right_fill_r[31:16], shift_right_8_r[31:16]};
            else
                result_r = shift_right_8_r;
       end       
       //----------------------------------------------
       // Arithmetic
       //----------------------------------------------
       `ALU_ADD : 
       begin
            result_r      = add_res_w;
       end
       `ALU_SUB : 
       begin
            result_r      = sub_res_w;
       end
       //----------------------------------------------
       // Logical
       //----------------------------------------------       
       `ALU_AND : 
       begin
            result_r      = (alu_a_i & alu_b_i);
       end
       `ALU_OR  : 
       begin
            result_r      = (alu_a_i | alu_b_i);
       end
       `ALU_XOR : 
       begin
            result_r      = (alu_a_i ^ alu_b_i);
       end
       //----------------------------------------------
       // Comparision
       //----------------------------------------------
       `ALU_LESS_THAN : 
       begin
            result_r      = (alu_a_i < alu_b_i) ? 32'h1 : 32'h0;
       end
       `ALU_LESS_THAN_SIGNED : 
       begin
            if (alu_a_i[31] != alu_b_i[31])
                result_r  = alu_a_i[31] ? 32'h1 : 32'h0;
            else
                result_r  = sub_res_w[31] ? 32'h1 : 32'h0;            
       end       
       default  : 
       begin
            result_r      = alu_a_i;
       end
    endcase
end

assign alu_p_o    = result_r;

endmodule
