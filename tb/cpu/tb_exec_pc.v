/* Whole execution-unit cycle miter against the preserved original module. */
`timescale 1ns/1ps
`include "biriscv_defs.v"
module tb_exec_pc;
    parameter integer BROKEN=0;
    reg clk=0, rst=1;
    reg valid=0, invalid=0, hold=0;
    reg [31:0] opcode=0, pc=0, a=0, b=0;
    reg [4:0] rd=0, ra=0, rb=0;
    wire [136:0] expected, observed_raw;
    wire [136:0] observed = BROKEN ? {observed_raw[136:1],~observed_raw[0]} : observed_raw;
    integer checks=0, n;
    reg [31:0] rng=32'h31415926;
    always #5 clk=~clk;
`define INPUTS .clk_i(clk),.rst_i(rst),.opcode_valid_i(valid),.opcode_opcode_i(opcode), \
    .opcode_pc_i(pc),.opcode_invalid_i(invalid),.opcode_rd_idx_i(rd), \
    .opcode_ra_idx_i(ra),.opcode_rb_idx_i(rb),.opcode_ra_operand_i(a), \
    .opcode_rb_operand_i(b),.hold_i(hold)
`define OUTPUTS(p) .branch_request_o(p[136]),.branch_is_taken_o(p[135]), \
    .branch_is_not_taken_o(p[134]),.branch_source_o(p[133:102]), \
    .branch_is_call_o(p[101]),.branch_is_ret_o(p[100]),.branch_is_jmp_o(p[99]), \
    .branch_pc_o(p[98:67]),.branch_d_request_o(p[66]),.branch_d_pc_o(p[65:34]), \
    .branch_d_priv_o(p[33:32]),.writeback_value_o(p[31:0])
    biriscv_exec u_reference (`INPUTS,`OUTPUTS(expected));
    triha_exec u_candidate (`INPUTS,`OUTPUTS(observed_raw));
`undef INPUTS
`undef OUTPUTS
    task compare;
        begin
            checks=checks+1;
            if (observed !== expected) begin
                $display("EXEC_PC_FAIL check=%0d opcode=%h pc=%h a=%h b=%h hold=%b expected=%h actual=%h",
                    checks,opcode,pc,a,b,hold,expected,observed);
                $finish;
            end
        end
    endtask
    task advance;
        begin
            #1; compare;
            @(posedge clk); #0.1; compare;
        end
    endtask
    function [31:0] random_word;
        input [31:0] value;
        begin random_word=value*32'd1664525+32'd1013904223; end
    endfunction
    initial begin
        repeat(3) @(posedge clk);
        #0.1; compare;
        for(n=0;n<40000;n=n+1) begin
            @(negedge clk);
            rng=random_word(rng); opcode=rng;
            rng=random_word(rng); pc=rng;
            rng=random_word(rng); a=rng;
            rng=random_word(rng); b=rng;
            rd=rng[4:0];ra=rng[9:5];rb=rng[14:10];
            valid=~rng[15]; invalid=rng[16]; hold=rng[17]; rst=(n%4096==0);
            case(n%32)
                0:opcode=(opcode & ~`INST_ADD_MASK)|`INST_ADD;
                1:opcode=(opcode & ~`INST_SUB_MASK)|`INST_SUB;
                2:opcode=(opcode & ~`INST_AND_MASK)|`INST_AND;
                3:opcode=(opcode & ~`INST_OR_MASK)|`INST_OR;
                4:opcode=(opcode & ~`INST_XOR_MASK)|`INST_XOR;
                5:opcode=(opcode & ~`INST_SLL_MASK)|`INST_SLL;
                6:opcode=(opcode & ~`INST_SRL_MASK)|`INST_SRL;
                7:opcode=(opcode & ~`INST_SRA_MASK)|`INST_SRA;
                8:opcode=(opcode & ~`INST_SLT_MASK)|`INST_SLT;
                9:opcode=(opcode & ~`INST_SLTU_MASK)|`INST_SLTU;
                10:opcode=(opcode & ~`INST_ADDI_MASK)|`INST_ADDI;
                11:opcode=(opcode & ~`INST_ANDI_MASK)|`INST_ANDI;
                12:opcode=(opcode & ~`INST_ORI_MASK)|`INST_ORI;
                13:opcode=(opcode & ~`INST_XORI_MASK)|`INST_XORI;
                14:opcode=(opcode & ~`INST_SLLI_MASK)|`INST_SLLI;
                15:opcode=(opcode & ~`INST_SRLI_MASK)|`INST_SRLI;
                16:opcode=(opcode & ~`INST_SRAI_MASK)|`INST_SRAI;
                17:opcode=(opcode & ~`INST_SLTI_MASK)|`INST_SLTI;
                18:opcode=(opcode & ~`INST_SLTIU_MASK)|`INST_SLTIU;
                19:opcode=(opcode & ~`INST_LUI_MASK)|`INST_LUI;
                20:opcode=(opcode & ~`INST_AUIPC_MASK)|`INST_AUIPC;
                21:opcode=(opcode & ~`INST_JAL_MASK)|`INST_JAL;
                22:opcode=(opcode & ~`INST_JALR_MASK)|`INST_JALR;
                23:opcode=(opcode & ~`INST_BEQ_MASK)|`INST_BEQ;
                24:opcode=(opcode & ~`INST_BNE_MASK)|`INST_BNE;
                25:opcode=(opcode & ~`INST_BLT_MASK)|`INST_BLT;
                26:opcode=(opcode & ~`INST_BGE_MASK)|`INST_BGE;
                27:opcode=(opcode & ~`INST_BLTU_MASK)|`INST_BLTU;
                28:opcode=(opcode & ~`INST_BGEU_MASK)|`INST_BGEU;
            endcase
            if(n%17==0)pc=32'hfffffffc;
            if(n%19==0)pc=32'h7fffffff;
            if(n%23==0)a=b;
            if(n%29==0)a=32'h80000000;
            if(n%31==0)b=32'hffffffff;
            if(n%37==0)opcode[28]=1'bx;
            if(n%41==0)opcode[2]=1'bz;
            if(n%43==0)pc[7]=1'bx;
            if(n%47==0)a[13]=1'bz;
            advance;
        end
        $display("EXEC_PC_PASS checks=%0d vectors=40000 full_output_bits=137",checks);
        $finish;
    end
    initial begin #1000000; $display("EXEC_PC_FAIL timeout");$finish;end
endmodule
