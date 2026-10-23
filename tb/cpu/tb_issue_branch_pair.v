/* ISA vectors exercise actual issue gates, including true dependency guards. */
`timescale 1ns/1ps
module tb_issue_branch_pair #(parameter DUAL_ISSUE=1, BROKEN=0);
    reg clk=0, rst=1, clock_run=1;
    reg [31:0] op_a=32'h13, op_b=32'h13, busy=0;
    integer checks=0, f, n;
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
                $fatal(1,"BRANCH_PAIR_FAIL op=%h a=%h b=%h expected=%b actual=%b",op_a,av,bv,expected,`I.opcode_b_accept_r);
            if (`I.opcode_b_accept_r && !`I.opcode_a_accept_r)
                $fatal(1,"BRANCH_PAIR_FAIL B_without_A");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0; clock_run=0;
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
        if(BROKEN) force `I.branch_d_exec0_request_i=0;
        for(f=0;f<8;f=f+1) if(f!=2 && f!=3) begin
            op_a=32'h00730463 | (f<<12); // branch x6,x7,+8
            for(n=0;n<64;n=n+1) begin
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                av=rng;bv=(n%3==0) ? rng : ~rng;
                case(f)
                    0:taken=(av==bv); 1:taken=(av!=bv);
                    4:taken=($signed(av)<$signed(bv));5:taken=($signed(av)>=$signed(bv));
                    6:taken=(av<bv);7:taken=(av>=bv);
                endcase
                op_b=32'h00150513;check_pair(!taken); // ALU
                op_b=32'h00052583;check_pair(!taken); // load
                op_b=32'h00b52023;check_pair(!taken); // store
                op_b=32'h02b50533;check_pair(!taken); // multiply
            end
        end
        op_a=32'h00730463; av=1;bv=2;op_b=32'h00150513;
        busy=32'h40;check_pair(0);busy=0; // real branch source hazard
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
        $display("BRANCH_PAIR_PASS checks=%0d",checks);$finish;
    end
    `undef I
endmodule
