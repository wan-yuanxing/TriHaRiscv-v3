`timescale 1ns/1ps
module tb_diagram_contract;
 tb_e1_branch_pair u_case();
 integer fd,checks=0;
 reg [31:0] expected0,expected1;
 reg check_result;
 initial begin fd=$fopen("cycle-contract.csv","w");$fdisplay(fd,"cycle,pop0,pop1,alu0,alu1,hold");end
 always @(posedge u_case.clk) begin
   check_result=0;
   if(!u_case.rst) begin
     if(u_case.u_dut.u_issue.fetch1_accept_o && !u_case.u_dut.u_issue.fetch0_accept_o)
       $fatal(1,"DIAGRAM_CONTRACT_FAIL B_consumed_without_A");
     expected0=u_case.u_dut.u_exec0.alu_p_w;
     expected1=u_case.u_dut.gen_dual_exec.u_exec1.alu_p_w;
     check_result=!u_case.u_dut.exec0_hold_w;
     checks=checks+1;
     $fdisplay(fd,"%0d,%b,%b,%h,%h,%b",checks,u_case.u_dut.u_issue.fetch0_accept_o,u_case.u_dut.u_issue.fetch1_accept_o,expected0,expected1,u_case.u_dut.exec0_hold_w);
   end
   #1;
   if(check_result && (u_case.u_dut.u_exec0.result_q!==expected0 || u_case.u_dut.gen_dual_exec.u_exec1.result_q!==expected1))
     $fatal(1,"DIAGRAM_CONTRACT_FAIL ALU_edge_mismatch");
 end
endmodule
