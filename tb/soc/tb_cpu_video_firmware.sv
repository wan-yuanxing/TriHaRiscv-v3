`timescale 1ns/1ps
`default_nettype none
// Simulation-only ROM/SRAM and byte-addressed DMA memory. The CPU, adapter,
// MMIO, capture branches, DMAs and arbiter are the actual frozen/production RTL.
module tb_cpu_video_firmware #(
    parameter integer DUAL_ISSUE=0, TEST_CASE=0, BAD_DATA=0, NO_CONTROL=0,
    parameter integer W=30,H=20,PT=2,PB=1
);
    localparam integer N=W*H,PW=W/2,PH=H/2,IW=W*2/5,AH=H*2/5,IH=PT+AH+PB;
    localparam integer RS=(W*3+15)/16*16,PS=(PW*3+15)/16*16,IS=(IW+15)/16*16,IP=IS*IH;
    localparam integer RB=RS*H,VB=PS*PH,IB=3*IP,IBYTES=3*IW*IH;
    reg clk_i=0,rst_ni=0,init_done=0,source_fault=0,overflow=0;
    always #4 clk_i=~clk_i;
    integer cycles=0;
    wire [31:0] s_axi_awaddr_i,s_axi_wdata_i,s_axi_araddr_i;
    wire [2:0] s_axi_awprot_i,s_axi_arprot_i;
    wire [3:0] s_axi_wstrb_i;
    wire s_axi_awvalid_i,s_axi_wvalid_i,s_axi_bready_i,s_axi_arvalid_i,s_axi_rready_i;
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
    reg enabled=0,pause_eof=1;
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
    reg active=0,pending_b=0,hold_b=0,hold_final=1,held_final=0,fail_next_b=0;
    reg [31:0] address=0,expected_raw_base=32'h82000000,expected_input_base=32'h82800000;
    integer beats=0,index=0,owner_id=0,delay_b=0,burst_bytes=0;
    integer bytes_by_branch[1:3],ack_by_branch[1:3];
    integer i,j,k,relative,new_bytes,tests=0,checked_bytes=0;
    reg old_arm=0,held_aw=0,held_w=0,held_b=0;
    reg [48:0] aw_saved;
    reg [144:0] w_saved;
    reg [5:0] b_saved;
    assign awready=rst_ni&&!active&&!pending_b&&!bvalid&&(cycles%5!=0);
    assign wready=rst_ni&&active&&(cycles%4!=0);
    always @(posedge clk_i)begin
        if(!rst_ni)begin
            sent<=0;active<=0;pending_b<=0;bvalid<=0;held_final<=0;old_arm<=0;
            held_aw<=0;held_w<=0;held_b<=0;enabled<=0;
            for(j=1;j<=3;j=j+1)begin bytes_by_branch[j]<=0;ack_by_branch[j]<=0;end
        end else begin
            if(old_arm!=arm_toggle)begin enabled<=TEST_CASE!=2; if(TEST_CASE==2)source_fault<=1; end old_arm<=arm_toggle;
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
                        1:begin if(raw_hit[i])$fatal(1,"duplicate raw");raw_hit[i]=1;raw_mem[i+16]=wdata[k*8+:8]^((BAD_DATA!=0&&i==0)?8'h01:8'h00);end
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
    reg [7:0] rom[0:8191],sram[0:32767];
    string image_path,signature_path;
    integer fd,image_size,lane,native_requests=0,native_responses=0,native_errors=0;
    integer axi_reads=0,axi_writes=0,axi_write_data=0,axi_read_errors=0,axi_write_errors=0;
    integer accepted_events=0,completion_events=0,retired=0,ifetch_stalls=0,data_stalls=0;
    integer eof_wait=0,final_wait=0,irq_rises=0,irq_falls=0;
    reg bus_pending=0,local_pending=0,local_ack=0,local_error=0;
    reg [31:0] local_data=0,saved_local_data=0;
    reg [10:0] local_tag=0,saved_local_tag=0,expected_native_tag=0;
    integer local_delay=0,fetch_delay=0;
    reg fetch_pending=0,fetch_valid=0;
    reg [63:0] fetch_data=0,saved_fetch_data=0;
    wire [31:0] d_addr,d_wdata,i_pc;
    wire [10:0] request_tag;
    wire d_rd,i_rd,d_cacheable,d_invalidate,d_writeback,d_flush;
    wire [3:0] d_wr;
    wire memory_select=d_addr<8192||(d_addr>=32'h10000&&d_addr<32'h18000);
    wire native_request_enable=!bus_pending&&!memory_select&&(NO_CONTROL==0);
    wire native_accept,native_ack,native_error;
    wire [31:0] native_rdata;
    wire [10:0] native_tag;
    wire d_accept=rst_ni&&!bus_pending&&(memory_select?(cycles%4!=0):native_accept);
    wire d_ack=local_ack||native_ack;
    wire d_error=local_ack?local_error:native_error;
    wire [31:0] d_data=local_ack?local_data:native_rdata;
    wire [10:0] d_tag=local_ack?local_tag:native_tag;
    wire i_accept=rst_ni&&!fetch_pending&&(cycles%3!=0);
    cpu_native_axil u_adapter(
        .clk_i(clk_i),.rst_ni(rst_ni),.cpu_addr_i(d_addr),.cpu_wdata_i(d_wdata),
        .cpu_re_i(d_rd&&native_request_enable),.cpu_wstrb_i(d_wr&{4{native_request_enable}}),
        .cpu_cacheable_i(d_cacheable),.cpu_req_tag_i(request_tag),
        .cpu_invalidate_i(d_invalidate&&native_request_enable),
        .cpu_writeback_i(d_writeback&&native_request_enable),.cpu_flush_i(d_flush&&native_request_enable),
        .cpu_rdata_o(native_rdata),.cpu_accept_o(native_accept),.cpu_ack_o(native_ack),
        .cpu_error_o(native_error),.cpu_resp_tag_o(native_tag),
        .m_axi_awaddr_o(s_axi_awaddr_i),.m_axi_awprot_o(s_axi_awprot_i),
        .m_axi_awvalid_o(s_axi_awvalid_i),.m_axi_awready_i(s_axi_awready_o),
        .m_axi_wdata_o(s_axi_wdata_i),.m_axi_wstrb_o(s_axi_wstrb_i),
        .m_axi_wvalid_o(s_axi_wvalid_i),.m_axi_wready_i(s_axi_wready_o),
        .m_axi_bresp_i(s_axi_bresp_o),.m_axi_bvalid_i(s_axi_bvalid_o),.m_axi_bready_o(s_axi_bready_i),
        .m_axi_araddr_o(s_axi_araddr_i),.m_axi_arprot_o(s_axi_arprot_i),
        .m_axi_arvalid_o(s_axi_arvalid_i),.m_axi_arready_i(s_axi_arready_o),
        .m_axi_rdata_i(s_axi_rdata_o),.m_axi_rresp_i(s_axi_rresp_o),
        .m_axi_rvalid_i(s_axi_rvalid_o),.m_axi_rready_o(s_axi_rready_i));
    triha_cpu #(.SUPPORT_DUAL_ISSUE(DUAL_ISSUE),.SUPPORT_BRANCH_PREDICTION(1),
        .SUPPORT_MULDIV(0),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),
        .SUPPORT_REGFILE_XILINX(0),.SUPPORT_LOAD_BYPASS(1),.SUPPORT_MUL_BYPASS(1)) u_cpu(
        .clk_i(clk_i),.rst_i(!rst_ni),.intr_i(irq_o),.reset_vector_i(32'd0),.cpu_id_i(32'd0),
        .mem_i_accept_i(i_accept),.mem_i_valid_i(fetch_valid),.mem_i_error_i(1'b0),.mem_i_inst_i(fetch_data),
        .mem_i_rd_o(i_rd),.mem_i_pc_o(i_pc),.mem_i_flush_o(),.mem_i_invalidate_o(),
        .mem_d_accept_i(d_accept),.mem_d_ack_i(d_ack),.mem_d_error_i(d_error),
        .mem_d_data_rd_i(d_data),.mem_d_resp_tag_i(d_tag),.mem_d_addr_o(d_addr),
        .mem_d_data_wr_o(d_wdata),.mem_d_rd_o(d_rd),.mem_d_wr_o(d_wr),
        .mem_d_req_tag_o(request_tag),.mem_d_cacheable_o(d_cacheable),
        .mem_d_invalidate_o(d_invalidate),.mem_d_writeback_o(d_writeback),.mem_d_flush_o(d_flush));
    reg [31:0] held_native_addr;
    reg expected_native_error=0,previous_irq=0,w1c_seen=0;
    reg [31:0] last_aw=0;
    function automatic retired_exception(input [5:0] exception_code);
        case(exception_code)
            6'h00,6'h30,6'h31,6'h33,6'h34:retired_exception=1;
            default:retired_exception=0;
        endcase
    endfunction
    always @(posedge clk_i) if(rst_ni)begin
        cycles<=cycles+1;
        local_ack<=0;fetch_valid<=0;
        if(i_rd&&!i_accept)ifetch_stalls<=ifetch_stalls+1;
        if((d_rd||(|d_wr))&&!d_accept)data_stalls<=data_stalls+1;
        if(i_rd&&i_accept)begin
            if(i_pc>=8192||i_pc[2:0]!=0)$fatal(1,"CPU_VIDEO_FAIL fetch address %h",i_pc);
            fetch_pending<=1;fetch_delay<=cycles%3;
            for(lane=0;lane<8;lane=lane+1)saved_fetch_data[lane*8+:8]<=rom[i_pc+lane];
        end else if(fetch_pending)begin
            if(fetch_delay==0)begin fetch_pending<=0;fetch_valid<=1;fetch_data<=saved_fetch_data;end
            else fetch_delay<=fetch_delay-1;
        end
        if((d_rd||(|d_wr))&&d_accept)begin
            if(bus_pending)$fatal(1,"CPU_VIDEO_FAIL duplicate acceptance");
            bus_pending<=1;
            if(memory_select)begin
                local_pending<=1;local_delay<=cycles%4;saved_local_tag<=request_tag;
                if(d_addr[1:0]!=0||d_cacheable||d_invalidate||d_writeback||d_flush)$fatal(1,"CPU_VIDEO_FAIL memory controls");
                for(lane=0;lane<4;lane=lane+1)begin
                    saved_local_data[lane*8+:8]<=d_addr<8192?rom[d_addr+lane]:sram[d_addr-32'h10000+lane];
                    if(d_wr[lane])begin
                        if(d_addr<32'h10000)$fatal(1,"CPU_VIDEO_FAIL ROM write");
                        sram[d_addr-32'h10000+lane]<=d_wdata[lane*8+:8];
                    end
                end
            end else begin
                native_requests<=native_requests+1;expected_native_tag<=request_tag;
                held_native_addr<=d_addr;
                expected_native_error<=d_addr==32'h200103fc||(d_addr==32'h20010000&&|d_wr);
                $display("NATIVE_ACCEPT addr=%h re=%b strb=%h tag=%h",d_addr,d_rd,d_wr,request_tag);
            end
        end else if(local_pending)begin
            if(local_delay==0)begin local_pending<=0;local_ack<=1;local_data<=saved_local_data;local_tag<=saved_local_tag;end
            else local_delay<=local_delay-1;
        end
        if(d_ack)begin
            if(!bus_pending)$fatal(1,"CPU_VIDEO_FAIL unsolicited data ACK");
            bus_pending<=0;
        end
        if(native_ack)begin
            if(native_tag!==expected_native_tag||native_error!==expected_native_error)$fatal(1,"CPU_VIDEO_FAIL native tag/error addr%h",held_native_addr);
            native_responses<=native_responses+1;
            if(native_error)begin
                native_errors<=native_errors+1;
                if(native_rdata!==0)$fatal(1,"CPU_VIDEO_FAIL error data");
            end
            $display("NATIVE_ACK tag=%h error=%b data=%h",native_tag,native_error,native_rdata);
        end
        if(u_cpu.csr_writeback_write_w&&u_cpu.csr_writeback_waddr_w==12'h344)
            $display("MIP_WRITE value=%h old=%h buffered=%h irq=%b",u_cpu.csr_writeback_wdata_w,
                u_cpu.u_csr.u_csrfile.csr_mip_q,u_cpu.u_csr.u_csrfile.csr_mip_next_q,irq_o);
        if(u_cpu.csr_writeback_exception_w!=0)
            $display("CPU_TRAP event=%h pc=%h value=%h mip=%h",u_cpu.csr_writeback_exception_w,
                u_cpu.csr_writeback_exception_pc_w,u_cpu.csr_writeback_exception_addr_w,u_cpu.u_csr.u_csrfile.csr_mip_q);
        if(s_axi_arvalid_i&&s_axi_arready_o)axi_reads<=axi_reads+1;
        if(s_axi_awvalid_i&&s_axi_awready_o)begin axi_writes<=axi_writes+1;last_aw<=s_axi_awaddr_i;end
        if(s_axi_wvalid_i&&s_axi_wready_o)begin
            axi_write_data<=axi_write_data+1;
            if((s_axi_awvalid_i?s_axi_awaddr_i:last_aw)==32'h20010014&&s_axi_wdata_i!=0)w1c_seen<=1;
        end
        if(s_axi_rvalid_o&&s_axi_rready_i&&s_axi_rresp_o!=0)axi_read_errors<=axi_read_errors+1;
        if(s_axi_bvalid_o&&s_axi_bready_i&&s_axi_bresp_o!=0)axi_write_errors<=axi_write_errors+1;
        if(irq_o&&!previous_irq)begin irq_rises<=irq_rises+1;w1c_seen<=0;end
        if(!irq_o&&previous_irq)begin
            if(!w1c_seen)$fatal(1,"CPU_VIDEO_FAIL IRQ cleared without software W1C");
            irq_falls<=irq_falls+1;
        end
        previous_irq<=irq_o;
        if(accepted_valid_i&&accepted_ready_o)accepted_events<=accepted_events+1;
        if(completion_valid_i&&completion_ready_o)begin
            completion_events<=completion_events+1;
            if(TEST_CASE==2)begin
                if(completion_success_i||completion_code_i!=3||accepted_events!=0||active||pending_b||bvalid||!capture_port_drained_i)
                    $fatal(1,"CPU_VIDEO_FAIL preaccepted failure/drain");
                if(capture_raw_bytes_i!=ack_by_branch[1]||capture_preview_bytes_i!=ack_by_branch[2]||capture_input_bytes_i!=ack_by_branch[3])
                    $fatal(1,"CPU_VIDEO_FAIL failed B counters");
            end else if(!completion_success_i||completion_code_i!=0||capture_raw_crc_i!==expected_crc||capture_preview_crc_i!==expected_preview_crc||
                ack_by_branch[1]!=1800||ack_by_branch[2]!=450||ack_by_branch[3]!=396)
                $fatal(1,"CPU_VIDEO_FAIL success without all B");
        end
        if(TEST_CASE!=2&&sent==N&&pause_eof)begin
            eof_wait<=eof_wait+1;
            if(completion_valid_i||u_mmio.completion_pending)$fatal(1,"CPU_VIDEO_FAIL success before EOF");
            if(eof_wait==100)pause_eof<=0;
        end
        if(TEST_CASE!=2&&held_final&&hold_final&&!pause_eof)begin
            final_wait<=final_wait+1;
            if(completion_valid_i||u_mmio.completion_pending)$fatal(1,"CPU_VIDEO_FAIL success before final B");
            if(final_wait==160)hold_final<=0;
        end
        retired<=retired+int'(u_cpu.u_issue.pipe0_valid_wb_w&&retired_exception(u_cpu.u_issue.pipe0_exception_wb_w))+
            int'(u_cpu.u_issue.pipe1_valid_wb_w&&retired_exception(u_cpu.u_issue.pipe1_exception_wb_w));
    end
    function automatic [31:0] signature_word(input integer word_index);
        signature_word={sram[word_index*4+3],sram[word_index*4+2],sram[word_index*4+1],sram[word_index*4]};
    endfunction
    integer outfd,word_index;
    reg [31:0] outcome;
    initial begin
        expected_crc=oracle_crc(1);expected_preview_crc=oracle_crc(2);
        if(!$value$plusargs("ROM_IMAGE=%s",image_path)||!$value$plusargs("SIGNATURE=%s",signature_path))$fatal(1,"CPU_VIDEO_FAIL input arguments");
        for(i=0;i<8192;i=i+1)rom[i]=0;
        for(i=0;i<32768;i=i+1)sram[i]=0;
        for(i=0;i<RB+32;i=i+1)raw_mem[i]=8'ha5;
        for(i=0;i<VB+32;i=i+1)preview_mem[i]=8'ha5;
        for(i=0;i<IB+32;i=i+1)input_mem[i]=8'ha5;
        for(i=0;i<RB;i=i+1)raw_hit[i]=0;
        for(i=0;i<VB;i=i+1)preview_hit[i]=0;
        for(i=0;i<IB;i=i+1)input_hit[i]=0;
        fd=$fopen(image_path,"rb");if(!fd)$fatal(1,"CPU_VIDEO_FAIL ROM open");
        image_size=$fread(rom,fd);$fclose(fd);
        if(image_size!=8192)$fatal(1,"CPU_VIDEO_FAIL ROM size");
        repeat(8)@(negedge clk_i);rst_ni=1;init_done=1;
    end
    always @(negedge clk_i) if(rst_ni)begin
        outcome=signature_word(0);
        if(outcome[31:20]==12'hbad)$fatal(1,"CPU_VIDEO_FAIL firmware signature %h stage%h cause%h",outcome,signature_word(1),u_cpu.u_csr.u_csrfile.csr_mcause_q);
        if(cycles>(NO_CONTROL!=0?20000:2000000))$fatal(1,"CPU_VIDEO_FAIL timeout pc%h signature%h no_control=%0d",i_pc,outcome,NO_CONTROL);
        if(outcome==32'h43505556&&!bus_pending&&!d_ack)begin
            if(signature_word(1)!=3||signature_word(2)!=2||signature_word(4)!=5||signature_word(6)!=32'h200103fc||
                signature_word(7)!=7||signature_word(9)!=32'h20010000)$fatal(1,"CPU_VIDEO_FAIL trap SRAM evidence");
            if(native_requests!=native_responses||native_errors!=2||axi_read_errors!=1||axi_write_errors!=1||
                axi_writes!=axi_write_data||axi_reads+axi_writes!=native_requests||ifetch_stalls==0||data_stalls==0||retired<100)
                $fatal(1,"CPU_VIDEO_FAIL transaction/retirement coverage req%0d ack%0d err%0d",native_requests,native_responses,native_errors);
            if(irq_o||irq_rises==0||irq_falls==0||completion_events!=1||accepted_events!=(TEST_CASE==2?0:1))$fatal(1,"CPU_VIDEO_FAIL event/IRQ coverage");
            if(TEST_CASE!=2)begin
                verify_memory;
                if(eof_wait<100||final_wait<160||sent!=N+1)$fatal(1,"CPU_VIDEO_FAIL EOF/B guard coverage");
            end
            if(TEST_CASE==1&&(signature_word(10)!=32'h8000000b||signature_word(13)!=1||signature_word(14)!=1||u_cpu.u_csr.u_csrfile.csr_mip_q[11]))
                $fatal(1,"CPU_VIDEO_FAIL external IRQ/MIP evidence");
            outfd=$fopen(signature_path,"w");if(!outfd)$fatal(1,"CPU_VIDEO_FAIL signature output");
            for(word_index=0;word_index<16;word_index=word_index+1)$fdisplay(outfd,"%08h",signature_word(word_index));
            $fclose(outfd);
            $display("CPU_VIDEO_FIRMWARE_PASS dual=%0d case=%0d cycles=%0d retired=%0d native=%0d bytes=%0d irq_rises=%0d irq_falls=%0d eof_guard=%0d b_guard=%0d",DUAL_ISSUE,TEST_CASE,cycles,retired,native_responses,checked_bytes,irq_rises,irq_falls,eof_wait,final_wait);
            $finish;
        end
    end
endmodule
`default_nettype wire
