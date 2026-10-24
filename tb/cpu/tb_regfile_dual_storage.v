/* Independent architectural 2-write/4-read storage oracle, including current
 * port0 collision priority, synchronous reset and unknown-address semantics.
 */
`timescale 1ns/1ps
module tb_regfile_dual_storage #(parameter BROKEN=0);
    reg clk=0,rst=1;
    reg [4:0] rd0=0,rd1=0,ra0=0,rb0=0,ra1=0,rb1=0;
    reg [31:0] wr0=0,wr1=0,rng=32'h2671cdef;
    reg [31:0] model[0:31];
    wire [31:0] va0,vb0,va1,vb1;
    wire [31:0] actual_wr0=BROKEN ? wr0^32'h1 : wr0;
    integer i,n,checks=0;
    always #5 clk=~clk;
    triha_regfile #(.SUPPORT_DUAL_ISSUE(1),.SUPPORT_REGFILE_XILINX(0)) u_dut (
        .clk_i(clk),.rst_i(rst),.rd0_i(rd0),.rd1_i(rd1),.rd0_value_i(actual_wr0),.rd1_value_i(wr1),
        .ra0_i(ra0),.rb0_i(rb0),.ra1_i(ra1),.rb1_i(rb1),
        .ra0_value_o(va0),.rb0_value_o(vb0),.ra1_value_o(va1),.rb1_value_o(vb1));
    function [31:0] value;
        input [4:0] addr;
        integer k;
        begin
            value=0;
            for(k=1;k<32;k=k+1)if(addr===k)value=model[k];
        end
    endfunction
    task check;
        begin
            #1;checks=checks+1;
            if({va0,vb0,va1,vb1}!=={value(ra0),value(rb0),value(ra1),value(rb1)})
                $fatal(1,"RF_DUAL_STORAGE_FAIL check=%0d rd=%h/%h read=%h/%h/%h/%h",checks,rd0,rd1,ra0,rb0,ra1,rb1);
        end
    endtask
    always @(posedge clk)begin
        if(rst)for(i=0;i<32;i=i+1)model[i]=0;
        else for(i=1;i<32;i=i+1)begin
            if(rd0==i)model[i]=wr0;
            else if(rd1==i)model[i]=wr1;
        end
    end
    task step;
        begin @(posedge clk);check;@(negedge clk);end
    endtask
    initial begin
        repeat(3)step;rst=0;ra0=1;rb0=2;ra1=3;rb1=0;
        rd0=1;rd1=1;wr0=32'h12345678;wr1=32'h87654321;step;
        rd0=0;rd1=1;wr1=32'hfedcba98;step;
        rd0=1;rd1=0;wr0=32'h98765432;step;
        for(n=0;n<4096;n=n+1)begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            rd0=rng[4:0];rd1=(n%7==0)?rd0:rng[9:5];
            wr0=rng;wr1=~rng;ra0=rd0;rb0=rd1;ra1=rng[14:10];rb1=rng[19:15];
            if(n%19==0)rd0=5'bx;
            if(n%23==0)rd1=5'bz;
            if(n%29==0)ra0=5'bx;
            if(n%31==0)rb1=5'bz;
            if(n%37==0)wr1=32'hx;
            if(n%43==0)rst=1'bx;
            else rst=(n%127==0);
            // Raising synchronous reset cannot change read data before edge.
            check;step;
        end
        rst=1;step;rst=0;rd0=0;rd1=0;ra0=0;rb0=0;ra1=0;rb1=0;step;
        $display("RF_DUAL_STORAGE_PASS checks=%0d collision_reset_unknown_address",checks);$finish;
    end
endmodule
