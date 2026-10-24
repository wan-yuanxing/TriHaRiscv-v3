/* ISA vectors exercise actual issue gates, including true dependency guards. */
`timescale 1ns/1ps
module tb_issue_zero_pair #(parameter DUAL_ISSUE=1, BROKEN=0);
    reg clk=0, rst=1, clock_run=1;
    reg [31:0] op_a=32'h13, op_b=32'h13, busy=0;
    integer checks=0, f, n, shape;
    reg [31:0] av=0,bv=0,rng=32'h1231abcd;
    reg taken;
    wire ai,ae,al,ab,am,ad,ac,ar,bi,be,bl,bb,bm,bd,bc,br;
    always #5 if (clock_run) clk=~clk;
    biriscv_decoder u_a (.valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(op_a),
        .invalid_o(ai),.exec_o(ae),.lsu_o(al),.branch_o(ab),.mul_o(am),.div_o(ad),.csr_o(ac),.rd_valid_o(ar));
    biriscv_decoder u_b (.valid_i(1'b1),.fetch_fault_i(1'b0),.enable_muldiv_i(1'b1),.opcode_i(op_b),
        .invalid_o(bi),.exec_o(be),.lsu_o(bl),.branch_o(bb),.mul_o(bm),.div_o(bd),.csr_o(bc),.rd_valid_o(br));
    triha_cpu #(.SUPPORT_DUAL_ISSUE(DUAL_ISSUE),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0),
        .mem_i_pc_o(),.mem_i_invalidate_o(),.mem_i_flush_o(),.mem_i_rd_o(),
        .mem_d_flush_o(),.mem_d_writeback_o(),.mem_d_invalidate_o(),.mem_d_req_tag_o(),
        .mem_d_cacheable_o(),.mem_d_wr_o(),.mem_d_rd_o(),.mem_d_data_wr_o(),.mem_d_addr_o());
    `define I u_dut.u_issue
    task check_pair;
        input expected;
        begin
            #1; checks=checks+1;
            if (`I.opcode_b_accept_r !== expected)
                $fatal(1,"ZERO_PAIR_FAIL op=%h a=%h b=%h expected=%b actual=%b",op_a,av,bv,expected,`I.opcode_b_accept_r);
            if (`I.opcode_b_accept_r && !`I.opcode_a_accept_r)
                $fatal(1,"ZERO_PAIR_FAIL B_without_A");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0; clock_run=0;
        force `I.pc_x_q=32'h80000000;
        force `I.fetch0_valid_i=1;force `I.fetch1_valid_i=1;
        force `I.fetch0_pc_i=32'h80000000;force `I.fetch1_pc_i=32'h80000004;
        force `I.fetch0_instr_i=op_a;force `I.fetch1_instr_i=op_b;
        force `I.opcode_a_r=op_a; force `I.opcode_b_r=op_b;
        force `I.opcode_a_valid_r=1; force `I.opcode_b_valid_r=0;
        force `I.opcode_a_fault_r=0; force `I.opcode_b_fault_r=0;
        force `I.issue_a_exec_w=ae; force `I.issue_a_lsu_w=al; force `I.issue_a_branch_w=ab;
        force `I.issue_a_mul_w=am; force `I.issue_a_div_w=ad; force `I.issue_a_csr_w=ac;
        force `I.issue_a_invalid_w=ai; force `I.issue_a_sb_alloc_w=ar;
        force `I.issue_b_exec_w=be; force `I.issue_b_lsu_w=bl; force `I.issue_b_branch_w=bb;
        force `I.issue_b_mul_w=bm; force `I.issue_b_div_w=bd; force `I.issue_b_csr_w=bc;
        force `I.issue_b_invalid_w=bi; force `I.issue_b_sb_alloc_w=br;
        force `I.squash_w=0; force `I.branch_csr_request_i=0; force `I.take_interrupt_i=0;
        force `I.lsu_stall_i=0; force `I.stall_w=0; force `I.div_pending_q=0; force `I.csr_pending_q=0;
        force `I.pipe0_load_e1_w=0; force `I.pipe0_store_e1_w=0; force `I.pipe0_mul_e1_w=0;
        force `I.pipe1_load_e1_w=0; force `I.pipe1_store_e1_w=0; force `I.pipe1_mul_e1_w=0;
        force `I.scoreboard_r=busy;
        force `I.opcode_b_valid_r=1;
        force `I.issue_a_ra_value_w=av; force `I.issue_a_rb_value_w=bv;
        force `I.pipe0_rd_e1_w=0; force `I.pipe1_rd_e1_w=0;
        force `I.pipe0_rd_bypass_e2_w=0;force `I.pipe1_rd_bypass_e2_w=0;
        force `I.pipe0_rd_bypass_wb_w=0;force `I.pipe1_rd_bypass_wb_w=0;
        force `I.opcode_a_pc_r=32'h80000000;force `I.opcode_b_pc_r=32'h80000004;
        // Decoder and execution-unit comparator remain real. Independent oracle
        // uses Verilog signed comparison rather than the execution subtraction.
        if(BROKEN) force `I.branch_pair_w=1;
        for(f=0;f<8;f=f+1) if(f!=2 && f!=3) begin
            for(shape=0;shape<4;shape=shape+1)begin
            op_a=32'h00730463 | (f<<12);
            if(shape==1 || shape==3)op_a[19:15]=0;
            if(shape==2 || shape==3)op_a[24:20]=0;
            for(n=0;n<64;n=n+1) begin
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                av=rng;bv=(n%3==0) ? rng : ~rng;
                if(shape==1 || shape==3)av=0;
                if(shape==2 || shape==3)bv=0;
                if(f<2 && n==31 && shape==2)av=32'h000000x0;
                if(f<2 && n==32 && shape==1)bv=32'h000000z0;
                case(f)
                    0:taken=(av==bv); 1:taken=(av!=bv);
                    4:taken=($signed(av)<$signed(bv));5:taken=($signed(av)>=$signed(bv));
                    6:taken=(av<bv);7:taken=(av>=bv);
                endcase
                op_b=32'h00150513;check_pair((f<2 && shape!=0 && taken===1'b0)); // ALU
                op_b=32'h00052583;check_pair((f<2 && shape!=0 && taken===1'b0)); // load
                op_b=32'h00b52023;check_pair((f<2 && shape!=0 && taken===1'b0)); // store
                op_b=32'h02b50533;check_pair((f<2 && shape!=0 && taken===1'b0)); // multiply
            end
            end
        end
        op_a=32'h00030463; av=1;bv=0;op_b=32'h00150513;
        busy=0;check_pair(1);
        busy=32'h40;check_pair(0);busy=0; // real branch source hazard
        busy=32'h400;check_pair(0);busy=0; // B source/destination still waits
        force `I.opcode_b_valid_r=0;check_pair(0);force `I.opcode_b_valid_r=1;
        force `I.opcode_a_valid_r=0;check_pair(0);force `I.opcode_a_valid_r=1;
        force `I.opcode_a_fault_r=1;check_pair(0);force `I.opcode_a_fault_r=0;
        force `I.opcode_b_fault_r=1;check_pair(0);force `I.opcode_b_fault_r=0;
        force `I.take_interrupt_i=1;check_pair(0);force `I.take_interrupt_i=0;
        force `I.squash_w=1;check_pair(0);force `I.squash_w=0;
        force `I.branch_csr_request_i=1;check_pair(0);force `I.branch_csr_request_i=0;
        force `I.lsu_stall_i=1;check_pair(0);force `I.lsu_stall_i=0;
        force `I.stall_w=1;check_pair(0);force `I.stall_w=0;
        op_b=32'h00730463;check_pair(0); // two branches forbidden
        op_b=32'h34002573;check_pair(0); // CSR forbidden
        op_b=32'h02b54533;check_pair(0); // divider forbidden
        op_b=32'hffffffff;check_pair(0); // illegal forbidden
        op_a=32'h0080006f;op_b=32'h00150513;check_pair(0); // JAL forbidden
        op_a=32'h00030067;check_pair(0); // JALR forbidden
        // A real zero-branch/B-MUL sample followed by an issuing consumer.
        // Leave arithmetic E1 data and producer registers unforced.
        release `I.pipe0_mul_e1_w;release `I.pipe1_mul_e1_w;
        release `I.pipe0_rd_e1_w;release `I.pipe1_rd_e1_w;
        force `I.issue_b_ra_value_w=32'h1234;force `I.issue_b_rb_value_w=32'h56;
        op_a=32'h00001463;op_b=32'h02b50533; // bne x0,x0,+8; mul x10,x10,x11
        check_pair(1);clock_run=1;
        @(negedge clk);#1;checks=checks+1;
        if(`I.pipe1_mul_e1_w!==1 || u_dut.u_mul.operand_a_e1_q!==33'h1234 ||
           u_dut.u_mul.operand_b_e1_q!==33'h56)
            $fatal(1,"ZERO_PAIR_FAIL real_branch_mul_capture");
        op_a=32'h00150493;force `I.opcode_b_valid_r=0;#1;checks=checks+1;
        if(`I.opcode0_ra_operand_o!==32'h61d78 || `I.opcode_a_issue_r!==1 || `I.opcode_a_accept_r!==1)
            $fatal(1,"ZERO_PAIR_FAIL early_consumer_issue");
        @(negedge clk);#1;checks=checks+1;
        if(`I.pipe0_opcode_e1_w!==32'h00150493 || `I.u_pipe0_ctrl.valid_e1_q!==1)
            $fatal(1,"ZERO_PAIR_FAIL early_consumer_capture");
        $display("ZERO_PAIR_PASS checks=%0d",checks);$finish;
    end
    `undef I
endmodule
