`timescale 1ns/1ps
module tb_video_capture_engine;
    parameter integer TEST_WIDTH=13, TEST_HEIGHT=3;
    localparam integer STRIDE=((TEST_WIDTH*3+15)/16)*16;
    localparam integer PIXELS=TEST_WIDTH*TEST_HEIGHT;
    localparam integer TIMEOUT=60000+PIXELS*20;
    reg clk=0,pixel_clk=0,reset_n=0,init_done=0;
    reg stop_pixel_clock=0,mode_good=1,rx_ready=1;
    always #4 clk=~clk;
    initial begin #3;forever begin #12.5;if(!stop_pixel_clock)pixel_clk=~pixel_clk;end end
    reg pixel_valid=0,frame_start=0,frame_end=0,frame_good=1;
    reg [23:0] pixel_rgb=0;
    reg [10:0] pixel_x=0,pixel_y=0;
    wire arm_toggle,cancel,ingress_valid,ingress_ready,engine_ready,source_fault,overflow;
    wire [47:0] ingress_data;
    reg block_fifo=0;
    integer injection=0,eof_delay=0;
    wire [47:0] m_data=ingress_data ^
        ((injection==1 && ingress_data[47:46]==0 && captured_pixels==0)?48'h200000000000:48'd0) ^
        ((injection==2 && ingress_data[47:46]==0 && captured_pixels==0)?48'h800000000000:48'd0) ^
        ((injection==3 && ingress_data[47:46]==1)?48'd1:48'd0) ^
        ((injection==4 && ingress_data[47:46]==1)?48'h100000000000:48'd0) ^
        ((injection==5 && ingress_data[47:46]==0 && captured_pixels==0)?48'h000001000000:48'd0) ^
        ((injection==6 && ingress_data[47:46]==1)?48'h200000000000:48'd0) ^
        ((injection==7 && ingress_data[47:46]==1)?48'h0000xxxxxxxx:48'd0);
    wire suppress_eof=injection==8&&ingress_data[47:46]==1;
    wire m_valid=ingress_valid&&!block_fifo&&!suppress_eof;
    wire m_ready=engine_ready;
    assign ingress_ready=engine_ready&&!block_fifo&&!suppress_eof;
    video_capture_ingress #(.FRAME_WIDTH(TEST_WIDTH),.FRAME_HEIGHT(TEST_HEIGHT),
        .FIFO_ADDR_WIDTH(TEST_WIDTH>=128?11:4)) ingress(
        .pixel_clk(pixel_clk),.pixel_reset_n(reset_n),.core_clk(clk),.core_reset_n(reset_n),
        .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .frame_start(frame_start),.frame_end(frame_end),.frame_good(frame_good),
        .mode_good(mode_good),.rx_ready(rx_ready),.arm_toggle(arm_toggle),.cancel(cancel),
        .m_valid(ingress_valid),.m_data(ingress_data),.m_ready(ingress_ready),
        .source_fault(source_fault),.overflow(overflow));
    wire busy,done,error;
    wire [7:0] phase,error_code;
    wire [31:0] captured_pixels,checked_bytes,source_crc,ddr_crc,frame_tag,fifo_peak;
    wire [27:0] axi_awaddr,axi_araddr;
    wire [255:0] axi_wdata,axi_rdata;
    wire [31:0] axi_wstrb;
    wire [3:0] axi_awlen,axi_awuser_id,axi_arlen,axi_aruser_id,axi_wusero_id,axi_rid;
    wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_awready,axi_wready,axi_wusero_last;
    wire axi_arvalid,axi_arready,axi_rlast,axi_rvalid;
    video_capture_engine #(.FRAME_WIDTH(TEST_WIDTH),.FRAME_HEIGHT(TEST_HEIGHT),
        .TIMEOUT_CYCLES(TIMEOUT)) dut(.m_ready(engine_ready),.*);
    reg corrupt_reader=0,hold_aw=0,hold_reader=0,bad_native_id=0;
    reg slow_verify=0,bad_reader_id=0,bad_reader_last=0;
    capture_engine_native_model #(.WIDTH(TEST_WIDTH),.HEIGHT(TEST_HEIGHT)) memory_model(.*);
    reg saw_dma=0,saw_eof=0,eof_before_dma=0,dma_before_eof=0;
    integer tests=0,arm_edges=0;
    reg previous_arm=0;
    always @(posedge clk)begin
        if(!reset_n)begin
            arm_edges<=0;previous_arm<=0;saw_dma<=0;saw_eof<=0;
            eof_before_dma<=0;dma_before_eof<=0;
        end
        else begin
            if(dut.dma_result_valid)begin
                saw_dma<=1;
                if(!saw_eof)dma_before_eof<=1;
            end
            if(m_valid&&m_ready&&m_data[47:46]==1)begin
                saw_eof<=1;
                if(!saw_dma)eof_before_dma<=1;
            end
            if(axi_arvalid&&axi_aruser_id==6&&(!dut.dma_retired||!dut.eof_seen||dut.dma_busy))
                $fatal(1,"independent read issued before full DMA retirement and EOF");
            if(arm_toggle!=previous_arm)arm_edges<=arm_edges+1;
            previous_arm<=arm_toggle;
            if(arm_edges>1)$fatal(1,"engine armed twice");
            if(done&&error)$fatal(1,"done and error asserted together");
            if(axi_awuser_ap||axi_aruser_ap)$fatal(1,"AP must be zero");
        end
    end
    // Parameter rejection is itself observable before any descriptor/ARM or
    // native transaction, including the allocation overflow at legal maxima.
    genvar invalid_case;
    generate for(invalid_case=0;invalid_case<5;invalid_case=invalid_case+1)begin : invalid_geometry
        localparam integer W=invalid_case==0?0:invalid_case==1?2049:invalid_case==4?2048:13;
        localparam integer H=invalid_case==2?0:invalid_case==3?2049:invalid_case==4?2048:3;
        wire bad_error,awvalid,arvalid,arm;
        wire [7:0] code;
        integer online_cycles=0;
        video_capture_engine #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(100)) rejected(
            .clk(clk),.reset_n(reset_n),.init_done(init_done),.m_valid(1'b0),.m_data(48'd0),
            .source_fault(1'b0),.overflow(1'b0),.arm_toggle(arm),.error(bad_error),.error_code(code),
            .axi_awvalid(awvalid),.axi_arvalid(arvalid),.axi_awready(1'b1),.axi_wready(1'b1),
            .axi_wusero_id(4'd0),.axi_wusero_last(1'b0),.axi_arready(1'b1),
            .axi_rdata(256'd0),.axi_rid(4'd0),.axi_rlast(1'b0),.axi_rvalid(1'b0));
        always @(posedge clk)begin
            if(!reset_n)online_cycles<=0;
            else if(init_done)begin
                online_cycles<=online_cycles+1;
                if(arm||awvalid||arvalid)$fatal(1,"invalid geometry generated traffic case=%0d",invalid_case);
                if(online_cycles>=2&&(!bad_error||code!=8'h08))$fatal(1,"invalid geometry not rejected case=%0d",invalid_case);
            end
        end
    end endgenerate
    // A source never waits for FIFO READY. The explicit horizontal blank is
    // 256 pixel clocks, so finite FIFO tests have realistic source duty.
    task automatic send_frame;
        integer x,y,k;
        begin : source_run
            wait(arm_toggle||!reset_n);
            if(!reset_n)disable source_run;
            repeat(8)@(negedge pixel_clk);
            for(y=0;y<TEST_HEIGHT;y=y+1)begin
                for(x=0;x<TEST_WIDTH;x=x+1)begin
                    if(!reset_n)disable source_run;
                    pixel_valid=1;pixel_x=x;pixel_y=y;
                    pixel_rgb={8'((x%256)^8'h93),8'((y%256)^8'h65),8'((x+y+183)%256)};
                    frame_start=x==0&&y==0;
                    frame_end=x==TEST_WIDTH-1&&y==TEST_HEIGHT-1&&eof_delay==0;
                    @(negedge pixel_clk);
                end
                pixel_valid=0;frame_start=0;frame_end=0;
                for(k=0;k<256;k=k+1)begin
                    if(!reset_n)disable source_run;
                    @(negedge pixel_clk);
                end
            end
            if(eof_delay!=0)begin
                for(k=0;k<eof_delay;k=k+1)begin
                    if(!reset_n)disable source_run;
                    @(negedge pixel_clk);
                end
                frame_end=1;@(negedge pixel_clk);frame_end=0;
            end
        end
    endtask
    initial forever begin
        wait(reset_n);send_frame();wait(!reset_n);
    end
    // Independent CRC oracle uses the normal (MSB-first) polynomial, input
    // reflection and output reflection, rather than the DUT's recurrence.
    function automatic [31:0] oracle_crc;
        integer x,y,c,b,k;
        reg [31:0] crc,result;
        reg [7:0] value;
        begin
            crc=32'hffffffff;
            for(y=0;y<TEST_HEIGHT;y=y+1)for(x=0;x<TEST_WIDTH;x=x+1)for(c=0;c<3;c=c+1)begin
                case(c)
                    0:value=(x%256)^8'h93;
                    1:value=(y%256)^8'h65;
                    2:value=(x+y+183)%256;
                endcase
                for(b=0;b<8;b=b+1)begin
                    if(crc[31]^value[b])crc=(crc<<1)^32'h04c11db7;
                    else crc=crc<<1;
                end
            end
            for(k=0;k<32;k=k+1)result[k]=~crc[31-k];
            oracle_crc=result;
        end
    endfunction
    reg [31:0] expected_crc;
    task automatic restart;
        begin
            @(negedge clk);reset_n=0;init_done=0;stop_pixel_clock=0;
            block_fifo=0;injection=0;eof_delay=0;mode_good=1;rx_ready=1;
            corrupt_reader=0;hold_aw=0;hold_reader=0;bad_native_id=0;
            slow_verify=0;bad_reader_id=0;bad_reader_last=0;
            pixel_valid=0;frame_start=0;frame_end=0;
            repeat(15)@(negedge clk);
            if(done||error||captured_pixels!=0||checked_bytes!=0)$fatal(1,"reset retained result");
            reset_n=1;repeat(8)@(negedge clk);
            if(axi_awvalid||axi_arvalid||arm_toggle)$fatal(1,"command or ARM before init");
            init_done=1;
        end
    endtask
    task automatic await_result(input bit pass);
        integer n;
        reg [7:0] code;
        begin
            n=0;
            while((pass?(!done&&!error):!error)&&n<TIMEOUT+1000)begin @(negedge clk);n=n+1;end
            if(n==TIMEOUT+1000)$fatal(1,"no bounded result phase=%h",phase);
            if(pass)begin
                if(!done||error||phase!=8'ha5||error_code!=0||captured_pixels!=PIXELS||
                    checked_bytes!=PIXELS*3||source_crc!==expected_crc||ddr_crc!==expected_crc||frame_tag!=1)
                    $fatal(1,"normal capture failed test=%0d phase=%h code=%h pixels=%0d bytes=%0d src=%h ddr=%h expected=%h",tests,phase,error_code,captured_pixels,checked_bytes,source_crc,ddr_crc,expected_crc);
                memory_model.check_image();
            end else begin
                if(!error||done||error_code==0||!cancel)$fatal(1,"fault not reported test=%0d",tests);
                code=error_code;repeat(30)@(negedge clk);
                if(!error||done||error_code!==code)$fatal(1,"fault was not sticky");
            end
            tests=tests+1;
        end
    endtask
    integer test_i;
    initial begin
        expected_crc=oracle_crc();
        if($test$plusargs("unknown_crc_only"))begin
            restart();injection=7;await_result(0);
            $display("VIDEO_CAPTURE_ENGINE_UNKNOWN_CRC_PASS");$finish;
        end
        if($test$plusargs("unknown_dma_only"))begin
            restart();wait(dut.dma_result_valid);force dut.dma_tag=32'bx;await_result(0);
            release dut.dma_tag;
            $display("VIDEO_CAPTURE_ENGINE_UNKNOWN_DMA_PASS");$finish;
        end
        restart();await_result(1);
        if(!eof_before_dma)$fatal(1,"missing EOF before DMA result coverage");
        if(!$test$plusargs("normal_only"))begin
            // Historical result survives unselected later source loss, but DDR
            // health loss must invalidate a previously successful capture.
            mode_good=0;repeat(20)@(negedge clk);
            if(!done||error)$fatal(1,"future HDMI loss changed historical result");
            init_done=0;await_result(0);
            restart();corrupt_reader=1;await_result(0);
            if(error_code!=8'h0b||checked_bytes!=PIXELS*3)$fatal(1,"independent CRC path not exercised");
            restart();slow_verify=1;await_result(1);
            if(!eof_before_dma)$fatal(1,"slow write verification did not retain early EOF");
            restart();eof_delay=2000;await_result(1);
            if(!dma_before_eof)$fatal(1,"missing DMA result before EOF coverage");
            for(test_i=1;test_i<=8;test_i=test_i+1)begin
                restart();injection=test_i;await_result(0);
            end
            restart();wait(captured_pixels>0);mode_good=0;await_result(0);
            restart();block_fifo=1;await_result(0);
            if(!overflow)$fatal(1,"physical source overflow was not reached");
            restart();wait(arm_toggle);stop_pixel_clock=1;await_result(0);
            if(error_code!=8'h07)$fatal(1,"source clock stop needs task timeout");
            restart();bad_native_id=1;await_result(0);
            restart();bad_reader_id=1;await_result(0);
            restart();bad_reader_last=1;await_result(0);
            restart();hold_aw=1;wait(axi_awvalid);stop_pixel_clock=1;await_result(0);
            if(!axi_awvalid||error_code!=8'h07)$fatal(1,"permanent native stall must preserve command and report timeout");
            hold_aw=0;repeat(200)@(negedge clk);
            if(axi_awvalid||memory_model.writing)$fatal(1,"timed-out AW/W did not drain after native resumed");
            restart();hold_aw=1;wait(axi_awvalid);init_done=0;await_result(0);
            hold_aw=0;repeat(200)@(negedge clk);
            if(axi_awvalid||memory_model.writing)$fatal(1,"faulted native AW/W did not drain");
            restart();hold_reader=1;wait(axi_arvalid&&axi_aruser_id==6);
            mode_good=0;force dut.source_fault=1'b1;await_result(0);
            hold_reader=0;repeat(1000)@(negedge clk);release dut.source_fault;
            if(axi_arvalid||memory_model.reading||dut.bridge_rvalid)$fatal(1,"faulted native AR/R did not drain");
            restart();wait(captured_pixels>0);restart();await_result(1);
            restart();wait(axi_arvalid&&axi_aruser_id==6);restart();await_result(1);
        end
        $display("VIDEO_CAPTURE_ENGINE_PASS width=%0d height=%0d tests=%0d pixels=%0d bytes=%0d crc=%h",TEST_WIDTH,TEST_HEIGHT,tests,captured_pixels,checked_bytes,ddr_crc);
        $finish;
    end
endmodule

// Byte memory is independent of DUT RGB/CRC/lane logic. Every enabled write
// is checked against an address-derived x/y/channel oracle, then stored. A5
// padding and both allocation red zones are checked after each normal run.
module capture_engine_native_model #(parameter integer WIDTH=13,HEIGHT=3)(
    input wire clk,reset_n,
    input wire corrupt_reader,hold_aw,hold_reader,bad_native_id,
    input wire slow_verify,bad_reader_id,bad_reader_last,
    input wire [27:0] axi_awaddr,axi_araddr,
    input wire [3:0] axi_awlen,axi_awuser_id,axi_arlen,axi_aruser_id,
    input wire axi_awvalid,axi_arvalid,
    output wire axi_awready,axi_arready,axi_wready,axi_rvalid,
    input wire [255:0] axi_wdata,input wire [31:0] axi_wstrb,
    output wire [255:0] axi_rdata,
    output wire [3:0] axi_wusero_id,axi_rid,
    output wire axi_wusero_last,axi_rlast
);
    localparam integer STRIDE=((WIDTH*3+15)/16)*16;
    reg [7:0] memory[0:2097215];
    integer tick=0,wi=0,ri=0,wn=0,rn=0,j,offset,byte_address,revision=0,verify_delay=0;
    reg writing=0,reading=0;
    reg [27:0] wa,ra;
    reg [3:0] wid,rid;
    reg stalled_aw=0,stalled_ar=0;
    reg [35:0] saved_aw,saved_ar;
    wire aw=axi_awvalid&&axi_awready,ar=axi_arvalid&&axi_arready;
    assign axi_awready=reset_n&&!writing&&!reading&&!hold_aw&&tick%5==1;
    assign axi_arready=reset_n&&!writing&&!reading&&!(hold_reader&&axi_aruser_id==6)&&
        !(slow_verify&&axi_aruser_id==3&&verify_delay<200)&&tick%7==2;
    assign axi_wready=reset_n&&(writing||aw)&&tick%4!=0;
    assign axi_rvalid=reset_n&&(reading||ar)&&(ar||tick%3!=0);
    assign axi_wusero_id=(writing?wid:axi_awuser_id)^(bad_native_id?4'd1:4'd0);
    assign axi_rid=(reading?rid:axi_aruser_id)^((bad_reader_id&&(reading?rid:axi_aruser_id)==6)?4'd1:4'd0);
    assign axi_wusero_last=writing?wi==wn-1:axi_awlen==0;
    assign axi_rlast=(reading?ri==rn-1:axi_arlen==0)^((bad_reader_last&&(reading?rid:axi_aruser_id)==6)?1'b1:1'b0);
    function automatic [255:0] fetch(input [27:0] address,input integer rev);
        integer k,base;
        begin
            base=address*4-32'h07300000+32;fetch=0;
            if(base>=32&&base+31<2097184)
                for(k=0;k<32;k=k+1)fetch[k*8+:8]=memory[base+k];
        end
    endfunction
    assign axi_rdata=(reading||ar)?(fetch(reading?ra:axi_araddr,revision)^
        ((corrupt_reader&&(reading?rid:axi_aruser_id)==6)?256'd1:256'd0)):256'd0;
    function automatic [7:0] expected_byte(input integer relative_address);
        integer y,x,c;
        begin
            y=relative_address/STRIDE;x=(relative_address%STRIDE)/3;c=(relative_address%STRIDE)%3;
            if(relative_address<0||y>=HEIGHT||relative_address%STRIDE>=WIDTH*3)expected_byte=8'ha5;
            else case(c)
                0:expected_byte=(x%256)^8'h93;
                1:expected_byte=(y%256)^8'h65;
                2:expected_byte=(x+y+183)%256;
            endcase
        end
    endfunction
    task automatic check_image;
        integer a;
        begin
            for(a=0;a<2097216;a=a+1)
                if(memory[a]!==expected_byte(a-32))$fatal(1,"independent memory byte=%0d actual=%h expected=%h",a-32,memory[a],expected_byte(a-32));
        end
    endtask
    initial for(j=0;j<2097216;j=j+1)memory[j]=8'ha5;
    integer reset_byte;
    always @(negedge reset_n)
        for(reset_byte=0;reset_byte<2097216;reset_byte=reset_byte+1)memory[reset_byte]=8'ha5;
    always @(posedge clk)begin
        if(!reset_n)begin
            tick<=0;writing<=0;reading<=0;wi<=0;ri<=0;wn<=0;rn<=0;
            wa<=0;ra<=0;wid<=0;rid<=0;stalled_aw<=0;stalled_ar<=0;revision<=0;verify_delay<=0;
        end else begin
            tick<=tick+1;
            if(slow_verify&&axi_arvalid&&axi_aruser_id==3&&verify_delay<200)verify_delay<=verify_delay+1;
            if(stalled_aw&&(!axi_awvalid||{axi_awaddr,axi_awlen,axi_awuser_id}!==saved_aw))$fatal(1,"native AW changed while stalled");
            if(stalled_ar&&(!axi_arvalid||{axi_araddr,axi_arlen,axi_aruser_id}!==saved_ar))$fatal(1,"native AR changed while stalled");
            stalled_aw<=axi_awvalid&&!axi_awready;saved_aw<={axi_awaddr,axi_awlen,axi_awuser_id};
            stalled_ar<=axi_arvalid&&!axi_arready;saved_ar<={axi_araddr,axi_arlen,axi_aruser_id};
            if(aw)begin
                if(axi_awaddr<28'h1cc0000||({1'b0,axi_awaddr}+(axi_awlen+1)*8)>29'h1d40000)$fatal(1,"native write outside allocation");
                writing<=1;wa<=axi_awaddr;wid<=axi_awuser_id;wn<=axi_awlen+1;wi<=0;
            end
            if((writing||aw)&&axi_wready)begin
                offset=(writing?wa:axi_awaddr)*4-32'h07300000;
                for(j=0;j<32;j=j+1)if(axi_wstrb[j])begin
                    byte_address=offset+j;
                    if(byte_address%STRIDE>=WIDTH*3||byte_address/STRIDE>=HEIGHT)$fatal(1,"enabled write into padding/redzone");
                    if(axi_wdata[j*8+:8]!==expected_byte(byte_address))$fatal(1,"write byte oracle address=%0d got=%h expected=%h",byte_address,axi_wdata[j*8+:8],expected_byte(byte_address));
                    memory[byte_address+32]=axi_wdata[j*8+:8];
                end
                revision<=revision+1;
                wa<=(writing?wa:axi_awaddr)+8;wi<=(writing?wi:0)+1;
                if(writing?wi==wn-1:axi_awlen==0)writing<=0;
            end
            if(ar)begin
                if(axi_araddr<28'h1cc0000||({1'b0,axi_araddr}+(axi_arlen+1)*8)>29'h1d40000)$fatal(1,"native read outside allocation");
                reading<=1;ra<=axi_araddr;rid<=axi_aruser_id;rn<=axi_arlen+1;ri<=0;
            end
            if((reading||ar)&&axi_rvalid)begin
                ra<=(reading?ra:axi_araddr)+8;ri<=(reading?ri:0)+1;
                if(reading?ri==rn-1:axi_arlen==0)reading<=0;
            end
        end
    end
endmodule
