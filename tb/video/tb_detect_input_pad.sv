`timescale 1ns/1ps
`default_nettype none
module tb_detect_input_pad #(parameter integer W=3,AH=2,H=4,CASE=0);
    reg clk=0,reset_n=0,clear=0,s_valid=0,s_row_last=0,m_ready=0;
    reg [23:0] s_rgb=0;
    wire s_ready,m_valid,m_row_last,m_frame_last,m_padding,fault;
    wire [23:0] m_bgr;
    detect_input_pad #(.WIDTH(W),.ACTIVE_HEIGHT(AH),.STORAGE_HEIGHT(H)) dut(.*);
    always #4 clk=~clk;
    integer cycle=0,received=0,tag=0,pressure=0,stalls=0;
    reg checking=0,held=0;
    reg [26:0] saved;
    function automatic [23:0] pixel(input integer index,value);
        pixel={8'((index+value)%256),8'((3*index+value)%256),8'((7*index+value)%256)};
    endfunction
    function automatic [23:0] expected(input integer index,value);
        reg [23:0] p;
        begin p=pixel(index,value);expected=index/W>=AH?24'd0:{p[7:0],p[15:8],p[23:16]};end
    endfunction
    always @(negedge clk)begin
        cycle=cycle+1;
        m_ready=pressure==2?0:(pressure==0?1:(cycle%31>=19));
    end
    always @(posedge clk)begin
        if(!reset_n||clear)held=0;
        else begin
            if(held&&(!m_valid||{m_padding,m_frame_last,m_row_last,m_bgr}!==saved))$fatal(1,"pad output changed while blocked");
            held=m_valid&&!m_ready;saved={m_padding,m_frame_last,m_row_last,m_bgr};
            if(held)stalls=stalls+1;
            if(checking&&m_valid&&m_ready)begin
                if(received>=W*H)$fatal(1,"pad excess output");
                if(m_bgr!==expected(received,tag))
                    $fatal(1,"pad pixel mismatch index=%0d got=%h",received,m_bgr);
                if(m_row_last!==(received%W==W-1)||m_frame_last!==(received==W*H-1)||m_padding!==(received/W>=AH))
                    $fatal(1,"pad metadata mismatch index=%0d",received);
                received=received+1;
            end
        end
    end
    task automatic restart;
        begin
            @(negedge clk);clear=1;s_valid=0;checking=0;
            @(negedge clk);clear=0;#1;
            if(fault||m_valid||!s_ready)$fatal(1,"pad clear idle failure");
        end
    endtask
    task automatic send(input [23:0] data,input logic last);
        integer n;
        begin
            @(negedge clk);s_valid=1;s_rgb=data;s_row_last=last;
            @(posedge clk);n=0;
            while(!s_ready)begin @(posedge clk);n=n+1;if(n>500)$fatal(1,"pad input timeout");end
            @(negedge clk);s_valid=0;
        end
    endtask
    task automatic frame(input integer value,backpressure);
        integer j,n;
        begin
            restart();tag=value;pressure=backpressure;received=0;checking=1;
            for(j=0;j<W*AH;j=j+1)begin
                if(j%17==8)repeat(2)@(negedge clk);
                send(pixel(j,value),j%W==W-1);
                if(fault)$fatal(1,"pad fault in legal source");
            end
            n=0;
            while(received<W*H)begin @(negedge clk);n=n+1;if(n>W*H*50+100)$fatal(1,"pad output timeout");end
            repeat(3)@(negedge clk);
            if(fault||m_valid||s_ready)$fatal(1,"pad terminal state");
            checking=0;
        end
    endtask
    task automatic expect_fault;
        begin repeat(3)@(negedge clk);if(!fault||s_ready)$fatal(1,"pad failed to latch fault");end
    endtask
    integer i;
    reg [23:0] bad;
    initial begin
        repeat(3)@(negedge clk);reset_n=1;
        if(CASE==0)begin frame(0,0);frame(129,1);frame(55,1);end
        else if(CASE==1)begin
            for(i=0;i<6;i=i+1)begin
                restart();pressure=0;bad=24'h123456;
                if(i%2==0)bad[(i/2)*8+:8]=8'hxx;else bad[(i/2)*8+:8]=8'hzz;
                send(bad,W==1);expect_fault();
            end
            restart();send(24'h010203,1'bx);expect_fault();
            restart();send(24'h010203,1'bz);expect_fault();
            restart();send(24'h010203,W!=1);expect_fault();
            frame(71,1);
            @(negedge clk);s_valid=1;expect_fault();@(negedge clk);s_valid=0;
        end else if(CASE==2)begin
            restart();pressure=2;send(24'hffffff,W==1);
            repeat(3)@(negedge clk);restart();frame(1,1);
            restart();pressure=0;
            for(i=0;i<W*AH;i=i+1)send(24'hffffff,i%W==W-1);
            pressure=2;repeat(3)@(negedge clk);restart();frame(17,1);
            restart();pressure=2;send(24'hffffff,W==1);
            #1;reset_n=0;#1;if(m_valid||s_ready)$fatal(1,"pad async reset");
            repeat(2)@(negedge clk);reset_n=1;frame(0,1);
        end else $fatal(1,"bad case");
        $display("DETECT_INPUT_PAD_PASS W=%0d AH=%0d H=%0d CASE=%0d stalls=%0d",W,AH,H,CASE,stalls);$finish;
    end
    initial begin #100000000;$fatal(1,"pad global timeout");end
endmodule
`default_nettype wire
