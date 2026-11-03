`timescale 1ns/1ps
`include "video_cfg.vh"
`include "video_display.vh"
module tb_display_record_guard;
    reg clk_i=0,rst_ni=0,start_valid_i=0,result_ready_i=0;
    always #4 clk_i=~clk_i;
    reg [5119:0] record_i=0;
    reg [1:0] mode_i=1;
    reg [2:0] modes_i=3'b111;
    reg asset_ready_i=1;
    reg [31:0] asset_id_i=0,asset_generation_i=0;
    wire start_ready_o,result_valid_o;
    wire [7:0] result_code_o;
    display_record_guard dut(.*);
    integer cases=0,lane_index,point_index,base;

    task automatic set_word(input integer index,input [31:0] value);
        record_i[index*32+:32]=value;
    endtask
    task automatic record_base(input [15:0] mask);
        begin
            record_i=0;mode_i=1;
            set_word(0,32'h00010000);set_word(1,640);set_word(2,0);
            set_word(3,17);set_word(4,23);set_word(5,`VIDEO_FRAME_SLOT_A);
            set_word(6,`VIDEO_FRAME_RAW_STRIDE);set_word(7,800);set_word(8,600);
            set_word(9,mask==0?3:1);set_word(10,17);set_word(11,23);set_word(12,{16'b0,mask});
        end
    endtask
    task automatic valid_box(input integer index);
        begin
            // Signed coordinates crossing zero: x=-3..4, y=-7..9.
            set_word(32+8*index,32'hfff9fffd);
            set_word(33+8*index,32'h00090004);
        end
    endtask
    task automatic check_result(input [7:0] expected,input integer latency);
        integer elapsed;
        begin
            @(negedge clk_i);
            if(!start_ready_o)$fatal(1,"GUARD_START_NOT_READY");
            start_valid_i=1;
            @(posedge clk_i);#1;
            @(negedge clk_i);start_valid_i=0;elapsed=0;
            while(!result_valid_o&&elapsed<30)begin
                @(posedge clk_i);#1;elapsed=elapsed+1;
            end
            if(!result_valid_o||result_code_o!==expected||elapsed!=latency)
                $fatal(1,"GUARD_RESULT case=%0d expected=%h/%0d got=%h/%0d",cases,expected,latency,result_code_o,elapsed);
            // Backpressure must hold the response and reject a new command.
            @(negedge clk_i);start_valid_i=1;
            repeat(3)begin
                @(posedge clk_i);#1;
                if(!result_valid_o||result_code_o!==expected||start_ready_o)
                    $fatal(1,"GUARD_RESPONSE_NOT_HELD");
            end
            @(negedge clk_i);start_valid_i=0;result_ready_i=1;
            @(negedge clk_i);result_ready_i=0;
            if(result_valid_o||!start_ready_o)$fatal(1,"GUARD_RESULT_NOT_RELEASED");
            cases=cases+1;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk_i);rst_ni=1;
        record_base(0);check_result(0,17);
        for(lane_index=0;lane_index<16;lane_index=lane_index+1)begin
            base=32+lane_index*8;
            record_base(16'b1<<lane_index);valid_box(lane_index);check_result(0,17);
            set_word(base+1,32'h0009fffd);check_result(8'h12,2+lane_index); // zero width
            set_word(base+1,32'hfff80004);check_result(8'h12,2+lane_index); // inverted height
            valid_box(lane_index);set_word(base+2,32'h20);check_result(8'h12,2+lane_index);
            record_base(0);valid_box(lane_index);check_result(8'h12,2+lane_index); // absent box must be zero
            for(point_index=0;point_index<5;point_index=point_index+1)begin
                record_base(16'b1<<lane_index);valid_box(lane_index);
                set_word(base+3+point_index,32'hfffe0003);check_result(8'h12,2+lane_index);
                set_word(base+2,32'b1<<point_index);check_result(0,17);
            end
        end
        record_base(16'hffff);
        for(lane_index=0;lane_index<16;lane_index=lane_index+1)valid_box(lane_index);
        check_result(0,17);
        set_word(32+3*8+1,32'hfff9fffd);set_word(32+12*8+1,32'hfff9fffd);
        check_result(8'h12,5); // first invalid lane decides completion time
        set_word(0,0);check_result(8'h10,1); // header error has priority
        record_base(0);mode_i=3;check_result(8'h14,1);
        record_base(0);record_i[5119]=1'bx;check_result(1,1);
        // A record may wait for its avatar after the lease starts.
        record_base(1);valid_box(0);mode_i=2;asset_ready_i=0;
        asset_id_i=7;asset_generation_i=9;
        set_word(9,25);set_word(14,7);set_word(15,9);
        set_word(16,32'h82600000);set_word(17,262144);
        set_word(18,256);set_word(19,256);set_word(20,1024);
        set_word(21,0);set_word(22,32'h01000100);
        @(negedge clk_i);start_valid_i=1;
        @(negedge clk_i);start_valid_i=0;
        repeat(9)begin
            @(posedge clk_i);#1;
            if(result_valid_o||start_ready_o)$fatal(1,"GUARD_ASSET_WAIT");
        end
        @(negedge clk_i);asset_ready_i=1;
        base=0;
        while(!result_valid_o&&base<25)begin @(posedge clk_i);#1;base=base+1;end
        if(!result_valid_o||result_code_o!==0||base!=17)$fatal(1,"GUARD_AFTER_ASSET_WAIT");
        repeat(3)begin
            @(posedge clk_i);#1;
            if(!result_valid_o||result_code_o!==0||start_ready_o)$fatal(1,"GUARD_WAIT_RESPONSE_HOLD");
        end
        @(negedge clk_i);result_ready_i=1;
        @(negedge clk_i);result_ready_i=0;cases=cases+1;
        // Abort a pending invalid final lane, then accept a fresh clean record.
        record_base(0);set_word(32+15*8,1);
        @(negedge clk_i);start_valid_i=1;
        @(negedge clk_i);start_valid_i=0;
        repeat(5)@(negedge clk_i);
        rst_ni=0;#1;
        if(result_valid_o||start_ready_o)$fatal(1,"GUARD_RESET_PENDING");
        repeat(3)@(negedge clk_i);rst_ni=1;
        record_base(0);check_result(0,17);
        $display("DISPLAY_RECORD_GUARD_PASS cases=%0d",cases);$finish;
    end
    initial begin #1000000;$fatal(1,"GUARD_WATCHDOG");end
endmodule
