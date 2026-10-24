/* Exhaustive independent exception-presence oracle. The wide selected vector
 * and scalar squash must use the original procedural selector semantics.
 */
`timescale 1ns/1ps
`include "biriscv_defs.v"
module tb_pipe_exception_scalar #(parameter BROKEN=0);
    reg clk=0,rst=1,clock_run=1;
    reg valid=0,complete=0,stall=0;
    reg [`PCINFO_W-1:0] ctrl=0;
    reg [5:0] stored=0,memory=0,expected_vector;
    reg expected_scalar;
    integer a,b,m,checks=0;
    always #5 if(clock_run)clk=~clk;
    triha_pipe_ctrl u_dut (
        .clk_i(clk),.rst_i(rst),.issue_stall_i(stall),
        .squash_e1_e2_i(1'b0),.squash_wb_i(1'b0),
        .mem_complete_i(complete),.mem_exception_e2_i(memory));
    task check;
        begin
            #1;checks=checks+1;
            if(valid && (ctrl[`PCINFO_LOAD] || ctrl[`PCINFO_STORE]) && complete)
                expected_vector=memory;
            else expected_vector=stored;
            expected_scalar=|expected_vector;
            if(u_dut.exception_e2_r!==expected_vector || u_dut.squash_e1_e2_o!==expected_scalar)
                $fatal(1,"PIPE_EXCEPTION_FAIL check=%0d expected=%h/%b actual=%h/%b",checks,expected_vector,expected_scalar,u_dut.exception_e2_r,u_dut.squash_e1_e2_o);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;clock_run=0;
        force u_dut.valid_e2_q=valid;
        force u_dut.ctrl_e2_q=ctrl;
        force u_dut.exception_e2_q=stored;
        force u_dut.squash_e1_e2_q=0;
        if(BROKEN)force u_dut.squash_e1_e2_o=0;
        for(a=0;a<64;a=a+1)for(b=0;b<64;b=b+1)for(m=0;m<16;m=m+1)begin
            stored=a;memory=b;valid=m[0];complete=m[1];
            ctrl[`PCINFO_LOAD]=m[2];ctrl[`PCINFO_STORE]=m[3];check;
        end
        stored=0;memory=1;ctrl=0;ctrl[`PCINFO_LOAD]=1;complete=1;valid=1'bx;check;
        valid=1;complete=1'bx;check;
        complete=1;valid=1'bz;check;
        valid=1;complete=1'bz;check;
        complete=1;ctrl[`PCINFO_LOAD]=1'bx;check;
        ctrl[`PCINFO_LOAD]=1;stored=6'b00000x;memory=0;check;
        memory=6'b00000x;check;
        valid=0;check;
        // Squash history must hold across a stalled cycle and clear on advance.
        release u_dut.squash_e1_e2_q;
        valid=0;stored=1;memory=0;complete=0;clock_run=1;
        @(negedge clk);#1;checks=checks+1;
        if(u_dut.squash_e1_e2_q!==1 || u_dut.squash_e1_e2_o!==1)
            $fatal(1,"PIPE_EXCEPTION_FAIL history_capture");
        stored=0;stall=1;
        @(negedge clk);#1;checks=checks+1;
        if(u_dut.squash_e1_e2_q!==1 || u_dut.squash_e1_e2_o!==1)
            $fatal(1,"PIPE_EXCEPTION_FAIL history_stall");
        stall=0;
        @(negedge clk);#1;checks=checks+1;
        if(u_dut.squash_e1_e2_q!==0 || u_dut.squash_e1_e2_o!==0)
            $fatal(1,"PIPE_EXCEPTION_FAIL history_clear");
        $display("PIPE_EXCEPTION_PASS checks=%0d scalar_and_vector",checks);$finish;
    end
endmodule
