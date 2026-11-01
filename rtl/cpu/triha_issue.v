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

// TriHa maintained issue derivative; see ADAPTATIONS.json.
module triha_issue
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MULDIV   = 1
    ,parameter SUPPORT_DUAL_ISSUE = 1
    ,parameter SUPPORT_LOAD_BYPASS = 1
    ,parameter SUPPORT_MUL_BYPASS = 1
    ,parameter EARLY_MUL_BYPASS = 1
    ,parameter SUPPORT_REGFILE_XILINX = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           fetch0_valid_i
    ,input  [ 31:0]  fetch0_instr_i
    ,input [8:0] fetch0_alu_decode_i
    ,input [2:0] fetch0_roles_i
    ,input [31:0] fetch0_pred_pc_i
    ,input  [ 31:0]  fetch0_pc_i
    ,input           fetch0_fault_fetch_i
    ,input           fetch0_fault_page_i
    ,input           fetch0_instr_exec_i
    ,input           fetch0_instr_lsu_i
    ,input           fetch0_instr_branch_i
    ,input           fetch0_instr_mul_i
    ,input           fetch0_instr_div_i
    ,input           fetch0_instr_csr_i
    ,input           fetch0_instr_rd_valid_i
    ,input           fetch0_instr_invalid_i
    ,input           fetch1_valid_i
    ,input  [ 31:0]  fetch1_instr_i
    ,input [8:0] fetch1_alu_decode_i
    ,input [2:0] fetch1_roles_i
    ,input [31:0] fetch1_pred_pc_i
    ,input  [ 31:0]  fetch1_pc_i
    ,input           fetch1_fault_fetch_i
    ,input           fetch1_fault_page_i
    ,input fetch1_instr_simple_exec_i
    ,input           fetch1_instr_exec_i
    ,input           fetch1_instr_lsu_i
    ,input           fetch1_instr_branch_i
    ,input           fetch1_instr_mul_i
    ,input           fetch1_instr_div_i
    ,input           fetch1_instr_csr_i
    ,input           fetch1_instr_rd_valid_i
    ,input           fetch1_instr_invalid_i
    ,input           branch_exec0_request_i
    ,input           branch_exec0_is_taken_i
    ,input           branch_exec0_is_not_taken_i
    ,input  [ 31:0]  branch_exec0_source_i
    ,input           branch_exec0_is_call_i
    ,input           branch_exec0_is_ret_i
    ,input           branch_exec0_is_jmp_i
    ,input  [ 31:0]  branch_exec0_pc_i
    ,input           branch_d_exec0_request_i
    ,input  [ 31:0]  branch_d_exec0_pc_i
    ,input  [  1:0]  branch_d_exec0_priv_i
    ,input           branch_exec1_request_i
    ,input           branch_exec1_is_taken_i
    ,input           branch_exec1_is_not_taken_i
    ,input  [ 31:0]  branch_exec1_source_i
    ,input           branch_exec1_is_call_i
    ,input           branch_exec1_is_ret_i
    ,input           branch_exec1_is_jmp_i
    ,input  [ 31:0]  branch_exec1_pc_i
    ,input           branch_d_exec1_request_i
    ,input  [ 31:0]  branch_d_exec1_pc_i
    ,input  [  1:0]  branch_d_exec1_priv_i
    ,input           branch_csr_request_i
    ,input  [ 31:0]  branch_csr_pc_i
    ,input  [  1:0]  branch_csr_priv_i
    ,input  [ 31:0]  writeback_exec0_value_i
    ,input  [ 31:0]  writeback_exec1_value_i
    ,input           writeback_mem_valid_i
    ,input  [ 31:0]  writeback_mem_value_i
    ,input          writeback_mem_bypass_zero_i
    ,input [31:0]   writeback_mem_bypass_i
    ,input  [  5:0]  writeback_mem_exception_i
    ,input  [ 31:0]  writeback_mul_value_i
    ,input  [ 31:0]  writeback_mul_early_i
    ,input           writeback_mul_early_zero_i
    ,input           writeback_mul_early_valid_i
    ,input           writeback_div_valid_i
    ,input  [ 31:0]  writeback_div_value_i
    ,input  [ 31:0]  csr_result_e1_value_i
    ,input           csr_result_e1_write_i
    ,input  [ 31:0]  csr_result_e1_wdata_i
    ,input  [  5:0]  csr_result_e1_exception_i
    ,input           lsu_stall_i
    ,input           take_interrupt_i

    // Outputs
    ,output          fetch0_accept_o
    ,output          fetch1_accept_o
    ,output          branch_request_o
    ,output [ 31:0]  branch_pc_o
    ,output [  1:0]  branch_priv_o
    ,output          branch_info_request_o
    ,output          branch_info_is_taken_o
    ,output          branch_info_is_not_taken_o
    ,output [ 31:0]  branch_info_source_o
    ,output          branch_info_is_call_o
    ,output          branch_info_is_ret_o
    ,output          branch_info_is_jmp_o
    ,output [ 31:0]  branch_info_pc_o
    ,output          exec0_opcode_valid_o
    ,output          exec1_opcode_valid_o
    ,output          lsu_opcode_valid_o
    ,output          csr_opcode_valid_o
    ,output          mul_opcode_valid_o
    ,output          div_opcode_valid_o
    ,output [ 31:0]  opcode0_opcode_o
    ,output [8:0] opcode0_alu_decode_o
    ,output [ 31:0]  opcode0_pc_o
    ,output          opcode0_invalid_o
    ,output [  4:0]  opcode0_rd_idx_o
    ,output [  4:0]  opcode0_ra_idx_o
    ,output [  4:0]  opcode0_rb_idx_o
    ,output [ 31:0]  opcode0_ra_operand_o
    ,output [ 31:0]  opcode0_rb_operand_o
    ,output          opcode0_ra_zero_o
    ,output          opcode0_rb_zero_o
    ,output          opcode1_ra_zero_o
    ,output          opcode1_rb_zero_o
    ,output [ 31:0]  opcode1_opcode_o
    ,output [8:0] opcode1_alu_decode_o
    ,output [ 31:0]  opcode1_pc_o
    ,output          opcode1_invalid_o
    ,output [  4:0]  opcode1_rd_idx_o
    ,output [  4:0]  opcode1_ra_idx_o
    ,output [  4:0]  opcode1_rb_idx_o
    ,output [ 31:0]  opcode1_ra_operand_o
    ,output [ 31:0]  opcode1_rb_operand_o
    ,output [ 31:0]  lsu_opcode_opcode_o
    ,output [ 31:0]  lsu_opcode_pc_o
    ,output          lsu_opcode_invalid_o
    ,output [  4:0]  lsu_opcode_rd_idx_o
    ,output [  4:0]  lsu_opcode_ra_idx_o
    ,output [  4:0]  lsu_opcode_rb_idx_o
    ,output [ 31:0]  lsu_opcode_ra_operand_o
    ,output [ 31:0]  lsu_opcode_rb_operand_o
    ,output [ 31:0]  mul_opcode_opcode_o
    ,output [ 31:0]  mul_opcode_pc_o
    ,output          mul_opcode_invalid_o
    ,output [  4:0]  mul_opcode_rd_idx_o
    ,output [  4:0]  mul_opcode_ra_idx_o
    ,output [  4:0]  mul_opcode_rb_idx_o
    ,output [ 31:0]  mul_opcode_ra_operand_o
    ,output [ 31:0]  mul_opcode_rb_operand_o
    ,output [ 31:0]  csr_opcode_opcode_o
    ,output [ 31:0]  csr_opcode_pc_o
    ,output          csr_opcode_invalid_o
    ,output [  4:0]  csr_opcode_rd_idx_o
    ,output [  4:0]  csr_opcode_ra_idx_o
    ,output [  4:0]  csr_opcode_rb_idx_o
    ,output [ 31:0]  csr_opcode_ra_operand_o
    ,output [ 31:0]  csr_opcode_rb_operand_o
    ,output          csr_writeback_write_o
    ,output [ 11:0]  csr_writeback_waddr_o
    ,output [ 31:0]  csr_writeback_wdata_o
    ,output [  5:0]  csr_writeback_exception_o
    ,output [ 31:0]  csr_writeback_exception_pc_o
    ,output [ 31:0]  csr_writeback_exception_addr_o
    ,output          exec0_hold_o
    ,output          exec1_hold_o
    ,output          mul_hold_o
    ,output          interrupt_inhibit_o
);



`include "biriscv_defs.v"

wire enable_dual_issue_w = SUPPORT_DUAL_ISSUE;
wire enable_muldiv_w     = SUPPORT_MULDIV;
wire enable_mul_bypass_w = SUPPORT_MUL_BYPASS;

wire stall_w;
wire squash_w;
wire cancel1_e1_w;
wire recovery_w,resolved_fault_w;
wire [31:0] conditional0_e1_w,conditional1_e1_w;
wire [31:0] recovery_pc_w;
wire payload0_selected_w;
wire resolved0_taken_w,resolved1_taken_w;
wire [31:0] resolved0_next_w,resolved1_next_w;
wire resolve0_valid_w,resolve1_valid_w;
wire [31:0] predicted0_e1_w,predicted1_e1_w;

//-------------------------------------------------------------
// PC
//-------------------------------------------------------------
wire        single_issue_w;
wire        dual_issue_w;
reg  [31:0] pc_x_q;
reg   [1:0] priv_x_q;

// Finish constant increments before the late redirect selection. Keep these
// used nets so ADS does not merge redirect controls into the carry chain.
wire [31:0] pc_plus4_w /* synthesis syn_keep=1 */;
wire [31:0] pc_plus8_w;
assign pc_plus4_w = pc_x_q + 32'd4;
generate
if (SUPPORT_DUAL_ISSUE) begin: g_pc_dual
    wire [31:0] increment_w /* synthesis syn_keep=1 */;
    assign increment_w = pc_x_q + 32'd8;
    assign pc_plus8_w = increment_w;
end else begin: g_pc_single
    assign pc_plus8_w = 32'b0;
end
endgenerate

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pc_x_q <= 32'b0;
else if (branch_csr_request_i)
    pc_x_q <= branch_csr_pc_i;
else if (recovery_w)
    pc_x_q <= recovery_pc_w;
else if (dual_issue_w)
    pc_x_q <= fetch1_pred_pc_i;
else if (single_issue_w)
    pc_x_q <= payload0_selected_w ? fetch0_pred_pc_i : fetch1_pred_pc_i;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    priv_x_q <= `PRIV_MACHINE;
