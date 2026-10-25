`timescale 1ns/1ps
// Check both real execution-lane inputs; an unconnected port must fail.
module tb_dual_branch_zero_ports #(parameter RF_MODE = 0);
    tb_triha_core #(.DUAL_ISSUE(1)) u_tb ();
    defparam u_tb.u_dut.u_cpu.SUPPORT_REGFILE_XILINX = RF_MODE;
    `define C u_tb.u_dut.u_cpu
    initial begin
        #1;
        force `C.u_issue.opcode0_ra_zero_w = 1'b0;
        force `C.u_issue.opcode0_rb_zero_w = 1'b1;
        force `C.u_issue.upper_ra_zero_w = 1'b1;
        force `C.u_issue.upper_rb_zero_w = 1'b0;
        force `C.u_issue.opcode1_ra_operand_o = 32'b0;
        force `C.u_issue.opcode1_rb_operand_o = 32'h42;
        #1;
        if (`C.u_exec0.opcode_ra_zero_i !== 1'b0 ||
            `C.u_exec0.opcode_rb_zero_i !== 1'b1 ||
            `C.gen_dual_exec.u_exec1.opcode_ra_zero_i !== 1'b1 ||
            `C.gen_dual_exec.u_exec1.opcode_rb_zero_i !== 1'b0)
            $fatal(1, "PROFILE_FAIL zero-property lane connectivity");
        force `C.u_issue.upper_ra_zero_w = 1'b0;
        force `C.u_issue.upper_rb_zero_w = 1'b1;
        force `C.u_issue.opcode1_ra_operand_o = 32'h42;
        force `C.u_issue.opcode1_rb_operand_o = 32'b0;
        #1;
        if (`C.gen_dual_exec.u_exec1.opcode_ra_zero_i !== 1'b0 ||
            `C.gen_dual_exec.u_exec1.opcode_rb_zero_i !== 1'b1)
            $fatal(1, "PROFILE_FAIL zero-property lane polarity");
        $display("BRANCH_ZERO_PORTS_PASS");
        $finish;
    end
    `undef C
endmodule
