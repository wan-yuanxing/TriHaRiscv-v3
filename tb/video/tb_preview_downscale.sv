`timescale 1ns/1ps
`default_nettype none

// The oracle computes each 2x2 block directly from four source coordinates;
// it does not model horizontal sums, RAM latency, or the DUT pipeline.
module preview_downscale_check #(
    parameter integer W=2,
    parameter integer H=2,
    parameter integer MICRO=0,
    parameter integer UNKNOWN_ONLY=0,
    parameter integer UNKNOWN_POSITION=0,
    parameter integer UNKNOWN_MARKER=0
)(output reg done=0);
    reg clk=0,reset_n=0,clear=0;
    always #5 clk=~clk;
    reg s_valid=0,s_row_last=0,m_ready=0;
    reg [23:0] s_rgb=0;
    wire s_ready,m_valid,m_row_last,fault;
    wire [23:0] m_rgb;
    preview_downscale #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H)) dut(.*);

    integer cycle=0,received=0,frames=0,outputs=0,stalls=0,concurrent=0;
    integer mode=0,tag=0,ready_mode=0;
    reg checking=0,held_valid=0;
    reg [24:0] held_payload=0;

    function automatic integer part(input integer total,input integer pixel);
        integer remainder;
        begin
            remainder=total-255*pixel;
            if(remainder<0)part=0;
            else if(remainder>255)part=255;
            else part=remainder;
        end
    endfunction

    function automatic [23:0] pixel(input integer x,input integer y,
                                    input integer kind,input integer value);
        integer r,g,b,p;
        begin
            r=0;g=0;b=0;p=(y%2)*2+x%2;
            case(kind)
                0: begin r=0;g=0;b=0;end
                1: begin r=255;g=255;b=255;end
                2: begin
                    r=((x+y)%2)*255;
                    g=(x%2)*255;b=(y%2)*255;
                end
                3: begin
                    r=(x*3+y*17+value)%256;
                    g=(x*11+y*5+value*2)%256;
                    b=(x^y^value)%256;
                end
                4: begin
                    r=part(value,p);g=part(1020-value,p);
                    b=part((value*257)%1021,p);
                end
                5: begin
                    if(p==value%4)begin
                        if(value/4==0)r=255;
                        if(value/4==1)g=255;
                        if(value/4==2)b=255;
                    end
                end
                default: $fatal(1,"bad oracle mode");
            endcase
            pixel={8'(r),8'(g),8'(b)};
        end
    endfunction

    function automatic [23:0] expected(input integer index);
        integer x,y,r,g,b;
        reg [23:0] a,c,d,e;
        begin
            x=(index%(W/2))*2;y=(index/(W/2))*2;
            a=pixel(x,y,mode,tag);c=pixel(x+1,y,mode,tag);
            d=pixel(x,y+1,mode,tag);e=pixel(x+1,y+1,mode,tag);
            r=(int'(a[23:16])+int'(c[23:16])+int'(d[23:16])+int'(e[23:16])+2)/4;
            g=(int'(a[15:8])+int'(c[15:8])+int'(d[15:8])+int'(e[15:8])+2)/4;
            b=(int'(a[7:0])+int'(c[7:0])+int'(d[7:0])+int'(e[7:0])+2)/4;
            expected={8'(r),8'(g),8'(b)};
        end
    endfunction

    always @(negedge clk)begin
        cycle=cycle+1;
        case(ready_mode)
            0:m_ready=1;
            1:m_ready=((cycle%17)>=7 && (cycle%31)!=15);
            2:m_ready=0;
            default:m_ready=((cycle%53)>=29 && (cycle%7)!=2);
        endcase
    end

    always @(posedge clk)begin
        if(!reset_n || clear)held_valid=0;
        else begin
            if(held_valid && (!m_valid || {m_row_last,m_rgb}!==held_payload))
                $fatal(1,"W=%0d H=%0d output changed under stall",W,H);
            held_valid=m_valid && !m_ready;
            held_payload={m_row_last,m_rgb};
            if(m_valid && !m_ready)stalls=stalls+1;
            if(s_valid && s_ready && m_valid && m_ready)concurrent=concurrent+1;
            if(checking && m_valid && m_ready)begin
                if(received>=W*H/4)
                    $fatal(1,"W=%0d H=%0d excess output",W,H);
                if(m_rgb!==expected(received))
                    $fatal(1,"W=%0d H=%0d pixel=%0d mode=%0d tag=%0d got=%h expected=%h",
                           W,H,received,mode,tag,m_rgb,expected(received));
                if(m_row_last!==(received%(W/2)==W/2-1))
                    $fatal(1,"W=%0d H=%0d output row_last index=%0d",W,H,received);
                received=received+1;outputs=outputs+1;
            end
        end
    end

    task automatic restart;
        begin
            @(negedge clk);s_valid=0;s_row_last=0;clear=1;checking=0;
            @(negedge clk);clear=0;
            #1;
            if(fault || m_valid || !s_ready)$fatal(1,"clear did not restore idle");
        end
    endtask

    task automatic send(input [23:0] rgb,input logic last);
        integer wait_cycles;
        begin
            @(negedge clk);s_valid=1;s_rgb=rgb;s_row_last=last;
            @(posedge clk);wait_cycles=0;
            while(!s_ready)begin
                wait_cycles=wait_cycles+1;
                if(wait_cycles>400)$fatal(1,"input ready timeout");
                @(posedge clk);
            end
            @(negedge clk);s_valid=0;s_row_last=0;
        end
    endtask

    task automatic frame(input integer kind,input integer value,input integer stalls_mode);
        integer x,y,n,drain,wait_cycles;
        begin
            restart();mode=kind;tag=value;received=0;checking=1;ready_mode=stalls_mode;
            for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
                // Deterministic uneven bubbles, including both parity phases.
                n=(x*7+y*11+value)%19;
                @(negedge clk);
                if(n<3)begin
                    s_valid=0;s_row_last=0;
                    repeat(n+1)@(negedge clk);
                end
                s_valid=1;s_rgb=pixel(x,y,kind,value);s_row_last=x==W-1;
                @(posedge clk);wait_cycles=0;
                while(!s_ready)begin
                    wait_cycles=wait_cycles+1;
                    if(wait_cycles>400)$fatal(1,"frame input ready timeout");
                    @(posedge clk);
                end
                #1;
                if(fault)$fatal(1,"unexpected input fault W=%0d H=%0d x=%0d y=%0d",W,H,x,y);
            end
            @(negedge clk);s_valid=0;s_row_last=0;
            drain=0;
            while(received<W*H/4)begin
                @(negedge clk);drain=drain+1;
                if(drain>400)$fatal(1,"missing output W=%0d H=%0d got=%0d expected=%0d",W,H,received,W*H/4);
            end
            repeat(4)@(negedge clk);
            if(s_ready || fault || m_valid)$fatal(1,"frame completion state incorrect");
            checking=0;frames=frames+1;
        end
    endtask

    task automatic expect_fault;
        begin
            #1;
            if(fault!==1'b1 || s_ready!==1'b0)$fatal(1,"malformed/excess input did not set fault");
            repeat(6)@(negedge clk);
            if(fault!==1'b1 || s_ready!==1'b0)$fatal(1,"fault not sticky");
        end
    endtask

    task automatic unknown_marker(input integer final_pixel,input integer high_z);
        logic marker;
        begin
            restart();ready_mode=0;
            marker=high_z?1'bz:1'bx;
            if(final_pixel)begin
                send(24'h010203,0);send(24'h040506,1);send(24'h070809,0);
            end
            send(24'h0a0b0c,marker);
            #1;
            if(fault!==1'b1 || s_ready!==1'b0)
                $fatal(1,"unknown row_last accepted position=%0d marker=%b",final_pixel,marker);
            expect_fault();
            if(m_valid!==1'b0)
                $fatal(1,"unknown row_last published output position=%0d marker=%b",final_pixel,marker);
            $display("PREVIEW_UNKNOWN_PASS position=%0d marker=%b",final_pixel,marker);
        end
    endtask

    integer q;
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        if(UNKNOWN_ONLY)begin
            unknown_marker(UNKNOWN_POSITION,UNKNOWN_MARKER);
        end else if(MICRO)begin
            for(q=0;q<4;q=q+1)unknown_marker(q/2,q%2);
            // Each channel covers every representable four-pixel sum.
            for(q=0;q<=1020;q=q+1)frame(4,q,q%2==0?1:3);
            frame(0,0,1);frame(1,0,3);frame(2,0,1);
            for(q=0;q<12;q=q+1)frame(5,q,3);

            restart();send(24'h010203,1);expect_fault(); // Early row_last.
            restart();send(24'h010203,0);send(24'h040506,0);expect_fault(); // Late row_last.
            frame(3,19,1);
            @(negedge clk);s_valid=1;s_rgb=24'habcdef;s_row_last=0;
            @(negedge clk);s_valid=0;expect_fault(); // Excess after complete frame.
            restart();send(24'hffffff,0);send(24'hffffff,1);
            restart();frame(0,0,1); // Clear a partial frame; stale RAM must not leak.

            restart();ready_mode=2;
            send(24'h123456,0);send(24'h789abc,1);
            send(24'h345678,0);send(24'h9abcde,1);
            repeat(5)@(negedge clk);
            if(!m_valid)$fatal(1,"no stalled output for clear test");
            @(negedge clk);s_valid=1;s_rgb=24'hfedcba;
            @(negedge clk);s_valid=0;expect_fault();
            if(!m_valid)$fatal(1,"fault revoked stalled valid output");
            restart();ready_mode=1;frame(1,0,1);

            restart();send(24'hffffff,0);
            @(negedge clk);reset_n=0;
            #1;if(fault || m_valid || s_ready)$fatal(1,"asynchronous reset outputs");
            repeat(2)@(negedge clk);reset_n=1;
            frame(3,117,3);
            restart();send(24'h123456,1);expect_fault();
            @(negedge clk);reset_n=0;
            #1;if(fault || m_valid || s_ready)$fatal(1,"reset did not clear sticky fault");
            repeat(2)@(negedge clk);reset_n=1;
            frame(3,211,1);
            if(stalls==0)$fatal(1,"no stalled output observed");
            $display("PREVIEW_MICRO_PASS exhaustive_sums=1021 channels=3 impulses=12 malformed=3 unknown_markers=4 excess=2 clear=3 reset=2 frames=%0d outputs=%0d stalls=%0d",frames,outputs,stalls);
        end else begin
            if(W==26)begin
                frame(0,0,0);frame(1,0,1);frame(2,0,3);
            end
            frame(3,23,3);
            if(concurrent==0)$fatal(1,"no simultaneous input/output transfer W=%0d H=%0d",W,H);
            $display("PREVIEW_GEOMETRY_PASS width=%0d height=%0d frames=%0d outputs=%0d stalls=%0d simultaneous=%0d",W,H,frames,outputs,stalls,concurrent);
        end
        done=1;
    end
endmodule

module tb_preview_downscale_unknown;
    parameter integer POSITION=0,MARKER=0;
    wire done;
    preview_downscale_check #(.W(2),.H(2),.UNKNOWN_ONLY(1),
        .UNKNOWN_POSITION(POSITION),.UNKNOWN_MARKER(MARKER)) unknown_check(done);
    initial begin wait(done);$finish;end
    initial begin #200000;$fatal(1,"unknown-marker watchdog");end
endmodule

module tb_preview_downscale;
    wire a,b,c,d,e;
    preview_downscale_check #(.W(2),.H(2),.MICRO(1)) micro(a);
    preview_downscale_check #(.W(26),.H(6)) rectangular(b);
    preview_downscale_check #(.W(800),.H(600)) full_frame(c);
    preview_downscale_check #(.W(2048),.H(2)) maximum_width(d);
    preview_downscale_check #(.W(2),.H(2048)) maximum_height(e);
    initial begin
        wait(a && b && c && d && e);
        $display("PREVIEW_DOWNSCALE_PASS geometries=5 full_frame_outputs=120000");
        $finish;
    end
    initial begin #40000000;$fatal(1,"preview watchdog");end
endmodule

// Override only this top's parameters to prove elaborated geometry rejection.
module tb_preview_downscale_invalid;
    parameter integer W=1,H=2;
    wire s_ready,m_valid,m_row_last,fault;
    wire [23:0] m_rgb;
    preview_downscale #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H)) dut(
        .clk(1'b0),.reset_n(1'b0),.clear(1'b0),
        .s_valid(1'b0),.s_ready(s_ready),.s_rgb(24'b0),.s_row_last(1'b0),
        .m_valid(m_valid),.m_ready(1'b0),.m_rgb(m_rgb),.m_row_last(m_row_last),.fault(fault));
    initial begin #1;$fatal(1,"invalid geometry was accepted W=%0d H=%0d",W,H);end
endmodule
`default_nettype wire