else if (branch_csr_request_i)
    priv_x_q <= branch_csr_priv_i;

//-------------------------------------------------------------
// Issue Select
//-------------------------------------------------------------
reg mispredicted_r;
reg slot0_valid_r;
reg slot1_valid_r;

always @ *
begin
    mispredicted_r = 1'b0;
    slot0_valid_r  = 1'b0;
    slot1_valid_r  = 1'b0;

    // Flush due to CSR branch
    if (branch_csr_request_i || squash_w || resolved_fault_w)
    begin
        slot0_valid_r  = 1'b0;
        slot1_valid_r  = 1'b0;
    end
    // Word 0 valid and expected PC (word 1 may also be valid)
    else if (fetch0_valid_i && {fetch0_pc_i[31:2], 2'b0} == {pc_x_q[31:2], 2'b0})
        slot0_valid_r  = 1'b1;
    // Neither word is the expected PC - must be a branch misprediction
    else if (fetch0_valid_i)
        mispredicted_r = 1'b1;
end

// Branch request (CSR branch - ecall, xret, or branch misprediction)
// Note: Correctly predicted branches are silent
assign branch_request_o          = branch_csr_request_i | recovery_w | mispredicted_r;
assign branch_pc_o               = branch_csr_request_i ? branch_csr_pc_i : (recovery_w ? recovery_pc_w : pc_x_q);
assign branch_priv_o             = branch_csr_request_i ? branch_csr_priv_i : priv_x_q;

//-------------------------------------------------------------
// Instruction Decoder
//-------------------------------------------------------------
// Queue outputs may cross packet boundaries. Select by actual PC match;
// pairing additionally requires contiguous PCs and preserves all sidebands.

wire payload0_match_w = fetch0_valid_i &&
    {fetch0_pc_i[31:2], 2'b0} == {pc_x_q[31:2], 2'b0};
wire payload1_match_w = fetch1_valid_i &&
    {fetch1_pc_i[31:2], 2'b0} == {pc_x_q[31:2], 2'b0};
// A valid secondary FIFO word is contiguous with the head, so bit2 differs.
// Use relative word position for speculative payload selection; retain the
// full address comparisons above as the execution-validity authority.
assign payload0_selected_w = 1'b1; // enqueue already aligns the first valid word
// synthesis translate_off
always @(posedge clk_i) if (!rst_i && fetch1_valid_i) begin
    if (fetch0_valid_i !== 1'b1 || fetch1_pc_i !== fetch0_pc_i + 32'd4)
        $fatal(1,"ISSUE_FIFO_CONTRACT_FAIL secondary_is_not_contiguous");
end
// synthesis translate_on
reg        opcode_a_valid_r;
reg        opcode_b_valid_r;
reg [1:0]  opcode_a_fault_r;
reg [1:0]  opcode_b_fault_r;
reg [31:0] opcode_a_r;
reg [31:0] opcode_b_r;
reg [31:0] opcode_a_pc_r;
reg [31:0] opcode_b_pc_r;

always @ *
begin
    opcode_a_valid_r = payload0_match_w;
    opcode_b_valid_r = payload0_match_w && fetch1_valid_i && fetch1_pc_i == fetch0_pc_i + 32'd4;
    opcode_a_r       = fetch1_instr_i;
    opcode_a_pc_r    = fetch1_pc_i;
    opcode_a_fault_r = {fetch1_fault_page_i, fetch1_fault_fetch_i};
    // Speculative B payload is independent of head-PC selection.
    // opcode_b_valid_r and existing issue gates authorize consumption.
    opcode_b_r       = fetch1_instr_i;
    opcode_b_pc_r    = fetch1_pc_i;
    opcode_b_fault_r = {fetch1_fault_page_i, fetch1_fault_fetch_i};

    // Head may pair with the next contiguous queued instruction.
    if (payload0_selected_w)
    begin
        opcode_a_r       = fetch0_instr_i;
        opcode_a_pc_r    = fetch0_pc_i;
        opcode_a_fault_r = {fetch0_fault_page_i, fetch0_fault_fetch_i};
    end
end

wire [4:0] issue_a_ra_idx_w   = opcode_a_r[19:15];
wire [4:0] issue_a_rb_idx_w   = opcode_a_r[24:20];
wire [4:0] issue_a_rd_idx_w   = opcode_a_r[11:7];
wire       issue_a_sb_alloc_w = (payload0_selected_w ? fetch0_instr_rd_valid_i : fetch1_instr_rd_valid_i);
wire       issue_a_exec_w     = (payload0_selected_w ? fetch0_instr_exec_i     : fetch1_instr_exec_i);
wire       issue_a_lsu_w      = (payload0_selected_w ? fetch0_instr_lsu_i      : fetch1_instr_lsu_i);
wire       issue_a_branch_w   = (payload0_selected_w ? fetch0_instr_branch_i   : fetch1_instr_branch_i);
wire       issue_a_mul_w      = (payload0_selected_w ? fetch0_instr_mul_i      : fetch1_instr_mul_i);
wire       issue_a_div_w      = (payload0_selected_w ? fetch0_instr_div_i      : fetch1_instr_div_i);
wire       issue_a_csr_w      = (payload0_selected_w ? fetch0_instr_csr_i      : fetch1_instr_csr_i);
wire       issue_a_invalid_w  = (payload0_selected_w ? fetch0_instr_invalid_i  : fetch1_instr_invalid_i);


wire [4:0] issue_b_ra_idx_w   = opcode_b_r[19:15];
wire [4:0] issue_b_rb_idx_w   = opcode_b_r[24:20];
wire [4:0] issue_b_rd_idx_w   = opcode_b_r[11:7];
wire       issue_b_sb_alloc_w = fetch1_instr_rd_valid_i;
wire       issue_b_exec_w     = fetch1_instr_exec_i;
wire       issue_b_lsu_w      = fetch1_instr_lsu_i;
wire       issue_b_branch_w   = fetch1_instr_branch_i;
wire       issue_b_mul_w      = fetch1_instr_mul_i;
wire       issue_b_div_w      = fetch1_instr_div_i;
wire       issue_b_csr_w      = fetch1_instr_csr_i;
wire       issue_b_invalid_w  = fetch1_instr_invalid_i;

//-------------------------------------------------------------
// Pipe0 - Status tracking
//------------------------------------------------------------- 
wire        pipe0_squash_e1_e2_w;
wire        pipe1_squash_e1_e2_w;

reg         opcode_a_issue_r;
reg         opcode_a_accept_r;
wire        pipe0_stall_raw_w;

wire        pipe0_load_e1_w;
wire        pipe0_store_e1_w;
wire        pipe0_mul_e1_w;
wire        pipe0_branch_e1_w;
wire [4:0]  pipe0_rd_e1_w;

wire [31:0] pipe0_pc_e1_w;
wire [31:0] pipe0_opcode_e1_w;
wire pipe0_mul_low_e1_w;
// Reuse E1 forwarding for the existing low-word product. The registered E2
// result still supplies architectural writeback; high products and dual issue
// retain their original hazard policy.
wire pipe0_early_mul_w = EARLY_MUL_BYPASS && SUPPORT_MUL_BYPASS &&
    pipe0_mul_e1_w && writeback_mul_early_valid_i &&
    pipe0_mul_low_e1_w;
wire [31:0] pipe0_forward_e1_w = pipe0_early_mul_w ? writeback_mul_early_i : writeback_exec0_value_i;
wire [31:0] pipe0_operand_ra_e1_w;
wire [31:0] pipe0_operand_rb_e1_w;

wire        pipe0_load_e2_w;
wire        pipe0_mul_e2_w;
wire [4:0]  pipe0_rd_e2_w;
wire [4:0]  pipe0_rd_bypass_e2_w;
wire [31:0] pipe0_result_e2_w;
wire pipe0_result_zero_e2_w;

