`timescale 1ns/1ps
module tb_rgb888_packer;
    reg clk=0,reset_n=0,flush=0;
    always #5 clk=~clk;
    reg pixel_valid=0,pixel_last=0;
    reg [23:0] pixel_rgb=0;
    wire pixel_ready;
    wire s_valid,s_row_last;
    wire [127:0] s_data;
    wire [15:0] s_keep;
    reg s_ready=0;
    rgb888_packer dut(.*);
    integer cycle=0,read_byte=0,expected_bytes=0,rows_received=0,cases=0;
    reg [7:0] oracle[0:8191];
    integer row_end[0:63];
    reg stalled=0;
    reg [144:0] held;
    reg check_enabled=0;
    always @(negedge clk)begin
        cycle=cycle+1;
        s_ready=(cycle%9!=0 && cycle%9!=1 && cycle%9!=2);
    end
    integer k;
    always @(posedge clk)begin
        if(!reset_n || flush)stalled=0;
        else begin
            if(stalled && {s_data,s_keep,s_row_last}!==held)$fatal(1,"packer stalled payload changed");
            stalled=s_valid && !s_ready;
            held={s_data,s_keep,s_row_last};
            if(s_valid && s_ready && check_enabled)begin
                if(s_keep==0 || (({1'b0,s_keep}+17'd1)&{1'b0,s_keep})!=0)
                    $fatal(1,"packer keep not contiguous");
                for(k=0;k<16;k=k+1)if(s_keep[k])begin
                    if(read_byte>=expected_bytes || s_data[k*8+:8]!==oracle[read_byte])
                        $fatal(1,"packer byte mismatch index=%0d actual=%h expected=%h",read_byte,s_data[k*8+:8],oracle[read_byte]);
                    read_byte=read_byte+1;
                end
                if(s_row_last)begin
                    if(read_byte!=row_end[rows_received])$fatal(1,"packer row split");
                    rows_received=rows_received+1;
                end else if(s_keep!=16'hffff)$fatal(1,"partial beat inside row");
            end
        end
    end
    task automatic send_row(input integer pixels,input integer tag);
        integer p;
        reg [23:0] color;
        begin
            for(p=0;p<pixels;p=p+1)begin
                color={(8'(p+tag)),(8'(p*3+tag+1)),(8'(p*7+tag+2))};
                oracle[expected_bytes]=color[23:16];oracle[expected_bytes+1]=color[15:8];oracle[expected_bytes+2]=color[7:0];
                expected_bytes=expected_bytes+3;
            end
            row_end[cases]=expected_bytes;cases=cases+1;
            for(p=0;p<pixels;p=p+1)begin
                @(negedge clk);pixel_valid=1;pixel_last=p==pixels-1;
                pixel_rgb={(8'(p+tag)),(8'(p*3+tag+1)),(8'(p*7+tag+2))};
                @(posedge clk);while(!pixel_ready)@(posedge clk);
                @(negedge clk);pixel_valid=0;pixel_last=0;
            end
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);reset_n=1;check_enabled=1;
        send_row(1,7);send_row(5,9);send_row(6,11);send_row(13,13);send_row(16,17);
        send_row(17,19);send_row(400,23);send_row(800,29);
        wait(rows_received==cases);repeat(4)@(negedge clk);
        if(read_byte!=expected_bytes)$fatal(1,"packer byte count");
        check_enabled=0;
        @(negedge clk);pixel_valid=1;pixel_last=0;pixel_rgb=24'h112233;
        @(posedge clk);while(!pixel_ready)@(posedge clk);
        @(negedge clk);pixel_valid=0;flush=1;
        @(negedge clk);flush=0;
        repeat(3)@(negedge clk);
        if(s_valid)$fatal(1,"flush retained partial row");
        read_byte=0;expected_bytes=0;rows_received=0;cases=0;check_enabled=1;
        send_row(6,41);wait(rows_received==1);
        @(negedge clk);reset_n=0;
        #1;if(s_valid)$fatal(1,"reset output not cleared");
        $display("RGB888_PACKER_PASS rows=9 spill=1 tails=1 stalls=1 flush=1");$finish;
    end
    initial begin #2000000;$fatal(1,"packer watchdog");end
endmodule
