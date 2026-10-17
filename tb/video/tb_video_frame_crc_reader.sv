`timescale 1ns/1ps
`default_nettype none
module tb_video_frame_crc_reader;
    reg clk=0;always #4 clk=~clk;
    reg reset_n=0,online=1,abort=0,req_valid=0,result_ready=0;
    reg [31:0] req_base=32'h87300ff0,req_row_bytes=43,req_stride=64,req_tag=19,expected_crc=32'ha62eaeaa;
    reg [15:0] req_rows=3;
    wire req_ready,result_valid,result_success,busy,fault;
    wire [7:0] result_code;
    wire [31:0] result_tag,checked_bytes,crc;
    wire [3:0] arid;wire [31:0] araddr;wire [7:0] arlen;
    wire [2:0] arsize;wire [1:0] arburst;wire arvalid,rready;
    reg arready=1,rvalid=0,rlast=0;reg [3:0] rid=6;
    reg [1:0] rresp=0;reg [127:0] rdata=0;
    video_frame_crc_reader #(.TIMEOUT_CYCLES(5000)) dut(.*);
    integer mode=0,cycles=0,reads=0,beats=0,index_q=0,total_q=0,lane;
    reg active=0;reg [31:0] address_q;
    function automatic [7:0] memory_byte(input [31:0] address);
        memory_byte=(address[7:0]*37+address[15:8]*11+13)&255;
    endfunction
    always @(posedge clk)begin
        if(!reset_n)begin active<=0;rvalid<=0;cycles<=0;reads<=0;beats<=0;end
        else begin
            cycles<=cycles+1;
            if(arvalid&&arready)begin
                if(active || arid!==4'h6 || arsize!==3'd4 || arburst!==2'b01 || arlen>15 ||
                    {1'b0,araddr[11:0]}+({5'd0,arlen}+13'd1)*13'd16>4096)
                    $fatal(1,"Illegal/overlapping read burst");
                if(araddr<req_base || araddr>=req_base+req_stride*req_rows)$fatal(1,"Read outside image");
                active<=1;address_q<=araddr;index_q<=0;total_q<=arlen+1;reads<=reads+1;
            end
            if(rvalid&&rready)begin
                rvalid<=0;beats<=beats+1;
                if(index_q==total_q-1)active<=0;
                else begin index_q<=index_q+1;address_q<=address_q+16;end
            end
            if(active&&!rvalid&&cycles%3!=0)begin
                for(lane=0;lane<16;lane=lane+1)rdata[lane*8+:8]<=memory_byte(address_q+lane);
                rid<=mode==1?4'h7:4'h6;
                rresp<=mode==2?2'b10:2'b00;
                rlast<=mode==3?(index_q!=total_q-1):(index_q==total_q-1);
                if(mode==4)rdata[7:0]<=8'hxx;
                rvalid<=1;
            end
        end
    end
    task automatic reset_case(input integer newmode);
        begin
            @(negedge clk);reset_n=0;req_valid=0;result_ready=0;abort=0;online=1;arready=1;mode=newmode;
            req_base=32'h87300ff0;expected_crc=32'ha62eaeaa;req_tag=19;
            repeat(4)@(negedge clk);reset_n=1;
        end
    endtask
    task automatic request;
        begin
            @(negedge clk);req_valid=1;
            while(!req_ready)@(negedge clk);
            @(negedge clk);req_valid=0;
        end
    endtask
    task automatic result_check(input bit success);
        reg [71:0] held;
        begin
            wait(result_valid);@(negedge clk);
            if(result_success!==success || result_tag!==19 || busy)$fatal(1,"Wrong result");
            if(success&&(checked_bytes!==129||crc!==32'ha62eaeaa||reads!=4||beats!=9))
                $fatal(1,"Wrong CRC/count/burst split bytes=%0d crc=%h reads=%0d beats=%0d",checked_bytes,crc,reads,beats);
            held={result_code,checked_bytes,crc};
            repeat(7)begin @(negedge clk);if(!result_valid || {result_code,checked_bytes,crc}!==held)$fatal(1,"Result not held");end
            result_ready=1;@(negedge clk);result_ready=0;
        end
    endtask
    integer k;
    initial begin
        reset_case(0);request();result_check(1);
        // A second request needs no global reset after a healthy completion.
        request();wait(result_valid);if(!result_success)$fatal(1,"Second request failed");
        for(k=1;k<=4;k=k+1)begin reset_case(k);request();result_check(0);if(!fault)$fatal(1,"Missing sticky fault");end
        reset_case(0);expected_crc=0;request();result_check(0);
        reset_case(0);req_base=32'h87300ff1;request();result_check(0);if(reads!=0)$fatal(1,"Bad descriptor issued AR");
        reset_case(0);arready=0;request();wait(arvalid);
        @(negedge clk);abort=1;
        repeat(12)begin @(negedge clk);if(!arvalid||result_valid)$fatal(1,"Aborted advertised AR withdrawn");end
        arready=1;result_check(0);if(active)$fatal(1,"Aborted read not drained");
        reset_case(0);request();wait(rvalid);@(negedge clk);online=0;result_check(0);
        reset_case(4);expected_crc=32'hxxxxxxxx;request();result_check(0);
        reset_case(0);req_tag=32'hxxxxxxxx;request();wait(result_valid);
        if(result_success || result_code!==1 || reads!=0)$fatal(1,"Unknown tag accepted");
        reset_case(0);request();wait(result_valid);
        begin:held_result_protocol_fault
            reg [71:0] held;
            @(negedge clk);held={result_code,checked_bytes,crc};force rvalid=1;
            repeat(4)begin @(negedge clk);
                if(!result_valid || {result_code,checked_bytes,crc}!==held)$fatal(1,"Stray R mutated held RESULT payload");
            end
            if(!fault)$fatal(1,"Stray R did not report separate fault");
            release rvalid;
        end
        reset_case(0);arready=0;request();wait(arvalid);repeat(5010)@(negedge clk);
        if(!arvalid || result_valid || !fault)$fatal(1,"Timeout withdrew advertised AR");
        arready=1;result_check(0);if(active)$fatal(1,"Timed-out burst not drained");
        reset_case(0);request();wait(dut.state==4);@(negedge clk);abort=1;
        result_check(0);if(active)$fatal(1,"Byte-processing abort not drained");
        $display("VIDEO_FRAME_CRC_READER_PASS cases=15");$finish;
    end
    initial begin #2000000;$fatal(1,"CRC reader test timeout");end
endmodule
`default_nettype wire
