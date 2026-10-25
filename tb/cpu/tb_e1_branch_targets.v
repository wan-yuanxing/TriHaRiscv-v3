// Independent instruction-field/address oracle for E1 branch evaluation.
`timescale 1ns/1ps
module tb_e1_branch_targets;
    parameter BROKEN=0;
    reg [31:0] op=0,pc=0,a=0,b=0,rng=32'h27182818;
    wire [69:0] actual;
    reg request,taken,ntaken,call_flag,ret_flag,jump_flag,condition;
    reg [31:0] destination,offset,fallthrough,difference;
    integer n,checks=0;
    triha_e1_branch u_dut(.opcode_i(op),.pc_i(pc),.operand_ra_i(a),.operand_rb_i(b),
        .request_o(actual[69]),.taken_o(actual[68]),.not_taken_o(actual[67]),
        .call_o(actual[66]),.ret_o(actual[65]),.jmp_o(actual[64]),
        .next_pc_o(actual[63:32]),.source_o(actual[31:0]));
    initial begin
        if(BROKEN)force u_dut.next_pc_o[25]=1'b0;
        for(n=0;n<30000;n=n+1)begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            op=rng;pc={rng[15:0],rng[31:16]};a=rng;b=~rng;
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
            case(n%23)
                0:begin a=0;b=0;end 1:a=0;2:b=0;
                3:begin a=32'h80000000;b=32'h7fffffff;end
                4:begin a=32'h7fffffff;b=32'h80000000;end
                5:begin pc=32'hfffffffe;a=32'hfffffffe;end
                6:b=a;7:op[31]=1'bx;8:op[20]=1'bz;
                9:a[31]=1'bx;10:b[0]=1'bz;11:op[12]=1'bx;
                12:pc[28]=1'bx;13:op[6]=1'bz;
            endcase
            if(op[19:15]==0)a=0;
            if(op[24:20]==0)b=0;
            request=0;condition=0;call_flag=0;ret_flag=0;jump_flag=0;
            fallthrough=pc+4;destination=fallthrough;offset=0;
            case(op[6:0])
                7'h6f:begin
                    request=1;condition=1;call_flag=(op[11:7]==1);jump_flag=1;
                    offset={{11{op[31]}},op[31],op[19:12],op[20],op[30:21],1'b0};
                    destination=pc+offset;
                end
                7'h67:if(op[14:12]==0)begin
                    request=1;condition=1;offset={{20{op[31]}},op[31:20]};
                    destination=a+offset;destination[0]=0;
                    ret_flag=(op[19:15]==1 && op[31:20]==0);
                    call_flag=~ret_flag && op[11:7]==1;jump_flag=~(call_flag|ret_flag);
                end
                7'h63:begin
                    offset={{19{op[31]}},op[31],op[7],op[30:25],op[11:8],1'b0};
                    case(op[14:12])
                        0,1:begin
                            request=1;
                            if(op[19:15]==0)condition=(b==0);
                            else if(op[24:20]==0)condition=(a==0);
                            else condition=(a==b);
                            if(op[12])condition=~condition;
                        end
                        4,5:begin
                            request=1;difference=a-b;
                            if(a[31]!=b[31])condition=a[31];else condition=difference[31];
                            if(op[12])condition=~condition;
                        end
                        6:begin request=1;condition=(a<b);end
                        7:begin request=1;condition=(a>=b);end
                    endcase
                    if(request)destination=condition ? pc+offset : fallthrough;
                end
            endcase
            taken=request && condition;ntaken=request && ~condition;
            // The parent exports request as taken | not-taken, including X.
            request=taken|ntaken;
            #1;
            if(actual!=={request,taken,ntaken,call_flag,ret_flag,jump_flag,destination,pc})
                $fatal(1,"E1_TARGET_FAIL n=%0d op=%h pc=%h a=%h b=%h actual=%h expected=%h",n,op,pc,a,b,actual,{request,taken,ntaken,call_flag,ret_flag,jump_flag,destination,pc});
            checks=checks+1;
        end
        $display("E1_TARGET_PASS checks=%0d",checks);$finish;
    end
endmodule
