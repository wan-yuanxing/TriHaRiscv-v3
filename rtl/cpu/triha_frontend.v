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

// TriHa maintained frontend derivative; see ADAPTATIONS.json.
module triha_frontend
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_BRANCH_PREDICTION = 1
    ,parameter REGISTER_REDIRECT = 1
    ,parameter REGISTER_TRAINING = 1
    ,parameter SUPPORT_MULDIV   = 1
    ,parameter SUPPORT_MMU      = 1
    ,parameter EXTRA_DECODE_STAGE = 0
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
    ,input           icache_accept_i
    ,input           icache_valid_i
    ,input           icache_error_i
    ,input  [ 63:0]  icache_inst_i
    ,input           icache_page_fault_i
    ,input           fetch0_accept_i
    ,input           fetch1_accept_i
    ,input           fetch_invalidate_i
    ,input           branch_request_i
    ,input  [ 31:0]  branch_pc_i
    ,input  [  1:0]  branch_priv_i
    ,input           branch_info_request_i
    ,input           branch_info_is_taken_i
    ,input           branch_info_is_not_taken_i
    ,input  [ 31:0]  branch_info_source_i
    ,input           branch_info_is_call_i
    ,input           branch_info_is_ret_i
    ,input           branch_info_is_jmp_i
    ,input  [ 31:0]  branch_info_pc_i

    // Outputs
    ,output          icache_rd_o
    ,output          icache_flush_o
    ,output          icache_invalidate_o
    ,output [ 31:0]  icache_pc_o
    ,output [  1:0]  icache_priv_o
    ,output          fetch0_valid_o
    ,output [ 31:0]  fetch0_instr_o
    ,output [8:0] fetch0_alu_decode_o
    ,output [2:0] fetch0_roles_o
    ,output [31:0] fetch0_pred_pc_o
    ,output [ 31:0]  fetch0_pc_o
    ,output          fetch0_fault_fetch_o
    ,output          fetch0_fault_page_o
    ,output fetch0_instr_simple_exec_o
    ,output          fetch0_instr_exec_o
    ,output          fetch0_instr_lsu_o
    ,output          fetch0_instr_branch_o
    ,output          fetch0_instr_mul_o
    ,output          fetch0_instr_div_o
    ,output          fetch0_instr_csr_o
    ,output          fetch0_instr_rd_valid_o
    ,output          fetch0_instr_invalid_o
    ,output          fetch1_valid_o
    ,output [ 31:0]  fetch1_instr_o
    ,output [8:0] fetch1_alu_decode_o
    ,output [2:0] fetch1_roles_o
    ,output [31:0] fetch1_pred_pc_o
    ,output [ 31:0]  fetch1_pc_o
    ,output          fetch1_fault_fetch_o
    ,output          fetch1_fault_page_o
    ,output fetch1_instr_simple_exec_o
    ,output          fetch1_instr_exec_o
    ,output          fetch1_instr_lsu_o
    ,output          fetch1_instr_branch_o
    ,output          fetch1_instr_mul_o
    ,output          fetch1_instr_div_o
    ,output          fetch1_instr_csr_o
    ,output          fetch1_instr_rd_valid_o
    ,output          fetch1_instr_invalid_o
);

wire           fetch_valid_w;
wire  [ 63:0]  fetch_instr_w;
wire           fetch_fault_page_w;
wire  [ 31:0]  next_pc_f_w;
wire  [  1:0]  next_taken_f_w;
wire  [ 31:0]  fetch_pc_f_w;
wire           fetch_accept_w;
wire  [  1:0]  fetch_pred_branch_w;
wire [31:0] fetch_pred_pc_w;
wire  [ 31:0]  fetch_pc_w;
wire           fetch_fault_fetch_w;
wire           fetch_pc_accept_w;


// Keep training updates outside the redirect/fetch combinational feedback.
// Capture all events, including taken/not-taken events without a miss request.
wire [69:0] training_input_w = {branch_info_request_i, branch_info_is_taken_i,
    branch_info_is_not_taken_i, branch_info_source_i, branch_info_is_call_i,
    branch_info_is_ret_i, branch_info_is_jmp_i, branch_info_pc_i};
