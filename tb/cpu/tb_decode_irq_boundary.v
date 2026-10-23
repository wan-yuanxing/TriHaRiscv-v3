/* CSR classification follows compacted words; idle history cannot block a
 * subsequently returned ALU packet from taking a pending interrupt. */
`timescale 1ns/1ps
module tb_decode_irq_boundary #(parameter BROKEN=0);
    reg clk=0,rst=1,push=0,pop0=0,pop1=0,flush=0;
    reg [63:0] data=64'h340025f334002573;
    reg [31:0] pc=32'h80001000,expected_pc=32'h80001000;
    integer checks=0;
    always #5 clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0),
        .mem_i_pc_o(),.mem_i_invalidate_o(),.mem_i_flush_o(),.mem_i_rd_o(),
        .mem_d_flush_o(),.mem_d_writeback_o(),.mem_d_invalidate_o(),.mem_d_req_tag_o(),
        .mem_d_cacheable_o(),.mem_d_wr_o(),.mem_d_rd_o(),.mem_d_data_wr_o(),.mem_d_addr_o());
    `define D u_dut.u_frontend.u_decode
    `define I u_dut.u_issue
    task check_ready;
        input blocked;
        begin
            #1;checks=checks+1;
            if(`I.interrupt_inhibit_o !== blocked)
                $fatal(1,"DECODE_IRQ_FAIL inhibit expected=%b actual=%b",blocked,`I.interrupt_inhibit_o);
            @(negedge clk);#1;
            if(u_dut.u_csr.take_interrupt_o !== !blocked)
                $fatal(1,"DECODE_IRQ_FAIL pending_interrupt_not_delivered");
        end
    endtask
    initial begin
        force `D.fetch_in_valid_i=push;force `D.fetch_in_instr_i=data;force `D.fetch_in_pc_i=pc;
        force `D.fetch_in_pred_branch_i=0;force `D.fetch_in_fault_fetch_i=0;force `D.fetch_in_fault_page_i=0;
        force `D.fetch_out0_accept_i=pop0;force `D.fetch_out1_accept_i=pop1;force `D.branch_request_i=flush;
        force `I.pc_x_q=expected_pc;force `I.csr_pending_q=0;force `I.squash_w=0;force `I.branch_csr_request_i=0;
        force `I.lsu_stall_i=1; // Observe decoding without executing arbitrary CSR payloads.
        force u_dut.u_csr.interrupt_w=32'h800;
        repeat(5) @(negedge clk);rst=0;push=1;
        @(negedge clk);push=0;check_ready(1);
        pop0=1;expected_pc=32'h80001004;
        @(negedge clk);pop0=0;check_ready(1);
        pop0=1;
        @(negedge clk);pop0=0;#1;
        if(`D.fetch_out0_valid_o || `D.fetch_out1_valid_o) $fatal(1,"DECODE_IRQ_FAIL not_empty");
        // Redirect while the retained idle payload is CSR. A delayed response
        // must replace it with an ALU packet and release interrupt inhibition.
        flush=1;@(negedge clk);flush=0;repeat(8) @(negedge clk);
        pc=32'h80002000;expected_pc=pc;data=64'h0000001300000013;push=1;
        @(negedge clk);push=0;
        if(BROKEN) force `I.interrupt_inhibit_o=1;
        check_ready(0);
        $display("DECODE_IRQ_PASS checks=%0d",checks);$finish;
    end
    `undef D
    `undef I
endmodule
