`timescale 1ns/1ps
`default_nettype none
// Real capture datapath, three write DMAs and real AXI B retirement. The memory
// oracle computes image bytes independently from address/geometry and checks
// A5 guards and untouched stride gaps; no fabricated event enters the endpoint.
module tb_video_capture_mmio_core #(parameter integer W=30,H=20,PT=2,PB=1);
    localparam integer N=W*H,PW=W/2,PH=H/2,IW=W*2/5,AH=H*2/5,IH=PT+AH+PB;
    localparam integer RS=(W*3+15)/16*16,PS=(PW*3+15)/16*16,IS=(IW+15)/16*16,IP=IS*IH;
    localparam integer RB=RS*H,VB=PS*PH,IB=3*IP,IBYTES=3*IW*IH;
    reg clk_i=0,rst_ni=0,init_done=0,source_fault=0,overflow=0;
    always #4 clk_i=~clk_i;
    reg [31:0] s_axi_awaddr_i=0,s_axi_wdata_i=0,s_axi_araddr_i=0;
    reg [2:0] s_axi_awprot_i=0,s_axi_arprot_i=0;
    reg [3:0] s_axi_wstrb_i=15;
    reg s_axi_awvalid_i=0,s_axi_wvalid_i=0,s_axi_bready_i=1,s_axi_arvalid_i=0,s_axi_rready_i=1;
    wire s_axi_awready_o,s_axi_wready_o,s_axi_bvalid_o,s_axi_arready_o,s_axi_rvalid_o;
    wire [1:0] s_axi_bresp_o,s_axi_rresp_o;
    wire [31:0] s_axi_rdata_o;
    wire capture_req_valid_o,capture_req_ready_i;
    wire [1:0] capture_req_slot_o;
    wire [31:0] capture_req_frame_id_o,capture_req_version_o;
    wire accepted_valid_i,accepted_ready_o,completion_valid_i,completion_ready_o,completion_success_i;
    wire [7:0] completion_code_i,capture_live_code_i;
    wire [1:0] capture_slot_i;
    wire [31:0] capture_frame_id_i,capture_version_i,capture_raw_base_i,capture_preview_base_i,capture_input_base_i;
    wire [31:0] capture_raw_pixels_i,capture_preview_pixels_i,capture_input_pixels_i;
    wire [31:0] capture_raw_bytes_i,capture_preview_bytes_i,capture_input_bytes_i;
    wire [31:0] capture_raw_crc_i,capture_preview_crc_i,capture_fifo_peak_i;
    wire capture_live_fault_i,capture_port_drained_i,capture_abort_o,irq_o;
    video_capture_mmio #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB)) u_mmio(.*);
    wire arm_toggle,cancel,busy,m_ready;
    reg enabled=0,pause_eof=0;
    integer sent=0;
    reg m_valid;
    reg [47:0] m_data;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid,awready,wvalid,wready,wlast,bready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg [3:0] bid=0;
    reg [1:0] bresp=0;
    reg bvalid=0;
    video_three_branch_capture #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB),.TIMEOUT_CYCLES(100000)) u_capture(
        .clk(clk_i),.reset_n(rst_ni),.init_done(init_done),.abort(capture_abort_o),
        .req_valid(capture_req_valid_o),.req_ready(capture_req_ready_i),.req_slot(capture_req_slot_o),
        .req_frame_id(capture_req_frame_id_o),.req_preprocess_version(capture_req_version_o),
        .m_valid(m_valid),.m_data(m_data),.m_ready(m_ready),.source_fault(source_fault),.overflow(overflow),
        .arm_toggle(arm_toggle),.cancel(cancel),.busy(busy),.port_drained(capture_port_drained_i),
        .accepted_valid(accepted_valid_i),.accepted_ready(accepted_ready_o),
        .completion_valid(completion_valid_i),.completion_ready(completion_ready_o),.completion_success(completion_success_i),
        .completion_code(completion_code_i),.error(capture_live_fault_i),.error_code(capture_live_code_i),
        .frame_id(capture_frame_id_i),.preprocess_version(capture_version_i),.slot(capture_slot_i),
        .raw_base(capture_raw_base_i),.preview_base(capture_preview_base_i),.input_base(capture_input_base_i),
        .captured_pixels(capture_raw_pixels_i),.preview_pixels(capture_preview_pixels_i),.input_pixels(capture_input_pixels_i),
        .source_crc(capture_raw_crc_i),.preview_crc(capture_preview_crc_i),.fifo_peak(capture_fifo_peak_i),
        .raw_written_bytes(capture_raw_bytes_i),.preview_written_bytes(capture_preview_bytes_i),.input_written_bytes(capture_input_bytes_i),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
    function automatic [7:0] raw_byte(input integer x,y,c);
        raw_byte=8'((37*x+19*y+83*c+((x*y)>>3))%256);
    endfunction
    function automatic [7:0] expected(input integer branch,offset);
        integer row,x,c,sx,sy,lx,rx,ty,by,upper,lower,total;
        begin
            if(branch==1)begin row=offset/RS;x=(offset%RS)/3;c=(offset%RS)%3;expected=raw_byte(x,row,c);end
            else if(branch==2)begin
                row=offset/PS;x=(offset%PS)/3;c=(offset%PS)%3;
                total=int'(raw_byte(x*2,row*2,c))+int'(raw_byte(x*2+1,row*2,c))+
                    int'(raw_byte(x*2,row*2+1,c))+int'(raw_byte(x*2+1,row*2+1,c));expected=8'((total+2)/4);
            end else begin
                c=2-offset/IP;row=(offset%IP)/IS;x=(offset%IP)%IS;
                if(row<PT||row>=PT+AH)expected=0;
                else begin
                    sx=(5*x+1)/2;sy=(5*(row-PT)+1)/2;
                    lx=x%2==0?1:3;rx=4-lx;ty=(row-PT)%2==0?1:3;by=4-ty;
                    upper=lx*int'(raw_byte(sx,sy,c))+rx*int'(raw_byte(sx+1,sy,c));
                    lower=lx*int'(raw_byte(sx,sy+1,c))+rx*int'(raw_byte(sx+1,sy+1,c));
                    expected=8'((ty*upper/4+by*lower/4+2)/4);
                end
            end
        end
    endfunction
    function automatic [31:0] oracle_crc(input integer divisor);
        reg [31:0] crc,result;reg [7:0] value;integer x,y,c,b,k;
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
        m_valid=enabled&&sent<=N&&!(pause_eof&&sent==N);
        m_data=sent<N?{2'b00,(sent%W==W-1),21'd0,raw_byte(sent%W,sent/W,0),raw_byte(sent%W,sent/W,1),raw_byte(sent%W,sent/W,2)}:
            {2'b01,1'b0,1'b1,12'd37,expected_crc};
    end
    reg [7:0] raw_mem[0:RB+31],preview_mem[0:VB+31],input_mem[0:IB+31];
    reg raw_hit[0:RB-1],preview_hit[0:VB-1],input_hit[0:IB-1];
    reg active=0,pending_b=0,hold_b=0,hold_final=0,held_final=0,fail_next_b=0;
    reg [31:0] address=0,expected_raw_base=0,expected_input_base=0;
    integer beats=0,index=0,owner_id=0,delay_b=0,burst_bytes=0;
    integer bytes_by_branch[1:3],ack_by_branch[1:3];
    integer i,j,k,relative,new_bytes,tests=0,checked_bytes=0;
    reg old_arm=0,held_aw=0,held_w=0,held_b=0;
    reg [48:0] aw_saved;
    reg [144:0] w_saved;
    reg [5:0] b_saved;
    assign awready=rst_ni&&!active&&!pending_b&&!bvalid;
    assign wready=rst_ni&&active;
    always @(posedge clk_i)begin
        if(!rst_ni)begin
            sent<=0;active<=0;pending_b<=0;bvalid<=0;held_final<=0;old_arm<=0;
            held_aw<=0;held_w<=0;held_b<=0;enabled<=0;
            for(j=1;j<=3;j=j+1)begin bytes_by_branch[j]<=0;ack_by_branch[j]<=0;end
        end else begin
            if(old_arm!=arm_toggle)enabled<=1;old_arm<=arm_toggle;
            if(m_valid&&m_ready)sent<=sent+1;
            if(held_aw&&(!awvalid||{awid,awaddr,awlen,awsize,awburst}!==aw_saved))$fatal(1,"core AW stability");
            if(held_w&&(!wvalid||{wdata,wstrb,wlast}!==w_saved))$fatal(1,"core W stability");
            if(held_b&&(!bvalid||{bid,bresp}!==b_saved))$fatal(1,"memory B stability");
            held_aw<=awvalid&&!awready;aw_saved<={awid,awaddr,awlen,awsize,awburst};
            held_w<=wvalid&&!wready;w_saved<={wdata,wstrb,wlast};held_b<=bvalid&&!bready;b_saved<={bid,bresp};
            if(awvalid&&awready)begin
                if(awid<1||awid>3||awsize!==4||awburst!==1||awlen>15||
                    int'(awaddr[11:0])+(int'(awlen)+1)*16>4096)$fatal(1,"AXI address/size");
                active<=1;address<=awaddr;owner_id<=int'(awid);beats<=int'(awlen)+1;index<=0;burst_bytes<=0;
            end
            if(wvalid&&wready)begin
                if(!active||wlast!==(index==beats-1))$fatal(1,"AXI WLAST");
                relative=int'(address-(owner_id==1?expected_raw_base:owner_id==2?expected_raw_base+32'h160000:expected_input_base));
                new_bytes=0;
                for(k=0;k<16;k=k+1)if(wstrb[k])begin
                    i=relative+k;
                    if(i<0||i>=(owner_id==1?RB:owner_id==2?VB:IB)||
                        (owner_id==1?i%RS>=W*3:owner_id==2?i%PS>=PW*3:i%IS>=IW))$fatal(1,"guard/stride write");
                    if(wdata[k*8+:8]!==expected(owner_id,i))$fatal(1,"byte branch%0d offset%0d got%h expected%h",owner_id,i,wdata[k*8+:8],expected(owner_id,i));
                    case(owner_id)
                        1:begin if(raw_hit[i])$fatal(1,"duplicate raw");raw_hit[i]=1;raw_mem[i+16]=wdata[k*8+:8];end
                        2:begin if(preview_hit[i])$fatal(1,"duplicate preview");preview_hit[i]=1;preview_mem[i+16]=wdata[k*8+:8];end
                        3:begin if(input_hit[i])$fatal(1,"duplicate input");input_hit[i]=1;input_mem[i+16]=wdata[k*8+:8];end
                    endcase
                    new_bytes=new_bytes+1;checked_bytes=checked_bytes+1;
                end
                bytes_by_branch[owner_id]<=bytes_by_branch[owner_id]+new_bytes;burst_bytes<=burst_bytes+new_bytes;
                address<=address+16;index<=index+1;
                if(wlast)begin
                    active<=0;pending_b<=1;delay_b<=4;
                    if(owner_id==3&&hold_final&&bytes_by_branch[3]+new_bytes==IBYTES)held_final<=1;
                end
            end
            if(pending_b&&!hold_b&&!(held_final&&hold_final))begin
                if(delay_b>0)delay_b<=delay_b-1;
                else begin bvalid<=1;pending_b<=0;bid<=4'(owner_id);bresp<=fail_next_b?2'b10:2'b00;fail_next_b<=0;end
            end
            if(bvalid&&bready)begin bvalid<=0;if(bresp==0)ack_by_branch[owner_id]<=ack_by_branch[owner_id]+burst_bytes;end
            if(completion_valid_i&&!capture_port_drained_i)$fatal(1,"core completion before actual B drain");
            if(completion_valid_i&&completion_success_i&&(sent!=N+1||active||pending_b||bvalid))$fatal(1,"success before EOF/B");
        end
    end
    task automatic write_word(input [31:0] addr,value,input [1:0] response);
        begin
            @(negedge clk_i);s_axi_awaddr_i=addr;s_axi_wdata_i=value;s_axi_awvalid_i=1;s_axi_wvalid_i=1;
            do @(posedge clk_i);while(!(s_axi_awready_o&&s_axi_wready_o));
            @(negedge clk_i);s_axi_awvalid_i=0;s_axi_wvalid_i=0;
            while(!s_axi_bvalid_o)@(negedge clk_i);
            if(s_axi_bresp_o!==response)$fatal(1,"core MMIO write response %h expected%h",s_axi_bresp_o,response);
            @(negedge clk_i);
        end
    endtask
    task automatic read_word(input [31:0] addr,output [31:0] value);
        begin
            @(negedge clk_i);s_axi_araddr_i=addr;s_axi_arvalid_i=1;
            do @(posedge clk_i);while(!s_axi_arready_o);
            @(negedge clk_i);s_axi_arvalid_i=0;
            while(!s_axi_rvalid_o)@(negedge clk_i);
            if(s_axi_rresp_o!==0)$fatal(1,"core MMIO read response");value=s_axi_rdata_o;
            @(negedge clk_i);
        end
    endtask
    task automatic expect_read(input [31:0] addr,value);
        reg [31:0] actual;
        begin read_word(addr,actual);if(actual!==value)$fatal(1,"core read %h got%h expected%h",addr,actual,value);end
    endtask
    task automatic restart;
        begin
            @(negedge clk_i);rst_ni=0;init_done=0;source_fault=0;overflow=0;
            s_axi_awvalid_i=0;s_axi_wvalid_i=0;s_axi_arvalid_i=0;pause_eof=0;hold_b=0;hold_final=0;fail_next_b=0;
            for(i=0;i<RB+32;i=i+1)raw_mem[i]=8'ha5;
            for(i=0;i<VB+32;i=i+1)preview_mem[i]=8'ha5;
            for(i=0;i<IB+32;i=i+1)input_mem[i]=8'ha5;
            for(i=0;i<RB;i=i+1)raw_hit[i]=0;
            for(i=0;i<VB;i=i+1)preview_hit[i]=0;
            for(i=0;i<IB;i=i+1)input_hit[i]=0;
            repeat(5)@(negedge clk_i);rst_ni=1;init_done=1;
        end
    endtask
    task automatic request(input integer which,input [31:0] frame);
        begin
            case(which)
                0:begin expected_raw_base=32'h82000000;expected_input_base=32'h82800000;end
                1:begin expected_raw_base=32'h82200000;expected_input_base=32'h82850000;end
                2:begin expected_raw_base=32'h82400000;expected_input_base=32'h828a0000;end
            endcase
            write_word(32'h20010008,1,0);write_word(32'h20010010,7,0);
            write_word(32'h20010100,32'(which),0);write_word(32'h20010104,frame,0);write_word(32'h20010020,1,0);
        end
    endtask
    task automatic wait_complete;
        reg [31:0] status;integer cycles;
        begin
            status=0;cycles=0;
            while(!status[5]&&cycles<30000)begin read_word(32'h2001000c,status);cycles=cycles+1;end
            if(!status[5])$fatal(1,"completion timeout status%h",status);
            if(!capture_port_drained_i||active||pending_b||bvalid)$fatal(1,"mailbox precedes B drain");
        end
    endtask
    task automatic verify_memory;
        begin
            for(i=0;i<RB;i=i+1)begin
                if(raw_hit[i]!==1'(i%RS<W*3)||raw_mem[i+16]!==(i%RS<W*3?expected(1,i):8'ha5))$fatal(1,"raw coverage/gap %0d",i);
            end
            for(i=0;i<VB;i=i+1)begin
                if(preview_hit[i]!==1'(i%PS<PW*3)||preview_mem[i+16]!==(i%PS<PW*3?expected(2,i):8'ha5))$fatal(1,"preview coverage/gap %0d",i);
            end
            for(i=0;i<IB;i=i+1)begin
                if(input_hit[i]!==1'(i%IS<IW)||input_mem[i+16]!==(i%IS<IW?expected(3,i):8'ha5))$fatal(1,"input coverage/gap %0d",i);
            end
            for(i=0;i<16;i=i+1)if(raw_mem[i]!==8'ha5||raw_mem[RB+16+i]!==8'ha5||
                preview_mem[i]!==8'ha5||preview_mem[VB+16+i]!==8'ha5||input_mem[i]!==8'ha5||input_mem[IB+16+i]!==8'ha5)$fatal(1,"memory guard");
        end
    endtask
    reg [31:0] status;
    integer test_id;
    initial begin
        expected_crc=oracle_crc(1);expected_preview_crc=oracle_crc(2);
        for(test_id=0;test_id<3;test_id=test_id+1)begin
            restart;request(test_id,test_id==2?32'hffffffff:32'(test_id));wait_complete;
            expect_read(32'h2001018c,1);expect_read(32'h20010018,0);
            expect_read(32'h20010190,expected_raw_base);expect_read(32'h20010198,expected_input_base);
            expect_read(32'h2001019c,N);expect_read(32'h200101a0,PW*PH);expect_read(32'h200101a4,IW*AH);
            expect_read(32'h200101a8,3*N);expect_read(32'h200101ac,3*PW*PH);expect_read(32'h200101b0,IBYTES);
            expect_read(32'h200101b4,expected_crc);expect_read(32'h200101b8,expected_preview_crc);expect_read(32'h200101bc,37);
            if(!irq_o||ack_by_branch[1]!=3*N||ack_by_branch[2]!=3*PW*PH||ack_by_branch[3]!=IBYTES)$fatal(1,"successful B bytes");
            verify_memory;write_word(32'h20010014,3,0);if(irq_o)$fatal(1,"core ACK IRQ");
            write_word(32'h20010020,1,2);tests=tests+1;
        end
        // Both EOF and every B are required. Hold the real final NCHW response.
        restart;hold_final=1;pause_eof=1;request(0,17);
        wait(sent==N);repeat(50)@(negedge clk_i);read_word(32'h2001000c,status);if(status[5])$fatal(1,"completion before EOF");
        pause_eof=0;wait(held_final);repeat(40)@(negedge clk_i);
        repeat(12)begin read_word(32'h2001000c,status);if(status[5]||capture_port_drained_i)$fatal(1,"completion before final input B");end
        hold_final=0;wait_complete;expect_read(32'h2001018c,1);verify_memory;tests=tests+1;
        // A failed real B cannot be reported while that response is withheld.
        restart;request(1,18);wait(accepted_valid_i);hold_b=1;wait(pending_b);
        repeat(20)@(negedge clk_i);read_word(32'h2001000c,status);if(status[5])$fatal(1,"error before response");
        // Shared arbiter BRESP fault has code09 in the unchanged capture core.
        fail_next_b=1;hold_b=0;wait_complete;expect_read(32'h2001018c,32'h900);expect_read(32'h20010018,9);
        expect_read(32'h200101a8,ack_by_branch[1]);expect_read(32'h200101ac,ack_by_branch[2]);expect_read(32'h200101b0,ack_by_branch[3]);
        if(!capture_abort_o||!irq_o)$fatal(1,"failed DMA missing abort/IRQ");tests=tests+1;
        // A real pre-first-PIX producer failure has no accepted event. Its
        // legitimate completion is retained with code03 after actual drain.
        restart;hold_b=1;request(0,19);wait(capture_req_ready_i==0);
        @(negedge clk_i);source_fault=1;repeat(8)@(negedge clk_i);hold_b=0;wait_complete;
        expect_read(32'h2001018c,32'h300);expect_read(32'h20010018,3);expect_read(32'h20010028,0);tests=tests+1;
        read_word(32'h2001000c,status);if(status[4]||sent!=0)$fatal(1,"pre-first-PIX error unexpectedly accepted pixels");
        // Reset is coordinated across endpoint, capture core and memory model,
        // and therefore can reset an outstanding DMA before another one-shot.
        restart;hold_b=1;request(2,20);wait(pending_b);restart;
        expect_read(32'h2001000c,128);request(2,0);wait_complete;expect_read(32'h20010184,0);verify_memory;tests=tests+1;
        $display("VIDEO_CAPTURE_MMIO_CORE_PASS cases=%0d geometry=%0dx%0d bytes_checked=%0d",tests,W,H,checked_bytes);$finish;
    end
    initial begin #10000000;$fatal(1,"real-core MMIO timeout sent=%0d",sent);end
endmodule
`default_nettype wire
