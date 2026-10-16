`timescale 1ns/1ps
module tb_clock_reset;
    reg sys_clk = 0, reset_n = 1;
    wire pixel_clk, cfg_clk, locked, pixel_reset_n, cfg_reset_n, tx_reset_n;
    integer i;
    always #18.518518518 sys_clk = ~sys_clk;
    video_clock_reset #(.STARTUP_CYCLES(4)) dut (
        .sys_clk(sys_clk), .reset_n(reset_n), .pixel_clk(pixel_clk),
        .cfg_clk(cfg_clk), .locked(locked), .pixel_reset_n(pixel_reset_n),
        .cfg_reset_n(cfg_reset_n), .tx_reset_n(tx_reset_n));
    task check_async_reset;
        begin
            #0.1;
            if ({pixel_reset_n,cfg_reset_n,tx_reset_n} !== 3'b000)
                $fatal(1,"Reset/PLL-loss must asynchronously clear local resets");
        end
    endtask
    task check_startup;
        begin
            wait(cfg_reset_n === 1'b1);
            for(i=0;i<3;i=i+1) begin
                @(posedge cfg_clk); #0.1;
                if(tx_reset_n !== 1'b0) $fatal(1,"TX reset released too early");
            end
            @(posedge cfg_clk); #0.1;
            if(tx_reset_n !== 1'b1) $fatal(1,"TX reset startup count incorrect");
            if(pixel_reset_n !== 1'b1) $fatal(1,"Pixel domain did not release");
        end
    endtask
    initial begin
        #1; reset_n=0; check_async_reset();
        #10; reset_n=1;
        check_startup();
        #7; reset_n=0;
        check_async_reset();
        #137; reset_n=1;
        check_startup();
        #7; force dut.locked = 0;
        check_async_reset();
        #137; release dut.locked;
        check_startup();
        $display("VIDEO_CLOCK_RESET_PASS external_reset=1 pll_loss=1 startup_cycles=4");
        $finish;
    end
    initial begin #1000000; $fatal(1,"Clock/reset test timeout"); end
endmodule
