`timescale 1ns/1ps
`default_nettype none
module tb_video_three_branch_capture #(parameter integer W=30,H=20,PT=2,PB=1);
    localparam integer N=W*H,PW=W/2,PH=H/2,IW=W*2/5,AH=H*2/5,IH=PT+AH+PB;
    localparam integer RS=(W*3+15)/16*16,PS=(PW*3+15)/16*16,IS=(IW+15)/16*16,IP=IS*IH;
    localparam integer RB=RS*H,VB=PS*PH,IB=3*IP,EXPECTED_INPUT=3*IW*IH;
    localparam integer TIMEOUT=3000+N*50;
    reg clk=0,reset_n=0,init_done=0,abort=0,req_valid=0,source_fault=0,overflow=0;
    reg [1:0] req_slot=0;
    reg [31:0] req_frame_id=32'hf003201,req_preprocess_version=1;
    wire req_ready,arm_toggle,cancel,busy,port_drained,accepted_valid,completion_valid,completion_success,error;
    reg accepted_ready=1,completion_ready=0;
    wire [7:0] completion_code,error_code;
    wire [31:0] frame_id,preprocess_version,raw_base,preview_base,input_base;
    wire [1:0] slot;
    wire [31:0] captured_pixels,preview_pixels,input_pixels,source_crc,preview_crc,fifo_peak;
    wire [31:0] raw_written_bytes,preview_written_bytes,input_written_bytes;
    reg enabled=0,pause_eof=0,pause_source=0;
    integer sent=0,case_id=0,tests=0,hold_final_branch=0;
    wire m_ready;
    reg m_valid;
    reg [47:0] m_data;
    reg hold_aw=0,hold_w=0,hold_b=0,bad_bid=0,bad_resp=0,stray=0;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid,awready,wvalid,wready,wlast,bready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg [3:0] response_id=0;
    reg [1:0] response=0;
    reg response_valid=0;
    wire [3:0] bid=response_id^(bad_bid?4'd8:4'd0);
    wire [1:0] bresp=bad_resp?2'b10:response;
    wire bvalid=response_valid||stray;
    always #4 clk=~clk;
    time transition_time=0;
    integer delta_transitions=0;
    always @(dut.stopping)begin
        if($time!=transition_time)begin transition_time=$time;delta_transitions=0;end
        delta_transitions=delta_transitions+1;
        if(delta_transitions>32)$fatal(1,"combinational fault-ready oscillation");
    end

    function automatic [7:0] raw_byte(input integer x,y,c);
        raw_byte=8'((37*x+19*y+83*c+((x*y)>>3))%256);
    endfunction
    function automatic [7:0] expected(input integer branch,offset);
        integer row,x,c,ox,oy,sx,sy,lx,rx,ty,by,upper,lower,total;
        begin
            if(branch==1)begin row=offset/RS;x=(offset%RS)/3;c=(offset%RS)%3;
                expected=raw_byte(x,row,c);end
            else if(branch==2)begin
                row=offset/PS;x=(offset%PS)/3;c=(offset%PS)%3;
                total=int'(raw_byte(x*2,row*2,c))+int'(raw_byte(x*2+1,row*2,c))+
                    int'(raw_byte(x*2,row*2+1,c))+int'(raw_byte(x*2+1,row*2+1,c));
                expected=8'((total+2)/4);
            end else begin
                c=2-offset/IP;row=(offset%IP)/IS;x=(offset%IP)%IS;
                if(row<PT||row>=PT+AH)expected=0;
                else begin
                    ox=x;oy=row-PT;sx=(5*ox+1)/2;sy=(5*oy+1)/2;
                    lx=ox%2==0?1:3;rx=4-lx;ty=oy%2==0?1:3;by=4-ty;
                    upper=lx*int'(raw_byte(sx,sy,c))+rx*int'(raw_byte(sx+1,sy,c));
                    lower=lx*int'(raw_byte(sx,sy+1,c))+rx*int'(raw_byte(sx+1,sy+1,c));
                    expected=8'((ty*upper/4+by*lower/4+2)/4);
                end
            end
        end
    endfunction
    function automatic [31:0] oracle_crc(input integer divisor);
        reg [31:0] crc,result;
        reg [7:0] value;
        integer x,y,c,b,k;
        begin
            crc=32'hffffffff;
            for(y=0;y<H/divisor;y=y+1)for(x=0;x<W/divisor;x=x+1)for(c=0;c<3;c=c+1)begin
                value=divisor==1?raw_byte(x,y,c):expected(2,y*PS+x*3+c);
                for(b=0;b<8;b=b+1)if(crc[31]^value[b])crc=(crc<<1)^32'h04c11db7;else crc=crc<<1;
            end
            for(k=0;k<32;k=k+1)result[k]=~crc[31-k];oracle_crc=result;
        end
    endfunction
    reg [31:0] expected_crc,expected_preview_crc;
    always @* begin
        m_valid=enabled&&!pause_source&&sent<=N&&!(pause_eof&&sent==N);
        m_data=sent<N?{2'b00,(sent%W==W-1),21'd0,raw_byte(sent%W,sent/W,0),raw_byte(sent%W,sent/W,1),raw_byte(sent%W,sent/W,2)}:
            {2'b01,1'b0,1'b1,12'd37,expected_crc};
        if(sent==0&&case_id==1)m_data[45]=1;
        if(sent==0&&case_id==2)m_data[7:0]=8'hxx;
        if(sent==N-1&&case_id==3)m_data={2'b01,1'b0,1'b1,12'd37,expected_crc};
        if(sent==N&&case_id==4)m_data[0]=~m_data[0];
        if(sent==N&&case_id==5)m_data[44]=0;
    end
    video_three_branch_capture #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB),
        .TIMEOUT_CYCLES(TIMEOUT)) dut(.*);

    reg [7:0] raw_mem[0:RB+31],preview_mem[0:VB+31],input_mem[0:IB+31];
    reg raw_hit[0:RB-1],preview_hit[0:VB-1],input_hit[0:IB-1];
    reg active=0,pending_b=0,held_final=0;
    reg [31:0] address=0;
    integer tick=0,beats=0,index=0,owner_id=0,delay_b=0,burst_bytes=0;
    integer bytes_by_branch[1:3],ack_by_branch[1:3];
    integer i,j,k,relative,row_left,new_bytes,saved_owner,arms=0;
    reg [31:0] random_state=32'hce2b8105;
    reg held_aw=0,held_w=0,held_accept=0,held_completion=0,old_arm=0,old_completion=0;
    reg [1:0] expected_slot;
    reg [31:0] expected_frame_id,expected_version,expected_raw_base,expected_input_base;
    reg [48:0] aw_saved;
    reg [144:0] w_saved;
    reg [65:0] accept_saved;
    reg [74:0] completion_saved;
    assign awready=reset_n&&!active&&!pending_b&&!response_valid&&!hold_aw&&random_state[0];
    assign wready=reset_n&&active&&!hold_w&&random_state[4:3]!=0;
    always @(posedge clk)begin
        if(!reset_n)begin
            sent<=0;tick<=0;active<=0;pending_b<=0;response_valid<=0;held_final<=0;
            held_aw<=0;held_w<=0;held_accept<=0;held_completion<=0;arms<=0;old_arm<=0;old_completion<=0;
            random_state<=32'hce2b8105;
            for(j=1;j<=3;j=j+1)begin bytes_by_branch[j]<=0;ack_by_branch[j]<=0;end
        end else begin
            tick<=tick+1;random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            if(m_valid&&m_ready)sent<=sent+1;
            if(old_arm!=arm_toggle)arms<=arms+1;old_arm<=arm_toggle;
            if(arms>1)$fatal(1,"multiple arm events");
            if(held_aw&&(!awvalid||{awid,awaddr,awlen,awsize,awburst}!==aw_saved))$fatal(1,"AW stability");
            if(held_w&&(!wvalid||{wdata,wstrb,wlast}!==w_saved))$fatal(1,"W stability");
            if(held_accept&&(!accepted_valid||{slot,frame_id,preprocess_version}!==accept_saved))$fatal(1,"accepted stability");
            if(held_completion&&(!completion_valid||{completion_success,completion_code,slot,frame_id,preprocess_version}!==completion_saved))$fatal(1,"completion stability");
            held_aw<=awvalid&&!awready;aw_saved<={awid,awaddr,awlen,awsize,awburst};
            held_w<=wvalid&&!wready;w_saved<={wdata,wstrb,wlast};
            held_accept<=accepted_valid&&!accepted_ready;accept_saved<={slot,frame_id,preprocess_version};
            held_completion<=completion_valid&&!completion_ready;completion_saved<={completion_success,completion_code,slot,frame_id,preprocess_version};
            if(awvalid&&awready)begin
                if(active||pending_b||response_valid||awid<1||awid>3||awsize!==4||awburst!==1||awlen>15||
                    int'(awaddr[11:0])+(int'(awlen)+1)*16>4096)$fatal(1,"AXI burst/owner");
                active<=1;address<=awaddr;owner_id<=int'(awid);beats<=int'(awlen)+1;index<=0;burst_bytes<=0;
            end
            if(wvalid&&wready)begin
                if(!active||wlast!==(index==beats-1))$fatal(1,"AXI WLAST");
                relative=int'(address-(owner_id==1?raw_base:owner_id==2?preview_base:input_base));
                row_left=owner_id==1?W*3-relative%RS:owner_id==2?PW*3-relative%PS:IW-relative%IS;
                if(wstrb!==(16'hffff>>(16-(row_left>=16?16:row_left))))$fatal(1,"WSTRB/row boundary");
                new_bytes=0;
                for(k=0;k<16;k=k+1)if(wstrb[k])begin
                    i=relative+k;
                    if(i<0||i>=(owner_id==1?RB:owner_id==2?VB:IB)||
                       (owner_id==1?i%RS>=W*3:owner_id==2?i%PS>=PW*3:i%IS>=IW))$fatal(1,"guard/stride write");
                    if(wdata[k*8+:8]!==expected(owner_id,i))$fatal(1,"three branch byte p=%0d offset=%0d got=%h expected=%h",owner_id,i,wdata[k*8+:8],expected(owner_id,i));
                    case(owner_id)
                        1:begin if(raw_hit[i])$fatal(1,"duplicate raw");raw_hit[i]=1;raw_mem[i+16]=wdata[k*8+:8];end
                        2:begin if(preview_hit[i])$fatal(1,"duplicate preview");preview_hit[i]=1;preview_mem[i+16]=wdata[k*8+:8];end
                        3:begin if(input_hit[i])$fatal(1,"duplicate input");input_hit[i]=1;input_mem[i+16]=wdata[k*8+:8];end
                    endcase
                    new_bytes=new_bytes+1;
                end
                bytes_by_branch[owner_id]<=bytes_by_branch[owner_id]+new_bytes;burst_bytes<=burst_bytes+new_bytes;
                address<=address+16;index<=index+1;
                if(wlast)begin
                    active<=0;pending_b<=1;delay_b<=5;
                    if(owner_id==hold_final_branch&&bytes_by_branch[owner_id]+new_bytes==
                        (owner_id==1?N*3:owner_id==2?PW*PH*3:EXPECTED_INPUT))held_final<=1;
                end
            end
            if(pending_b&&!hold_b&&!held_final)begin
                if(delay_b>0)delay_b<=delay_b-1;
                else begin response_valid<=1;pending_b<=0;response_id<=4'(owner_id);response<=0;end
            end
            if(response_valid&&bready)begin
                response_valid<=0;
                if(bid==owner_id&&bresp==0)ack_by_branch[owner_id]<=ack_by_branch[owner_id]+burst_bytes;
            end
            if(completion_valid&&!old_completion&&!port_drained)$fatal(1,"completion before drain");
            old_completion<=completion_valid;
            if(completion_valid&&completion_success&&(sent!=N+1||accepted_valid||active||pending_b||response_valid))$fatal(1,"early success");
        end
    end
    task automatic restart;
        begin
            @(negedge clk);reset_n=0;init_done=0;enabled=0;abort=0;source_fault=0;overflow=0;req_valid=0;
            req_slot=0;req_frame_id=32'hf003201;req_preprocess_version=1;accepted_ready=1;completion_ready=0;
            pause_eof=0;pause_source=0;hold_aw=0;hold_w=0;hold_b=0;bad_bid=0;bad_resp=0;stray=0;hold_final_branch=0;
            for(i=0;i<RB+32;i=i+1)raw_mem[i]=8'ha5;
            for(i=0;i<VB+32;i=i+1)preview_mem[i]=8'ha5;
            for(i=0;i<IB+32;i=i+1)input_mem[i]=8'ha5;
            for(i=0;i<RB;i=i+1)raw_hit[i]=0;
            for(i=0;i<VB;i=i+1)preview_hit[i]=0;
            for(i=0;i<IB;i=i+1)input_hit[i]=0;
            repeat(5)@(negedge clk);reset_n=1;init_done=1;
        end
    endtask
    task automatic request;
        begin
            @(negedge clk);expected_slot=req_slot;expected_frame_id=req_frame_id;expected_version=req_preprocess_version;
            case(req_slot)
                0:begin expected_raw_base=32'h82000000;expected_input_base=32'h82800000;end
                1:begin expected_raw_base=32'h82200000;expected_input_base=32'h82850000;end
                2:begin expected_raw_base=32'h82400000;expected_input_base=32'h828a0000;end
                default:begin expected_raw_base=0;expected_input_base=0;end
            endcase
            req_valid=1;@(posedge clk);while(!req_ready)@(posedge clk);
            @(negedge clk);req_valid=0;enabled=1;
            if(raw_base!==expected_raw_base||preview_base!==(expected_raw_base+32'h160000)||input_base!==expected_input_base)
                $fatal(1,"slot base mapping");
        end
    endtask
    task automatic result_check(input integer code);
        integer b,n;
        begin
            wait(completion_valid);@(negedge clk);
            if(completion_success!==(code==0)||completion_code!==8'(code)||!port_drained||
               slot!==expected_slot||frame_id!==expected_frame_id||preprocess_version!==expected_version)
                $fatal(1,"completion metadata/code got=%h expected=%h",completion_code,code);
            if(raw_written_bytes!==ack_by_branch[1]||preview_written_bytes!==ack_by_branch[2]||input_written_bytes!==ack_by_branch[3])$fatal(1,"ack counters");
            if(code==0)begin
                if(captured_pixels!=N||preview_pixels!=PW*PH||input_pixels!=IW*AH||source_crc!==expected_crc||
                   preview_crc!==expected_preview_crc||fifo_peak!=37||error||busy||cancel)$fatal(1,"success counters/CRC");
                for(b=1;b<=3;b=b+1)for(n=0;n<(b==1?RB+32:b==2?VB+32:IB+32);n=n+1)begin
                    i=n-16;
                    if(i>=0&&i<(b==1?RB:b==2?VB:IB)&&(b==1?i%RS<W*3:b==2?i%PS<PW*3:i%IS<IW))begin
                        if((b==1?raw_mem[n]:b==2?preview_mem[n]:input_mem[n])!==expected(b,i))$fatal(1,"final memory");
                    end else if((b==1?raw_mem[n]:b==2?preview_mem[n]:input_mem[n])!==8'ha5)$fatal(1,"final guard");
                end
            end else if(!error||!cancel||req_ready)$fatal(1,"missing sticky error");
            repeat(25)@(negedge clk);tests=tests+1;
        end
    endtask
    integer t,fd;
    string dump_file;
    initial begin
        expected_crc=oracle_crc(1);expected_preview_crc=oracle_crc(2);
        if($value$plusargs("CASE=%d",case_id))begin end
        if($value$plusargs("DUMP=%s",dump_file))begin end
        if(case_id==0)begin
            for(t=0;t<($test$plusargs("normal_only")?1:3);t=t+1)begin
                restart();req_slot=2'(t);req_frame_id=req_frame_id+32'(t);hold_final_branch=t+1;accepted_ready=0;
                request();wait(accepted_valid);repeat(35)@(negedge clk);
                if(completion_valid)$fatal(1,"success before accepted event consumed");accepted_ready=1;
                wait(held_final);repeat(193)@(negedge clk);
                if(completion_valid)$fatal(1,"success before final branch B");held_final=0;hold_final_branch=0;
                result_check(0);
                if(dump_file!="")begin
                    fd=$fopen(dump_file,"w");if(!fd)$fatal(1,"dump open");
                    for(i=0;i<3*IP;i=i+1)if(i%IS<IW)$fdisplay(fd,"%02h",input_mem[i+16]);$fclose(fd);
                end
            end
        end else begin
            restart();
            if(case_id==18)req_slot=3;if(case_id==19)req_preprocess_version=2;
            if(case_id==20)req_frame_id=32'hxxxxxxxx;if(case_id==21)req_slot=2'bxx;
            if(case_id==17)pause_source=1;
            if(case_id==8||case_id==11)hold_aw=1;
            if(case_id==9||case_id==12)hold_w=1;
            if(case_id==10||case_id==13)hold_b=1;
            if(case_id==29)hold_b=1;
            if(case_id==14)bad_bid=1;if(case_id==15)bad_resp=1;
            request();
            case(case_id)
                1,2:result_check(4);
                3,4,5:result_check(5);
                6,7:begin wait(accepted_valid||sent>0);@(negedge clk);source_fault=case_id==6;overflow=case_id==7;result_check(case_id==6?3:2);end
                8,11:begin wait(awvalid);repeat(3)@(negedge clk);abort=case_id==8;init_done=case_id!=11;repeat(20)@(negedge clk);hold_aw=0;result_check(case_id==8?12:1);end
                9,12:begin wait(wvalid);repeat(3)@(negedge clk);abort=case_id==9;init_done=case_id!=12;repeat(20)@(negedge clk);hold_w=0;result_check(case_id==9?12:1);end
                10,13:begin wait(pending_b);repeat(3)@(negedge clk);abort=case_id==10;init_done=case_id!=13;repeat(20)@(negedge clk);hold_b=0;result_check(case_id==10?12:1);end
                14,15:result_check(9);
                16:begin wait(accepted_valid||sent>0);@(negedge clk);stray=1;@(negedge clk);stray=0;result_check(9);end
                17:result_check(7);
                18,19,20,21:begin result_check(8);if(arm_toggle||awvalid||bytes_by_branch[1]+bytes_by_branch[2]+bytes_by_branch[3]!=0)$fatal(1,"bad request armed");end
                22:begin pause_eof=1;wait(raw_written_bytes==N*3&&preview_written_bytes==PW*PH*3&&input_written_bytes==EXPECTED_INPUT);
                    repeat(35)@(negedge clk);if(completion_valid)$fatal(1,"success without EOF");pause_eof=0;result_check(0);end
                23:begin result_check(0);@(negedge clk);abort=1;init_done=0;repeat(20)@(negedge clk);
                    if(!completion_valid||!completion_success||completion_code!=0)$fatal(1,"late fault withdrew published completion");end
                24:begin
                    wait(dut.input_valid&&dut.input_ready);@(negedge clk);force dut.input_rgb=24'hxxxxxx;
                    $display("BAD_INPUT_INJECTED time=%0t",$time);$fflush();
                    wait(error);@(negedge clk);release dut.input_rgb;result_check(10);
                end
                25:begin
                    result_check(0);@(negedge clk);stray=1;@(negedge clk);stray=0;
                    repeat(20)@(negedge clk);
                    if(!completion_valid||!completion_success||completion_code!=0||!error||error_code!=9)
                        $fatal(1,"late stray changed published completion");
                end
                26:begin
                    accepted_ready=0;
                    wait(dut.eof_seen&&dut.retired==7&&port_drained);
                    repeat(TIMEOUT+16)@(negedge clk);
                    if(error||completion_valid||!accepted_valid)$fatal(1,"accepted backpressure timed out");
                    accepted_ready=1;result_check(0);
                end
                27:begin
                    wait(sent>0);@(negedge clk);req_valid=1;req_slot=2;req_frame_id=32'hfeed1234;req_preprocess_version=99;
                    result_check(0);if(req_ready)$fatal(1,"one-shot reused without reset");req_valid=0;
                end
                28:begin
                    wait(dut.result_valid_vec[0]);@(negedge clk);force dut.result_tags[31:0]=32'hbad;
                    wait(error);@(negedge clk);release dut.result_tags[31:0];result_check(6);
                    // A terminal metadata error and abort are sampled together.
                    // Classification crosses one register; its first reason
                    // must survive a later, normally higher-priority offline.
                    restart();request();wait(dut.result_valid_vec[0]);
                    @(negedge clk);force dut.result_tags[31:0]=32'hbad;abort=1;
                    @(posedge clk);#1;
                    if(error)$fatal(1,"CAPTURE_FAULT_PIPELINE_RED: terminal fault was not registered before public error");
                    if(!cancel)$fatal(1,"pending terminal fault did not cancel data intake");
                    @(negedge clk);release dut.result_tags[31:0];abort=0;init_done=0;
                    @(posedge clk);#1;
                    if(!error||error_code!=6)$fatal(1,"later offline replaced earlier metadata fault");
                    result_check(6);
                    // Once the source event is consumed, each fresh fast fault
                    // must block success on that exact publication edge.
                    for(t=0;t<4;t=t+1)begin
                        restart();accepted_ready=0;request();
                        wait(dut.eof_seen&&dut.retired==7&&port_drained);
                        repeat(3)@(negedge clk);
                        if(completion_valid||!accepted_valid)$fatal(1,"bad publication-window setup");
                        accepted_ready=1;@(posedge clk);@(negedge clk);
                        case(t)0:abort=1;1:source_fault=1;2:overflow=1;3:init_done=0;endcase
                        @(posedge clk);#1;
                        if(completion_valid&&completion_success)$fatal(1,"success raced a fresh publication-edge fault");
                        wait(error);result_check(t==0?12:t==1?3:t==2?2:1);
                    end
                    // Health can fail while idle; after the detection edge its
                    // pending interval must not advertise a new descriptor.
                    restart();@(negedge clk);force dut.writer_fault=3'b001;
                    @(posedge clk);#1;
                    if(error||!cancel)$fatal(1,"idle health fault did not cross pending boundary");
                    @(negedge clk);release dut.writer_fault;req_valid=1;
                    #1;if(req_ready)$fatal(1,"pending idle fault advertised descriptor acceptance");
                    @(posedge clk);@(negedge clk);req_valid=0;
                    wait(completion_valid);@(negedge clk);
                    if(completion_success||completion_code!=6||frame_id!=0||arm_toggle||!port_drained||
                       bytes_by_branch[1]+bytes_by_branch[2]+bytes_by_branch[3]!=0)
                        $fatal(1,"idle fault manufactured an owned frame or successful completion");
                    tests=tests+1;
                end
                29:begin
                    wait(pending_b);repeat(50)@(negedge clk);
                    if(arm_toggle||accepted_valid||captured_pixels!=0||bytes_by_branch[1]!=0||bytes_by_branch[2]!=0)
                        $fatal(1,"armed before input padding retired");
                    hold_b=0;result_check(0);
                end
                default:$fatal(1,"unknown case");
            endcase
        end
        $display("VIDEO_THREE_CAPTURE_PASS W=%0d H=%0d case=%0d tests=%0d",W,H,case_id,tests);$finish;
    end
    initial begin repeat(TIMEOUT*3)@(posedge clk);$fatal(1,"three capture timeout");end
endmodule
`default_nettype wire
