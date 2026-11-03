`timescale 1ns/1ps
`default_nettype none
// Real two-clock ingress/FIFO + production three-branch pipeline. The byte
// oracle uses output coordinates, not the RTL's phase counters or arithmetic.
module tb_video_capture_rearm #(
    parameter integer W=30,H=20,PT=2,PB=1,JOBS=7,NEW_PARAMETERS=1,
    parameter integer PIXEL_GAP=5,FIFO_AW=5,
    parameter real PIXEL_HALF=12.5,CORE_HALF=4.0
);
    localparam integer N=W*H,PW=W/2,PH=H/2,IW=W*2/5,AH=H*2/5,IH=PT+AH+PB;
    localparam integer RS=(W*3+15)/16*16,PS=(PW*3+15)/16*16,IS=(IW+15)/16*16,IP=IS*IH;
    localparam integer LIMIT=N*50+3000,SPAN=3*IP+RS*H+PS*PH;
    reg clk=0,pixel_clk=0,pixel_run=1,reset_n=0,init_done=0,abort=0,req_valid=0;
    always #(CORE_HALF) clk=~clk;
    initial begin #1.3;forever #(PIXEL_HALF) if(pixel_run)pixel_clk=~pixel_clk;end
    reg [1:0] req_slot=0;
    reg [31:0] req_frame_id=1,req_preprocess_version=1;
    reg accepted_ready=0,completion_ready=0;
    wire req_ready,arm_toggle,cancel,busy,port_drained,accepted_valid,completion_valid,completion_success,error;
    wire [7:0] completion_code,error_code;
    wire [31:0] frame_id,preprocess_version,raw_base,preview_base,input_base;
    wire [1:0] slot;
    wire [31:0] captured_pixels,preview_pixels,input_pixels,source_crc,preview_crc,fifo_peak;
    wire [31:0] raw_written_bytes,preview_written_bytes,input_written_bytes;
    reg pixel_valid=0,frame_start=0,frame_end=0,frame_good=1,mode_good=1,rx_ready=1;
    reg [23:0] pixel_rgb=0;
    reg [10:0] pixel_x=0,pixel_y=0;
    wire fifo_valid,fifo_ready,m_valid,m_ready,source_fault,overflow;
    wire [47:0] fifo_data,m_data;
    video_capture_ingress #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.FIFO_ADDR_WIDTH(FIFO_AW),.ENABLE_REARM(NEW_PARAMETERS)) ingress(
        .pixel_clk(pixel_clk),.pixel_reset_n(reset_n),.core_clk(clk),.core_reset_n(reset_n),
        .pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .frame_start(frame_start),.frame_end(frame_end),.frame_good(frame_good),.mode_good(mode_good),
        .rx_ready(rx_ready),.arm_toggle(arm_toggle),.cancel(cancel),.m_valid(fifo_valid),
        .m_data(fifo_data),.m_ready(fifo_ready),.source_fault(source_fault),.overflow(overflow));
    video_stream_register #(.DATA_WIDTH(48)) stream_register(
        .clk(clk),.reset_n(reset_n),.s_valid(fifo_valid),.s_ready(fifo_ready),.s_data(fifo_data),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data));
    wire [3:0] awid;wire [31:0] awaddr;wire [7:0] awlen;wire [2:0] awsize;
    wire [1:0] awburst;wire awvalid,awready,wvalid,wready,wlast,bready;
    wire [127:0] wdata;wire [15:0] wstrb;
    reg [3:0] bid=0;reg [1:0] bresp=0;reg bvalid=0;
    video_three_branch_capture #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB),
        .TIMEOUT_CYCLES(LIMIT),.ENABLE_REARM(NEW_PARAMETERS)) dut(.*);

    integer job=0,case_id=0,tick=0,checks=0,arms=0,completed=0;
    integer count[1:3],acks[1:3];
    reg hit[0:SPAN-1];
    reg active=0,pending=0,final_held=0,hold_aw=0,hold_w=0,hold_b=0,bad_b=0;
    reg old_arm=0,source_done=1,allow_fault=0;
    integer owner=0,beats=0,beat=0,delay_b=0,burst_bytes=0,final_branch=0;
    reg [31:0] address=0,rng=32'h13bca951;
    reg held_aw=0,held_w=0,held_record=0;
    reg [48:0] saved_aw;
    reg [144:0] saved_w;
    reg [1023:0] saved_record;
    wire [1023:0] record={completion_success,completion_code,slot,frame_id,preprocess_version,
        raw_base,preview_base,input_base,captured_pixels,preview_pixels,input_pixels,source_crc,
        preview_crc,fifo_peak,raw_written_bytes,preview_written_bytes,input_written_bytes};
    function automatic [31:0] raw_address(input integer s);
        raw_address=32'h82000000+s*32'h200000;
    endfunction
    function automatic [31:0] input_address(input integer s);
        input_address=32'h82800000+s*32'h50000;
    endfunction
    function automatic [7:0] src(input integer x,y,c,tag);
        src=8'((37*x+19*y+83*c+((x*y)>>3)+tag*43+tag*x)%256);
    endfunction
    function automatic [7:0] expected(input integer branch,offset,tag);
        integer x,y,c,sx,sy,wx,wy,upper,lower,total;
        begin
            if(branch==1)expected=src((offset%RS)/3,offset/RS,(offset%RS)%3,tag);
            else if(branch==2)begin
                x=(offset%PS)/3;y=offset/PS;c=(offset%PS)%3;
                total=int'(src(2*x,2*y,c,tag))+int'(src(2*x+1,2*y,c,tag))+
                    int'(src(2*x,2*y+1,c,tag))+int'(src(2*x+1,2*y+1,c,tag));
                expected=8'((total+2)/4);
            end else begin
                c=2-offset/IP;y=(offset%IP)/IS;x=offset%IS;
                if(y<PT||y>=PT+AH)expected=0;
                else begin
                    y=y-PT;sx=(10*x+3)/4;sy=(10*y+3)/4;wx=x%2==0?3:1;wy=y%2==0?3:1;
                    upper=(4-wx)*int'(src(sx,sy,c,tag))+wx*int'(src(sx+1,sy,c,tag));
                    lower=(4-wx)*int'(src(sx,sy+1,c,tag))+wx*int'(src(sx+1,sy+1,c,tag));
                    expected=8'(((4-wy)*upper/4+wy*lower/4+2)/4);
                end
            end
        end
    endfunction
    function automatic [31:0] crc(input integer branch,tag);
        reg [31:0] c,r;reg [7:0] v;integer x,y,ch,b,k;
        begin
            c=32'hffffffff;
            for(y=0;y<(branch==1?H:PH);y=y+1)for(x=0;x<(branch==1?W:PW);x=x+1)for(ch=0;ch<3;ch=ch+1)begin
                v=expected(branch,y*(branch==1?RS:PS)+x*3+ch,tag);
                for(b=0;b<8;b=b+1)c=(c<<1)^((c[31]^v[b])?32'h04c11db7:32'd0);
            end
            for(k=0;k<32;k=k+1)r[k]=~c[31-k];crc=r;
        end
    endfunction
    assign awready=reset_n&&!active&&!pending&&!bvalid&&!hold_aw&&rng[0];
    assign wready=reset_n&&active&&!hold_w&&rng[3:2]!=0;
    integer k,off,idx,new_bytes,row_left,total_bytes;
    always @(posedge clk)if(reset_n)begin
        tick<=tick+1;rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(error&&!allow_fault)$fatal(1,"REARM_UNEXPECTED_FAULT job=%0d code=%h",job,error_code);
        if(completion_valid&&!port_drained)$fatal(1,"REARM_PUBLISHED_BEFORE_DRAIN");
        if(old_arm!=arm_toggle)arms=arms+1;old_arm=arm_toggle;
        if(held_aw&&(!awvalid||saved_aw!=={awid,awaddr,awlen,awsize,awburst}))$fatal(1,"REARM_AW_UNSTABLE");
        if(held_w&&(!wvalid||saved_w!=={wdata,wstrb,wlast}))$fatal(1,"REARM_W_UNSTABLE");
        if(held_record&&(!completion_valid||saved_record!==record))$fatal(1,"REARM_RECORD_OVERWRITTEN");
        held_aw<=awvalid&&!awready;saved_aw<={awid,awaddr,awlen,awsize,awburst};
        held_w<=wvalid&&!wready;saved_w<={wdata,wstrb,wlast};
        held_record<=completion_valid&&!completion_ready;saved_record<=record;
        if(req_ready&&(active||pending||bvalid||completion_valid||accepted_valid))$fatal(1,"REARM_BEFORE_DRAIN_OR_EVENT");
        if(awvalid&&awready)begin
            if(awid<1||awid>3||awsize!=4||awburst!=1||awlen>15||int'(awaddr[11:0])+(int'(awlen)+1)*16>4096)
                $fatal(1,"REARM_BURST_RULES");
            active<=1;owner<=awid;address<=awaddr;beats<=int'(awlen)+1;beat<=0;burst_bytes<=0;
        end
        if(wvalid&&wready)begin
            if(wlast!==(beat==beats-1))$fatal(1,"REARM_WLAST");
            off=int'(address-(owner==1?raw_address(job%3):owner==2?raw_address(job%3)+32'h160000:input_address(job%3)));
            row_left=owner==1?W*3-off%RS:owner==2?PW*3-off%PS:IW-off%IS;
            if(wstrb!==(16'hffff>>(16-(row_left>=16?16:row_left))))$fatal(1,"REARM_STRIDE_STROBE");
            new_bytes=0;
            for(k=0;k<16;k=k+1)if(wstrb[k])begin
                idx=off+k;
                if(idx<0||idx>=(owner==1?RS*H:owner==2?PS*PH:3*IP)||
                    (owner==1?idx%RS>=W*3:owner==2?idx%PS>=PW*3:idx%IS>=IW))$fatal(1,"REARM_SLOT_OR_GUARD_WRITE");
                if(wdata[k*8+:8]!==expected(owner,idx,job))$fatal(1,"REARM_BYTE job=%0d branch=%0d offset=%0d",job,owner,idx);
                idx=idx+(owner==1?0:owner==2?RS*H:RS*H+PS*PH);
                if(hit[idx])$fatal(1,"REARM_DUPLICATE_BYTE");hit[idx]=1;checks=checks+1;new_bytes=new_bytes+1;
            end
            count[owner]<=count[owner]+new_bytes;burst_bytes<=burst_bytes+new_bytes;address<=address+16;beat<=beat+1;
            if(wlast)begin
                active<=0;pending<=1;delay_b<=7;
                if(owner==final_branch&&count[owner]+new_bytes==(owner==1?N*3:owner==2?PW*PH*3:3*IW*IH))final_held<=1;
            end
        end
        if(pending&&!hold_b&&!final_held)begin
            if(delay_b>0)delay_b<=delay_b-1;
            else begin bvalid<=1;bid<=4'(owner);bresp<=bad_b?2'b10:2'b00;pending<=0;end
        end
        if(bvalid&&bready)begin bvalid<=0;if(!bad_b)acks[owner]<=acks[owner]+burst_bytes;end
    end
    task automatic send_frame(input integer tag);
        integer x,y,g;
        begin
            source_done=0;
            for(y=0;y<H;y=y+1)begin
                for(x=0;x<W;x=x+1)begin
                    @(negedge pixel_clk);pixel_valid=1;pixel_x=11'(x);pixel_y=11'(y);frame_start=x==0&&y==0;
                    pixel_rgb={src(x,y,0,tag),src(x,y,1,tag),src(x,y,2,tag)};
                    for(g=1;g<PIXEL_GAP;g=g+1)begin @(negedge pixel_clk);pixel_valid=0;frame_start=0;end
                end
                @(negedge pixel_clk);pixel_valid=0;frame_start=0;
                repeat(64)@(negedge pixel_clk);
            end
            frame_end=1;@(negedge pixel_clk);frame_end=0;source_done=1;
        end
    endtask
    task automatic start_job;
        integer i,n;reg arm_before;
        begin
            n=0;
            while(!req_ready&&n<64)begin @(negedge clk);n=n+1;end
            if(!req_ready)$fatal(1,"REARM_SECOND_REQUEST_BLOCKED job=%0d state=%0d healthy=%b empty=%b writers=%b accepted=%b consumed=%b completion=%b success=%b m=%b error=%h",job,dut.state,dut.rearm_healthy,dut.rearm_empty,dut.req_ready_vec,accepted_valid,dut.accepted_consumed,completion_valid,completion_success,m_valid,error_code);
            if(case_id==30)begin
                // Prepare the drained preprocessing pipeline while idle,
                // before any new request/AXI response can drive its clear.
                repeat(3)@(negedge clk);
                if(dut.u_input_scale.complete||dut.g_preview.u_preview_scale.complete||
                   dut.u_raw_packer.ending||dut.g_preview.u_preview_packer.ending)
                    $fatal(1,"REARM_PIPELINE_NOT_PREPARED job=%0d",job);
            end
            for(i=0;i<SPAN;i=i+1)hit[i]=0;
            for(i=1;i<=3;i=i+1)begin count[i]=0;acks[i]=0;end
            req_slot=2'(job%3);req_frame_id=32'(job+1);req_preprocess_version=1;
            arm_before=arm_toggle;req_valid=1;@(posedge clk);@(negedge clk);req_valid=0;
            if(raw_base!==raw_address(job%3)||input_base!==input_address(job%3)||slot!==2'(job%3)||frame_id!==32'(job+1))
                $fatal(1,"REARM_REQUEST_IDENTITY");
            if(case_id==4&&job==1)begin
                // Pixel clock has stopped before this request; it cannot acknowledge arm.
                repeat(64)@(negedge clk);
                if(accepted_valid||captured_pixels!=0)$fatal(1,"REARM_STOPPED_PIXEL_CLOCK");pixel_run=1;
            end
            wait(arm_toggle!=arm_before);repeat(6)@(negedge pixel_clk);
        end
    endtask
    integer n,j,expected_code;
    initial begin
        if($value$plusargs("CASE=%d",case_id))begin end
        repeat(8)@(negedge clk);reset_n=1;init_done=1;
        for(job=0;job<JOBS;job=job+1)begin
            accepted_ready=0;completion_ready=0;final_branch=job%3+1;
            if(case_id==4&&job==1)pixel_run=0;
            start_job();
            if(case_id>=10&&case_id<=15&&job==2)begin
                allow_fault=1;accepted_ready=1;final_branch=0;expected_code=12;
                if(case_id!=15)fork send_frame(job); join_none
                case(case_id)
                    10:begin hold_aw=1;wait(awvalid);repeat(7)@(negedge clk);abort=1;repeat(24)@(negedge clk);hold_aw=0;end
                    11:begin hold_w=1;wait(wvalid);repeat(7)@(negedge clk);abort=1;repeat(24)@(negedge clk);hold_w=0;end
                    12:begin hold_b=1;wait(pending);repeat(7)@(negedge clk);abort=1;repeat(24)@(negedge clk);hold_b=0;end
                    13:begin wait(captured_pixels>5);@(negedge pixel_clk);mode_good=0;expected_code=3;end
                    14:begin bad_b=1;expected_code=9;end
                    15:expected_code=7;
                    default:$fatal(1,"bad case");
                endcase
                wait(completion_valid);@(negedge clk);
                if(completion_success||completion_code!==8'(expected_code)||!error||!cancel||!port_drained)
                    $fatal(1,"REARM_FAILURE_DRAIN code=%h expected=%h",completion_code,expected_code);
                completion_ready=1;repeat(100)@(negedge clk);abort=0;mode_good=1;
                req_valid=1;repeat(100)begin @(negedge clk);if(req_ready)$fatal(1,"REARM_FAILURE_REUSED");end
                $display("VIDEO_CAPTURE_REARM_PASS case=%0d successful=%0d fault=%0d bytes=%0d",case_id,completed,expected_code,checks);$finish;
            end
            fork send_frame(job); join_none
            wait(accepted_valid);repeat(31)@(negedge clk);
            if(completion_valid||req_ready)$fatal(1,"REARM_ACCEPT_EVENT_SKIPPED");
            if(case_id!=1)accepted_ready=1;
            wait(final_held);repeat(47)@(negedge clk);
            if(completion_valid||req_ready||port_drained)$fatal(1,"REARM_FINAL_B_SKIPPED");
            final_held=0;final_branch=0;
            if(case_id==1)begin
                wait(dut.eof_seen&&dut.retired==7&&port_drained);
                repeat(97)@(negedge clk);
                if(completion_valid||req_ready||!accepted_valid)$fatal(1,"REARM_ACCEPTED_AFTER_DRAIN_SKIPPED");
                accepted_ready=1;
            end
            wait(completion_valid);@(negedge clk);
            if(!completion_success||completion_code!=0||error||cancel||busy||!port_drained||!source_done||
                source_fault||overflow||captured_pixels!=N||preview_pixels!=PW*PH||input_pixels!=IW*AH||
                raw_written_bytes!=N*3||preview_written_bytes!=PW*PH*3||input_written_bytes!=3*IW*IH||
                source_crc!==crc(1,job)||preview_crc!==crc(2,job)||arms!=job+1||
                fifo_peak<1||fifo_peak>(1<<FIFO_AW))$fatal(1,"REARM_COUNTS_CRC_OR_SOURCE job=%0d",job);
            for(j=1;j<=3;j=j+1)if(count[j]!=acks[j]||count[j]!=(j==1?N*3:j==2?PW*PH*3:3*IW*IH))$fatal(1,"REARM_WRITTEN_COUNTS");
            // A queued request must not mutate the held full record.
            req_valid=1;req_slot=3;req_frame_id=32'hdeadbeef;req_preprocess_version=99;
            repeat(73)begin @(negedge clk);if(req_ready)$fatal(1,"REARM_COMPLETION_NOT_CONSUMED");end
            req_valid=0;completed=completed+1;
            if(case_id>=20&&case_id<=25&&job==JOBS-1)begin
                allow_fault=1;
                if(case_id>=23)begin
                    completion_ready=1;@(posedge clk);@(negedge clk);completion_ready=0;
                    wait(req_ready);@(negedge clk);
                end
                // One sampled late pulse is terminal even after its level falls.
                case(case_id)
                    20,23:abort=1;
                    21,24:force overflow=1;
                    22,25:force source_fault=1;
                endcase
                @(posedge clk);@(negedge clk);
                abort=0;release overflow;release source_fault;
                repeat(8)@(negedge clk);
                if(!error||!cancel||req_ready||error_code!==8'((case_id==20||case_id==23)?12:(case_id==21||case_id==24)?2:3))
                    $fatal(1,"REARM_LATE_PULSE_REUSED");
                if(case_id<23&&(!completion_valid||!completion_success))$fatal(1,"REARM_LATE_PULSE_WITHDREW_RECORD");
                completion_ready=1;@(posedge clk);@(negedge clk);completion_ready=0;
                repeat(100)begin @(negedge clk);if(req_ready||completion_valid)$fatal(1,"REARM_LATE_FAULT_DUPLICATE_EVENT");end
                $display("VIDEO_CAPTURE_REARM_PASS case=%0d successful=%0d late_fault=%0d bytes=%0d",case_id,completed,error_code,checks);$finish;
            end
            if(case_id==3&&job==JOBS-1)begin
                allow_fault=1;init_done=0;repeat(10)@(negedge clk);
                if(!completion_valid||!completion_success)$fatal(1,"REARM_LATE_FAULT_WITHDREW_RECORD");
            end
            if(case_id==2&&job<JOBS-1)begin
                // Keep a valid next identity queued across the successful ACK.
                req_slot=2'((job+1)%3);req_frame_id=32'(job+2);req_preprocess_version=1;req_valid=1;
            end
            completion_ready=1;@(posedge clk);@(negedge clk);completion_ready=0;
            if(case_id==3&&job==JOBS-1)begin
                init_done=1;repeat(20)@(negedge clk);
                if(req_ready||!error)$fatal(1,"REARM_LATE_FAULT_REUSED");
            end
        end
        $display("VIDEO_CAPTURE_REARM_PASS case=%0d successful=%0d arms=%0d bytes=%0d",case_id,completed,arms,checks);$finish;
    end
    initial begin #(LIMIT*CORE_HALF*2*(JOBS+4));$fatal(1,"REARM_WATCHDOG job=%0d state=%0d source=%0d pixels=%0d error=%h",job,dut.state,ingress.state,captured_pixels,error_code);end
endmodule
`default_nettype wire
