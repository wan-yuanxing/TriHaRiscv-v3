/* Registered redirect contract: no asynchronous PC bypass, no stale delivery. */
`timescale 1ns / 1ps
`ifndef CPU_FRONTEND_MODULE
`define CPU_FRONTEND_MODULE biriscv_frontend
`endif
module tb_frontend_redirect;
    reg clk=0, rst=1;
    reg branch=0, accept=1, consume=1;
    reg [31:0] target=0;
    reg response=0, pending=0;
    integer delay_count=0, cycles=0, delivered=0, redirects=0, dropped=0;
    reg [31:0] expected_pc=0, held_pc;
    reg checking=0;
    wire rd, valid0, valid1;
    wire [31:0] pc, pc0, pc1;
    always #5 clk=~clk;
    `CPU_FRONTEND_MODULE #(.SUPPORT_MMU(0), .SUPPORT_BRANCH_PREDICTION(0)) u_dut (
        .clk_i(clk), .rst_i(rst), .icache_accept_i(accept && !pending),
        .icache_valid_i(response), .icache_error_i(1'b0),
        .icache_inst_i(64'h00000013_00000013), .icache_page_fault_i(1'b0),
        .fetch0_accept_i(consume), .fetch1_accept_i(consume), .fetch_invalidate_i(1'b0),
        .branch_request_i(branch), .branch_pc_i(target), .branch_priv_i(2'b11),
        .branch_info_request_i(1'b0), .branch_info_is_taken_i(1'b0),
        .branch_info_is_not_taken_i(1'b0), .branch_info_source_i(32'b0),
        .branch_info_is_call_i(1'b0), .branch_info_is_ret_i(1'b0),
        .branch_info_is_jmp_i(1'b0), .branch_info_pc_i(32'b0),
        .icache_rd_o(rd), .icache_pc_o(pc),
        .fetch0_valid_o(valid0), .fetch0_pc_o(pc0),
        .fetch1_valid_o(valid1), .fetch1_pc_o(pc1),
        .icache_flush_o(), .icache_invalidate_o(), .icache_priv_o(),
        .fetch0_instr_o(), .fetch0_fault_fetch_o(), .fetch0_fault_page_o(),
        .fetch0_instr_exec_o(), .fetch0_instr_lsu_o(), .fetch0_instr_branch_o(),
        .fetch0_instr_mul_o(), .fetch0_instr_div_o(), .fetch0_instr_csr_o(),
        .fetch0_instr_rd_valid_o(), .fetch0_instr_invalid_o(),
        .fetch1_instr_o(), .fetch1_fault_fetch_o(), .fetch1_fault_page_o(),
        .fetch1_instr_exec_o(), .fetch1_instr_lsu_o(), .fetch1_instr_branch_o(),
        .fetch1_instr_mul_o(), .fetch1_instr_div_o(), .fetch1_instr_csr_o(),
        .fetch1_instr_rd_valid_o(), .fetch1_instr_invalid_o()
    );
    always @(posedge clk) if (!rst) begin
        cycles=cycles+1;
        if (cycles>1000) $fatal(1,"FRONTEND_FAIL timeout");
        response<=0;
        if (rd && accept && !pending) begin
            pending<=1;
            delay_count<=3;
        end else if (pending) begin
            if (delay_count==0) begin
                response<=1;
                pending<=0;
            end else delay_count<=delay_count-1;
        end
        if (branch) begin
            expected_pc=target;
            checking=1;
        end else if (checking && consume) begin
            if (valid0) begin
                if (pc0!==expected_pc) $fatal(1,"FRONTEND_FAIL stale0 pc=%h expected=%h",pc0,expected_pc);
                expected_pc=expected_pc+4;
                delivered=delivered+1;
            end
            if (valid1) begin
                if (pc1!==expected_pc) $fatal(1,"FRONTEND_FAIL stale1 pc=%h expected=%h",pc1,expected_pc);
                expected_pc=expected_pc+4;
                delivered=delivered+1;
            end
        end
        if (response && !u_dut.fetch_valid_w) dropped=dropped+1;
    end
    task redirect;
        input [31:0] new_pc;
        begin
            @(negedge clk);
            held_pc=u_dut.fetch_pc_f_w;
            branch=1;
            target=new_pc;
            #1;
            if (u_dut.fetch_pc_f_w!==held_pc)
                $fatal(1,"FRONTEND_FAIL combinational_redirect old=%h new=%h",held_pc,u_dut.fetch_pc_f_w);
            redirects=redirects+1;
            @(negedge clk);
            branch=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);
        rst=0;
        redirect(32'h80001000);
        wait(delivered>=4);
        wait(pending);
        redirect(32'h80002000);
        consume=0;
        repeat(12) @(negedge clk);
        accept=0;
        redirect(32'h80003000);
        redirect(32'h80004000);
        repeat(5) @(negedge clk);
        accept=1;
        consume=1;
        wait(delivered>=12);
        if (redirects!=4 || dropped==0) $fatal(1,"FRONTEND_FAIL coverage");
        $display("FRONTEND_PASS redirects=%0d delivered=%0d dropped=%0d",redirects,delivered,dropped);
        $finish;
    end
endmodule
