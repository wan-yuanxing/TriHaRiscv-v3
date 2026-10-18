`timescale 1ns/1ps
`default_nettype none
module tb_video_frame_crc_checksum;
    reg clk=0;always #4 clk=~clk;
    reg reset_n=0,online=1,abort=0,req_valid=0,result_ready=0;
    reg [31:0] req_base=32'h82800ff0,req_row_bytes=19,req_stride=32,req_tag=3,expected_crc=0;
    reg [15:0] req_rows=3;
    wire req_ready,result_valid,result_success,busy,fault;
    wire [7:0] result_code;wire [31:0] result_tag,checked_bytes,crc;
    wire [3:0] arid;wire [31:0] araddr;wire [7:0] arlen;wire [2:0] arsize;wire [1:0] arburst;
    wire arvalid,rready;reg arready=1,rvalid=0,rlast=0;reg [3:0] rid=6;reg [1:0] rresp=0;reg [127:0] rdata=0;
    video_frame_crc_reader #(.CHECK_EXPECTED_CRC(0),.TIMEOUT_CYCLES(300)) dut(.*);
    integer mode=0,cycles=0,reads=0,index_q=0,total_q=0,lane,tests=0;
    reg active=0;reg [31:0] address_q;
    function automatic [7:0] value(input [31:0] a);value=8'(a*29+(a>>8)*17+3);endfunction
    function automatic [31:0] oracle;
        reg [31:0] c;reg [7:0] b;integer y,x,n;
        begin
            c=32'hffffffff;
            for(y=0;y<3;y=y+1)for(x=0;x<19;x=x+1)begin
                b=value(req_base+y*32+x);
                for(n=0;n<8;n=n+1)c=(c>>1)^((c[0]^b[n])?32'hedb88320:0);
            end
            oracle=~c;
        end
    endfunction
    always @(posedge clk)begin
        if(!reset_n)begin active<=0;rvalid<=0;cycles<=0;reads<=0;end
        else begin
            cycles<=cycles+1;
            if(arvalid&&arready)begin
                if(active||arid!==6||arsize!==4||arburst!==1)$fatal(1,"checksum read ownership/descriptor");
                active<=1;address_q<=araddr;index_q<=0;total_q<=arlen+1;reads<=reads+1;
            end
            if(rvalid&&rready)begin
                rvalid<=0;
                if(index_q==total_q-1)active<=0;
                else begin index_q<=index_q+1;address_q<=address_q+16;end
            end
            if(active&&!rvalid&&cycles%3!=0)begin
                for(lane=0;lane<16;lane=lane+1)rdata[lane*8+:8]<=value(address_q+lane);
                if(mode==1)rdata[7:0]<=8'hxx;
                if(mode==2)rdata[7:0]<=8'hzz;
                rid<=mode==3?7:6;rresp<=mode==4?2:0;
                rlast<=mode==5?(index_q!=total_q-1):(index_q==total_q-1);rvalid<=1;
            end
        end
    end
    task automatic restart(input integer m);
        begin
            @(negedge clk);reset_n=0;req_valid=0;result_ready=0;abort=0;online=1;arready=1;mode=m;expected_crc=0;req_tag=3;
            repeat(4)@(negedge clk);reset_n=1;
        end
    endtask
    task automatic request;
        begin @(negedge clk);req_valid=1;while(!req_ready)@(negedge clk);@(negedge clk);req_valid=0;end
    endtask
    task automatic result_check(input bit success,input integer code);
        reg [104:0] held;
        begin
            wait(result_valid);@(negedge clk);
            if(result_success!==success||result_code!==8'(code)||busy||active)$fatal(1,"checksum result mode=%0d code=%h",mode,result_code);
            if(success&&(crc!==oracle()||checked_bytes!==57||result_tag!==3||reads%4!=0||reads==0||fault))$fatal(1,"checksum skips holes / computes CRC");
            held={result_success,result_code,result_tag,checked_bytes,crc};
            repeat(9)begin @(negedge clk);if(!result_valid||{result_success,result_code,result_tag,checked_bytes,crc}!==held)$fatal(1,"checksum result changed while held");end
            result_ready=1;@(negedge clk);result_ready=0;tests=tests+1;
        end
    endtask
    integer m;
    initial begin
        restart(0);request();result_check(1,0);
        request();result_check(1,0);
        for(m=1;m<=5;m=m+1)begin restart(m);request();result_check(0,m<=2?11:5);if(!fault)$fatal(1,"checksum missing sticky fault");end
        restart(0);expected_crc=32'hxxxxxxxx;request();result_check(0,1);if(reads)$fatal(1,"unknown expected_crc accepted in checksum mode");
        restart(0);req_tag=32'hxxxxxxxx;request();result_check(0,1);if(reads)$fatal(1,"unknown tag accepted");
        restart(0);arready=0;request();wait(arvalid);@(negedge clk);abort=1;
        repeat(15)begin @(negedge clk);if(!arvalid||result_valid)$fatal(1,"abort withdrew checksum AR");end
        arready=1;result_check(0,3);
        restart(0);arready=0;request();wait(arvalid);repeat(310)@(negedge clk);
        if(!arvalid||result_valid||!fault)$fatal(1,"timeout withdrew checksum AR");arready=1;result_check(0,4);
        restart(0);request();wait(rvalid);@(negedge clk);online=0;result_check(0,2);
        restart(0);request();wait(result_valid);
        begin:held_stray
            reg [103:0] saved;
            @(negedge clk);saved={result_code,result_tag,checked_bytes,crc};force rvalid=1;
            repeat(4)begin @(negedge clk);if(!result_valid||{result_code,result_tag,checked_bytes,crc}!==saved)$fatal(1,"stray response changed held result");end
            if(!fault)$fatal(1,"stray response missing fault");release rvalid;tests=tests+1;
        end
        restart(0);request();wait(dut.state==4);restart(0);request();result_check(1,0);
        $display("VIDEO_FRAME_CRC_CHECKSUM_PASS tests=%0d",tests);$finish;
    end
    initial begin #1000000;$fatal(1,"checksum test timeout");end
endmodule
`default_nettype wire