wire [69:0] training_packet_w;
wire training_request_w, training_taken_w, training_not_taken_w;
wire training_call_w, training_ret_w, training_jmp_w;
wire [31:0] training_source_w, training_pc_w;
generate
if (REGISTER_TRAINING)
begin: g_training
    reg [69:0] packet_q;
    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
        packet_q <= 70'b0;
    else
        packet_q <= training_input_w;
    assign training_packet_w = packet_q;
end
else
begin: g_training_bypass
    assign training_packet_w = training_input_w;
end
endgenerate
assign {training_request_w, training_taken_w, training_not_taken_w,
    training_source_w, training_call_w, training_ret_w, training_jmp_w,
    training_pc_w} = training_packet_w;

triha_npc
#(
     .NUM_BTB_ENTRIES(NUM_BTB_ENTRIES)
    ,.BTB_DIRECT_MAPPED(BTB_DIRECT_MAPPED)
    ,.SUPPORT_BRANCH_PREDICTION(SUPPORT_BRANCH_PREDICTION)
    ,.GSHARE_ENABLE(GSHARE_ENABLE)
    ,.NUM_RAS_ENTRIES_W(NUM_RAS_ENTRIES_W)
    ,.NUM_BHT_ENTRIES_W(NUM_BHT_ENTRIES_W)
    ,.BHT_ENABLE(BHT_ENABLE)
    ,.NUM_BTB_ENTRIES_W(NUM_BTB_ENTRIES_W)
    ,.NUM_BHT_ENTRIES(NUM_BHT_ENTRIES)
    ,.RAS_ENABLE(RAS_ENABLE)
    ,.NUM_RAS_ENTRIES(NUM_RAS_ENTRIES)
)
u_npc
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.invalidate_i(1'b0)
    ,.branch_request_i(training_request_w)
    ,.branch_is_taken_i(training_taken_w)
    ,.branch_is_not_taken_i(training_not_taken_w)
    ,.branch_source_i(training_source_w)
    ,.branch_is_call_i(training_call_w)
    ,.branch_is_ret_i(training_ret_w)
    ,.branch_is_jmp_i(training_jmp_w)
    ,.branch_pc_i(training_pc_w)
    ,.pc_f_i(fetch_pc_f_w)
    ,.pc_accept_i(fetch_pc_accept_w)

    // Outputs
    ,.next_pc_f_o(next_pc_f_w)
    ,.next_taken_f_o(next_taken_f_w)
);


triha_decode
#(
     .EXTRA_DECODE_STAGE(EXTRA_DECODE_STAGE)
    ,.SUPPORT_MULDIV(SUPPORT_MULDIV)
)
u_decode
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.fetch_in_valid_i(fetch_valid_w)
    ,.fetch_in_instr_i(fetch_instr_w)
    ,.fetch_in_pred_pc_i(fetch_pred_pc_w)
    ,.fetch_in_pred_branch_i(fetch_pred_branch_w)
    ,.fetch_in_fault_fetch_i(fetch_fault_fetch_w)
    ,.fetch_in_fault_page_i(fetch_fault_page_w)
    ,.fetch_in_pc_i(fetch_pc_w)
    ,.fetch_out0_accept_i(fetch0_accept_i)
    ,.fetch_out1_accept_i(fetch1_accept_i)
    ,.branch_request_i(branch_request_i)
    ,.branch_pc_i(branch_pc_i)
    ,.branch_priv_i(branch_priv_i)

    // Outputs
    ,.fetch_in_accept_o(fetch_accept_w)
    ,.fetch_out0_valid_o(fetch0_valid_o)
    ,.fetch_out0_instr_o(fetch0_instr_o)
    ,.fetch_out0_alu_decode_o(fetch0_alu_decode_o)
    ,.fetch_out0_roles_o(fetch0_roles_o)
    ,.fetch_out0_pred_pc_o(fetch0_pred_pc_o)
    ,.fetch_out0_pc_o(fetch0_pc_o)
    ,.fetch_out0_fault_fetch_o(fetch0_fault_fetch_o)
    ,.fetch_out0_fault_page_o(fetch0_fault_page_o)
    ,.fetch_out0_instr_simple_exec_o(fetch0_instr_simple_exec_o)
    ,.fetch_out0_instr_exec_o(fetch0_instr_exec_o)
    ,.fetch_out0_instr_lsu_o(fetch0_instr_lsu_o)
    ,.fetch_out0_instr_branch_o(fetch0_instr_branch_o)
    ,.fetch_out0_instr_mul_o(fetch0_instr_mul_o)
    ,.fetch_out0_instr_div_o(fetch0_instr_div_o)
    ,.fetch_out0_instr_csr_o(fetch0_instr_csr_o)
    ,.fetch_out0_instr_rd_valid_o(fetch0_instr_rd_valid_o)
    ,.fetch_out0_instr_invalid_o(fetch0_instr_invalid_o)
    ,.fetch_out1_valid_o(fetch1_valid_o)
    ,.fetch_out1_instr_o(fetch1_instr_o)
    ,.fetch_out1_alu_decode_o(fetch1_alu_decode_o)
    ,.fetch_out1_roles_o(fetch1_roles_o)
    ,.fetch_out1_pred_pc_o(fetch1_pred_pc_o)
    ,.fetch_out1_pc_o(fetch1_pc_o)
    ,.fetch_out1_fault_fetch_o(fetch1_fault_fetch_o)
    ,.fetch_out1_fault_page_o(fetch1_fault_page_o)
    ,.fetch_out1_instr_simple_exec_o(fetch1_instr_simple_exec_o)
    ,.fetch_out1_instr_exec_o(fetch1_instr_exec_o)
    ,.fetch_out1_instr_lsu_o(fetch1_instr_lsu_o)
    ,.fetch_out1_instr_branch_o(fetch1_instr_branch_o)
    ,.fetch_out1_instr_mul_o(fetch1_instr_mul_o)
    ,.fetch_out1_instr_div_o(fetch1_instr_div_o)
    ,.fetch_out1_instr_csr_o(fetch1_instr_csr_o)
    ,.fetch_out1_instr_rd_valid_o(fetch1_instr_rd_valid_o)
    ,.fetch_out1_instr_invalid_o(fetch1_instr_invalid_o)
);


