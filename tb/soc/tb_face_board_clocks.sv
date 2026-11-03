`timescale 1ns/1ps
// Board wiring/reset test. Vendor GPLL model is real; face implementation is
// replaced by its exact port declaration so this checks the board boundary.
module tb_face_board_clocks;
    reg ref_clk=0,sys_clk=0,reset_n=0,pixel_in=0;
    always #4 ref_clk=~ref_clk;
    always #18.518518 sys_clk=~sys_clk;
    always #12.5 pixel_in=~pixel_in;
    triha_face_full_top #(.STARTUP_CYCLES(4)) dut(
        .sys_clk(sys_clk),.rst_in(reset_n),.ref_clk_p(ref_clk),.ref_clk_n(~ref_clk),
        .pixclk_in(pixel_in),.uart_rx(1'b1),.mode_button_n(1'b1));
    real previous_edge;
    integer i;
    initial begin
        #100;reset_n=1;
        wait(dut.application_reset_n && dut.video_reset_n);
        repeat(20)@(posedge dut.face.compute_clk_i);
        previous_edge=$realtime;
        for(i=0;i<50;i=i+1)begin
            @(posedge dut.face.compute_clk_i);
            if($realtime-previous_edge<19.99 || $realtime-previous_edge>20.01)
                $fatal(1,"compute period must be 20 ns");
            previous_edge=$realtime;
        end
        @(posedge dut.face.video_clk_i);previous_edge=$realtime;
        for(i=0;i<50;i=i+1)begin
            @(posedge dut.face.video_clk_i);
            if($realtime-previous_edge<7.99 || $realtime-previous_edge>8.01)
                $fatal(1,"video period must be 8 ns");
            previous_edge=$realtime;
        end
        if(dut.boot_uart_rx.DIVISOR!=1085 || dut.boot_uart_tx.DIVISOR!=1085)
            $fatal(1,"UART divisor must match 125 MHz");
        // Exercise loss and release of application lock without resetting PHY.
        force dut.compute_pll_lock=0;
        #1;
        if(dut.face.rst_ni!==0 || dut.ingress.pixel_reset_n!==0 ||
           dut.ingress.core_reset_n!==0 || dut.boot_uart_rx.rst_ni!==0 ||
           dut.display_reset_n!==0) $fatal(1,"application reset not coordinated");
        if(dut.I_ips_ddr_top.resetn!==1) $fatal(1,"compute PLL loss reset DDR PHY");
        #50;release dut.compute_pll_lock;
        wait(dut.application_reset_n && dut.video_reset_n);
        repeat(5)@(posedge dut.face.compute_clk_i);
        $display("FACE_BOARD_CLOCK_PASS compute_ns=20 video_ns=8 samples=50 reset_loss=1");
        $finish;
    end
    // Direct interfaces belong to one domain; this also catches reassigning
    // capture/UART to compute while their consumer remains in video.
    always @(negedge ref_clk)begin
        #0.1;
        if(dut.application_reset_n)begin
            if(dut.ingress.core_clk!==dut.face.video_clk_i ||
               dut.capture_register.clk!==dut.face.video_clk_i ||
               dut.boot_uart_rx.clk_i!==dut.face.video_clk_i ||
               dut.boot_uart_tx.clk_i!==dut.face.video_clk_i)
                $fatal(1,"video-side direct interface clock mismatch");
        end
    end
    initial begin #100000;$fatal(1,"clock lock/test timeout");end
endmodule
