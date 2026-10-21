`timescale 1ns/1ps
`default_nettype none
module tb_display_record_pixels #(parameter integer W=40,H=24,CASE_ID=0,FULL=0,TIGHT=0,BOX_ONLY=0,parameter real PIXEL_HALF=12.5);
    reg core_clk=0,core_reset_n=0,pixel_clk=0,pixel_reset_n=0;
    always #4 core_clk=~core_clk;
    initial begin #3;forever #(PIXEL_HALF)pixel_clk=~pixel_clk;end
    reg cmd_valid=0,commit_ready=0,retire_ready=0;
    wire cmd_ready,commit_valid,retire_valid,fault;
    reg [1:0] cmd_mode=0,cmd_slot=0;reg [31:0] cmd_frame=0,cmd_generation=0,cmd_seq=0;
    reg [5119:0] cmd_data=0,records[0:8];
    wire [1:0] commit_mode,commit_slot,retire_slot,retire_mode;
    wire [31:0] commit_frame,commit_generation,commit_seq,retire_frame,retire_generation,retire_seq;
    wire retire_raw,retire_asset;wire [31:0] retire_asset_id,retire_asset_generation;wire [7:0] fault_code;
    wire pixel_pending;wire [1:0] pending_mode,pending_slot;wire [31:0] pending_frame,pending_generation;
    localparam integer HT=W+(TIGHT?0:8),VT=H+(TIGHT?0:4);
    reg [10:0] raw_x=0,raw_y=0;
    wire raw_de=raw_x<W&&raw_y<H,raw_hs=raw_x>=W+2&&raw_x<W+5,raw_vs=raw_y>=H+1&&raw_y<H+3;
    wire raw_sof=raw_x==0&&raw_y==0;
    reg [31:0] source_frame=0,source_generation=0;reg [1:0] source_slot=0;
    integer pending_id=0,active_id=0,pixel_ticks=0,core_ticks=0;
    reg asset_ready=1,source_hold=0,late_error=0,new_source_wait=0;reg [31:0] asset_id=7,asset_generation=71;
    wire pending_needs_asset=pending_id!=0&&(pending_id==3||pending_id==5||pending_id==6);
    wire wanted_asset_ready=!pending_needs_asset||(asset_ready&&asset_id==records[pending_id][14*32+:32]&&asset_generation==records[pending_id][15*32+:32]);
    wire expected_apply=pixel_pending&&raw_sof&&wanted_asset_ready&&!fault&&!source_hold;
    wire generation_probe=CASE_ID==7&&source_hold&&pixel_pending;
    wire switch_source_early=new_source_wait&&pixel_pending&&raw_sof;
    wire [31:0] raw_frame=generation_probe?32'd1:expected_apply||switch_source_early?records[pending_id][3*32+:32]:source_frame;
    wire [31:0] raw_generation=generation_probe?32'd11:expected_apply||switch_source_early?records[pending_id][4*32+:32]:source_generation;
    wire [1:0] raw_slot=expected_apply||switch_source_early?records[pending_id][2*32+:2]:source_slot;
    wire raw_context_valid=raw_frame!=0;
    wire [23:0] raw_rgb={8'(raw_x*7+raw_frame*31),8'(raw_y*11+raw_frame*17),8'(raw_x*3+raw_y*13)};
    wire avatar_req_valid;wire [17:0] avatar_req_addr;wire [31:0] avatar_req_asset_id,avatar_req_generation;
    reg sample_valid=0,sample_error=0;reg [31:0] sample_rgba=0;
    wire [23:0] out_rgb;wire [10:0] out_x,out_y;wire [31:0] out_frame,out_generation,out_seq;
    wire [1:0] out_slot,out_mode;wire out_de,out_hs,out_vs,out_sof,out_box,out_point,out_avatar,out_fault;
    display_record_pixels dut(.*);
    reg guard_start=0;wire guard_ready,guard_result;wire [7:0] guard_code;
    reg [5119:0] guard_data=0;reg [1:0] guard_mode=0;
    display_record_guard u_fixture_guard(
        .clk_i(core_clk),.rst_ni(core_reset_n),.start_valid_i(guard_start),.start_ready_o(guard_ready),
        .record_i(guard_data),.mode_i(guard_mode),.modes_i(3'b111),.asset_ready_i(1'b1),
        .asset_id_i(guard_data[14*32+:32]),.asset_generation_i(guard_data[15*32+:32]),
        .result_valid_o(guard_result),.result_ready_i(1'b1),.result_code_o(guard_code));
    function automatic [31:0] material(input integer x,y,a);
        material={8'(37*x+13*y+17+17*a),8'(x^(y*7)^a),8'(255-x+11*y+29*a),8'(x+3*y+a*5)};
    endfunction
    reg [13:0] valid_pipe=0;integer ids[0:13];integer next_id=0,k,applied_tick[0:8];
    integer pixel_fd,checked=0,commits=0,retires=0,applies=0,requests=0;
    reg [31:0] ref_seq=0;integer ref_id;
    wire [1:0] provider_behavior=CASE_ID==3&&active_id==3?2'd2:2'd0;
    reg [1:0] behavior_pipe[0:8];
    always @(posedge pixel_clk)begin
        if(!pixel_reset_n)begin
            raw_x<=0;raw_y<=0;source_frame<=0;source_generation<=0;source_slot<=0;
            valid_pipe<=0;active_id=0;ref_seq=0;
            sample_valid<=0;sample_error<=0;sample_rgba<=0;
            for(k=0;k<9;k=k+1)behavior_pipe[k]<=0;
        end else begin
            pixel_ticks=pixel_ticks+1;
            if(raw_x==HT-1)begin raw_x<=0;if(raw_y==VT-1)raw_y<=0;else raw_y<=raw_y+1'b1;end
            else raw_x<=raw_x+1'b1;
            if(pixel_pending)begin
                if(pending_mode!==(pending_id==2||pending_id==7?2'd1:pending_id==3||pending_id==5||pending_id==6?2'd2:2'd0)||
                    pending_frame!==records[pending_id][3*32+:32]||pending_generation!==records[pending_id][4*32+:32]||
                    pending_slot!==records[pending_id][2*32+:2])$fatal(1,"RECORD_PIXELS_PENDING_IDENTITY");
            end
            if(expected_apply)begin
                active_id=pending_id;ref_seq=32'(100+pending_id);applied_tick[pending_id]=pixel_ticks;applies=applies+1;
                source_frame<=raw_frame;source_generation<=raw_generation;source_slot<=raw_slot;
            end
            if(switch_source_early)begin source_frame<=raw_frame;source_generation<=raw_generation;source_slot<=raw_slot;end
            ref_id=active_id;
            $fdisplay(pixel_fd,"I %h %h %h %h %h %h %h %h %h %h %h %h %h %h",next_id,ref_id,raw_frame,raw_generation,raw_slot,ref_seq,
                raw_x,raw_y,raw_rgb,raw_de,raw_hs,raw_vs,raw_sof,((CASE_ID==3&&ref_id==3)||late_error?2:0));
            for(k=13;k>0;k=k-1)ids[k]=ids[k-1];ids[0]=next_id;next_id=next_id+1;
            valid_pipe<={valid_pipe[12:0],1'b1};
            behavior_pipe[0]<=((CASE_ID==3&&ref_id==3)||late_error?2:0);for(k=1;k<9;k=k+1)behavior_pipe[k]<=behavior_pipe[k-1];
            if(valid_pipe[8])begin
                $fdisplay(pixel_fd,"Q %h %h %h %h %h",ids[9],avatar_req_valid,avatar_req_addr,avatar_req_asset_id,avatar_req_generation);
                if(avatar_req_valid)requests=requests+1;
            end
            sample_valid<=avatar_req_valid;sample_error<=avatar_req_valid&&behavior_pipe[8]==2;
            sample_rgba<=avatar_req_valid?material(int'(avatar_req_addr[9:2]),int'(avatar_req_addr[17:10]),int'(avatar_req_asset_id)):32'hxxxxxxxx;
            #1;
            if(valid_pipe[13])begin
                $fdisplay(pixel_fd,"P %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",ids[13],out_frame,out_generation,out_slot,out_mode,out_seq,
                    out_x,out_y,out_de,out_hs,out_vs,out_sof,out_rgb,out_box,out_point,out_avatar,out_fault);
                checked=checked+1;
            end
        end
    end
    integer last_commit=0;
    always @(posedge core_clk)if(core_reset_n)begin
        core_ticks=core_ticks+1;
        if(commit_valid)begin
            if(commit_frame!==records[pending_id][3*32+:32]||commit_generation!==records[pending_id][4*32+:32]||
                commit_slot!==records[pending_id][2*32+:2]||commit_seq!==32'(100+pending_id)||
                commit_mode!==2'(pending_id==2||pending_id==7?1:pending_id==3||pending_id==5||pending_id==6?2:0)||
                pixel_ticks<applied_tick[pending_id]+13)$fatal(1,"RECORD_PIXELS_EARLY_OR_WRONG_COMMIT");
            if(cmd_ready)$fatal(1,"RECORD_PIXELS_COMMAND_DURING_FEEDBACK");
        end
        if(commit_valid&&commit_ready)begin commits=commits+1;last_commit=pending_id;end
        if(retire_valid)begin
            if(cmd_ready)$fatal(1,"RECORD_PIXELS_COMMAND_DURING_RETIRE");
            if(last_commit!=(CASE_ID==8||CASE_ID==10?5:4+retires))$fatal(1,"RECORD_PIXELS_RETIRE_BEFORE_FEEDBACK");
            if(retire_frame!==32'(retires==0?1:retires==1?1:retires==2?2:3)||
                retire_generation!==32'(retires==0?10:retires==1?10:retires==2?11:12)||
                retire_slot!==2'(retires<2?0:retires==2?1:2))$fatal(1,"RECORD_PIXELS_RETIRE_IDENTITY");
            if({retire_raw,retire_asset}!==2'(CASE_ID==8||CASE_ID==10?3:retires==0?1:retires==1?2:retires==2?2:3))$fatal(1,"RECORD_PIXELS_RETIRE_FLAGS");
            if(retire_asset&&(retire_asset_id!==32'(retires<2?7:8)||retire_asset_generation!==32'(retires<2?71:81)))$fatal(1,"RECORD_PIXELS_RETIRE_ASSET");
            if(retire_seq!==32'(retires+103)||retire_mode!==2'(retires==0||retires>1?2:0))$fatal(1,"RECORD_PIXELS_RETIRE_CONTEXT");
        end
        if(retire_valid&&retire_ready)retires=retires+1;
    end
    task automatic submit(input integer id);
        reg [5119:0] saved;integer old_commits;
        begin
            old_commits=commits;pending_id=id;
            @(negedge core_clk);guard_data=records[id];guard_mode=id==2||id==7?1:id==3||id==5||id==6?2:0;guard_start=1;
            do @(posedge core_clk);while(!guard_ready);
            @(negedge core_clk);guard_start=0;wait(guard_result);
            if(guard_code!=0)$fatal(1,"RECORD_PIXELS_FIXTURE_NOT_GUARD_LEGAL %0d code=%h",id,guard_code);
            @(negedge core_clk);cmd_data=records[id];cmd_slot=cmd_data[2*32+:2];cmd_frame=cmd_data[3*32+:32];cmd_generation=cmd_data[4*32+:32];cmd_seq=32'(100+id);
            cmd_mode=id==2||id==7?1:id==3||id==5||id==6?2:0;saved=cmd_data;cmd_valid=1;
            if(CASE_ID==1&&id==1)cmd_frame=0;
            if(CASE_ID==5&&id==1)cmd_data[31:0]=32'hxxxxxxxx;
            do @(posedge core_clk);while(!cmd_ready);
            @(negedge core_clk);cmd_valid=0;cmd_data=~saved;cmd_frame=32'hdeadbeef;cmd_generation=0;cmd_seq=0;cmd_slot=3;cmd_mode=3;
            if((CASE_ID==1||CASE_ID==5)&&id==1)begin wait(fault);end
            else if(CASE_ID==9&&id==5)begin
                cmd_valid=1'bx;@(negedge core_clk);cmd_valid=0;wait(fault);
                repeat(4)@(negedge pixel_clk);new_source_wait=1;
                repeat(HT*VT*2)@(negedge pixel_clk);
                if(commit_valid||commits!=1||retire_valid)$fatal(1,"RECORD_PIXELS_UNPROVEN_AFTER_CORE_FAULT");
            end
            else if(CASE_ID==4&&id==3)begin
                wait(pixel_pending);repeat(HT*VT)@(negedge pixel_clk);
                if(commits!=2||retire_valid)$fatal(1,"RECORD_PIXELS_PENDING_RESET_PREMISE");
                @(negedge pixel_clk);pixel_reset_n=0;core_reset_n=0;
                $fdisplay(pixel_fd,"Z %h",next_id);
                repeat(8)@(negedge core_clk);commits=0;retires=0;applies=0;
                core_reset_n=1;pixel_reset_n=1;asset_ready=1;
            end
            else if((CASE_ID==2||CASE_ID==3)&&id==3)begin wait(fault);repeat(80)@(negedge core_clk);if(commit_valid||commits!=2)$fatal(1,"RECORD_PIXELS_FALSE_FAULT_COMMIT");end
            else if(CASE_ID==6&&id==3)begin
                wait(commit_valid);repeat(67)@(negedge core_clk);late_error=1;wait(fault);
                repeat(80)@(negedge core_clk);if(!commit_valid||cmd_ready)$fatal(1,"RECORD_PIXELS_PROVEN_COMMIT_LOST_ON_FAULT");
                commit_ready=1;@(negedge core_clk);commit_ready=0;
                if(commits!=3||retire_valid)$fatal(1,"RECORD_PIXELS_HISTORICAL_EVENT");
            end
            else begin
                wait(commit_valid);repeat(67)@(negedge core_clk);
                if(!commit_valid||cmd_ready)$fatal(1,"RECORD_PIXELS_FEEDBACK_NOT_HELD");
                commit_ready=1;@(negedge core_clk);commit_ready=0;
                if(commits!=old_commits+1)$fatal(1,"RECORD_PIXELS_COMMIT_HANDSHAKE");
                repeat(91)@(negedge core_clk);
                if(retire_valid)begin
                    repeat(57)@(negedge core_clk);retire_ready=1;@(negedge core_clk);retire_ready=0;
                end
            end
        end
    endtask
    string directory;integer j;
    initial begin
        for(j=0;j<9;j=j+1)applied_tick[j]=0;
        if(!$value$plusargs("DIR=%s",directory))$fatal(1,"RECORD_PIXELS_DIR");
        $readmemh({directory,"/records.hex"},records);pixel_fd=$fopen({directory,"/pixels.log"},"w");if(!pixel_fd)$fatal(1,"dump open");
        repeat(8)@(negedge core_clk);core_reset_n=1;pixel_reset_n=1;
        if(CASE_ID==7)begin
            source_hold=1;
            fork begin submit(1);end begin repeat(HT*VT*2)@(negedge pixel_clk);if(commits!=0)$fatal(1,"RECORD_PIXELS_GENERATION_WAIT");source_hold=0;end join
        end else submit(1);
        if(CASE_ID==9)begin source_hold=1;asset_id=8;asset_generation=81;submit(5);end
        if(CASE_ID!=1&&CASE_ID!=5&&CASE_ID!=7&&CASE_ID!=9)begin
            submit(2);
            if(!BOX_ONLY)begin
            if(CASE_ID==2)begin asset_id=99;asset_generation=991;end
            if(CASE_ID==4)asset_ready=0;
            if(CASE_ID==0&&FULL==0)begin
                asset_ready=0;
                fork begin submit(3);end begin repeat(HT*VT*2)@(negedge pixel_clk);if(commits!=2)$fatal(1,"RECORD_PIXELS_ASSET_WAIT");asset_ready=1;end join
            end else submit(3);
            if(CASE_ID==0&&FULL==0)begin
                submit(4);asset_id=8;asset_generation=81;source_hold=1;
                fork begin submit(5);end begin repeat(HT*VT*2)@(negedge pixel_clk);if(commits!=4)$fatal(1,"RECORD_PIXELS_SOURCE_WAIT");source_hold=0;end join
                submit(6);asset_id=9;asset_generation=91;submit(7);submit(8);
            end
            if(CASE_ID==4)submit(1);
            if(CASE_ID==8||CASE_ID==10)begin
                asset_ready=0;asset_id=8;asset_generation=81;new_source_wait=1;
                fork begin submit(5);end begin repeat(HT*VT*2)@(negedge pixel_clk);if(fault||commits!=3||retire_valid)$fatal(1,"RECORD_PIXELS_NEW_SOURCE_ASSET_WAIT");asset_ready=1;end join
            end
            end
        end
        if(CASE_ID==0||CASE_ID==4||CASE_ID==7||CASE_ID==8||CASE_ID==10)begin
            wait(raw_sof);@(negedge pixel_clk);repeat(HT*VT+32)@(negedge pixel_clk);
            if(fault||commits!=(BOX_ONLY?2:CASE_ID==8||CASE_ID==10?4:CASE_ID==4||CASE_ID==7?1:FULL?3:8)||retires!=(BOX_ONLY?0:CASE_ID==8||CASE_ID==10?1:CASE_ID==4||CASE_ID==7||FULL?0:4)||(!BOX_ONLY&&CASE_ID!=4&&CASE_ID!=7&&requests==0))$fatal(1,"RECORD_PIXELS_COVERAGE c=%0d r=%0d code=%h",commits,retires,fault_code);
        end else begin repeat(HT*VT+32)@(negedge pixel_clk);if(!fault||cmd_ready)$fatal(1,"RECORD_PIXELS_FAULT_NOT_HELD");end
        $fclose(pixel_fd);$display("DISPLAY_RECORD_PIXELS_PASS case=%0d commits=%0d retires=%0d applies=%0d pixels=%0d requests=%0d",CASE_ID,commits,retires,applies,checked,requests);$finish;
    end
    initial begin #1000000000;$fatal(1,"RECORD_PIXELS_WATCHDOG");end
endmodule
`default_nettype wire
