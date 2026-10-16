`timescale 1ns/1ps
module tb_diag_uart;
    reg clk=0,reset_n=0;
    always #5 clk=~clk;
    reg [255:0] payload;
    wire tx,busy;
    video_diag_uart #(.CLOCK_HZ(1000),.BAUD(100),.INTERVAL_CYCLES(4000)) dut(
        .clk(clk),.reset_n(reset_n),.payload(payload),.tx(tx),.busy(busy));
    task read_byte(output reg[7:0] value);
        integer b;
        begin
            @(negedge tx);repeat(5)@(posedge clk);#1;
            if(tx!==0)$fatal(1,"Bad UART start");
            for(b=0;b<8;b=b+1)begin repeat(10)@(posedge clk);#1;value[b]=tx;end
            repeat(10)@(posedge clk);#1;if(tx!==1)$fatal(1,"Bad UART stop");
        end
    endtask
    task read_packet(input[255:0] expected);
        integer j;
        reg[7:0] value,checksum,want;
        begin
            checksum=0;
            for(j=0;j<37;j=j+1)begin
                read_byte(value);
                case(j)
                    0:want="T";1:want="R";2:want="V";3:want="1";
                    36:want=checksum;
                    default:want=expected[(j-4)*8+:8];
                endcase
                if(value!==want)$fatal(1,"UART byte%0d got%h expected%h",j,value,want);
                checksum=checksum^value;
                if(j==1)payload=~expected; // Packet must already be latched.
            end
        end
    endtask
    integer k;
    reg[255:0] first;
    initial begin
        for(k=0;k<32;k=k+1)first[k*8+:8]=k^8'ha5;
        payload=first;#1;reset_n=0;repeat(3)@(negedge clk);reset_n=1;
        read_packet(first);read_packet(~first);
        @(negedge tx);#2;reset_n=0;#1;
        if(tx!==1 || busy!==0)$fatal(1,"UART reset did not release line");
        repeat(3)@(negedge clk);payload=first;reset_n=1;
        read_packet(first);
        $display("VIDEO_DIAG_UART_PASS: bit-level 8N1, coherent packets, checksum, reset");$finish;
    end
    initial begin #1000000;$fatal(1,"Watchdog");end
endmodule
