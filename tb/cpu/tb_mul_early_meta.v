/* Clocked complete multiplier outputs versus the frozen pre-metadata source. */
`timescale 1ns/1ps
module tb_mul_early_meta #(parameter BROKEN=0);
    reg clk=0,rst=1,valid=0,invalid=0,hold=0;
    always #5 clk=~clk;
    reg [31:0] opcode=0,a=0,b=0,rng=32'h71395a2b;
    wire [64:0] ref_out,got_out;
    integer n,i,j,k,checks=0;
    triha_mul_meta_reference u_reference (
        .clk_i(clk),.rst_i(rst),.opcode_valid_i(valid),.opcode_opcode_i(opcode),
        .opcode_pc_i(32'h80000000),.opcode_invalid_i(invalid),.opcode_rd_idx_i(opcode[11:7]),
        .opcode_ra_idx_i(opcode[19:15]),.opcode_rb_idx_i(opcode[24:20]),
        .opcode_ra_operand_i(a),.opcode_rb_operand_i(b),.hold_i(hold),
        .writeback_value_o(ref_out[64:33]),.early_low_value_o(ref_out[32:1]),.early_low_valid_o(ref_out[0])
    );
    triha_multiplier u_dut (
        .clk_i(clk),.rst_i(rst),.opcode_valid_i(valid),.opcode_opcode_i(opcode),
        .opcode_pc_i(32'h80000000),.opcode_invalid_i(invalid),.opcode_rd_idx_i(opcode[11:7]),
        .opcode_ra_idx_i(opcode[19:15]),.opcode_rb_idx_i(opcode[24:20]),
        .opcode_ra_operand_i(a),.opcode_rb_operand_i(b),.hold_i(hold),
        .writeback_value_o(got_out[64:33]),.early_low_value_o(got_out[32:1]),.early_low_valid_o(got_out[0])
    );
    function [31:0] boundary;
        input integer index;
        begin
            case(index)
                0:boundary=0;1:boundary=1;2:boundary=32'hffff;3:boundary=32'h10000;
                4:boundary=32'h7fffffff;5:boundary=32'h80000000;
                6:boundary=32'hffff0000;default:boundary=32'hffffffff;
            endcase
        end
    endfunction
    function [31:0] operation;
        input integer index;
        begin
            case(index)
                0:operation=32'h02b50533;1:operation=32'h02b51533;
                2:operation=32'h02b52533;3:operation=32'h02b53533;
                4:operation=32'h02b54533;5:operation=32'h00150513;
                6:operation=0;default:operation=32'hffffffff;
            endcase
        end
    endfunction
    task check;
        begin
            checks=checks+1;
            if(got_out!==ref_out)$fatal(1,"MUL_META_FAIL n=%0d opcode=%h a=%h b=%h hold=%b ref=%h got=%h",n,opcode,a,b,hold,ref_out,got_out);
        end
    endtask
    initial begin
        repeat(3)begin @(posedge clk);#1;check;end
        @(negedge clk);rst=0;if(BROKEN)force u_dut.early_low_valid_o=0;
        for(n=0;n<20000;n=n+1)begin
            @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            a=rng;b={rng[15:0],rng[31:16]};opcode=operation(n%8);
            if(n%5==0)a[31:16]=0;if(n%7==0)b[31:16]=0;
            valid=rng[5];invalid=rng[6];hold=(n%11==0);rst=(n%997==0);
            case(n%97)
                1:a[16]=1'bx;2:b[17]=1'bz;3:a[31]=1'bz;4:b[31]=1'bx;
                5:a[3]=1'bx;6:b[4]=1'bz;7:hold=1'bx;8:valid=1'bx;
                9:opcode[31]=1'bx;10:opcode[25]=1'bz;11:invalid=1'bz;
            endcase
            #1;check;@(posedge clk);#1;check;
        end
        for(k=0;k<8;k=k+1)for(i=0;i<8;i=i+1)for(j=0;j<8;j=j+1)begin
            @(negedge clk);rst=0;valid=1;invalid=0;hold=0;opcode=operation(k);a=boundary(i);b=boundary(j);
            #1;check;@(posedge clk);#1;check;
        end
        $display("MUL_META_PASS samples=%0d full_writeback_early_value_ready",checks);$finish;
    end
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

// TriHa maintained multiplier derivative; see ADAPTATIONS.json.
module triha_mul_meta_reference
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
end
else if (hold_i)
    ;
// Match the execution datapath pattern: sample data whenever not held.
// Pipeline control alone decides whether the resulting value is consumed.
else
begin
    operand_a_e1_q <= operand_a_r;
    operand_b_e1_q <= operand_b_r;
    mulhi_sel_e1_q <= ~((opcode_opcode_i & `INST_MUL_MASK) == `INST_MUL);
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
assign early_low_valid_o = (operand_a_e1_q[31:16]==16'b0) &&
                          (operand_b_e1_q[31:16]==16'b0);

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
