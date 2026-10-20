/* All four multiply forms, invalid bubbles and holds, against integer math. */
`timescale 1ns / 1ps
module tb_multiplier_payload #(parameter integer CORRUPT_RESULT=0);
    reg clk=0, rst=1, valid=0, hold=0;
    reg [31:0] opcode=0, operand_a=0, operand_b=0, rng=32'h271828;
    reg signed [32:0] math_a, math_b;
    reg signed [65:0] product;
    reg [31:0] expected_e1=0, expected_out=0;
    reg [31:0] expected_low=0;
    reg expected_narrow=1;
    reg valid_e1=0, valid_out=0;
    integer index, checks=0, holds=0;
    wire [31:0] result;
    wire [31:0] early_low;
    wire early_valid;
    always #5 clk=~clk;
    triha_multiplier u_dut (
        .clk_i(clk), .rst_i(rst), .opcode_valid_i(valid), .opcode_opcode_i(opcode),
        .opcode_pc_i(32'b0), .opcode_invalid_i(1'b0), .opcode_rd_idx_i(5'b0),
        .opcode_ra_idx_i(5'b0), .opcode_rb_idx_i(5'b0), .opcode_ra_operand_i(operand_a),
        .opcode_rb_operand_i(operand_b), .hold_i(hold), .writeback_value_o(result),
        .early_low_value_o(early_low), .early_low_valid_o(early_valid)
    );
    always @* begin
        math_a=$signed({(opcode[14:12]==1 || opcode[14:12]==2) && operand_a[31],operand_a});
        math_b=$signed({opcode[14:12]==1 && operand_b[31],operand_b});
        product=math_a*math_b;
    end
    initial if(CORRUPT_RESULT!=0) force u_dut.result_e2_q=32'b0;
    always @(posedge clk) begin
        if(rst) begin
            expected_low<=0;
            expected_narrow<=1;
            valid_e1<=0;
            valid_out<=0;
        end else if(!hold) begin
            expected_low<=operand_a[15:0]*operand_b[15:0];
            expected_narrow<=operand_a[31:16]==0 && operand_b[31:16]==0;
            expected_out<=expected_e1;
            valid_out<=valid_e1;
            expected_e1<=opcode[14:12]==0 ? product[31:0] : product[63:32];
            valid_e1<=valid;
        end else holds=holds+1;
        #1;
        if(early_low!==expected_low) $fatal(1,"MUL_PAYLOAD_FAIL early_low_or_hold expected=%h actual=%h",expected_low,early_low);
        if(early_valid!==expected_narrow) $fatal(1,"MUL_PAYLOAD_FAIL narrow_qualification_or_hold");
        if(!rst && valid_out) begin
            if(result!==expected_out) $fatal(1,"MUL_PAYLOAD_FAIL expected=%h actual=%h",expected_out,result);
            checks=checks+1;
        end
    end
    initial begin
        repeat(5) @(negedge clk);
        rst=0;
        for(index=0;index<4096;index=index+1) begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            valid=index%3!=1;
            hold=index%7==3 || index%11==5;
            opcode=valid ? (32'h02000033 | ((index%4)<<12)) : 32'h00000013;
            case(index%8)
                0: begin operand_a=32'h80000000; operand_b=32'hffffffff; end
                1: begin operand_a=0; operand_b=rng; end
                2: begin operand_a=32'hffffffff; operand_b=32'hffffffff; end
                3: begin operand_a=32'h7fffffff; operand_b=32'h80000000; end
                default: begin operand_a=rng; operand_b={rng[10:0],rng[31:11]}; end
            endcase
        end
        @(negedge clk); valid=0; hold=0;
        repeat(4) @(negedge clk);
        if(checks<100 || holds<20) $fatal(1,"MUL_PAYLOAD_FAIL coverage");
        $display("MUL_PAYLOAD_PASS checks=%0d holds=%0d",checks,holds);
        $finish;
    end
endmodule
