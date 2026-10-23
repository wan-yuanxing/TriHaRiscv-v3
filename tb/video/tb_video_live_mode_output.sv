`timescale 1ns/1ps
module tb_video_live_mode_output;
    parameter integer W=20,H=20;
    reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0,mode_button_n=1,online=0,allow_pixels=1;
    always #4 core_clk=~core_clk;
    always #12.5 pixel_clk=~pixel_clk;
    reg [10:0] raw_x=0,raw_y=0;
    reg [31:0] context_frame_id=1;
    wire [31:0] context_generation=32'd1;
    wire [1:0] context_slot=context_frame_id[0]?2'd0:2'd1;
    wire raw_de=raw_x<W&&raw_y<H,raw_sof=raw_x==0&&raw_y==0;
    wire raw_hs=raw_x>=W+20&&raw_x<W+25,raw_vs=raw_y>=H+3;
    wire context_valid=online&&allow_pixels&&raw_de;
    function automatic [23:0] src(input integer x,y,tag);
        src={8'(x*7+tag*37),8'(y*13+tag*23),8'(x+y+tag*71)};
    endfunction
    wire [23:0] raw_rgb=src(raw_x,raw_y,context_frame_id);
    wire [23:0] out_rgb;wire [10:0] out_x,out_y;wire [31:0] out_frame_id;
    wire out_de,out_hs,out_vs,out_sof,mode_first_pixel,mode_error,asset_ready;
    wire [31:0] mode_state,request_seq,committed_seq,request_count,commit_count,coalesced_count;
    `ifndef LIVE_MODE_DUT
    `define LIVE_MODE_DUT video_live_mode_output
    `endif
    `LIVE_MODE_DUT #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.BUTTON_CLOCK_HZ(1000),.BUTTON_STABLE_MS(2)) dut(.*);
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin raw_x<=0;raw_y<=0;context_frame_id<=1;end
        else if(raw_x==W+95)begin
            raw_x<=0;
            if(raw_y==H+7)begin raw_y<=0;context_frame_id<=context_frame_id+1'b1;end
            else raw_y<=raw_y+1'b1;
        end else raw_x<=raw_x+1'b1;
    end
    function automatic [23:0] effect(input integer mode,x,y,tag);
        integer k,l,t,r,b,px,py,sx,sy,fr,fg,fb,a,c,v;
        reg border,primary,point_hit;reg [23:0] back;
        begin
            back=src(x,y,tag);effect=back;border=0;primary=0;point_hit=0;
            if(mode==1)begin
                for(k=0;k<2;k=k+1)begin
                    l=k==0?W/4:W/8;t=k==0?H/4:H/6;r=k==0?W*3/4:W/2;b=k==0?H*3/4:H/2;
                    if(x>=l&&x<r&&y>=t&&y<b&&(x-l<2||r-1-x<2||y-t<2||b-1-y<2))begin border=1;if(k==0)primary=1;end
                end
                for(k=0;k<5;k=k+1)begin
                    px=k==2?W/2:(k==1||k==4?W*5/8:W*3/8);
                    py=k==2?H/2:(k>=3?H*5/8:H*3/8);
                    if(x>=px-2&&x<=px+2&&y>=py-2&&y<=py+2)point_hit=1;
                end
                if(point_hit)effect=24'hffff00;else if(border)effect=primary?24'hff0000:24'h00ff00;
            end else if(mode==2&&x>=W/4&&x<W*3/4&&y>=H/4&&y<H*3/4)begin
                sx=(x-W/4)*256/(W*3/4-W/4);sy=(y-H/4)*256/(H*3/4-H/4);
                fr=(37*sx+13*sy+17)&255;fg=(sx^(sy*7))&255;fb=(255-sx+11*sy)&255;a=(sx+sy*3)&255;effect=0;
                for(c=0;c<3;c=c+1)begin
                    v=(a*(c==0?fr:c==1?fg:fb)+(255-a)*((back>>(16-8*c))&255)+127)/255;
                    effect=effect|(v<<(16-8*c));
                end
            end
        end
    endfunction
    reg [58:0] meta[0:13];reg [13:0] valid_pipe=0,trace_valid=0;
    reg [23:0] raster[0:W*H-1];reg raster_started=0;
    integer i,x,y,id=0,m,checked=0,rasters[0:2],epoch,old_count;
    reg [13:0] command_pipe=0;
    reg [31:0] sequence_pipe[0:13];
    integer visible_commands=0,observed_commits=0,phase_case=-1,phase_mask=0;
    reg [31:0] last_visible_seq=0;
    reg sync_hold=0,old_cmd_valid=0;
    reg [10:0] edge_x,edge_y;
    always @(posedge pixel_clk)begin
        edge_x=raw_x;edge_y=raw_y;
        if(!pixel_reset_n)begin command_pipe<=0;visible_commands=0;last_visible_seq=0;old_cmd_valid=0;end
        else begin
            command_pipe<={command_pipe[12:0],dut.pixel_cmd_valid&&dut.pixel_cmd_ready};
            sequence_pipe[0]<=dut.pixel_cmd_seq;
            for(integer n=1;n<14;n=n+1)sequence_pipe[n]<=sequence_pipe[n-1];
            #1;
            if(dut.pixel_cmd_valid&&!old_cmd_valid&&phase_case>=0)begin
                if((phase_case==0&&!(edge_x==W+95&&edge_y==H+7))||
                   (phase_case==1&&!(edge_x==0&&edge_y==0))||
                   (phase_case==2&&!(edge_x==1&&edge_y==0)))$fatal(1,"LIVE_MODE_PHASE_STIMULUS");
                phase_mask=phase_mask|(1<<phase_case);
            end
            old_cmd_valid=dut.pixel_cmd_valid;
            if(mode_first_pixel!==command_pipe[13])$fatal(1,"LIVE_MODE_PAD_MARKER_LATENCY");
            if(command_pipe[13])begin visible_commands=visible_commands+1;last_visible_seq=sequence_pipe[13];end
        end
    end
    always @(negedge core_clk)begin
        if(!core_reset_n)observed_commits=0;
        else if(commit_count!=observed_commits)begin
            if(commit_count!=observed_commits+1||visible_commands<commit_count||committed_seq!=last_visible_seq)
                $fatal(1,"LIVE_MODE_ACK_BEFORE_VISIBLE_RETIREMENT");
            observed_commits=commit_count;
        end
    end
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin valid_pipe<=0;trace_valid<=0;raster_started=0;end
        else begin
            valid_pipe<={valid_pipe[12:0],context_valid};
            trace_valid<={trace_valid[12:0],1'b1};
            meta[0]<={context_frame_id,raw_x,raw_y,raw_de,raw_hs,raw_vs,raw_sof,context_valid};
            for(i=1;i<14;i=i+1)meta[i]<=meta[i-1];
            #1;
            if(trace_valid[13]&&{out_frame_id,out_x,out_y,out_de,out_hs,out_vs,out_sof}!==meta[13][58:1])
                $fatal(1,"LIVE_MODE_FULL_RASTER_METADATA");
            // A deliberately invalid source interval is not a complete
            // displayed raster. Never compare unwritten entries from its predecessor.
            if(out_de&&!valid_pipe[13])raster_started=0;
            if(valid_pipe[13])begin
                if({out_frame_id,out_x,out_y,out_de,out_hs,out_vs,out_sof}!==meta[13][58:1])
                    $fatal(1,"LIVE_MODE_ID_OR_TIMING: changing frame must follow every pixel got=%0d",out_frame_id);
                if(mode_first_pixel&&!(out_sof&&out_de))$fatal(1,"LIVE_MODE_ACK_BEFORE_PAD_FIRST");
                if(out_sof)begin raster_started=1;id=out_frame_id;end
                if(raster_started&&out_de)begin
                    if(out_frame_id!=id)$fatal(1,"LIVE_MODE_TORN_ID");
                    raster[out_y*W+out_x]=out_rgb;
                    if(out_x==W-1&&out_y==H-1)begin
                        m=mode_state[4]?mode_state[3:2]:0;
                        for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
                            if(raster[y*W+x]!==effect(m,x,y,id))$fatal(1,"LIVE_MODE_PIXEL mode=%0d frame=%0d x=%0d y=%0d got=%h want=%h seq=%0d/%0d",m,id,x,y,raster[y*W+x],effect(m,x,y,id),request_seq,committed_seq);
                            checked=checked+1;
                        end
                        rasters[m]=rasters[m]+1;raster_started=0;
                    end
                end
            end
        end
    end
    always @(negedge core_clk)if(core_reset_n&&mode_error)$fatal(1,"LIVE_MODE_FAULT: continuous frames must not lock static context");
    task automatic press(input integer cycles);
        begin
            old_count=request_count;@(negedge core_clk);mode_button_n=0;
            repeat(cycles)@(negedge core_clk);mode_button_n=1;repeat(8)@(negedge core_clk);
            if(request_count!=old_count+1)$fatal(1,"LIVE_MODE_PRESS_COUNT");
        end
    endtask
    task automatic settle(input integer value);
        begin wait(mode_state[4]&&mode_state[3:2]==value&&request_seq==committed_seq&&!mode_state[5]);end
    endtask
    task automatic phased_press(input integer phase_value,value);
        begin
            wait(!dut.mode_cdc.core_busy);
            // Model an arbitrarily delayed synchronizer while the real core
            // mailbox remains owned and stable. Release at selected raster edge.
            sync_hold=dut.mode_cdc.request_seen;
            force dut.mode_cdc.request_sync=sync_hold;
            press(10);wait(dut.mode_cdc.core_busy);
            if(phase_value==0)wait(raw_x==W+95&&raw_y==H+7);
            if(phase_value==1)wait(raw_x==0&&raw_y==0);
            if(phase_value==2)wait(raw_x==1&&raw_y==0);
            @(negedge pixel_clk);phase_case=phase_value;sync_hold=dut.mode_cdc.request_toggle;
            @(negedge pixel_clk);release dut.mode_cdc.request_sync;
            settle(value);phase_case=-1;
        end
    endtask
    initial begin
        for(epoch=0;epoch<2;epoch=epoch+1)begin
            core_reset_n=0;pixel_reset_n=0;online=0;allow_pixels=1;mode_button_n=1;
            phase_mask=0;
            for(i=0;i<3;i=i+1)rasters[i]=0;
            repeat(8)@(negedge core_clk);core_reset_n=1;pixel_reset_n=1;
            wait(asset_ready);@(negedge pixel_clk);online=1;
            settle(0);wait(rasters[0]>=3);
            press(1000);settle(1);wait(rasters[1]>=3);
            press(10);settle(2);wait(rasters[2]>=3);
            press(10);settle(0);
            // Multiple requests before one raster boundary coalesce safely.
            @(negedge pixel_clk);allow_pixels=0;
            press(10);press(10);press(10);
            repeat(100)@(negedge core_clk);
            if(request_seq==committed_seq)$fatal(1,"LIVE_MODE_COMMITTED_WITHOUT_VALID_SOF");
            @(negedge pixel_clk);allow_pixels=1;
            settle(0);wait(rasters[0]>=5);
            phased_press(0,1);phased_press(1,2);phased_press(2,0);
            if(phase_mask!=7)$fatal(1,"LIVE_MODE_PHASE_COVERAGE");
        end
        $display("VIDEO_LIVE_MODE_OUTPUT_PASS pixels=%0d coalesced=%0d",checked,coalesced_count);$finish;
    end
    initial begin #10000000;$fatal(1,"LIVE_MODE_TIMEOUT");end
endmodule
