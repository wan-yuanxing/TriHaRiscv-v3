`timescale 1ns/1ps
module tb_branch_alignment_precheck;
    reg [31:0] opcode=32'h00208063,pc=32'h1000,ra=0,rb=0,pred=32'h1000;
    reg valid=1,stall=0,squash=0,csr=0,branch0=1;
    wire [31:0] early=pc+{{19{opcode[31]}},opcode[31],opcode[7],opcode[30:25],opcode[11:8],1'b0};
    wire [6:0] actual,expected;
    wire [31:0] next_actual,next_expected,source_actual,source_expected;
    wire target_bad;
    reg poison=0;
    wire [31:0] consumer_next=poison ? {next_actual[31:2],~next_actual[1],next_actual[0]} : next_actual;
    wire [4:0] consumer_actual,consumer_expected;
    wire [31:0] recovery_actual,recovery_expected;
    integer i,j,k,checks=0,unknown_checks=0;
    candidate_branch #(.EARLY_CONDITIONAL_TARGET(1)) dut(
        .conditional_pc_i(early),.opcode_i(opcode),.pc_i(pc),.operand_ra_i(ra),.operand_rb_i(rb),
        .predicted_pc_i(pred),.mismatch_o(actual[0]),.request_o(actual[1]),.taken_o(actual[2]),
        .not_taken_o(actual[3]),.call_o(actual[4]),.ret_o(actual[5]),.jmp_o(actual[6]),
        .next_pc_o(next_actual),.source_o(source_actual),.target_misaligned_o(target_bad));
    parent_branch #(.EARLY_CONDITIONAL_TARGET(1)) oracle(
        .conditional_pc_i(early),.opcode_i(opcode),.pc_i(pc),.operand_ra_i(ra),.operand_rb_i(rb),
        .predicted_pc_i(pred),.mismatch_o(expected[0]),.request_o(expected[1]),.taken_o(expected[2]),
        .not_taken_o(expected[3]),.call_o(expected[4]),.ret_o(expected[5]),.jmp_o(expected[6]),
        .next_pc_o(next_expected),.source_o(source_expected));
    candidate_consumer consume(
        .resolve0_valid_w(valid),.resolve1_valid_w(valid),.resolved0_taken_w(actual[2]),.resolved1_taken_w(actual[2]),
        .resolved0_next_w(consumer_next),.resolved1_next_w(consumer_next),
        .resolved0_target_misaligned_w(target_bad),.resolved1_target_misaligned_w(target_bad),
        .resolved0_mismatch_w(actual[0]),.resolved1_mismatch_w(actual[0]),
        .stall_w(stall),.squash_w(squash),.branch_csr_request_i(csr),.pipe0_branch_e1_w(branch0),
        .fault0_w(consumer_actual[0]),.fault1_w(consumer_actual[1]),.resolved_fault_w(consumer_actual[2]),
        .recovery_w(consumer_actual[3]),.cancel1_e1_w(consumer_actual[4]),.recovery_pc_w(recovery_actual));
    parent_consumer consume_oracle(
        .resolve0_valid_w(valid),.resolve1_valid_w(valid),.resolved0_taken_w(expected[2]),.resolved1_taken_w(expected[2]),
        .resolved0_next_w(next_expected),.resolved1_next_w(next_expected),
        .resolved0_target_misaligned_w(1'b0),.resolved1_target_misaligned_w(1'b0),
        .resolved0_mismatch_w(expected[0]),.resolved1_mismatch_w(expected[0]),
        .stall_w(stall),.squash_w(squash),.branch_csr_request_i(csr),.pipe0_branch_e1_w(branch0),
        .fault0_w(consumer_expected[0]),.fault1_w(consumer_expected[1]),.resolved_fault_w(consumer_expected[2]),
        .recovery_w(consumer_expected[3]),.cancel1_e1_w(consumer_expected[4]),.recovery_pc_w(recovery_expected));
    task check;
        begin
            #1;
            if(actual!==expected || next_actual!==next_expected || source_actual!==source_expected ||
                consumer_actual!==consumer_expected || (!poison && recovery_actual!==recovery_expected))
                $fatal(1,"ALIGNMENT_FAIL check=%0d opcode=%h pc=%h taken=%b actual=%b expected=%b",checks,opcode,pc,actual[2],consumer_actual,consumer_expected);
            checks=checks+1;
        end
    endtask
    initial begin
        if($test$plusargs("FAULT_ALIGNMENT")) force consume.resolved0_target_misaligned_w=1'b0;
        // Real taken BEQ to +2 must fault; non-taken with the same target must not.
        opcode=32'h00208163;ra=0;rb=0;check;
        if(consumer_actual[0]!==1'b1)$fatal(1,"ALIGNMENT_FAIL taken_target_plus2");
        rb=1;check;
        if(consumer_actual[0]!==1'b0)$fatal(1,"ALIGNMENT_FAIL not_taken_target_plus2");
        if($test$plusargs("POISON_NEXT"))begin
            ra=0;rb=0;poison=1;check;poison=0;
        end
        for(i=0;i<8;i=i+1)begin
            case(i)
                0:opcode=32'h00208163;
                1:opcode=32'h00209163;
                2:opcode=32'h0020c163;
                3:opcode=32'h0020d163;
                4:opcode=32'h0020e163;
                5:opcode=32'h0020f163;
                6:opcode=32'h002000ef;
                7:opcode=32'h001080e7;
            endcase
            for(j=0;j<4;j=j+1)begin
                pc=32'h1000+j;ra=j;rb=0;pred=32'h1004;check;
                for(k=0;k<16;k=k+1)begin
                    {valid,stall,squash,csr}=k;check;
                end
                valid=1;stall=0;squash=0;csr=0;
                force dut.branch_taken_r=1'bx;force oracle.branch_taken_r=1'bx;check;unknown_checks=unknown_checks+1;
                release dut.branch_taken_r;release oracle.branch_taken_r;
                force dut.branch_taken_r=1'bz;force oracle.branch_taken_r=1'bz;check;unknown_checks=unknown_checks+1;
                release dut.branch_taken_r;release oracle.branch_taken_r;
            end
        end
        // JALR clears sum bit zero; bit one still causes a fetch alignment fault.
        opcode=32'h00008067;pc=32'h1000;ra=32'h2001;check;
        if(next_actual!==32'h2000 || consumer_actual[0]!==0)$fatal(1,"ALIGNMENT_FAIL jalr_clear_bit0");
        ra=32'h2003;check;
        if(next_actual!==32'h2002 || consumer_actual[0]!==1)$fatal(1,"ALIGNMENT_FAIL jalr_bit1");
        for(i=0;i<20000;i=i+1)begin
            pc=$random;ra=$random;rb=$random;pred=$random;opcode=$random;
            case(i%10)
                0:opcode=(opcode&32'hffff8f80)|32'h63;
                1:opcode=(opcode&32'hffff8f80)|32'h1063;
                2:opcode=(opcode&32'hffff8f80)|32'h4063;
                3:opcode=(opcode&32'hffff8f80)|32'h5063;
                4:opcode=(opcode&32'hffff8f80)|32'h6063;
                5:opcode=(opcode&32'hffff8f80)|32'h7063;
                6:opcode=(opcode&32'hffffff80)|32'h6f;
                7:opcode=(opcode&32'hffff8f80)|32'h67;
                8:opcode=32'h13;
            endcase
            valid=i%3!=0;stall=i%7==0;squash=i%11==0;csr=i%13==0;
            if(i%3==0)rb=ra;
            check;
            if(i%7==0)begin ra[3]=1'bx;rb[7]=1'bz;check;end
            if(i%11==0)begin opcode[5]=1'bx;check;end
            if(i%13==0)begin opcode[14]=1'bz;pc[1]=1'bx;check;end
            if(i%17==0)begin pred[1]=1'bz;check;end
        end
        $display("ALIGNMENT_PASS checks=%0d unknown_direction=%0d",checks,unknown_checks);$finish;
    end
endmodule
