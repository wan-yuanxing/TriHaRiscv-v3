`timescale 1ns/1ps
// Composition oracle: public pad outputs and public committed status only.
// No expected pixels are derived from internal renderer/cache implementation.
module tb_video_demo_mode_output;
    reg core_clk=0,pixel_clk=0,core_reset_n=0,pixel_reset_n=0,mode_button_n=1;
    always #4 core_clk=~core_clk;
    always #12.5 pixel_clk=~pixel_clk;
    reg context_valid=0;
    reg [31:0] context_frame_id=7,context_generation=1;
    reg [1:0] context_slot=0;
    reg [10:0] raw_x=0,raw_y=0;
    wire raw_de=raw_x<10&&raw_y<10;
    wire raw_hs=raw_x>=18&&raw_x<21,raw_vs=raw_y>=13&&raw_y<15;
    wire raw_sof=raw_x==0&&raw_y==0;
    reg variant=0;
    function automatic [23:0] original(input integer x,y,input bit source_variant);
        original={8'(8'h93^x),8'(8'h65^y),8'(8'hb7+x+y)} ^ (source_variant?24'h5a3cc3:24'd0);
    endfunction
    wire [23:0] raw_rgb=original(raw_x,raw_y,variant);
    wire [23:0] out_rgb;
    wire [10:0] out_x,out_y;
    wire [31:0] out_frame_id;
    wire out_de,out_hs,out_vs,out_sof,mode_first_pixel;
    wire [31:0] mode_state,request_seq,committed_seq,request_count,commit_count,coalesced_count;
    wire mode_error,asset_ready;
    video_demo_mode_output #(.FRAME_WIDTH(10),.FRAME_HEIGHT(10),
        .BUTTON_CLOCK_HZ(1000),.BUTTON_STABLE_MS(2)) dut(.*);
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin raw_x<=0;raw_y<=0;end
        else if(raw_x==23)begin raw_x<=0;raw_y<=raw_y==15?0:raw_y+1'b1;end
        else raw_x<=raw_x+1'b1;
    end
    function automatic [23:0] effect(input integer mode_value,x,y);
        integer left,top,right,bottom,sx,sy,r,g,b,a,c,v,px,py,k;
        reg hit,primary,point_hit;
        reg [23:0] back,result_rgb;
        begin
            back=original(x,y,variant);result_rgb=back;hit=0;primary=0;point_hit=0;
            if(mode_value==1)begin
                // Independent sets for diagnostic boxes: [2,7)x[2,7) and [1,5)x[1,5).
                for(k=0;k<2;k=k+1)begin
                    left=k==0?2:1;top=k==0?2:1;right=k==0?7:5;bottom=k==0?7:5;
                    if(x>=left&&x<right&&y>=top&&y<bottom&&
                       (x-left<2||right-1-x<2||y-top<2||bottom-1-y<2))begin
                        hit=1;if(k==0)primary=1;
                    end
                end
                for(k=0;k<5;k=k+1)begin
                    px=k==2?5:(k==1||k==4?6:3);
                    py=k==2?5:(k>=3?6:3);
                    if(x>=px-2&&x<=px+2&&y>=py-2&&y<=py+2)point_hit=1;
                end
                if(point_hit)result_rgb=24'hffff00;
                else if(hit)result_rgb=primary?24'hff0000:24'h00ff00;
            end else if(mode_value==2&&x>=2&&x<7&&y>=2&&y<7)begin
                sx=(x-2)*256/5;sy=(y-2)*256/5;
                r=(37*sx+13*sy+17)&255;g=(sx^(sy*7))&255;
                b=(255-sx+11*sy)&255;a=(sx+3*sy)&255;
                result_rgb=0;
                for(c=0;c<3;c=c+1)begin
                    v=(a*(c==0?r:c==1?g:b)+(255-a)*((back>>(16-8*c))&255)+127)/255;
                    result_rgb=result_rgb|(v<<(16-8*c));
                end
            end
            effect=result_rgb;
        end
    endfunction
    reg [25:0] expected_meta[0:13];
    reg [13:0] valid_pipe=0;
    reg [23:0] raster[0:99];
    integer checked_pixels=0,mode_rasters[0:2],i,x,y,current_mode,old_commit,scenario=0;
    reg started=0;
    task automatic check(input bit ok,input string why);
        if(!ok)$fatal(1,"demo_mode case%0d: %s",scenario,why);
    endtask
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin
            valid_pipe<=0;started=0;
            for(i=0;i<14;i=i+1)expected_meta[i]<=0;
        end else begin
            valid_pipe<={valid_pipe[12:0],1'b1};
            expected_meta[0]<={raw_x,raw_y,raw_de,raw_hs,raw_vs,raw_sof};
            for(i=1;i<14;i=i+1)expected_meta[i]<=expected_meta[i-1];
            #1;
            if(valid_pipe[13])begin
                check({out_x,out_y,out_de,out_hs,out_vs,out_sof}===expected_meta[13],"pad pixel/control delay");
                if(mode_first_pixel)check(out_sof&&out_de,"actual mode feedback not at visible first pixel");
                if(out_sof)started=1;
                if(out_de)raster[out_y*10+out_x]=out_rgb;
                if(started&&out_x==23&&out_y==15)begin
                    current_mode=mode_state[4]?mode_state[3:2]:0;
                    for(y=0;y<10;y=y+1)for(x=0;x<10;x=x+1)begin
                        if(raster[y*10+x]!==effect(current_mode,x,y))
                            $fatal(1,"composition mode%0d pixel(%0d,%0d): %h expected %h",current_mode,x,y,raster[y*10+x],effect(current_mode,x,y));
                        checked_pixels=checked_pixels+1;
                    end
                    mode_rasters[current_mode]=mode_rasters[current_mode]+1;
                end
            end
        end
    end
    task automatic reset_both;
        begin
            core_reset_n=0;pixel_reset_n=0;mode_button_n=1;context_valid=0;
            repeat(5)@(negedge core_clk);repeat(3)@(negedge pixel_clk);
            for(i=0;i<3;i=i+1)mode_rasters[i]=0;
            core_reset_n=1;pixel_reset_n=1;
        end
    endtask
    task automatic press_mode(input integer hold_cycles);
        integer before_count,timeout_count;
        begin
            before_count=request_count;
            @(negedge core_clk);mode_button_n=0;
            repeat(hold_cycles)@(negedge core_clk);
            mode_button_n=1;repeat(8)@(negedge core_clk);
            check(request_count==before_count+1,"MODE press did not generate exactly one request");
        end
    endtask
    task automatic wait_mode(input integer value);
        integer n;
        begin
            n=0;
            while(!(mode_state[4]&&mode_state[3:2]==value&&!mode_state[5]))begin
                @(negedge core_clk);n=n+1;
                if(n==20000)$fatal(1,"mode%0d did not actually commit",value);
            end
            check(!mode_error,"mode composition sticky fault");
        end
    endtask
    initial begin
        if($value$plusargs("CASE=%d",scenario))begin end
        reset_both();
        if(scenario==1)begin
            press_mode(8);press_mode(8);
            check(mode_state[1:0]==2&&!mode_state[4],"pre-frame requests not retained");
        end
        wait(asset_ready);context_valid=1;
        wait_mode(scenario==1?2:0);
        repeat(3)@(negedge raw_sof);
        if(scenario==0)begin
            press_mode(5000);wait_mode(1);wait(mode_rasters[1]>=2);
            press_mode(8);wait_mode(2);wait(mode_rasters[2]>=2);
            press_mode(8);wait_mode(0);wait(mode_rasters[0]>=2);
            check(request_count==3,"long press repeated");
        end else if(scenario==1)begin
            wait(mode_rasters[2]>=2);
            press_mode(8);press_mode(8);press_mode(8);press_mode(8);
            wait_mode(0);wait(mode_rasters[0]>=2);
            check(request_count==6&&committed_seq==6,"queued presses lost final request");
        end else if(scenario==2)begin
            press_mode(8);wait_mode(1);press_mode(8);wait_mode(2);wait(mode_rasters[2]>=2);
            reset_both();variant=1;context_frame_id=8;context_generation=2;
            wait(asset_ready);context_valid=1;wait_mode(0);wait(mode_rasters[0]>=2);
            check(request_count==0&&request_seq==0,"KEY0 epoch kept old mode request");
        end else $fatal(1,"Unknown case");
        check(checked_pixels>=300,"no complete raster checked");
        $display("VIDEO_DEMO_MODE_OUTPUT_PASS case=%0d pixels=%0d raw=%0d box=%0d avatar=%0d",scenario,checked_pixels,mode_rasters[0],mode_rasters[1],mode_rasters[2]);$finish;
    end
    initial begin #5000000;$fatal(1,"demo_mode timeout");end
endmodule
