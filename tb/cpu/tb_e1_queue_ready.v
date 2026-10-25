// Queue dequeue may proceed during a same-edge flush; younger execution may not.
`timescale 1ns/1ps
module tb_e1_queue_ready;
    reg clk=0,rst=1,run_clock=1,recovery=0;
    reg [31:0] a=32'h00500293,b=32'h00600313;
    reg [1:0] expected;
    integer n,checks=0;
    wire ai,ae,al,ab,am,ad,ac,ar,bi,be,bl,bb,bm,bd,bc,br;
    always #5 if(run_clock)clk=~clk;
    biriscv_decoder u_a(.valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(a),
        .invalid_o(ai),.exec_o(ae),.lsu_o(al),.branch_o(ab),.mul_o(am),.div_o(ad),.csr_o(ac),.rd_valid_o(ar));
    biriscv_decoder u_b(.valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(b),
        .invalid_o(bi),.exec_o(be),.lsu_o(bl),.branch_o(bb),.mul_o(bm),.div_o(bd),.csr_o(bc),.rd_valid_o(br));
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),.SUPPORT_REGFILE_XILINX(0)) u_dut(
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0));
    `define I u_dut.u_issue
    initial begin
        repeat(5)@(negedge clk);rst=0;run_clock=0;
        force `I.pc_x_q=32'h80000000;
        force `I.fetch0_valid_i=1;force `I.fetch1_valid_i=1;
        force `I.fetch0_pc_i=32'h80000000;force `I.fetch1_pc_i=32'h80000004;
        force `I.fetch0_instr_i=a;force `I.fetch1_instr_i=b;
        force `I.fetch0_fault_fetch_i=0;force `I.fetch0_fault_page_i=0;
        force `I.fetch1_fault_fetch_i=0;force `I.fetch1_fault_page_i=0;
        force `I.fetch0_instr_exec_i=ae;force `I.fetch0_instr_lsu_i=al;force `I.fetch0_instr_branch_i=ab;
        force `I.fetch0_instr_mul_i=am;force `I.fetch0_instr_div_i=ad;force `I.fetch0_instr_csr_i=ac;
        force `I.fetch0_instr_invalid_i=ai;force `I.fetch0_instr_rd_valid_i=ar;
        force `I.fetch1_instr_exec_i=be;force `I.fetch1_instr_lsu_i=bl;force `I.fetch1_instr_branch_i=bb;
        force `I.fetch1_instr_mul_i=bm;force `I.fetch1_instr_div_i=bd;force `I.fetch1_instr_csr_i=bc;
        force `I.fetch1_instr_invalid_i=bi;force `I.fetch1_instr_rd_valid_i=br;
        force `I.branch_csr_request_i=0;force `I.take_interrupt_i=0;force `I.squash_w=0;
        force `I.lsu_stall_i=0;force `I.stall_w=0;force `I.div_pending_q=0;force `I.csr_pending_q=0;
        force `I.resolved_fault_w=0;force `I.recovery_w=recovery;
        for(n=0;n<1024;n=n+1)begin
            a={n[11:0],5'b0,3'b0,5'd5,7'h13};
            case(n%4)
                0:b=32'h00600313; // independent ALU pair
                1:b=32'h00528313; // true same-packet RAW
                2:b=32'h00402303; // B load
                3:b=32'h00600293; // WAW
            endcase
            recovery=0;#1;expected={`I.fetch0_accept_o,`I.fetch1_accept_o};
            if(expected[1]!==1'b1)$fatal(1,"E1_QUEUE_READY_FAIL no_normal_primary");
            recovery=1;#1;checks=checks+1;
            if({`I.fetch0_accept_o,`I.fetch1_accept_o}!==expected)
                $fatal(1,"E1_QUEUE_READY_FAIL dequeue_waits_for_recovery n=%0d",n);
            if(`I.exec0_opcode_valid_o || `I.exec1_opcode_valid_o || `I.lsu_opcode_valid_o || `I.csr_opcode_valid_o)
                $fatal(1,"E1_QUEUE_READY_FAIL execution_not_cancelled");
        end
        $display("E1_QUEUE_READY_PASS checks=%0d",checks);$finish;
    end
    `undef I
endmodule
