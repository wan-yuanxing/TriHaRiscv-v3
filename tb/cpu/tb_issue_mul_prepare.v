`timescale 1ns/1ps
`include "biriscv_defs.v"
module tb_issue_mul_prepare #(parameter BROKEN=0);
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
    reg [31:0] op_a=32'h00628463,op_b=32'h027503b3,busy_mask=0;
    reg taken=0,present=1,class_b_mul=1;
    reg [32:0] expected_a,expected_b;
    integer checks=0,mode;
    task tick;
        begin #2;clk=1;#1;clk=0;#1;end
    endtask
    task tags;
        input a,b;
        begin
            checks=checks+1;
            if(`I.pipe0_mul_e1_w!==a || `I.pipe1_mul_e1_w!==b)
                $fatal(1,"MUL_PREPARE_FAIL producer_tags actual=%b%b expected=%b%b",`I.pipe0_mul_e1_w,`I.pipe1_mul_e1_w,a,b);
        end
    endtask
    task check_b;
        input want;
        begin
            #1;checks=checks+1;
            if(`I.mul_opcode_opcode_o!==op_b || `I.mul_opcode_ra_operand_o!==32'h00010000 ||
               `I.mul_opcode_rb_operand_o!==32'h12345678)
                $fatal(1,"MUL_PREPARE_FAIL B_payload_waits_for_permission");
            if(`I.mul_opcode_valid_o!==want)
                $fatal(1,"MUL_PREPARE_FAIL permission expected=%b actual=%b",want,`I.mul_opcode_valid_o);
            if(u_dut.u_mul.operand_a_r!==33'h000010000 || u_dut.u_mul.operand_b_r!==33'h012345678)
                $fatal(1,"MUL_PREPARE_FAIL multiplier_input");
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
        force `I.fetch0_instr_lsu_i=0;force `I.fetch1_instr_lsu_i=0;
        force `I.fetch0_instr_branch_i=1;force `I.fetch1_instr_branch_i=0;
        force `I.fetch0_instr_mul_i=0;force `I.fetch1_instr_mul_i=class_b_mul;
        force `I.fetch0_instr_div_i=0;force `I.fetch1_instr_div_i=0;
        force `I.fetch0_instr_csr_i=0;force `I.fetch1_instr_csr_i=0;
        force `I.fetch0_instr_invalid_i=0;force `I.fetch1_instr_invalid_i=0;
        force `I.fetch0_instr_rd_valid_i=0;force `I.fetch1_instr_rd_valid_i=1;
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
        if(BROKEN)force `I.mul_opcode_ra_operand_o=0;
        busy_mask=32'h400;check_b(0);busy_mask=0;
        present=0;check_b(0);present=1;
        force `I.lsu_stall_i=1;check_b(0);force `I.lsu_stall_i=0;
        force `I.squash_w=1;check_b(0);force `I.squash_w=0;
        force `I.take_interrupt_i=1;check_b(0);force `I.take_interrupt_i=0;
        force `I.branch_csr_request_i=1;check_b(0);force `I.branch_csr_request_i=0;
        // Pure ALU A may issue while B is blocked; preparing B must not issue a multiply.
        op_a=32'h00000593;force `I.fetch0_instr_branch_i=0;force `I.fetch0_instr_exec_i=1;
        force `I.fetch0_instr_rd_valid_i=1;busy_mask=32'h400;check_b(0);busy_mask=0;check_b(1);
        // An absent second slot may contain uninitialized decode data.
        // A real ALU instruction must still produce no MUL issue.
        present=0;class_b_mul=1'bx;#1;checks=checks+1;
        if(`I.mul_opcode_valid_o!==0 )
            $fatal(1,"MUL_PREPARE_FAIL invalid_B_unknown_class valid=%b",`I.mul_opcode_valid_o);
        present=1;class_b_mul=1;
        // A LSU may pair with B MUL; A MUL always retains its own payload.
        op_a=32'h00b62023;force `I.fetch0_instr_exec_i=0;force `I.fetch0_instr_lsu_i=1;
        force `I.fetch0_instr_rd_valid_i=0;check_b(1);
        force `I.fetch0_instr_lsu_i=0;force `I.fetch0_instr_mul_i=1;
        force `I.fetch0_instr_rd_valid_i=1;
        force `I.opcode0_ra_operand_o=32'h87654321;force `I.opcode0_rb_operand_o=32'h80000000;
        op_a=32'h027513b3;#1;checks=checks+1;
        if(`I.mul_opcode_opcode_o!==op_a || `I.mul_opcode_valid_o!==1 ||
           u_dut.u_mul.operand_a_r!==33'h187654321 || u_dut.u_mul.operand_b_r!==33'h180000000)
            $fatal(1,"MUL_PREPARE_FAIL A_MULH_lost");
        op_a=32'h027523b3;#1;checks=checks+1;
        if(`I.mul_opcode_opcode_o!==op_a || u_dut.u_mul.operand_a_r!==33'h187654321 ||
           u_dut.u_mul.operand_b_r!==33'h080000000)
            $fatal(1,"MUL_PREPARE_FAIL A_MULHSU_lost");
        op_a=32'h027533b3;#1;checks=checks+1;
        if(`I.mul_opcode_opcode_o!==op_a || u_dut.u_mul.operand_a_r!==33'h087654321 ||
           u_dut.u_mul.operand_b_r!==33'h080000000)
            $fatal(1,"MUL_PREPARE_FAIL A_MULHU_lost");
        // Exercise real sequential multiplier capture and real E1 producer tags.
        release `I.pipe0_mul_e1_w;release `I.pipe1_mul_e1_w;
        present=0;
        for(mode=0;mode<4;mode=mode+1)begin
            op_a=32'h027503b3|(mode<<12);
            rst=1;tick;rst=0;tick;tags(1,0);
            expected_a=(mode==1 || mode==2) ? 33'h187654321 : 33'h087654321;
            expected_b=mode==1 ? 33'h180000000 : 33'h080000000;
            checks=checks+1;
            if(u_dut.u_mul.operand_a_e1_q!==expected_a || u_dut.u_mul.operand_b_e1_q!==expected_b)
                $fatal(1,"MUL_PREPARE_FAIL A_clock_sign mode=%0d",mode);
        end
        release `I.opcode0_ra_operand_o;release `I.opcode0_rb_operand_o;
        force `I.opcode1_ra_operand_o=32'h1234;force `I.opcode1_rb_operand_o=32'h56;
        force `I.fetch0_instr_mul_i=0;force `I.fetch0_instr_exec_i=1;
        op_a=32'h00000593;op_b=32'h027503b3;present=1;
        rst=1;tick;rst=0;tick;tags(0,1);
        if(u_dut.u_mul.operand_a_e1_q!==33'h1234 || u_dut.u_mul.operand_b_e1_q!==33'h56)
            $fatal(1,"MUL_PREPARE_FAIL B_clock_capture");
        op_a=32'h00138493;present=0;#1;checks=checks+1;
        if(`I.opcode0_ra_operand_o!==32'h61d78 || `I.opcode_a_issue_r!==1 || `I.opcode_a_accept_r!==1)
            $fatal(1,"MUL_PREPARE_FAIL real_early_consumer value=%h",`I.opcode0_ra_operand_o);
        force `I.stall_w=1;tick;tags(0,1);
        if(u_dut.u_mul.operand_a_e1_q!==33'h1234 || u_dut.u_mul.operand_b_e1_q!==33'h56)
            $fatal(1,"MUL_PREPARE_FAIL held_data");
        force `I.stall_w=0;tick;tags(0,0);checks=checks+1;
        if(`I.pipe0_opcode_e1_w!==32'h00138493 || `I.u_pipe0_ctrl.valid_e1_q!==1)
            $fatal(1,"MUL_PREPARE_FAIL consumer_not_captured");
        // Prepared but cancelled arithmetic must not forward without a producer.
        for(mode=0;mode<5;mode=mode+1)begin
            rst=1;tick;rst=0;busy_mask=0;present=1;taken=0;
            op_a=32'h00628463;
            force `I.fetch0_instr_exec_i=0;force `I.fetch0_instr_mul_i=0;
            force `I.fetch0_instr_branch_i=1;force `I.fetch0_instr_rd_valid_i=0;
            if(mode==0)taken=1;
            if(mode==1)busy_mask=32'h400;
            if(mode==2)force `I.take_interrupt_i=1;
            if(mode==3)force `I.squash_w=1;
            if(mode==4)begin
                op_a=32'h027503b3;present=0;
                force `I.fetch0_instr_branch_i=0;force `I.fetch0_instr_mul_i=1;
                force `I.fetch0_instr_rd_valid_i=1;force `I.take_interrupt_i=1;
            end
            tick;tags(0,0);
            busy_mask=0;taken=0;force `I.take_interrupt_i=0;force `I.squash_w=0;
            force `I.fetch0_instr_mul_i=0;force `I.fetch0_instr_branch_i=0;
            force `I.fetch0_instr_exec_i=1;force `I.fetch0_instr_rd_valid_i=1;
            op_a=32'h00138493;present=0;#1;checks=checks+1;
            if(`I.opcode0_ra_operand_o!==0)
                $fatal(1,"MUL_PREPARE_FAIL cancelled_product_forwarded mode=%0d",mode);
        end
        $display("MUL_PREPARE_PASS checks=%0d payload_permission_sign_and_real_capture",checks);$finish;
    end
    `undef I
endmodule
