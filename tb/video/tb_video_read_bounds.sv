`timescale 1ns/1ps
// Compare the production grant predicate to byte-address arithmetic. Count
// the last byte inclusively so a burst ending at the aperture boundary passes.
module tb_video_read_bounds;
    video_read_arbiter dut();
    reg [31:0] pages[0:6],addr;
    reg [3:0] id; reg [7:0] len; reg [2:0] size; reg [1:0] burst;
    reg [48:0] payload,clean;
    integer p,b,l,off,k,kind,cases=0;
    reg [63:0] lastbyte;
    reg expected,actual;
    task check;
        begin
            lastbyte={32'b0,addr}+(64'd16*({56'b0,len}+64'd1))-64'd1;
            expected=(^{id,addr,len,size,burst})!==1'bx && addr[3:0]==0 && len<=15 && size==4 && burst==1 &&
                {32'b0,addr}>=64'h80000000 && lastbyte<64'h88000000 && ({32'b0,addr}>>12)==(lastbyte>>12);
            actual=dut.legal(id,addr,len,size,burst);
            if(actual!==expected)$fatal(1,"READ_BOUNDS addr=%h len=%h size=%h burst=%h actual=%b expected=%b",addr,len,size,burst,actual,expected);
            cases=cases+1;
        end
    endtask
    initial begin
        pages[0]=0;pages[1]=32'h7ffff000;pages[2]=32'h80000000;
        pages[3]=32'h83adc000;pages[4]=32'h87fff000;pages[5]=32'h88000000;pages[6]=32'hfffff000;
        id=3;size=4;burst=1;
        for(p=0;p<7;p=p+1)for(b=0;b<256;b=b+1)for(l=0;l<256;l=l+1)begin
            addr=pages[p]+b*16;len=l;check;
        end
        for(off=0;off<16;off=off+1)for(b=0;b<8;b=b+1)for(l=0;l<4;l=l+1)begin
            addr=32'h87ffff00+off;len=15;size=b;burst=l;check;
        end
        clean={4'd3,32'h80000f10,8'd14,3'd4,2'd1};
        for(k=0;k<49;k=k+1)for(kind=0;kind<2;kind=kind+1)begin
            payload=clean;payload[k]=kind?1'bz:1'bx;{id,addr,len,size,burst}=payload;check;
        end
        $display("VIDEO_READ_BOUNDS_PASS cases=%0d",cases);$finish;
    end
endmodule
