`timescale 1ns/1ps
`default_nettype none
module tb_detect_nchw_dma #(
    parameter integer W=17,AH=3,PT=2,PB=1,GAP=16,BILINEAR=0
);
    localparam integer H=PT+AH+PB,RS=((W+15)/16)*16+GAP,PS=RS*H+GAP;
    localparam integer SIZE=3*PS+32,TOTAL=3*W*H,FW=W*5/2,FH=AH*5/2;
    localparam [31:0] BASE=32'h82800ff0;
    reg clk=0,reset_n=0,online=1,abort=0,req_valid=0,result_ready=0;
    reg [31:0] req_base=BASE,req_tag=32'h320da7a;
    reg enabled=0,bad_rgb=0,hold_aw=0,hold_w=0,hold_b=0;
    reg [1:0] bad_last=0;
    reg inject_bus=0,inject_id=0;
    integer sent=0,cycle=0,tag=0,testcase=0,frames=0;
    wire req_ready,s_ready,result_valid,result_success,fault,busy;
    wire [7:0] result_code;
    wire [31:0] result_tag,written_bytes;
    wire s_valid,s_row_last;
    wire [23:0] s_rgb;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid,awready,wvalid,wready,wlast,bready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg bvalid=0;
    wire [1:0] bresp=inject_bus?2'b10:2'b00;
    wire [3:0] bid=inject_id?4'd5:4'd3;
    always #4 clk=~clk;

    function automatic [7:0] source_byte(input integer x,y,c,t);
        integer seed;
        begin
            seed=t==4?1:t==5?7:0;
            case(t)
                0:source_byte=0;
                1:source_byte=255;
                2:source_byte=c==0?211:c==1?93:17;
                default:source_byte=8'((37*x+19*y+83*c+((x*y)>>3)+seed*(7*(x%7)+13*(y%11)+29*c))%256);
            endcase
        end
    endfunction
    function automatic [23:0] source_rgb(input integer x,y,t);
        source_rgb={source_byte(x,y,0,t),source_byte(x,y,1,t),source_byte(x,y,2,t)};
    endfunction
    function automatic [7:0] expected_byte(input integer row,x,plane);
        integer sx,sy,lx,rx,ty,by,upper,lower;
        begin
            if(row<PT||row>=PT+AH)expected_byte=0;
            else if(!BILINEAR)expected_byte=source_byte(x,row-PT,2-plane,tag);
            else begin
                sx=(5*x+1)/2;sy=(5*(row-PT)+1)/2;
                lx=x%2==0?1:3;rx=4-lx;ty=(row-PT)%2==0?1:3;by=4-ty;
                upper=lx*int'(source_byte(sx,sy,2-plane,tag))+rx*int'(source_byte(sx+1,sy,2-plane,tag));
                lower=lx*int'(source_byte(sx,sy+1,2-plane,tag))+rx*int'(source_byte(sx+1,sy+1,2-plane,tag));
                expected_byte=8'((ty*upper/4+by*lower/4+2)/4);
            end
        end
    endfunction
    generate if(BILINEAR)begin:g_scale
        wire ready,scale_fault;
        wire valid=enabled&&sent<FW*FH;
        detect_bilinear #(.FRAME_WIDTH(FW),.FRAME_HEIGHT(FH)) scaler(
            .clk(clk),.reset_n(reset_n),.clear(1'b0),.s_valid(valid),.s_ready(ready),
            .s_rgb(source_rgb(sent%FW,sent/FW,tag)),.s_row_last(sent%FW==FW-1),
            .m_valid(s_valid),.m_ready(s_ready),.m_rgb(s_rgb),.m_row_last(s_row_last),.fault(scale_fault));
        always @(posedge clk)if(reset_n)begin
            if(valid&&ready)sent<=sent+1;
            if(scale_fault)$fatal(1,"unexpected scaler fault");
        end
    end else begin:g_direct
        assign s_valid=enabled&&sent<W*AH;
        assign s_rgb=bad_rgb?24'hxxxxxx:source_rgb(sent%W,sent/W,tag);
        assign s_row_last=bad_last==1?1'bx:bad_last==2?1'b1:bad_last==3?1'b0:sent%W==W-1;
        always @(posedge clk)if(reset_n&&s_valid&&s_ready)sent<=sent+1;
    end endgenerate
    detect_nchw_dma #(.WIDTH(W),.ACTIVE_HEIGHT(AH),.PAD_TOP(PT),.PAD_BOTTOM(PB),
        .ROW_STRIDE(RS),.PLANE_STRIDE(PS)) dut(
        .clk(clk),.reset_n(reset_n),.online(online),.abort(abort),
        .req_valid(req_valid),.req_ready(req_ready),.req_base(req_base),.req_tag(req_tag),
        .s_valid(s_valid),.s_ready(s_ready),.s_rgb(s_rgb),.s_row_last(s_row_last),
        .result_valid(result_valid),.result_ready(result_ready),.result_success(result_success),
        .result_code(result_code),.result_tag(result_tag),.written_bytes(written_bytes),.busy(busy),.fault(fault),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));

    reg [7:0] memory[0:SIZE-1];
    reg touched[0:SIZE-1];
    reg active=0,pending_b=0,final_b=0,held_aw=0,held_w=0,held_result=0;
    reg [43:0] aw_payload;
    reg [144:0] w_payload;
    reg [72:0] result_payload;
    reg [31:0] address=0;
    integer beats=0,wi=0,bdelay=0,bytes_written=0,bursts=0,responses=0,ack_bytes=0,burst_bytes=0;
    integer b,offset,plane,row,x,new_bytes,fd,i,n,t;
    string prefix;
    assign awready=reset_n&&!hold_aw&&!active&&!pending_b&&!bvalid&&cycle%5!=1;
    assign wready=reset_n&&!hold_w&&active&&cycle%7>=3;
    always @(posedge clk)begin
        if(!reset_n)begin
            cycle<=0;active<=0;pending_b<=0;bvalid<=0;final_b<=0;bytes_written<=0;
            bursts<=0;responses<=0;bdelay<=0;held_aw<=0;held_w<=0;held_result<=0;ack_bytes<=0;burst_bytes<=0;
        end else begin
            cycle<=cycle+1;
            if(held_aw&&(!awvalid||{awid,awaddr,awlen}!==aw_payload))$fatal(1,"AW withdrawn/changed");
            if(held_w&&(!wvalid||{wlast,wstrb,wdata}!==w_payload))$fatal(1,"W withdrawn/changed");
            if(held_result&&(!result_valid||{result_success,result_code,result_tag,written_bytes}!==result_payload))$fatal(1,"result withdrawn/changed");
            held_aw<=awvalid&&!awready;aw_payload<={awid,awaddr,awlen};
            held_w<=wvalid&&!wready;w_payload<={wlast,wstrb,wdata};
            held_result<=result_valid&&!result_ready;result_payload<={result_success,result_code,result_tag,written_bytes};
            if(awvalid&&awready)begin
                if(active||pending_b||awid!==3||awsize!==4||awburst!==1||awlen>15||
                   int'(awaddr[11:0])+(int'(awlen)+1)*16>4096)$fatal(1,"bad AXI burst");
                address<=awaddr;beats<=int'(awlen)+1;wi<=0;active<=1;bursts<=bursts+1;burst_bytes<=0;
            end
            if(wvalid&&wready)begin
                if(wlast!==(wi==beats-1))$fatal(1,"bad WLAST");
                new_bytes=0;
                for(b=0;b<16;b=b+1)if(wstrb[b])begin
                    offset=int'(address-BASE)+wi*16+b;plane=offset/PS;row=(offset%PS)/RS;x=(offset%PS)%RS;
                    if(offset<0||plane>=3||row>=H||x>=W)$fatal(1,"write to guard/stride/plane gap");
                    if(wdata[b*8+:8]!==expected_byte(row,x,plane))$fatal(1,"NCHW mismatch p=%0d y=%0d x=%0d got=%h expected=%h",plane,row,x,wdata[b*8+:8],expected_byte(row,x,plane));
                    if(touched[16+offset])$fatal(1,"duplicate byte write");
                    touched[16+offset]<=1;memory[16+offset]<=wdata[b*8+:8];new_bytes=new_bytes+1;
                end
                bytes_written<=bytes_written+new_bytes;
                burst_bytes<=burst_bytes+new_bytes;
                if(wlast)begin
                    active<=0;pending_b<=1;bdelay<=0;
                    if(bytes_written+new_bytes==TOTAL)final_b<=1;
                end else wi<=wi+1;
            end
            if(pending_b&&!bvalid)begin
                if(bdelay<7)bdelay<=bdelay+1;
                else if(!hold_b)bvalid<=1;
            end
            if(bvalid&&bready)begin
                bvalid<=0;pending_b<=0;responses<=responses+1;
                if(bid==3&&bresp==0)ack_bytes<=ack_bytes+burst_bytes;
            end
            if(result_valid&&(active||pending_b||bvalid))$fatal(1,"result before AXI drain");
            if(result_valid&&result_success&&responses!=bursts)$fatal(1,"success before B retirement");
        end
    end
    task automatic start;
        begin
            @(negedge clk);reset_n=0;enabled=0;req_valid=0;result_ready=0;online=1;abort=0;
            sent=0;bad_last=0;bad_rgb=0;hold_aw=0;hold_w=0;hold_b=0;inject_bus=0;inject_id=0;req_base=BASE;
            for(i=0;i<SIZE;i=i+1)begin memory[i]=8'ha5;touched[i]=0;end
            repeat(4)@(negedge clk);reset_n=1;
        end
    endtask
    task automatic request;
        begin
            @(negedge clk);req_valid=1;
            @(posedge clk);while(!req_ready)@(posedge clk);
            @(negedge clk);req_valid=0;enabled=1;
        end
    endtask
    task automatic finish_result(input integer code);
        begin
            wait(result_valid);@(negedge clk);
            if(result_code!==8'(code)||result_success!==(code==0)||result_tag!==req_tag)$fatal(1,"bad result code got=%0d expected=%0d",result_code,code);
            repeat(35)@(negedge clk);
            if(written_bytes!=ack_bytes)$fatal(1,"acknowledged-byte count mismatch");
            if(code==0)begin
                if(written_bytes!=TOTAL||bytes_written!=TOTAL||sent!=(BILINEAR?FW*FH:W*AH))$fatal(1,"bad complete counters");
                for(n=0;n<SIZE;n=n+1)begin
                    offset=n-16;plane=offset/PS;row=(offset%PS)/RS;x=(offset%PS)%RS;
                    if(offset>=0&&plane<3&&row<H&&x<W)begin
                        if(memory[n]!==expected_byte(row,x,plane))$fatal(1,"memory mismatch");
                    end else if(memory[n]!==8'ha5)$fatal(1,"guard changed");
                end
                if(prefix!="")begin
                    fd=$fopen($sformatf("%s_%0d.hex",prefix,tag),"w");
                    if(!fd)$fatal(1,"dump open failed");
                    for(plane=0;plane<3;plane=plane+1)for(row=0;row<H;row=row+1)for(x=0;x<W;x=x+1)
                        $fdisplay(fd,"%02h",memory[16+plane*PS+row*RS+x]);
                    $fclose(fd);
                end
            end else if(awvalid||wvalid||s_ready||req_ready)$fatal(1,"failed request still active");
            frames=frames+1;
        end
    endtask
    initial begin
        if($value$plusargs("CASE=%d",testcase))begin end
        if($value$plusargs("DUMP=%s",prefix))begin end
        if(testcase==0)begin
            for(t=0;t<6;t=t+1)begin
                start();tag=t;request();
                // Block only the final response, after all earlier responses retire.
                wait(final_b);@(negedge clk);hold_b=1;
                repeat(193)@(negedge clk);
                if(result_valid)$fatal(1,"early tensor completion");
                hold_b=0;finish_result(0);
            end
        end else begin
            start();tag=3;
            if(testcase==11)req_base=BASE+1;
            if(testcase==12)req_base=32'h87fffff0;
            if(testcase==13)req_base=32'hxxxxxxxx;
            request();
            case(testcase)
                1:begin wait(s_ready);@(negedge clk);abort=1;finish_result(3);end
                2:begin hold_aw=1;wait(awvalid);repeat(3)@(negedge clk);abort=1;repeat(20)@(negedge clk);hold_aw=0;finish_result(3);end
                3:begin hold_w=1;wait(wvalid);repeat(3)@(negedge clk);abort=1;repeat(20)@(negedge clk);hold_w=0;finish_result(3);end
                4:begin hold_b=1;wait(pending_b);repeat(3)@(negedge clk);abort=1;repeat(20)@(negedge clk);hold_b=0;finish_result(3);end
                5:begin wait(s_ready);@(negedge clk);online=0;finish_result(4);end
                6:begin wait(s_ready);@(negedge clk);bad_last=1;finish_result(2);end
                7:begin wait(s_ready);@(negedge clk);bad_rgb=1;finish_result(2);end
                8:begin inject_bus=1;finish_result(6);end
                9:begin inject_id=1;finish_result(5);end
                10:begin // Payload is irrelevant while intake is blocked.
                    wait(awvalid);@(negedge clk);bad_last=1;bad_rgb=1;
                    repeat(2)@(negedge clk);bad_last=0;bad_rgb=0;finish_result(0);
                end
                11,12,13:begin finish_result(1);if(bursts!=0)$fatal(1,"invalid descriptor wrote memory");end
                14:begin
                    finish_result(0);enabled=0;result_ready=1;
                    repeat(2)@(negedge clk);result_ready=0;
                    if(!req_ready)$fatal(1,"success not reusable");
                    sent=0;bytes_written=0;bursts=0;responses=0;ack_bytes=0;final_b=0;tag=4;req_tag=req_tag+1;
                    for(i=0;i<SIZE;i=i+1)begin memory[i]=8'ha5;touched[i]=0;end
                    request();finish_result(0);
                end
                15:begin wait(s_ready);@(negedge clk);bad_last=2;finish_result(2);end
                16:begin wait(sent==W-1);@(negedge clk);bad_last=3;finish_result(2);end
                17:begin hold_aw=1;wait(awvalid);repeat(3)@(negedge clk);online=0;repeat(20)@(negedge clk);hold_aw=0;finish_result(4);end
                18:begin hold_w=1;wait(wvalid);repeat(3)@(negedge clk);online=0;repeat(20)@(negedge clk);hold_w=0;finish_result(4);end
                19:begin hold_b=1;wait(pending_b);repeat(3)@(negedge clk);online=0;repeat(20)@(negedge clk);hold_b=0;finish_result(4);end
                20:begin hold_aw=1;wait(awvalid);repeat(3)@(negedge clk);abort=1;repeat(20)@(negedge clk);abort=0;hold_aw=0;finish_result(3);end
                21:begin
                    wait(s_ready);@(negedge clk);force bvalid=1;
                    @(negedge clk);release bvalid;bvalid=0;finish_result(7);
                end
                22,24,25:begin
                    hold_aw=1;wait(awvalid);@(negedge clk);force bvalid=1;
                    @(negedge clk);release bvalid;bvalid=0;
                    repeat(3)@(negedge clk);
                    inject_bus=testcase==24;inject_id=testcase==25;hold_aw=0;finish_result(7);
                end
                23:begin
                    hold_w=1;wait(wvalid);@(negedge clk);force bvalid=1;
                    @(negedge clk);release bvalid;bvalid=0;
                    repeat(3)@(negedge clk);hold_w=0;finish_result(7);
                end
                26,27,28,29:begin
                    inject_bus=testcase==26||testcase==28;
                    inject_id=testcase==27||testcase==29;
                    wait(bvalid&&bready);@(posedge clk);
                    @(negedge clk);
                    if(testcase<28)abort=1;else online=0;
                    finish_result(inject_bus?6:5);
                end
                30,31,32,33:begin
                    hold_aw=testcase==30||testcase==32;hold_w=!hold_aw;
                    if(hold_aw)wait(awvalid);else wait(wvalid);
                    @(negedge clk);force bvalid=1;
                    @(negedge clk);release bvalid;bvalid=0;
                    if(testcase<32)abort=1;else online=0;
                    repeat(20)@(negedge clk);hold_aw=0;hold_w=0;finish_result(7);
                end
                default:$fatal(1,"unknown case");
            endcase
        end
        $display("DETECT_NCHW_DMA_PASS W=%0d AH=%0d PT=%0d PB=%0d GAP=%0d bilinear=%0d case=%0d frames=%0d bytes=%0d",W,AH,PT,PB,GAP,BILINEAR,testcase,frames,TOTAL);$finish;
    end
    initial begin #500000000;$fatal(1,"NCHW global timeout");end
endmodule
`default_nettype wire
