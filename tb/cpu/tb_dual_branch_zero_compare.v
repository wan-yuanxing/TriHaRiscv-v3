`timescale 1ns/1ps
module tb_dual_branch_zero_compare;
    parameter BROKEN = 0;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [31:0] a, b, op;
    reg [4:0] ai, bi;
    reg valid, hold;
    wire az = (a == 0);
    wire bz = (b == 0) ^ BROKEN;
    integer n;
    reg expected;
    triha_branch_exec u_exec (
        .clk_i(clk), .rst_i(1'b0), .opcode_valid_i(valid),
        .opcode_opcode_i(op), .opcode_pc_i(32'h1000),
        .opcode_invalid_i(1'b0), .opcode_rd_idx_i(5'b0),
        .opcode_ra_idx_i(ai), .opcode_rb_idx_i(bi),
        .opcode_ra_operand_i(a), .opcode_rb_operand_i(b),
        .opcode_ra_zero_i(az), .opcode_rb_zero_i(bz),
        .alu_decode_i(9'b0), .hold_i(hold),
        .writeback_value_o(), .branch_d_priv_o(), .branch_d_pc_o(),
        .branch_d_request_o(), .branch_pc_o(), .branch_is_jmp_o(),
        .branch_is_ret_o(), .branch_is_call_o(), .branch_source_o(),
        .branch_is_not_taken_o(), .branch_is_taken_o(), .branch_request_o()
    );
    initial begin
        for (n = 0; n < 10000; n = n + 1) begin
            ai = (n % 3 == 0) ? 0 : 3;
            bi = (n % 3 == 1) ? 0 : 4;
            a = $random; b = $random;
            if (n % 7 == 0) a = 0;
            if (n % 11 == 0) b = 0;
            if (n % 13 == 0) a = 32'bx;
            if (n % 17 == 0) b = 32'bz;
            if (ai == 0) a = 0;
            if (bi == 0) b = 0;
            op = n[0] ? 32'h1063 : 32'h63;
            valid = n[1]; hold = n[2];
            expected = n[0] ? (a != b) : (a == b);
            #1;
            if (u_exec.branch_taken_r !== expected)
                $fatal(1, "PROFILE_FAIL branch zero comparison n=%0d", n);
        end
        $display("BRANCH_ZERO_COMPARE_PASS cases=10000");
        $finish;
    end
endmodule
