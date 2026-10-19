/* Late stall/ack may block commit, but must not select speculative data. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
module tb_bypass_tag;
    reg clk=0, rst=1;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(0),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),.mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0),
        .mem_i_rd_o(),.mem_i_pc_o(),.mem_i_flush_o(),.mem_i_invalidate_o(),
        .mem_d_addr_o(),.mem_d_data_wr_o(),.mem_d_rd_o(),.mem_d_wr_o(),.mem_d_req_tag_o(),
        .mem_d_cacheable_o(),.mem_d_invalidate_o(),.mem_d_writeback_o(),.mem_d_flush_o()
    );
    task no_issue;
        begin
            if({u_dut.u_issue.exec0_opcode_valid_o,u_dut.u_issue.exec1_opcode_valid_o,
                u_dut.u_issue.lsu_opcode_valid_o,u_dut.u_issue.mul_opcode_valid_o,
                u_dut.u_issue.div_opcode_valid_o,u_dut.u_issue.csr_opcode_valid_o}!==6'b0)
                $fatal(1,"BYPASS_TAG_FAIL stalled_or_faulted_issue");
        end
    endtask
    initial begin
        // Stop the clock after reset to inspect combinational qualifications.
        repeat(4) begin #5;clk=1;#5;clk=0;end
        rst=0;
        force u_dut.u_issue.pc_x_q=32'h80000000;
        force u_dut.u_issue.fetch0_valid_i=1;
        force u_dut.u_issue.fetch0_pc_i=32'h80000000;
        force u_dut.u_issue.fetch0_instr_i=32'h006283b3;
        force u_dut.u_issue.fetch1_valid_i=0;
        force u_dut.u_issue.fetch0_instr_exec_i=1;
        force u_dut.u_issue.fetch0_instr_lsu_i=0;
        force u_dut.u_issue.fetch0_instr_csr_i=0;
        force u_dut.u_issue.fetch0_instr_mul_i=0;
        force u_dut.u_issue.fetch0_instr_div_i=0;
        force u_dut.u_issue.fetch0_instr_branch_i=0;
        force u_dut.u_issue.fetch0_instr_rd_valid_i=1;
        force u_dut.u_issue.lsu_stall_i=0;
        force u_dut.u_issue.u_pipe0_ctrl.valid_wb_q=1;
        force u_dut.u_issue.u_pipe0_ctrl.ctrl_wb_q=10'h080;
        force u_dut.u_issue.u_pipe0_ctrl.opcode_wb_q=32'h000002b3;
        force u_dut.u_issue.u_pipe0_ctrl.result_wb_q=32'hcafef00d;
        force u_dut.u_issue.u_pipe0_ctrl.valid_e2_q=1;
        force u_dut.u_issue.u_pipe0_ctrl.ctrl_e2_q=10'h082;
        force u_dut.u_issue.u_pipe0_ctrl.opcode_e2_q=32'h000004b3;
        force u_dut.u_issue.u_pipe0_ctrl.mem_bypass_e2_i=32'h1234cafe;
        force u_dut.u_issue.u_pipe0_ctrl.mem_complete_i=1;
        force u_dut.u_issue.u_pipe0_ctrl.mem_exception_e2_i=0;
        #1;
        if(u_dut.u_issue.opcode0_ra_operand_o!==32'hcafef00d)
            $fatal(1,"BYPASS_TAG_FAIL initial_wb_forward");
        force u_dut.u_issue.stall_w=1;
        #1;
        if(u_dut.u_issue.pipe0_rd_wb_w!==0 || u_dut.u_issue.pipe0_rd_e2_w!==0)
            $fatal(1,"BYPASS_TAG_FAIL issue_stall_did_not_block_commit_tags");
        no_issue;
        if(u_dut.u_issue.opcode0_ra_operand_o!==32'hcafef00d)
            $fatal(1,"BYPASS_TAG_FAIL wb_data_changes_when_issue_stalled");
        force u_dut.u_issue.u_pipe0_ctrl.mem_complete_i=0;
        release u_dut.u_issue.stall_w;
        #1;
        if(u_dut.u_issue.pipe0_rd_wb_w!==0 || u_dut.u_issue.pipe0_rd_e2_w!==0)
            $fatal(1,"BYPASS_TAG_FAIL memory_stall_did_not_block_commit_tags");
        no_issue;
        if(u_dut.u_issue.opcode0_ra_operand_o!==32'hcafef00d)
            $fatal(1,"BYPASS_TAG_FAIL wb_data_changes_on_ack");
        force u_dut.u_issue.fetch0_instr_i=32'h006483b3;
        #1; no_issue;
        if(u_dut.u_issue.opcode0_ra_operand_o!==32'h1234cafe)
            $fatal(1,"BYPASS_TAG_FAIL e2_data_changes_on_ack");
        force u_dut.u_issue.u_pipe0_ctrl.mem_complete_i=1;
        #1;
        if(u_dut.u_issue.opcode0_ra_operand_o!==32'h1234cafe ||
           u_dut.u_issue.exec0_opcode_valid_o!==1 || u_dut.u_issue.pipe0_rd_e2_w!==9)
            $fatal(1,"BYPASS_TAG_FAIL ready_forward_or_issue");
        force u_dut.u_issue.u_pipe0_ctrl.mem_exception_e2_i=`EXCEPTION_FAULT_LOAD;
        #1; no_issue;
        $display("BYPASS_TAG_PASS wb_e2_data_stable_commit_stall_fault_guard");
        $finish;
    end
endmodule
