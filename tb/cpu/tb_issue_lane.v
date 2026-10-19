/* Data lane selection is independent of PC-hit/valid; issue stays fail-closed. */
`timescale 1ns / 1ps
module tb_issue_lane;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(0), .SUPPORT_SUPER(0), .SUPPORT_MMU(0)) u_dut (
        .clk_i(clk), .rst_i(rst), .intr_i(1'b0), .reset_vector_i(32'h80000000), .cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1), .mem_i_valid_i(1'b0), .mem_i_error_i(1'b0), .mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0), .mem_d_accept_i(1'b1), .mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0), .mem_d_resp_tag_i(11'b0),
        .mem_i_rd_o(), .mem_i_pc_o(), .mem_i_flush_o(), .mem_i_invalidate_o(),
        .mem_d_addr_o(), .mem_d_data_wr_o(), .mem_d_rd_o(), .mem_d_wr_o(), .mem_d_req_tag_o(),
        .mem_d_cacheable_o(), .mem_d_invalidate_o(), .mem_d_writeback_o(), .mem_d_flush_o()
    );
    task check_lane0;
        begin
            if ({u_dut.u_issue.opcode_a_r,u_dut.u_issue.opcode_a_pc_r,u_dut.u_issue.opcode_a_fault_r,
                 u_dut.u_issue.opcode_b_r,u_dut.u_issue.opcode_b_pc_r,u_dut.u_issue.opcode_b_fault_r}
                !== {32'h00700293,32'h80000000,2'b01,32'h00032383,32'h80000004,2'b10})
                $fatal(1,"ISSUE_LANE_FAIL pc_hit_or_valid_changes_lane0_data");
            if ({u_dut.u_issue.issue_a_exec_w,u_dut.u_issue.issue_a_lsu_w,u_dut.u_issue.csr_opcode_invalid_o}!==3'b100)
                $fatal(1,"ISSUE_LANE_FAIL lane0_class");
        end
    endtask
    task check_lane1;
        begin
            if ({u_dut.u_issue.opcode_a_r,u_dut.u_issue.opcode_a_pc_r,u_dut.u_issue.opcode_a_fault_r,
                 u_dut.u_issue.opcode_b_r,u_dut.u_issue.opcode_b_pc_r,u_dut.u_issue.opcode_b_fault_r}
                !== {32'h00032383,32'h80000004,2'b10,32'b0,32'b0,2'b0})
                $fatal(1,"ISSUE_LANE_FAIL pc_hit_or_valid_changes_lane1_data");
            if ({u_dut.u_issue.issue_a_exec_w,u_dut.u_issue.issue_a_lsu_w,u_dut.u_issue.csr_opcode_invalid_o}!==3'b011)
                $fatal(1,"ISSUE_LANE_FAIL lane1_class");
        end
    endtask
    task check_no_issue;
        begin
            if ({u_dut.u_issue.exec0_opcode_valid_o,u_dut.u_issue.exec1_opcode_valid_o,
                 u_dut.u_issue.lsu_opcode_valid_o,u_dut.u_issue.mul_opcode_valid_o,
                 u_dut.u_issue.div_opcode_valid_o,u_dut.u_issue.csr_opcode_valid_o,
                 u_dut.u_issue.fetch0_accept_o,u_dut.u_issue.fetch1_accept_o}!==8'b0)
                $fatal(1,"ISSUE_LANE_FAIL wrong_pc_or_empty_lane_issued");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        force u_dut.u_issue.pc_x_q=32'h80000010;
        force u_dut.u_issue.fetch0_valid_i=1;
        force u_dut.u_issue.fetch0_pc_i=32'h80000000;
        force u_dut.u_issue.fetch0_instr_i=32'h00700293;
        force u_dut.u_issue.fetch0_fault_page_i=0;
        force u_dut.u_issue.fetch0_fault_fetch_i=1;
        force u_dut.u_issue.fetch1_valid_i=1;
        force u_dut.u_issue.fetch1_pc_i=32'h80000004;
        force u_dut.u_issue.fetch1_instr_i=32'h00032383;
        force u_dut.u_issue.fetch1_fault_page_i=1;
        force u_dut.u_issue.fetch1_fault_fetch_i=0;
        force u_dut.u_issue.fetch0_instr_invalid_i=0;
        force u_dut.u_issue.fetch1_instr_invalid_i=1;
        force u_dut.u_issue.fetch0_instr_exec_i=1;
        force u_dut.u_issue.fetch0_instr_lsu_i=0;
        force u_dut.u_issue.fetch1_instr_exec_i=0;
        force u_dut.u_issue.fetch1_instr_lsu_i=1;
        force u_dut.u_issue.branch_csr_request_i=0;
        force u_dut.u_issue.squash_w=0;
        #1; check_lane0; check_no_issue;
        if(u_dut.u_issue.branch_request_o!==1 || u_dut.u_issue.branch_pc_o!==32'h80000010)
            $fatal(1,"ISSUE_LANE_FAIL wrong_pc_redirect");
        force u_dut.u_issue.squash_w=1;
        force u_dut.u_issue.pc_x_q=32'hc0000000;
        #1; check_lane0; check_no_issue;
        force u_dut.u_issue.fetch0_valid_i=0;
        force u_dut.u_issue.fetch1_valid_i=0;
        #1; check_lane0; check_no_issue;
        force u_dut.u_issue.pc_x_q=32'h80000000;
        force u_dut.u_issue.fetch0_valid_i=1;
        force u_dut.u_issue.fetch1_valid_i=1;
        #1; check_lane0;
        if({u_dut.u_issue.opcode_a_valid_r,u_dut.u_issue.opcode_b_valid_r}!==2'b11)
            $fatal(1,"ISSUE_LANE_FAIL matching_lane0_eligibility");
        force u_dut.u_issue.pc_x_q=32'h80000004;
        #1; check_lane1;
        if({u_dut.u_issue.opcode_a_valid_r,u_dut.u_issue.opcode_b_valid_r}!==2'b10)
            $fatal(1,"ISSUE_LANE_FAIL matching_lane1_eligibility");
        force u_dut.u_issue.fetch1_valid_i=0;
        force u_dut.u_issue.squash_w=0;
        #1; check_lane1; check_no_issue;
        force u_dut.u_issue.fetch1_valid_i=1;
        force u_dut.u_issue.pc_x_q=32'h80000014;
        #1; check_lane1; check_no_issue;
        if({u_dut.u_issue.opcode_a_valid_r,u_dut.u_issue.opcode_b_valid_r}!==2'b00)
            $fatal(1,"ISSUE_LANE_FAIL stale_packet_eligibility");
        $display("ISSUE_LANE_PASS raw_lane_pc_hit_valid_cancel");
        $finish;
    end
endmodule
