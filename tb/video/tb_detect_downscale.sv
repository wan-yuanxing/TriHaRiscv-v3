`timescale 1ns/1ps
`default_nettype none

// Mathematical oracle: enumerate the 25 source coordinates independently of
// the implementation's horizontal accumulators, RAM and pipeline schedule.
module tb_detect_downscale #(
    parameter integer W=15,H=10,CASE=0
);
    reg clk=0,reset_n=0,clear=0,s_valid=0,s_row_last=0,m_ready=0;
    reg [23:0] s_rgb=0;
    wire s_ready,m_valid,m_row_last,fault;
    wire [23:0] m_rgb;
    detect_downscale #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H)) dut(.*);
    always #4 clk=~clk;
    integer cycle=0,mode=0,tag=0,ready_mode=0,received=0,frames=0;
    integer stalls=0,concurrent=0;
    reg checking=0,held=0;
    reg [24:0] held_data;

    function automatic integer part(input integer total,input integer p);
        integer v;
        begin v=total-255*p;part=v<0?0:(v>255?255:v);end
    endfunction
    function automatic [23:0] pixel(input integer x,y,kind,value);
        integer r,g,b,p;
        begin
            r=0;g=0;b=0;p=(y%5)*5+x%5;
            case(kind)
                0:begin end
                1:begin r=255;g=255;b=255;end
                2:begin r=(3*x+17*y+value)%256;g=(11*x+5*y+value*2)%256;b=(x^y^value)%256;end
                3:begin r=((x+y)%2)*255;g=(x%2)*255;b=(y%2)*255;end
                4:begin
                    if(x==0&&y==0)r=255;
                    if(x==W-1&&y==0)g=255;
                    if(x==0&&y==H-1)b=255;
                    if(x==W-1&&y==H-1)begin r=255;g=255;b=255;end
                end
                5:begin r=part(value,p);g=part(6375-value,p);b=part((value*257)%6376,p);end
                default:$fatal(1,"invalid oracle kind");
            endcase
            pixel={8'(r),8'(g),8'(b)};
        end
    endfunction
    function automatic [23:0] expected(input integer index);
        integer x,y,dx,dy,r,g,b;
        reg [23:0] p;
        begin
            x=(index%(W/5))*5;y=(index/(W/5))*5;r=0;g=0;b=0;
            for(dy=0;dy<5;dy=dy+1)for(dx=0;dx<5;dx=dx+1)begin
                p=pixel(x+dx,y+dy,mode,tag);
                r=r+int'(p[23:16]);g=g+int'(p[15:8]);b=b+int'(p[7:0]);
            end
            expected={8'((r+12)/25),8'((g+12)/25),8'((b+12)/25)};
        end
    endfunction
    always @(negedge clk)begin
        cycle=cycle+1;
        case(ready_mode)
            0:m_ready=1;
            1:m_ready=cycle%37>=19 && cycle%11!=0;
            2:m_ready=0;
            default:m_ready=cycle%71>=53;
        endcase
    end
    always @(posedge clk)begin
        if(!reset_n||clear)held=0;
        else begin
            if(held&&(!m_valid||{m_row_last,m_rgb}!==held_data))$fatal(1,"stalled output changed");
            held=m_valid&&!m_ready;held_data={m_row_last,m_rgb};
            if(held)stalls=stalls+1;
            if(m_valid&&m_ready&&s_valid&&s_ready)concurrent=concurrent+1;
            if(checking&&m_valid&&m_ready)begin
                if(received>=W*H/25)$fatal(1,"excess output");
                if(m_rgb!==expected(received))$fatal(1,"pixel mismatch W=%0d H=%0d index=%0d kind=%0d sum=%0d got=%h expected=%h",W,H,received,mode,tag,m_rgb,expected(received));
                if(m_row_last!==(received%(W/5)==W/5-1))$fatal(1,"output row_last mismatch");
                received=received+1;
            end
        end
    end
    task automatic restart;
        begin
            @(negedge clk);s_valid=0;clear=1;checking=0;
            @(negedge clk);clear=0;#1;
            if(fault||m_valid||!s_ready)$fatal(1,"clear failed to restore idle");
        end
    endtask
    task automatic send(input [23:0] rgb,input logic last);
        integer n;
        begin
            @(negedge clk);s_valid=1;s_rgb=rgb;s_row_last=last;
            @(posedge clk);n=0;
            while(!s_ready)begin @(posedge clk);n=n+1;if(n>1000)$fatal(1,"input wait timeout");end
            @(negedge clk);s_valid=0;
        end
    endtask
    task automatic frame(input integer kind,value,backpressure);
        integer x,y,waits;
        begin
            restart();mode=kind;tag=value;received=0;checking=1;ready_mode=backpressure;
            for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
                if(backpressure!=0&&(x+3*y+value)%29==7)repeat(3)@(negedge clk);
                send(pixel(x,y,kind,value),x==W-1);
                if(fault)$fatal(1,"fault on valid frame x=%0d y=%0d",x,y);
            end
            waits=0;
            while(received<W*H/25)begin @(negedge clk);waits=waits+1;if(waits>1000)$fatal(1,"output wait timeout");end
            repeat(3)@(negedge clk);
            if(m_valid||s_ready||fault)$fatal(1,"frame terminal state invalid");
            checking=0;frames=frames+1;
        end
    endtask
    task automatic must_fault;
        begin
            repeat(2)@(negedge clk);
            if(!fault||s_ready)$fatal(1,"invalid accepted payload did not stop input");
            repeat(3)@(negedge clk);
            if(!fault)$fatal(1,"fault was not sticky");
        end
    endtask
    integer i,j;
    reg [23:0] bad_rgb;
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        case(CASE)
            0:begin
                frame(0,0,0);frame(1,0,1);frame(2,37,3);frame(3,0,1);frame(4,0,3);
                if(stalls==0)$fatal(1,"missing backpressure coverage");
                if(W>5&&concurrent==0)$fatal(1,"missing concurrent transfer coverage");
            end
            1:begin
                if(W!=5||H!=5)$fatal(1,"exhaustive test requires 5x5");
                for(i=0;i<=6375;i=i+1)frame(5,i,i%2);
            end
            2:begin
                // Corrupt first and later block payloads, including the RAM
                // read and final accumulation phases, at all color bytes.
                for(i=0;i<12;i=i+1)begin
                    restart();ready_mode=0;
                    for(j=0;j<(i%3)*W+(i%5);j=j+1)send(24'h123456,j%W==W-1);
                    bad_rgb=24'h123456;
                    if(i%2==0)bad_rgb[(i%3)*8+:8]=8'hxx;
                    else bad_rgb[(i%3)*8+:8]=8'hzz;
                    send(bad_rgb,((i%5)==W-1));must_fault();
                end
                restart();send(24'h010203,1);must_fault();
                restart();send(24'h010203,1'bx);must_fault();
                restart();send(24'h010203,1'bz);must_fault();
                restart();for(j=0;j<W;j=j+1)send(24'h010203,0);must_fault();
                frame(2,99,1);
                @(negedge clk);s_valid=1;s_rgb=24'h010203;s_row_last=0;
                must_fault();@(negedge clk);s_valid=0;
                // The final output must retain VALID even if excess input
                // marks this already complete frame faulty while blocked.
                restart();checking=0;ready_mode=0;
                for(j=0;j<W*H-1;j=j+1)send(24'hffffff,j%W==W-1);
                ready_mode=2;send(24'hffffff,1);
                repeat(4)@(negedge clk);
                if(!m_valid)$fatal(1,"missing pending final output");
                @(negedge clk);s_valid=1;repeat(4)@(negedge clk);
                if(!fault||!m_valid||m_rgb!==24'hffffff)$fatal(1,"fault withdrew pending output");
                s_valid=0;ready_mode=0;repeat(4)@(negedge clk);
            end
            3:begin
                for(i=0;i<7;i=i+1)begin
                    restart();ready_mode=0;
                    for(j=0;j<(i+1)*W+3;j=j+1)send(24'hffffff,j%W==W-1);
                    frame(2,i,1);
                    restart();for(j=0;j<5*W-1;j=j+1)send(24'hffffff,j%W==W-1);
                    // Assert asynchronous reset away from a clock edge.
                    #1;reset_n=0;#1;
                    if(m_valid||s_ready)$fatal(1,"async reset not immediate");
                    repeat(2)@(negedge clk);reset_n=1;
                    frame(4,0,3);
                end
            end
            default:$fatal(1,"unknown test case");
        endcase
        $display("DETECT_DOWNSCALE_PASS W=%0d H=%0d CASE=%0d frames=%0d stalls=%0d concurrent=%0d",W,H,CASE,frames,stalls,concurrent);
        $finish;
    end
    initial begin #200000000;$fatal(1,"global simulation timeout");end
endmodule
`default_nettype wire
