`timescale 1ns/1ps
module tb_display_mode_control #(parameter integer CONTEXT_WIDTH=128);
    reg clk=0,reset_n=0;
    reg request_valid=0;wire request_ready;reg [1:0] request_mode=0;
    wire reject_valid;reg reject_ready=0;wire [1:0] rejected_mode;wire [31:0] rejected_requests;
    reg context_valid=0;reg [31:0] context_frame_id=1,context_generation=10;
    reg [1:0] context_slot=0;reg [CONTEXT_WIDTH-1:0] context_data=128'h1020304050607080;
    reg [2:0] capabilities=7;reg result_valid=0,result_empty=0,avatar_ready=0;
    reg [31:0] result_frame_id=1;
    wire [1:0] requested_mode,active_mode;wire [31:0] request_seq,committed_seq;
    wire active_valid;wire [31:0] active_frame_id,active_generation;wire [1:0] active_slot;
    wire [CONTEXT_WIDTH-1:0] active_data;
    wire pending,unavailable,protocol_error;
    wire [31:0] request_count,command_count,commit_count,coalesced_count,protocol_errors;
    wire cmd_valid;reg cmd_ready=0;wire [1:0] cmd_mode,cmd_slot;
    wire [31:0] cmd_seq,cmd_frame_id,cmd_generation;
    wire [CONTEXT_WIDTH-1:0] cmd_data;
    reg commit_valid=0;wire commit_ready;reg [1:0] commit_mode=0,commit_slot=0;
    reg [31:0] commit_seq=0,commit_frame_id=0,commit_generation=0;
    reg [1:0] sent_mode,sent_slot;reg [31:0] sent_seq,sent_frame,sent_generation;
    reg [CONTEXT_WIDTH-1:0] sent_data;
    reg held=0;reg [CONTEXT_WIDTH+99:0] held_payload;
    integer checks=0,test_case=0,j;
    always #4 clk=~clk;
    display_mode_control #(.CONTEXT_WIDTH(CONTEXT_WIDTH)) dut(.*);
    always @(posedge clk)begin
        if(!reset_n)held<=0;
        else begin
            if(held)begin
                if(!cmd_valid || {cmd_mode,cmd_seq,cmd_frame_id,cmd_slot,cmd_generation,cmd_data}!==held_payload)
                    $fatal(1,"MODE: exposed command changed under backpressure");
            end
            held<=cmd_valid&&!cmd_ready;
            held_payload<={cmd_mode,cmd_seq,cmd_frame_id,cmd_slot,cmd_generation,cmd_data};
        end
    end
    task automatic check(input bit ok,input string message);
        begin checks++;if(ok!==1'b1)$fatal(1,"MODE case%0d: %s",test_case,message);end
    endtask
    task automatic cycle;begin @(posedge clk);#1;end endtask
    task automatic reset_control;
        begin
            @(negedge clk);reset_n=0;request_valid=0;reject_ready=0;context_valid=0;
            capabilities=7;result_valid=0;result_empty=0;avatar_ready=0;
            context_frame_id=1;context_slot=0;context_generation=10;context_data=128'h1020304050607080;
            result_frame_id=1;cmd_ready=0;commit_valid=0;
            cycle;check(!cmd_valid&&!active_valid&&!reject_valid&&!protocol_error,"reset clears protocol state");
            check(requested_mode==0&&active_mode==0&&request_seq==0&&committed_seq==0,"reset defaults RAW and sequence0");
            @(negedge clk);reset_n=1;cycle;
        end
    endtask
    task automatic request(input reg [1:0] mode);
        integer waited;
        begin
            @(negedge clk);request_mode=mode;request_valid=1;waited=0;
            while(!request_ready)begin cycle;waited++;if(waited>30)$fatal(1,"request timeout");end
            cycle;@(negedge clk);request_valid=0;
        end
    endtask
    task automatic await_offer;
        integer waited;
        begin
            waited=0;
            while(!cmd_valid)begin cycle;waited++;if(waited>30)$fatal(1,"MODE: missing prepared command");end
        end
    endtask
    task automatic accept_command;
        begin
            await_offer;
            sent_mode=cmd_mode;sent_seq=cmd_seq;sent_frame=cmd_frame_id;
            sent_slot=cmd_slot;sent_generation=cmd_generation;sent_data=cmd_data;
            @(negedge clk);cmd_ready=1;cycle;
            check(!cmd_valid&&commit_ready,"accepted command waits for actual commit");
            @(negedge clk);cmd_ready=0;
        end
    endtask
    task automatic confirm_command;
        begin
            @(negedge clk);commit_valid=1;commit_mode=sent_mode;commit_seq=sent_seq;
            commit_frame_id=sent_frame;commit_slot=sent_slot;commit_generation=sent_generation;
            check(commit_ready,"commit receiver ready for in-flight command");cycle;
            check(active_valid&&active_mode==sent_mode&&committed_seq==sent_seq&&active_frame_id==sent_frame&&
                  active_slot==sent_slot&&active_generation==sent_generation&&active_data==sent_data,"only matching commit publishes full active identity");
            @(negedge clk);commit_valid=0;
        end
    endtask
    task automatic initial_raw;
        begin
            @(negedge clk);context_valid=1;
            cycle;check(!active_valid,"preparation must not activate image");
            accept_command;check(!active_valid&&commit_count==0,"command acceptance is not commit");
            confirm_command;cycle;check(!pending&&!cmd_valid,"initial RAW completed");
        end
    endtask
    task automatic no_offer(input integer clocks);
        integer k;
        begin for(k=0;k<clocks;k++)begin cycle;check(!cmd_valid,"unqualified request cannot prepare");end end
    endtask
    initial begin
        if(!$value$plusargs("CASE=%d",test_case))test_case=0;
        reset_control;
        case(test_case)
        0:begin no_offer(10);check(pending&&!commit_ready,"no frame stays pending without invented commits");initial_raw;end
        1:begin
            initial_raw;result_valid=1;avatar_ready=1;
            for(j=1;j<=9;j++)begin
                request(j%3);await_offer;check(cmd_mode==j%3&&cmd_seq==j,"RAW BOX AVATAR sequence");
                accept_command;check(active_mode==(j-1)%3,"active waits actual feedback");confirm_command;
            end
            cycle;check(request_count==9&&command_count==10&&commit_count==10&&!pending,"request/command/commit counters distinct");
        end
        2:begin
            initial_raw;capabilities=1;request(1);no_offer(8);
            check(unavailable&&pending&&active_mode==0,"missing BOX capability reports unavailable");
            capabilities=3;no_offer(8);check(!unavailable&&pending,"missing result is pending not unavailable");
            result_valid=1;accept_command;confirm_command;
        end
        3:begin
            initial_raw;result_valid=1;result_frame_id=2;request(1);no_offer(8);
            check(pending&&!unavailable,"wrong-frame result cannot be borrowed");
            result_frame_id=1;accept_command;confirm_command;
            request(2);no_offer(8);check(active_mode==1,"avatar waits asset readiness");
            avatar_ready=1;accept_command;confirm_command;
        end
        4:begin
            initial_raw;result_valid=1;avatar_ready=1;
            request(1);await_offer;
            for(j=2;j<=12;j++)request(j%3);
            check(cmd_mode==1&&cmd_seq==1&&request_seq==12&&coalesced_count==10,"held request and last desired are separate");
            accept_command;check(!cmd_valid&&active_mode==0,"held command remains active RAW until commit");
            confirm_command;await_offer;check(cmd_mode==0&&cmd_seq==12,"only latest not-yet-issued request follows");
            accept_command;confirm_command;cycle;
            check(command_count==3&&commit_count==3&&!pending,"coalesced intermediate modes never dispatched");
        end
        5:begin
            initial_raw;result_valid=1;request(1);await_offer;
            @(negedge clk);context_frame_id=2;context_slot=1;context_generation=11;context_data=~context_data;
            repeat(4)cycle;check(cmd_frame_id==1&&cmd_generation==10,"context change cannot alter exposed command");
            accept_command;confirm_command;no_offer(5);
            check(active_frame_id==1&&pending,"new context needs same-frame result");
            result_frame_id=2;await_offer;
            check(cmd_frame_id==2&&cmd_slot==1&&cmd_generation==11&&cmd_data==context_data,"latest context prepared after retirement");
            accept_command;confirm_command;cycle;check(!pending,"new frame and mode context complete");
        end
        6:begin
            initial_raw;result_valid=1;request(1);accept_command;
            @(negedge clk);commit_valid=1;commit_mode=sent_mode;commit_seq=sent_seq+1;
            commit_frame_id=sent_frame;commit_slot=sent_slot;commit_generation=sent_generation;
            cycle;check(protocol_error&&protocol_errors==1&&active_mode==0&&commit_ready,"wrong sequence cannot change active or retire command");
            @(negedge clk);commit_valid=0;
            confirm_command;check(active_mode==1&&protocol_error,"correct feedback still retires with sticky diagnostic");
        end
        7:begin
            initial_raw;request(3);check(reject_valid&&rejected_mode==3&&rejected_requests==1,"reserved mode rejected");
            check(request_seq==0&&requested_mode==0&&request_count==0,"reject cannot change desired mode or sequence");
            repeat(8)begin cycle;check(reject_valid&&!request_ready&&!cmd_valid,"held rejection backpressures request channel");end
            @(negedge clk);reject_ready=1;cycle;
            @(negedge clk);reject_ready=0;
            request(1);check(request_seq==1&&!reject_valid,"legal request after rejected event retirement");
        end
        8:begin
            initial_raw;result_valid=1;request(1);await_offer;reset_control;
            no_offer(5);check(command_count==0&&commit_count==0&&!active_valid,"reset discards unaccepted command");
            initial_raw;result_valid=1;request(1);accept_command;reset_control;
            check(!commit_ready&&!active_valid&&request_seq==0,"coordinated reset clears in-flight epoch");initial_raw;
        end
        9:begin
            initial_raw;capabilities=0;
            @(negedge clk);force dut.request_seq=32'hfffffffe;cycle;
            @(negedge clk);release dut.request_seq;
            request(1);check(request_seq==32'hffffffff,"sequence reaches unsigned maximum");
            request(2);check(request_seq==0&&requested_mode==2,"sequence wraps modulo32 without reserved mode");
            result_valid=1;avatar_ready=1;capabilities=7;
            await_offer;check(cmd_seq==0&&cmd_mode==2,"wrapped request still prepares");accept_command;confirm_command;
        end
        10:begin
            @(negedge clk);context_valid=1;await_offer;
            for(j=1;j<=300;j++)request((j*7)%3);
            check(request_seq==300&&coalesced_count==299&&cmd_seq==0,"large request burst retains last desired plus one held command");
            @(negedge clk);context_frame_id=7;context_generation=40;context_data=~context_data;result_valid=1;result_frame_id=7;avatar_ready=1;
            accept_command;confirm_command;await_offer;
            check(cmd_seq==300&&cmd_mode==0&&cmd_frame_id==7&&cmd_generation==40,"latest complete context after request burst");
            accept_command;confirm_command;cycle;check(!pending&&command_count==2,"burst does not invent intermediate commits");
        end
        11:begin
            @(negedge clk);context_valid=1;request_valid=1;request_mode=1;result_valid=1;
            cycle;check(!cmd_valid&&request_seq==1,"same-cycle request takes priority over preparation");
            @(negedge clk);request_valid=0;await_offer;
            check(cmd_mode==1&&cmd_seq==1,"prepare latest request next cycle");accept_command;confirm_command;
        end
        12:begin
            initial_raw;result_valid=1;result_empty=1;request(2);
            check(!avatar_ready,"no-face test has no material prepared");accept_command;
            check(sent_mode==2,"valid empty result qualifies AVATAR without material");confirm_command;
        end
        13:begin
            initial_raw;result_valid=1;avatar_ready=1;request(2);await_offer;
            @(negedge clk);capabilities=1;result_valid=0;avatar_ready=0;context_valid=0;
            repeat(8)cycle;check(cmd_valid&&cmd_mode==2,"qualification loss cannot retract public command");
            accept_command;confirm_command;check(active_mode==2,"consumer commits frozen validated context");
        end
        14:begin
            initial_raw;capabilities=0;request(1);
            // Accelerate intervening blocked requests, retaining an unsent desire.
            @(negedge clk);force dut.request_seq=32'hfffffffe;cycle;
            @(negedge clk);release dut.request_seq;
            request(1);request(0);
            check(request_seq==committed_seq&&requested_mode==active_mode,"new unsent request aliases committed sequence and mode");
            check(pending,"aliased unsent request must remain outstanding");
            j=coalesced_count;request(0);
            check(coalesced_count==j+1,"aliased unsent request counts when replaced");
            capabilities=7;await_offer;check(cmd_seq==1&&cmd_mode==0,"same-mode unsatisfied request still issues");
            accept_command;confirm_command;cycle;check(!pending,"latest request eventually commits after alias");
        end
        15:begin
            initial_raw;result_valid=1;avatar_ready=1;request(1);await_offer;
            request(2);
            @(negedge clk);force dut.request_seq=0;cycle;
            @(negedge clk);release dut.request_seq;
            request(1);check(request_seq==cmd_seq&&requested_mode==cmd_mode,"new desire aliases older frozen command");
            accept_command;confirm_command;
            check(pending,"older aliased commit cannot retire newest request");
            await_offer;check(cmd_seq==1&&cmd_mode==1,"newest aliased desire requires its own actual commit");
            accept_command;confirm_command;cycle;check(!pending&&commit_count==3,"alias is retired by distinct actual commit");
        end
        16:begin
            initial_raw;result_valid=1;avatar_ready=1;request(1);accept_command;
            @(negedge clk);commit_valid=1;commit_mode=sent_mode;commit_seq=sent_seq;
            commit_frame_id=sent_frame;commit_slot=sent_slot;commit_generation=sent_generation;
            request_valid=1;request_mode=2;
            cycle;check(active_mode==1&&requested_mode==2&&request_seq==2&&pending,"simultaneous actual commit cannot clear a new desire");
            @(negedge clk);commit_valid=0;request_valid=0;
            await_offer;check(cmd_mode==2&&cmd_seq==2,"new desire follows simultaneous older commit");
            accept_command;confirm_command;cycle;check(!pending,"new desire retired by own commit");
        end
        default:$fatal(1,"unknown mode case");
        endcase
        $display("DISPLAY_MODE_CONTROL_PASS case=%0d width=%0d checks=%0d",test_case,CONTEXT_WIDTH,checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"mode watchdog");end
endmodule
