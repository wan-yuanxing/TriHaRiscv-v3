/* Fault address remains precise while unused bypass data ignores fault control. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
module tb_load_bypass;
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
    task check_fault_commit;
        begin
            if(u_dut.u_issue.pipe0_result_wb_w!==32'h80001000 ||
               u_dut.u_issue.pipe0_exception_wb_w!==`EXCEPTION_FAULT_LOAD ||
               u_dut.u_issue.pipe0_valid_wb_w!==0 || u_dut.u_issue.pipe0_rd_wb_w!==0)
                $fatal(1,"LOAD_BYPASS_FAIL fault_commit");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        force u_dut.u_lsu.resp_addr_w=32'h80001000;
        force u_dut.u_lsu.resp_load_w=1;
        force u_dut.u_lsu.resp_byte_w=0;
        force u_dut.u_lsu.resp_half_w=0;
        force u_dut.u_lsu.resp_signed_w=0;
        force u_dut.u_lsu.mem_unaligned_e2_q=0;
        force u_dut.u_lsu.mem_ack_i=1;
        force u_dut.u_lsu.mem_error_i=0;
        force u_dut.u_lsu.mem_data_rd_i=32'h11223344;
        force u_dut.u_issue.u_pipe0_ctrl.valid_e2_q=1;
        // Existing control layout: bit1=LOAD, bit7=RD_VALID.
        force u_dut.u_issue.u_pipe0_ctrl.ctrl_e2_q=10'h082;
        force u_dut.u_issue.u_pipe0_ctrl.opcode_e2_q=32'h00002283;
        force u_dut.u_issue.u_pipe0_ctrl.issue_stall_i=0;
        #1;
        if(u_dut.u_issue.pipe0_result_e2_w!==32'h11223344)
            $fatal(1,"LOAD_BYPASS_FAIL good_data");
        force u_dut.u_issue.u_pipe0_ctrl.issue_stall_i=1;
        #1;
        if(u_dut.u_issue.pipe0_result_e2_w!==32'h11223344 || u_dut.u_issue.pipe0_rd_e2_w!==0)
            $fatal(1,"LOAD_BYPASS_FAIL stall_changes_payload_or_keeps_tag");
        force u_dut.u_issue.u_pipe0_ctrl.issue_stall_i=0;
        force u_dut.u_lsu.mem_ack_i=0;
        #1;
        if(u_dut.u_issue.pipe0_result_e2_w!==32'h11223344)
            $fatal(1,"LOAD_BYPASS_FAIL ack_changes_forward_data");
        force u_dut.u_lsu.mem_ack_i=1;
        force u_dut.u_lsu.mem_error_i=1;
        #1;
        if(u_dut.u_issue.pipe0_result_e2_w!==32'h11223344)
            $fatal(1,"LOAD_BYPASS_FAIL fault_changes_forward_data");
        if(u_dut.u_lsu.writeback_value_o!==32'h80001000)
            $fatal(1,"LOAD_BYPASS_FAIL lost_badaddr");
        @(negedge clk); check_fault_commit;
        force u_dut.u_lsu.mem_data_rd_i=32'hxxxxxxxx;
        #1;
        if(u_dut.u_issue.pipe0_result_e2_w!==32'hxxxxxxxx)
            $fatal(1,"LOAD_BYPASS_FAIL unknown_payload");
        @(negedge clk); check_fault_commit;
        if(u_dut.u_csr.u_csrfile.csr_mtval_q!==32'h80001000)
            $fatal(1,"LOAD_BYPASS_FAIL mtval");
        $display("LOAD_BYPASS_PASS data_fault_split_invalid_x_mtval");
        $finish;
    end
endmodule
