`timescale 1ns/1ps
`default_nettype none
// Real MMIO/owner/link/raw CDC; independent byte-address memory and raster oracle.
module tb_video_display_scanout #(parameter integer W=16,H=4,FULL=0,parameter real PIXEL_HALF=12.5);
    localparam integer HT=FULL?1056:W+128,VT=FULL?628:H+8;
    reg clk_i=0,rst_ni=0,pixel_clk=0,pixel_reset_n=0,ddr_ready=1;
    always #4 clk_i=~clk_i;initial begin #3;forever #(PIXEL_HALF)pixel_clk=~pixel_clk;end
    reg [31:0] s_axi_awaddr_i=0,s_axi_wdata_i=0,s_axi_araddr_i=0;
    reg [2:0] s_axi_awprot_i=0,s_axi_arprot_i=0;reg [3:0] s_axi_wstrb_i=15;
    reg s_axi_awvalid_i=0,s_axi_wvalid_i=0,s_axi_bready_i=1,s_axi_arvalid_i=0,s_axi_rready_i=1;
    wire s_axi_awready_o,s_axi_wready_o,s_axi_bvalid_o,s_axi_arready_o,s_axi_rvalid_o;
    wire [1:0] s_axi_bresp_o,s_axi_rresp_o;wire [31:0] s_axi_rdata_o;
    reg [10:0] pixel_x=0,pixel_y=0;
    wire pixel_de=pixel_x<W&&pixel_y<H,pixel_hs=pixel_x>=W+2&&pixel_x<W+4,pixel_vs=pixel_y>=H+1&&pixel_y<H+3;
    wire pixel_frame_start=pixel_x==0&&pixel_y==0;
    wire [23:0] out_rgb;wire out_de,out_hs,out_vs,fault,irq_o;wire [7:0] fault_code;
    wire [31:0] raw_commits,raw_scans,raw_lines,underflows,raw_frame;
    wire [3:0] m_axi_arid;wire [31:0] m_axi_araddr;wire [7:0] m_axi_arlen;wire [2:0] m_axi_arsize;wire [1:0] m_axi_arburst;
    wire m_axi_arvalid,m_axi_rready;reg m_axi_arready=0,m_axi_rvalid=0,m_axi_rlast=0;
    reg [3:0] m_axi_rid=0;reg [127:0] m_axi_rdata=0;reg [1:0] m_axi_rresp=0;
    video_display_scanout #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(1000000)) dut(.*);
    function automatic [7:0] memory_byte(input [31:0] addr);
        memory_byte=8'((addr*13)^(addr>>8)^(addr>>16)^(addr>>21));
    endfunction
    function automatic [23:0] expected_pixel(input [31:0] base,input integer x,y);
        reg [31:0] a;begin a=base+32'(y)*2400+32'(x)*3;expected_pixel={memory_byte(a),memory_byte(a+1),memory_byte(a+2)};end
    endfunction
    integer ticks=0,beats=0,bursts=0,left=0,lane,idx;
    reg active_read=0,hold_read=0,bad_id=0;reg [31:0] read_address=0;
    reg [2:0] raw_leased=0;reg [31:0] visible_base=0;
    integer records=0,feedbacks=0,retires=0,checked_pixels=0,rasters=0;
    always @(posedge clk_i)if(rst_ni)begin
        ticks=ticks+1;
        if(fault&&case_id!=2)$fatal(1,"SCANOUT_FAULT %h",fault_code);
        if(dut.record_valid&&dut.record_ready)begin
            if(raw_leased[dut.record_slot])$fatal(1,"SCANOUT_REUSED_RAW_LEASE");
            raw_leased[dut.record_slot]=1;records=records+1;
        end
        if(dut.raw_commit_valid)visible_base=32'h82000000+32'(dut.raw_commit_slot)*32'h200000;
        if(dut.feedback_valid_i&&dut.feedback_ready_o)begin
            if(raw_commits==0)$fatal(1,"SCANOUT_COMMIT_BEFORE_RAW");feedbacks=feedbacks+1;
        end
        if(dut.raw_release_valid&&dut.raw_release_ready)begin
            if(active_read&&((read_address-32'h82000000)/32'h200000)==dut.raw_release_slot)$fatal(1,"SCANOUT_RELEASE_WITH_DMA");
            if(!raw_leased[dut.raw_release_slot])$fatal(1,"SCANOUT_RELEASE_UNOWNED");
            raw_leased[dut.raw_release_slot]=0;
        end
        if(dut.retire_valid_i&&dut.retire_ready_o)retires=retires+1;
    end
    always @(posedge clk_i)begin
        if(!rst_ni)begin m_axi_arready<=0;m_axi_rvalid<=0;active_read<=0;left<=0;end
        else begin
            m_axi_arready<=!active_read&&!hold_read&&ticks%7!=2;
            if(m_axi_arvalid&&m_axi_arready)begin
                idx=int'((m_axi_araddr-32'h82000000)/32'h200000);
                if(active_read||idx<0||idx>2||!raw_leased[idx])$fatal(1,"SCANOUT_AR_OWNERSHIP");
                if(m_axi_arid!=0||m_axi_arsize!=4||m_axi_arburst!=1||m_axi_araddr[3:0]!=0||m_axi_arlen>15||
                    int'(m_axi_araddr[11:0])+(int'(m_axi_arlen)+1)*16>4096||
                    (m_axi_araddr-(32'h82000000+32'(idx)*32'h200000))>=H*2400)$fatal(1,"SCANOUT_AR_DESCRIPTOR");
                read_address<=m_axi_araddr;left<=int'(m_axi_arlen)+1;active_read<=1;m_axi_arready<=0;bursts=bursts+1;
            end
            if(m_axi_rvalid&&m_axi_rready)begin
                m_axi_rvalid<=0;read_address<=read_address+16;left<=left-1;beats=beats+1;
                if(left==1)active_read<=0;
            end
            if(active_read&&!m_axi_rvalid&&!hold_read&&ticks%5!=1)begin
                m_axi_rvalid<=1;m_axi_rid<=bad_id?3:0;m_axi_rresp<=0;m_axi_rlast<=left==1;
                for(lane=0;lane<16;lane=lane+1)m_axi_rdata[lane*8+:8]<=memory_byte(read_address+lane);
            end
        end
    end
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==HT-1)begin pixel_x<=0;if(pixel_y==VT-1)pixel_y<=0;else pixel_y<=pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
    reg [10:0] x0=0,x1=0,y0=0,y1=0;reg de0=0,de1=0,hs0=0,hs1=0,vs0=0,vs1=0,armed=0;
    reg [23:0] raster[0:W*H-1],wanted;integer warmup=0,x,y;
    always @(posedge pixel_clk)if(pixel_reset_n)begin
        x0<=pixel_x;x1<=x0;y0<=pixel_y;y1<=y0;de0<=pixel_de;de1<=de0;hs0<=pixel_hs;hs1<=hs0;vs0<=pixel_vs;vs1<=vs0;warmup=warmup+1;#1;
        if(warmup>4&&case_id!=2)begin
            if(x1==0&&y1==0)armed=1;
            if({out_de,out_hs,out_vs}!=={de1,hs1,vs1})$fatal(1,"SCANOUT_PIXEL_ALIGNMENT");
            if(de1)raster[y1*W+x1]=out_rgb;else if(out_rgb!==24'h101820)$fatal(1,"SCANOUT_BLANKING");
            if(armed&&x1==HT-1&&y1==VT-1)begin
                for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
                    wanted=visible_base==0?24'h101820:expected_pixel(visible_base,x,y);
                    if(raster[y*W+x]!==wanted)$fatal(1,"SCANOUT_PIXEL_ORACLE x=%0d y=%0d got=%h expected=%h",x,y,raster[y*W+x],wanted);
                end
                if(visible_base!=0)begin checked_pixels=checked_pixels+W*H;rasters=rasters+1;end
            end
        end
    end
    reg [31:0] rd;integer checks=0;
    task automatic read_word(input [31:0] off);
        begin
            @(negedge clk_i);s_axi_araddr_i=32'h20011000+off;s_axi_arvalid_i=1;
            do @(posedge clk_i);while(!s_axi_arready_o);
            @(negedge clk_i);s_axi_arvalid_i=0;while(!s_axi_rvalid_o)@(negedge clk_i);
            if(s_axi_rresp_o!=0)$fatal(1,"SCANOUT_MMIO_READ");rd=s_axi_rdata_o;checks=checks+1;@(negedge clk_i);
        end
    endtask
    task automatic expect_word(input [31:0] off,value);
        begin read_word(off);if(rd!==value)$fatal(1,"SCANOUT_READ off=%h got=%h expected=%h",off,rd,value);end
    endtask
    task automatic write_word(input [31:0] off,value,input [1:0] response);
        begin
            @(negedge clk_i);s_axi_awaddr_i=32'h20011000+off;s_axi_wdata_i=value;s_axi_awvalid_i=1;s_axi_wvalid_i=1;
            do @(posedge clk_i);while(!(s_axi_awready_o&&s_axi_wready_o));
            @(negedge clk_i);s_axi_awvalid_i=0;s_axi_wvalid_i=0;
            while(!s_axi_bvalid_o)@(negedge clk_i);
            if(s_axi_bresp_o!==response)$fatal(1,"SCANOUT_MMIO_WRITE off=%h got=%h wanted=%h",off,s_axi_bresp_o,response);
            checks=checks+1;@(negedge clk_i);
        end
    endtask
    reg [31:0] record[0:159];integer j;
    task automatic load_record(input integer slot,frame,generation);
        begin
            for(j=0;j<160;j=j+1)record[j]=0;
            record[0]=32'h10000;record[1]=640;record[2]=32'(slot);record[3]=32'(frame);record[4]=32'(generation);
            record[5]=32'h82000000+32'(slot)*32'h200000;record[6]=2400;record[7]=800;record[8]=600;
            record[9]=3;record[10]=32'(frame);record[11]=32'(generation);
            for(j=0;j<160;j=j+1)write_word(32'h100+32'(j)*4,record[j],0);
        end
    endtask
    task automatic submit(input integer mode,seq,input bit only);
        begin write_word('h24,32'(mode),0);write_word('h28,32'(seq),0);write_word('h20,only?3:1,0);end
    endtask
    task automatic wait_events(input [31:0] mask);
        integer loops;begin
            loops=0;rd=0;
            while((rd&mask)!=mask&&loops<1000000)begin read_word('h14);loops=loops+1;end
            if((rd&mask)!=mask)$fatal(1,"SCANOUT_EVENT_TIMEOUT wanted=%h got=%h",mask,rd);
            repeat(12)@(negedge clk_i);
        end
    endtask
    task automatic commit_identity(input integer slot,frame,generation,seq,only);
        begin expect_word('h44,32'(frame));expect_word('h48,32'(generation));expect_word('h4c,32'(slot));expect_word('h50,0);expect_word('h54,32'(seq));expect_word('h58,32'(only));end
    endtask
    task automatic release_identity(input integer slot,frame,generation);
        begin expect_word('h5c,32'(frame));expect_word('h60,32'(generation));expect_word('h64,32'(slot));end
    endtask
    string trace_path;reg [127:0] kind;integer trace_file,rc,wait_mask,trace_reads=0,trace_writes=0,trace_fences=0,trace_waits=0,ended=0;
    reg [31:0] off,value;integer case_id=0,old_records,old_commits,start_rasters;
    initial begin
        if($value$plusargs("CASE=%d",case_id))begin end
        repeat(8)@(negedge clk_i);rst_ni=1;pixel_reset_n=1;
        if($value$plusargs("TRACE=%s",trace_path))begin
            trace_file=$fopen(trace_path,"r");if(!trace_file)$fatal(1,"SCANOUT_TRACE_OPEN");
            while(!$feof(trace_file))begin
                rc=$fscanf(trace_file,"%s",kind);
                if(rc==1)case(kind)
                    "W":begin rc=$fscanf(trace_file,"%h %h",off,value);if(rc!=2)$fatal(1,"TRACE_FORMAT");write_word(off,value,0);trace_writes=trace_writes+1;end
                    "R":begin rc=$fscanf(trace_file,"%h %h",off,value);if(rc!=2)$fatal(1,"TRACE_FORMAT");expect_word(off,value);trace_reads=trace_reads+1;end
                    "F":begin @(negedge clk_i);trace_fences=trace_fences+1;end
                    "A":begin rc=$fscanf(trace_file,"%d",wait_mask);if(rc!=1)$fatal(1,"TRACE_FORMAT");wait_events(32'(wait_mask));trace_waits=trace_waits+1;end
                    "END":begin ended=ended+1;end
                    default:$fatal(1,"TRACE_UNKNOWN_TOKEN %s",kind);
                endcase
            end
            $fclose(trace_file);
            if(ended!=1||records!=6||feedbacks!=8||retires!=5)$fatal(1,"SCANOUT_TRACE_COVERAGE records=%0d feedbacks=%0d retires=%0d",records,feedbacks,retires);
        end else begin
            expect_word('h80,1);load_record(0,1,7);hold_read=1;submit(0,3,0);
            repeat(100)@(negedge clk_i);expect_word('h14,0);hold_read=0;
            wait_events(1);commit_identity(0,1,7,3,0);
            if(FULL)begin
                wait(rasters>=1);write_word('h18,1,0);
                load_record(1,2,7);submit(0,4,0);wait_events(3);
                commit_identity(1,2,7,4,0);release_identity(0,1,7);write_word('h18,3,0);
                wait(rasters>=3);
                if(records!=2||feedbacks!=2||retires!=1||underflows!=0)$fatal(1,"SCANOUT_FULL_COVERAGE");
            end else if(case_id==2)begin
                write_word('h18,1,0);bad_id=1;wait(fault);repeat(100)@(negedge clk_i);
                expect_word('h14,0);expect_word('h1c,6);
            end else begin
                start_rasters=rasters;wait(rasters>=start_rasters+2);commit_identity(0,1,7,3,0);write_word('h18,1,0);
                old_records=records;old_commits=int'(raw_commits);load_record(0,1,7);submit(0,99,1);
                wait_events(1);commit_identity(0,1,7,99,1);
                if(records!=old_records||raw_commits!=old_commits||retires!=0)$fatal(1,"SCANOUT_MODE_RECAPTURED");write_word('h18,1,0);
                load_record(1,2,7);submit(0,4,0);wait_events(3);commit_identity(1,2,7,4,0);release_identity(0,1,7);
                expect_word('h1c,4);write_word('h18,1,0);expect_word('h14,2);expect_word('h1c,4);
                // Third slot can commit while the first release waits for software ACK.
                load_record(2,3,7);submit(0,5,0);wait_events(3);commit_identity(2,3,7,5,0);release_identity(0,1,7);
                start_rasters=rasters;wait(rasters>=start_rasters+2);expect_word('h1c,0);release_identity(0,1,7);
                write_word('h18,3,0);wait_events(2);release_identity(1,2,7);write_word('h18,2,0);expect_word('h1c,3);
                load_record(0,1,99);submit(0,6,0);wait_events(3);commit_identity(0,1,99,6,0);release_identity(2,3,7);write_word('h18,3,0);
                // Unsupported BOX is rejected by the unchanged validator, without disturbing RAW.
                load_record(0,1,99);submit(1,8,1);wait_events(4);expect_word('h6c,'h14);write_word('h18,4,0);
                if(records!=4||feedbacks!=5||retires!=3||underflows!=0)$fatal(1,"SCANOUT_INTEGRATION_COVERAGE");
            end
        end
        if(case_id!=2&&!FULL)begin start_rasters=rasters;wait(rasters>=start_rasters+1);end
        $display("VIDEO_DISPLAY_SCANOUT_PASS case=%0d records=%0d feedbacks=%0d retires=%0d pixels=%0d rasters=%0d R=%0d W=%0d F=%0d A=%0d underflows=%0d",case_id,records,feedbacks,retires,checked_pixels,rasters,trace_reads,trace_writes,trace_fences,trace_waits,underflows);$finish;
    end
    initial begin #2000000000;$fatal(1,"SCANOUT_WATCHDOG case=%0d records=%0d feedbacks=%0d retires=%0d",case_id,records,feedbacks,retires);end
endmodule
`default_nettype wire
