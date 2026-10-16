`timescale 1ns/1ps
module tb_pll;
    reg reference_clk = 0;
    wire pixel_clk, config_clk, locked;
    realtime previous, elapsed;
    integer i;
    always #18.518518518 reference_clk = ~reference_clk;
    video_pll dut (.clkin1(reference_clk), .clkout0(pixel_clk),
                   .clkout1(config_clk), .lock(locked));
    initial begin
        wait(locked === 1'b1);
        repeat(10) @(posedge pixel_clk);
        previous = $realtime;
        for(i=0;i<100;i=i+1) begin
            @(posedge pixel_clk);
            elapsed = $realtime - previous;
            if(elapsed < 24.99 || elapsed > 25.01)
                $fatal(1,"Pixel PLL period %f ns, expected 25",elapsed);
            previous = $realtime;
        end
        @(posedge config_clk);
        previous = $realtime;
        for(i=0;i<100;i=i+1) begin
            @(posedge config_clk);
            elapsed = $realtime - previous;
            if(elapsed < 99.98 || elapsed > 100.02)
                $fatal(1,"Config PLL period %f ns, expected 100",elapsed);
            previous = $realtime;
        end
        $display("VIDEO_PLL_PASS pixel_period_ns=25 config_period_ns=100 locked=1");
        $finish;
    end
    initial begin #1000000; $fatal(1,"PLL lock/test timeout"); end
endmodule
