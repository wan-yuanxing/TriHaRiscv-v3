`timescale 1ns/1ps
module tb_board_smoke;
    reg sys_clk=0, rst_in=1;
    wire pix_clk, hs_out,vs_out,de_out,rstn_out,hd_scl;
    tri1 hd_sda;
    wire [7:0] r_out,g_out,b_out;
    wire hdmi_int_led,heart_beat_led,ddr_init_done,init_over_rx;
    integer x,y,pixel;
    reg [23:0] expected;
    video_board_smoke_top dut(.*);
    always #18.5185185 sys_clk=~sys_clk;
    initial begin
        #1; rst_in=0;
        repeat(5) @(negedge sys_clk);
        rst_in=1;
        wait(rstn_out===1);
        // Pick the next complete raster, independent of the I2C initialization.
        @(posedge vs_out);
        @(negedge vs_out);
        @(posedge de_out);
        #1;
        for(pixel=0;pixel<1056*628;pixel=pixel+1) begin
            x=pixel%1056; y=pixel/1056;
            if(de_out !== (x<800 && y<600) ||
               hs_out !== (x>=840 && x<968) ||
               vs_out !== (y>=601 && y<605))
                $fatal(1,"Board output control mismatch at %d,%d",x,y);
            expected=0;
            if(x<800 && y<600) case(x/100)
                0:expected=24'hffffff; 1:expected=24'hffff00;
                2:expected=24'h00ffff; 3:expected=24'h00ff00;
                4:expected=24'hff00ff; 5:expected=24'hff0000;
                6:expected=24'h0000ff; 7:expected=24'h000000;
            endcase
            if({r_out,g_out,b_out} !== expected)
                $fatal(1,"Board RGB mismatch at %d,%d",x,y);
            @(posedge pix_clk); #1;
        end
        // No device is attached: status must report an initialization fault.
        if(init_over_rx !== 1 || hdmi_int_led !== 0)
            $fatal(1,"Absent transmitter status is not error=1/done=0");
        #3; rst_in=0; #1;
        if(rstn_out !== 0 || de_out !== 0 || {r_out,g_out,b_out} !== 0)
            $fatal(1,"Asynchronous board reset did not blank pixels/reassert reset");
        $display("VIDEO_BOARD_SMOKE_PASS raster_pixels=663168 no_rx_dependency=1 no_device_error=1");
        $finish;
    end
    initial begin #60000000; $fatal(1,"Board smoke integration timeout"); end
endmodule
