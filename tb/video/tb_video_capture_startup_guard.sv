`timescale 1ns/1ps
module tb_video_capture_startup_guard #(
    parameter integer TEST_FRAMES=128
);
    reg pixel_clk=0,reset_n=0,mode_good=1,rx_ready=1;
    reg frame_start=0,frame_end=0,frame_good=0;
    wire capture_ready;
    integer n,checks=0;
    always #12.5 pixel_clk=~pixel_clk;
    video_capture_startup_guard #(.STABLE_FRAMES(TEST_FRAMES)) dut(.*);
    task automatic check(input bit ok,input string message);
        begin
            checks=checks+1;
            if(ok!==1'b1)$fatal(1,"STARTUP GUARD: %s",message);
        end
    endtask
    task automatic cycle;
        begin @(posedge pixel_clk);#1;end
    endtask
    task automatic reset_guard;
        begin
            @(negedge pixel_clk);reset_n=0;mode_good=1;rx_ready=1;
            frame_start=0;frame_end=0;frame_good=0;
            #1;check(!capture_ready,"asynchronous reset clears readiness");
            repeat(3)cycle;
            @(negedge pixel_clk);reset_n=1;
            cycle;
        end
    endtask
    task automatic start_frame;
        begin @(negedge pixel_clk);frame_start=1;cycle;
            @(negedge pixel_clk);frame_start=0;cycle;end
    endtask
    task automatic close_frame(input bit good);
        begin @(negedge pixel_clk);frame_end=1;frame_good=good;cycle;
            @(negedge pixel_clk);frame_end=0;frame_good=0;cycle;end
    endtask
    task automatic full_frame(input bit good);
        begin start_frame;repeat(3)cycle;close_frame(good);end
    endtask
    task automatic earn_ready;
        begin
            for(n=0;n<TEST_FRAMES;n=n+1)begin
                check(!capture_ready,"must wait all complete frames");
                start_frame;check(!capture_ready,"frame start cannot complete warmup");
                close_frame(1);
                check(capture_ready==(n==TEST_FRAMES-1),"exact completed-frame threshold");
            end
        end
    endtask
    initial begin
        reset_guard;
        repeat(8)close_frame(1);
        check(!capture_ready,"orphan EOF cannot count as a complete frame");
        earn_ready;
        // Pixel color is deliberately absent from this interface: a legal
        // black frame obeys exactly the same qualification as a bright frame.
        repeat(300)full_frame(1);
        check(capture_ready,"counter saturates while input stays healthy");
        @(negedge pixel_clk);mode_good=0;cycle;
        check(!capture_ready,"mode loss immediately revokes readiness");
        @(negedge pixel_clk);mode_good=1;
        close_frame(1);check(!capture_ready,"recovery halfway through frame cannot count");
        earn_ready;
        full_frame(0);check(!capture_ready,"bad EOF restarts consecutive qualification");
        earn_ready;
        @(negedge pixel_clk);rx_ready=0;cycle;
        check(!capture_ready,"RX readiness loss revokes warmup");
        @(negedge pixel_clk);rx_ready=1;
        start_frame;
        @(negedge pixel_clk);mode_good=0;cycle;
        @(negedge pixel_clk);mode_good=1;
        close_frame(1);check(!capture_ready,"mid-frame health loss discards that interval");
        earn_ready;
        @(negedge pixel_clk);mode_good=1'bx;cycle;
        check(capture_ready===1'b0,"unknown health cannot retain readiness");
        @(negedge pixel_clk);mode_good=1;
        earn_ready;
        reset_guard;earn_ready;
        $display("VIDEO_CAPTURE_STARTUP_GUARD_PASS frames=%0d checks=%0d",TEST_FRAMES,checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"startup guard watchdog");end
endmodule
