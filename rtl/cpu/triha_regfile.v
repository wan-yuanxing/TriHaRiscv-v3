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
/*
 * TriHa register file: asynchronous distributed RAM for single issue.
 * Two copies provide the existing two simultaneous read ports. A resettable
 * written mask preserves synchronous zero-on-reset without resetting RAM.
 * The single-issue integration has no secondary write. Dual issue retains
 * the existing implementation. See ADAPTATIONS.json for provenance.
 */
`timescale 1ns / 1ps
module triha_regfile #(
    parameter SUPPORT_REGFILE_XILINX = 0,
    parameter SUPPORT_DUAL_ISSUE = 1
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire [4:0]  rd0_i,
    input  wire [4:0]  rd1_i,
    input  wire [31:0] rd0_value_i,
    input  wire [31:0] rd1_value_i,
    input  wire [4:0]  ra0_i,
    input  wire [4:0]  rb0_i,
    input  wire [4:0]  ra1_i,
    input  wire [4:0]  rb1_i,
    output wire [31:0] ra0_value_o,
    output wire [31:0] rb0_value_o,
    output wire [31:0] ra1_value_o,
    output wire [31:0] rb1_value_o
);
    generate
        if (!SUPPORT_DUAL_ISSUE && !SUPPORT_REGFILE_XILINX) begin : g_single
            reg [31:1] written_q;
            wire [31:0] known_w = {written_q, 1'b0};
            wire write_w = !rst_i && (|rd0_i);
            wire [31:0] ra_data_w;
            wire [31:0] rb_data_w;

            always @(posedge clk_i) begin
                if (rst_i)
                    written_q <= 31'b0;
                else if (|rd0_i)
                    written_q[rd0_i] <= 1'b1;
            end

            genvar bit_pair;
            for (bit_pair=0; bit_pair<16; bit_pair=bit_pair+1) begin : g_pair
                GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ra (
                    .DO(ra_data_w[2*bit_pair +: 2]),
                    .DI(rd0_value_i[2*bit_pair +: 2]),
                    .RADDR(ra0_i), .WADDR(rd0_i), .WCLK(clk_i), .WE(write_w)
                );
                GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_rb (
                    .DO(rb_data_w[2*bit_pair +: 2]),
                    .DI(rd0_value_i[2*bit_pair +: 2]),
                    .RADDR(rb0_i), .WADDR(rd0_i), .WCLK(clk_i), .WE(write_w)
                );
            end

            assign ra0_value_o = known_w[ra0_i] ? ra_data_w : 32'b0;
            assign rb0_value_o = known_w[rb0_i] ? rb_data_w : 32'b0;
            assign ra1_value_o = 32'b0;
            assign rb1_value_o = 32'b0;

            // synthesis translate_off
            always @(posedge clk_i) begin
                if (!rst_i && rd1_i !== 5'b0)
                    $fatal(1, "REGFILE_FAIL single_issue_secondary_write");
            end
            // synthesis translate_on
        end else begin : g_existing
            biriscv_regfile #(
                .SUPPORT_REGFILE_XILINX(SUPPORT_REGFILE_XILINX),
                .SUPPORT_DUAL_ISSUE(SUPPORT_DUAL_ISSUE)
            ) u_regfile (
                .clk_i(clk_i), .rst_i(rst_i),
                .rd0_i(rd0_i), .rd1_i(rd1_i),
                .rd0_value_i(rd0_value_i), .rd1_value_i(rd1_value_i),
                .ra0_i(ra0_i), .rb0_i(rb0_i), .ra1_i(ra1_i), .rb1_i(rb1_i),
                .ra0_value_o(ra0_value_o), .rb0_value_o(rb0_value_o),
                .ra1_value_o(ra1_value_o), .rb1_value_o(rb1_value_o)
            );
        end
    endgenerate
endmodule
