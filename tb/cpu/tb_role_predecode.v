`timescale 1ns/1ps
module tb_role_predecode;
    reg [31:0] op0,op1,late0,late1;
    reg invalid0,invalid1,select0;
    reg [1:0] fault0,fault1;
    wire [2:0] raw0,raw1,actual0,actual1,expected0,expected1;
    reg [31:0] selected_op,selected_late;
    reg selected_invalid;
    reg [1:0] selected_fault;
    reg [2:0] selected_raw;
    integer n,c,q,k,checks;
    reg poison,broken;
    function state4;
        input integer value;
        begin case(value%4) 0:state4=0;1:state4=1;2:state4=1'bx;default:state4=1'bz;endcase end
    endfunction
    always @* begin
        selected_op=op1;selected_late=late1;selected_invalid=invalid1;selected_fault=fault1;selected_raw=raw1;
        if(select0)begin
            selected_op=op0;selected_late=late0;selected_invalid=invalid0;selected_fault=fault0;selected_raw=raw0;
        end
    end
    role_predecode dut_raw0(.opcode_i(op0),.roles_o(raw0));
    role_predecode dut_raw1(.opcode_i(op1),.roles_o(raw1));
    role_parent golden0(.opcode_i(selected_op),.invalid_i(selected_invalid),.fault_i(selected_fault),.raw_i(selected_raw),.roles_o(expected0));
    role_parent golden1(.opcode_i(op1),.invalid_i(invalid1),.fault_i(fault1),.raw_i(raw1),.roles_o(expected1));
    role_candidate candidate0(.opcode_i(selected_late),.invalid_i(selected_invalid),.fault_i(selected_fault),.raw_i(selected_raw ^ (broken?3'b001:3'b000)),.roles_o(actual0));
    role_candidate candidate1(.opcode_i(late1),.invalid_i(invalid1),.fault_i(fault1),.raw_i(raw1),.roles_o(actual1));
    task check;
        begin
            late0=poison?32'h00000037:op0;late1=poison?32'h00000037:op1;
            #1;checks=checks+1;
            if(actual0!==expected0 || actual1!==expected1)begin
                $display("ROLE_PREDECODE_FAIL check=%0d actual=%b/%b expected=%b/%b",checks,actual0,actual1,expected0,expected1);
                $finish;
            end
        end
    endtask
    initial begin
        checks=0;poison=$test$plusargs("POISON_OPCODE");broken=$test$plusargs("FAULT_ROLE");
        for(n=0;n<1024;n=n+1)begin
            op0=32'h01ab8f80;op0[6:0]=n%128;op0[14:12]=n/128;
            op1=~op0;op1[6:0]=(127-n)%128;op1[14:12]=7-n/128;
            for(c=0;c<4;c=c+1)for(q=0;q<64;q=q+1)begin
                select0=state4(c);invalid0=state4(q);invalid1=state4(63-q);
                fault0={state4(q/16),state4(q/4)};fault1={state4((63-q)/16),state4((63-q)/4)};
                check;
            end
        end
        invalid0=0;invalid1=0;fault0=0;fault1=0;
        for(n=0;n<10000;n=n+1)begin
            op0=$random;op1=$random;select0=state4(n);
            k=n%32;if(n%3==0)op0[k]=1'bx;else if(n%3==1)op1[k]=1'bz;
            check;
        end
        $display("ROLE_PREDECODE_PASS checks=%0d",checks);$finish;
    end
endmodule
