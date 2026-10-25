// E1 registered operands against the frozen parent's clocked branch result.
`timescale 1ns/1ps
module tb_e1_branch_resolve;
    parameter HAS_RESOLVER=0, BROKEN=0;
    reg clk=0,rst=1,valid=0;
    always #5 clk=~clk;
    reg [31:0] op=0,pc=0,a=0,b=0,rng=32'h7139b52a;
    reg [31:0] op_q=0,pc_q=0,a_q=0,b_q=0;
    integer n,j,k,checks=0;
    wire [69:0] expected,actual;
    triha_branch_parent u_parent (
        .clk_i(clk),.rst_i(rst),.opcode_valid_i(valid),.opcode_opcode_i(op),
        .opcode_pc_i(pc),.opcode_invalid_i(1'b0),.opcode_rd_idx_i(op[11:7]),
        .opcode_ra_idx_i(op[19:15]),.opcode_rb_idx_i(op[24:20]),
        .opcode_ra_operand_i(a),.opcode_rb_operand_i(b),.opcode_ra_zero_i(a==0),
        .opcode_rb_zero_i(b==0),.alu_decode_i(9'b0),.hold_i(1'b0),
        .branch_request_o(expected[69]),.branch_is_taken_o(expected[68]),
        .branch_is_not_taken_o(expected[67]),.branch_is_call_o(expected[66]),
        .branch_is_ret_o(expected[65]),.branch_is_jmp_o(expected[64]),
        .branch_pc_o(expected[63:32]),.branch_source_o(expected[31:0])
    );
    always @(posedge clk or posedge rst)
        if(rst)begin op_q<=0;pc_q<=0;a_q<=0;b_q<=0;end
        else if(valid)begin op_q<=op;pc_q<=pc;a_q<=a;b_q<=b;end
    generate if(HAS_RESOLVER)begin:g_resolve
        triha_e1_branch u_resolve (.opcode_i(op_q),.pc_i(pc_q),.operand_ra_i(a_q),.operand_rb_i(b_q),
            .request_o(actual[69]),.taken_o(actual[68]),.not_taken_o(actual[67]),
            .call_o(actual[66]),.ret_o(actual[65]),.jmp_o(actual[64]),
            .next_pc_o(actual[63:32]),.source_o(actual[31:0]));
        initial if(BROKEN)force u_resolve.branch_taken_r=1'b0;
    end else assign actual=70'b0;endgenerate
    function [31:0] boundary;
        input integer q;
        case(q)
            0:boundary=0;1:boundary=1;2:boundary=32'hffffffff;
            3:boundary=32'h80000000;4:boundary=32'h7fffffff;
            5:boundary=32'h80000001;6:boundary=32'h7ffffffe;
            default:boundary=32'h5555aaaa;
        endcase
    endfunction
    task check;
        begin
            checks=checks+1;
            if(actual!==expected)$fatal(1,"E1_BRANCH_FAIL n=%0d op=%h a=%h b=%h expected=%h actual=%h",n,op_q,a_q,b_q,expected,actual);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        for(n=0;n<20000;n=n+1)begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            op=rng;pc=32'h80000000|{10'b0,rng[21:2],2'b0};a=rng;b={rng[15:0],rng[31:16]};
            case(n%16)
                0:begin a=0;b=0;end 1:begin a=0;b=1;end 2:begin a=1;b=0;end
                3:begin a=32'h80000000;b=32'h7fffffff;end
                4:begin a=32'h7fffffff;b=32'h80000000;end
                5:begin a=32'hffffffff;b=0;end 6:begin a=0;b=32'hffffffff;end 7:b=a;
            endcase
            case(n%10)
                0:begin op[6:0]=7'h63;op[14:12]=0;end
                1:begin op[6:0]=7'h63;op[14:12]=1;end
                2:begin op[6:0]=7'h63;op[14:12]=4;end
                3:begin op[6:0]=7'h63;op[14:12]=5;end
                4:begin op[6:0]=7'h63;op[14:12]=6;end
                5:begin op[6:0]=7'h63;op[14:12]=7;end
                6:op[6:0]=7'h6f;
                7:begin op[6:0]=7'h67;op[14:12]=0;end
                8:begin op[6:0]=7'h13;op[14:12]=0;end
            endcase
            valid=n%7!=0;
            case(n%97)
                1:a[0]=1'bx;2:b[16]=1'bz;3:a[31]=1'bx;4:b[31]=1'bz;
                5:begin a[31]=0;b[31]=1;a[4]=1'bx;b[12]=1'bz;end
                6:begin a[31]=1;b[31]=0;a[4]=1'bz;b[12]=1'bx;end
                7:valid=1'bx;8:op[31]=1'bx;9:op[12]=1'bz;
            endcase
            // Register x0 always reads zero in the actual E1 packet.
            if(op[19:15]==0)a=0;
            if(op[24:20]==0)b=0;
            if(n==0)valid=1;
            @(posedge clk);#1;check;
        end
        for(j=0;j<8;j=j+1)for(k=0;k<8;k=k+1)begin
            @(negedge clk);valid=1;op=32'h00b55463;a=boundary(j);b=boundary(k);
            @(posedge clk);#1;check;
        end
        $display("E1_BRANCH_PASS checks=%0d",checks);$finish;
    end
endmodule
