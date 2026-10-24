`timescale 1ns/1ps
module tb_issue_packet_hazard #(parameter BROKEN=0);
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
    reg [4:0] a_rd=0,b_ra=0,b_rb=0,b_rd=0;
    reg alloc=0;
    reg [2:0] roles=0;
    reg [31:0] mask, rng=32'habc73981;
    reg expected;
    integer n,j,checks=0;
    task check;
        begin
            // Independent old mechanism: conditional indexed bit insertion.
            mask=0;
            if(alloc && |a_rd)mask[a_rd]=1'b1;
            expected=(roles[0] && |b_ra && mask[b_ra]) ||
                     (roles[1] && |b_rb && mask[b_rb]) ||
                     (roles[2] && |b_rd && mask[b_rd]);
            #1;checks=checks+1;
            if(`I.same_packet_busy_r !== expected)
                $fatal(1,"PACKET_HAZARD_FAIL alloc=%b a=%b b=%d/%d/%d roles=%b got=%b expected=%b",alloc,a_rd,b_ra,b_rb,b_rd,roles,`I.same_packet_busy_r,expected);
        end
    endtask
    task check_b_fire;
        input want;
        begin
            #1;checks=checks+1;
            if(`I.opcode_b_issue_r !== want || `I.opcode_b_accept_r !== want)
                $fatal(1,"PACKET_HAZARD_FAIL B_fire expected=%b actual=%b/%b",want,`I.opcode_b_issue_r,`I.opcode_b_accept_r);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=0;clock_run=0;
        force `I.issue_a_rd_idx_w=a_rd;force `I.issue_a_sb_alloc_w=alloc;
        force `I.issue_b_ra_idx_w=b_ra;force `I.issue_b_rb_idx_w=b_rb;force `I.issue_b_rd_idx_w=b_rd;
        force `I.b_roles_w=roles;
        force `I.squash_w=1;
        for(n=0;n<8192;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;
            a_rd=rng[4:0];b_ra=rng[9:5];b_rb=rng[14:10];b_rd=rng[19:15];roles=rng[22:20];alloc=rng[23];
            if(n%3==0)b_ra=a_rd;
            if(n%5==0)b_rb=a_rd;
            if(n%7==0)b_rd=a_rd;
            if(n%11==0)alloc=1'bx;
            if(n%13==0)a_rd=5'b001x1;
            if(n%17==0)a_rd=5'bxxxxx;
            if(n%19==0)alloc=1'bz;
            check;
        end
        alloc=1;a_rd=5;b_ra=5;b_rb=0;b_rd=0;roles=1;
        if(BROKEN)force `I.same_packet_busy_r=0;
        check;
        // Actual issue permissions are tested separately from operand/oracle checks.
        a_rd=10;b_ra=0;b_rb=0;b_rd=11;alloc=1;roles=7;
        force `I.issue_a_ra_idx_w=0;force `I.issue_a_rb_idx_w=0;
        force `I.opcode_a_valid_r=1;force `I.opcode_b_valid_r=1;
        force `I.issue_a_exec_w=1;force `I.issue_b_exec_w=1;
        force `I.issue_a_lsu_w=0;force `I.issue_b_lsu_w=0;
        force `I.issue_a_branch_w=0;force `I.issue_b_branch_w=0;
        force `I.issue_a_mul_w=0;force `I.issue_b_mul_w=0;
        force `I.issue_a_div_w=0;force `I.issue_b_div_w=0;
        force `I.issue_a_csr_w=0;force `I.issue_b_csr_w=0;
        force `I.pipe0_load_e1_w=0;force `I.pipe1_load_e1_w=0;
        force `I.pipe0_load_e2_w=0;force `I.pipe1_load_e2_w=0;
        force `I.pipe0_mul_e1_w=0;force `I.pipe1_mul_e1_w=0;
        force `I.pipe0_mul_e2_w=0;force `I.pipe1_mul_e2_w=0;
        force `I.pipe0_store_e1_w=0;force `I.pipe1_store_e1_w=0;
        force `I.take_interrupt_i=0;force `I.branch_csr_request_i=0;
        force `I.lsu_stall_i=0;force `I.stall_w=0;
        force `I.div_pending_q=0;force `I.csr_pending_q=0;
        force `I.squash_w=0;check_b_fire(1);
        force `I.opcode_a_valid_r=0;check_b_fire(0);force `I.opcode_a_valid_r=1;
        force `I.opcode_b_valid_r=0;check_b_fire(0);force `I.opcode_b_valid_r=1;
        force `I.take_interrupt_i=1;check_b_fire(0);force `I.take_interrupt_i=0;
        force `I.branch_csr_request_i=1;check_b_fire(0);force `I.branch_csr_request_i=0;
        force `I.squash_w=1;check_b_fire(0);force `I.squash_w=0;
        force `I.lsu_stall_i=1;check_b_fire(0);force `I.lsu_stall_i=0;
        force `I.stall_w=1;check_b_fire(0);force `I.stall_w=0;
        force `I.div_pending_q=1;check_b_fire(0);force `I.div_pending_q=0;
        force `I.csr_pending_q=1;check_b_fire(0);force `I.csr_pending_q=0;
        b_ra=a_rd;check_b_fire(0);b_ra=0;
        b_rd=a_rd;check_b_fire(0);b_rd=11;
        alloc=1'bx;check_b_fire(1);
        alloc=1;a_rd=0;b_rd=0;check_b_fire(1);
        $display("PACKET_HAZARD_PASS checks=%0d old_indexed_write_equivalence",checks);$finish;
    end
    `undef I
endmodule
