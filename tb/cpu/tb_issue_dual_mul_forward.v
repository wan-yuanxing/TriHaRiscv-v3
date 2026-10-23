/* Shared narrow-product forwarding: both producer/consumer lanes and sources. */
`timescale 1ns/1ps
module tb_issue_dual_mul_forward #(parameter BROKEN=0);
    reg clk=0, rst=1, clock_run=1;
    reg [31:0] op_a=32'h00528333, op_b=32'h005283b3;
    reg [32:0] a=7,b=9;
    reg [31:0] expected;
    reg [31:0] rng=32'h151f07ba;
    reg producer=0, consumer=0;
    integer p,c,n,checks=0;
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
    task check;
        input issued;
        begin
            #1; checks=checks+1;
            if ((consumer ? `I.opcode_b_accept_r : `I.opcode_a_accept_r) !== issued)
                $fatal(1,"DUAL_MUL_FORWARD_FAIL accept producer=%0d consumer=%0d expected=%b",producer,consumer,issued);
            if (issued) begin
                if (consumer) begin
                    if (`I.opcode1_ra_operand_o !== expected || `I.opcode1_rb_operand_o !== expected)
                        $fatal(1,"DUAL_MUL_FORWARD_FAIL lane1 value expected=%h actual=%h/%h",expected,`I.opcode1_ra_operand_o,`I.opcode1_rb_operand_o);
                end else if (`I.opcode0_ra_operand_o !== expected || `I.opcode0_rb_operand_o !== expected)
                    $fatal(1,"DUAL_MUL_FORWARD_FAIL lane0 value expected=%h actual=%h/%h",expected,`I.opcode0_ra_operand_o,`I.opcode0_rb_operand_o);
            end
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst=0;clock_run=0;
        force `I.pc_x_q=32'h80000000;
        force `I.fetch0_valid_i=1;force `I.fetch0_pc_i=32'h80000000;force `I.fetch0_instr_i=op_a;
        force `I.fetch1_valid_i=consumer;force `I.fetch1_pc_i=32'h80000004;force `I.fetch1_instr_i=op_b;
        force `I.fetch0_fault_fetch_i=0;force `I.fetch0_fault_page_i=0;
        force `I.fetch1_fault_fetch_i=0;force `I.fetch1_fault_page_i=0;
        force `I.fetch0_instr_exec_i=1;force `I.fetch1_instr_exec_i=1;
        force `I.fetch0_instr_lsu_i=0;force `I.fetch1_instr_lsu_i=0;
        force `I.fetch0_instr_branch_i=0;force `I.fetch1_instr_branch_i=0;
        force `I.fetch0_instr_mul_i=0;force `I.fetch1_instr_mul_i=0;
        force `I.fetch0_instr_div_i=0;force `I.fetch1_instr_div_i=0;
        force `I.fetch0_instr_csr_i=0;force `I.fetch1_instr_csr_i=0;
        force `I.fetch0_instr_invalid_i=0;force `I.fetch1_instr_invalid_i=0;
        force `I.fetch0_instr_rd_valid_i=1;force `I.fetch1_instr_rd_valid_i=1;
        force `I.branch_csr_request_i=0;force `I.squash_w=0;force `I.take_interrupt_i=0;
        force `I.lsu_stall_i=0;force `I.stall_w=0;force `I.div_pending_q=0;force `I.csr_pending_q=0;
        force `I.pipe0_mul_e1_w=!producer;force `I.pipe1_mul_e1_w=producer;
        force `I.pipe0_load_e1_w=0;force `I.pipe1_load_e1_w=0;
        force `I.pipe0_store_e1_w=0;force `I.pipe1_store_e1_w=0;
        force `I.pipe0_rd_e1_w=producer ? 5'b0 : 5'd5;
        force `I.pipe1_rd_e1_w=producer ? 5'd5 : 5'b0;
        force `I.pipe0_opcode_e1_w=32'h027302b3;force `I.pipe1_opcode_e1_w=32'h027302b3;
        force `I.pipe0_rd_bypass_e2_w=0;force `I.pipe1_rd_bypass_e2_w=0;
        force `I.pipe0_rd_bypass_wb_w=0;force `I.pipe1_rd_bypass_wb_w=0;
        force u_dut.u_mul.operand_a_e1_q=a;force u_dut.u_mul.operand_b_e1_q=b;
        if(BROKEN) force u_dut.u_mul.partial_ll_w=0;
        for(p=0;p<2;p=p+1) begin
            producer=p;
            for(c=0;c<2;c=c+1) begin
                consumer=c;op_a=c ? 32'h00000513 : 32'h00528333;
                for(n=0;n<256;n=n+1) begin
                    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                    a={17'b0,rng[15:0]};b={17'b0,rng[31:16]};expected=a[31:0]*b[31:0];
                    check(1);
                end
                a=33'h10001;b=9;check(0);a=7;expected=63;
                force `I.pipe0_opcode_e1_w=32'h027312b3;force `I.pipe1_opcode_e1_w=32'h027312b3;check(0);
                force `I.pipe0_opcode_e1_w=32'h027322b3;force `I.pipe1_opcode_e1_w=32'h027322b3;check(0);
                force `I.pipe0_opcode_e1_w=32'h027332b3;force `I.pipe1_opcode_e1_w=32'h027332b3;check(0);
                force `I.pipe0_opcode_e1_w=32'h027302b3;force `I.pipe1_opcode_e1_w=32'h027302b3;
                force `I.stall_w=1;check(0);force `I.stall_w=0;
                force `I.lsu_stall_i=1;check(0);force `I.lsu_stall_i=0;
                force `I.squash_w=1;check(0);force `I.squash_w=0;
                force `I.branch_csr_request_i=1;check(0);force `I.branch_csr_request_i=0;
                // Older E2/WB data must not override this current E1 value.
                force `I.pipe0_rd_bypass_e2_w=5;force `I.pipe0_result_e2_w=32'hdeadbeef;
                force `I.pipe1_rd_bypass_wb_w=5;force `I.pipe1_result_wb_w=32'hacbd1357;
                check(1);
                force `I.pipe0_rd_bypass_e2_w=0;force `I.pipe1_rd_bypass_wb_w=0;
            end
        end
        // Early data belongs to the preceding E1 operation, never to a MUL
        // being issued now. A same-packet dependent B must remain blocked.
        consumer=1;op_a=32'h027302b3;
        force `I.pipe0_mul_e1_w=0;force `I.pipe1_mul_e1_w=0;
        force `I.pipe0_rd_e1_w=0;force `I.pipe1_rd_e1_w=0;
        force `I.fetch0_instr_exec_i=0;force `I.fetch0_instr_mul_i=1;
        check(0);
        $display("DUAL_MUL_FORWARD_PASS checks=%0d",checks);$finish;
    end
    `undef I
endmodule
