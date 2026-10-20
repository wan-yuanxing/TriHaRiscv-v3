/* E1 MUL bypass: independent numeric values, original MULH/load interlocks. */
`timescale 1ns/1ps
module tb_issue_mul_forward #(parameter BROKEN=0);
    reg clk=0,rst=1,run_clock=1;
    reg [31:0] op=32'h00128313;
    reg [32:0] a=7,b=9;
    reg [63:0] expected;
    reg [31:0] rng=32'h271828;
    integer index,checks=0;
    always #5 if(run_clock) clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(0),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0));
    `define I u_dut.u_issue
    task check;
        input issued;
        begin
            #1;checks=checks+1;
            if(`I.opcode_a_issue_r!==issued)
                $fatal(1,"MUL_FORWARD_FAIL issue expected=%b actual=%b",issued,`I.opcode_a_issue_r);
            if(issued && `I.opcode0_ra_operand_o!==expected[31:0])
                $fatal(1,"MUL_FORWARD_FAIL operand expected=%h actual=%h",expected[31:0],`I.opcode0_ra_operand_o);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);rst=0;run_clock=0;
        force `I.pc_x_q=32'h80000000;
        force `I.fetch0_valid_i=1;force `I.fetch0_pc_i=32'h80000000;force `I.fetch0_instr_i=op;
        force `I.fetch0_fault_fetch_i=0;force `I.fetch0_fault_page_i=0;
        force `I.fetch0_instr_exec_i=1;force `I.fetch0_instr_lsu_i=0;force `I.fetch0_instr_mul_i=0;
        force `I.fetch0_instr_div_i=0;force `I.fetch0_instr_csr_i=0;force `I.fetch0_instr_invalid_i=0;
        force `I.fetch0_instr_rd_valid_i=1;force `I.fetch1_valid_i=0;
        force `I.branch_csr_request_i=0;force `I.squash_w=0;force `I.take_interrupt_i=0;
        force `I.lsu_stall_i=0;force `I.stall_w=0;force `I.div_pending_q=0;force `I.csr_pending_q=0;
        force `I.pipe0_mul_e1_w=1;force `I.pipe0_load_e1_w=0;force `I.pipe0_store_e1_w=0;
        force `I.pipe1_mul_e1_w=0;force `I.pipe1_load_e1_w=0;force `I.pipe1_store_e1_w=0;
        force `I.pipe0_rd_e1_w=5;force `I.pipe1_rd_e1_w=0;
        force `I.pipe0_opcode_e1_w=32'h027302b3; // MUL x5,x6,x7
        force `I.pipe0_rd_bypass_e2_w=0;force `I.pipe0_rd_bypass_wb_w=0;
        force `I.pipe1_rd_bypass_e2_w=0;force `I.pipe1_rd_bypass_wb_w=0;
        force u_dut.u_mul.operand_a_e1_q=a;force u_dut.u_mul.operand_b_e1_q=b;
        if(BROKEN) force u_dut.u_mul.partial_ll_w=0;
        for(index=0;index<1024;index=index+1) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(index<512) begin a={17'b0,rng[15:0]};b={17'b0,rng[31:16]};end
            else begin a={1'b0,rng|32'h10000};b={1'b0,rng[15:0],rng[31:16]};end
            if(index==0) begin a=7;b=9;end
            if(index==1) begin a=33'h0ffff;b=33'h0ffff;end
            expected=a[31:0]*b[31:0];check(index<512);
        end
        a=7;b=9;expected=63;
        op=32'h00528333;check(1); // ADD x6,x5,x5: both operands use the product
        if(`I.opcode0_rb_operand_o!==expected[31:0]) $fatal(1,"MUL_FORWARD_FAIL source2");
        force `I.pc_x_q=32'h80000004;
        force `I.fetch0_valid_i=0;force `I.fetch1_valid_i=1;
        force `I.fetch1_pc_i=32'h80000004;force `I.fetch1_instr_i=op;
        force `I.fetch1_fault_fetch_i=0;force `I.fetch1_fault_page_i=0;
        force `I.fetch1_instr_exec_i=1;force `I.fetch1_instr_lsu_i=0;force `I.fetch1_instr_mul_i=0;
        force `I.fetch1_instr_div_i=0;force `I.fetch1_instr_csr_i=0;force `I.fetch1_instr_invalid_i=0;
        force `I.fetch1_instr_rd_valid_i=1;
        check(1); // odd fetch word uses the independent upper read/forward network
        if(`I.opcode0_rb_operand_o!==expected[31:0]) $fatal(1,"MUL_FORWARD_FAIL upper_source2");
        force `I.pipe0_opcode_e1_w=32'h027312b3;check(0); // MULH still waits
        force `I.pipe0_opcode_e1_w=32'h027322b3;check(0); // MULHSU
        force `I.pipe0_opcode_e1_w=32'h027332b3;check(0); // MULHU
        force `I.pipe0_mul_e1_w=0;force `I.pipe0_load_e1_w=1;check(0);
        force `I.pipe0_mul_e1_w=1;force `I.pipe0_load_e1_w=0;
        force `I.pipe0_opcode_e1_w=32'h027302b3;
        force `I.squash_w=1;check(0);force `I.squash_w=0;
        force `I.lsu_stall_i=1;check(0);
        $display("MUL_FORWARD_PASS checks=%0d",checks);$finish;
    end
    `undef I
endmodule
