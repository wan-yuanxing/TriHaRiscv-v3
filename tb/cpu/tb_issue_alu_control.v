/* ALU control follows the exact raw A/B opcode selector, before validity. */
`timescale 1ns/1ps
module tb_issue_alu_control #(parameter BROKEN=0);
    reg clk=0,rst=1,clock_run=1;
    always #5 if(clock_run)clk=~clk;
    reg [31:0] pc=32'h80000000;
    reg [8:0] control0=0,control1=0;
    reg [8:0] expected;
    reg [31:0] selected_word;
    reg v0=1,v1=1;
    integer n,sel,bitno,unknown_kind,checks=0;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),.mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0));
    task check;
        begin
            expected=control1;selected_word=32'h002081b3;
            if(pc[2]==0)begin expected=control0;selected_word=32'h00100093;end
            #1;checks=checks+1;
            if(u_dut.u_issue.opcode0_alu_decode_o!==expected || u_dut.u_issue.opcode1_alu_decode_o!==control1 ||
               u_dut.u_issue.opcode0_opcode_o!==selected_word)
                $fatal(1,"ISSUE_ALU_CONTROL_FAIL check=%0d select=%b A=%h/%h B=%h/%h",checks,pc[2],
                    u_dut.u_issue.opcode0_alu_decode_o,expected,u_dut.u_issue.opcode1_alu_decode_o,control1);
        end
    endtask
    task select;
        input integer kind;
        begin
            pc=32'h80000000;
            case(kind)1:pc[2]=1;2:pc[2]=1'bx;3:pc[2]=1'bz;default:;endcase
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;clock_run=0;
        force u_dut.u_issue.pc_x_q=pc;
        force u_dut.u_issue.fetch0_pc_i=32'h80000000;force u_dut.u_issue.fetch1_pc_i=32'h80000004;
        force u_dut.u_issue.fetch0_instr_i=32'h00100093;force u_dut.u_issue.fetch1_instr_i=32'h002081b3;
        force u_dut.u_issue.fetch0_valid_i=v0;force u_dut.u_issue.fetch1_valid_i=v1;
        force u_dut.u_issue.fetch0_alu_decode_i=control0;force u_dut.u_issue.fetch1_alu_decode_i=control1;
        if(BROKEN)force u_dut.u_issue.opcode0_alu_decode_o=0;
        for(n=0;n<512;n=n+1)begin
            control0=n;control1=~n;
            v0=n[0];v1=n[1];if(n%7==0)v0=1'bx;if(n%11==0)v1=1'bz;
            for(sel=0;sel<4;sel=sel+1)begin select(sel);check;end
            for(bitno=0;bitno<9;bitno=bitno+1)for(unknown_kind=0;unknown_kind<2;unknown_kind=unknown_kind+1)begin
                control0=n;control1=~n;
                if(unknown_kind==0)control0[bitno]=1'bx;else control1[bitno]=1'bz;
                for(sel=0;sel<4;sel=sel+1)begin select(sel);check;end
            end
        end
        $display("ISSUE_ALU_CONTROL_PASS checks=%0d both_lanes_selectorXZ_validity_independent",checks);$finish;
    end
endmodule
