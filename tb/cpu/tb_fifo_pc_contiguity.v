// Actual FIFO secondary validity against independent full32-bit PC+4 oracle.
`timescale 1ns/1ps
module tb_fifo_pc_contiguity;
    parameter BROKEN=0;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [31:0] p0=0,p1=4,rng=32'h27182818;
    wire v1;
    integer n,j,count,checks=0;
    triha_fetch_fifo #(.DEPTH(3),.OPC_INFO_W(19)) u_dut(
        .clk_i(clk),.rst_i(rst),.flush_i(1'b0),.push_i(1'b0),
        .pred_pc_in_i(32'b0),.pc_in_i(32'b0),.pred_in_i(2'b0),.data_in_i(64'b0),
        .info0_in_i(19'b0),.info1_in_i(19'b0),.csr0_in_i(1'b0),.csr1_in_i(1'b0),
        .valid1_o(v1),.pop0_i(1'b0),.pop1_i(1'b0));
    initial begin
        if(BROKEN)force u_dut.valid1_o=1'b0;
        repeat(3)@(negedge clk);rst=0;
        for(n=0;n<40000;n=n+1)begin
            @(negedge clk);
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            p0=rng;p1=p0+4;count=n%7;
            if(n<64)begin
                j=n%32;p0=(32'h1<<j)-4;p1=p0+4;count=2;
                if(n>=32)p1=p1^(32'h1<<j);
            end else begin
                if(n%3==0)p1={rng[15:0],rng[31:16]};
                case(n%97)
                    1:p0[n%32]=1'bx;2:p0[n%32]=1'bz;
                    3:p1[n%32]=1'bx;4:p1[n%32]=1'bz;
                    5:begin p0=32'hfffffffc;p1=0;end
                endcase
            end
            u_dut.count_q=count;u_dut.pc_q[0]=p0;u_dut.pc_q[1]=p1;
            #1;checks=checks+1;
            if(v1!==(count>1 && p1==p0+32'd4))
                $fatal(1,"FIFO_PC_FAIL count=%0d p0=%h p1=%h expected=%b actual=%b",count,p0,p1,count>1 && p1==p0+32'd4,v1);
        end
        $display("FIFO_PC_PASS checks=%0d",checks);$finish;
    end
endmodule
