`timescale 1ns/1ps
`default_nettype none
module tb_detect_c8_pack #(parameter integer W=3,AH=2,H=4,CASE=0);
    reg clk=0,reset_n=0,clear=0,req_valid=0,s_valid=0,m_ready=0;
    reg [7:0] req_zero=0;
    reg [23:0] s_q_bgr=0;
    reg s_row_last=0,s_frame_last=0,s_padding=0;
    wire req_ready,s_ready,m_valid,m_row_last,m_frame_last,done,fault;
    wire [127:0] m_data;
    wire [15:0] m_keep;
    detect_c8_pack #(.WIDTH(W),.ACTIVE_HEIGHT(AH),.STORAGE_HEIGHT(H)) dut(.*);
    always #4 clk=~clk;
    localparam integer BEATS_PER_ROW=(W+1)/2;
    integer cycle=0,received=0,tag=0,pressure=0,stalls=0;
    reg [7:0] zero=0;
    reg checking=0,held=0;
    reg [145:0] saved;
    function automatic [23:0] qpixel(input integer index,value,input [7:0] z);
        integer x,y;
        begin
            x=index%W;y=index/W;
            qpixel=y>=AH?{3{z}}:{8'((x+7*y+value)%256),8'((3*x+5*y+value)%256),8'((11*x+y+value)%256)};
        end
    endfunction
    function automatic [63:0] c8(input integer index,value,input [7:0] z);
        reg [23:0] q;
        begin q=qpixel(index,value,z);c8={{5{z}},q[7:0],q[15:8],q[23:16]};end
    endfunction
    function automatic [127:0] expected(input integer index);
        integer x,y;
        begin
            x=(index%BEATS_PER_ROW)*2;y=index/BEATS_PER_ROW;
            expected={x+1<W?c8(y*W+x+1,tag,zero):64'd0,c8(y*W+x,tag,zero)};
        end
    endfunction
    always @(negedge clk)begin
        cycle=cycle+1;m_ready=pressure==2?0:(pressure==0?1:cycle%37>=23);
    end
    always @(posedge clk)begin
        if(!reset_n||clear)held=0;
        else begin
            if(held&&(!m_valid||{m_frame_last,m_row_last,m_keep,m_data}!==saved))$fatal(1,"pack output changed while blocked");
            held=m_valid&&!m_ready;saved={m_frame_last,m_row_last,m_keep,m_data};
            if(held)stalls=stalls+1;
            if(checking&&done&&received!=BEATS_PER_ROW*H)$fatal(1,"pack early done");
            if(checking&&m_valid&&m_ready)begin
                if(received>=BEATS_PER_ROW*H)$fatal(1,"pack excess output");
                if(m_data!==expected(received))$fatal(1,"pack byte mismatch index=%0d got=%h expected=%h",received,m_data,expected(received));
                if(m_keep!==((W%2!=0&&received%BEATS_PER_ROW==BEATS_PER_ROW-1)?16'h00ff:16'hffff))$fatal(1,"pack keep mismatch");
                if(m_row_last!==(received%BEATS_PER_ROW==BEATS_PER_ROW-1)||m_frame_last!==(received==BEATS_PER_ROW*H-1))$fatal(1,"pack metadata mismatch");
                received=received+1;
            end
        end
    end
    task automatic restart;
        begin
            @(negedge clk);clear=1;s_valid=0;req_valid=0;checking=0;
            @(negedge clk);clear=0;#1;
            if(fault||done||m_valid||s_ready||!req_ready)$fatal(1,"pack clear idle failure");
        end
    endtask
    task automatic request(input [7:0] z);
        begin
            @(negedge clk);req_valid=1;req_zero=z;
            @(posedge clk);if(!req_ready)$fatal(1,"pack req not ready");
            @(negedge clk);req_valid=0;req_zero=8'hxx;
        end
    endtask
    task automatic send(input [23:0] q,input logic last,frame_end,padding);
        integer n;
        begin
            @(negedge clk);s_valid=1;s_q_bgr=q;s_row_last=last;s_frame_last=frame_end;s_padding=padding;
            @(posedge clk);n=0;
            while(!s_ready)begin @(posedge clk);n=n+1;if(n>500)$fatal(1,"pack input timeout");end
            @(negedge clk);s_valid=0;
        end
    endtask
    task automatic frame(input integer value,input [7:0] z,input integer backpressure);
        integer j,n;
        begin
            restart();request(z);tag=value;zero=z;pressure=backpressure;received=0;checking=1;
            for(j=0;j<W*H;j=j+1)begin
                send(qpixel(j,value,z),j%W==W-1,j==W*H-1,j/W>=AH);
                if(fault)$fatal(1,"pack fault on valid frame");
            end
            n=0;while(!done)begin @(negedge clk);n=n+1;if(n>1000)$fatal(1,"pack completion timeout");end
            repeat(3)@(negedge clk);
            if(received!=BEATS_PER_ROW*H||m_valid||s_ready||req_ready||fault)$fatal(1,"pack terminal state");
            checking=0;
        end
    endtask
    task automatic expect_fault;
        begin repeat(3)@(negedge clk);if(!fault||s_ready||done)$fatal(1,"pack failed fault/done contract");end
    endtask
    integer i,j;
    reg [23:0] bad;
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        if(CASE==0)begin frame(0,0,0);frame(128,128,1);frame(55,55,1);end
        else if(CASE==1)begin
            restart();request(8'hxx);expect_fault();
            restart();request(8'hzz);expect_fault();
            for(i=0;i<6;i=i+1)begin
                restart();request(8'h37);pressure=0;bad=24'h123456;
                if(i%2==0)bad[(i/2)*8+:8]=8'hxx;else bad[(i/2)*8+:8]=8'hzz;
                send(bad,W==1,H==1,0);expect_fault();
            end
            restart();request(0);send(24'h010203,W!=1,H==1,0);expect_fault();
            restart();request(0);send(24'h010203,W==1,H!=1,0);expect_fault();
            restart();request(0);send(24'h010203,W==1,H==1,1);expect_fault();
            restart();request(0);send(24'h010203,1'bx,H==1,0);expect_fault();
            restart();request(0);send(24'h010203,W==1,1'bz,0);expect_fault();
            restart();request(0);send(24'h010203,W==1,H==1,1'bx);expect_fault();
            if(H>AH)begin
                restart();request(8'h80);
                for(j=0;j<W*AH;j=j+1)send(qpixel(j,1,8'h80),j%W==W-1,0,0);
                send(24'h000000,W==1,AH==H-1&&W==1,1);expect_fault();
            end
            frame(17,55,1);
            @(negedge clk);s_valid=1;expect_fault();@(negedge clk);s_valid=0;
            restart();request(0);pressure=0;
            for(j=0;j<W*H-1;j=j+1)send(qpixel(j,3,0),j%W==W-1,0,j/W>=AH);
            pressure=2;send(qpixel(W*H-1,3,0),1,1,H>AH);
            repeat(3)@(negedge clk);if(done||!m_valid)$fatal(1,"pack missing held final");
            s_valid=1;expect_fault();if(!m_valid)$fatal(1,"pack fault withdrew VALID");s_valid=0;
        end else if(CASE==2)begin
            restart();request(8'h80);send(24'h123456,W==1,H==1,0);restart();frame(1,55,1);
            restart();request(0);pressure=2;
            for(j=0;j<(W==1?1:2);j=j+1)send(qpixel(j,1,0),j%W==W-1,j==W*H-1,j/W>=AH);
            #1;reset_n=0;#1;if(m_valid||s_ready||req_ready||done)$fatal(1,"pack async reset");
            repeat(2)@(negedge clk);reset_n=1;frame(0,0,1);
        end else $fatal(1,"bad case");
        $display("DETECT_C8_PACK_PASS W=%0d AH=%0d H=%0d CASE=%0d stalls=%0d",W,AH,H,CASE,stalls);$finish;
    end
    initial begin #100000000;$fatal(1,"pack global timeout");end
endmodule
`default_nettype wire