triha_fetch_prediction
#(
     // Reuse the existing registered fetch timing without enabling the outer MMU.
     .SUPPORT_MMU(SUPPORT_MMU || REGISTER_REDIRECT)
    ,.ACTIVE_WAIT_ACCEPT(SUPPORT_MMU)
)
u_fetch
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.fetch_accept_i(fetch_accept_w)
    ,.icache_accept_i(icache_accept_i)
    ,.icache_valid_i(icache_valid_i)
    ,.icache_error_i(icache_error_i)
    ,.icache_inst_i(icache_inst_i)
    ,.icache_page_fault_i(icache_page_fault_i)
    ,.fetch_invalidate_i(fetch_invalidate_i)
    ,.branch_request_i(branch_request_i)
    ,.branch_pc_i(branch_pc_i)
    ,.branch_priv_i(branch_priv_i)
    ,.next_pc_f_i(next_pc_f_w)
    ,.next_taken_f_i(next_taken_f_w)

    // Outputs
    ,.fetch_valid_o(fetch_valid_w)
    ,.fetch_instr_o(fetch_instr_w)
    ,.fetch_pred_pc_o(fetch_pred_pc_w)
    ,.fetch_pred_branch_o(fetch_pred_branch_w)
    ,.fetch_fault_fetch_o(fetch_fault_fetch_w)
    ,.fetch_fault_page_o(fetch_fault_page_w)
    ,.fetch_pc_o(fetch_pc_w)
    ,.icache_rd_o(icache_rd_o)
    ,.icache_flush_o(icache_flush_o)
    ,.icache_invalidate_o(icache_invalidate_o)
    ,.icache_pc_o(icache_pc_o)
    ,.icache_priv_o(icache_priv_o)
    ,.pc_f_o(fetch_pc_f_w)
    ,.pc_accept_o(fetch_pc_accept_w)
);



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

