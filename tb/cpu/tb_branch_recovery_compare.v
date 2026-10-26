`timescale 1ns/1ps
module tb_branch_recovery_compare;
    parameter NEW_COMPARE=0;
    parameter POISON_NEXT=1;
    parameter BROKEN=0;
    parameter BROKEN_SCALAR=0;
    reg [31:0] opcode=32'h00208063,pc=32'h1000,ra=0,rb=0,pred=0;
    wire [31:0] next_pc;
    wire mismatch;
    reg expected;
    reg [31:0] poison_value,random_state=32'hc4192e61;
    integer i,j,checks=0;
    generate if(NEW_COMPARE)begin:g_new
        triha_e1_branch u_dut(.opcode_i(opcode),.pc_i(pc),.operand_ra_i(ra),.operand_rb_i(rb),
            .predicted_pc_i(pred),.mismatch_o(mismatch),.next_pc_o(next_pc));
        initial if(BROKEN_SCALAR)
            force mismatch=u_dut.branch_taken_r ? u_dut.target_mismatch_w : u_dut.sequential_mismatch_w;
    end else begin:g_old
        triha_e1_branch u_dut(.opcode_i(opcode),.pc_i(pc),.operand_ra_i(ra),.operand_rb_i(rb),.next_pc_o(next_pc));
        assign mismatch=next_pc!=pred;
    end endgenerate
    task randomize;
        begin
            random_state=random_state^(random_state<<13);
            random_state=random_state^(random_state>>17);
            random_state=random_state^(random_state<<5);
        end
    endtask
    task compare;
        begin
            #1;expected=next_pc!=pred;
            if(BROKEN)force mismatch=1'b0;
            #1;if(mismatch!==expected)$fatal(1,"RECOVERY_COMPARE_FAIL semantic check=%0d got=%b expected=%b opcode=%h",checks,mismatch,expected,opcode);
            checks=checks+1;
        end
    endtask
    initial begin
        #1;pred=next_pc;#1;expected=next_pc!=pred;
        poison_value=pred^32'h40000000;
        if(POISON_NEXT)begin
            force next_pc=poison_value;
            #1;if(mismatch!==expected)$fatal(1,"RECOVERY_COMPARE_FAIL comparison_after_direction_mux");
            release next_pc;
        end
        // A scalar comparison mux would incorrectly produce 1 here: both
        // concrete PCs differ, but their merged vector has unknown bits.
        opcode=32'h00208063;pc=32'h1004;ra=32'hxxxxxxxx;rb=0;pred=32'h1000;
        #1;if((next_pc!=pred)!==1'bx)$fatal(1,"RECOVERY_COMPARE_FAIL invalid_four_state_setup");
        compare;
        pc[2]=1'bx;compare;
        opcode=32'h003080e7;ra=32'h0000100x;pred=32'h1000;compare;
        for(i=0;i<20000;i=i+1)begin
            randomize;ra=random_state;randomize;rb=random_state;
            randomize;pc=random_state;randomize;pred=random_state;
            case(i%9)
                0:opcode=32'h00208063;
                1:opcode=32'h00209063;
                2:opcode=32'h0020c063;
                3:opcode=32'h0020d063;
                4:opcode=32'h0020e063;
                5:opcode=32'h0020f063;
                6:opcode=32'h001000ef;
                7:opcode=32'h003080e7;
                8:opcode=32'h00000013;
            endcase
            // Mix taken/not-taken and both matching/mismatching predictions.
            if(i%3==0)rb=ra;
            if(i%4==0)begin #1;pred=next_pc;end
            compare;
            // Unknown operand, prediction, direction and opcode cases must
            // retain the original conditional-vector merge semantics.
            if(i%8==0)begin ra[0]=1'bx;rb[31]=1'bx;compare;end
            if(i%16==0)begin pred[15]=1'bx;compare;end
            if(i%32==0)begin opcode[12]=1'bx;compare;end
        end
        $display("RECOVERY_COMPARE_PASS checks=%0d poison=%0d",checks,POISON_NEXT);$finish;
    end
endmodule
