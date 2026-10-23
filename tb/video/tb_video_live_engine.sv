`timescale 1ns/1ps
`default_nettype none
// Real capture/ingress/display/bridge; native DDR model stores actual bytes.
module tb_video_live_engine;
    parameter integer W=20,H=10,DELAYED=1,TARGET=5,EPOCHS=2,DENSE=0,PT=1,PB=1;
    reg clk=0,pixel_clk=0,rx_clk=0,reset_n=0,init_done=0;
    always #4 clk=~clk;
    always #12.5 pixel_clk=~pixel_clk;
    initial begin #2;forever #12.5 rx_clk=~rx_clk;end
    reg [10:0] pixel_x=0,pixel_y=0;
    wire pixel_de=pixel_x<W&&pixel_y<H;
    wire pixel_hs=pixel_x>=W+20&&pixel_x<W+25,pixel_vs=pixel_y>=H+3;
    wire frame_start=pixel_x==0&&pixel_y==0;
    always @(posedge pixel_clk)begin
        if(!reset_n)begin pixel_x<=0;pixel_y<=0;end
        else if(pixel_x==W+95)begin pixel_x<=0;pixel_y<=pixel_y==H+7?0:pixel_y+1'b1;end
        else pixel_x<=pixel_x+1'b1;
    end
    wire [23:0] out_rgb;wire out_hs,out_vs,out_de;
    reg cv=0,fb=0,fe=0,fg=1,mode_good=1;
    reg [10:0] cx=0,cy=0;reg [23:0] crgb=0;
    wire fv,fr,m_valid,m_ready,arm_toggle,cancel,source_fault,overflow;
    wire [47:0] fd,m_data;
    video_capture_ingress #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.ENABLE_REARM(1)) ingress(
        .pixel_clk(rx_clk),.pixel_reset_n(reset_n),.core_clk(clk),.core_reset_n(reset_n),
        .pixel_valid(cv),.pixel_rgb(crgb),.pixel_x(cx),.pixel_y(cy),.frame_start(fb),
        .frame_end(fe),.frame_good(fg),.mode_good(mode_good),.rx_ready(1'b1),
        .arm_toggle(arm_toggle),.cancel(cancel),.m_valid(fv),.m_data(fd),.m_ready(fr),
        .source_fault(source_fault),.overflow(overflow));
    video_stream_register #(.DATA_WIDTH(48)) pipe(
        .clk(clk),.reset_n(reset_n),.s_valid(fv),.s_ready(fr),.s_data(fd),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data));
    wire busy,done,error,capture_complete,port_drained;wire [7:0] error_code,phase;
    wire [31:0] captured_pixels,preview_pixels,source_crc,preview_crc,fifo_peak,ddr_crc,preview_ddr_crc;
    wire [31:0] frame_id,commits,completed_scans,read_lines,underflows,input_pixels;
    wire [31:0] raw_written_bytes,preview_written_bytes,input_written_bytes,preprocess_version,capture_frame_id;
    wire [31:0] raw_base,preview_base,input_base,input_ddr_crc,input_checked_bytes,captures,releases;
    wire [27:0] axi_awaddr,axi_araddr;wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_arvalid;
    wire [3:0] axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen,axi_wusero_id,axi_rid;
    wire axi_awready,axi_arready,axi_wready,axi_wusero_last,axi_rlast,axi_rvalid;
    wire [255:0] axi_wdata,axi_rdata;wire [31:0] axi_wstrb;
    `ifndef LIVE_DUT
    `define LIVE_DUT video_live_engine
    `endif
    `LIVE_DUT #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PAD_TOP(PT),.PAD_BOTTOM(PB),.TIMEOUT_CYCLES(10000000)) dut(
        .pixel_reset_n(reset_n),.*);
    integer fault_mode=0,write_beats,read_beats,earliest_beats,masked_beats,aw_commands,ar_commands,write_gaps;
    generate if(DENSE)begin
        video_live_memory #(.W(W),.H(H),.PT(PT),.PB(PB),.DELAYED(DELAYED)) mem(.*);
    end else begin
        ddr_native_model #(.MEMORY_SLOTS(2048)) mem(.address_mask(28'hfffffff),.delayed(DELAYED!=0),.*);
    end endgenerate
    function automatic [23:0] src(input integer x,y,tag);
        src={8'(x*7+tag*37),8'(y*13+tag*23),8'(x+y+tag*71)};
    endfunction
    integer tag=0,x,y,case_id=0,rasters=0,pixels=0,epoch=0;
    reg arm_seen=0;
    // New source material on EVERY request, without using KEY0 or DUT data.
    initial forever begin
        @(negedge rx_clk);
        if(!reset_n)begin arm_seen=0;tag=0;cv=0;fb=0;fe=0;end
        else if(arm_seen!=arm_toggle)begin
            arm_seen=arm_toggle;tag=tag+1;
            repeat(6)@(negedge rx_clk);
            for(y=0;y<H;y=y+1)begin
                for(x=0;x<W;x=x+1)begin
                    cv=1;fb=x==0&&y==0;cx=x;cy=y;crgb=src(x,y,tag);
                    @(negedge rx_clk);
                end
                cv=0;fb=0;repeat(64)@(negedge rx_clk);
            end
            fe=1;@(negedge rx_clk);fe=0;
        end
    end
    integer raster_tag=0,raster_pixels=0;
    always @(negedge pixel_clk)if(reset_n)begin
        if(dut.display.out_context_valid)begin
            if(dut.display.out_x==0&&dut.display.out_y==0)begin
                raster_tag=dut.display.out_frame_id;raster_pixels=0;
            end
            if(dut.display.out_frame_id!==raster_tag)$fatal(1,"LIVE_TORN_FRAME");
            if(out_rgb!==src(dut.display.out_x,dut.display.out_y,raster_tag))
                $fatal(1,"LIVE_PIXEL id=%0d x=%0d y=%0d got=%h",raster_tag,dut.display.out_x,dut.display.out_y,out_rgb);
            raster_pixels=raster_pixels+1;pixels=pixels+1;
            if(dut.display.out_x==W-1&&dut.display.out_y==H-1)begin
                if(raster_pixels!=W*H)$fatal(1,"LIVE_PARTIAL_FRAME");
                rasters=rasters+1;
            end
        end
    end
    // Submitted slots remain protected until actual display release, including
    // the pending descriptor and all old reads/pixel pipelines.
    reg [1:0] protected_slots=0;
    always @(posedge clk)begin
        if(!reset_n)protected_slots<=0;
        else begin
            if(dut.display.record_valid&&dut.display.record_ready)
                protected_slots[dut.display.record_slot]<=1;
            if(dut.display.release_valid&&dut.display.release_ready)
                protected_slots[dut.display.release_slot]<=0;
            if(dut.capture.req_valid&&dut.capture.req_ready&&protected_slots[dut.capture.req_slot])
                $fatal(1,"LIVE_SLOT_REUSED_BEFORE_RELEASE");
            if(error&&case_id==0)$fatal(1,"LIVE_UNEXPECTED_ERROR %h",error_code);
        end
    end
    initial begin
        if($value$plusargs("CASE=%d",case_id))begin end
        for(epoch=0;epoch<(case_id==0?EPOCHS:1);epoch=epoch+1)begin
            reset_n=0;init_done=0;repeat(12)@(negedge clk);reset_n=1;
            repeat(12)@(negedge clk);init_done=1;
            wait(commits>=TARGET);
            if(rasters<TARGET-1||underflows!=0||tag<TARGET)$fatal(1,"LIVE_NO_AUTOMATIC_PROGRESS");
            if(case_id!=0)begin
                if(case_id==1)begin
                    wait(ingress.state==2);@(negedge rx_clk);mode_good=0;
                end else begin
                    wait(dut.display.pixel_state==3);@(negedge clk);fault_mode=9;
                end
                wait(error);
                if(case_id==1&&error_code!=8'h03)$fatal(1,"LIVE_WRONG_SOURCE_FAULT %h",error_code);
                if(case_id==2&&error_code!=8'h66)$fatal(1,"LIVE_WRONG_READ_STALL_FAULT %h",error_code);
                repeat(200)@(negedge clk);
                if(!cancel||!error||error_code==0)$fatal(1,"LIVE_FAULT_NOT_STICKY");
                if(case_id==2)fault_mode=0;
                wait(port_drained);
                repeat(50)@(negedge clk);
                if(!port_drained||axi_awvalid||axi_arvalid)$fatal(1,"LIVE_FAULT_NOT_DRAINED");
            end
        end
        $display("VIDEO_LIVE_ENGINE_PASS case=%0d pixels=%0d rasters=%0d commits=%0d",case_id,pixels,rasters,commits);
        $finish;
    end
    initial begin #((W+160)*(H+20)*25*TARGET*10);$fatal(1,"LIVE_TIMEOUT: automatic commits=%0d tag=%0d phase=%h error=%h",commits,tag,phase,error_code);end
endmodule
`default_nettype wire
