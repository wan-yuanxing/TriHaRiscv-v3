/* Independent architectural RF oracle. Native RAM data gates turn Z into X;
 * the equality-to-zero property must match the actual full data after reset.
 */
`timescale 1ns/1ps
module tb_regfile_zero_metadata #(parameter BROKEN=0);
    reg clk=0,rst=1;
    reg [4:0] rd0=0,rd1=0,ra0=0,rb0=0,ra1=0,rb1=0;
    reg [31:0] wr0=0,wr1=0,rng=32'h185907ca;
    reg [31:0] model[0:31];
    wire [31:0] va0,vb0,va1,vb1;
    wire za0,zb0,za1,zb1;
    integer i,n,checks=0;
    always #5 clk=~clk;
    triha_regfile #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_REGFILE_XILINX(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.rd0_i(rd0),.rd1_i(rd1),.rd0_value_i(wr0),.rd1_value_i(wr1),
        .ra0_i(ra0),.rb0_i(rb0),.ra1_i(ra1),.rb1_i(rb1),
        .ra0_value_o(va0),.rb0_value_o(vb0),.ra1_value_o(va1),.rb1_value_o(vb1),
        .ra0_zero_o(za0),.rb0_zero_o(zb0),.ra1_zero_o(za1),.rb1_zero_o(zb1));
    function [31:0] value;
        input [4:0] addr;
        integer k;
        begin
            value=0;
            for(k=1;k<32;k=k+1)if(addr===k)value=model[k];
        end
    endfunction
    task check;
        reg [31:0] a,b,c,d;
        begin
            #1;checks=checks+1;
            a=value(ra0);b=value(rb0);c=value(ra1);d=value(rb1);
            if({va0,vb0,va1,vb1}!=={a,b,c,d})
                $fatal(1,"RF_ZERO_META_FAIL data check=%0d",checks);
            if({za0,zb0,za1,zb1}!=={a==0,b==0,c==0,d==0})
                $fatal(1,"RF_ZERO_META_FAIL flags check=%0d got=%b expected=%b",checks,
                    {za0,zb0,za1,zb1},{a==0,b==0,c==0,d==0});
        end
    endtask
    always @(posedge clk)begin
        if(rst)for(i=0;i<32;i=i+1)model[i]=0;
        else for(i=1;i<32;i=i+1)begin
            if(rd0==i)model[i]=wr0 & 32'hffffffff;
            else if(rd1==i)model[i]=wr1 & 32'hffffffff;
        end
    end
    task step;
        begin @(posedge clk);check;@(negedge clk);end
    endtask
    initial begin
        repeat(3)step;rst=0;ra0=1;rb0=2;ra1=3;rb1=0;
        if(BROKEN)force u_dut.g_dual_native.zero_q[1]=0;
        check;
        for(n=1;n<32;n=n+1)begin
            rd0=n;rd1=n;wr0=0;wr1=32'hffffffff;
            ra0=n;rb0=n;ra1=n;rb1=n;step;
            wr0=32'b1<<(n%32);wr1=0;step;
            rd0=0;rd1=n;wr1=0;step;
            wr1=0;wr1[n%32]=1'bx;step;
            wr1=0;wr1[n%32]=1'bz;step;
            wr1=32'b1<<((n+1)%32);wr1[n%32]=1'bx;step;
        end
        rd0=5'b00x01;rd1=1;wr0=32'hffffffff;wr1=0;
        ra0=1;rb0=5'b00x01;ra1=5'b01z01;rb1=0;step;
        wr1=1;rst=1'bz;check;step;
        for(n=0;n<10000;n=n+1)begin
            rng=rng*32'd1664525+32'd1013904223;
            rd0=rng[4:0];rd1=(n%7==0)?rd0:rng[9:5];
            wr0=(n%5==0)?0:rng;wr1=(n%3==0)?0:~rng;
            ra0=rd0;rb0=rd1;ra1=rng[14:10];rb1=rng[19:15];
            if(n%11==0)begin wr0=0;wr0[n%32]=1'bx;end
            if(n%13==0)begin wr1=0;wr1[n%32]=1'bz;end
            if(n%19==0)rd0=5'bx;
            if(n%23==0)rd1=5'bz;
            if(n%29==0)ra0=5'bx;
            if(n%31==0)rb1=5'bz;
            if(n%37==0)begin rd0=0;rd1=0;end
            if(n%41==0)rst=1'bz;
            else if(n%43==0)rst=1'bx;
            else rst=(n%127==0);
            check;step;
        end
        rst=1;step;rst=0;rd0=0;rd1=0;ra0=0;rb0=0;ra1=0;rb1=0;step;
        $display("RF_ZERO_META_PASS checks=%0d full128bit_plus4flags_reset_collision_unknown_XZdata",checks);$finish;
    end
endmodule
