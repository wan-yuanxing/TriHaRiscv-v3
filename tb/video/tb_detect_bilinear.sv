`timescale 1ns/1ps
`default_nettype none
module tb_detect_bilinear #(parameter integer W=15,H=10,CASE=0);
    localparam integer OW=W*2/5,OH=H*2/5,N=OW*OH;
    reg clk=0,reset_n=0,clear=0,s_valid=0,s_row_last=0,m_ready=1;
    reg [23:0] s_rgb=0;
    wire s_ready,m_valid,m_row_last,fault;
    wire [23:0] m_rgb;
    always #4 clk=~clk;
    detect_bilinear #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H)) dut(
        .clk(clk),.reset_n(reset_n),.clear(clear),.s_valid(s_valid),.s_ready(s_ready),
        .s_rgb(s_rgb),.s_row_last(s_row_last),.m_valid(m_valid),.m_ready(m_ready),
        .m_rgb(m_rgb),.m_row_last(m_row_last),.fault(fault));
    integer cycle=0,received=0,mode=0,ready_mode=0,frames=0,stalls=0,fault_cases=0;
    integer i,j,k,px,py,kind,stage,asynchronous,fd=0;
    reg checking=0,held=0;
    reg [24:0] held_payload;
    string dump_prefix,dump_file;

    function automatic [7:0] source_byte(input integer x,y,c,tag);
        integer seed;
        begin
            seed=tag==4?1:tag==5?7:0;
            case(tag)
                0:source_byte=0;
                1:source_byte=255;
                2:source_byte=c==0?211:c==1?93:17;
                default:source_byte=8'((37*x+19*y+83*c+((x*y)>>3)+seed*(7*(x%7)+13*(y%11)+29*c))%256);
            endcase
        end
    endfunction
    function automatic [23:0] source_rgb(input integer index,tag);
        source_rgb={source_byte(index%W,index/W,0,tag),source_byte(index%W,index/W,1,tag),source_byte(index%W,index/W,2,tag)};
    endfunction
    // Coordinate oracle: no source phase/RAM/pipeline state is reproduced.
    function automatic [7:0] expected_byte(input integer index,c,tag);
        integer ox,oy,sx,sy,lx,rx,ty,by,upper,lower;
        begin
            ox=index%OW;oy=index/OW;sx=(5*ox+1)/2;sy=(5*oy+1)/2;
            lx=ox%2==0?1:3;rx=4-lx;ty=oy%2==0?1:3;by=4-ty;
            upper=lx*int'(source_byte(sx,sy,c,tag))+rx*int'(source_byte(sx+1,sy,c,tag));
            lower=lx*int'(source_byte(sx,sy+1,c,tag))+rx*int'(source_byte(sx+1,sy+1,c,tag));
            expected_byte=8'((ty*upper/4+by*lower/4+2)/4);
        end
    endfunction
    function automatic [23:0] expected_rgb(input integer index,tag);
        expected_rgb={expected_byte(index,0,tag),expected_byte(index,1,tag),expected_byte(index,2,tag)};
    endfunction
    always @(negedge clk)begin
        case(ready_mode)
            0:m_ready=1;
            1:m_ready=0;
            2:m_ready=received<N-1;
            3:m_ready=cycle%128>=96;
            default:m_ready=cycle%7>=3;
        endcase
    end
    always @(posedge clk)begin
        if(!reset_n||clear)begin held=0;cycle=0;end
        else begin
            cycle=cycle+1;
            if(held&&(!m_valid||{m_row_last,m_rgb}!==held_payload))$fatal(1,"bilinear blocked output changed");
            held=m_valid&&!m_ready;held_payload={m_row_last,m_rgb};
            if(m_valid&&!m_ready)stalls=stalls+1;
            if(m_valid&&m_ready)begin
                if(checking)begin
                    if(received>=N)$fatal(1,"bilinear excess output");
                    if(m_rgb!==expected_rgb(received,mode))$fatal(1,"bilinear mismatch idx=%0d mode=%0d got=%h expected=%h",received,mode,m_rgb,expected_rgb(received,mode));
                    if(m_row_last!==(received%OW==OW-1))$fatal(1,"bilinear row metadata");
                    if(fd)$fdisplay(fd,"%06h",m_rgb);
                end
                received=received+1;
            end
        end
    end
    task automatic restart;
        begin
            @(negedge clk);checking=0;s_valid=0;clear=1;ready_mode=0;
            repeat(2)@(negedge clk);clear=0;reset_n=1;received=0;#1;
            if(fault||m_valid||!s_ready)$fatal(1,"bilinear clear idle");
        end
    endtask
    task automatic send(input [23:0] rgb,input row_end);
        integer wait_cycles;
        begin
            @(negedge clk);s_valid=1;s_rgb=rgb;s_row_last=row_end;
            @(posedge clk);wait_cycles=0;
            while(!s_ready)begin @(posedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>3000)$fatal(1,"bilinear source timeout");end
            @(negedge clk);s_valid=0;
        end
    endtask
    task automatic frame(input integer tag,pressure);
        integer n,t;
        begin
            restart();mode=tag;checking=1;ready_mode=pressure;
            if(dump_prefix!="")begin
                dump_file=$sformatf("%s_%0d.hex",dump_prefix,tag);fd=$fopen(dump_file,"w");
                if(!fd)$fatal(1,"cannot open bilinear dump");
            end
            for(n=0;n<W*H;n=n+1)begin
                if((n+tag)%13==2)repeat(2)@(negedge clk);
                send(source_rgb(n,tag),n%W==W-1);
                if(fault)$fatal(1,"bilinear fault on legal frame");
            end
            t=0;while(received<N)begin @(negedge clk);t=t+1;if(t>5000)$fatal(1,"bilinear drain timeout");end
            repeat(5)@(negedge clk);
            if(m_valid||s_ready||fault||received!=N)$fatal(1,"bilinear terminal state");
            if(fd)begin $fclose(fd);fd=0;end
            checking=0;frames=frames+1;
        end
    endtask
    task automatic expect_fault;
        begin repeat(3)@(negedge clk);if(!fault||s_ready)$fatal(1,"bilinear missing sticky fault");fault_cases=fault_cases+1;end
    endtask
    initial begin
        dump_prefix="";if($value$plusargs("DUMP=%s",dump_prefix))begin end
        repeat(3)@(negedge clk);reset_n=1;
        case(CASE)
            0:begin
                for(k=0;k<6;k=k+1)frame(k,k==3?3:k%2==0?0:4);
                if(stalls==0)$fatal(1,"bilinear backpressure not exercised");
            end
            1:begin
                // Every 5x5 source phase, including the skipped row/column.
                for(py=0;py<5;py=py+1)for(px=0;px<5;px=px+1)for(kind=0;kind<6;kind=kind+1)begin
                    restart();mode=3;
                    for(j=0;j<py*W+px;j=j+1)send(source_rgb(j,3),j%W==W-1);
                    case(kind)
                        0:send(24'hxx1234,px==W-1);
                        1:send(24'h12xx34,px==W-1);
                        2:send(24'h1234xx,px==W-1);
                        3:send(24'hzzzzzz,px==W-1);
                        4:send(source_rgb(py*W+px,3),1'bx);
                        5:send(source_rgb(py*W+px,3),px!=W-1);
                    endcase
                    expect_fault();
                end
                // Unknown blocked payload is not an accepted malformed item.
                restart();ready_mode=1;
                for(j=0;j<W+2;j=j+1)send(source_rgb(j,3),j%W==W-1);
                wait(m_valid);@(negedge clk);s_valid=1;s_rgb=24'hxxxxxx;s_row_last=1'bx;
                repeat(20)@(negedge clk);
                if(s_ready||fault||!m_valid)$fatal(1,"bilinear interpreted blocked payload");
                s_valid=0;ready_mode=0;repeat(4)@(negedge clk);
                // A terminal protocol fault cannot retract an owned last item.
                restart();mode=1;checking=1;ready_mode=2;
                for(j=0;j<W*H;j=j+1)send(source_rgb(j,1),j%W==W-1);
                while(received<N-1||!m_valid)@(negedge clk);
                repeat(3)@(negedge clk);s_valid=1;expect_fault();
                if(!m_valid||m_rgb!==24'hffffff||!m_row_last)$fatal(1,"bilinear fault retracted final item");
                s_valid=0;ready_mode=0;repeat(5)@(negedge clk);
                if(received!=N)$fatal(1,"bilinear final owned output lost");
                frame(5,4);
            end
            2:begin
                for(asynchronous=0;asynchronous<2;asynchronous=asynchronous+1)for(stage=0;stage<4;stage=stage+1)begin
                    restart();ready_mode=1;
                    for(j=0;j<(stage==3?3:W+2);j=j+1)send(source_rgb(j,1),j%W==W-1);
                    if(stage==1)@(negedge clk);
                    if(stage==2)begin wait(m_valid);@(negedge clk);end
                    if(asynchronous)begin
                        #1;reset_n=0;#1;if(m_valid||s_ready)$fatal(1,"bilinear asynchronous cancel");
                        repeat(2)@(negedge clk);reset_n=1;
                    end else begin
                        clear=1;#1;if(m_valid||s_ready)$fatal(1,"bilinear clear cancel");
                        repeat(2)@(negedge clk);clear=0;
                    end
                    frame(stage+2,stage%2==0?3:4);
                end
            end
            default:$fatal(1,"bad bilinear test case");
        endcase
        $display("DETECT_BILINEAR_PASS W=%0d H=%0d CASE=%0d frames=%0d faults=%0d stalls=%0d",W,H,CASE,frames,fault_cases,stalls);$finish;
    end
    initial begin #400000000;$fatal(1,"bilinear global timeout");end
endmodule
`default_nettype wire
