`timescale 1ns/1ps
module tb_branch_target_compare;
    reg [31:0] opcode=32'h00208063,pc=32'h1000,ra=0,rb=0,pred=32'h1000;
    wire [6:0] actual,expected;
    wire [31:0] next_actual,next_expected,source_actual,source_expected;
    integer i,checks=0;
    triha_e1_branch dut(.opcode_i(opcode),.pc_i(pc),.operand_ra_i(ra),.operand_rb_i(rb),
        .predicted_pc_i(pred),.mismatch_o(actual[0]),.request_o(actual[1]),
        .taken_o(actual[2]),.not_taken_o(actual[3]),.call_o(actual[4]),
        .ret_o(actual[5]),.jmp_o(actual[6]),.next_pc_o(next_actual),.source_o(source_actual));
    triha_e1_branch_parent oracle(.opcode_i(opcode),.pc_i(pc),.operand_ra_i(ra),.operand_rb_i(rb),
        .predicted_pc_i(pred),.mismatch_o(expected[0]),.request_o(expected[1]),
        .taken_o(expected[2]),.not_taken_o(expected[3]),.call_o(expected[4]),
        .ret_o(expected[5]),.jmp_o(expected[6]),.next_pc_o(next_expected),.source_o(source_expected));
    task check;
        begin
            #1;
            if(actual!==expected || next_actual!==next_expected || source_actual!==source_expected)
                $fatal(1,"TARGET_COMPARE_FAIL check=%0d opcode=%h actual=%b expected=%b",checks,opcode,actual,expected);
            checks=checks+1;
        end
    endtask
    initial begin
        if($test$plusargs("POISON_TARGET"))begin
            #1;pred=next_expected;#1;
            force dut.branch_target_r=32'hdeadbeef;
            #1;if(actual[0]!==expected[0])$fatal(1,"TARGET_COMPARE_FAIL comparison_after_target_mux");
            release dut.branch_target_r;
        end
        if($test$plusargs("FAULT_COMPARE"))force dut.target_mismatch_w=1'b0;
        // Preserve B-immediate fields, especially critical opcode[8].
        for(i=0;i<32;i=i+1)begin
            case(i%4)
                0:pc=32'h00000ffe;
                1:pc=32'h7ffffffe;
                2:pc=32'hfffffffc;
                3:pc=32'h00000000;
            endcase
            opcode=32'h00208063;
            opcode[8]=(i/4)%2;
            opcode[31]=(i/8)%2;
            opcode[7]=(i/16)%2;
            ra=0;rb=0;#1;pred=next_expected;check;
            pred=pred^32'h100;check;
        end
        for(i=0;i<30000;i=i+1)begin
            pc=$random;ra=$random;rb=$random;pred=$random;
            opcode=$random;
            case(i%10)
                0:opcode=(opcode & 32'hffff8f80)|32'h63;
                1:opcode=(opcode & 32'hffff8f80)|32'h1063;
                2:opcode=(opcode & 32'hffff8f80)|32'h4063;
                3:opcode=(opcode & 32'hffff8f80)|32'h5063;
                4:opcode=(opcode & 32'hffff8f80)|32'h6063;
                5:opcode=(opcode & 32'hffff8f80)|32'h7063;
                6:opcode=(opcode & 32'hffffff80)|32'h6f;
                7:opcode=(opcode & 32'hffff8f80)|32'h67;
                8:opcode=32'h13;
            endcase
            if(i%3==0)rb=ra;
            if(i%4==0)begin #1;pred=next_expected;end
            check;
            if(i%7==0)begin ra[3]=1'bx;rb[7]=1'bz;check;end
            if(i%11==0)begin opcode[5]=1'bx;check;end
            if(i%13==0)begin opcode[14]=1'bz;pc[2]=1'bx;check;end
            if(i%17==0)begin pred[15]=1'bz;check;end
        end
        $display("TARGET_COMPARE_PASS checks=%0d",checks);$finish;
    end
endmodule
