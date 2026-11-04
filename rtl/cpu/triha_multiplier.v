
// TriHa maintained multiplier derivative; see ADAPTATIONS.json.
module triha_multiplier
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           opcode_valid_i
    ,input  [ 31:0]  opcode_opcode_i
    ,input  [ 31:0]  opcode_pc_i
    ,input           opcode_invalid_i
    ,input  [  4:0]  opcode_rd_idx_i
    ,input  [  4:0]  opcode_ra_idx_i
    ,input  [  4:0]  opcode_rb_idx_i
    ,input  [ 31:0]  opcode_ra_operand_i
    ,input  [ 31:0]  opcode_rb_operand_i
    ,input           hold_i

    // Outputs
    ,output [ 31:0]  writeback_value_o
    ,output [ 31:0]  early_low_value_o
    ,output         early_low_zero_o
    ,output         early_low_valid_o
);



//-----------------------------------------------------------------
// Includes
//-----------------------------------------------------------------
`include "biriscv_defs.v"

localparam MULT_STAGES = 2; // 2 or 3

//-------------------------------------------------------------
// Registers / Wires
//-------------------------------------------------------------
reg  [31:0]  result_e2_q;
reg  [31:0]  result_e3_q;

reg [32:0]   operand_a_e1_q;
reg [32:0]   operand_b_e1_q;
reg          mulhi_sel_e1_q;
reg          early_ready_e1_q;
reg          early_zero_e1_q;

//-------------------------------------------------------------
// Multiplier
//-------------------------------------------------------------
wire [64:0]  mult_result_w;
reg  [32:0]  operand_b_r;
reg  [32:0]  operand_a_r;
reg  [31:0]  result_r;



always @ *
begin
    if ((opcode_opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU)
        operand_a_r = {opcode_ra_operand_i[31], opcode_ra_operand_i[31:0]};
    else if ((opcode_opcode_i & `INST_MULH_MASK) == `INST_MULH)
        operand_a_r = {opcode_ra_operand_i[31], opcode_ra_operand_i[31:0]};
    else // MULHU || MUL
        operand_a_r = {1'b0, opcode_ra_operand_i[31:0]};
end

always @ *
begin
    if ((opcode_opcode_i & `INST_MULHSU_MASK) == `INST_MULHSU)
        operand_b_r = {1'b0, opcode_rb_operand_i[31:0]};
    else if ((opcode_opcode_i & `INST_MULH_MASK) == `INST_MULH)
        operand_b_r = {opcode_rb_operand_i[31], opcode_rb_operand_i[31:0]};
    else // MULHU || MUL
        operand_b_r = {1'b0, opcode_rb_operand_i[31:0]};
end


// Pipeline flops for multiplier
always @(posedge clk_i or posedge rst_i)
if (rst_i)
begin
    operand_a_e1_q <= 33'b0;
    operand_b_e1_q <= 33'b0;
    mulhi_sel_e1_q <= 1'b0;
    early_ready_e1_q <= 1'b1;
    early_zero_e1_q <= 1'b1;
end
else if (hold_i)
    ;
// Match the execution datapath pattern: sample data whenever not held.
// Pipeline control alone decides whether the resulting value is consumed.
else
begin
    // Full unsigned 16x16 product: zero iff either operand is zero.
    early_zero_e1_q <= (operand_a_r[15:0]==16'b0) || (operand_b_r[15:0]==16'b0);
    // RTL multiply propagates unknown low operands even for 0 * X.
    // This override preserves simulation semantics; hardware inputs are binary.
    // synthesis translate_off
    if ((^operand_a_r[15:0] === 1'bx) || (^operand_b_r[15:0] === 1'bx))
        early_zero_e1_q <= 1'bx;
    // synthesis translate_on
    operand_a_e1_q <= operand_a_r;
    operand_b_e1_q <= operand_b_r;
    mulhi_sel_e1_q <= ~((opcode_opcode_i & `INST_MUL_MASK) == `INST_MUL);
    early_ready_e1_q <= (operand_a_r[31:16]==16'b0) && (operand_b_r[31:16]==16'b0);
end

// Signed 17-bit partial products retain the full signed/unsigned 33-bit math.
// The low partial product is shared by normal writeback and the narrow bypass.
wire signed [16:0] low_a_w = {1'b0,operand_a_e1_q[15:0]};
wire signed [16:0] low_b_w = {1'b0,operand_b_e1_q[15:0]};
wire signed [16:0] high_a_w = operand_a_e1_q[32:16];
wire signed [16:0] high_b_w = operand_b_e1_q[32:16];
wire signed [33:0] partial_ll_w = low_a_w * low_b_w;
wire signed [33:0] partial_lh_w = low_a_w * high_b_w;
wire signed [33:0] partial_hl_w = high_a_w * low_b_w;
wire signed [33:0] partial_hh_w = high_a_w * high_b_w;
wire signed [35:0] cross_w = {{2{partial_lh_w[33]}},partial_lh_w} +
    {{2{partial_hl_w[33]}},partial_hl_w} + {20'b0,partial_ll_w[31:16]};
// Isolate the arithmetic shift from the unsigned concatenation's expression
// context; otherwise Verilog can zero-fill a negative cross-product carry.
wire signed [35:0] cross_carry_w = cross_w >>> 16;
wire signed [35:0] upper_w = {{2{partial_hh_w[33]}},partial_hh_w} + cross_carry_w;
assign mult_result_w = {upper_w[32:0],cross_w[15:0],partial_ll_w[15:0]};
assign early_low_value_o = partial_ll_w[31:0];
assign early_low_valid_o = early_ready_e1_q;
assign early_low_zero_o = early_zero_e1_q;

always @ *
begin
    result_r = mulhi_sel_e1_q ? mult_result_w[63:32] : mult_result_w[31:0];
end

always @(posedge clk_i or posedge rst_i)
if (rst_i)
    result_e2_q <= 32'b0;
else if (~hold_i)
    result_e2_q <= result_r;

always @(posedge clk_i or posedge rst_i)
if (rst_i)
    result_e3_q <= 32'b0;
else if (~hold_i)
    result_e3_q <= result_e2_q;

assign writeback_value_o  = (MULT_STAGES == 3) ? result_e3_q : result_e2_q;


endmodule
