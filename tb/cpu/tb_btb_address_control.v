`timescale 1ns/1ps
module tb_btb_address_control;
    reg [7:0] row;
    reg rst,train,invalidate;
    wire write_enable=train && !rst && !invalidate;
    wire [4:0] original[0:7],candidate[0:7];
    reg [4:0] stable[0:7];
    reg poison,broken;
    integer i,c,b,checks;
    genvar g;
    generate for(g=0;g<8;g=g+1)begin:blocks
        address_parent #(.BLOCK(g)) u_parent(.write_row_i(row),.rst_i(rst),.write_i(write_enable),.address_o(original[g]));
        address_candidate #(.BLOCK(g)) u_candidate(.write_row_i(row),.rst_i(rst),.write_i(write_enable),.address_o(candidate[g]));
    end endgenerate
    function four;
        input integer v;
        begin case(v%4)0:four=0;1:four=1;2:four=1'bx;default:four=1'bz;endcase end
    endfunction
    task check;
        reg [4:0] observed;
        begin
            #1;
            for(b=0;b<8;b=b+1)begin
                observed=candidate[b] ^ ((broken && b==0)?5'b00001:5'b00000);
                checks=checks+1;
                if((write_enable && row[7:5]==b)===1'b1 && (observed!==original[b] || observed!==(row[4:0]&5'b11111)))begin
                    $display("BTB_ADDRESS_FAIL enabled check=%0d block=%0d",checks,b);$finish;
                end
                if(poison && observed!==stable[b])begin
                    $display("BTB_ADDRESS_FAIL control_dependency check=%0d block=%0d",checks,b);$finish;
                end
            end
        end
    endtask
    initial begin
        poison=$test$plusargs("POISON_CONTROL");broken=$test$plusargs("FAULT_ADDRESS");checks=0;
        for(i=0;i<1256;i=i+1)begin
            row=i%256;
            if(i>=256)begin
                row=$random;
                if(i%3==0)row[i%8]=1'bx;
                if(i%3==1)row[i%8]=1'bz;
            end
            rst=0;train=1;invalidate=0;#1;
            for(b=0;b<8;b=b+1)stable[b]=candidate[b];
            for(c=0;c<64;c=c+1)begin
                train=four(c);rst=four(c/4);invalidate=four(c/16);check;
            end
        end
        $display("BTB_ADDRESS_PASS checks=%0d",checks);$finish;
    end
endmodule
