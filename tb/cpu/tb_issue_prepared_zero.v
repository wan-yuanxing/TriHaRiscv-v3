/* Data lane selection is independent of PC-hit/valid; issue stays fail-closed. */
`timescale 1ns / 1ps
module tb_issue_prepared_zero #(parameter BROKEN=0,parameter DUAL_ISSUE=0);
    reg clk=0, rst=1;
    always #5 clk=~clk;
    triha_cpu #(.SUPPORT_DUAL_ISSUE(DUAL_ISSUE), .SUPPORT_SUPER(0), .SUPPORT_MMU(0)) u_dut (
        .clk_i(clk), .rst_i(rst), .intr_i(1'b0), .reset_vector_i(32'h80000000), .cpu_id_i(32'b0),
        .mem_i_accept_i(1'b1), .mem_i_valid_i(1'b0), .mem_i_error_i(1'b0), .mem_i_inst_i(64'b0),
        .mem_d_data_rd_i(32'b0), .mem_d_accept_i(1'b1), .mem_d_ack_i(1'b0),
        .mem_d_error_i(1'b0), .mem_d_resp_tag_i(11'b0),
        .mem_i_rd_o(), .mem_i_pc_o(), .mem_i_flush_o(), .mem_i_invalidate_o(),
        .mem_d_addr_o(), .mem_d_data_wr_o(), .mem_d_rd_o(), .mem_d_wr_o(), .mem_d_req_tag_o(),
        .mem_d_cacheable_o(), .mem_d_invalidate_o(), .mem_d_writeback_o(), .mem_d_flush_o()
    );

    reg [31:0] model [0:31];
    reg [4:0] wr=0, tags[0:5];
    reg [31:0] wr_data=0, values[0:5];
    reg [31:0] instruction0=0, instruction1=0, selected_pc=32'h80000000;
    reg [31:0] random_q=32'h27182818;
    integer checks=0, n, j, index, mask, shape, payload_type;
    function [31:0] next_random;
        input [31:0] old;
        begin next_random=old*32'd1664525+32'd1013904223;end
    endfunction
    function [31:0] expected;
        input [4:0] idx;
        reg [31:0] result;
        begin
            result=model[idx];
            // Existing dual FF RF uses a numeric case with zero default.
            if(DUAL_ISSUE && (^idx === 1'bx))result=0;
            if(tags[0]==idx)result=values[0];
            if(tags[1]==idx)result=values[1];
            if(tags[2]==idx)result=values[2];
            if(tags[3]==idx)result=values[3];
            if(tags[4]==idx)result=values[4];
            if(tags[5]==idx)result=values[5];
            if(idx==0)result=0;
            expected=result;
        end
    endfunction
    task check;
        reg [31:0] instruction, got_a;
        reg zero_expected;
        begin
            instruction=instruction1;
            if(!selected_pc[2])instruction=instruction0;
            got_a=u_dut.u_issue.opcode0_ra_operand_o;

            if(got_a!==expected(instruction[19:15]) ||
               u_dut.u_issue.opcode0_rb_operand_o!==expected(instruction[24:20]))begin
                $display("PREPARED_ZERO_FAIL operands check=%0d pc=%h ra=%h expected=%h rb=%h expected=%h",
                    checks,selected_pc,got_a,expected(instruction[19:15]),
                    u_dut.u_issue.opcode0_rb_operand_o,expected(instruction[24:20]));$finish;
            end
            // Physical boundary: the lower RAM address must not depend on PC.
            if(u_dut.u_issue.u_regfile.ra0_i!==instruction0[19:15] ||
               u_dut.u_issue.u_regfile.rb0_i!==instruction0[24:20])begin
                $display("PREPARED_ZERO_FAIL RAM address still depends on selected PC");$finish;
            end
            zero_expected=0;
            if(instruction[19:15]==0)begin
                case(instruction[14:12])
                    0:zero_expected=(expected(instruction[24:20])!=0);
                    1:zero_expected=(expected(instruction[24:20])==0);
                endcase
            end else if(instruction[24:20]==0)begin
                case(instruction[14:12])
                    0:zero_expected=(expected(instruction[19:15])!=0);
                    1:zero_expected=(expected(instruction[19:15])==0);
                endcase
            end
            if(u_dut.u_issue.zero_branch_not_taken_r!==zero_expected)
                $fatal(1,"PREPARED_ZERO_FAIL check=%0d instr=%h expected=%b got=%b",checks,instruction,zero_expected,u_dut.u_issue.zero_branch_not_taken_r);
            checks=checks+3;
        end
    endtask
    initial begin
        for(j=0;j<32;j=j+1)model[j]=0;
        for(j=0;j<6;j=j+1)begin tags[j]=0;values[j]=0;end
        repeat(5)@(negedge clk);rst=0;
        force u_dut.u_issue.squash_w=1;
        if(BROKEN)force u_dut.u_issue.zero_branch_not_taken_r=1;
        force u_dut.u_issue.pc_x_q=selected_pc;
        force u_dut.u_issue.fetch0_valid_i=1;
        force u_dut.u_issue.fetch1_valid_i=1;
        force u_dut.u_issue.fetch0_pc_i=32'h80000000;
        force u_dut.u_issue.fetch1_pc_i=32'h80000004;
        force u_dut.u_issue.fetch0_instr_i=instruction0;
        force u_dut.u_issue.fetch1_instr_i=instruction1;
        force u_dut.u_issue.pipe0_rd_wb_w=wr;
        force u_dut.u_issue.pipe1_rd_wb_w=0;
        force u_dut.u_issue.pipe0_result_wb_w=wr_data;
        force u_dut.u_issue.pipe0_rd_bypass_wb_w=tags[0];
        force u_dut.u_issue.pipe1_rd_bypass_wb_w=tags[1];
        force u_dut.u_issue.pipe0_rd_bypass_e2_w=tags[2];
        force u_dut.u_issue.pipe1_rd_bypass_e2_w=tags[3];
        force u_dut.u_issue.pipe0_rd_e1_w=tags[4];
        force u_dut.u_issue.pipe1_rd_e1_w=tags[5];
        // WB0 data is shared with the actual RF write port.
        force u_dut.u_issue.pipe1_result_wb_w=values[1];
        force u_dut.u_issue.pipe0_result_e2_w=values[2];
        force u_dut.u_issue.pipe1_result_e2_w=values[3];
        force u_dut.u_issue.writeback_exec0_value_i=values[4];
        force u_dut.u_issue.writeback_exec1_value_i=values[5];
        for(n=1;n<32;n=n+1)begin
            wr=n;wr_data=32'h9e3779b9*n;
            @(posedge clk);#1;model[n]=wr_data;@(negedge clk);
        end
        wr=0;
        for(n=0;n<4000;n=n+1)begin
            @(negedge clk);
            random_q=next_random(random_q);instruction0=random_q;
            random_q=next_random(random_q);instruction1=random_q;
            for(j=0;j<6;j=j+1)begin
                random_q=next_random(random_q);tags[j]=random_q[4:0];
                random_q=next_random(random_q);values[j]=random_q;
            end
            wr_data=values[0];
            if(n%5==0)for(j=0;j<6;j=j+1)tags[j]=instruction0[19:15];
            if(n%7==0)instruction1[19:15]=0;
            if(n%11==0)instruction0[17]=1'bx;
            if(n%13==0)tags[3][2]=1'bx;
            selected_pc=32'h80000000;#1;check;
            selected_pc=32'h80000004;#1;check;
            if(n%17==0)begin selected_pc[2]=1'bx;#1;check;end
            if(n>0 && n%193==0)begin
                rst=1;@(posedge clk);#1;
                for(j=0;j<32;j=j+1)model[j]=0;
                check;@(negedge clk);rst=0;
                for(j=1;j<32;j=j+1)begin
                    wr=j;wr_data=(32'h6a09e667*n)^j;
                    @(posedge clk);#1;model[j]=wr_data;@(negedge clk);
                end
                wr=0;
            end
        end
        // Exhaust all six-source hit masks for every architectural nonzero
        // index. The sequential oracle remains independent of implementation.
        for(index=1;index<32;index=index+1)begin
            instruction0=0;instruction1=0;
            instruction0[19:15]=index;instruction0[24:20]=index;
            instruction1[19:15]=index;instruction1[24:20]=index;
            for(mask=0;mask<64;mask=mask+1)begin
                for(j=0;j<6;j=j+1)begin
                    tags[j]=((mask>>j)&1) ? index : (index==31 ? 30 : 31);
                    values[j]=32'h9e3779b9*(j+1)^mask;
                end
                // A masked earlier X/Z payload must not contaminate a
                // selected later payload; selected Z must remain Z in RTL.
                values[0][3]=1'bx;values[1][7]=1'bz;
                wr_data=values[0];
                selected_pc=32'h80000000;#1;check;
                selected_pc=32'h80000004;#1;check;
            end
        end
        // Every hit mask for both x0 source positions, BEQ/BNE, and zero,
        // nonzero, partial-X and partial-Z selected source payloads.
        for(index=1;index<32;index=index+1)for(mask=0;mask<64;mask=mask+1)for(payload_type=0;payload_type<4;payload_type=payload_type+1)begin
            for(j=0;j<6;j=j+1)begin
                tags[j]=((mask>>j)&1) ? index : (index==31 ? 30 : 31);
                case(payload_type)
                    0:values[j]=0;
                    1:values[j]=32'b1<<(j+1);
                    2:begin values[j]=0;values[j][j]=1'bx;end
                    3:begin values[j]=0;values[j][j]=1'bz;end
                endcase
            end
            wr_data=values[0];
            for(shape=0;shape<4;shape=shape+1)begin
                instruction0=32'h00000463;
                if(shape<2)instruction0[24:20]=index;
                else instruction0[19:15]=index;
                instruction0[14:12]=(shape%2);
                instruction1=instruction0;
                selected_pc=32'h80000000;#1;check;
                selected_pc=32'h80000004;#1;check;
            end
        end
        // Exercise actual RF writes followed by no-bypass zero branches.
        // Native hold gates normalize Z storage bits into X; the branch and
        // scalar oracle use that architectural read value independently.
        for(j=0;j<6;j=j+1)begin tags[j]=0;values[j]=0;end
        for(index=1;index<32;index=index+1)for(payload_type=0;payload_type<6;payload_type=payload_type+1)begin
            case(payload_type)
                0:wr_data=0;
                1:wr_data=32'b1<<(index%32);
                2:begin wr_data=0;wr_data[index%32]=1'bx;end
                3:begin wr_data=0;wr_data[index%32]=1'bz;end
                4:begin wr_data=32'b1<<((index+1)%32);wr_data[index%32]=1'bx;end
                5:begin wr_data=32'b1<<((index+1)%32);wr_data[index%32]=1'bz;end
            endcase
            wr=index;@(posedge clk);#1;model[index]=wr_data & 32'hffffffff;
            @(negedge clk);wr=0;
            for(shape=0;shape<4;shape=shape+1)begin
                instruction0=32'h00000463;
                if(shape<2)instruction0[24:20]=index;
                else instruction0[19:15]=index;
                instruction0[14:12]=(shape%2);instruction1=instruction0;
                selected_pc=32'h80000000;#1;check;
                selected_pc=32'h80000004;#1;check;
            end
        end
        $display("PREPARED_ZERO_PASS checks=%0d native_RF_forward_priority_zero_reset_fourstate",checks);$finish;
    end
    initial begin #2000000;$display("PREPARED_ZERO_FAIL timeout");$finish;end
endmodule
