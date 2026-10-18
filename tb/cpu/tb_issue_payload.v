/* Kill/exception control must gate valid without changing the selected data. */
`timescale 1ns / 1ps
module tb_issue_payload;
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
    task check_data;
        begin
            if ({u_dut.u_issue.opcode0_opcode_o,u_dut.u_issue.opcode0_pc_o,
                 u_dut.u_issue.opcode0_rd_idx_o,u_dut.u_issue.opcode0_ra_idx_o,u_dut.u_issue.opcode0_rb_idx_o}
                !== {32'h00700293,32'h80000000,5'd5,5'd0,5'd7})
                $fatal(1,"ISSUE_PAYLOAD_FAIL kill_changes_payload opcode=%h",u_dut.u_issue.opcode0_opcode_o);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        force u_dut.u_issue.pc_x_q=32'h80000000;
        force u_dut.u_issue.fetch0_valid_i=1;
        force u_dut.u_issue.fetch0_pc_i=32'h80000000;
        force u_dut.u_issue.fetch0_instr_i=32'h00700293;
        force u_dut.u_issue.fetch1_valid_i=1;
        force u_dut.u_issue.fetch1_pc_i=32'h80000004;
        force u_dut.u_issue.fetch1_instr_i=32'h00000013;
        force u_dut.u_issue.squash_w=0;
        force u_dut.u_issue.branch_csr_request_i=0;
        #1; check_data;
        force u_dut.u_issue.squash_w=1;
        #1; check_data;
        if (u_dut.u_issue.exec0_opcode_valid_o!==0) $fatal(1,"ISSUE_PAYLOAD_FAIL squash_valid");
        force u_dut.u_issue.squash_w=0;
        force u_dut.u_issue.branch_csr_request_i=1;
        #1; check_data;
        if (u_dut.u_issue.exec0_opcode_valid_o!==0) $fatal(1,"ISSUE_PAYLOAD_FAIL csr_valid");
        $display("ISSUE_PAYLOAD_PASS squash_and_csr_gate_valid_only");
        $finish;
    end
endmodule
