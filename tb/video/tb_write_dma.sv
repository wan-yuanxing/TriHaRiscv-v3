`timescale 1ns/1ps
module tb_write_dma;
    reg clk=0,reset_n=0,online=0,abort=0;
    always #5 clk=~clk;
    reg req_valid=0;
    wire req_ready;
    reg [31:0] req_base=0,req_row_bytes=0,req_stride=0,req_tag=0;
    reg [15:0] req_rows=0;
    reg s_valid=0,s_row_last=0;
    reg [127:0] s_data=0;
    reg [15:0] s_keep=0;
    wire s_ready,result_valid,result_success,busy,fault;
    reg result_ready=0;
    wire [7:0] result_code;
    wire [31:0] result_tag,written_bytes;
    wire [3:0] awid,bid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst,bresp;
    wire awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    video_write_dma dut(.*);
    localparam [31:0] BASE=32'h87300000;
    reg [7:0] memory[0:2097151];
    reg active=0,response=0;
    reg [31:0] address_q;
    reg [7:0] length_q;
    integer beat_q=0,tick=0,delay_q=0,aw_count=0,b_count=0,tests=0;
    reg [3:0] id_q;
    reg inject_bresp=0,inject_bid=0,inject_early_b=0,stall_aw=0,stall_w=0,stall_b=0;
    assign awready=reset_n && !active && !response && !stall_aw && tick%5==1;
    assign wready=reset_n && active && !stall_w && tick%4!=0;
    assign bvalid=inject_early_b || (response && !stall_b && delay_q==0);
    assign bid=id_q ^ (inject_bid?4'h1:4'h0);
    assign bresp=inject_bresp?2'b10:2'b00;
    reg hold_aw=0,hold_w=0;
    reg [48:0] aw_held;
    reg [144:0] w_held;
    integer j,index;
    always @(posedge clk)begin
        if(!reset_n)begin active<=0;response<=0;tick<=0;delay_q<=0;hold_aw<=0;hold_w<=0;end
        else begin
            tick<=tick+1;
            if(hold_aw && (!awvalid || {awid,awaddr,awlen,awsize,awburst}!==aw_held))$fatal(1,"DMA AW changed while stalled");
            if(hold_w && (!wvalid || {wdata,wstrb,wlast}!==w_held))$fatal(1,"DMA W changed while stalled");
            hold_aw<=awvalid&&!awready;aw_held<={awid,awaddr,awlen,awsize,awburst};
            hold_w<=wvalid&&!wready;w_held<={wdata,wstrb,wlast};
            if(awvalid&&awready)begin
                if(awsize!=4 || awburst!=1 || awlen>15 || awaddr[3:0]!=0 ||
                   ({1'b0,awaddr[11:0]}+((awlen+13'd1)<<4))>4096)$fatal(1,"DMA illegal AXI burst");
                if(awaddr<BASE || awaddr+(awlen+1)*16>BASE+2097152)$fatal(1,"DMA escaped test region");
                active<=1;address_q<=awaddr;length_q<=awlen;id_q<=awid;beat_q<=0;aw_count<=aw_count+1;
            end
            if(wvalid&&wready)begin
                if(wlast!=(beat_q==length_q))$fatal(1,"DMA WLAST");
                for(j=0;j<16;j=j+1)if(wstrb[j])begin
                    index=address_q-BASE+beat_q*16+j;memory[index]<=wdata[j*8+:8];
                end
                if(wlast)begin active<=0;response<=1;delay_q<=11;end
                else beat_q<=beat_q+1;
            end
            if(response && delay_q>0)delay_q<=delay_q-1;
            if(bvalid&&bready)begin response<=0;b_count<=b_count+1;end
        end
    end
    task automatic reset_all;
        begin
            @(negedge clk);reset_n=0;online=0;abort=0;req_valid=0;s_valid=0;result_ready=0;
            inject_bresp=0;inject_bid=0;inject_early_b=0;stall_aw=0;stall_w=0;stall_b=0;
            repeat(3)@(negedge clk);reset_n=1;online=1;
        end
    endtask
    task automatic request(input [31:0] base,input integer rowbytes,input integer stride,input integer rows,input integer tag);
        begin
            @(negedge clk);req_base=base;req_row_bytes=rowbytes;req_stride=stride;req_rows=rows;req_tag=tag;req_valid=1;
            @(posedge clk);while(!req_ready)@(posedge clk);
            @(negedge clk);req_valid=0;
        end
    endtask
    function automatic [7:0] expected_byte(input integer row,input integer col,input integer tag);
        expected_byte=8'(row*31+col*7+tag*13);
    endfunction
    task automatic send_rows(input integer rowbytes,input integer rows,input integer tag);
        integer y,x,lane,n;
        begin
            for(y=0;y<rows;y=y+1)for(x=0;x<rowbytes;x=x+16)begin
                n=rowbytes-x<16?rowbytes-x:16;
                @(negedge clk);s_valid=1;s_keep=16'hffff>>(16-n);s_row_last=x+n==rowbytes;
                s_data=0;for(lane=0;lane<n;lane=lane+1)s_data[lane*8+:8]=expected_byte(y,x+lane,tag);
                @(posedge clk);while(!s_ready)@(posedge clk);
                @(negedge clk);s_valid=0;
                if((x/16)%7==0)repeat(2)@(negedge clk);
            end
        end
    endtask
    task automatic take_result(input bit success,input integer tag,input integer count);
        reg [72:0] saved;
        begin
            wait(result_valid);#1;
            if(result_success!==success || result_tag!=tag || written_bytes!=count)
                $fatal(1,"DMA result success=%b tag=%d count=%d code=%d",result_success,result_tag,written_bytes,result_code);
            saved={result_success,result_tag,written_bytes,result_code};
            repeat(7)begin @(posedge clk);#1;if(!result_valid || {result_success,result_tag,written_bytes,result_code}!==saved)$fatal(1,"DMA result changed");end
            @(negedge clk);result_ready=1;@(negedge clk);result_ready=0;tests=tests+1;
        end
    endtask
    task automatic healthy(input integer offset,input integer rowbytes,input integer stride,input integer rows,input integer tag);
        integer y,x;
        begin
            for(y=0;y<rows*stride+64;y=y+1)memory[offset+y]=8'ha5;
            request(BASE+offset,rowbytes,stride,rows,tag);send_rows(rowbytes,rows,tag);
            take_result(1,tag,rowbytes*rows);
            for(y=0;y<rows;y=y+1)for(x=0;x<stride;x=x+1)begin
                if(memory[offset+y*stride+x] !== (x<rowbytes?expected_byte(y,x,tag):8'ha5))
                    $fatal(1,"DMA memory/padding mismatch y=%d x=%d",y,x);
            end
            if(memory[offset+rows*stride]!==8'ha5)$fatal(1,"DMA end guard");
        end
    endtask
    integer saved_aw;
    initial begin
        reset_all;
        healthy(0,39,48,3,1);healthy(4080,272,288,3,2);
        healthy(32,16,16,1,3);healthy(64,240,240,2,4);healthy(1024,256,256,1,5);
        healthy(0,2400,2400,600,6);healthy(0,1200,1200,300,7);
        saved_aw=aw_count;
        request(32'h87fffff0,32,32,1,8);take_result(0,8,0);
        request(BASE+1,16,16,1,9);take_result(0,9,0);
        request(BASE,0,16,1,10);take_result(0,10,0);
        request(BASE,32,16,1,11);take_result(0,11,0);
        if(aw_count!=saved_aw)$fatal(1,"invalid descriptor issued AW");
        request(BASE,39,48,1,12);
        @(negedge clk);s_valid=1;s_keep=16'h007f;s_row_last=0;
        @(posedge clk);while(!s_ready)@(posedge clk);
        @(negedge clk);s_valid=0;take_result(0,12,0);
        // Abort unpublished data.
        request(BASE,256,256,1,13);
        @(negedge clk);abort=1;@(negedge clk);abort=0;take_result(0,13,0);
        // Once AW is exposed, abort must preserve and finish the buffered burst.
        stall_aw=1;request(BASE,16,16,1,14);send_rows(16,1,14);wait(awvalid);
        @(negedge clk);abort=1;repeat(5)@(negedge clk);abort=0;stall_aw=0;
        take_result(0,14,16);
        inject_bresp=1;request(BASE,16,16,1,15);send_rows(16,1,15);take_result(0,15,0);inject_bresp=0;
        inject_bid=1;request(BASE,16,16,1,16);send_rows(16,1,16);take_result(0,16,0);
        if(!fault || req_ready)$fatal(1,"wrong BID must quarantine");
        reset_all;healthy(0,39,48,1,17);
        stall_aw=1;request(BASE,16,16,1,18);send_rows(16,1,18);wait(awvalid);
        @(negedge clk);inject_early_b=1;@(negedge clk);inject_early_b=0;
        if(!fault)$fatal(1,"early B must quarantine before write completion");
        stall_aw=0;take_result(0,18,16);
        reset_all;
        @(negedge clk);online=0;@(negedge clk);online=1;
        if(!fault || req_ready)$fatal(1,"idle online loss must quarantine until coordinated reset");
        reset_all;
        @(negedge clk);inject_early_b=1;req_valid=1;req_base=BASE;req_row_bytes=16;req_stride=16;req_rows=1;
        #1;if(req_ready)$fatal(1,"stray B must block same-edge descriptor acceptance");
        @(negedge clk);inject_early_b=0;req_valid=0;
        if(!fault || result_valid)$fatal(1,"idle stray B must fault without manufacturing result");
        reset_all;
        request(BASE,16,16,1,19);send_rows(16,1,19);wait(result_valid);
        @(negedge clk);inject_early_b=1;@(negedge clk);inject_early_b=0;
        if(!fault || !result_valid || !result_success || result_tag!=19 || written_bytes!=16)
            $fatal(1,"stray B while result held must fault without changing result");
        take_result(1,19,16);
        $display("VIDEO_WRITE_DMA_PASS cases=%0d aw=%0d b=%0d raw_and_preview=1",tests,aw_count,b_count);$finish;
    end
    initial begin #100000000;$fatal(1,"DMA test watchdog");end
endmodule