wire        pipe0_valid_wb_w;
wire        pipe0_csr_wb_w;
wire [4:0]  pipe0_rd_wb_w;
wire [4:0]  pipe0_rd_bypass_wb_w;
wire [31:0] pipe0_result_wb_w;
wire [31:0] pipe0_pc_wb_w;
wire [31:0] pipe0_opc_wb_w;
wire [31:0] pipe0_ra_val_wb_w;
wire [31:0] pipe0_rb_val_wb_w;
wire [`EXCEPTION_W-1:0] pipe0_exception_wb_w;

wire [`EXCEPTION_W-1:0] issue_a_fault_w = opcode_a_fault_r[0] ? `EXCEPTION_FAULT_FETCH:
                                          opcode_a_fault_r[1] ? `EXCEPTION_PAGE_FAULT_INST: `EXCEPTION_W'b0;

triha_pipe_ctrl
#( 
     .SUPPORT_LOAD_BYPASS(SUPPORT_LOAD_BYPASS)
    ,.SUPPORT_MUL_BYPASS(SUPPORT_MUL_BYPASS)
)
u_pipe0_ctrl
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)    

    // Issue
    ,.issue_valid_i(opcode_a_issue_r)
    ,.issue_accept_i(opcode_a_accept_r)
    ,.cancel_e1_i(1'b0)
    ,.issue_stall_i(stall_w)
    ,.issue_lsu_i(issue_a_lsu_w)
    ,.issue_csr_i(issue_a_csr_w)
    ,.issue_div_i(issue_a_div_w)
    ,.issue_mul_i(issue_a_mul_w)
    ,.issue_branch_i(issue_a_branch_w)
    ,.issue_rd_valid_i(issue_a_sb_alloc_w)
    ,.issue_rd_i(issue_a_rd_idx_w)
    ,.issue_exception_i(issue_a_fault_w)
    ,.issue_pc_i(opcode0_pc_o)
    ,.issue_opcode_i(opcode0_opcode_o)
    ,.issue_operand_ra_i(opcode0_ra_operand_o)
    ,.issue_operand_rb_i(opcode0_rb_operand_o)
    ,.issue_pred_pc_i((dual_issue_w ? opcode0_pc_o+32'd4 : (payload0_selected_w ? fetch0_pred_pc_i : fetch1_pred_pc_i)))
    ,.resolved_next_e1_i(resolved0_next_w)
    ,.resolved_taken_e1_i(resolved0_taken_w)
    ,.conditional_pc_e1_o(conditional0_e1_w)
    ,.pred_pc_e1_o(predicted0_e1_w)
    ,.resolve_e1_o(resolve0_valid_w)
    ,.issue_branch_taken_i(1'b0)
    ,.issue_branch_target_i(32'b0)
    ,.take_interrupt_i(take_interrupt_i)

    // Execution stage 1: ALU result
    ,.alu_result_e1_i(writeback_exec0_value_i)
    ,.csr_result_value_e1_i(csr_result_e1_value_i)
    ,.csr_result_write_e1_i(csr_result_e1_write_i)
    ,.csr_result_wdata_e1_i(csr_result_e1_wdata_i)
    ,.csr_result_exception_e1_i(csr_result_e1_exception_i)

    // Execution stage 1
    ,.load_e1_o(pipe0_load_e1_w)
    ,.store_e1_o(pipe0_store_e1_w)
    ,.mul_e1_o(pipe0_mul_e1_w)
    ,.mul_low_e1_o(pipe0_mul_low_e1_w)
    ,.branch_e1_o(pipe0_branch_e1_w)
    ,.rd_e1_o(pipe0_rd_e1_w)
    ,.pc_e1_o(pipe0_pc_e1_w)
    ,.opcode_e1_o(pipe0_opcode_e1_w)
    ,.operand_ra_e1_o(pipe0_operand_ra_e1_w)
    ,.operand_rb_e1_o(pipe0_operand_rb_e1_w)

    // Execution stage 2: Other results
    ,.mem_complete_i(writeback_mem_valid_i)
    ,.mem_result_e2_i(writeback_mem_value_i)
    ,.mem_bypass_zero_e2_i(writeback_mem_bypass_zero_i)
    ,.mem_bypass_e2_i(writeback_mem_bypass_i)
    ,.mem_exception_e2_i(writeback_mem_exception_i)
    ,.mul_result_e2_i(writeback_mul_value_i)

    // Execution stage 2
    ,.load_e2_o(pipe0_load_e2_w)
    ,.mul_e2_o(pipe0_mul_e2_w)
    ,.rd_e2_o(pipe0_rd_e2_w)
    ,.rd_bypass_e2_o(pipe0_rd_bypass_e2_w)
    ,.result_zero_e2_o(pipe0_result_zero_e2_w)
    ,.result_e2_o(pipe0_result_e2_w)

    ,.stall_o(pipe0_stall_raw_w)
    ,.squash_e1_e2_o(pipe0_squash_e1_e2_w)
    ,.squash_e1_e2_i(pipe1_squash_e1_e2_w)
    ,.squash_wb_i(1'b0)

    // Out of pipe: Divide Result
    ,.div_complete_i(writeback_div_valid_i)
    ,.div_result_i(writeback_div_value_i)

    // Commit
    ,.valid_wb_o(pipe0_valid_wb_w)
    ,.csr_wb_o(pipe0_csr_wb_w)
    ,.rd_wb_o(pipe0_rd_wb_w)
    ,.rd_bypass_wb_o(pipe0_rd_bypass_wb_w)
    ,.result_wb_o(pipe0_result_wb_w)
    ,.pc_wb_o(pipe0_pc_wb_w)
    ,.opcode_wb_o(pipe0_opc_wb_w)
    ,.operand_ra_wb_o(pipe0_ra_val_wb_w)
    ,.operand_rb_wb_o(pipe0_rb_val_wb_w)
    ,.exception_wb_o(pipe0_exception_wb_w)
    ,.csr_write_wb_o(csr_writeback_write_o)
    ,.csr_waddr_wb_o(csr_writeback_waddr_o)
    ,.csr_wdata_wb_o(csr_writeback_wdata_o)   
);

assign exec0_hold_o = stall_w;
assign mul_hold_o   = stall_w;

//-------------------------------------------------------------
// Pipe1 - Status tracking
//-------------------------------------------------------------
reg         opcode_b_issue_r;
reg         opcode_b_accept_r;
reg queue_a_accept_r,queue_b_accept_r;
wire        pipe1_stall_raw_w;

wire        pipe1_load_e1_w;
wire        pipe1_store_e1_w;
wire        pipe1_mul_e1_w;
wire        pipe1_branch_e1_w;
wire [4:0]  pipe1_rd_e1_w;

wire [31:0] pipe1_pc_e1_w;
wire [31:0] pipe1_opcode_e1_w;
wire pipe1_mul_low_e1_w;
wire pipe1_early_mul_w = EARLY_MUL_BYPASS && SUPPORT_MUL_BYPASS &&
    pipe1_mul_e1_w && writeback_mul_early_valid_i &&
    pipe1_mul_low_e1_w;
wire [31:0] pipe1_forward_e1_w = pipe1_early_mul_w ? writeback_mul_early_i : writeback_exec1_value_i;
wire [31:0] pipe1_operand_ra_e1_w;
wire [31:0] pipe1_operand_rb_e1_w;

wire        pipe1_load_e2_w;
wire        pipe1_mul_e2_w;
wire [4:0]  pipe1_rd_e2_w;
wire [4:0]  pipe1_rd_bypass_e2_w;
wire [31:0] pipe1_result_e2_w;
wire pipe1_result_zero_e2_w;

wire        pipe1_valid_wb_w;
wire [4:0]  pipe1_rd_wb_w;
wire [4:0]  pipe1_rd_bypass_wb_w;
wire [31:0] pipe1_result_wb_w;
wire [31:0] pipe1_pc_wb_w;
wire [31:0] pipe1_opc_wb_w;
wire [31:0] pipe1_ra_val_wb_w;
wire [31:0] pipe1_rb_val_wb_w;
wire [`EXCEPTION_W-1:0] pipe1_exception_wb_w;

