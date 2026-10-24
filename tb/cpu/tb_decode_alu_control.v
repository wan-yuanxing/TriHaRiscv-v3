/* Clocked all-output oracle against frozen v20 decode plus its own FIFO.
 * The complete original implementation follows below, module names only changed.
 */
`timescale 1ns/1ps
module tb_decode_alu_control #(parameter BROKEN=0,MULDIV=1,EXTRA=0,BROKEN_ALU=0);
    reg clk=0,rst=1,push=0,pop0=0,pop1=0,flush=0,fetch_fault=0,page_fault=0;
    reg [31:0] pc=32'h80001000,rng=32'h6741523b;
    reg [63:0] data=64'h0010009300200113;
    reg [1:0] pred=0;
    wire [150:0] got,ref_out;
    wire [8:0] control0,control1,expected_control0,expected_control1;
    triha_alu_predecode u_expected0 (.opcode_i(ref_out[148:117]),.control_o(expected_control0));
    triha_alu_predecode u_expected1 (.opcode_i(ref_out[73:42]),.control_o(expected_control1));
    integer n,checks=0;
    always #5 clk=~clk;
    triha_decode #(.SUPPORT_MULDIV(MULDIV),.EXTRA_DECODE_STAGE(EXTRA)) u_dut (
        .clk_i(clk),.rst_i(rst),.fetch_in_valid_i(push),.fetch_in_instr_i(data),
        .fetch_in_pred_branch_i(pred),.fetch_in_fault_fetch_i(fetch_fault),.fetch_in_fault_page_i(page_fault),
        .fetch_in_pc_i(pc),.fetch_out0_accept_i(pop0),.fetch_out1_accept_i(pop1),
        .branch_request_i(flush),.branch_pc_i(0),.branch_priv_i(2'b0),
        .fetch_in_accept_o(got[150]),
        .fetch_out0_alu_decode_o(control0),.fetch_out1_alu_decode_o(control1),
        .fetch_out0_valid_o(got[149]),.fetch_out0_instr_o(got[148:117]),.fetch_out0_pc_o(got[116:85]),
        .fetch_out0_fault_fetch_o(got[84]),.fetch_out0_fault_page_o(got[83]),
        .fetch_out0_instr_exec_o(got[82]),.fetch_out0_instr_lsu_o(got[81]),.fetch_out0_instr_branch_o(got[80]),
        .fetch_out0_instr_mul_o(got[79]),.fetch_out0_instr_div_o(got[78]),.fetch_out0_instr_csr_o(got[77]),
        .fetch_out0_instr_rd_valid_o(got[76]),.fetch_out0_instr_invalid_o(got[75]),
        .fetch_out1_valid_o(got[74]),.fetch_out1_instr_o(got[73:42]),.fetch_out1_pc_o(got[41:10]),
        .fetch_out1_fault_fetch_o(got[9]),.fetch_out1_fault_page_o(got[8]),
        .fetch_out1_instr_exec_o(got[7]),.fetch_out1_instr_lsu_o(got[6]),.fetch_out1_instr_branch_o(got[5]),
        .fetch_out1_instr_mul_o(got[4]),.fetch_out1_instr_div_o(got[3]),.fetch_out1_instr_csr_o(got[2]),
        .fetch_out1_instr_rd_valid_o(got[1]),.fetch_out1_instr_invalid_o(got[0]));
    triha_decode_queued_reference #(.SUPPORT_MULDIV(MULDIV),.EXTRA_DECODE_STAGE(EXTRA)) u_reference (
        .clk_i(clk),.rst_i(rst),.fetch_in_valid_i(push),.fetch_in_instr_i(data),
        .fetch_in_pred_branch_i(pred),.fetch_in_fault_fetch_i(fetch_fault),.fetch_in_fault_page_i(page_fault),
        .fetch_in_pc_i(pc),.fetch_out0_accept_i(pop0),.fetch_out1_accept_i(pop1),
        .branch_request_i(flush),.branch_pc_i(0),.branch_priv_i(2'b0),
        .fetch_in_accept_o(ref_out[150]),
        .fetch_out0_valid_o(ref_out[149]),.fetch_out0_instr_o(ref_out[148:117]),.fetch_out0_pc_o(ref_out[116:85]),
        .fetch_out0_fault_fetch_o(ref_out[84]),.fetch_out0_fault_page_o(ref_out[83]),
        .fetch_out0_instr_exec_o(ref_out[82]),.fetch_out0_instr_lsu_o(ref_out[81]),.fetch_out0_instr_branch_o(ref_out[80]),
        .fetch_out0_instr_mul_o(ref_out[79]),.fetch_out0_instr_div_o(ref_out[78]),.fetch_out0_instr_csr_o(ref_out[77]),
        .fetch_out0_instr_rd_valid_o(ref_out[76]),.fetch_out0_instr_invalid_o(ref_out[75]),
        .fetch_out1_valid_o(ref_out[74]),.fetch_out1_instr_o(ref_out[73:42]),.fetch_out1_pc_o(ref_out[41:10]),
        .fetch_out1_fault_fetch_o(ref_out[9]),.fetch_out1_fault_page_o(ref_out[8]),
        .fetch_out1_instr_exec_o(ref_out[7]),.fetch_out1_instr_lsu_o(ref_out[6]),.fetch_out1_instr_branch_o(ref_out[5]),
        .fetch_out1_instr_mul_o(ref_out[4]),.fetch_out1_instr_div_o(ref_out[3]),.fetch_out1_instr_csr_o(ref_out[2]),
        .fetch_out1_instr_rd_valid_o(ref_out[1]),.fetch_out1_instr_invalid_o(ref_out[0]));
    task check;
        begin
            #1;checks=checks+1;
            if({control0,control1}!=={expected_control0,expected_control1})
                $fatal(1,"ALU_META_ALIGNMENT_FAIL check=%0d controls=%h/%h expected=%h/%h",checks,control0,control1,expected_control0,expected_control1);
            if(got!==ref_out)$fatal(1,"ALU_META_ALIGNMENT_FAIL check=%0d cfg=%0d/%0d got=%h expected=%h",checks,MULDIV,EXTRA,got,ref_out);
        end
    endtask
    initial begin
        repeat(4)begin @(negedge clk);check;end
        rst=0;push=1;
        @(negedge clk);check;push=0;
        if(BROKEN)force u_dut.fetch_out0_instr_exec_o=0;
        if(BROKEN_ALU)force u_dut.fetch_out0_alu_decode_o=0;
        for(n=0;n<12000;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;
            {push,pop0,pop1}=rng[2:0];flush=rng[8:3]==0;pred=rng[10:9];
            fetch_fault=rng[15:11]==0;page_fault=rng[20:16]==0;
            pc={4'h8,rng[27:3],3'b0};data={rng,~rng};
            case(n%12)
                0:data=64'h0010009300200113;
                1:data=64'h002081b3002081b3;
                2:data=64'h022081b3022081b3;
                3:data=64'h0001208300112023;
                4:data=64'h000080670000006f;
                5:data=64'h0000007300000063;
                6:data=64'h3000107300000013;
                7:data=64'h0010007300000013;
            endcase
            if(n%31==0)data[7]=1'bx;
            if(n%37==0)data[34]=1'bz;
            if(n%41==0)push=1'bx;
            if(n%43==0)pop0=1'bx;
            if(n%47==0)pop1=1'bz;
            if(n%53==0)pred[0]=1'bx;
            if(n%59==0)flush=1'bx;
            if(n%61==0)fetch_fault=1'bx;
            if(n%67==0)page_fault=1'bz;
            if(n>0 && n%193==0)rst=1;
            else rst=0;
            @(negedge clk);check;
        end
        $display("ALU_META_ALIGNMENT_PASS checks=%0d complete151bit_history_four_state",checks);$finish;
    end
endmodule

// Frozen reference appended by preparation, original bytes except module names.
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

module triha_decode_queued_reference
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MULDIV   = 1
    ,parameter EXTRA_DECODE_STAGE = 0
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           fetch_in_valid_i
    ,input  [ 63:0]  fetch_in_instr_i
    ,input  [  1:0]  fetch_in_pred_branch_i
    ,input           fetch_in_fault_fetch_i
    ,input           fetch_in_fault_page_i
    ,input  [ 31:0]  fetch_in_pc_i
    ,input           fetch_out0_accept_i
    ,input           fetch_out1_accept_i
    ,input           branch_request_i
    ,input  [ 31:0]  branch_pc_i
    ,input  [  1:0]  branch_priv_i

    // Outputs
    ,output          fetch_in_accept_o
    ,output          fetch_out0_valid_o
    ,output [ 31:0]  fetch_out0_instr_o
    ,output [ 31:0]  fetch_out0_pc_o
    ,output          fetch_out0_fault_fetch_o
    ,output          fetch_out0_fault_page_o
    ,output          fetch_out0_instr_exec_o
    ,output          fetch_out0_instr_lsu_o
    ,output          fetch_out0_instr_branch_o
    ,output          fetch_out0_instr_mul_o
    ,output          fetch_out0_instr_div_o
    ,output          fetch_out0_instr_csr_o
    ,output          fetch_out0_instr_rd_valid_o
    ,output          fetch_out0_instr_invalid_o
    ,output          fetch_out1_valid_o
    ,output [ 31:0]  fetch_out1_instr_o
    ,output [ 31:0]  fetch_out1_pc_o
    ,output          fetch_out1_fault_fetch_o
    ,output          fetch_out1_fault_page_o
    ,output          fetch_out1_instr_exec_o
    ,output          fetch_out1_instr_lsu_o
    ,output          fetch_out1_instr_branch_o
    ,output          fetch_out1_instr_mul_o
    ,output          fetch_out1_instr_div_o
    ,output          fetch_out1_instr_csr_o
    ,output          fetch_out1_instr_rd_valid_o
    ,output          fetch_out1_instr_invalid_o
);



wire        enable_muldiv_w     = SUPPORT_MULDIV;

//-----------------------------------------------------------------
// 2 cycle frontend latency
//-----------------------------------------------------------------
generate
if (EXTRA_DECODE_STAGE)
begin
    wire        fetch_in_fault_page_w;
    wire        fetch_in_fault_fetch_w;
    wire [1:0]  fetch_in_pred_branch_w;
    wire [63:0] fetch_in_instr_raw_w;
    wire [63:0] fetch_in_instr_w;
    wire [31:0] fetch_in_pc_w;
    wire        fetch_in_valid_w;

    reg [100:0] fetch_buffer_q;

    always @ (posedge clk_i or posedge rst_i)
    if (rst_i)
        fetch_buffer_q <= 101'b0;
    else if (branch_request_i)
        fetch_buffer_q <= 101'b0;
    else if (!fetch_in_valid_w || fetch_in_accept_o)
        fetch_buffer_q <= {fetch_in_fault_page_i, fetch_in_fault_fetch_i, fetch_in_pred_branch_i, fetch_in_instr_i, fetch_in_pc_i, fetch_in_valid_i};

    assign {fetch_in_fault_page_w, 
            fetch_in_fault_fetch_w, 
            fetch_in_pred_branch_w, 
            fetch_in_instr_raw_w, 
            fetch_in_pc_w, 
            fetch_in_valid_w} = fetch_buffer_q;

    assign fetch_in_instr_w = (fetch_in_fault_page_w | fetch_in_fault_fetch_w) ? 64'b0 : fetch_in_instr_raw_w;

    wire [7:0] info0_in_w;
    wire [9:0] info0_out_w;
    wire [7:0] info1_in_w;
    wire [9:0] info1_out_w;


    biriscv_decoder
    u_dec0
    (
         .valid_i(fetch_in_valid_w)
        ,.fetch_fault_i(fetch_in_fault_fetch_w | fetch_in_fault_page_w)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_in_instr_w[31:0])

        ,.invalid_o(info0_in_w[7])
        ,.exec_o(info0_in_w[6])
        ,.lsu_o(info0_in_w[5])
        ,.branch_o(info0_in_w[4])
        ,.mul_o(info0_in_w[3])
        ,.div_o(info0_in_w[2])
        ,.csr_o(info0_in_w[1])
        ,.rd_valid_o(info0_in_w[0])
    );

    biriscv_decoder
    u_dec1
    (
         .valid_i(fetch_in_valid_w)
        ,.fetch_fault_i(fetch_in_fault_fetch_w | fetch_in_fault_page_w)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_in_instr_w[63:32])

        ,.invalid_o(info1_in_w[7])
        ,.exec_o(info1_in_w[6])
        ,.lsu_o(info1_in_w[5])
        ,.branch_o(info1_in_w[4])
        ,.mul_o(info1_in_w[3])
        ,.div_o(info1_in_w[2])
        ,.csr_o(info1_in_w[1])
        ,.rd_valid_o(info1_in_w[0])
    );

    triha_fifo_queued_reference
    #( .OPC_INFO_W(10), .DEPTH(3) )
    u_fifo
    (
         .clk_i(clk_i)
        ,.rst_i(rst_i)

        ,.flush_i(branch_request_i)

        // Input side
        ,.push_i(fetch_in_valid_w)
        ,.pc_in_i(fetch_in_pc_w)
        ,.pred_in_i(fetch_in_pred_branch_w)
        ,.data_in_i(fetch_in_instr_w)
        ,.info0_in_i({info0_in_w, fetch_in_fault_page_w, fetch_in_fault_fetch_w})
        ,.info1_in_i({info1_in_w, fetch_in_fault_page_w, fetch_in_fault_fetch_w})
        ,.accept_o(fetch_in_accept_o)

        // Outputs
        ,.valid0_o(fetch_out0_valid_o)
        ,.pc0_out_o(fetch_out0_pc_o)
        ,.data0_out_o(fetch_out0_instr_o)
        ,.info0_out_o({fetch_out0_instr_invalid_o, fetch_out0_instr_exec_o,
                       fetch_out0_instr_lsu_o,     fetch_out0_instr_branch_o,
                       fetch_out0_instr_mul_o,     fetch_out0_instr_div_o,
                       fetch_out0_instr_csr_o,     fetch_out0_instr_rd_valid_o,
                       fetch_out0_fault_page_o,    fetch_out0_fault_fetch_o})
        ,.pop0_i(fetch_out0_accept_i)

        ,.valid1_o(fetch_out1_valid_o)
        ,.pc1_out_o(fetch_out1_pc_o)
        ,.data1_out_o(fetch_out1_instr_o)
        ,.info1_out_o({fetch_out1_instr_invalid_o, fetch_out1_instr_exec_o,
                       fetch_out1_instr_lsu_o,     fetch_out1_instr_branch_o,
                       fetch_out1_instr_mul_o,     fetch_out1_instr_div_o,
                       fetch_out1_instr_csr_o,     fetch_out1_instr_rd_valid_o,
                       fetch_out1_fault_page_o,    fetch_out1_fault_fetch_o})
        ,.pop1_i(fetch_out1_accept_i)
        ,.csr0_in_i(1'b0),.csr1_in_i(1'b0),.csr0_out_o(),.csr1_out_o()
    );
end
//-----------------------------------------------------------------
// 1 cycle frontend latency
//-----------------------------------------------------------------
else
begin
    wire [63:0] payload_in_w = (fetch_in_fault_page_i | fetch_in_fault_fetch_i) ? 64'b0 : fetch_in_instr_i;
    wire csr0_in_w, csr1_in_w, csr0_history_w, csr1_history_w;
    wire decoded_csr0_w, decoded_csr1_w;
    biriscv_decoder u_csr_hint0 (
        .valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(enable_muldiv_w),.opcode_i(payload_in_w[31:0]),
        .invalid_o(),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(csr0_in_w),.rd_valid_o()
    );
    biriscv_decoder u_csr_hint1 (
        .valid_i(1'b0),.fetch_fault_i(1'b0),.enable_muldiv_i(enable_muldiv_w),.opcode_i(payload_in_w[63:32]),
        .invalid_o(),.exec_o(),.lsu_o(),.branch_o(),.mul_o(),.div_o(),.csr_o(csr1_in_w),.rd_valid_o()
    );
    triha_fifo_queued_reference
    #( .OPC_INFO_W(2), .DEPTH(3) )
    u_fifo
    (
         .clk_i(clk_i)
        ,.rst_i(rst_i)

        ,.flush_i(branch_request_i)

        // Input side
        ,.push_i(fetch_in_valid_i)
        ,.pc_in_i(fetch_in_pc_i)
        ,.pred_in_i(fetch_in_pred_branch_i)
        ,.data_in_i(payload_in_w)
        ,.info0_in_i({fetch_in_fault_page_i, fetch_in_fault_fetch_i})
        ,.info1_in_i({fetch_in_fault_page_i, fetch_in_fault_fetch_i})
        ,.accept_o(fetch_in_accept_o)

        // Outputs
        ,.valid0_o(fetch_out0_valid_o)
        ,.pc0_out_o(fetch_out0_pc_o)
        ,.data0_out_o(fetch_out0_instr_o)
        ,.info0_out_o({fetch_out0_fault_page_o, fetch_out0_fault_fetch_o})
        ,.pop0_i(fetch_out0_accept_i)

        ,.valid1_o(fetch_out1_valid_o)
        ,.pc1_out_o(fetch_out1_pc_o)
        ,.data1_out_o(fetch_out1_instr_o)
        ,.info1_out_o({fetch_out1_fault_page_o, fetch_out1_fault_fetch_o})
        ,.pop1_i(fetch_out1_accept_i)
        ,.csr0_in_i(csr0_in_w),.csr1_in_i(csr1_in_w)
        ,.csr0_out_o(csr0_history_w),.csr1_out_o(csr1_history_w)
    );

    biriscv_decoder
    u_dec0
    (
         .valid_i(fetch_out0_valid_o)
        ,.fetch_fault_i(fetch_out0_fault_fetch_o | fetch_out0_fault_page_o)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_out0_instr_o)

        ,.invalid_o(fetch_out0_instr_invalid_o)
        ,.exec_o(fetch_out0_instr_exec_o)
        ,.lsu_o(fetch_out0_instr_lsu_o)
        ,.branch_o(fetch_out0_instr_branch_o)
        ,.mul_o(fetch_out0_instr_mul_o)
        ,.div_o(fetch_out0_instr_div_o)
        ,.csr_o(decoded_csr0_w)
        ,.rd_valid_o(fetch_out0_instr_rd_valid_o)
    );

    biriscv_decoder
    u_dec1
    (
         .valid_i(fetch_out1_valid_o)
        ,.fetch_fault_i(fetch_out1_fault_fetch_o | fetch_out1_fault_page_o)
        ,.enable_muldiv_i(enable_muldiv_w)
        ,.opcode_i(fetch_out1_instr_o)

        ,.invalid_o(fetch_out1_instr_invalid_o)
        ,.exec_o(fetch_out1_instr_exec_o)
        ,.lsu_o(fetch_out1_instr_lsu_o)
        ,.branch_o(fetch_out1_instr_branch_o)
        ,.mul_o(fetch_out1_instr_mul_o)
        ,.div_o(fetch_out1_instr_div_o)
        ,.csr_o(decoded_csr1_w)
        ,.rd_valid_o(fetch_out1_instr_rd_valid_o)
    );
    // Preserve original CSR classification even when the FIFO is empty.
    assign fetch_out0_instr_csr_o = fetch_out0_valid_o ? decoded_csr0_w :
        (csr0_history_w | fetch_out0_fault_fetch_o | fetch_out0_fault_page_o);
    assign fetch_out1_instr_csr_o = fetch_out1_valid_o ? decoded_csr1_w :
        (csr1_history_w | fetch_out1_fault_fetch_o | fetch_out1_fault_page_o);
end
endgenerate

endmodule

module triha_fifo_queued_reference
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
    parameter WIDTH   = 64,
    parameter DEPTH   = 2,
    parameter ADDR_W  = 1,
    parameter OPC_INFO_W = 10
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
     input                  clk_i
    ,input                  rst_i

    ,input                  flush_i

    // Input side
    ,input                  push_i
    ,input  [31:0]          pc_in_i
    ,input  [1:0]           pred_in_i
    ,input  [WIDTH-1:0]     data_in_i
    ,input [OPC_INFO_W-1:0] info0_in_i
    ,input [OPC_INFO_W-1:0] info1_in_i
    ,output                 accept_o

    // Outputs
    ,output                 valid0_o
    ,output  [31:0]         pc0_out_o
    ,output [(WIDTH/2)-1:0] data0_out_o
    ,output[OPC_INFO_W-1:0] info0_out_o
    ,input                  pop0_i

    ,output                 valid1_o
    ,output  [31:0]         pc1_out_o
    ,output [(WIDTH/2)-1:0] data1_out_o
    ,output[OPC_INFO_W-1:0] info1_out_o
    ,input                  pop1_i
    ,input                  csr0_in_i
    ,input                  csr1_in_i
    ,output                 csr0_out_o
    ,output                 csr1_out_o
);

// Compact a four-word instruction queue, keeping PC and all sideband fields
// with each word. Two outputs may cross an original 64-bit fetch boundary.
// No combinational push-through and no change to memory response latency.
localparam WORDS = 2*DEPTH;
reg [31:0] pc_q[0:WORDS-1];
reg [WIDTH/2-1:0] data_q[0:WORDS-1];
reg [OPC_INFO_W-1:0] info_q[0:WORDS-1];
reg csr_q[0:WORDS-1];
reg [ADDR_W+1:0] count_q;
wire pop_a_w = pop0_i && valid0_o;
wire pop_b_w = pop1_i && valid1_o;
wire push_w = push_i && accept_o;
// Fixed destination enables replace dynamic multi-write compaction.
reg remove_a_r,remove_b_r;
reg [ADDR_W+1:0] remaining_r;
always @* begin
    // Preserve the old procedural filtering when a pop condition is X:
    // an entry survives only when its removal condition is definitely false.
    remove_a_r=1'b1; if(!pop_a_w) remove_a_r=1'b0;
    remove_b_r=1'b1; if(!pop_b_w) remove_b_r=1'b0;
    remaining_r=count_q-remove_a_r-remove_b_r;
end
assign accept_o = count_q <= WORDS-2;
assign valid0_o = count_q != 0;
assign valid1_o = count_q > 1 && pc_q[1] == pc_q[0] + 32'd4;
assign pc0_out_o=pc_q[0]; assign pc1_out_o=pc_q[1];
assign data0_out_o=data_q[0]; assign data1_out_o=data_q[1];
assign info0_out_o=info_q[0]; assign info1_out_o=info_q[1];
assign csr0_out_o=csr_q[0]; assign csr1_out_o=csr_q[1];
always @(posedge clk_i or posedge rst_i)
if(rst_i) count_q<=0;
else if(flush_i) count_q<=0;
else begin
    count_q<=remaining_r;
    if(push_w) begin
        if(!pred_in_i[0]) count_q<=remaining_r+2;
        else count_q<=remaining_r+1;
    end
end
localparam PAYLOAD_W=32+WIDTH/2+OPC_INFO_W+1;
genvar entry;
generate for(entry=0;entry<WORDS;entry=entry+1) begin:g_entry
    wire [PAYLOAD_W-1:0] same_w={pc_q[entry],data_q[entry],info_q[entry],csr_q[entry]};
    wire [PAYLOAD_W-1:0] one_w,two_w,shift_w;
    if(entry+1<WORDS) begin:g_one
        assign one_w={pc_q[entry+1],data_q[entry+1],info_q[entry+1],csr_q[entry+1]};
    end else assign one_w=same_w;
    if(entry+2<WORDS) begin:g_two
        assign two_w={pc_q[entry+2],data_q[entry+2],info_q[entry+2],csr_q[entry+2]};
    end else assign two_w=same_w;
    // B-only dequeue preserves entry0 while compacting all later entries.
    assign shift_w=remove_a_r && remove_b_r ? two_w :
        ((entry==0 ? remove_a_r : (remove_a_r || remove_b_r)) ? one_w : same_w);
    always @(posedge clk_i or posedge rst_i)
    if(rst_i) begin
        pc_q[entry]<=0;data_q[entry]<=0;info_q[entry]<=0;csr_q[entry]<=0;
    end else if(flush_i) begin
        // Stored inactive payload history is retained across a flush.
    end else begin
        if(push_w && remaining_r==entry)
            {pc_q[entry],data_q[entry],info_q[entry],csr_q[entry]}<=
                {{pc_in_i[31:3],3'b000},data_in_i[WIDTH/2-1:0],info0_in_i,csr0_in_i};
        else if(push_w && !pred_in_i[0] && remaining_r+1==entry)
            {pc_q[entry],data_q[entry],info_q[entry],csr_q[entry]}<=
                {{pc_in_i[31:3],3'b100},data_in_i[WIDTH-1:WIDTH/2],info1_in_i,csr1_in_i};
        else if(remaining_r>entry)
            {pc_q[entry],data_q[entry],info_q[entry],csr_q[entry]}<=shift_w;
    end
end endgenerate
endmodule
