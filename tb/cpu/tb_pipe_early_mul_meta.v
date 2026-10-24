/* Clocked reset-reachable oracle for the original three bypass-tag expressions. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
module tb_pipe_early_mul_meta;
    parameter BROKEN=0,NEW_META=0;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg valid=0, accept=0, hold=0, lsu=0, csr=0, div=0, mul=0, branch=0;
    reg rd_valid=0, irq=0, taken=0, mem_complete=1, div_complete=1;
    reg flush_e2=0, flush_wb=0;
    reg [31:0] opcode=0, target=0, data=0;
    reg [5:0] issue_fault=0, csr_fault=0, mem_fault=0;
    wire [4:0] tag_e1, tag_e2, tag_wb;
    integer n, checks=0, e1_live=0, e2_live=0, wb_live=0;
    reg [31:0] rng=32'h52a7139b;
    reg [4:0] expect_e1, expect_e2, expect_wb;
    triha_pipe_ctrl u_dut (
        .clk_i(clk),.rst_i(rst),.issue_valid_i(valid),.issue_accept_i(accept),
        .issue_stall_i(hold),.issue_lsu_i(lsu),.issue_csr_i(csr),
        .issue_div_i(div),.issue_mul_i(mul),.issue_branch_i(branch),
        .issue_rd_valid_i(rd_valid),.issue_rd_i(opcode[11:7]),
        .issue_exception_i(issue_fault),.take_interrupt_i(irq),
        .issue_branch_taken_i(taken),.issue_branch_target_i(target),
        .issue_pc_i(32'h80000100),.issue_opcode_i(opcode),
        .issue_operand_ra_i(data),.issue_operand_rb_i(~data),
        .alu_result_e1_i(data),.csr_result_value_e1_i(data),
        .csr_result_write_e1_i(csr),.csr_result_wdata_e1_i(data),
        .csr_result_exception_e1_i(csr_fault),.mem_complete_i(mem_complete),
        .mem_result_e2_i(data),.mem_bypass_e2_i(data),.mem_exception_e2_i(mem_fault),
        .mul_result_e2_i(data),.div_complete_i(div_complete),.div_result_i(data),
        .squash_e1_e2_i(flush_e2),.squash_wb_i(flush_wb),
        .rd_e1_o(tag_e1),.rd_bypass_e2_o(tag_e2),.rd_bypass_wb_o(tag_wb)
    );
    wire observed_low;
    generate if(NEW_META)begin:g_new_meta
        assign observed_low=u_dut.mul_low_e1_o;
        initial if(BROKEN)force u_dut.mul_low_e1_o=0;
    end else begin:g_old_expression
        assign observed_low=((u_dut.opcode_e1_q & `INST_MUL_MASK)==`INST_MUL);
    end endgenerate
    task check_tags;
        begin
            expect_e1={5{u_dut.ctrl_e1_q[7]}} & u_dut.opcode_e1_q[11:7];
            expect_e2={5{u_dut.valid_e2_q && u_dut.ctrl_e2_q[7]}} & u_dut.opcode_e2_q[11:7];
            expect_wb={5{u_dut.valid_wb_q && u_dut.ctrl_wb_q[7]}} & u_dut.opcode_wb_q[11:7];
            if(observed_low!==((u_dut.opcode_e1_q & `INST_MUL_MASK)==`INST_MUL))
                $fatal(1,"EARLY_META_FAIL low_opcode n=%0d opcode=%h got=%b",n,u_dut.opcode_e1_q,observed_low);
            checks=checks+1;
            if ({tag_e1,tag_e2,tag_wb} !== {expect_e1,expect_e2,expect_wb})
                $fatal(1,"EARLY_META_FAIL n=%0d actual=%h/%h/%h expected=%h/%h/%h",n,tag_e1,tag_e2,tag_wb,expect_e1,expect_e2,expect_wb);
            if (|tag_e1) e1_live=e1_live+1;
            if (|tag_e2) e2_live=e2_live+1;
            if (|tag_wb) wb_live=wb_live+1;
        end
    endtask
    initial begin
        repeat(3) begin @(posedge clk);#1;check_tags;end
        @(negedge clk);rst=0;

        for(n=0;n<20000;n=n+1)begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            opcode=rng;data=~rng;target={rng[31:2],2'b0};
            case(n%8)
                0:opcode=32'h02b50533;1:opcode=32'h02b51533;
                2:opcode=32'h02b52533;3:opcode=32'h02b53533;
                4:opcode=32'h02b54533;5:opcode=32'h00150513;6:opcode=0;
            endcase
            valid=(n%9!=0);accept=(n%7!=0);hold=(n%11==0);
            {lsu,csr,div,mul,branch}=0;
            case(n%6) 0:lsu=1;1:csr=1;2:div=1;3:mul=1;4:branch=1;endcase
            rd_valid=rng[12];irq=(n%31==0);taken=rng[13];
            mem_complete=rng[14];div_complete=rng[15];
            flush_e2=(n%37==0);flush_wb=(n%41==0);
            issue_fault=(n%17==0) ? n[5:0] : 0;
            csr_fault=(n%19==0) ? n[5:0] : 0;
            mem_fault=(n%13==0) ? n[5:0] : 0;
            // Partial unknown/Z opcodes and controls, without forcing stage state.
            case(n%127)
                1:opcode[8]=1'bx; 2:opcode[9]=1'bz;
                3:rd_valid=1'bx; 4:rd_valid=1'bz;
                5:irq=1'bx; 6:issue_fault=6'b00x000;
                7:mem_fault=6'b0z0000; 8:csr_fault=6'b000x00;
                9:hold=1'bx; 10:valid=1'bx; 11:accept=1'bx;
                12:flush_e2=1'bx;13:flush_wb=1'bx;14:opcode[31]=1'bx;15:opcode[25]=1'bz;
            endcase
            if(n%251==0) target[0]=1;
            if(n%997==0)rst=1;else rst=0;
            @(posedge clk);#1;check_tags;
            // Late completion changes must not alter registered data tags.
            mem_complete=~mem_complete;div_complete=~div_complete;#1;check_tags;
        end
        if(e1_live<1000 || e2_live<1000 || wb_live<1000)
            $fatal(1,"EARLY_META_FAIL insufficient_live_coverage %0d/%0d/%0d",e1_live,e2_live,wb_live);
        $display("EARLY_META_PASS checks=%0d live=%0d/%0d/%0d",checks,e1_live,e2_live,wb_live);
        $finish;
    end
endmodule
