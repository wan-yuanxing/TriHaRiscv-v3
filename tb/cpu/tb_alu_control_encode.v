/* Independent original execution decode versus early control/data selection. */
`timescale 1ns/1ps
module tb_alu_control_encode #(parameter BROKEN=0);
    reg [31:0] op=0,rng=32'h7183a42d;
    reg [31:0] a=32'h13579bdf,b=32'h2468ace0,pc=32'h80001234;
    wire [8:0] control;
    reg [16:0] support;
    integer n,bitno,k,position,checks=0;
    triha_alu_predecode u_encode(.opcode_i(op),.control_o(control));
    biriscv_exec u_reference(.clk_i(1'b0),.rst_i(1'b1),.opcode_valid_i(1'b0),.opcode_opcode_i(op),
        .opcode_pc_i(pc),.opcode_invalid_i(1'b0),.opcode_rd_idx_i(op[11:7]),.opcode_ra_idx_i(op[19:15]),
        .opcode_rb_idx_i(op[24:20]),.opcode_ra_operand_i(a),.opcode_rb_operand_i(b),.hold_i(1'b0));
    triha_branch_exec #(.SUPPORT_ALU_PREDECODE(1)) u_dut(.clk_i(1'b0),.rst_i(1'b1),.opcode_valid_i(1'b0),.opcode_opcode_i(op),
        .alu_decode_i(control ^ (BROKEN ? 9'b000100000 : 9'b0)),
        .opcode_pc_i(pc),.opcode_invalid_i(1'b0),.opcode_rd_idx_i(op[11:7]),.opcode_ra_idx_i(op[19:15]),
        .opcode_rb_idx_i(op[24:20]),.opcode_ra_operand_i(a),.opcode_rb_operand_i(b),.hold_i(1'b0));
    task check;
        begin
            #1;checks=checks+1;
            if({u_dut.alu_func_r,u_dut.alu_input_a_r,u_dut.alu_input_b_r}!==
               {u_reference.alu_func_r,u_reference.alu_input_a_r,u_reference.alu_input_b_r})
                $fatal(1,"ALU_CONTROL_ENCODE_FAIL check=%0d op=%h control=%h",checks,op,control);
        end
    endtask
    initial begin
        for(n=0;n<131072;n=n+1)begin
            support=n;op={support[16:10],10'b0,support[9:7],5'b0,support[6:0]};check;
        end
        for(n=0;n<4096;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;support=rng[16:0];
            for(bitno=0;bitno<17;bitno=bitno+1)begin
                position=bitno<7 ? bitno : bitno<10 ? bitno+5 : bitno+15;
                op={support[16:10],10'bx,support[9:7],5'bz,support[6:0]};
                op[position]=1'bx;check;op[position]=1'bz;check;
            end
        end
        for(n=0;n<20000;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;op=rng;
            for(k=0;k<4;k=k+1)begin
                rng=rng*32'd1664525+32'd1013904223;
                if(rng[5])op[rng[4:0]]=1'bx;else op[rng[4:0]]=1'bz;
            end
            a=rng;b=~rng;pc=32'h80000000|rng;
            if(n%7==0)a[11]=1'bx;
            if(n%11==0)b[13]=1'bz;
            if(n%17==0)pc[23]=1'bx;
            check;
        end
        $display("ALU_CONTROL_ENCODE_PASS checks=%0d full68bit_fields_exhaustive17_support_selectedXZ",checks);$finish;
    end
endmodule
