`timescale 1ns/1ps
module tb_axi_capture_bist;
    parameter integer TEST_WIDTH=13, TEST_HEIGHT=3;
    localparam integer STRIDE=((TEST_WIDTH*3+15)/16)*16;
    localparam integer EXPECTED_BEATS=((TEST_WIDTH*3+15)/16)*TEST_HEIGHT;
    reg clk=0,reset_n=0,init_done=0;
    always #4 clk=~clk;
    wire busy,done,error;
    wire [7:0] phase,error_code;
    wire [31:0] compared_beats;
    wire [27:0] first_error_addr,axi_awaddr,axi_araddr;
    wire [255:0] first_error_xor,axi_wdata,axi_rdata;
    wire [31:0] axi_wstrb;
    wire [3:0] axi_awlen,axi_awuser_id,axi_arlen,axi_aruser_id,axi_wusero_id,axi_rid;
    wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_awready,axi_wready,axi_wusero_last;
    wire axi_arvalid,axi_arready,axi_rlast,axi_rvalid;
    reg corrupt_frame=0,drop_write=0,bad_mask=0,hold_aw=0,overrun_guard=0;
    integer tests=0,cycles=0;
    video_axi_capture_bist #(.FRAME_WIDTH(TEST_WIDTH),.FRAME_HEIGHT(TEST_HEIGHT),
        .TIMEOUT_CYCLES(1000)) dut(.*);
    capture_native_model #(.GUARD_OFFSET(((TEST_HEIGHT-1)*STRIDE+TEST_WIDTH*3+15)/16*16)) memory_model(.*);
    always @(posedge clk)begin
        cycles<=cycles+1;
        if(axi_awuser_ap || axi_aruser_ap)$fatal(1,"AP must remain zero");
        if(error && done)$fatal(1,"error must block PASS");
    end
    task automatic restart;
        begin
            @(negedge clk);reset_n=0;init_done=0;
            corrupt_frame=0;drop_write=0;bad_mask=0;hold_aw=0;overrun_guard=0;
            repeat(5)@(negedge clk);
            if(done || error || compared_beats!=0)$fatal(1,"reset retained result");
            reset_n=1;
            repeat(5)@(negedge clk);
            if(axi_awvalid || axi_arvalid)$fatal(1,"command before init");
            init_done=1;
        end
    endtask
    task automatic await_result(input bit expect_pass);
        integer n;
        reg [7:0] held_code;
        reg [31:0] held_compared;
        reg [27:0] held_address;
        reg [255:0] held_xor;
        begin
            n=0;
            while(!done && !error && n<10000000)begin @(negedge clk);n=n+1;end
            if(n==10000000)$fatal(1,"engine did not terminate phase=%h count=%d",phase,compared_beats);
            if(expect_pass)begin
                if(error || !done || phase!=8'ha5 || compared_beats!=EXPECTED_BEATS)
                    $fatal(1,"capture failed phase=%h code=%h beats=%d addr=%h xor=%h",phase,error_code,compared_beats,first_error_addr,first_error_xor);
                if(memory_model.earliest_reads==0)$fatal(1,"missing simultaneous AR/R coverage");
            end else begin
                if(done || !error || error_code==0)$fatal(1,"fault incorrectly passed test=%0d",tests);
                held_code=error_code;held_compared=compared_beats;
                held_address=first_error_addr;held_xor=first_error_xor;
                repeat(30)@(negedge clk);
                if(done || !error || error_code!==held_code || compared_beats!==held_compared ||
                    first_error_addr!==held_address || first_error_xor!==held_xor)
                    $fatal(1,"error diagnostics were not sticky");
            end
            tests=tests+1;
        end
    endtask
    integer x,y,c,index;
    reg [7:0] expected;
    initial begin
        restart();await_result(1);
        // Independent address and RGB oracle; padding may never be modified.
        for(y=0;y<TEST_HEIGHT;y=y+1)begin
            for(x=0;x<TEST_WIDTH;x=x+1)begin
                for(c=0;c<3;c=c+1)begin
                    case(c)
                        0:expected=(x%256)^8'h93;
                        1:expected=(y%256)^8'h65;
                        2:expected=(x+y+183)%256;
                    endcase
                    index=y*STRIDE+x*3+c;
                    if(memory_model.memory[index]!==expected)$fatal(1,"independent image byte %d",index);
                end
            end
            for(c=TEST_WIDTH*3;c<STRIDE;c=c+1)
                if(memory_model.memory[y*STRIDE+c]!==8'ha5)$fatal(1,"row padding overwritten");
        end
        if(!$test$plusargs("normal_only"))begin
            @(negedge clk);init_done=0;repeat(2)@(negedge clk);await_result(0);
            restart();corrupt_frame=1;await_result(0);
            if(compared_beats!=0 || first_error_addr!=28'h1cc0000 || first_error_xor[255:128]!=0 || first_error_xor[7:0]!=1)
                $fatal(1,"primary checker diagnostics");
            restart();drop_write=1;await_result(0);
            restart();bad_mask=1;await_result(0);
            restart();overrun_guard=1;await_result(0);
            if(compared_beats!=EXPECTED_BEATS || error_code!=8'h05)
                $fatal(1,"guard corruption was not caught after independent image comparison");
            restart();hold_aw=1;await_result(0);
            restart();
            wait(phase==8'h30);repeat(10)@(negedge clk);init_done=0;
            await_result(0);init_done=1;repeat(30)@(negedge clk);
            if(!error || done)$fatal(1,"reinit erased error");
            restart();await_result(1);
        end
        $display("VIDEO_AXI_CAPTURE_BIST_PASS width=%0d height=%0d tests=%0d beats=%0d cycles=%0d",TEST_WIDTH,TEST_HEIGHT,tests,compared_beats,cycles);
        $finish;
    end
endmodule

// Efficient byte-addressed allocation model; no DUT data-generation function
// or AXI/native lane mapping is reused. Native lacks RREADY.
module capture_native_model #(
    parameter integer GUARD_OFFSET=144
)(
    input wire clk,reset_n,input wire [7:0] phase,
    input wire corrupt_frame,drop_write,bad_mask,hold_aw,overrun_guard,
    input wire [27:0] axi_awaddr,axi_araddr,
    input wire [3:0] axi_awlen,axi_awuser_id,axi_arlen,axi_aruser_id,
    input wire axi_awvalid,axi_arvalid,
    output wire axi_awready,axi_arready,axi_wready,axi_rvalid,
    input wire [255:0] axi_wdata,input wire [31:0] axi_wstrb,
    output wire [255:0] axi_rdata,
    output wire [3:0] axi_wusero_id,axi_rid,
    output wire axi_wusero_last,axi_rlast
);
    reg [7:0] memory[0:2097151];
    integer tick=0,wi=0,ri=0,wn=0,rn=0,j,offset;
    reg writing=0,reading=0,dropped=0;
    reg [27:0] wa,ra;
    reg [3:0] wid,rid;
    reg stalled_aw=0,stalled_ar=0;
    reg [35:0] saved_aw,saved_ar;
    integer earliest_reads=0;
    wire aw=axi_awvalid&&axi_awready,ar=axi_arvalid&&axi_arready;
    assign axi_awready=reset_n&&!writing&&!reading&&!hold_aw&&tick%5==1;
    assign axi_arready=reset_n&&!writing&&!reading&&tick%7==2;
    assign axi_wready=reset_n&&(writing||aw)&&tick%4!=0;
    assign axi_rvalid=reset_n&&(reading||ar)&&(ar||tick%3!=0);
    assign axi_wusero_id=writing?wid:axi_awuser_id;
    assign axi_rid=reading?rid:axi_aruser_id;
    assign axi_wusero_last=writing?wi==wn-1:axi_awlen==0;
    assign axi_rlast=reading?ri==rn-1:axi_arlen==0;
    function automatic [255:0] fetch(input [27:0] word_address,input integer revision);
        integer k,base;
        begin
            base=word_address*4-32'h07300000;fetch=0;
            if(base>=0 && base+31<2097152)
                for(k=0;k<32;k=k+1)fetch[k*8+:8]=memory[base+k];
        end
    endfunction
    assign axi_rdata=fetch(reading?ra:axi_araddr,tick)^((corrupt_frame&&phase==8'h40)?256'd1:256'd0);
    initial for(j=0;j<2097152;j=j+1)memory[j]=8'ha5;
    // Each destructive run begins from a known image, so a dropped rewrite
    // cannot accidentally match the same pattern left by an earlier run.
    integer reset_byte;
    always @(negedge reset_n)
        for(reset_byte=0;reset_byte<2097152;reset_byte=reset_byte+1)memory[reset_byte]=8'ha5;
    always @(posedge clk)begin
        if(!reset_n)begin
            tick<=0;writing<=0;reading<=0;dropped<=0;wi<=0;ri<=0;wn<=0;rn<=0;
            wa<=0;ra<=0;wid<=0;rid<=0;stalled_aw<=0;stalled_ar<=0;earliest_reads<=0;
        end
        else begin
            tick<=tick+1;
            if(stalled_aw && (!axi_awvalid || {axi_awaddr,axi_awlen,axi_awuser_id}!==saved_aw))
                $fatal(1,"native AW changed while stalled");
            if(stalled_ar && (!axi_arvalid || {axi_araddr,axi_arlen,axi_aruser_id}!==saved_ar))
                $fatal(1,"native AR changed while stalled");
            stalled_aw<=axi_awvalid&&!axi_awready;saved_aw<={axi_awaddr,axi_awlen,axi_awuser_id};
            stalled_ar<=axi_arvalid&&!axi_arready;saved_ar<={axi_araddr,axi_arlen,axi_aruser_id};
            if(aw)begin
                if(axi_awaddr<28'h1cc0000 || ({1'b0,axi_awaddr}+(axi_awlen+1)*8)>29'h1d40000)$fatal(1,"native write outside allocation");
                writing<=1;wa<=axi_awaddr;wid<=axi_awuser_id;wn<=axi_awlen+1;wi<=0;
            end
            if((writing||aw)&&axi_wready)begin
                offset=(writing?wa:axi_awaddr)*4-32'h07300000;
                if(!(drop_write&&phase==8'h30&&!dropped))begin
                    for(j=0;j<32;j=j+1)
                        if(bad_mask || axi_wstrb[j])memory[offset+j]=axi_wdata[j*8+:8];
                end else dropped<=1;
                if(overrun_guard && phase==8'h30 && offset<=GUARD_OFFSET && offset+32>=GUARD_OFFSET)
                    memory[GUARD_OFFSET]=0;
                wa<=(writing?wa:axi_awaddr)+8;wi<=(writing?wi:0)+1;
                if(writing?wi==wn-1:axi_awlen==0)writing<=0;
            end
            if(ar)begin
                if(axi_araddr<28'h1cc0000 || ({1'b0,axi_araddr}+(axi_arlen+1)*8)>29'h1d40000)$fatal(1,"native read outside allocation");
                reading<=1;ra<=axi_araddr;rid<=axi_aruser_id;rn<=axi_arlen+1;ri<=0;
            end
            if((reading||ar)&&axi_rvalid)begin
                if(ar)earliest_reads<=earliest_reads+1;
                ra<=(reading?ra:axi_araddr)+8;ri<=(reading?ri:0)+1;
                if(reading?ri==rn-1:axi_arlen==0)reading<=0;
            end
        end
    end
endmodule
