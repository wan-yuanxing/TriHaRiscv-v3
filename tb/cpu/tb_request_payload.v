/* Request payload ignores late valid, but an unaccepted request stays stable. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
module tb_request_payload;
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
    task check_held;
        begin
            if(u_dut.u_lsu.mem_addr_o!==32'h80001124 || u_dut.u_lsu.mem_data_wr_o!==0 ||
               u_dut.u_lsu.mem_rd_o!==1 || u_dut.u_lsu.mem_wr_o!==0 || u_dut.u_lsu.mem_cacheable_o!==1)
                $fatal(1,"REQUEST_PAYLOAD_FAIL stalled_request_changed");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        force u_dut.u_lsu.mem_accept_i=0;
        force u_dut.u_lsu.mem_ack_i=0;
        force u_dut.u_lsu.mem_error_i=0;
        force u_dut.u_lsu.opcode_valid_i=0;
        force u_dut.u_lsu.opcode_opcode_i=32'h12432283;
        force u_dut.u_lsu.opcode_ra_operand_i=32'h80001000;
        force u_dut.u_lsu.opcode_rb_operand_i=32'h89abcdef;
        #1;
        if(u_dut.u_lsu.mem_addr_r!==32'h80001124)
            $fatal(1,"REQUEST_PAYLOAD_FAIL valid_changes_address_format");
        force u_dut.u_lsu.opcode_valid_i=1;
        @(negedge clk); check_held;
        force u_dut.u_lsu.opcode_valid_i=0;
        force u_dut.u_lsu.opcode_opcode_i=32'h00732023;
        force u_dut.u_lsu.opcode_ra_operand_i=32'h80002000;
        #1;
        if(u_dut.u_lsu.mem_data_r!==32'h89abcdef || u_dut.u_lsu.mem_wr_r!==0)
            $fatal(1,"REQUEST_PAYLOAD_FAIL valid_changes_store_data_or_enables_store");
        repeat(3) begin @(negedge clk); check_held; end
        force u_dut.u_lsu.mem_accept_i=1;
        @(negedge clk);
        force u_dut.u_lsu.mem_ack_i=1;
        force u_dut.u_lsu.mem_error_i=1;
        #1;
        if(u_dut.u_lsu.writeback_value_o!==32'h80001124 ||
           u_dut.u_lsu.writeback_exception_o!==`EXCEPTION_FAULT_LOAD)
            $fatal(1,"REQUEST_PAYLOAD_FAIL response_tag_or_badaddr");
        @(negedge clk);
        if({u_dut.u_lsu.mem_rd_o,u_dut.u_lsu.mem_wr_o,u_dut.u_lsu.mem_invalidate_o,
            u_dut.u_lsu.mem_writeback_o,u_dut.u_lsu.mem_flush_o}!==8'b0)
            $fatal(1,"REQUEST_PAYLOAD_FAIL fault_did_not_cancel");
        $display("REQUEST_PAYLOAD_PASS raw_data_stall_hold_fault_cancel");
        $finish;
    end
endmodule
