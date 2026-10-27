`timescale 1ns/1ps
`include "biriscv_defs.v"
module tb_shift_data_compare #(parameter PREDECODE=1);
    reg clk=0,rst=1,valid=0,hold=0,invalid=0;
    always #5 clk=~clk;
    reg [31:0] opcode=0,pc=32'h80000000,a=0,b=0;
    reg [8:0] decode=0;
    wire [136:0] ref_out,got_out;
    integer n,j,k,checks=0;
    triha_branch_parent #(.SUPPORT_ALU_PREDECODE(PREDECODE),.SUPPORT_REGISTER_SHIFT(0)) u_reference (
        .clk_i(clk),
        .rst_i(rst),
        .opcode_valid_i(valid),
        .opcode_opcode_i(opcode),
        .opcode_pc_i(pc),
        .opcode_invalid_i(invalid),
        .opcode_rd_idx_i(opcode[11:7]),
        .opcode_ra_idx_i(opcode[19:15]),
        .opcode_rb_idx_i(opcode[24:20]),
        .opcode_ra_operand_i(a),
        .opcode_rb_operand_i(b),
        .opcode_ra_zero_i(a==0),.opcode_rb_zero_i(b==0),.alu_decode_i(decode),
        .hold_i(hold),
        .branch_request_o(ref_out[136]),
        .branch_is_taken_o(ref_out[135]),
        .branch_is_not_taken_o(ref_out[134]),
        .branch_source_o(ref_out[133:102]),
        .branch_is_call_o(ref_out[101]),
        .branch_is_ret_o(ref_out[100]),
        .branch_is_jmp_o(ref_out[99]),
        .branch_pc_o(ref_out[98:67]),
        .branch_d_request_o(ref_out[66]),
        .branch_d_pc_o(ref_out[65:34]),
        .branch_d_priv_o(ref_out[33:32]),
        .writeback_value_o(ref_out[31:0])
    );
    triha_branch_exec #(.SUPPORT_ALU_PREDECODE(PREDECODE),.SUPPORT_REGISTER_SHIFT(0)) u_candidate (
        .clk_i(clk),
        .rst_i(rst),
        .opcode_valid_i(valid),
        .opcode_opcode_i(opcode),
        .opcode_pc_i(pc),
        .opcode_invalid_i(invalid),
        .opcode_rd_idx_i(opcode[11:7]),
        .opcode_ra_idx_i(opcode[19:15]),
        .opcode_rb_idx_i(opcode[24:20]),
        .opcode_ra_operand_i(a),
        .opcode_rb_operand_i(b),
        .opcode_ra_zero_i(a==0),.opcode_rb_zero_i(b==0),.alu_decode_i(decode),
        .hold_i(hold),
        .branch_request_o(got_out[136]),
        .branch_is_taken_o(got_out[135]),
        .branch_is_not_taken_o(got_out[134]),
        .branch_source_o(got_out[133:102]),
        .branch_is_call_o(got_out[101]),
        .branch_is_ret_o(got_out[100]),
        .branch_is_jmp_o(got_out[99]),
        .branch_pc_o(got_out[98:67]),
        .branch_d_request_o(got_out[66]),
        .branch_d_pc_o(got_out[65:34]),
        .branch_d_priv_o(got_out[33:32]),
        .writeback_value_o(got_out[31:0])
    );

    task check;
        begin #1;
            if(got_out!==ref_out)$fatal(1,"SHIFT_DATA_FAIL checks=%0d decode=%b op=%h",checks,decode,opcode);
            checks=checks+1;
        end
    endtask
    initial begin
        if($test$plusargs("FAULT_RESULT"))force u_candidate.result_q[7]=1'b0;
        #2;rst=0;#1;rst=1;#4;rst=0;
        if($test$plusargs("POISON_INPUT"))begin
            @(negedge clk);opcode=32'h0010d093;a=32'h80000001;
            decode={`ALU_SHIFTR,2'd1,3'd4};valid=1;
            force u_candidate.alu_input_a_r=32'b0;
            @(posedge clk);#1;check;
            release u_candidate.alu_input_a_r;
        end
        for(n=0;n<512;n=n+1)for(j=0;j<32;j=j+1)begin
            @(negedge clk);decode=n;opcode=32'h00109093;
            opcode[24:20]=j;a=$random;b=$random;pc=$random;
            if(j%3==0)opcode[14:12]=3'b101;
            if(j%5==0)opcode[30]=1;
            valid=n%2;hold=(j%7==0);invalid=n%3==0;
            @(posedge clk);#1;check;
        end
        // Every legal shift and amount must actually clock through, independently
        // of the hold pattern used by the arbitrary-predecode sweep above.
        for(k=0;k<3;k=k+1)for(j=0;j<32;j=j+1)begin
            @(negedge clk);valid=1;hold=0;invalid=0;
            a=32'h80000001;b=$random;pc=$random;
            case(k)
                0:begin opcode=32'h00009093;decode={`ALU_SHIFTL,2'd1,3'd4};end
                1:begin opcode=32'h0000d093;decode={`ALU_SHIFTR,2'd1,3'd4};end
                2:begin opcode=32'h4000d093;decode={`ALU_SHIFTR_ARITH,2'd1,3'd4};end
            endcase
            opcode[24:20]=j;
            @(posedge clk);#1;check;
        end
        for(k=0;k<3;k=k+1)for(j=0;j<10;j=j+1)begin
            @(negedge clk);valid=1;hold=0;invalid=0;
            a=32'h80000001;b=$random;
            case(k)
                0:begin opcode=32'h01f09093;decode={`ALU_SHIFTL,2'd1,3'd4};end
                1:begin opcode=32'h01f0d093;decode={`ALU_SHIFTR,2'd1,3'd4};end
                2:begin opcode=32'h41f0d093;decode={`ALU_SHIFTR_ARITH,2'd1,3'd4};end
            endcase
            if(j<5)opcode[20+j]=1'bx;
            else opcode[15+j]=1'bz;
            @(posedge clk);#1;check;
        end
        for(n=0;n<16000;n=n+1)begin
            @(negedge clk);a=$random;b=$random;pc=$random;opcode=$random;decode=$random;
            valid=n%2;hold=n%7==0;invalid=n%3==0;
            case(n%17)
                0:a[31]=1'bx;1:a[0]=1'bz;2:opcode[20]=1'bx;
                3:decode[4]=1'bx;4:decode[3]=1'bz;5:decode[7]=1'bx;
                6:hold=1'bx;7:hold=1'bz;8:rst=1'bx;9:valid=1'bx;
            endcase
            @(posedge clk);#1;check;rst=0;
        end
        $display("SHIFT_DATA_PASS checks=%0d predecode=%0d",checks,PREDECODE);$finish;
    end
endmodule
