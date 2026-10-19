/* Independent RISC-V integer oracle plus original-unit cycle comparison. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
`ifndef DIV_MODULE
`define DIV_MODULE biriscv_divider
`endif
module tb_divider_arithmetic #(parameter BROKEN=0);
    reg clk=0, rst=1, valid=0;
    reg [31:0] opcode=0, a=0, b=0, expected=0;
    reg [31:0] random_q=32'h73b0c159;
    wire golden_valid, candidate_valid;
    wire [31:0] golden_value, candidate_value;
    reg delayed_valid=0;
    reg [31:0] delayed_value=0;
    reg check_oracle=1;
    integer arithmetic_checks=0;
    integer checks=0, cycles=0, operations=0, cached=0, op, n;
    always #5 clk=~clk;
    biriscv_divider u_golden (
        .clk_i(clk),.rst_i(rst),.opcode_valid_i(valid),.opcode_opcode_i(opcode),
        .opcode_pc_i(32'b0),.opcode_invalid_i(1'b0),.opcode_rd_idx_i(5'd5),
        .opcode_ra_idx_i(5'd6),.opcode_rb_idx_i(5'd7),
        .opcode_ra_operand_i(a),.opcode_rb_operand_i(b),
        .writeback_valid_o(golden_valid),.writeback_value_o(golden_value)
    );
    `DIV_MODULE u_candidate (
        .clk_i(clk),.rst_i(rst),.opcode_valid_i(valid),.opcode_opcode_i(opcode),
        .opcode_pc_i(32'b0),.opcode_invalid_i(1'b0),.opcode_rd_idx_i(5'd5),
        .opcode_ra_idx_i(5'd6),.opcode_rb_idx_i(5'd7),
        .opcode_ra_operand_i(a),.opcode_rb_operand_i(b),
        .writeback_valid_o(candidate_valid),.writeback_value_o(candidate_value)
    );
    always @(negedge clk) begin
        if(rst) begin
            delayed_valid=0;
            delayed_value=0;
        end else begin
            if(delayed_valid!==candidate_valid)
                $fatal(1,"DIV_ARITH_FAIL completion_cycle");
            if(candidate_valid) begin
                if(candidate_value!==delayed_value || (check_oracle && candidate_value!==expected))
                    $fatal(1,"DIV_ARITH_FAIL value op=%h a=%h b=%h got=%h golden=%h expected=%h",opcode,a,b,candidate_value,delayed_value,expected);
                checks=checks+1;
                if(check_oracle) arithmetic_checks=arithmetic_checks+1;
            end
            delayed_valid=golden_valid;
            delayed_value=golden_value;
        end
    end
    function [31:0] oracle;
        input [1:0] kind;
        input [31:0] x,y;
        reg signed [63:0] sx,sy,sv;
        begin
            sx={{32{x[31]}},x}; sy={{32{y[31]}},y};
            case(kind)
            0: begin
                if(y==0) oracle=32'hffffffff;
                else if(x==32'h80000000 && y==32'hffffffff) oracle=32'h80000000;
                else begin sv=sx/sy; oracle=sv[31:0]; end
            end
            1: oracle=(y==0) ? 32'hffffffff : x/y;
            2: begin
                if(y==0) oracle=x;
                else if(x==32'h80000000 && y==32'hffffffff) oracle=32'b0;
                else begin sv=sx%sy; oracle=sv[31:0]; end
            end
            3: oracle=(y==0) ? x : x%y;
            endcase
        end
    endfunction
    task run_operation;
        input [1:0] kind;
        input [31:0] x,y;
        begin
            @(negedge clk); #1;
            case(kind)
            0: opcode=`INST_DIV;
            1: opcode=`INST_DIVU;
            2: opcode=`INST_REM;
            3: opcode=`INST_REMU;
            endcase
            a=x; b=y; expected=oracle(kind,x,y); valid=1;
            @(negedge clk); #1; valid=0; cycles=0;
            while(!candidate_valid) begin
                @(negedge clk); #1; cycles=cycles+1;
                if(cycles>36) $fatal(1,"DIV_ARITH_FAIL timeout");
            end
            if(candidate_value!==expected || delayed_value!==expected)
                $fatal(1,"DIV_ARITH_FAIL task_value");
            if(cycles<4) cached=cached+1;
            operations=operations+1;
            @(negedge clk); #1;
        end
    endtask
    task noise;
        begin
            repeat(3) begin
                @(negedge clk); #1;
                opcode=32'h007302b3;
                a=~a+32'd123; b=b^32'hace13579;
            end
        end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        #1; rst=0;
        if(BROKEN) force u_candidate.writeback_value_o=32'hc0ffee00;
        for(op=0;op<4;op=op+1) begin
            run_operation(op,0,0); noise; run_operation(op,0,0);
            run_operation(op,1,0); noise; run_operation(op,1,0);
            run_operation(op,32'hffffffff,0);
            run_operation(op,32'h80000000,32'hffffffff); noise;
            run_operation(op,32'h80000000,32'hffffffff);
            run_operation(op,32'h80000000,1);
            run_operation(op,32'h7fffffff,32'hffffffff);
            run_operation(op,32'hffffffeb,4); noise; run_operation(op,32'hffffffeb,4);
            run_operation(op,21,32'hfffffffc);
            run_operation(op,32'hffffffeb,32'hfffffffc);
        end
        for(n=0;n<64;n=n+1) begin
            random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
            for(op=0;op<4;op=op+1)
                run_operation(op,random_q,random_q^32'h378acf01);
        end
        if(arithmetic_checks!=operations || cached<16) $fatal(1,"DIV_ARITH_FAIL coverage checks=%d operations=%d cache=%d",checks,operations,cached);
        // Busy restarts, repeated valid beats and reset compare against the
        // original unit's complete output stream delayed exactly one cycle.
        check_oracle=0;
        for(n=0;n<1000;n=n+1) begin
            @(negedge clk); #1;
            random_q={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
            valid=(random_q[2:0]==0);
            case(random_q[4:3])
            0: opcode=`INST_DIV;
            1: opcode=`INST_DIVU;
            2: opcode=`INST_REM;
            3: opcode=`INST_REMU;
            endcase
            if(random_q[5]) begin a=random_q; b=random_q^32'h98765432; end
            if(n==127) begin rst=1; valid=0; end
            if(n==130) rst=0;
        end
        valid=0;
        repeat(40) @(negedge clk);
        #1;
        $display("DIV_ARITH_PASS operations=%d checks=%d cached=%d random_stream_cycles=1000",operations,checks,cached);
        $finish;
    end
endmodule
