`timescale 1ns/1ps
`include "biriscv_defs.v"
module tb_issue_lsu_prepare #(parameter BROKEN=0);
    reg clk=0, rst=1, clock_run=1;
    always #5 if(clock_run) clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0),
        .mem_i_pc_o(),.mem_i_invalidate_o(),.mem_i_flush_o(),.mem_i_rd_o(),
        .mem_d_flush_o(),.mem_d_writeback_o(),.mem_d_invalidate_o(),.mem_d_req_tag_o(),
        .mem_d_cacheable_o(),.mem_d_wr_o(),.mem_d_rd_o(),.mem_d_data_wr_o(),.mem_d_addr_o());
    `define I u_dut.u_issue
    reg [31:0] op_a=32'h00628463,op_b=32'h00752023,busy_mask=0;
    reg taken=0,present=1,class_b_lsu=1;
    integer checks=0;
    task check_b;
        input want;
        begin
            #1;checks=checks+1;
            if(`I.lsu_opcode_opcode_o!==op_b || `I.lsu_opcode_ra_operand_o!==32'h00010000 ||
               `I.lsu_opcode_rb_operand_o!==32'h12345678)
                $fatal(1,"LSU_PREPARE_FAIL B_payload_waits_for_permission");
            if(`I.lsu_opcode_valid_o!==want || u_dut.u_lsu.mem_wr_r!==(want?4'hf:4'h0) || u_dut.u_lsu.mem_rd_r!==0)
                $fatal(1,"LSU_PREPARE_FAIL unauthorized_or_missing_store expected=%b valid=%b wr=%h",want,`I.lsu_opcode_valid_o,u_dut.u_lsu.mem_wr_r);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=0;clock_run=0;
        force `I.pc_x_q=32'h80000000;
        force `I.fetch0_valid_i=1;force `I.fetch0_pc_i=32'h80000000;force `I.fetch0_instr_i=op_a;
        force `I.fetch1_valid_i=present;force `I.fetch1_pc_i=32'h80000004;force `I.fetch1_instr_i=op_b;
        force `I.fetch0_fault_fetch_i=0;force `I.fetch0_fault_page_i=0;
        force `I.fetch1_fault_fetch_i=0;force `I.fetch1_fault_page_i=0;
        force `I.fetch0_instr_exec_i=0;force `I.fetch1_instr_exec_i=0;
        force `I.fetch0_instr_lsu_i=0;force `I.fetch1_instr_lsu_i=class_b_lsu;
        force `I.fetch0_instr_branch_i=1;force `I.fetch1_instr_branch_i=0;
        force `I.fetch0_instr_mul_i=0;force `I.fetch1_instr_mul_i=0;
        force `I.fetch0_instr_div_i=0;force `I.fetch1_instr_div_i=0;
        force `I.fetch0_instr_csr_i=0;force `I.fetch1_instr_csr_i=0;
        force `I.fetch0_instr_invalid_i=0;force `I.fetch1_instr_invalid_i=0;
        force `I.fetch0_instr_rd_valid_i=0;force `I.fetch1_instr_rd_valid_i=0;
        force `I.scoreboard_r=busy_mask;
        force `I.branch_csr_request_i=0;force `I.squash_w=0;force `I.take_interrupt_i=0;
        force `I.lsu_stall_i=0;force `I.stall_w=0;force `I.div_pending_q=0;force `I.csr_pending_q=0;
        force `I.pipe0_load_e1_w=0;force `I.pipe1_load_e1_w=0;
        force `I.pipe0_store_e1_w=0;force `I.pipe1_store_e1_w=0;
        force `I.pipe0_mul_e1_w=0;force `I.pipe1_mul_e1_w=0;
        force `I.pipe0_load_e2_w=0;force `I.pipe1_load_e2_w=0;
        force `I.pipe0_mul_e2_w=0;force `I.pipe1_mul_e2_w=0;
        force `I.branch_d_exec0_request_i=taken;
        force `I.opcode1_ra_operand_o=32'h00010000;force `I.opcode1_rb_operand_o=32'h12345678;
        taken=1;check_b(0);taken=0;check_b(1);
        if(BROKEN)force `I.lsu_opcode_valid_o=1;
        busy_mask=32'h400;check_b(0);busy_mask=0;
        present=0;check_b(0);present=1;
        force `I.lsu_stall_i=1;check_b(0);force `I.lsu_stall_i=0;
        force `I.squash_w=1;check_b(0);force `I.squash_w=0;
        force `I.take_interrupt_i=1;check_b(0);force `I.take_interrupt_i=0;
        force `I.branch_csr_request_i=1;check_b(0);force `I.branch_csr_request_i=0;
        // Pure ALU A may issue while B is blocked; preparing B must not store.
        op_a=32'h00000593;force `I.fetch0_instr_branch_i=0;force `I.fetch0_instr_exec_i=1;
        force `I.fetch0_instr_rd_valid_i=1;busy_mask=32'h400;check_b(0);busy_mask=0;check_b(1);
        // An absent second slot may contain uninitialized decode data.
        // A real ALU instruction must still produce no LSU side effects.
        present=0;class_b_lsu=1'bx;#1;checks=checks+1;
        if(`I.lsu_opcode_valid_o!==0 || u_dut.u_lsu.mem_wr_r!==0 || u_dut.u_lsu.mem_rd_r!==0)
            $fatal(1,"LSU_PREPARE_FAIL invalid_B_unknown_class valid=%b wr=%h rd=%b",`I.lsu_opcode_valid_o,u_dut.u_lsu.mem_wr_r,u_dut.u_lsu.mem_rd_r);
        present=1;class_b_lsu=1;
        // CSR cache maintenance must retain A, even with an unissued LSU B.
        force `I.fetch0_instr_exec_i=0;force `I.fetch0_instr_csr_i=1;force `I.fetch0_instr_rd_valid_i=0;
        op_a={`CSR_DFLUSH,5'd5,3'b001,5'b0,7'h73};#1;checks=checks+1;
        if(`I.lsu_opcode_opcode_o!==op_a || `I.lsu_opcode_valid_o!==1 || !u_dut.u_lsu.dcache_flush_w)
            $fatal(1,"LSU_PREPARE_FAIL A_DFLUSH_lost");
        op_a={`CSR_DWRITEBACK,5'd5,3'b001,5'b0,7'h73};#1;checks=checks+1;
        if(`I.lsu_opcode_opcode_o!==op_a || `I.lsu_opcode_valid_o!==1 || !u_dut.u_lsu.dcache_writeback_w)
            $fatal(1,"LSU_PREPARE_FAIL A_DWRITEBACK_lost");
        op_a={`CSR_DINVALIDATE,5'd5,3'b001,5'b0,7'h73};#1;checks=checks+1;
        if(`I.lsu_opcode_opcode_o!==op_a || `I.lsu_opcode_valid_o!==1 || !u_dut.u_lsu.dcache_invalidate_w)
            $fatal(1,"LSU_PREPARE_FAIL A_DINVALIDATE_lost");
        $display("LSU_PREPARE_PASS checks=%0d payload_permission_and_CSR",checks);$finish;
    end
    `undef I
endmodule
