`timescale 1ns/1ps
`default_nettype none
// Real capture datapath, three write DMAs and real AXI B retirement. The memory
// oracle computes image bytes independently from address/geometry and checks
// A5 guards and untouched stride gaps; no fabricated event enters the endpoint.
module tb_video_shared_memory #(parameter integer W=30,H=20,PT=2,PB=1,JOBS=7,GAPS=1,QUOTA=4,PIXEL_HALF=25);
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
    wire [31:0] capture_req_frame_id_o,capture_req_version_o,capture_req_generation_o;
    wire accepted_valid_i,accepted_ready_o,completion_valid_i,completion_ready_o,completion_success_i;
    wire [7:0] completion_code_i,capture_live_code_i;
    wire [1:0] capture_slot_i;
    wire [31:0] capture_frame_id_i,capture_version_i,capture_raw_base_i,capture_preview_base_i,capture_input_base_i;
    wire [31:0] capture_raw_pixels_i,capture_preview_pixels_i,capture_input_pixels_i;
    wire [31:0] capture_raw_bytes_i,capture_preview_bytes_i,capture_input_bytes_i;
    wire [31:0] capture_raw_crc_i,capture_preview_crc_i,capture_fifo_peak_i;
    wire capture_live_fault_i,capture_port_drained_i,capture_abort_o,irq_o;
    video_capture_mmio_v2 #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB)) u_mmio(.*);
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
    wire [3:0] bid;wire [1:0] bresp;wire bvalid;
    video_three_branch_capture #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB),.TIMEOUT_CYCLES(1000000),.ENABLE_REARM(1)) u_capture(
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
    function automatic [7:0] source_value(input integer x,y,c,tag);
        source_value=8'((37*x+19*y+83*c+((x*y)>>3)+tag*43+tag*x)%256);
    endfunction
    function automatic [7:0] raw_byte(input integer x,y,c);
        raw_byte=source_value(x,y,c,test_id);
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
    reg old_arm=0;
    integer test_id=0,i,j,branch,offset,tests=0,verified_bytes=0;
    reg [31:0] expected_raw_base=0,expected_input_base=0;
    reg pixel_clk=0;initial begin #3;forever #(PIXEL_HALF)pixel_clk=~pixel_clk;end
    localparam integer HT=W+128,VT=H+8;
    reg [10:0] pixel_x=0,pixel_y=0;
    wire pixel_de=pixel_x<W&&pixel_y<H,pixel_hs=pixel_x>=W+2&&pixel_x<W+4,pixel_vs=pixel_y>=H+1&&pixel_y<H+3;
    wire pixel_frame_start=pixel_x==0&&pixel_y==0;
    reg record_valid=0;wire record_ready,record_reject_valid;wire [7:0] record_reject_code;
    reg [31:0] record_base=0,record_frame_id=0;reg [1:0] record_slot=0;
    wire commit_valid,release_valid;reg commit_ready=1,release_ready=1;
    wire [31:0] commit_frame_id,release_frame_id;wire [1:0] commit_slot,release_slot;
    wire [23:0] out_rgb;wire out_de,out_hs,out_vs,display_error;wire [7:0] display_code;
    wire [31:0] commits,scans,lines,underflows,display_frame,rejected_records;
    wire [3:0] d_arid,d_rid;wire [31:0] d_araddr;wire [7:0] d_arlen;wire [2:0] d_arsize;
    wire [1:0] d_arburst,d_rresp;wire d_arvalid,d_arready,d_rvalid,d_rready,d_rlast;wire [127:0] d_rdata;
    raw_display #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(1000000)) scanout(
        .core_clk(clk_i),.core_reset_n(rst_ni),.pixel_clk(pixel_clk),.pixel_reset_n(rst_ni),.ddr_ready(init_done),
        .record_valid(record_valid),.record_ready(record_ready),.record_reject_valid(record_reject_valid),.record_reject_ready(1'b1),
        .record_reject_code(record_reject_code),.rejected_records(rejected_records),.record_base(record_base),.record_stride(RS),
        .record_frame_id(record_frame_id),.record_slot(record_slot),.commit_valid(commit_valid),.commit_ready(commit_ready),
        .commit_frame_id(commit_frame_id),.commit_slot(commit_slot),.release_valid(release_valid),.release_ready(release_ready),
        .release_frame_id(release_frame_id),.release_slot(release_slot),.pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_de(pixel_de),
        .pixel_hs(pixel_hs),.pixel_vs(pixel_vs),.pixel_frame_start(pixel_frame_start),.out_rgb(out_rgb),.out_de(out_de),.out_hs(out_hs),.out_vs(out_vs),
        .error(display_error),.error_code(display_code),.commits(commits),.completed_scans(scans),.read_lines(lines),.underflows(underflows),.frame_id(display_frame),
        .m_axi_arid(d_arid),.m_axi_araddr(d_araddr),.m_axi_arlen(d_arlen),.m_axi_arsize(d_arsize),.m_axi_arburst(d_arburst),
        .m_axi_arvalid(d_arvalid),.m_axi_arready(d_arready),.m_axi_rid(d_rid),.m_axi_rdata(d_rdata),.m_axi_rresp(d_rresp),
        .m_axi_rlast(d_rlast),.m_axi_rvalid(d_rvalid),.m_axi_rready(d_rready));
    wire [27:0] h_awaddr,h_araddr;wire [3:0] h_awlen,h_arlen,h_awid,h_arid,h_wid,h_rid;
    wire h_awvalid,h_arvalid,h_awready,h_arready,h_wready,h_rvalid,h_wlast,h_rlast;
    wire [255:0] h_wdata,h_rdata;wire [31:0] h_wstrb;wire shared_fault,shared_busy,shared_drained;wire [7:0] shared_code;
    wire [31:0] read_grants,write_grants;integer aw_commands,ar_commands,write_bytes,read_beats;
    video_shared_ddr #(.MAX_READ_BURSTS(QUOTA),.NATIVE_TIMEOUT_CYCLES(1000000)) memory_port(
        .clk(clk_i),.reset_n(rst_ni),.online(init_done),.display_urgent(1'b1),
        .c_awid(awid),.c_awaddr(awaddr),.c_awlen(awlen),.c_awsize(awsize),.c_awburst(awburst),.c_awvalid(awvalid),.c_awready(awready),
        .c_wdata(wdata),.c_wstrb(wstrb),.c_wlast(wlast),.c_wvalid(wvalid),.c_wready(wready),.c_bid(bid),.c_bresp(bresp),.c_bvalid(bvalid),.c_bready(bready),
        .d_arid(d_arid),.d_araddr(d_araddr),.d_arlen(d_arlen),.d_arsize(d_arsize),.d_arburst(d_arburst),.d_arvalid(d_arvalid),.d_arready(d_arready),
        .d_rid(d_rid),.d_rdata(d_rdata),.d_rresp(d_rresp),.d_rlast(d_rlast),.d_rvalid(d_rvalid),.d_rready(d_rready),
        .h_awaddr(h_awaddr),.h_araddr(h_araddr),.h_awlen(h_awlen),.h_arlen(h_arlen),.h_awid(h_awid),.h_arid(h_arid),
        .h_awvalid(h_awvalid),.h_arvalid(h_arvalid),.h_awready(h_awready),.h_arready(h_arready),.h_wready(h_wready),.h_rvalid(h_rvalid),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_rdata(h_rdata),.h_wid(h_wid),.h_rid(h_rid),.h_wlast(h_wlast),.h_rlast(h_rlast),
        .fault(shared_fault),.fault_code(shared_code),.busy(shared_busy),.port_drained(shared_drained),.read_grants(read_grants),.write_grants(write_grants));
    video_shared_memory_model #(.W(W),.H(H),.PT(PT),.PB(PB),.GAPS(GAPS)) native_mem(
        .clk(clk_i),.reset_n(rst_ni),.h_awaddr(h_awaddr),.h_araddr(h_araddr),.h_awlen(h_awlen),.h_arlen(h_arlen),.h_awid(h_awid),.h_arid(h_arid),
        .h_awvalid(h_awvalid),.h_arvalid(h_arvalid),.h_awready(h_awready),.h_arready(h_arready),.h_wready(h_wready),.h_rvalid(h_rvalid),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_rdata(h_rdata),.h_wid(h_wid),.h_rid(h_rid),.h_wlast(h_wlast),.h_rlast(h_rlast),
        .aw_commands(aw_commands),.ar_commands(ar_commands),.write_bytes(write_bytes),.read_beats(read_beats));
    reg [2:0] leased=0;integer slot_frame[0:2];integer seen_commits=0,seen_releases=0,overlap_ticks=0,contested=0;
    integer raster_count=0,checked_pixels=0,checked_by_frame[0:31];
    always @(posedge clk_i)if(rst_ni)begin
        if(old_arm!=arm_toggle)begin enabled<=1;sent<=0;end old_arm<=arm_toggle;
        if(m_valid&&m_ready)sent<=sent+1;
        if(shared_fault||capture_live_fault_i||display_error||record_reject_valid)
            $fatal(1,"SHARED_INTEGRATION_FAULT shared=%h capture=%h display=%h",shared_code,capture_live_code_i,display_code);
        if(awvalid&&d_arvalid)contested=contested+1;
        if(busy&&display_frame!=0)overlap_ticks=overlap_ticks+1;
        if(awvalid&&awready&&leased[capture_slot_i])$fatal(1,"SHARED_CAPTURE_OVERWROTE_LEASE");
        if(record_valid&&record_ready)begin
            if(leased[record_slot])$fatal(1,"SHARED_RECORD_REUSED_LEASE");
            leased[record_slot]=1;slot_frame[record_slot]=record_frame_id;
        end
        if(commit_valid&&commit_ready)begin
            if(!leased[commit_slot]||slot_frame[commit_slot]!=commit_frame_id)$fatal(1,"SHARED_COMMIT_IDENTITY");
            seen_commits=seen_commits+1;
        end
        if(release_valid&&release_ready)begin
            if(!leased[release_slot]||slot_frame[release_slot]!=release_frame_id)$fatal(1,"SHARED_RELEASE_IDENTITY");
            leased[release_slot]=0;seen_releases=seen_releases+1;
        end
        if(d_arvalid&&d_arready)begin
            j=int'((d_araddr-32'h82000000)/32'h200000);
            if(j<0||j>2||!leased[j]||d_araddr>=32'h82000000+j*32'h200000+RB)$fatal(1,"SHARED_READ_AFTER_RELEASE");
        end
    end
    always @(posedge pixel_clk)begin
        if(!rst_ni)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==HT-1)begin pixel_x<=0;if(pixel_y==VT-1)pixel_y<=0;else pixel_y<=pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
    reg [10:0] x0=0,x1=0,y0=0,y1=0;reg de0=0,de1=0,hs0=0,hs1=0,vs0=0,vs1=0,valid0=0,valid1=0;
    reg [23:0] raster[0:N-1],wanted;integer row,col,warmup=0;reg raster_armed=0;
    always @(posedge pixel_clk)if(rst_ni)begin
        x0<=pixel_x;y0<=pixel_y;x1<=x0;y1<=y0;de0<=pixel_de;de1<=de0;hs0<=pixel_hs;hs1<=hs0;vs0<=pixel_vs;vs1<=vs0;
        valid0<=1;valid1<=valid0;warmup=warmup+1;#1;
        if(valid1&&warmup>4)begin
            if(x1==0&&y1==0)raster_armed=1;
            if({out_de,out_hs,out_vs}!=={de1,hs1,vs1})$fatal(1,"SHARED_PIXEL_ALIGNMENT");
            if(de1)raster[y1*W+x1]=out_rgb;
            else if(out_rgb!==24'h101820)$fatal(1,"SHARED_BLANKING");
            if(raster_armed&&x1==HT-1&&y1==VT-1)begin
                for(row=0;row<H;row=row+1)for(col=0;col<W;col=col+1)begin
                    wanted=display_frame==0?24'h101820:{source_value(col,row,0,int'(display_frame)-1),source_value(col,row,1,int'(display_frame)-1),source_value(col,row,2,int'(display_frame)-1)};
                    if(raster[row*W+col]!==wanted)$fatal(1,"SHARED_PIXEL_ORACLE frame=%0d x=%0d y=%0d got=%h expected=%h",display_frame,col,row,raster[row*W+col],wanted);
                end
                if(display_frame!=0)begin checked_pixels=checked_pixels+N;raster_count=raster_count+1;checked_by_frame[display_frame]=checked_by_frame[display_frame]+1;end
            end
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
    task automatic request(input integer which,input [31:0] frame);
        begin
            case(which)
                0:begin expected_raw_base=32'h82000000;expected_input_base=32'h82800000;end
                1:begin expected_raw_base=32'h82200000;expected_input_base=32'h82850000;end
                2:begin expected_raw_base=32'h82400000;expected_input_base=32'h828a0000;end
            endcase
            write_word(32'h20012008,1,0);write_word(32'h20012010,7,0);
            write_word(32'h20012100,32'(which),0);write_word(32'h20012104,frame,0);write_word(32'h20012134,frame^32'h5678,0);write_word(32'h20012020,1,0);
        end
    endtask
    task automatic wait_complete;
        reg [31:0] status;integer cycles;
        begin
            status=0;cycles=0;
            while(!status[5]&&cycles<300000)begin read_word(32'h2001200c,status);cycles=cycles+1;end
            if(!status[5])$fatal(1,"completion timeout status%h",status);
            if(!capture_port_drained_i||bvalid)$fatal(1,"mailbox precedes B drain");
        end
    endtask
    integer b,limit,case_id=0;reg [31:0] address,status;
    integer progress_ticks=0;
    always @(posedge clk_i)if(rst_ni)begin
        progress_ticks=progress_ticks+1;
        if(progress_ticks%100000==0)begin
            $display("SHARED_PROGRESS job=%0d sent=%0d capture=%0d scans=%0d frame=%0d commits=%0d releases=%0d pixels=%0d sched=%0d bridge=%0d grants=%0d/%0d pixelstate=%0d rvalid=%b ready=%b leased=%b checked=%0d",test_id,sent,u_capture.state,scans,display_frame,seen_commits,seen_releases,checked_pixels,memory_port.u_scheduler.state,memory_port.u_bridge.state,read_grants,write_grants,scanout.pixel_state,release_valid,release_ready,leased,checked_by_frame[test_id+1]);$fflush();
        end
    end
    initial begin
        if($value$plusargs("CASE=%d",case_id))begin end
        for(i=0;i<32;i=i+1)checked_by_frame[i]=0;
        for(i=0;i<3;i=i+1)slot_frame[i]=0;
        repeat(8)@(negedge clk_i);rst_ni=1;init_done=1;
        for(test_id=0;test_id<JOBS;test_id=test_id+1)begin
            if(leased[test_id%3])$fatal(1,"SHARED_CPU_REUSED_BEFORE_RELEASE");
            expected_crc=oracle_crc(1);expected_preview_crc=oracle_crc(2);
            request(test_id%3,32'(test_id+1));wait_complete;
            expect_read(32'h2001218c,1);expect_read(32'h200121b4,expected_crc);expect_read(32'h200121b8,expected_preview_crc);
            for(b=1;b<=3;b=b+1)begin
                limit=b==1?RB:b==2?VB:IB;
                for(offset=0;offset<limit;offset=offset+1)begin
                    address=(b==1?expected_raw_base:b==2?expected_raw_base+32'h160000:expected_input_base)+offset;
                    if(b==1?offset%RS<W*3:b==2?offset%PS<PW*3:offset%IS<IW)begin
                        if(native_mem.peek(address)!==expected(b,offset))$fatal(1,"SHARED_FINAL_MEMORY branch=%0d offset=%0d",b,offset);
                        verified_bytes=verified_bytes+1;
                    end else if(native_mem.peek(address)!==8'ha5)$fatal(1,"SHARED_STRIDE_GUARD");
                end
            end
            write_word(32'h20012014,3,0);wait(capture_req_ready_i);write_word(32'h20012030,1,0);
            if(case_id==1&&test_id>0)release_ready=0;
            @(negedge clk_i);record_base=expected_raw_base;record_frame_id=32'(test_id+1);record_slot=2'(test_id%3);record_valid=1;
            do @(posedge clk_i);while(!record_ready);
            @(negedge clk_i);record_valid=0;
            wait(seen_commits==test_id+1);
            if(case_id==1&&test_id>0)begin
                wait(release_valid);repeat(71)@(negedge clk_i);
                if(!leased[release_slot])$fatal(1,"SHARED_RETIRE_ACK_SKIPPED");release_ready=1;
            end
            wait(checked_by_frame[test_id+1]>=1);
            if(test_id>0)wait(seen_releases==test_id);
            tests=tests+1;
        end
        // Small geometries may interleave without simultaneous AXI requests.
        // The suite requires contention across the complete geometry matrix.
        if(overlap_ticks==0||underflows!=0||seen_commits!=JOBS||seen_releases!=JOBS-1||read_grants==0||write_grants==0)
            $fatal(1,"SHARED_OVERLAP_COVERAGE");
        $display("VIDEO_SHARED_MEMORY_PASS jobs=%0d bytes=%0d pixels=%0d rasters=%0d overlap=%0d contested=%0d read_grants=%0d write_grants=%0d releases=%0d underflows=%0d",tests,verified_bytes,checked_pixels,raster_count,overlap_ticks,contested,read_grants,write_grants,seen_releases,underflows);$finish;
    end
    initial begin #1000000000;$fatal(1,"SHARED_MEMORY_WATCHDOG job=%0d commits=%0d releases=%0d",test_id,seen_commits,seen_releases);end
endmodule
`default_nettype wire
