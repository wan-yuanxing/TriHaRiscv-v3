`timescale 1ns/1ps
`default_nettype none
module tb_display_slot_owner #(parameter integer CONTEXT_WIDTH=128);
    reg clk_i=0,rst_ni=0;
    reg submit_valid_i=0;wire submit_ready_o;
    reg submit_mode_only_i=0;reg [1:0] submit_slot_i=0,submit_mode_i=0;
    reg [31:0] submit_frame_i=1,submit_generation_i=10,submit_base_i=32'h82000000;
    reg [31:0] submit_stride_i=2400,submit_seq_i=0;
    reg [CONTEXT_WIDTH-1:0] submit_data_i=1;
    wire reject_valid_o;reg reject_ready_i=0;wire [7:0] reject_code_o;
    wire [31:0] reject_seq_o;
    wire cmd_valid_o;reg cmd_ready_i=0;wire cmd_mode_only_o;
    wire [1:0] cmd_slot_o,cmd_mode_o;
    wire [31:0] cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o;
    wire [CONTEXT_WIDTH-1:0] cmd_data_o;
    reg feedback_valid_i=0;wire feedback_ready_o;
    reg [1:0] feedback_slot_i=0,feedback_mode_i=0;
    reg [31:0] feedback_frame_i=0,feedback_generation_i=0,feedback_seq_i=0;
    wire commit_valid_o;reg commit_ready_i=0;wire commit_mode_only_o;
    wire [1:0] commit_slot_o,commit_mode_o;
    wire [31:0] commit_frame_o,commit_generation_o,commit_seq_o;
    reg retire_valid_i=0;wire retire_ready_o;reg [1:0] retire_slot_i=0;
    reg [31:0] retire_frame_i=0,retire_generation_i=0;
    wire release_valid_o;reg release_ready_i=0;wire [1:0] release_slot_o;
    wire [31:0] release_frame_o,release_generation_o;
    wire active_valid_o;wire [1:0] active_slot_o,active_mode_o;
    wire [31:0] active_frame_o,active_generation_o,active_base_o,active_stride_o,active_seq_o;
    wire [CONTEXT_WIDTH-1:0] active_data_o;
    wire [2:0] slot_free_o;wire protocol_error_o;wire [7:0] error_code_o;
    wire [31:0] submits_o,commits_o,releases_o,rejected_o;
    reg [1:0] sent_slot,sent_mode;reg sent_mode_only;
    reg [31:0] sent_frame,sent_generation,sent_seq;
    reg [CONTEXT_WIDTH-1:0] sent_data;
    reg expected_mode_only;reg [1:0] expected_slot,expected_mode;
    reg [31:0] expected_frame,expected_generation,expected_base,expected_stride,expected_seq;
    reg [CONTEXT_WIDTH-1:0] expected_data;
    integer test_case=0,checks=0,j,n;
    reg [31:0] rng=32'h4f20a19d;
    reg [2:0] owned=0;
    reg cmd_held=0,commit_held=0,release_held=0,reject_held=0;
    reg [CONTEXT_WIDTH+165:0] held_command;
    reg [100:0] held_commit;
    reg [65:0] held_release;
    reg [39:0] held_reject;
    always #4 clk_i=~clk_i;
    display_slot_owner #(.CONTEXT_WIDTH(CONTEXT_WIDTH)) dut(.*);
    task automatic check(input bit ok,input string message);
        begin checks++;if(ok!==1'b1)$fatal(1,"DISPLAY_SLOTS case=%0d: %s",test_case,message);end
    endtask
    task automatic cycle;begin @(posedge clk_i);#1;end endtask
    // Check only public handshakes, without reading DUT state or counters.
    always @(posedge clk_i)begin
        if(!rst_ni)begin cmd_held<=0;commit_held<=0;release_held<=0;reject_held<=0;end
        else begin
            if(cmd_held)check(cmd_valid_o &&
                {cmd_mode_only_o,cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,cmd_data_o}===held_command,
                "command payload changed while blocked");
            if(commit_held)check(commit_valid_o &&
                {commit_mode_only_o,commit_slot_o,commit_mode_o,commit_frame_o,commit_generation_o,commit_seq_o}===held_commit,
                "commit event changed while blocked");
            if(release_held)check(release_valid_o &&
                {release_slot_o,release_frame_o,release_generation_o}===held_release,"release event changed while blocked");
            if(reject_held)check(reject_valid_o && {reject_code_o,reject_seq_o}===held_reject,
                "rejection changed while blocked");
            cmd_held<=cmd_valid_o&&!cmd_ready_i;
            commit_held<=commit_valid_o&&!commit_ready_i;
            release_held<=release_valid_o&&!release_ready_i;
            reject_held<=reject_valid_o&&!reject_ready_i;
            held_command<={cmd_mode_only_o,cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,cmd_data_o};
            held_commit<={commit_mode_only_o,commit_slot_o,commit_mode_o,commit_frame_o,commit_generation_o,commit_seq_o};
            held_release<={release_slot_o,release_frame_o,release_generation_o};
            held_reject<={reject_code_o,reject_seq_o};
        end
    end
    task automatic check_refs;
        check(slot_free_o===~owned,"slot reused before complete retirement and release ACK");
    endtask
    task automatic reset_owner;
        begin
            @(negedge clk_i);rst_ni=0;submit_valid_i=0;feedback_valid_i=0;retire_valid_i=0;
            cmd_ready_i=0;commit_ready_i=0;release_ready_i=0;reject_ready_i=0;owned=0;
            cycle;check(!active_valid_o&&!cmd_valid_o&&!commit_valid_o&&!release_valid_o&&!reject_valid_o,
                "coordinated reset clears events and identity");
            check(slot_free_o==7&&!protocol_error_o&&submits_o==0&&commits_o==0&&releases_o==0,
                "coordinated reset clears references and counters");
            @(negedge clk_i);rst_ni=1;cycle;
        end
    endtask
    task automatic offer(input bit mode_only,input integer slot,input integer frame,
                         input integer gen,input integer mode,input reg [31:0] seq,
                         input reg [CONTEXT_WIDTH-1:0] data);
        integer waited;
        begin
            @(negedge clk_i);submit_mode_only_i=mode_only;submit_slot_i=slot;submit_frame_i=frame;
            submit_generation_i=gen;submit_base_i=32'h82000000+slot*32'h200000;
            submit_stride_i=2400;submit_mode_i=mode;submit_seq_i=seq;
            submit_data_i=data^({CONTEXT_WIDTH{1'b1}}<<32);
            expected_mode_only=mode_only;expected_slot=slot;expected_mode=mode;
            expected_frame=frame;expected_generation=gen;expected_base=submit_base_i;
            expected_stride=2400;expected_seq=seq;expected_data=submit_data_i;
            submit_valid_i=1;waited=0;
            while(!submit_ready_o)begin cycle;waited++;check(waited<40,"submission readiness timeout");end
            cycle;@(negedge clk_i);submit_valid_i=0;
            // The producer may reuse its input bus immediately after ACK.
            submit_data_i=~expected_data;submit_frame_i=~expected_frame;
            submit_seq_i=~expected_seq;submit_base_i=~expected_base;
        end
    endtask
    task automatic take_command(input bit is_new);
        integer waited;
        begin
            waited=0;while(!cmd_valid_o)begin cycle;waited++;check(waited<40,"missing frozen command");end
            check({cmd_mode_only_o,cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,cmd_data_o}===
                  {expected_mode_only,expected_slot,expected_mode,expected_frame,expected_generation,expected_base,expected_stride,expected_seq,expected_data},
                  "command must freeze every submitted field across input reuse");
            sent_slot=cmd_slot_o;sent_mode=cmd_mode_o;sent_frame=cmd_frame_o;
            sent_generation=cmd_generation_o;sent_seq=cmd_seq_o;sent_data=cmd_data_o;sent_mode_only=cmd_mode_only_o;
            if(is_new)owned[sent_slot]=1;
            check_refs;
            repeat(3)cycle;
            @(negedge clk_i);cmd_ready_i=1;cycle;
            @(negedge clk_i);cmd_ready_i=0;
        end
    endtask
    task automatic feedback;
        begin
            @(negedge clk_i);feedback_valid_i=1;feedback_slot_i=sent_slot;feedback_frame_i=sent_frame;
            feedback_generation_i=sent_generation;feedback_seq_i=sent_seq;feedback_mode_i=sent_mode;
            #1;check(feedback_ready_o,"feedback receiver must drain");cycle;
            check(commit_valid_o&&commit_slot_o==sent_slot&&commit_frame_o==sent_frame&&
                commit_generation_o==sent_generation&&commit_seq_o==sent_seq&&commit_mode_o==sent_mode&&
                commit_mode_only_o==sent_mode_only,"complete commit event identity");
            check(active_valid_o&&active_slot_o==sent_slot&&active_frame_o==sent_frame&&
                active_generation_o==sent_generation&&active_mode_o==sent_mode&&active_seq_o==sent_seq&&
                active_data_o===sent_data,"active changes only on actual matching feedback");
            check(active_base_o==32'h82000000+sent_slot*32'h200000&&active_stride_o==2400,"active raw layout");
            @(negedge clk_i);feedback_valid_i=0;repeat(3)cycle;check_refs;
        end
    endtask
    task automatic ack_commit;
        begin
            @(negedge clk_i);commit_ready_i=1;cycle;check(!commit_valid_o,"commit ACK consumes event");
            @(negedge clk_i);commit_ready_i=0;
        end
    endtask
    task automatic new_frame(input integer slot,input integer frame,input integer gen,input reg [31:0] seq);
        begin offer(0,slot,frame,gen,0,seq,frame);take_command(1);feedback;ack_commit;end
    endtask
    task automatic retire(input integer slot,input integer frame,input integer gen);
        begin
            @(negedge clk_i);retire_valid_i=1;retire_slot_i=slot;retire_frame_i=frame;retire_generation_i=gen;
            #1;check(retire_ready_o,"retirement receiver ready");cycle;
            @(negedge clk_i);retire_valid_i=0;
            check(release_valid_o&&release_slot_o==slot&&release_frame_o==frame&&release_generation_o==gen,
                "release must retain exact old identity");
            check_refs;repeat(4)cycle;check_refs;
        end
    endtask
    task automatic ack_release;
        reg [1:0] old_slot;
        begin
            check(release_valid_o,"release event required before ACK");old_slot=release_slot_o;
            @(negedge clk_i);release_ready_i=1;cycle;owned[old_slot]=0;
            check(!release_valid_o,"release ACK consumed");check_refs;
            @(negedge clk_i);release_ready_i=0;
        end
    endtask
    task automatic rejection(input reg [7:0] code,input reg [31:0] seq);
        begin
            check(reject_valid_o&&reject_code_o==code&&reject_seq_o==seq,"held rejection reason and seq");
            check(!cmd_valid_o&&!protocol_error_o,"invalid submission cannot publish or poison active");
            repeat(4)cycle;check_refs;
            @(negedge clk_i);reject_ready_i=1;cycle;
            @(negedge clk_i);reject_ready_i=0;
        end
    endtask
    initial begin
        if(!$value$plusargs("CASE=%d",test_case))test_case=0;
        reset_owner;
        case(test_case)
        0:begin
            offer(0,0,1,10,0,1,1);
            check(slot_free_o==6&&!active_valid_o,"accepted frame is reserved, not yet active");
            take_command(1);repeat(4)cycle;check(!active_valid_o,"command ACK is not commit");
            feedback;check(!submit_ready_o,"commit event backpressure protects identity");ack_commit;
            for(j=1;j<=3;j=j+1)begin
                offer(1,0,1,10,j%3,j+1,1);take_command(0);feedback;
                check(!release_valid_o&&slot_free_o==6,"MODE never releases current frame");ack_commit;
            end
            check(commits_o==4&&submits_o==4&&releases_o==0,"mode and frame accounting");
            new_frame(1,2,11,5);check(slot_free_o==4&&!release_valid_o,"commit alone never frees old slot");
            retire(0,1,10);offer(0,0,3,12,0,6,3);rejection(5,6);ack_release;
            new_frame(2,3,12,7);retire(1,2,11);ack_release;
            new_frame(0,4,13,8);retire(2,3,12);ack_release;
        end
        1:begin
            new_frame(0,1,10,0);
            offer(0,0,2,11,0,1,2);rejection(5,1);
            offer(1,0,2,10,1,2,1);rejection(6,2);
            offer(1,0,1,11,1,3,1);rejection(6,3);
            offer(1,0,1,10,1,4,2);rejection(6,4);
            offer(1,1,1,10,1,5,1);rejection(6,5);
            offer(0,3,2,11,0,6,2);rejection(2,6);
            offer(0,1,0,11,0,7,2);rejection(2,7);
            offer(0,1,2,11,3,8,2);rejection(4,8);
            check(active_frame_o==1&&slot_free_o==6&&rejected_o==8,"rejections preserve active and refs");
        end
        2:begin
            new_frame(0,1,10,0);new_frame(1,2,11,1);new_frame(2,3,12,2);
            check(slot_free_o==0,"all three references remain protected");
            retire(0,1,10);
            check(!retire_ready_o,"second retirement blocked behind release event");
            repeat(8)cycle;check_refs;ack_release;
            retire(1,2,11);ack_release;check(slot_free_o==3,"only active slot remains protected");
            offer(1,2,3,12,2,32'hffffffff,3);take_command(0);feedback;ack_commit;
            offer(1,2,3,12,0,0,3);take_command(0);
            check(active_seq_o==32'hffffffff,"wrapped seq cannot impersonate commit");feedback;ack_commit;
        end
        3:begin
            new_frame(0,1,10,1);offer(0,1,2,11,0,2,2);take_command(1);
            fork
                feedback;
                begin
                    @(negedge clk_i);retire_valid_i=1;retire_slot_i=0;retire_frame_i=1;retire_generation_i=10;
                    cycle;@(negedge clk_i);retire_valid_i=0;
                end
            join
            check(release_valid_o&&!protocol_error_o,"same-edge old retirement and new commit");
            @(negedge clk_i);retire_valid_i=0;ack_commit;ack_release;
        end
        4:begin
            new_frame(0,1,10,1);offer(0,1,2,11,0,2,2);take_command(1);
            @(negedge clk_i);feedback_valid_i=1;feedback_slot_i=1;feedback_frame_i=2;
            feedback_generation_i=11;feedback_seq_i=99;feedback_mode_i=0;cycle;
            check(protocol_error_o&&error_code_o==8'he2&&!commit_valid_o&&active_frame_o==1,
                "wrong seq cannot commit or lose pending transaction");
            @(negedge clk_i);feedback_valid_i=0;feedback;ack_commit;
            check(!submit_ready_o&&active_frame_o==2,"sticky error blocks new work but drains accepted command");
            retire(0,1,10);ack_release;
        end
        5:begin
            new_frame(0,1,10,1);
            @(negedge clk_i);retire_valid_i=1;retire_slot_i=0;retire_frame_i=1;retire_generation_i=10;cycle;
            check(protocol_error_o&&error_code_o==8'he3&&!release_valid_o&&slot_free_o==6,
                "active reference cannot retire early");
            @(negedge clk_i);retire_valid_i=0;feedback_valid_i=1;cycle;
            check(error_code_o==8'he3,"first error is sticky");
            @(negedge clk_i);feedback_valid_i=0;reset_owner;
            new_frame(0,5,20,1);new_frame(1,6,21,2);retire(0,5,20);ack_release;
            @(negedge clk_i);retire_valid_i=1;retire_slot_i=0;retire_frame_i=5;retire_generation_i=20;cycle;
            check(protocol_error_o&&!release_valid_o&&slot_free_o==5,"duplicate retirement is rejected");
        end
        6:begin
            // Mutate descriptors before their only acceptance edge.
            for(j=0;j<8;j=j+1)begin
                reset_owner;
                @(negedge clk_i);submit_valid_i=1;submit_mode_only_i=0;submit_slot_i=0;submit_frame_i=1;
                submit_generation_i=0;submit_base_i=32'h82000000;submit_stride_i=2400;
                submit_mode_i=0;submit_seq_i=7;submit_data_i=1;
                case(j)
                    0:submit_base_i=32'h82000010;
                    1:submit_stride_i=2416;
                    2:submit_data_i='x;
                    3:submit_frame_i='x;
                    4:submit_mode_only_i=1'bx;
                    5:submit_slot_i=2'bx;
                    6:submit_generation_i='x;
                    7:submit_mode_i=2'bx;
                endcase
                cycle;@(negedge clk_i);submit_valid_i=0;
                rejection(j<2?8'd3:8'd1,7);check(slot_free_o==7,"bad metadata creates no reservation");
            end
        end
        7:begin
            // Coordinated reset at each externally visible held phase.
            offer(0,0,1,10,0,1,1);reset_owner;
            offer(0,0,1,10,0,1,1);take_command(1);reset_owner;
            offer(0,0,1,10,0,1,1);take_command(1);feedback;reset_owner;
            new_frame(0,1,10,1);new_frame(1,2,11,2);retire(0,1,10);reset_owner;
            new_frame(2,9,30,1);check(slot_free_o==3&&active_frame_o==9,"reset allows new generation");
        end
        8:begin
            // Deterministic three-slot stress with changing contexts and wrap.
            new_frame(0,1,100,32'hffffffe0);
            for(n=1;n<=96;n=n+1)begin
                rng=(rng<<1)^(rng[31]?32'h04c11db7:0);
                repeat(rng[2:0])cycle;
                new_frame(n%3,n+1,n+100,32'hffffffe0+n);
                repeat(rng[5:3])cycle;
                retire((n-1)%3,n,n+99);ack_release;
                offer(1,n%3,n+1,n+100,(n%2)+1,n,n+1);take_command(0);feedback;ack_commit;
                check_refs;check(!protocol_error_o,"stress protocol remains healthy");
            end
            check(commits_o==193&&releases_o==96,"stress conservation of refs and commits");
        end
        9:begin
            // Feedback before downstream acceptance is a protocol error.
            offer(0,0,1,10,0,1,1);owned=1;
            @(negedge clk_i);feedback_valid_i=1;feedback_slot_i=0;feedback_frame_i=1;
            feedback_generation_i=10;feedback_seq_i=1;feedback_mode_i=0;cycle;
            check(protocol_error_o&&error_code_o==8'he1&&cmd_valid_o&&!active_valid_o,
                "unsent command cannot commit, and published offer remains held");
            @(negedge clk_i);feedback_valid_i=0;take_command(0);feedback;ack_commit;
            check_refs;
        end
        10:begin
            new_frame(0,1,10,1);
            offer(1,0,1,10,1,2,1);take_command(0);feedback;ack_commit;
            @(negedge clk_i);retire_valid_i=1;retire_slot_i=0;retire_frame_i=1;retire_generation_i=10;
            cycle;
            check(protocol_error_o&&error_code_o==8'he3&&!release_valid_o&&slot_free_o==6,
                "MODE commit must not make active reference eligible for retirement");
            @(negedge clk_i);retire_valid_i=0;check_refs;
        end
        default:$fatal(1,"unknown case");
        endcase
        $display("DISPLAY_SLOTS_PASS case=%0d width=%0d checks=%0d",test_case,CONTEXT_WIDTH,checks);$finish;
    end
    initial begin #2000000;$fatal(1,"DISPLAY_SLOTS watchdog");end
endmodule
`default_nettype wire
