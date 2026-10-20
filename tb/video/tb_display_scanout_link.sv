`timescale 1ns/1ps
`default_nettype none
module tb_display_scanout_link #(parameter integer LEGACY_LINK=0);
    reg clk=0,reset_n=0,pixel_clk=0,pixel_reset_n=0;
    always #4 clk=~clk;always #12.5 pixel_clk=~pixel_clk;
    reg cmd_valid=0,cmd_mode_only=0;wire cmd_ready;
    reg [1:0] cmd_slot=0,cmd_mode=0;
    reg [31:0] cmd_frame=1,cmd_generation=7,cmd_base=32'h82000000,cmd_stride=2400,cmd_seq=3;
    wire record_valid;reg record_ready=0;
    wire [31:0] record_base,record_stride,record_frame;wire [1:0] record_slot;
    reg raw_commit_valid=0,raw_release_valid=0,raw_reject=0,raw_error=0;
    reg [31:0] raw_commit_frame=0,raw_release_frame=0;reg [1:0] raw_commit_slot=0,raw_release_slot=0;
    wire raw_commit_ready,raw_release_ready;
    wire feedback_valid,retire_valid;reg feedback_ready=0,retire_ready=0;
    wire [1:0] feedback_slot,feedback_mode,retire_slot;
    wire [31:0] feedback_frame,feedback_generation,feedback_seq,retire_frame,retire_generation;
    wire fault;wire [7:0] fault_code;
    reg pixel_sof=0,sof_enable=1;integer pixel_ticks=0;
    always @(negedge pixel_clk)begin pixel_ticks=pixel_ticks+1;pixel_sof=sof_enable&&(pixel_ticks%17==0);end
    generate if(LEGACY_LINK)begin
        // Deliberately unsafe test-only join: request acceptance is mistaken
        // for visible commit. No existing production module uses this join.
        assign cmd_ready=1;assign record_valid=cmd_valid;
        assign record_base=cmd_base;assign record_stride=cmd_stride;assign record_frame=cmd_frame;assign record_slot=cmd_slot;
        assign feedback_valid=cmd_valid;assign feedback_slot=cmd_slot;assign feedback_mode=cmd_mode;
        assign feedback_frame=cmd_frame;assign feedback_generation=cmd_generation;assign feedback_seq=cmd_seq;
        assign retire_valid=0;assign retire_slot=0;assign retire_frame=0;assign retire_generation=0;
        assign raw_commit_ready=1;assign raw_release_ready=1;assign fault=0;assign fault_code=0;
    end else begin
        display_scanout_link dut(.*);
    end endgenerate
    integer case_id=0,raw_commits=0,records=0,feedbacks=0,retirements=0;
    reg held_record=0,held_feedback=0,held_retire=0;
    reg [97:0] saved_record;reg [99:0] saved_feedback;reg [65:0] saved_retire;
    always @(posedge clk)if(reset_n)begin
        if(fault&&cmd_valid&&cmd_ready)$fatal(1,"LINK_FAULT_ACCEPTED_COMMAND");
        if(held_record&&(!record_valid||{record_slot,record_base,record_stride,record_frame}!==saved_record))$fatal(1,"LINK_RECORD_UNSTABLE");
        if(held_feedback&&(!feedback_valid||{feedback_mode,feedback_slot,feedback_frame,feedback_generation,feedback_seq}!==saved_feedback))$fatal(1,"LINK_FEEDBACK_UNSTABLE");
        if(held_retire&&(!retire_valid||{retire_slot,retire_frame,retire_generation}!==saved_retire))$fatal(1,"LINK_RETIRE_UNSTABLE");
        held_record<=record_valid&&!record_ready;saved_record<={record_slot,record_base,record_stride,record_frame};
        held_feedback<=feedback_valid&&!feedback_ready;saved_feedback<={feedback_mode,feedback_slot,feedback_frame,feedback_generation,feedback_seq};
        held_retire<=retire_valid&&!retire_ready;saved_retire<={retire_slot,retire_frame,retire_generation};
        if(record_valid&&record_ready)records=records+1;
        if(raw_commit_valid&&raw_commit_ready)raw_commits=raw_commits+1;
        if(feedback_valid&&raw_commits==0)$fatal(1,"LINK_COMMIT_PRECEDES_RAW");
        if(feedback_valid&&feedback_ready)feedbacks=feedbacks+1;
        if(retire_valid&&retire_ready)retirements=retirements+1;
    end
    task automatic offer(input integer slot,frame,generation,seq,input bit only);
        begin
            @(negedge clk);cmd_slot=2'(slot);cmd_frame=32'(frame);cmd_generation=32'(generation);cmd_seq=32'(seq);
            cmd_mode_only=only;cmd_base=32'h82000000+32'(slot)*32'h200000;cmd_valid=1;
            do @(posedge clk);while(!cmd_ready);
            @(negedge clk);cmd_valid=0;
        end
    endtask
    task automatic take_record;
        begin
            wait(record_valid);repeat(7)@(negedge clk);
            if(feedback_valid)$fatal(1,"LINK_RECORD_IS_NOT_COMMIT");
            record_ready=1;@(negedge clk);record_ready=0;
        end
    endtask
    task automatic send_commit(input integer slot,frame);
        begin
            @(negedge clk);raw_commit_slot=2'(slot);raw_commit_frame=32'(frame);raw_commit_valid=1;
            do @(posedge clk);while(!raw_commit_ready);
            @(negedge clk);raw_commit_valid=0;
        end
    endtask
    task automatic take_feedback(input integer slot,frame,generation,seq);
        begin
            wait(feedback_valid);repeat(9)@(negedge clk);
            if({feedback_slot,feedback_frame,feedback_generation,feedback_seq}!=={2'(slot),32'(frame),32'(generation),32'(seq)}||feedback_mode!=0)$fatal(1,"LINK_FEEDBACK_IDENTITY");
            feedback_ready=1;@(negedge clk);feedback_ready=0;
        end
    endtask
    task automatic expect_fault;
        begin
            repeat(12)@(negedge clk);cmd_valid=1;
            repeat(8)begin @(negedge clk);if(!fault||cmd_ready||feedback_valid||retire_valid)$fatal(1,"LINK_FAULT_NOT_CONSERVATIVE code=%0d",fault_code);end
        end
    endtask
    task automatic delayed_release(input bit record_already_taken);
        integer waited;
        begin
            offer(0,1,7,3,0);take_record;send_commit(0,1);take_feedback(0,1,7,3);
            offer(1,2,8,4,0);take_record;send_commit(1,2);take_feedback(1,2,8,4);
            offer(2,3,9,5,0);
            if(record_already_taken)take_record;
            @(negedge clk);raw_release_slot=0;raw_release_frame=1;raw_release_valid=1;waited=0;#1;
            while(!raw_release_ready&&waited<40)begin @(negedge clk);waited=waited+1;end
            if(!raw_release_ready)$fatal(1,"LINK_DELAYED_RELEASE_BLOCKED");
            @(posedge clk);@(negedge clk);raw_release_valid=0;
            wait(retire_valid);
            if({retire_slot,retire_frame,retire_generation}!=={2'd0,32'd1,32'd7})$fatal(1,"LINK_DELAYED_RELEASE_IDENTITY");
            retire_ready=1;@(negedge clk);retire_ready=0;
            if(!record_already_taken)take_record;
            send_commit(2,3);take_feedback(2,3,9,5);
            if(fault||records!=3||feedbacks!=3||retirements!=1)$fatal(1,"LINK_DELAYED_RELEASE_COVERAGE");
        end
    endtask
    initial begin
        if($value$plusargs("CASE=%d",case_id))begin end
        repeat(6)@(negedge clk);reset_n=1;pixel_reset_n=1;
        if(case_id==9||case_id==10)begin delayed_release(case_id==10);end
        else if(case_id==6||case_id==7)begin
            raw_commit_valid=case_id==6?1'b1:1'bx;repeat(2)@(negedge clk);raw_commit_valid=0;expect_fault;
        end else if(case_id==8)begin offer(0,1,7,3,1);expect_fault;end
        else begin
            offer(0,1,7,3,0);
            if(case_id==4)begin raw_error=1;repeat(9)@(negedge clk);if(!record_valid)$fatal(1,"LINK_FAULT_WITHDREW_RECORD");record_ready=1;@(negedge clk);record_ready=0;expect_fault;end
            else begin
                take_record;
                if(case_id==3)begin raw_reject=1;@(negedge clk);raw_reject=0;expect_fault;end
                else if(case_id==1)begin send_commit(0,99);expect_fault;end
                else begin
                    send_commit(0,1);take_feedback(0,1,7,3);
                    if(case_id==2)begin raw_release_slot=0;raw_release_frame=1;raw_release_valid=1;repeat(3)@(negedge clk);raw_release_valid=0;expect_fault;end
                    else if(case_id==5)begin cmd_generation=32'bx;cmd_valid=1;@(negedge clk);cmd_valid=0;expect_fault;end
                    else begin
                        offer(1,2,7,4,0);take_record;
                        fork
                            send_commit(1,2);
                            begin
                                raw_release_slot=0;raw_release_frame=1;raw_release_valid=1;
                                repeat(12)@(negedge clk);
                                if(raw_release_ready||retire_valid)$fatal(1,"LINK_RETIRE_PRECEDES_FEEDBACK");
                                take_feedback(1,2,7,4);
                                do @(posedge clk);while(!raw_release_ready);
                                @(negedge clk);raw_release_valid=0;
                            end
                        join
                        wait(retire_valid);repeat(23)@(negedge clk);
                        if({retire_slot,retire_frame,retire_generation}!=={2'd0,32'd1,32'd7})$fatal(1,"LINK_RETIRE_IDENTITY");
                        retire_ready=1;@(negedge clk);retire_ready=0;
                        sof_enable=0;offer(1,2,7,99,1);repeat(35)@(negedge clk);
                        if(feedback_valid||record_valid||retire_valid||records!=2)$fatal(1,"LINK_MODE_EARLY_OR_RAW_REPLAY");
                        sof_enable=1;take_feedback(1,2,7,99);
                        offer(0,1,99,100,0);take_record;send_commit(0,1);take_feedback(0,1,99,100);
                        if(fault||records!=3||feedbacks!=4||retirements!=1)$fatal(1,"LINK_COVERAGE");
                    end
                end
            end
        end
        $display("DISPLAY_SCANOUT_LINK_PASS case=%0d records=%0d feedbacks=%0d retirements=%0d",case_id,records,feedbacks,retirements);$finish;
    end
    initial begin #1000000;$fatal(1,"LINK_WATCHDOG case=%0d",case_id);end
endmodule
`default_nettype wire
