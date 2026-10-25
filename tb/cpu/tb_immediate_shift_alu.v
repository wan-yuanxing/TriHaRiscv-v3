// Complete native ALU oracle when the legal immediate shamt equals b[4:0].
`timescale 1ns/1ps
module tb_immediate_shift_alu;
    parameter BROKEN=0;
    reg [3:0] op=0;
    reg [31:0] a=0,b=0,rng=32'h7139b52a;
    wire [31:0] old_result,new_result;
    wire [4:0] shamt=BROKEN ? (b[4:0]^5'b1) : b[4:0];
    integer n,f,j,k,checks=0;
    biriscv_alu u_old(.alu_op_i(op),.alu_a_i(a),.alu_b_i(b),.alu_p_o(old_result));
    triha_immediate_shift_alu u_new(.alu_op_i(op),.alu_a_i(a),.alu_b_i(b),.shift_amount_i(shamt),.alu_p_o(new_result));
    task check;
        begin
            #1;checks=checks+1;
            if(old_result!==new_result)$fatal(1,"IMMEDIATE_SHIFT_ALU_FAIL op=%h a=%h b=%h old=%h new=%h",op,a,b,old_result,new_result);
        end
    endtask
    function [31:0] boundary;
        input integer index;
        case(index)
            0:boundary=0;1:boundary=1;2:boundary=32'hffffffff;
            3:boundary=32'h80000000;4:boundary=32'h7fffffff;
            5:boundary=32'h80000001;6:boundary=32'h7ffffffe;
            default:boundary=32'h5555aaaa;
        endcase
    endfunction
    initial begin
        for(f=0;f<16;f=f+1)for(j=0;j<8;j=j+1)for(k=0;k<32;k=k+1)begin
            op=f;a=boundary(j);b=k;check;
        end
        for(n=0;n<40000;n=n+1)begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            a=rng;b={rng[15:0],rng[31:16]};op=n%16;
            case(n%97)
                0:a[31]=1'bx;1:a[0]=1'bz;2:b[0]=1'bx;3:b[1]=1'bz;
                4:b[2]=1'bx;5:b[3]=1'bz;6:b[4]=1'bx;7:op[0]=1'bx;
                8:op[2]=1'bz;
            endcase
            check;
        end
        $display("IMMEDIATE_SHIFT_ALU_PASS checks=%0d",checks);$finish;
    end
endmodule
