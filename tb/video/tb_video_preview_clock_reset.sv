`timescale 1ns/1ps
module tb_video_preview_clock_reset #(parameter integer HOLD_KEY0_AT_BOOT=1);
    reg sys_clk=0,reset_n=0;
    wire pixel_clk,cfg_clk,locked,pixel_reset_n,cfg_reset_n,tx_reset_n;
    always #18.5185185 sys_clk=~sys_clk;
`ifdef OLD_CLOCK_RESET
    video_clock_reset #(.STARTUP_CYCLES(16)) dut(.*);
`else
    video_preview_clock_reset #(.STARTUP_CYCLES(16)) dut(.*);
`endif
    integer cases=0;
    reg protect_link=0;
    always @(negedge tx_reset_n)
        if(protect_link && locked)$fatal(1,"KEY0 must not reset the initialized HDMI link");
    task automatic check(input bit ok,input string why);
        if(ok!==1'b1)$fatal(1,"PREVIEW CLOCK RESET: %s",why);
    endtask
    task automatic await_data_release;
        begin
            wait(pixel_reset_n && cfg_reset_n);
            check(tx_reset_n,"HDMI must stay ready while data domains release");
        end
    endtask
    task automatic key_press(input integer hold_ns);
        begin
            #7;reset_n=0;#1;
            check(!pixel_reset_n&&!cfg_reset_n,"KEY0 assertion must clear data domains immediately");
            check(tx_reset_n,"KEY0 assertion must preserve HDMI reset output");
            #(hold_ns);reset_n=1;
            #1;check(!pixel_reset_n&&!cfg_reset_n,"KEY0 release cannot bypass local synchronizers");
            await_data_release();cases=cases+1;
        end
    endtask
    initial begin
        // Holding KEY0 at configuration must hold the datapath, but must not
        // prevent the independent PLL/HDMI boot sequence from completing.
        if(!HOLD_KEY0_AT_BOOT)begin #27;reset_n=1;end
        wait(locked);
        repeat(28)@(negedge cfg_clk);
        check(tx_reset_n,"HDMI boot must finish even while KEY0 holds datapath reset");
        if(HOLD_KEY0_AT_BOOT)check(!pixel_reset_n&&!cfg_reset_n,"held KEY0 must keep data domains reset");
        protect_link=1;reset_n=1;await_data_release();cases=cases+1;
        key_press(1);key_press(370);key_press(3000);
        repeat(4)key_press(13);

        // A stopped local clock cannot release its own data-domain reset.
        #7;reset_n=0;#1;
        force dut.pll.clkout1=0;
        reset_n=1;
        repeat(8)@(negedge pixel_clk);
        check(pixel_reset_n&&!cfg_reset_n&&tx_reset_n,"stopped cfg clock must delay only cfg release");
        release dut.pll.clkout1;await_data_release();cases=cases+1;
        #7;reset_n=0;#1;
        force dut.pll.clkout0=0;
        reset_n=1;
        repeat(5)@(negedge cfg_clk);
        check(cfg_reset_n&&!pixel_reset_n&&tx_reset_n,"stopped pixel clock must delay only pixel release");
        release dut.pll.clkout0;await_data_release();cases=cases+1;

        // Actual PLL loss remains a full HDMI restart, unlike KEY0 recapture.
        protect_link=0;#7;force dut.pll.lock=0;#1;
        check(!pixel_reset_n&&!cfg_reset_n&&!tx_reset_n,"PLL loss must reset both domains and HDMI");
        repeat(8)@(negedge cfg_clk);
        release dut.pll.lock;wait(locked);
        repeat(15)begin @(negedge cfg_clk);check(!tx_reset_n,"relock must repeat the startup hold");end
        wait(tx_reset_n);await_data_release();cases=cases+1;
        protect_link=1;key_press(47);
        $display("VIDEO_PREVIEW_CLOCK_RESET_PASS cases=%0d key0_link_preserved=1 pll_restart=1",cases);
        $finish;
    end
    initial begin #50000;$fatal(1,"Preview clock/reset watchdog");end
endmodule