// Maintained request-prediction derivative; vendor source remains unchanged.
module triha_fetch_prediction
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MMU      = 1
    ,parameter ACTIVE_WAIT_ACCEPT = SUPPORT_MMU
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           fetch_accept_i
    ,input           icache_accept_i
    ,input           icache_valid_i
    ,input           icache_error_i
    ,input  [ 63:0]  icache_inst_i
    ,input           icache_page_fault_i
    ,input           fetch_invalidate_i
    ,input           branch_request_i
    ,input  [ 31:0]  branch_pc_i
    ,input  [  1:0]  branch_priv_i
    ,input  [ 31:0]  next_pc_f_i
    ,input  [  1:0]  next_taken_f_i

    // Outputs
    ,output          fetch_valid_o
    ,output [ 63:0]  fetch_instr_o
    ,output [  1:0]  fetch_pred_branch_o
    ,output          fetch_fault_fetch_o
    ,output          fetch_fault_page_o
    ,output [31:0] fetch_pred_pc_o
    ,output [ 31:0]  fetch_pc_o
    ,output          icache_rd_o
    ,output          icache_flush_o
    ,output          icache_invalidate_o
    ,output [ 31:0]  icache_pc_o
    ,output [  1:0]  icache_priv_o
    ,output [ 31:0]  pc_f_o
    ,output          pc_accept_o
);



//-------------------------------------------------------------
// Registers / Wires
//-------------------------------------------------------------
reg         active_q;

wire        icache_busy_w;
wire        stall_w       = !fetch_accept_i || icache_busy_w || !icache_accept_i;

//-------------------------------------------------------------
// Buffered branch
//-------------------------------------------------------------
reg         branch_q;
reg [31:0]  branch_pc_q;
reg [1:0]   branch_priv_q;

wire        branch_w;
wire [31:0] branch_pc_w;
wire [1:0]  branch_priv_w;

generate
if (SUPPORT_MMU)
begin
    assign branch_w      = branch_q;
    assign branch_pc_w   = branch_pc_q;
    assign branch_priv_w = branch_priv_q;
    
    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
    begin
        branch_q       <= 1'b0;
        branch_pc_q    <= 32'b0;
        branch_priv_q  <= `PRIV_MACHINE;
    end
    else if (branch_request_i)
    begin
        branch_q       <= 1'b1;
        branch_pc_q    <= branch_pc_i;
        branch_priv_q  <= branch_priv_i;
    end
    else if (icache_rd_o && icache_accept_i)
    begin
        branch_q       <= 1'b0;
        branch_pc_q    <= 32'b0;
    end
end
else
begin
    assign branch_w      = branch_q || branch_request_i;
    assign branch_pc_w   = (branch_q & !branch_request_i) ? branch_pc_q   : branch_pc_i;
    assign branch_priv_w = `PRIV_MACHINE; // don't care

    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
    begin
        branch_q       <= 1'b0;
        branch_pc_q    <= 32'b0;
    end
    else if (branch_request_i && (icache_busy_w || !active_q))
    begin
        branch_q       <= branch_w;
        branch_pc_q    <= branch_pc_w;
    end
    else if (~icache_busy_w)
    begin
        branch_q       <= 1'b0;
        branch_pc_q    <= 32'b0;
    end

end
endgenerate

//-------------------------------------------------------------
// Active flag
//-------------------------------------------------------------
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    active_q    <= 1'b0;
// Registered redirect alone must not select the MMU activation policy.
// Reuse the native non-MMU sticky activation; request acceptance and
// stale-response dropping remain at their original handshake boundary.
else if (SUPPORT_MMU && branch_w && (!ACTIVE_WAIT_ACCEPT || ~stall_w))
    active_q    <= 1'b1;
else if (!SUPPORT_MMU && branch_w)
    active_q    <= 1'b1;

//-------------------------------------------------------------
// Stall flag
//-------------------------------------------------------------
reg stall_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    stall_q    <= 1'b0;
else
    stall_q    <= stall_w;

//-------------------------------------------------------------
// Request tracking
//-------------------------------------------------------------
reg icache_fetch_q;
reg icache_invalidate_q;

// ICACHE fetch tracking
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    icache_fetch_q <= 1'b0;
else if (icache_rd_o && icache_accept_i)
    icache_fetch_q <= 1'b1;
else if (icache_valid_i)
    icache_fetch_q <= 1'b0;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    icache_invalidate_q <= 1'b0;
else if (icache_invalidate_o && !icache_accept_i)
    icache_invalidate_q <= 1'b1;
else
    icache_invalidate_q <= 1'b0;

