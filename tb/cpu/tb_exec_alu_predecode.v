/* All-output clocked oracle against unchanged original execution logic. */
`timescale 1ns / 1ps
module tb_exec_alu_predecode;
    parameter USE_DERIVATIVE=1, BROKEN=0, BROKEN_PC=0, PREDECODE=0, BROKEN_CTRL=0;
    reg clk=0,rst=1,valid=0,hold=0,invalid=0;
    always #5 clk=~clk;
    reg [31:0] opcode=0,pc=32'h80000000,a=0,b=0,rng=32'h7139b52a;
    integer n,i,j,checks=0,bge_taken=0,bge_not_taken=0;
    wire [136:0] ref_out,got_out;
    reg [136:0] observed;
    biriscv_exec u_reference (
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

    generate if(USE_DERIVATIVE)begin:g_new
        triha_alu_exec_model #(.PREDECODE(PREDECODE),.BROKEN_CTRL(BROKEN_CTRL)) u_candidate (
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

    end else begin:g_original
        biriscv_exec u_candidate (
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

    end endgenerate
    function [31:0] boundary;
        input integer k;
        begin
            case(k)
                0:boundary=0;1:boundary=1;2:boundary=32'hffffffff;
                3:boundary=32'h80000000;4:boundary=32'h7fffffff;
                5:boundary=32'h80000001;6:boundary=32'h7ffffffe;
                default:boundary=32'h5555aaaa;
            endcase
        end
    endfunction
    task check;
        begin
            observed=got_out;
            if(BROKEN_PC && valid===1'b1 && opcode[6:0]==7'h63)
                observed[67]=~observed[67];
            if(BROKEN && opcode[6:0]==7'h63 && opcode[14:12]==3'b101 && ref_out[66]===1'b1)observed[66]=0;
            checks=checks+1;
            if(observed!==ref_out)$fatal(1,"ALU_PREDECODE_FAIL n=%0d opcode=%h a=%h b=%h ref=%h got=%h",n,opcode,a,b,ref_out,observed);
            if(opcode[6:0]==7'h63 && opcode[14:12]==3'b101)begin
                if(ref_out[66]===1'b1)bge_taken=bge_taken+1;
                if(ref_out[66]===1'b0)bge_not_taken=bge_not_taken+1;
            end
        end
    endtask
    initial begin
        repeat(3)begin @(posedge clk);#1;check;end
        @(negedge clk);rst=0;
        for(n=0;n<20000;n=n+1)begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            opcode=rng;pc=32'h80000000|{10'b0,rng[21:2],2'b0};a=rng;b={rng[15:0],rng[31:16]};
            case(n%16)
                0:begin a=0;b=0;end 1:begin a=0;b=1;end 2:begin a=1;b=0;end
                3:begin a=32'h80000000;b=32'h7fffffff;end
                4:begin a=32'h7fffffff;b=32'h80000000;end
                5:begin a=32'hffffffff;b=0;end 6:begin a=0;b=32'hffffffff;end 7:b=a;
            endcase
            case(n%12)
                0:begin opcode[6:0]=7'h63;opcode[14:12]=0;end
                1:begin opcode[6:0]=7'h63;opcode[14:12]=1;end
                2:begin opcode[6:0]=7'h63;opcode[14:12]=4;end
                3:begin opcode[6:0]=7'h63;opcode[14:12]=5;end
                4:begin opcode[6:0]=7'h63;opcode[14:12]=6;end
                5:begin opcode[6:0]=7'h63;opcode[14:12]=7;end
                6:opcode[6:0]=7'h6f;
                7:begin opcode[6:0]=7'h67;opcode[14:12]=0;end
                8:begin opcode[6:0]=7'h13;opcode[14:12]=0;end
                9:begin opcode[6:0]=7'h33;opcode[14:12]=0;opcode[31:25]=0;end
                10:begin opcode[6:0]=7'h33;opcode[14:12]=0;opcode[31:25]=7'h20;end
            endcase
            valid=(n%7!=0);hold=(n%11==0);invalid=rng[7];
            case(n%97)
                1:a[0]=1'bx;2:b[16]=1'bz;3:a[31]=1'bx;4:b[31]=1'bz;
                5:begin a[31]=0;b[31]=1;a[4]=1'bx;b[12]=1'bz;end
                6:begin a[31]=1;b[31]=0;a[4]=1'bz;b[12]=1'bx;end
                7:valid=1'bx;8:hold=1'bx;9:opcode[31]=1'bx;10:opcode[12]=1'bz;11:invalid=1'bx;
            endcase
            if(n%997==0)rst=1;else rst=0;
            #1;check;@(posedge clk);#1;check;
        end
        // Explicit BGE cross-product avoids phase correlation with random opcode kinds.
        for(i=0;i<8;i=i+1)for(j=0;j<8;j=j+1)begin
            @(negedge clk);rst=0;valid=1;hold=0;invalid=0;
            opcode=32'h00b55463;a=boundary(i);b=boundary(j);
            #1;check;@(posedge clk);#1;check;
        end
        for(i=0;i<4;i=i+1)begin
            @(negedge clk);opcode=32'h00b55463;a=0;b=0;
            case(i)
                0:begin a[31]=0;b[31]=1;a[4]=1'bx;b[7]=1'bz;end
                1:begin a[31]=1;b[31]=0;a[4]=1'bz;b[7]=1'bx;end
                2:begin a[31]=1'bx;b[31]=0;end
                3:begin a[31]=0;b[31]=1'bz;end
            endcase
            #1;check;@(posedge clk);#1;check;
        end
        if(bge_taken<100 || bge_not_taken<100)$fatal(1,"ALU_PREDECODE_FAIL missing_BGE_coverage");
        $display("ALU_PREDECODE_PASS checks=%0d BGE_taken=%0d BGE_not_taken=%0d",checks,bge_taken,bge_not_taken);$finish;
    end
endmodule

module triha_alu_exec_model #(parameter PREDECODE=0,BROKEN_CTRL=0)
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           opcode_valid_i
    ,input  [ 31:0]  opcode_opcode_i
    ,input  [ 31:0]  opcode_pc_i
    ,input           opcode_invalid_i
    ,input  [  4:0]  opcode_rd_idx_i
    ,input  [  4:0]  opcode_ra_idx_i
    ,input  [  4:0]  opcode_rb_idx_i
    ,input  [ 31:0]  opcode_ra_operand_i
    ,input  [ 31:0]  opcode_rb_operand_i
    ,input           hold_i

    // Outputs
    ,output          branch_request_o
    ,output          branch_is_taken_o
    ,output          branch_is_not_taken_o
    ,output [ 31:0]  branch_source_o
    ,output          branch_is_call_o
    ,output          branch_is_ret_o
    ,output          branch_is_jmp_o
    ,output [ 31:0]  branch_pc_o
    ,output          branch_d_request_o
    ,output [ 31:0]  branch_d_pc_o
    ,output [  1:0]  branch_d_priv_o
    ,output [ 31:0]  writeback_value_o
);
    generate if(PREDECODE)begin:g_pre
        wire [8:0] control_w;
        triha_alu_predecode u_pre(.opcode_i(opcode_opcode_i),.control_o(control_w));
        triha_branch_exec #(.SUPPORT_ALU_PREDECODE(1)) u_exec(
            .alu_decode_i(control_w ^ (BROKEN_CTRL ? 9'b000100000 : 9'b0)),
            .clk_i(clk_i),.rst_i(rst_i),.opcode_valid_i(opcode_valid_i),.opcode_opcode_i(opcode_opcode_i),.opcode_pc_i(opcode_pc_i),.opcode_invalid_i(opcode_invalid_i),.opcode_rd_idx_i(opcode_rd_idx_i),.opcode_ra_idx_i(opcode_ra_idx_i),.opcode_rb_idx_i(opcode_rb_idx_i),.opcode_ra_operand_i(opcode_ra_operand_i),.opcode_rb_operand_i(opcode_rb_operand_i),.hold_i(hold_i),.branch_request_o(branch_request_o),.branch_is_taken_o(branch_is_taken_o),.branch_is_not_taken_o(branch_is_not_taken_o),.branch_source_o(branch_source_o),.branch_is_call_o(branch_is_call_o),.branch_is_ret_o(branch_is_ret_o),.branch_is_jmp_o(branch_is_jmp_o),.branch_pc_o(branch_pc_o),.branch_d_request_o(branch_d_request_o),.branch_d_pc_o(branch_d_pc_o),.branch_d_priv_o(branch_d_priv_o),.writeback_value_o(writeback_value_o));
    end else begin:g_old
        triha_branch_exec u_exec(.clk_i(clk_i),.rst_i(rst_i),.opcode_valid_i(opcode_valid_i),.opcode_opcode_i(opcode_opcode_i),.opcode_pc_i(opcode_pc_i),.opcode_invalid_i(opcode_invalid_i),.opcode_rd_idx_i(opcode_rd_idx_i),.opcode_ra_idx_i(opcode_ra_idx_i),.opcode_rb_idx_i(opcode_rb_idx_i),.opcode_ra_operand_i(opcode_ra_operand_i),.opcode_rb_operand_i(opcode_rb_operand_i),.hold_i(hold_i),.branch_request_o(branch_request_o),.branch_is_taken_o(branch_is_taken_o),.branch_is_not_taken_o(branch_is_not_taken_o),.branch_source_o(branch_source_o),.branch_is_call_o(branch_is_call_o),.branch_is_ret_o(branch_is_ret_o),.branch_is_jmp_o(branch_is_jmp_o),.branch_pc_o(branch_pc_o),.branch_d_request_o(branch_d_request_o),.branch_d_pc_o(branch_d_pc_o),.branch_d_priv_o(branch_d_priv_o),.writeback_value_o(writeback_value_o));
    end endgenerate
endmodule
