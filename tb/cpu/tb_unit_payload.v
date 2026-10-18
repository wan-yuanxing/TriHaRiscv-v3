/* Data flops sample independently of late valid; side effects remain qualified. */
`timescale 1ns / 1ps
module tb_unit_payload #(parameter integer TEST_CSR=0);
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
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        if (TEST_CSR==0) begin
            force u_dut.u_mul.hold_i=0;
            force u_dut.u_mul.opcode_valid_i=0;
            force u_dut.u_mul.opcode_opcode_i=32'h02728333;
            force u_dut.u_mul.opcode_ra_operand_i=32'd7;
            force u_dut.u_mul.opcode_rb_operand_i=32'd9;
            @(negedge clk);
            if (u_dut.u_mul.operand_a_e1_q!==33'd7 || u_dut.u_mul.operand_b_e1_q!==33'd9)
                $fatal(1,"UNIT_PAYLOAD_FAIL multiplier_zero_on_invalid");
        end else begin
            force u_dut.u_csr.opcode_valid_i=0;
            force u_dut.u_csr.opcode_opcode_i=32'h340392f3;
            force u_dut.u_csr.opcode_ra_idx_i=5'd7;
            force u_dut.u_csr.opcode_ra_operand_i=32'd11;
            force u_dut.u_csr.opcode_invalid_i=0;
            force u_dut.u_csr.u_csrfile.csr_mscratch_q=32'h12345678;
            @(negedge clk);
            if (u_dut.u_csr.rd_result_e1_q!==32'h12345678 || u_dut.u_csr.csr_wdata_e1_q!==32'd11)
                $fatal(1,"UNIT_PAYLOAD_FAIL csr_zero_on_invalid");
            if (u_dut.u_csr.rd_valid_e1_q!==0 || u_dut.u_csr.exception_e1_q!==0)
                $fatal(1,"UNIT_PAYLOAD_FAIL csr_side_effect_on_invalid");
        end
        $display("UNIT_PAYLOAD_PASS csr=%0d",TEST_CSR);
        $finish;
    end
endmodule