//-------------------------------------------------------------
// PC
//-------------------------------------------------------------
reg [31:0]  pc_f_q;
reg [31:0]  pc_d_q;
reg [1:0]   pred_d_q;
reg [31:0] pred_pc_d_q;
always @(posedge clk_i or posedge rst_i)
if(rst_i) pred_pc_d_q<=0;
else if(icache_rd_o && icache_accept_i) pred_pc_d_q<=next_pc_f_i;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pc_f_q  <= 32'b0;
// Branch request
else if (SUPPORT_MMU && branch_w && ~stall_w)
    pc_f_q  <= branch_pc_w;
else if (!SUPPORT_MMU && (stall_w || !active_q || stall_q) && branch_w)
    pc_f_q  <= branch_pc_w;
// NPC
else if (!stall_w)
    pc_f_q  <= next_pc_f_i;

wire [31:0] icache_pc_w;
wire [1:0]  icache_priv_w;
wire        fetch_resp_drop_w;

generate
if (SUPPORT_MMU)
begin
    reg [1:0] priv_f_q;
    reg       branch_d_q;

    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
        priv_f_q  <= `PRIV_MACHINE;
    // Branch request
    else if (branch_w && ~stall_w)
        priv_f_q  <= branch_priv_w;

    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
        branch_d_q  <= 1'b0;
    // Branch request
    else if (branch_w && ~stall_w)
        branch_d_q  <= 1'b1;
    // NPC
    else if (!stall_w)
        branch_d_q  <= 1'b0;

    assign icache_pc_w       = pc_f_q;
    assign icache_priv_w     = priv_f_q;
    assign fetch_resp_drop_w = branch_w | branch_d_q;
end
else
begin
    assign icache_pc_w       = (branch_w & ~stall_q) ? branch_pc_w : pc_f_q;
    assign icache_priv_w     = `PRIV_MACHINE; // Don't care
    assign fetch_resp_drop_w = branch_w;
end
endgenerate

// Last fetch address
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pc_d_q <= 32'b0;
else if (icache_rd_o && icache_accept_i)
    pc_d_q <= icache_pc_w;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    pred_d_q <= 2'b0;
else if (icache_rd_o && icache_accept_i)
    pred_d_q <= next_taken_f_i;
else if (icache_valid_i)
    pred_d_q <= 2'b0;

//-------------------------------------------------------------
// Outputs
//-------------------------------------------------------------
assign icache_rd_o         = active_q & fetch_accept_i & !icache_busy_w;
assign icache_pc_o         = {icache_pc_w[31:3],3'b0};
assign icache_priv_o       = icache_priv_w;
assign icache_flush_o      = fetch_invalidate_i | icache_invalidate_q;
assign icache_invalidate_o = 1'b0;

assign icache_busy_w       =  icache_fetch_q && !icache_valid_i;

//-------------------------------------------------------------
// Response Buffer
//-------------------------------------------------------------
reg [131:0] skid_buffer_q;
reg         skid_valid_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    skid_buffer_q  <= 132'b0;
    skid_valid_q   <= 1'b0;
end 
// Instruction output back-pressured - hold in skid buffer
else if (fetch_valid_o && !fetch_accept_i)
begin
    skid_valid_q  <= 1'b1;
    skid_buffer_q <= {fetch_pred_pc_o, fetch_fault_page_o, fetch_fault_fetch_o, fetch_pred_branch_o, fetch_pc_o, fetch_instr_o};
end
else
begin
    skid_valid_q  <= 1'b0;
    skid_buffer_q <= 132'b0;
end

assign fetch_pred_pc_o = skid_valid_q ? skid_buffer_q[131:100] : pred_pc_d_q;
assign fetch_valid_o       = (icache_valid_i || skid_valid_q) & !fetch_resp_drop_w;
assign fetch_pc_o          = skid_valid_q ? skid_buffer_q[95:64] : {pc_d_q[31:2],2'b0};
assign fetch_instr_o       = skid_valid_q ? skid_buffer_q[63:0]  : icache_inst_i;
assign fetch_pred_branch_o = skid_valid_q ? skid_buffer_q[97:96] : pred_d_q;

// Faults
assign fetch_fault_fetch_o = skid_valid_q ? skid_buffer_q[98] : icache_error_i;
assign fetch_fault_page_o  = skid_valid_q ? skid_buffer_q[99] : icache_page_fault_i;

assign pc_f_o              = icache_pc_w;
assign pc_accept_o         = ~stall_w;



endmodule
