// Actual scheduler: side-effect B pairing waits for an E1 MUL source, while
// architectural forwarding and speculative B ALU pairing remain unchanged.
`timescale 1ns/1ps
module tb_mul_branch_pair_policy;
    parameter BROKEN=0;
    reg clk=0,rst=1,run_clock=1;
    always #5 if(run_clock)clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),.SUPPORT_REGFILE_XILINX(0)) u_dut(
        .clk_i(clk),.rst_i(rst),.intr_i(1'b0),.reset_vector_i(32'h80000000),.cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1),.mem_i_valid_i(1'b0),.mem_i_error_i(1'b0),.mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0),.mem_d_accept_i(1'b1),.mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0),.mem_d_resp_tag_i(11'b0));
    `define I u_dut.u_issue
    reg [31:0] op_a=32'h00030463,op_b=32'h00b52023;
    reg [29:0] tags=0;
    reg [191:0] values=0;
    reg mul0=0,mul1=0;
    reg [1:0] b_kind=0;
    integer index,mask,muls,shape,form,k,last,checks=0;
    reg [31:0] expected_value;
    reg known,not_taken,expected_b;
    generate if(BROKEN)begin:g_broken
        initial force `I.pair_source_known_w=6'b111111;
    end endgenerate
    initial begin
        repeat(5)@(negedge clk);rst=0;run_clock=0;
        force `I.opcode_a_r=op_a;force `I.opcode_b_r=op_b;
        force `I.fetch0_instr_i=op_a;force `I.fetch1_instr_i=op_b;
        force `I.payload0_selected_w=1'b1;
        force `I.opcode_a_valid_r=1'b1;force `I.opcode_b_valid_r=1'b1;
        force `I.opcode_a_pc_r=32'h80000000;force `I.opcode_b_pc_r=32'h80000004;
        force `I.pc_x_q=32'h80000000;
        force `I.opcode_a_fault_r=0;force `I.opcode_b_fault_r=0;
        force `I.issue_a_exec_w=0;force `I.issue_a_lsu_w=0;force `I.issue_a_branch_w=1;
        force `I.issue_a_mul_w=0;force `I.issue_a_div_w=0;force `I.issue_a_csr_w=0;
        force `I.issue_a_invalid_w=0;force `I.issue_a_sb_alloc_w=0;
        force `I.issue_b_exec_w=(b_kind==1);force `I.issue_b_simple_exec_w=(b_kind==1);
        force `I.issue_b_lsu_w=(b_kind==0);force `I.issue_b_mul_w=(b_kind==2);
        force `I.issue_b_branch_w=0;force `I.issue_b_div_w=0;force `I.issue_b_csr_w=0;
        force `I.issue_b_invalid_w=0;force `I.issue_b_sb_alloc_w=0;
        force `I.squash_w=0;force `I.recovery_w=0;force `I.branch_csr_request_i=0;
        force `I.take_interrupt_i=0;force `I.lsu_stall_i=0;force `I.stall_w=0;
        force `I.div_pending_q=0;force `I.csr_pending_q=0;
        force `I.pipe0_load_e1_w=0;force `I.pipe1_load_e1_w=0;
        force `I.pipe0_store_e1_w=0;force `I.pipe1_store_e1_w=0;
        force `I.pipe0_mul_e1_w=mul0;force `I.pipe1_mul_e1_w=mul1;
        force `I.pipe0_early_mul_w=mul0;force `I.pipe1_early_mul_w=mul1;
        force `I.raw_bypass_tags_w=tags;force `I.raw_bypass_values_w=values;
        force `I.writeback_exec0_value_i=values[159:128];
        force `I.writeback_exec1_value_i=values[191:160];
        force `I.issue_a_ra_value_w=32'd17;force `I.issue_a_rb_value_w=32'd17;
        force `I.issue_a_ra_zero_w=0;force `I.issue_a_rb_zero_w=0;
        for(index=0;index<32;index=index+1)for(mask=0;mask<64;mask=mask+1)
        for(muls=0;muls<4;muls=muls+1)for(shape=0;shape<4;shape=shape+1)
        for(form=0;form<3;form=form+1)begin
            mul0=muls%2;mul1=muls/2;b_kind=form;tags=0;values=0;
            op_a=32'h00000463;
            if(shape<2)op_a[19:15]=index;else op_a[24:20]=index;
            op_a[14:12]=shape%2;
            case(form)0:op_b=32'h00b52023;1:op_b=32'h00150513;2:op_b=32'h02b50533;endcase
            expected_value=17;known=1;last=-1;
            for(k=0;k<6;k=k+1)begin
                tags[k*5 +: 5]=((mask>>k)&1) ? index : 0;
                values[k*32 +: 32]=(k+shape)%2 ? 32'd9 : 32'd0;
                if(((mask>>k)&1) && index!=0)begin expected_value=values[k*32 +: 32];last=k;end
            end
            if(last==4 && mul0)known=0;
            if(last==5 && mul1)known=0;
            if(index==0)begin expected_value=0;known=1;end
            not_taken=(shape%2) ? expected_value==0 : expected_value!=0;
            expected_b=(form==1) || (known && not_taken);
            #1;checks=checks+1;
            if(`I.opcode0_ra_operand_o!==(shape<2 ? expected_value : 0) ||
               `I.opcode0_rb_operand_o!==(shape<2 ? 0 : expected_value))
                $fatal(1,"MUL_BRANCH_PAIR_FAIL architectural_operand");
            if(`I.opcode0_ra_zero_o!==(`I.opcode0_ra_operand_o==0) ||
               `I.opcode0_rb_zero_o!==(`I.opcode0_rb_operand_o==0))
                $fatal(1,"MUL_BRANCH_PAIR_FAIL architectural_zero");
            if(`I.dual_issue_ok_w!==expected_b)
                $fatal(1,"MUL_BRANCH_PAIR_FAIL idx=%0d mask=%0d mul=%0d shape=%0d B=%0d expect=%b got=%b",index,mask,muls,shape,form,expected_b,`I.dual_issue_ok_w);
        end
        $display("MUL_BRANCH_PAIR_PASS checks=%0d",checks);$finish;
    end
    `undef I
endmodule
