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

/* TriHa divider boundary: retain the existing algorithm and cached results. */
`timescale 1ns / 1ps
module triha_divider #(parameter REGISTER_INPUT=1) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        opcode_valid_i,
    input  wire [31:0] opcode_opcode_i,
    input  wire [31:0] opcode_pc_i,
    input  wire        opcode_invalid_i,
    input  wire [4:0]  opcode_rd_idx_i,
    input  wire [4:0]  opcode_ra_idx_i,
    input  wire [4:0]  opcode_rb_idx_i,
    input  wire [31:0] opcode_ra_operand_i,
    input  wire [31:0] opcode_rb_operand_i,
    output wire        writeback_valid_o,
    output wire [31:0] writeback_value_o
);
    wire valid_w, invalid_w;
    wire [31:0] opcode_w, pc_w, a_w, b_w;
    wire [4:0] rd_w, ra_w, rb_w;
    wire [143:0] payload_w = {opcode_opcode_i,opcode_pc_i,opcode_invalid_i,
        opcode_rd_idx_i,opcode_ra_idx_i,opcode_rb_idx_i,opcode_ra_operand_i,opcode_rb_operand_i};
    wire [143:0] selected_payload_w;
    generate
        if (REGISTER_INPUT) begin : g_input
            reg valid_q;
            reg [143:0] payload_q;
            always @(posedge clk_i or posedge rst_i) begin
                if (rst_i) begin
                    valid_q <= 1'b0;
                    payload_q <= 144'b0;
                end else begin
                    valid_q <= opcode_valid_i;
                    payload_q <= payload_w;
                end
            end
            assign valid_w = valid_q;
            assign selected_payload_w = payload_q;
        end else begin : g_direct
            assign valid_w = opcode_valid_i;
            assign selected_payload_w = payload_w;
        end
    endgenerate
    assign {opcode_w,pc_w,invalid_w,rd_w,ra_w,rb_w,a_w,b_w}=selected_payload_w;
    biriscv_divider u_div (
        .clk_i(clk_i),.rst_i(rst_i),.opcode_valid_i(valid_w),.opcode_opcode_i(opcode_w),
        .opcode_pc_i(pc_w),.opcode_invalid_i(invalid_w),.opcode_rd_idx_i(rd_w),
        .opcode_ra_idx_i(ra_w),.opcode_rb_idx_i(rb_w),
        .opcode_ra_operand_i(a_w),.opcode_rb_operand_i(b_w),
        .writeback_valid_o(writeback_valid_o),.writeback_value_o(writeback_value_o)
    );
endmodule
