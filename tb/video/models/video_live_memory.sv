`timescale 1ns/1ps
// Packed native store for full-size live tests. Reads use bytes written by DUT;
// branch ranges are independently mapped and guard writes fail immediately.
module video_live_memory #(
    parameter integer W=800,H=600,PT=40,PB=40,DELAYED=1
)(
    input wire clk,reset_n,input integer fault_mode,
    input wire [27:0] axi_awaddr,axi_araddr,
    input wire [3:0] axi_awlen,axi_arlen,axi_awuser_id,axi_aruser_id,
    input wire axi_awvalid,axi_arvalid,output wire axi_awready,axi_arready,axi_wready,
    input wire [255:0] axi_wdata,input wire [31:0] axi_wstrb,
    output wire [3:0] axi_wusero_id,output wire axi_wusero_last,
    output reg [255:0] axi_rdata,output reg [3:0] axi_rid,
    output reg axi_rlast,axi_rvalid
);
    localparam integer RB=((W*3+15)/16*16)*H,VB=((W/2*3+15)/16*16)*(H/2);
    localparam integer IB=((W*2/5+15)/16*16)*(H*2/5+PT+PB)*3;
    localparam integer RS=(RB+31)/32,VS=(VB+31)/32,IS=(IB+31)/32,SPAN=RS+VS+IS;
    reg [255:0] memory[0:2*SPAN-1];
    integer ticks=0,wi=0,wn=0,ri=0,rn=0,delay_r=0;
    reg writing=0,reading=0;reg [27:0] wa=0,ra=0;reg [3:0] wid=0,rid=0;
    assign axi_awready=reset_n&&!writing&&!reading&&!axi_rvalid&&(!DELAYED||ticks%5==1);
    assign axi_arready=reset_n&&!writing&&!reading&&!axi_rvalid&&(!DELAYED||ticks%7==2);
    assign axi_wready=reset_n&&writing&&(!DELAYED||ticks%4!=0);
    assign axi_wusero_id=wid;assign axi_wusero_last=wi==wn-1;
    function automatic integer locate(input [31:0] a);
        integer s;reg [31:0] r,b;
        begin
            locate=-1;
            for(s=0;s<2;s=s+1)begin
                r=32'h82000000+32'(s)*32'h200000;b=32'h82800000+32'(s)*32'h50000;
                if(a>=r&&a<r+RB)locate=s*SPAN+int'(a-r)/32;
                if(a>=r+32'h160000&&a<r+32'h160000+VB)locate=s*SPAN+RS+int'(a-r-32'h160000)/32;
                if(a>=b&&a<b+IB)locate=s*SPAN+RS+VS+int'(a-b)/32;
            end
        end
    endfunction
    integer n,lane,k;reg [31:0] a;
    initial for(k=0;k<2*SPAN;k=k+1)memory[k]=0;
    always @(posedge clk)begin
        if(!reset_n)begin
            ticks<=0;writing<=0;reading<=0;wi<=0;wn<=0;ri<=0;rn<=0;
            wa<=0;ra<=0;wid<=0;rid<=0;delay_r<=0;
            axi_rvalid<=0;axi_rdata<=0;axi_rid<=0;axi_rlast<=0;
        end else begin
            ticks<=ticks+1;axi_rvalid<=0;
            if(axi_awvalid&&axi_awready)begin writing<=1;wa<=axi_awaddr;wid<=axi_awuser_id;wi<=0;wn<=int'(axi_awlen)+1;end
            if(writing&&axi_wready)begin
                a=32'h80000000+({4'd0,wa}<<2);n=locate(a);
                if(n<0)$fatal(1,"LIVE_MEMORY_GUARD_WRITE %h",a);
                for(lane=0;lane<32;lane=lane+1)if(axi_wstrb[lane])memory[n][lane*8+:8]=axi_wdata[lane*8+:8];
                wa<=wa+8;wi<=wi+1;if(wi==wn-1)writing<=0;
            end
            if(axi_arvalid&&axi_arready)begin reading<=1;ra<=axi_araddr;rid<=axi_aruser_id;ri<=0;rn<=int'(axi_arlen)+1;delay_r<=5;end
            if(reading&&fault_mode!=9)begin
                if(delay_r!=0)delay_r<=delay_r-1;
                else begin
                    a=32'h80000000+({4'd0,ra}<<2);n=locate(a);
                    if(n<0)$fatal(1,"LIVE_MEMORY_GUARD_READ %h",a);
                    axi_rdata<=memory[n];axi_rid<=rid;axi_rlast<=ri==rn-1;axi_rvalid<=1;
                    ra<=ra+8;ri<=ri+1;delay_r<=DELAYED?ticks%3:0;
                    if(ri==rn-1)reading<=0;
                end
            end
        end
    end
endmodule
