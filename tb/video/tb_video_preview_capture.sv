`timescale 1ns/1ps
`default_nettype none
module tb_video_preview_capture;
    parameter integer TEST_WIDTH=26,TEST_HEIGHT=6;
    localparam integer PIXELS=TEST_WIDTH*TEST_HEIGHT,PREVIEW_PIXELS=PIXELS/4;
    localparam integer TIMEOUT=2000+PIXELS*30;
    reg clk=0,reset_n=0,init_done=0,source_fault=0,overflow=0;
    always #4 clk=~clk;
    wire busy,done,error,m_ready,arm_toggle,cancel;
    wire [7:0] error_code;
    wire [31:0] captured_pixels,preview_pixels,source_crc,preview_crc,fifo_peak;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid,awready,wlast,wvalid,wready,bvalid,bready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    wire [3:0] bid;
    wire [1:0] bresp;
    reg m_valid=0;
    reg [47:0] m_data=0;
    integer injection=0,sent=0,tests=0;
    reg pause_source=0,pause_eof=0,hold_aw=0,hold_w=0,hold_b=0,bad_bid=0,bad_resp=0;
    reg [31:0] raw_expected_crc,preview_expected_crc;
    video_preview_capture #(.FRAME_WIDTH(TEST_WIDTH),.FRAME_HEIGHT(TEST_HEIGHT),
        .TIMEOUT_CYCLES(TIMEOUT)) dut(.*);
    preview_capture_axi_memory #(.WIDTH(TEST_WIDTH),.HEIGHT(TEST_HEIGHT)) memory_model(.*);

    function automatic [7:0] source_byte(input integer x,y,c);
        begin
            case(c)
                0:source_byte=8'((37*x+19*y+147)%256);
                1:source_byte=8'((11*x+53*y+101)%256);
                default:source_byte=8'((71*x+7*y+183)%256);
            endcase
        end
    endfunction
    function automatic [7:0] preview_byte(input integer x,y,c);
        integer total;
        begin
            total=int'(source_byte(x*2,y*2,c))+int'(source_byte(x*2+1,y*2,c))+
                int'(source_byte(x*2,y*2+1,c))+int'(source_byte(x*2+1,y*2+1,c));
            preview_byte=8'((total+2)/4);
        end
    endfunction
    // Deliberately use the normal MSB-first polynomial and reflected input,
    // independently of the RTL's reflected polynomial recurrence.
    function automatic [31:0] oracle_crc(input integer scale);
        reg [31:0] crc,result;
        reg [7:0] value;
        integer x,y,c,b,k;
        begin
            crc=32'hffffffff;
            for(y=0;y<TEST_HEIGHT/scale;y=y+1)
                for(x=0;x<TEST_WIDTH/scale;x=x+1)for(c=0;c<3;c=c+1)begin
                    value=scale==1?source_byte(x,y,c):preview_byte(x,y,c);
                    for(b=0;b<8;b=b+1)
                        if(crc[31]^value[b])crc=(crc<<1)^32'h04c11db7;
                        else crc=crc<<1;
                end
            for(k=0;k<32;k=k+1)result[k]=~crc[31-k];
            oracle_crc=result;
        end
    endfunction
    integer sx,sy;
    always @* begin
        sx=sent%TEST_WIDTH;sy=sent/TEST_WIDTH;
        m_valid=reset_n&&arm_toggle&&!error&&!pause_source&&sent<=PIXELS&&
            !((injection==10||pause_eof)&&sent==PIXELS);
        m_data=sent<PIXELS?{2'b00,(sx==TEST_WIDTH-1),21'd0,
            source_byte(sx,sy,0),source_byte(sx,sy,1),source_byte(sx,sy,2)}:
            {2'b01,1'b0,1'b1,12'd123,raw_expected_crc};
        if(sent==0)case(injection)
            1:m_data[45]=~m_data[45];
            2:m_data[24]=1;
            3:m_data[47:46]=2'bx0;
            4:m_data[7:0]=8'bx;
            default:begin end
        endcase
        if(sent==PIXELS)case(injection)
            5:m_data[44]=0;
            6:m_data[45]=1;
            7:m_data[0]=1'bx;
            8:m_data[32]=1'bx;
            default:begin end
        endcase
        if(injection==9&&sent==PIXELS-1)m_data={2'b01,1'b0,1'b1,12'd123,raw_expected_crc};
    end
    genvar invalid_case;
    generate for(invalid_case=0;invalid_case<8;invalid_case=invalid_case+1)begin : invalid_geometry
        localparam integer W=invalid_case==0?0:invalid_case==1?1:invalid_case==2?3:
            invalid_case==3?2050:invalid_case==7?2048:2;
        localparam integer H=invalid_case==4?0:invalid_case==5?3:invalid_case==6?2050:
            invalid_case==7?2048:2;
        wire rejected_error,rejected_arm,rejected_aw;
        wire [7:0] rejected_code;
        integer online_cycles=0;
        video_preview_capture #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(100)) rejected(
            .clk(clk),.reset_n(reset_n),.init_done(init_done),.m_valid(1'b0),.m_data(48'd0),
            .source_fault(1'b0),.overflow(1'b0),.arm_toggle(rejected_arm),.error(rejected_error),
            .error_code(rejected_code),.awvalid(rejected_aw),.awready(1'b1),.wready(1'b1),
            .bid(4'd0),.bresp(2'd0),.bvalid(1'b0));
        always @(posedge clk)begin
            if(!reset_n)online_cycles<=0;
            else if(init_done)begin
                online_cycles<=online_cycles+1;
                if(rejected_arm||rejected_aw)$fatal(1,"invalid geometry generated traffic case=%0d",invalid_case);
                if(online_cycles>=2&&(!rejected_error||rejected_code!==8'h08))
                    $fatal(1,"geometry not rejected case=%0d code=%h",invalid_case,rejected_code);
            end
        end
    end endgenerate
    reg old_arm=0;
    integer arm_count=0;
    always @(posedge clk)begin
        if(!reset_n)begin sent<=0;old_arm<=0;arm_count<=0;end
        else begin
            if(m_valid&&m_ready)sent<=sent+1;
            if(arm_toggle!=old_arm)arm_count<=arm_count+1;
            old_arm<=arm_toggle;
            if(arm_count>1)$fatal(1,"capture armed twice");
            if(done&&error)$fatal(1,"done and error simultaneously");
            if(done&&(memory_model.active||memory_model.pending_b||bvalid))
                $fatal(1,"done before last B retirement");
            if(done&&(captured_pixels!==PIXELS||preview_pixels!==PREVIEW_PIXELS))
                $fatal(1,"done with incomplete counts");
        end
    end
    task automatic restart;
        begin
            @(negedge clk);reset_n=0;init_done=0;source_fault=0;overflow=0;
            pause_source=0;pause_eof=0;hold_aw=0;hold_w=0;hold_b=0;bad_bid=0;bad_resp=0;injection=0;
            repeat(5)@(negedge clk);
            if(done||error||arm_toggle||captured_pixels!=0||preview_pixels!=0)
                $fatal(1,"coordinated reset retained capture state");
            reset_n=1;repeat(5)@(negedge clk);
            if(awvalid||wvalid||arm_toggle)$fatal(1,"traffic before init_done");
            init_done=1;
        end
    endtask
    task automatic await_result(input bit success);
        integer n;
        reg [7:0] saved_code;
        begin
            n=0;
            while((success?(!done&&!error):!error)&&n<TIMEOUT+100)begin @(negedge clk);n=n+1;end
            if(n==TIMEOUT+100)$fatal(1,"no bounded result");
            if(success)begin
                if(!done||error||error_code!==0||source_crc!==raw_expected_crc||
                    preview_crc!==preview_expected_crc||fifo_peak!==123||busy||cancel)
                    $fatal(1,"success mismatch test=%0d code=%h raw=%h/%h preview=%h/%h counts=%0d/%0d",tests,error_code,
                        source_crc,raw_expected_crc,preview_crc,preview_expected_crc,captured_pixels,preview_pixels);
                memory_model.check_image();
                repeat(20)@(negedge clk);
                if(!done||error)$fatal(1,"completion not held");
            end else begin
                if(!error||done||error_code===0||!cancel)$fatal(1,"missing sticky fault test=%0d",tests);
                saved_code=error_code;repeat(25)@(negedge clk);
                if(!error||done||error_code!==saved_code)$fatal(1,"fault result changed");
            end
            tests=tests+1;
        end
    endtask
    task automatic await_drain;
        integer n;
        begin
            hold_aw=0;hold_w=0;hold_b=0;n=0;
            while((awvalid||wvalid||memory_model.active||memory_model.pending_b||bvalid)&&n<2000)begin
                @(negedge clk);n=n+1;
            end
            if(n==2000)$fatal(1,"failed capture did not drain advertised write");
        end
    endtask
    integer i;
    initial begin
        raw_expected_crc=oracle_crc(1);preview_expected_crc=oracle_crc(2);
        restart();await_result(1);
        if(!$test$plusargs("normal_only"))begin
            // Sources after the completed historical frame do not replace it.
            source_fault=1;overflow=1;repeat(10)@(negedge clk);
            if(!done||error)$fatal(1,"later source state changed historical frame");
            init_done=0;await_result(0);
            restart();hold_b=1;wait(memory_model.pending_b);
            repeat(50)@(negedge clk);
            if(done)$fatal(1,"done while first B withheld");
            hold_b=0;await_result(1);
            restart();pause_eof=1;wait(dut.raw_retired&&dut.preview_retired);
            repeat(20)@(negedge clk);
            if(done)$fatal(1,"DMA success completed without EOF");
            pause_eof=0;await_result(1);
            restart();wait(preview_pixels==PREVIEW_PIXELS);hold_b=1;
            wait(memory_model.pending_b||bvalid);repeat(60)@(negedge clk);
            if(done)$fatal(1,"done while final write response withheld");
            hold_b=0;await_result(1);
            for(i=1;i<=10;i=i+1)begin restart();injection=i;await_result(0);await_drain();end
            restart();bad_bid=1;await_result(0);await_drain();
            restart();bad_resp=1;await_result(0);await_drain();
            restart();wait(captured_pixels>0);overflow=1;await_result(0);await_drain();
            restart();wait(captured_pixels>0);source_fault=1;await_result(0);await_drain();
            restart();pause_source=1;await_result(0);
            if(error_code!==8'h07)$fatal(1,"source clock stop must timeout");
            restart();hold_aw=1;wait(awvalid);source_fault=1;await_result(0);
            if(!awvalid)$fatal(1,"fault withdrew stalled AW");await_drain();
            restart();hold_aw=1;wait(awvalid);init_done=0;await_result(0);
            if(!awvalid)$fatal(1,"offline withdrew stalled AW");await_drain();
            restart();hold_w=1;wait(wvalid);overflow=1;await_result(0);
            if(!wvalid)$fatal(1,"fault withdrew stalled W");await_drain();
            restart();hold_w=1;wait(wvalid);init_done=0;await_result(0);
            if(!wvalid)$fatal(1,"offline withdrew stalled W");await_drain();
            restart();hold_b=1;wait(memory_model.pending_b);init_done=0;await_result(0);await_drain();
            restart();hold_aw=1;wait(awvalid);await_result(0);
            if(!awvalid||error_code!==8'h07)$fatal(1,"AW timeout ownership lost");await_drain();
            restart();wait(dut.raw_result_valid);force dut.raw_tag=32'bx;await_result(0);release dut.raw_tag;
            restart();wait(dut.preview_result_valid);force dut.preview_tag=32'bx;await_result(0);release dut.preview_tag;
            restart();wait(dut.raw_result_valid);force dut.raw_bytes=32'bx;await_result(0);release dut.raw_bytes;
            restart();wait(dut.preview_result_valid);force dut.preview_success=1'bx;await_result(0);release dut.preview_success;
            restart();wait(wvalid);restart();await_result(1);
        end
        $display("VIDEO_PREVIEW_CAPTURE_PASS width=%0d height=%0d tests=%0d raw=%0d preview=%0d crc=%h/%h",
            TEST_WIDTH,TEST_HEIGHT,tests,captured_pixels,preview_pixels,source_crc,preview_crc);
        $finish;
    end
    initial begin
        repeat(TIMEOUT*40)@(posedge clk);
        $fatal(1,"testbench watchdog");
    end
endmodule

// Byte-addressed memory with an independent address/four-pixel oracle.
// Padding and 32-byte guards around both planes begin as A5 and stay A5.
module preview_capture_axi_memory #(parameter integer WIDTH=26,HEIGHT=6)(
    input wire clk,reset_n,hold_aw,hold_w,hold_b,bad_bid,bad_resp,
    input wire [3:0] awid,input wire [31:0] awaddr,input wire [7:0] awlen,
    input wire [2:0] awsize,input wire [1:0] awburst,input wire awvalid,
    output wire awready,input wire [127:0] wdata,input wire [15:0] wstrb,
    input wire wlast,wvalid,output wire wready,
    output reg [3:0] bid=0,output reg [1:0] bresp=0,
    output reg bvalid=0,input wire bready
);
    localparam integer RAW_STRIDE=((WIDTH*3+15)/16)*16;
    localparam integer PREVIEW_STRIDE=((WIDTH/2*3+15)/16)*16;
    localparam integer RAW_SIZE=RAW_STRIDE*HEIGHT,PREVIEW_SIZE=PREVIEW_STRIDE*(HEIGHT/2);
    reg [7:0] raw_memory[0:RAW_SIZE+63],preview_memory[0:PREVIEW_SIZE+63];
    reg raw_written[0:RAW_SIZE-1],preview_written[0:PREVIEW_SIZE-1];
    reg active=0,pending_b=0;
    reg [31:0] address=0;
    reg [3:0] owner_id=0;
    integer tick=0,beats=0,index=0,delay_b=0,j,relative,a,x,y,c,total;
    integer raw_bursts=0,preview_bursts=0,tail_beats=0,page_splits=0;
    reg stalled_aw=0,stalled_w=0;
    reg [31:0] random_state=32'h1badf00d;
    reg [48:0] saved_aw;
    reg [144:0] saved_w;
    reg [15:0] expected_strobe;
    integer row_left;
    assign awready=reset_n&&!active&&!pending_b&&!bvalid&&!hold_aw&&random_state[0];
    assign wready=reset_n&&active&&!hold_w&&(random_state[4:3]!=0);
    function automatic [7:0] oracle_raw(input integer xx,yy,cc);
        begin
            case(cc)
                0:oracle_raw=8'((xx*37+yy*19+147)&255);
                1:oracle_raw=8'((xx*11+yy*53+101)&255);
                default:oracle_raw=8'((xx*71+yy*7+183)&255);
            endcase
        end
    endfunction
    function automatic [7:0] oracle_plane(input integer plane,offset);
        integer xx,yy,cc,sum,stride,width,height;
        begin
            stride=plane==0?RAW_STRIDE:PREVIEW_STRIDE;
            width=plane==0?WIDTH:WIDTH/2;height=plane==0?HEIGHT:HEIGHT/2;
            yy=offset/stride;xx=(offset%stride)/3;cc=(offset%stride)%3;
            if(offset<0||yy>=height||offset%stride>=width*3)oracle_plane=8'ha5;
            else if(plane==0)oracle_plane=oracle_raw(xx,yy,cc);
            else begin
                sum=int'(oracle_raw(2*xx,2*yy,cc))+int'(oracle_raw(2*xx+1,2*yy,cc))+
                    int'(oracle_raw(2*xx,2*yy+1,cc))+int'(oracle_raw(2*xx+1,2*yy+1,cc));
                oracle_plane=8'((sum+2)/4);
            end
        end
    endfunction
    task automatic initialize_memory;
        integer k;
        begin
            for(k=0;k<RAW_SIZE+64;k=k+1)raw_memory[k]=8'ha5;
            for(k=0;k<PREVIEW_SIZE+64;k=k+1)preview_memory[k]=8'ha5;
            for(k=0;k<RAW_SIZE;k=k+1)raw_written[k]=0;
            for(k=0;k<PREVIEW_SIZE;k=k+1)preview_written[k]=0;
        end
    endtask
    initial initialize_memory();
    always @(negedge reset_n)initialize_memory();
    task automatic check_image;
        integer k;
        begin
            for(k=0;k<RAW_SIZE+64;k=k+1)if(raw_memory[k]!==oracle_plane(0,k-32))
                $fatal(1,"RAW memory byte %0d got=%h expected=%h",k-32,raw_memory[k],oracle_plane(0,k-32));
            for(k=0;k<PREVIEW_SIZE+64;k=k+1)if(preview_memory[k]!==oracle_plane(1,k-32))
                $fatal(1,"preview memory byte %0d got=%h expected=%h",k-32,preview_memory[k],oracle_plane(1,k-32));
            for(k=0;k<RAW_SIZE;k=k+1)if(k%RAW_STRIDE<WIDTH*3&&!raw_written[k])
                $fatal(1,"raw active byte never written %0d",k);
            for(k=0;k<PREVIEW_SIZE;k=k+1)if(k%PREVIEW_STRIDE<(WIDTH/2)*3&&!preview_written[k])
                $fatal(1,"preview active byte never written %0d",k);
            if(raw_bursts==0||preview_bursts==0)$fatal(1,"both AXI owners not observed");
            if((WIDTH*3)%16!=0&&tail_beats==0)$fatal(1,"missing partial WSTRB coverage");
            if(WIDTH==800&&page_splits==0)$fatal(1,"missing 4KiB split coverage");
        end
    endtask
    always @(posedge clk)begin
        if(!reset_n)begin
            active<=0;pending_b<=0;bvalid<=0;tick<=0;beats<=0;index<=0;delay_b<=0;
            address<=0;owner_id<=0;bid<=0;bresp<=0;stalled_aw<=0;stalled_w<=0;
            raw_bursts<=0;preview_bursts<=0;tail_beats<=0;page_splits<=0;
            random_state<=32'h1badf00d;
        end else begin
            tick<=tick+1;
            random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            if(stalled_aw&&(!awvalid||{awid,awaddr,awlen,awsize,awburst}!==saved_aw))
                $fatal(1,"AW changed or VALID withdrawn under stall");
            if(stalled_w&&(!wvalid||{wdata,wstrb,wlast}!==saved_w))
                $fatal(1,"W changed or VALID withdrawn under stall");
            stalled_aw<=awvalid&&!awready;saved_aw<={awid,awaddr,awlen,awsize,awburst};
            stalled_w<=wvalid&&!wready;saved_w<={wdata,wstrb,wlast};
            if(awvalid&&awready)begin
                if(awsize!==4||awburst!==1||awlen>15||awaddr[3:0]!==0||
                    ({1'b0,awaddr[11:0]}+(int'(awlen)+1)*16)>4096)
                    $fatal(1,"illegal AXI burst addr=%h len=%0d",awaddr,awlen);
                if((awid!==1&&awid!==2)||active||pending_b||bvalid)$fatal(1,"invalid/interleaved owner");
                if(awid==1)raw_bursts<=raw_bursts+1;else preview_bursts<=preview_bursts+1;
                if(({1'b0,awaddr[11:0]}+(int'(awlen)+1)*16)==4096)page_splits<=page_splits+1;
                active<=1;address<=awaddr;owner_id<=awid;beats<=int'(awlen)+1;index<=0;
            end
            if(wvalid&&wready)begin
                if(!active||wlast!==(index==beats-1))$fatal(1,"unexpected W/LAST");
                relative=int'(address-(owner_id==1?32'h87300000:32'h87460000));
                row_left=owner_id==1?WIDTH*3-relative%RAW_STRIDE:(WIDTH/2)*3-relative%PREVIEW_STRIDE;
                expected_strobe=row_left>=16?16'hffff:16'hffff>>(16-row_left);
                if(wstrb!==expected_strobe)$fatal(1,"incorrect row-tail WSTRB %h expected %h",wstrb,expected_strobe);
                if(wstrb!=16'hffff)tail_beats<=tail_beats+1;
                for(j=0;j<16;j=j+1)if(wstrb[j])begin
                    relative=int'(address-(owner_id==1?32'h87300000:32'h87460000))+j;
                    if(owner_id==1)begin
                        if(relative<0||relative>=RAW_SIZE||relative%RAW_STRIDE>=WIDTH*3)
                            $fatal(1,"raw enabled padding/guard byte %0d",relative);
                        if(wdata[j*8+:8]!==oracle_plane(0,relative))
                            $fatal(1,"raw write oracle addr=%h got=%h expected=%h",address+j,wdata[j*8+:8],oracle_plane(0,relative));
                        if(raw_written[relative])$fatal(1,"raw byte written twice %0d",relative);
                        raw_written[relative]=1;
                        raw_memory[relative+32]=wdata[j*8+:8];
                    end else begin
                        if(relative<0||relative>=PREVIEW_SIZE||relative%PREVIEW_STRIDE>=(WIDTH/2)*3)
                            $fatal(1,"preview enabled padding/guard byte %0d",relative);
                        if(wdata[j*8+:8]!==oracle_plane(1,relative))
                            $fatal(1,"preview write oracle addr=%h got=%h expected=%h",address+j,wdata[j*8+:8],oracle_plane(1,relative));
                        if(preview_written[relative])$fatal(1,"preview byte written twice %0d",relative);
                        preview_written[relative]=1;
                        preview_memory[relative+32]=wdata[j*8+:8];
                    end
                end
                address<=address+16;index<=index+1;
                if(wlast)begin active<=0;pending_b<=1;delay_b<=5+int'(random_state[3:0]);end
            end
            if(pending_b&&!hold_b)begin
                if(delay_b==0)begin
                    pending_b<=0;bvalid<=1;bid<=owner_id^(bad_bid?4'h8:4'h0);
                    bresp<=bad_resp?2'b10:2'b00;
                end else delay_b<=delay_b-1;
            end
            if(bvalid&&bready)bvalid<=0;
        end
    end
endmodule
`default_nettype wire