wire [`EXCEPTION_W-1:0] issue_b_fault_w = opcode_b_fault_r[0] ? `EXCEPTION_FAULT_FETCH:
                                          opcode_b_fault_r[1] ? `EXCEPTION_PAGE_FAULT_INST: `EXCEPTION_W'b0;

triha_pipe_ctrl
#( 
     .SUPPORT_LOAD_BYPASS(SUPPORT_LOAD_BYPASS)
    ,.SUPPORT_MUL_BYPASS(SUPPORT_MUL_BYPASS)
)
u_pipe1_ctrl
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    // Issue
    ,.issue_valid_i(opcode_b_issue_r)
    ,.issue_accept_i(opcode_b_accept_r)
    ,.cancel_e1_i(cancel1_e1_w)
    ,.issue_stall_i(stall_w)
    ,.issue_lsu_i(issue_b_lsu_w)
    ,.issue_csr_i(1'b0)
    ,.issue_div_i(1'b0)
    ,.issue_mul_i(issue_b_mul_w)
    ,.issue_branch_i(issue_b_branch_w)
    ,.issue_rd_valid_i(issue_b_sb_alloc_w)
    ,.issue_rd_i(issue_b_rd_idx_w)
    ,.issue_exception_i(issue_b_fault_w)
    ,.issue_pc_i(opcode1_pc_o)
    ,.issue_opcode_i(opcode1_opcode_o)
    ,.issue_operand_ra_i(opcode1_ra_operand_o)
    ,.issue_operand_rb_i(opcode1_rb_operand_o)
    ,.issue_pred_pc_i(fetch1_pred_pc_i)
    ,.resolved_next_e1_i(resolved1_next_w)
    ,.resolved_taken_e1_i(resolved1_taken_w)
    ,.conditional_pc_e1_o(conditional1_e1_w)
    ,.pred_pc_e1_o(predicted1_e1_w)
    ,.resolve_e1_o(resolve1_valid_w)
    ,.issue_branch_taken_i(1'b0)
    ,.issue_branch_target_i(32'b0)
    ,.take_interrupt_i(take_interrupt_i)

    // Execution stage 1: ALU, CSR result
    ,.alu_result_e1_i(writeback_exec1_value_i)
    ,.csr_result_value_e1_i(csr_result_e1_value_i)
    ,.csr_result_write_e1_i(csr_result_e1_write_i)
    ,.csr_result_wdata_e1_i(csr_result_e1_wdata_i)
    ,.csr_result_exception_e1_i(csr_result_e1_exception_i)

    // Execution stage 1
    ,.load_e1_o(pipe1_load_e1_w)
    ,.store_e1_o(pipe1_store_e1_w)
    ,.mul_e1_o(pipe1_mul_e1_w)
    ,.mul_low_e1_o(pipe1_mul_low_e1_w)
    ,.branch_e1_o(pipe1_branch_e1_w)
    ,.rd_e1_o(pipe1_rd_e1_w)
    ,.pc_e1_o(pipe1_pc_e1_w)
    ,.opcode_e1_o(pipe1_opcode_e1_w)
    ,.operand_ra_e1_o(pipe1_operand_ra_e1_w)
    ,.operand_rb_e1_o(pipe1_operand_rb_e1_w)

    // Execution stage 2: Other results
    ,.mem_complete_i(writeback_mem_valid_i)
    ,.mem_result_e2_i(writeback_mem_value_i)
    ,.mem_bypass_zero_e2_i(writeback_mem_bypass_zero_i)
    ,.mem_bypass_e2_i(writeback_mem_bypass_i)
    ,.mem_exception_e2_i(writeback_mem_exception_i)
    ,.mul_result_e2_i(writeback_mul_value_i)

    // Execution stage 2
    ,.load_e2_o(pipe1_load_e2_w)
    ,.mul_e2_o(pipe1_mul_e2_w)
    ,.rd_e2_o(pipe1_rd_e2_w)
    ,.rd_bypass_e2_o(pipe1_rd_bypass_e2_w)
    ,.result_zero_e2_o(pipe1_result_zero_e2_w)
    ,.result_e2_o(pipe1_result_e2_w)

    ,.stall_o(pipe1_stall_raw_w)
    ,.squash_e1_e2_o(pipe1_squash_e1_e2_w)
    ,.squash_e1_e2_i(pipe0_squash_e1_e2_w)
    ,.squash_wb_i(pipe0_squash_e1_e2_w)

    // Out of pipe: Divide Result
    ,.div_complete_i(writeback_div_valid_i)
    ,.div_result_i(writeback_div_value_i)

    // Commit
    ,.valid_wb_o(pipe1_valid_wb_w)
    ,.csr_wb_o()
    ,.rd_wb_o(pipe1_rd_wb_w)
    ,.rd_bypass_wb_o(pipe1_rd_bypass_wb_w)
    ,.result_wb_o(pipe1_result_wb_w)
    ,.pc_wb_o(pipe1_pc_wb_w)
    ,.opcode_wb_o(pipe1_opc_wb_w)
    ,.operand_ra_wb_o(pipe1_ra_val_wb_w)
    ,.operand_rb_wb_o(pipe1_rb_val_wb_w)
    ,.exception_wb_o(pipe1_exception_wb_w)
    ,.csr_write_wb_o()
    ,.csr_waddr_wb_o()
    ,.csr_wdata_wb_o()
);

assign exec1_hold_o = stall_w;

assign csr_writeback_exception_o      = pipe0_exception_wb_w | pipe1_exception_wb_w;
assign csr_writeback_exception_pc_o   = (|pipe0_exception_wb_w) ? pipe0_pc_wb_w     : pipe1_pc_wb_w;
assign csr_writeback_exception_addr_o = (|pipe0_exception_wb_w) ? pipe0_result_wb_w : pipe1_result_wb_w;

//-------------------------------------------------------------
// Branch predictor info
//-------------------------------------------------------------
// This info is used to learn future prediction, and to correct 
// BTB, BHT, GShare, RAS indexes on mispredictions.
// Resolve from existing E1 operand registers. No RF/forwarding input is
// used by this logic. An older completion is never turned into a new stall.




wire resolved0_ntaken_w,resolved1_ntaken_w;
wire resolved0_mismatch_w,resolved1_mismatch_w;
wire resolved0_request_w,resolved1_request_w;
wire resolved0_call_w,resolved1_call_w,resolved0_ret_w,resolved1_ret_w,resolved0_jmp_w,resolved1_jmp_w;
triha_e1_branch #(.EARLY_CONDITIONAL_TARGET(1)) u_branch0(.conditional_pc_i(conditional0_e1_w),.opcode_i(pipe0_opcode_e1_w),.pc_i(pipe0_pc_e1_w),
    .operand_ra_i(pipe0_operand_ra_e1_w),.operand_rb_i(pipe0_operand_rb_e1_w),
    .request_o(resolved0_request_w),.taken_o(resolved0_taken_w),.not_taken_o(resolved0_ntaken_w),
    .call_o(resolved0_call_w),.ret_o(resolved0_ret_w),.jmp_o(resolved0_jmp_w),
    .predicted_pc_i(predicted0_e1_w),.mismatch_o(resolved0_mismatch_w),
    .next_pc_o(resolved0_next_w),.source_o());
triha_e1_branch #(.EARLY_CONDITIONAL_TARGET(1)) u_branch1(.conditional_pc_i(conditional1_e1_w),.opcode_i(pipe1_opcode_e1_w),.pc_i(pipe1_pc_e1_w),
    .operand_ra_i(pipe1_operand_ra_e1_w),.operand_rb_i(pipe1_operand_rb_e1_w),
    .request_o(resolved1_request_w),.taken_o(resolved1_taken_w),.not_taken_o(resolved1_ntaken_w),
    .call_o(resolved1_call_w),.ret_o(resolved1_ret_w),.jmp_o(resolved1_jmp_w),
    .predicted_pc_i(predicted1_e1_w),.mismatch_o(resolved1_mismatch_w),
    .next_pc_o(resolved1_next_w),.source_o());
wire fault0_w=resolve0_valid_w && resolved0_taken_w && resolved0_next_w[1:0]!=0;
wire fault1_w=resolve1_valid_w && resolved1_taken_w && resolved1_next_w[1:0]!=0;
assign resolved_fault_w=(fault0_w || fault1_w) && !stall_w;
wire recover0_w=resolve0_valid_w && !fault0_w && resolved0_mismatch_w;
wire recover1_w=resolve1_valid_w && !fault1_w && resolved1_mismatch_w;
assign recovery_w=(recover0_w || recover1_w) && !stall_w && !squash_w && !branch_csr_request_i;
assign recovery_pc_w=recover0_w ? resolved0_next_w : resolved1_next_w;
// Only speculative ALU B is newly allowed. It has no external side effect.
// Kill its E1->E2 transfer when older branch A leaves sequential execution;
// current E2 memory completion/writeback remains independent.
assign cancel1_e1_w=pipe0_branch_e1_w && resolve1_valid_w && (recover0_w || fault0_w);
wire train0_w=pipe0_branch_e1_w && resolve0_valid_w && !stall_w && !squash_w;
wire train1_w=pipe1_branch_e1_w && resolve1_valid_w && !stall_w && !squash_w;
assign branch_info_request_o=recovery_w | mispredicted_r;
assign branch_info_is_taken_o=(train0_w && resolved0_taken_w) | (train1_w && resolved1_taken_w);
assign branch_info_is_not_taken_o=(train0_w && resolved0_ntaken_w) | (train1_w && resolved1_ntaken_w);
assign branch_info_is_call_o=(train0_w && resolved0_call_w) | (train1_w && resolved1_call_w);
assign branch_info_is_ret_o=(train0_w && resolved0_ret_w) | (train1_w && resolved1_ret_w);
assign branch_info_is_jmp_o=(train0_w && resolved0_jmp_w) | (train1_w && resolved1_jmp_w);
assign branch_info_source_o=train1_w && resolved1_request_w ? pipe1_pc_e1_w : pipe0_pc_e1_w;
assign branch_info_pc_o=train1_w && resolved1_request_w ? resolved1_next_w : resolved0_next_w;

//-------------------------------------------------------------
// Blocking events (division, CSR unit access)
//-------------------------------------------------------------
reg div_pending_q;
reg csr_pending_q;

// Division operations take 2 - 34 cycles and stall
// the pipeline (complete out-of-pipe) until completed.
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    div_pending_q <= 1'b0;
else if (pipe0_squash_e1_e2_w || pipe1_squash_e1_e2_w)
    div_pending_q <= 1'b0;
else if (div_opcode_valid_o && issue_a_div_w)
    div_pending_q <= 1'b1;
else if (writeback_div_valid_i)
    div_pending_q <= 1'b0;

// CSR operations are infrequent - avoid any complications of pipelining them.
// These only take a 2-3 cycles anyway and may result in a pipe flush (e.g. ecall, ebreak..).
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    csr_pending_q <= 1'b0;
else if (pipe0_squash_e1_e2_w || pipe1_squash_e1_e2_w)
    csr_pending_q <= 1'b0;
else if (csr_opcode_valid_o && issue_a_csr_w)
    csr_pending_q <= 1'b1;
else if (pipe0_csr_wb_w)
    csr_pending_q <= 1'b0;

assign squash_w = pipe0_squash_e1_e2_w || pipe1_squash_e1_e2_w;

//-------------------------------------------------------------
// Issue / scheduling logic
//-------------------------------------------------------------
// Register roles qualify hazards only, never rewrite operand indices or
// payloads. Invalid/faulting instructions preserve conservative decoding.
function [2:0] qualify_register_roles;
    input [2:0] raw_roles;
    input invalid;
    input [1:0] fault;
    begin
        qualify_register_roles=3'b111;
        if(!invalid && fault==0)qualify_register_roles=raw_roles;
    end
endfunction
reg [2:0] selected_roles_r;
always @* begin
    selected_roles_r=fetch1_roles_i;
    if(payload0_selected_w)selected_roles_r=fetch0_roles_i;
end
wire [2:0] a_roles_w /* synthesis syn_keep=1 */;
wire [2:0] b_roles_w /* synthesis syn_keep=1 */;
assign a_roles_w=qualify_register_roles(selected_roles_r,issue_a_invalid_w,opcode_a_fault_r);
assign b_roles_w=qualify_register_roles(fetch1_roles_i,issue_b_invalid_w,opcode_b_fault_r);
wire prior_lsu_unit_wait_w =
    (pipe0_load_e1_w || pipe0_store_e1_w || pipe1_load_e1_w || pipe1_store_e1_w) &&
    (issue_a_mul_w || issue_a_div_w || issue_a_csr_w);

// Normalize the original procedural allocation predicates before comparing
// binary producer tags directly. Unknown predicates still allocate nothing.
reg [3:0] pending_producer_r;
wire [19:0] pending_tags_w={pipe1_rd_e2_w,pipe0_rd_e2_w,pipe1_rd_e1_w,pipe0_rd_e1_w};
always @* begin
    pending_producer_r=4'b0;
    if(SUPPORT_LOAD_BYPASS==0)begin
        if(pipe0_load_e2_w)pending_producer_r[2]=1;
        if(pipe1_load_e2_w)pending_producer_r[3]=1;
    end
    if(SUPPORT_MUL_BYPASS==0)begin
        if(pipe0_mul_e2_w)pending_producer_r[2]=1;
        if(pipe1_mul_e2_w)pending_producer_r[3]=1;
    end
    if(pipe0_load_e1_w || (pipe0_mul_e1_w && !pipe0_early_mul_w))pending_producer_r[0]=1;
    if(pipe1_load_e1_w || (pipe1_mul_e1_w && !pipe1_early_mul_w))pending_producer_r[1]=1;
end

function pending_operand_busy;
    input [4:0] index;
    input [19:0] tags;
    input [3:0] pending;
    integer producer;
    begin
        case(index)
            5'd0:pending_operand_busy=1'b0;
            5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9, 5'd10, 5'd11, 5'd12, 5'd13, 5'd14, 5'd15, 5'd16, 5'd17, 5'd18, 5'd19, 5'd20, 5'd21, 5'd22, 5'd23, 5'd24, 5'd25, 5'd26, 5'd27, 5'd28, 5'd29, 5'd30, 5'd31:begin
                pending_operand_busy=1'b0;
                for(producer=0;producer<4;producer=producer+1)begin
                    // The old indexed write ignores an unknown producer ID.
                    case(tags[producer*5 +: 5])
                        5'd0, 5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9, 5'd10, 5'd11, 5'd12, 5'd13, 5'd14, 5'd15, 5'd16, 5'd17, 5'd18, 5'd19, 5'd20, 5'd21, 5'd22, 5'd23, 5'd24, 5'd25, 5'd26, 5'd27, 5'd28, 5'd29, 5'd30, 5'd31:
                            if(pending[producer] && tags[producer*5 +: 5]==index)
                                pending_operand_busy=1'b1;
                        default:;
                    endcase
                end
            end
            // An unknown indexed read was X even for an all-zero bitmap.
            default:pending_operand_busy=1'bx;
        endcase
    end
endfunction

// Prepare both raw-fetch dependencies before selecting the A payload.
// This scalar follows the same procedural IF as opcode_a_r: X/Z selects B.
function packet_dependency;
    input [4:0] destination;
    input [4:0] ra,rb,rd;
    input [2:0] roles;
    begin
        packet_dependency=1'b0;
        case(destination)
            5'd1,5'd2,5'd3,5'd4,5'd5,5'd6,5'd7,5'd8,5'd9,5'd10,5'd11,5'd12,5'd13,5'd14,5'd15,
            5'd16,5'd17,5'd18,5'd19,5'd20,5'd21,5'd22,5'd23,5'd24,5'd25,5'd26,5'd27,5'd28,5'd29,5'd30,5'd31:
                packet_dependency=(roles[0] && ra==destination) ||
                    (roles[1] && rb==destination) || (roles[2] && rd==destination);
            default:;
        endcase
    end
endfunction
wire lower_packet_busy_w /* synthesis syn_keep=1 */;
wire upper_packet_busy_w /* synthesis syn_keep=1 */;
assign lower_packet_busy_w=packet_dependency(fetch0_instr_i[11:7],
    issue_b_ra_idx_w,issue_b_rb_idx_w,issue_b_rd_idx_w,b_roles_w);
assign upper_packet_busy_w=packet_dependency(fetch1_instr_i[11:7],
    issue_b_ra_idx_w,issue_b_rb_idx_w,issue_b_rd_idx_w,b_roles_w);
reg selected_packet_busy_r;
always @* begin
    selected_packet_busy_r=upper_packet_busy_w;
    if(payload0_selected_w)selected_packet_busy_r=lower_packet_busy_w;
end

// Legacy bitmaps below are observer shadows; real issue permission reads tags.
reg [31:0] scoreboard_r;
reg [31:0] older_scoreboard_r;
reg same_packet_busy_r;
reg        pipe1_mux_lsu_r;
reg        pipe1_mux_mul_r;

// Check instructions can be issued in the second execution unit
// B execution capability was decoded before the queue at the same stage as
// all other unit classes; no opcode-function decode remains on dequeue.
wire issue_b_simple_exec_w=fetch1_instr_simple_exec_i;
wire pipe1_ok_w      = issue_b_simple_exec_w | issue_b_branch_w | issue_b_lsu_w | issue_b_mul_w;

// Early BEQ/BNE-to-x0 decisions avoid the full two-operand branch comparator
// in secondary issue permission. Other branches execute alone in this trial.
wire opcode0_ra_zero_w;
wire opcode0_rb_zero_w;
reg zero_branch_not_taken_r;
always @* begin
    zero_branch_not_taken_r=1'b0;
    if(opcode_a_r[19:15]==5'b0)begin
        case(opcode_a_r[14:12])
            3'b000:zero_branch_not_taken_r=~opcode0_rb_zero_w;
            3'b001:zero_branch_not_taken_r=opcode0_rb_zero_w;
            default:zero_branch_not_taken_r=1'b0;
        endcase
    end else if(opcode_a_r[24:20]==5'b0)begin
        case(opcode_a_r[14:12])
            3'b000:zero_branch_not_taken_r=~opcode0_ra_zero_w;
            3'b001:zero_branch_not_taken_r=opcode0_ra_zero_w;
            default:zero_branch_not_taken_r=1'b0;
        endcase
    end
end
wire branch_pair_w = issue_a_branch_w && opcode_a_r[6:0] == 7'h63 &&
    !issue_a_invalid_w && opcode_a_fault_r == 0 &&
    !issue_b_invalid_w && opcode_b_fault_r == 0 && zero_branch_not_taken_r &&
    (issue_b_exec_w || issue_b_lsu_w || issue_b_mul_w);

// Is this combination of instructions possible to execute concurrently.
// This excludes result dependencies which may also block secondary execution.
wire speculative_branch_alu_pair_w=issue_a_branch_w && issue_b_simple_exec_w &&
    !issue_a_invalid_w && opcode_a_fault_r==0 && !issue_b_invalid_w && opcode_b_fault_r==0;
wire dual_issue_ok_w =   enable_dual_issue_w &&  // Second pipe switched on
                         pipe1_ok_w &&           // Instruction 2 is possible on second exec unit
                        (branch_pair_w || speculative_branch_alu_pair_w || ((issue_a_exec_w | issue_a_lsu_w | issue_a_mul_w) && issue_b_simple_exec_w)   ||
                         ((issue_a_exec_w | issue_a_lsu_w | issue_a_mul_w) && issue_b_branch_w) ||
                         ((issue_a_exec_w | issue_a_mul_w) && issue_b_lsu_w)                    ||
                         ((issue_a_exec_w | issue_a_lsu_w) && issue_b_mul_w)
                         ) && ~take_interrupt_i;

always @ *
begin
    opcode_a_issue_r     = 1'b0;
    opcode_b_issue_r     = 1'b0;
    opcode_a_accept_r    = 1'b0;
    opcode_b_accept_r    = 1'b0;
    scoreboard_r         = 32'b0;
    pipe1_mux_lsu_r      = 1'b0;
    pipe1_mux_mul_r      = 1'b0;

    // Execution units with >= 2 cycle latency
    if (SUPPORT_LOAD_BYPASS == 0)
    begin
        if (pipe0_load_e2_w)
            scoreboard_r[pipe0_rd_e2_w] = 1'b1;
        if (pipe1_load_e2_w)
            scoreboard_r[pipe1_rd_e2_w] = 1'b1;
    end
    if (SUPPORT_MUL_BYPASS == 0)
    begin
        if (pipe0_mul_e2_w)
            scoreboard_r[pipe0_rd_e2_w] = 1'b1;
        if (pipe1_mul_e2_w)
            scoreboard_r[pipe1_rd_e2_w] = 1'b1;
    end

    // Execution units with >= 1 cycle latency (loads / multiply)
    if (pipe0_load_e1_w || (pipe0_mul_e1_w && !pipe0_early_mul_w))
        scoreboard_r[pipe0_rd_e1_w] = 1'b1;
    if (pipe1_load_e1_w || (pipe1_mul_e1_w && !pipe1_early_mul_w))
        scoreboard_r[pipe1_rd_e1_w] = 1'b1;

    // Older producers and same-packet hazards are computed independently of A fire.
    older_scoreboard_r = scoreboard_r;
    same_packet_busy_r = 1'b0;
    // Destination zero/unknown allocates nothing in the prepared function.
    // Allocation X/Z is skipped by this same original procedural IF.
    if(issue_a_sb_alloc_w) same_packet_busy_r=selected_packet_busy_r;

    // Do not start multiply, division or CSR operation in the cycle after a load (leaving only ALU operations and branches)
    if ((pipe0_load_e1_w || pipe0_store_e1_w || pipe1_load_e1_w || pipe1_store_e1_w ) && (issue_a_mul_w || issue_a_div_w || issue_a_csr_w))
        scoreboard_r = 32'hFFFFFFFF;

    // Stall - no issues...
    if (lsu_stall_i || stall_w || div_pending_q || csr_pending_q)
        ;
    // Primary slot (lsu, branch, alu, mul, div, csr)
    else if (opcode_a_valid_r && !prior_lsu_unit_wait_w &&
        !((a_roles_w[0] && pending_operand_busy(issue_a_ra_idx_w,pending_tags_w,pending_producer_r)) || 
          (a_roles_w[1] && pending_operand_busy(issue_a_rb_idx_w,pending_tags_w,pending_producer_r)) ||
          (a_roles_w[2] && pending_operand_busy(issue_a_rd_idx_w,pending_tags_w,pending_producer_r))))
    begin
        opcode_a_issue_r  = 1'b1;
        opcode_a_accept_r = 1'b1;

        if (opcode_a_accept_r && issue_a_sb_alloc_w && (|issue_a_rd_idx_w))
            scoreboard_r[issue_a_rd_idx_w] = 1'b1;
    end

    // Stall - no issues...
    if (lsu_stall_i || stall_w || div_pending_q || csr_pending_q)
        ;
    // Secondary Slot (lsu, branch, alu, mul)
    else if (dual_issue_ok_w && opcode_b_valid_r && opcode_a_accept_r &&
        !((b_roles_w[0] && pending_operand_busy(issue_b_ra_idx_w,pending_tags_w,pending_producer_r)) ||
          (b_roles_w[1] && pending_operand_busy(issue_b_rb_idx_w,pending_tags_w,pending_producer_r)) ||
          (b_roles_w[2] && pending_operand_busy(issue_b_rd_idx_w,pending_tags_w,pending_producer_r))) &&
        !same_packet_busy_r)
    begin
        opcode_b_issue_r  = 1'b1;
        opcode_b_accept_r = 1'b1;
        pipe1_mux_lsu_r   = issue_b_lsu_w;
        pipe1_mux_mul_r   = issue_b_mul_w;

        if (opcode_b_accept_r && issue_b_sb_alloc_w && (|issue_b_rd_idx_w))
            scoreboard_r[issue_b_rd_idx_w] = 1'b1;
    end    
    // A recovery flushes the FIFO on this same edge. Its ordinary dequeue
    // calculation need not wait for branch resolution; the flush dominates it.
    // Execution and all external side-effect strobes are still cancelled below.
    queue_a_accept_r=opcode_a_accept_r;
    queue_b_accept_r=opcode_b_accept_r;
    if(branch_csr_request_i || squash_w || resolved_fault_w)begin
        queue_a_accept_r=1'b0;
        queue_b_accept_r=1'b0;
    end
    // Schedule from stable packet/class/hazards first. Late cancellation only
    // masks the final fire/accept strobes, not the classifier or scoreboard.
    if (branch_csr_request_i || squash_w || recovery_w || resolved_fault_w)
    begin
        opcode_a_issue_r  = 1'b0;
        opcode_b_issue_r  = 1'b0;
        opcode_a_accept_r = 1'b0;
        opcode_b_accept_r = 1'b0;
        pipe1_mux_lsu_r   = 1'b0;
        pipe1_mux_mul_r   = 1'b0;
    end

end

// Prepare potential B LSU payload before branch resolution / issue permission.
// A CSR/cache-maintenance and A LSU retain A. When B is merely prepared,
// only B's real issue event may authorize memory side effects.
wire lsu_payload_b_w = issue_b_lsu_w &&
    (issue_a_exec_w || issue_a_branch_w || issue_a_mul_w);
// Invalid slots may have unknown class bits; actual issue gates all requests.
// CSR remains included for cache-maintenance operations.
assign lsu_opcode_valid_o = (((issue_a_lsu_w || issue_a_csr_w) && opcode_a_issue_r) ||
    (issue_b_lsu_w && opcode_b_issue_r)) & ~take_interrupt_i;
assign exec0_opcode_valid_o = opcode_a_issue_r;
// Shared multiplier data is prepared from static unit classes; actual issue
// and existing producer tags authorize all uses of the sampled arithmetic.
wire mul_payload_b_w = issue_b_mul_w &&
    (issue_a_exec_w || issue_a_lsu_w || issue_a_branch_w);
assign mul_opcode_valid_o = enable_muldiv_w &
    ((issue_a_mul_w && opcode_a_issue_r) || (issue_b_mul_w && opcode_b_issue_r));
assign div_opcode_valid_o   = enable_muldiv_w & (opcode_a_issue_r);
// Preserve the original IRQ-inhibit semantics even on a cancelled packet.
assign interrupt_inhibit_o  = csr_pending_q ||
    (slot0_valid_r ? fetch0_instr_csr_i : fetch1_instr_csr_i);

assign exec1_opcode_valid_o = opcode_b_issue_r;

assign dual_issue_w         = opcode_b_issue_r & opcode_b_accept_r & ~take_interrupt_i;
assign single_issue_w       = (opcode_a_issue_r & opcode_a_accept_r) & ~dual_issue_w & ~take_interrupt_i;

assign fetch0_accept_o      = ((slot0_valid_r & queue_a_accept_r) | slot1_valid_r) & ~take_interrupt_i;
assign fetch1_accept_o      = ((slot1_valid_r & queue_a_accept_r) | queue_b_accept_r) & ~take_interrupt_i;

assign stall_w              = pipe0_stall_raw_w | pipe1_stall_raw_w;

//-------------------------------------------------------------
// Register File


//------------------------------------------------------------- 
wire [31:0] issue_a_ra_value_w;
wire [31:0] issue_a_rb_value_w;
wire [31:0] issue_b_ra_value_w;
wire [31:0] issue_b_rb_value_w;
wire issue_a_ra_zero_w,issue_a_rb_zero_w,issue_b_ra_zero_w,issue_b_rb_zero_w;

// Speculative operand reads do not issue another instruction. Both fetch slots
// are registered already; keep PC[2] out of the native RAM address path.
localparam PARALLEL_OPERAND_READ = !SUPPORT_REGFILE_XILINX;
wire [4:0] rf_ra0_w = PARALLEL_OPERAND_READ ? fetch0_instr_i[19:15] : issue_a_ra_idx_w;
wire [4:0] rf_rb0_w = PARALLEL_OPERAND_READ ? fetch0_instr_i[24:20] : issue_a_rb_idx_w;
wire [31:0] raw_upper_ra_w, raw_upper_rb_w;
wire raw_upper_ra_zero_w,raw_upper_rb_zero_w;
generate
if (PARALLEL_OPERAND_READ && !SUPPORT_DUAL_ISSUE) begin: g_parallel_read
    triha_regfile #(.SUPPORT_REGFILE_XILINX(0), .SUPPORT_DUAL_ISSUE(0)) u_upper (
        .clk_i(clk_i), .rst_i(rst_i),
        .rd0_i(pipe0_rd_wb_w), .rd0_value_i(pipe0_result_wb_w),
        .rd1_i(pipe1_rd_wb_w), .rd1_value_i(pipe1_result_wb_w),
        .ra0_i(fetch1_instr_i[19:15]), .rb0_i(fetch1_instr_i[24:20]),
        .ra1_i(5'b0), .rb1_i(5'b0),
        .ra0_value_o(raw_upper_ra_w), .rb0_value_o(raw_upper_rb_w),
        .ra1_value_o(), .rb1_value_o(),
        .ra0_zero_o(raw_upper_ra_zero_w),.rb0_zero_o(raw_upper_rb_zero_w),
        .ra1_zero_o(),.rb1_zero_o()
    );
end else if (PARALLEL_OPERAND_READ) begin: g_dual_parallel_read
    // Reuse the existing B read ports; no additional storage or RF copy.
    assign raw_upper_ra_w = issue_b_ra_value_w;
    assign raw_upper_rb_w = issue_b_rb_value_w;
    assign raw_upper_ra_zero_w=issue_b_ra_zero_w;
    assign raw_upper_rb_zero_w=issue_b_rb_zero_w;
end else begin: g_no_parallel_read
    assign raw_upper_ra_w = 32'b0;
    assign raw_upper_rb_w = 32'b0;
    assign raw_upper_ra_zero_w=1'b1;
    assign raw_upper_rb_zero_w=1'b1;
end
endgenerate

// Original priority: WB0, WB1, E2-0, E2-1, E1-0, E1-1, then architectural x0.
// All dependencies are explicit function inputs for complete sensitivity.
function [31:0] forward_raw_operand;
    input [4:0] index;
    input [31:0] rf_data;
    input [29:0] tags;
    input [191:0] values;
    reg [31:0] value;
    reg [5:0] hit;
    reg [5:0] select;
    integer source;
    begin
        hit = 6'b0;
        for (source=0; source<6; source=source+1)
            if (tags[source*5 +: 5] == index)
                hit[source] = 1'b1;
        for (source=0; source<6; source=source+1)
            select[source] = hit[source] & ~(|(hit & (6'b111111 << (source+1))));
        // At most one known select bit is set. A case transfers X/Z data
        // unchanged, including when an earlier matching source contains Z.
        case (select)
            6'b000001: value = values[31:0];
            6'b000010: value = values[63:32];
            6'b000100: value = values[95:64];
            6'b001000: value = values[127:96];
            6'b010000: value = values[159:128];
            6'b100000: value = values[191:160];
            default: value = rf_data;
        endcase
        if (index == 5'b0)
            value = 32'b0;
        forward_raw_operand = value;
    end
endfunction
// Compare each possible value before the late source selection. Matches
// retain the original sequential priority and skipped unknown equality.
function forward_raw_zero;
    input [4:0] index;
    input rf_zero;
    input [29:0] tags;
    input [5:0] source_zero;
    reg value;
    integer source;
    begin
        value=rf_zero;
        for(source=0;source<6;source=source+1)
            if(tags[source*5 +: 5]==index)value=source_zero[source];
        if(index==5'b0)value=1'b1;
        forward_raw_zero=value;
    end
endfunction
wire [29:0] raw_bypass_tags_w = {pipe1_rd_e1_w,pipe0_rd_e1_w,
    pipe1_rd_bypass_e2_w,pipe0_rd_bypass_e2_w,pipe1_rd_bypass_wb_w,pipe0_rd_bypass_wb_w};
wire [191:0] raw_bypass_values_w = {pipe1_forward_e1_w,pipe0_forward_e1_w,
    pipe1_result_e2_w,pipe0_result_e2_w,pipe1_result_wb_w,pipe0_result_wb_w};
wire [31:0] raw_lower_ra_w = forward_raw_operand(fetch0_instr_i[19:15],issue_a_ra_value_w,
    raw_bypass_tags_w,raw_bypass_values_w);
wire [31:0] raw_lower_rb_w = forward_raw_operand(fetch0_instr_i[24:20],issue_a_rb_value_w,
    raw_bypass_tags_w,raw_bypass_values_w);
wire [31:0] raw_upper_forward_ra_w = forward_raw_operand(fetch1_instr_i[19:15],raw_upper_ra_w,
    raw_bypass_tags_w,raw_bypass_values_w);
wire [31:0] raw_upper_forward_rb_w = forward_raw_operand(fetch1_instr_i[24:20],raw_upper_rb_w,
    raw_bypass_tags_w,raw_bypass_values_w);


// Register file: 2W4R
triha_regfile
#(
     .SUPPORT_REGFILE_XILINX(SUPPORT_REGFILE_XILINX)
    ,.SUPPORT_DUAL_ISSUE(SUPPORT_DUAL_ISSUE)
)
u_regfile
(
    .clk_i(clk_i),
    .rst_i(rst_i),

    // Write ports
    .rd0_i(pipe0_rd_wb_w),
    .rd0_value_i(pipe0_result_wb_w),
    .rd1_i(pipe1_rd_wb_w),
    .rd1_value_i(pipe1_result_wb_w),

    // Read ports
    .ra0_i(rf_ra0_w),
    .rb0_i(rf_rb0_w),
    .ra0_value_o(issue_a_ra_value_w),
    .rb0_value_o(issue_a_rb_value_w),

    .ra1_i(issue_b_ra_idx_w),
    .rb1_i(issue_b_rb_idx_w),
    .ra1_value_o(issue_b_ra_value_w),
    .rb1_value_o(issue_b_rb_value_w),
    .ra0_zero_o(issue_a_ra_zero_w),.rb0_zero_o(issue_a_rb_zero_w),
    .ra1_zero_o(issue_b_ra_zero_w),.rb1_zero_o(issue_b_rb_zero_w)
);

// These scalar properties share the unchanged raw data sources and tags.
wire [5:0] raw_source_zero_w;
genvar zero_source;
generate for(zero_source=0;zero_source<6;zero_source=zero_source+1)begin:g_prepared_zero_source
    if(zero_source==2 || zero_source==3)begin:g_memory_zero
        assign raw_source_zero_w[zero_source]=(zero_source==2) ? pipe0_result_zero_e2_w : pipe1_result_zero_e2_w;
    end else if(zero_source==4 || zero_source==5)begin:g_early_zero
        wire select_mul_w=(zero_source==4) ? pipe0_early_mul_w : pipe1_early_mul_w;
        wire [31:0] exec_value_w=(zero_source==4) ? writeback_exec0_value_i : writeback_exec1_value_i;
        reg selected_zero_r;
        always @* begin
            case(select_mul_w)
                1'b0:selected_zero_r=(exec_value_w==32'b0);
                1'b1:selected_zero_r=writeback_mul_early_zero_i;
                default:selected_zero_r=(raw_bypass_values_w[zero_source*32 +: 32]==32'b0);
            endcase
        end
        assign raw_source_zero_w[zero_source]=selected_zero_r;
    end else begin:g_other_zero
        assign raw_source_zero_w[zero_source]=(raw_bypass_values_w[zero_source*32 +: 32]==32'b0);
    end
end endgenerate
wire lower_ra_zero_w=forward_raw_zero(fetch0_instr_i[19:15],issue_a_ra_zero_w,raw_bypass_tags_w,raw_source_zero_w);
wire lower_rb_zero_w=forward_raw_zero(fetch0_instr_i[24:20],issue_a_rb_zero_w,raw_bypass_tags_w,raw_source_zero_w);
wire upper_ra_zero_w=forward_raw_zero(fetch1_instr_i[19:15],raw_upper_ra_zero_w,raw_bypass_tags_w,raw_source_zero_w);
wire upper_rb_zero_w=forward_raw_zero(fetch1_instr_i[24:20],raw_upper_rb_zero_w,raw_bypass_tags_w,raw_source_zero_w);
reg selected_ra_zero_r;
reg selected_rb_zero_r;
always @* begin
    selected_ra_zero_r=(opcode0_ra_operand_o==32'b0);
    selected_rb_zero_r=(opcode0_rb_operand_o==32'b0);
    if(PARALLEL_OPERAND_READ)begin
        selected_ra_zero_r=upper_ra_zero_w;
        selected_rb_zero_r=upper_rb_zero_w;
        if(payload0_selected_w)begin
            selected_ra_zero_r=lower_ra_zero_w;
            selected_rb_zero_r=lower_rb_zero_w;
        end
    end
end
assign opcode0_ra_zero_w=selected_ra_zero_r;
assign opcode0_rb_zero_w=selected_rb_zero_r;

//-------------------------------------------------------------
// Issue Slot 0
//------------------------------------------------------------- 
reg [8:0] selected_alu_decode_r;
always @* begin
    selected_alu_decode_r=fetch1_alu_decode_i;
    if(payload0_selected_w)selected_alu_decode_r=fetch0_alu_decode_i;
end
assign opcode0_alu_decode_o=selected_alu_decode_r;
assign opcode1_alu_decode_o=fetch1_alu_decode_i;
assign opcode0_opcode_o = opcode_a_r;
assign opcode0_pc_o     = opcode_a_pc_r;
assign opcode0_rd_idx_o = issue_a_rd_idx_w;
assign opcode0_ra_idx_o = issue_a_ra_idx_w;
assign opcode0_rb_idx_o = issue_a_rb_idx_w;
assign opcode0_invalid_o= 1'b0; 

reg [31:0] issue_a_ra_value_r;
reg [31:0] issue_a_rb_value_r;

always @ *
begin
    // NOTE: Newest version of operand takes priority
    issue_a_ra_value_r = issue_a_ra_value_w;
    issue_a_rb_value_r = issue_a_rb_value_w;

    // Bypass - WB
    if (pipe0_rd_bypass_wb_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe0_result_wb_w;
    if (pipe0_rd_bypass_wb_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe0_result_wb_w;

    if (pipe1_rd_bypass_wb_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe1_result_wb_w;
    if (pipe1_rd_bypass_wb_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe1_result_wb_w;

    // Bypass - E2
    if (pipe0_rd_bypass_e2_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe0_result_e2_w;
    if (pipe0_rd_bypass_e2_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe0_result_e2_w;

    if (pipe1_rd_bypass_e2_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe1_result_e2_w;
    if (pipe1_rd_bypass_e2_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe1_result_e2_w;

    // Bypass - E1
    if (pipe0_rd_e1_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe0_forward_e1_w;
    if (pipe0_rd_e1_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe0_forward_e1_w;

    if (pipe1_rd_e1_w == issue_a_ra_idx_w)
        issue_a_ra_value_r = pipe1_forward_e1_w;
    if (pipe1_rd_e1_w == issue_a_rb_idx_w)
        issue_a_rb_value_r = pipe1_forward_e1_w;

    // Reg 0 source
    if (issue_a_ra_idx_w == 5'b0)
        issue_a_ra_value_r = 32'b0;
    if (issue_a_rb_idx_w == 5'b0)
        issue_a_rb_value_r = 32'b0;
    if (PARALLEL_OPERAND_READ) begin
        issue_a_ra_value_r = raw_upper_forward_ra_w;
        issue_a_rb_value_r = raw_upper_forward_rb_w;
        if (payload0_selected_w) begin
            issue_a_ra_value_r = raw_lower_ra_w;
            issue_a_rb_value_r = raw_lower_rb_w;
        end
    end
end

assign opcode0_ra_operand_o = issue_a_ra_value_r;
assign opcode0_rb_operand_o = issue_a_rb_value_r;
assign opcode0_ra_zero_o    = opcode0_ra_zero_w;
assign opcode0_rb_zero_o    = opcode0_rb_zero_w;
assign opcode1_ra_zero_o = PARALLEL_OPERAND_READ ? upper_ra_zero_w : (opcode1_ra_operand_o == 32'b0);
assign opcode1_rb_zero_o = PARALLEL_OPERAND_READ ? upper_rb_zero_w : (opcode1_rb_operand_o == 32'b0);

//-------------------------------------------------------------
// Issue Slot 1
//------------------------------------------------------------- 
assign opcode1_opcode_o = opcode_b_r;
assign opcode1_pc_o     = opcode_b_pc_r;
assign opcode1_rd_idx_o = issue_b_rd_idx_w;
assign opcode1_ra_idx_o = issue_b_ra_idx_w;
assign opcode1_rb_idx_o = issue_b_rb_idx_w;
assign opcode1_invalid_o= 1'b0;

reg [31:0] issue_b_ra_value_r;
reg [31:0] issue_b_rb_value_r;

always @ *
begin
    // NOTE: Newest version of operand takes priority
    issue_b_ra_value_r = issue_b_ra_value_w;
    issue_b_rb_value_r = issue_b_rb_value_w;

    // Bypass - WB
    if (pipe0_rd_bypass_wb_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe0_result_wb_w;
    if (pipe0_rd_bypass_wb_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe0_result_wb_w;

    if (pipe1_rd_bypass_wb_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe1_result_wb_w;
    if (pipe1_rd_bypass_wb_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe1_result_wb_w;

    // Bypass - E2
    if (pipe0_rd_bypass_e2_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe0_result_e2_w;
    if (pipe0_rd_bypass_e2_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe0_result_e2_w;

    if (pipe1_rd_bypass_e2_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe1_result_e2_w;
    if (pipe1_rd_bypass_e2_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe1_result_e2_w;

    // Bypass - E1
    if (pipe0_rd_e1_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe0_forward_e1_w;
    if (pipe0_rd_e1_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe0_forward_e1_w;

    if (pipe1_rd_e1_w == issue_b_ra_idx_w)
        issue_b_ra_value_r = pipe1_forward_e1_w;
    if (pipe1_rd_e1_w == issue_b_rb_idx_w)
        issue_b_rb_value_r = pipe1_forward_e1_w;

    // Reg 0 source
    if (issue_b_ra_idx_w == 5'b0)
        issue_b_ra_value_r = 32'b0;
    if (issue_b_rb_idx_w == 5'b0)
        issue_b_rb_value_r = 32'b0;
end

assign opcode1_ra_operand_o = issue_b_ra_value_r;
assign opcode1_rb_operand_o = issue_b_rb_value_r;

// synthesis translate_off
// When an instruction can actually issue, speculative data tags must equal
// the original control/commit tags. No control or write-port uses bypass tags.
always @(posedge clk_i) begin
    if (!rst_i && (opcode_a_issue_r || opcode_b_issue_r)) begin
        if ({pipe0_rd_e2_w,pipe0_rd_wb_w,pipe1_rd_e2_w,pipe1_rd_wb_w} !==
            {pipe0_rd_bypass_e2_w,pipe0_rd_bypass_wb_w,pipe1_rd_bypass_e2_w,pipe1_rd_bypass_wb_w})
            $fatal(1,"BYPASS_TAG_FAIL actual_issue_tag_mismatch");
    end
end
// synthesis translate_on


//-------------------------------------------------------------
// Load store unit
//-------------------------------------------------------------
assign lsu_opcode_opcode_o      = lsu_payload_b_w ? opcode1_opcode_o     : opcode0_opcode_o;
assign lsu_opcode_pc_o          = lsu_payload_b_w ? opcode1_pc_o         : opcode0_pc_o;
assign lsu_opcode_rd_idx_o      = lsu_payload_b_w ? opcode1_rd_idx_o     : opcode0_rd_idx_o;
assign lsu_opcode_ra_idx_o      = lsu_payload_b_w ? opcode1_ra_idx_o     : opcode0_ra_idx_o;
assign lsu_opcode_rb_idx_o      = lsu_payload_b_w ? opcode1_rb_idx_o     : opcode0_rb_idx_o;
assign lsu_opcode_ra_operand_o  = lsu_payload_b_w ? opcode1_ra_operand_o : opcode0_ra_operand_o;
assign lsu_opcode_rb_operand_o  = lsu_payload_b_w ? opcode1_rb_operand_o : opcode0_rb_operand_o;
assign lsu_opcode_invalid_o     = 1'b0;

//-------------------------------------------------------------
// Multiply
//-------------------------------------------------------------
assign mul_opcode_opcode_o      = mul_payload_b_w ? opcode1_opcode_o     : opcode0_opcode_o;
assign mul_opcode_pc_o          = mul_payload_b_w ? opcode1_pc_o         : opcode0_pc_o;
assign mul_opcode_rd_idx_o      = mul_payload_b_w ? opcode1_rd_idx_o     : opcode0_rd_idx_o;
assign mul_opcode_ra_idx_o      = mul_payload_b_w ? opcode1_ra_idx_o     : opcode0_ra_idx_o;
assign mul_opcode_rb_idx_o      = mul_payload_b_w ? opcode1_rb_idx_o     : opcode0_rb_idx_o;
assign mul_opcode_ra_operand_o  = mul_payload_b_w ? opcode1_ra_operand_o : opcode0_ra_operand_o;
assign mul_opcode_rb_operand_o  = mul_payload_b_w ? opcode1_rb_operand_o : opcode0_rb_operand_o;
assign mul_opcode_invalid_o     = 1'b0;

//-------------------------------------------------------------
// CSR unit
//-------------------------------------------------------------
assign csr_opcode_valid_o       = opcode_a_issue_r & ~take_interrupt_i;
assign csr_opcode_opcode_o      = opcode0_opcode_o;
assign csr_opcode_pc_o          = opcode0_pc_o;
assign csr_opcode_rd_idx_o      = opcode0_rd_idx_o;
assign csr_opcode_ra_idx_o      = opcode0_ra_idx_o;
assign csr_opcode_rb_idx_o      = opcode0_rb_idx_o;
assign csr_opcode_ra_operand_o  = opcode0_ra_operand_o;
assign csr_opcode_rb_operand_o  = opcode0_rb_operand_o;
assign csr_opcode_invalid_o     = issue_a_invalid_w;

//-------------------------------------------------------------
// Checker Interface
//-------------------------------------------------------------
`ifdef verilator
biriscv_trace_sim
u_pipe0_dec0_verif
(
     .valid_i(pipe0_valid_wb_w)
    ,.pc_i(pipe0_pc_wb_w)
    ,.opcode_i(pipe0_opc_wb_w)
);

wire [4:0] v_pipe0_rs1_w = pipe0_opc_wb_w[19:15];
wire [4:0] v_pipe0_rs2_w = pipe0_opc_wb_w[24:20];

function [0:0] complete_valid0; /*verilator public*/
begin
    complete_valid0 = pipe0_valid_wb_w;
end
endfunction
function [31:0] complete_pc0; /*verilator public*/
begin
    complete_pc0 = pipe0_pc_wb_w;
end
endfunction
function [31:0] complete_opcode0; /*verilator public*/
begin
    complete_opcode0 = pipe0_opc_wb_w;
end
endfunction
function [4:0] complete_ra0; /*verilator public*/
begin
    complete_ra0 = v_pipe0_rs1_w;
end
endfunction
function [4:0] complete_rb0; /*verilator public*/
begin
    complete_rb0 = v_pipe0_rs2_w;
end
endfunction
function [4:0] complete_rd0; /*verilator public*/
begin
    complete_rd0 = pipe0_rd_wb_w;
end
endfunction
function [31:0] complete_ra_val0; /*verilator public*/
begin
    complete_ra_val0 = pipe0_ra_val_wb_w;
end
endfunction
function [31:0] complete_rb_val0; /*verilator public*/
begin
    complete_rb_val0 = pipe0_rb_val_wb_w;
end
endfunction
function [31:0] complete_rd_val0; /*verilator public*/
begin
    if (|pipe0_rd_wb_w)
        complete_rd_val0 = pipe0_result_wb_w;
    else
        complete_rd_val0 = 32'b0;
end
endfunction

biriscv_trace_sim
u_pipe0_dec1_verif
(
     .valid_i(pipe1_valid_wb_w)
    ,.pc_i(pipe1_pc_wb_w)
    ,.opcode_i(pipe1_opc_wb_w)
);

wire [4:0] v_pipe1_rs1_w = pipe1_opc_wb_w[19:15];
wire [4:0] v_pipe1_rs2_w = pipe1_opc_wb_w[24:20];

function [0:0] complete_valid1; /*verilator public*/
begin
    complete_valid1 = pipe1_valid_wb_w;
end
endfunction
function [31:0] complete_pc1; /*verilator public*/
begin
    complete_pc1 = pipe1_pc_wb_w;
end
endfunction
function [31:0] complete_opcode1; /*verilator public*/
begin
    complete_opcode1 = pipe1_opc_wb_w;
end
endfunction
function [4:0] complete_ra1; /*verilator public*/
begin
    complete_ra1 = v_pipe1_rs1_w;
end
endfunction
function [4:0] complete_rb1; /*verilator public*/
begin
    complete_rb1 = v_pipe1_rs2_w;
end
endfunction
function [4:0] complete_rd1; /*verilator public*/
begin
    complete_rd1 = pipe1_rd_wb_w;
end
endfunction
function [31:0] complete_ra_val1; /*verilator public*/
begin
    complete_ra_val1 = pipe1_ra_val_wb_w;
end
endfunction
function [31:0] complete_rb_val1; /*verilator public*/
begin
    complete_rb_val1 = pipe1_rb_val_wb_w;
end
endfunction
function [31:0] complete_rd_val1; /*verilator public*/
begin
    if (|pipe1_rd_wb_w)
        complete_rd_val1 = pipe1_result_wb_w;
    else
        complete_rd_val1 = 32'b0;
end
endfunction
function [5:0] complete_exception; /*verilator public*/
begin
    complete_exception = pipe0_exception_wb_w | pipe1_exception_wb_w;
end
endfunction
`endif


endmodule

// Combinational branch evaluation of an already registered E1 packet.
module triha_e1_branch #(parameter EARLY_CONDITIONAL_TARGET=0)(
    input [31:0] conditional_pc_i,
    input [31:0] opcode_i,pc_i,operand_ra_i,operand_rb_i,
    input [31:0] predicted_pc_i,
    output reg mismatch_o,
    output request_o,taken_o,not_taken_o,call_o,ret_o,jmp_o,
    output [31:0] next_pc_o,source_o
);
wire [31:0] opcode_opcode_i=opcode_i,opcode_pc_i=pc_i;
wire [31:0] opcode_ra_operand_i=operand_ra_i,opcode_rb_operand_i=operand_rb_i;
wire [4:0] opcode_rd_idx_i=opcode_i[11:7],opcode_ra_idx_i=opcode_i[19:15],opcode_rb_idx_i=opcode_i[24:20];
wire opcode_ra_zero_i=operand_ra_i==0,opcode_rb_zero_i=operand_rb_i==0;
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
// Compute the four useful addresses independently of direction/type decode.
// Preserve the used sum boundaries so ADS cannot fold the late selection
// back into a shared carry chain. No new cycle or architectural state.
wire [31:0] sequential_pc_w /* synthesis syn_keep=1 */;
wire [31:0] conditional_pc_w /* synthesis syn_keep=1 */;
wire [31:0] jump_pc_w /* synthesis syn_keep=1 */;
wire [31:1] register_pc_hi_w /* synthesis syn_keep=1 */;
wire [31:0] register_sum_w=opcode_ra_operand_i+imm12_r;
assign sequential_pc_w=opcode_pc_i+32'd4;
assign conditional_pc_w=EARLY_CONDITIONAL_TARGET ? conditional_pc_i : opcode_pc_i+bimm_r;
assign jump_pc_w=opcode_pc_i+jimm20_r;
assign register_pc_hi_w=register_sum_w[31:1];
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
    branch_target_r = conditional_pc_w;

    if ((opcode_opcode_i & `INST_JAL_MASK) == `INST_JAL) // jal
    begin
        branch_r        = 1'b1;
        branch_taken_r  = 1'b1;
        branch_target_r = jump_pc_w;
        branch_call_r   = (opcode_rd_idx_i == 5'd1); // RA
        branch_jmp_r    = 1'b1;
    end
    else if ((opcode_opcode_i & `INST_JALR_MASK) == `INST_JALR) // jalr
    begin
        branch_r            = 1'b1;
        branch_taken_r      = 1'b1;
        branch_target_r     = {register_pc_hi_w,1'b0};
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


assign taken_o=branch_r && branch_taken_r;
assign not_taken_o=branch_r && ~branch_taken_r;
assign request_o=taken_o | not_taken_o;
assign call_o=branch_r && branch_call_r;
assign ret_o=branch_r && branch_ret_r;
assign jmp_o=branch_r && branch_jmp_r;
// Compare both possible next PCs before the late direction decision.
// The unknown-direction fallback preserves conditional-vector merge semantics;
// selecting two scalar comparisons alone is not four-state equivalent.
wire conditional_mismatch_w /* synthesis syn_keep=1 */;
wire jump_mismatch_w /* synthesis syn_keep=1 */;
wire register_mismatch_w /* synthesis syn_keep=1 */;
reg target_mismatch_w;
assign conditional_mismatch_w=conditional_pc_w!=predicted_pc_i;
assign jump_mismatch_w=jump_pc_w!=predicted_pc_i;
assign register_mismatch_w={register_pc_hi_w,1'b0}!=predicted_pc_i;
// Match the existing procedural target priority, including X/Z decode.
// Compare independent targets before selecting a scalar mismatch.
always @* begin
    target_mismatch_w=conditional_mismatch_w;
    if ((opcode_opcode_i & `INST_JAL_MASK) == `INST_JAL)
        target_mismatch_w=jump_mismatch_w;
    else if ((opcode_opcode_i & `INST_JALR_MASK) == `INST_JALR)
        target_mismatch_w=register_mismatch_w;
end
wire sequential_mismatch_w /* synthesis syn_keep=1 */;
assign sequential_mismatch_w=sequential_pc_w!=predicted_pc_i;
always @* begin
    case(branch_taken_r)
        1'b0:mismatch_o=sequential_mismatch_w;
        1'b1:mismatch_o=target_mismatch_w;
        default:mismatch_o=(branch_taken_r ? branch_target_r : sequential_pc_w)!=predicted_pc_i;
    endcase
end
assign next_pc_o=branch_taken_r ? branch_target_r : sequential_pc_w;
assign source_o=opcode_pc_i;
endmodule
