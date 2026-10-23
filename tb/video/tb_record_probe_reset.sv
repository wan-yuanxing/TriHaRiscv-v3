`timescale 1ns/1ps
// Manual, independent clocks: no access to the synchronizer implementation.
module tb_record_probe_reset;
    reg clk_i=0,pixel_clk=0,rst_ni=1,pixel_reset_n=1;
    reg core_scan_i=1,core_shift_i=1,core_capture_i=1;
    reg pixel_scan_i=1,pixel_shift_i=1,pixel_capture_i=1;
    wire core_scan_o,pixel_scan_o;
    video_record_probe u_probe(.*);
    integer checks=0;
    task tick_core;begin #3;clk_i=1;#1;clk_i=0;#1;end endtask
    task tick_pixel;begin #3;pixel_clk=1;#1;pixel_clk=0;#1;end endtask
    task clear_core;begin
        if(u_probe.u_pipeline.rst_ni!==0 || u_probe.core_input_q!==0 ||
           u_probe.core_output_q!==0 || core_scan_o!==0)
            $fatal(1,"PROBE_RESET core not held/cleared");
        checks=checks+1;
    end endtask
    task clear_pixel;begin
        if(u_probe.u_pipeline.pixel_reset_n!==0 || u_probe.pixel_input_q!==0 ||
           u_probe.pixel_output_q!==0 || pixel_scan_o!==0)
            $fatal(1,"PROBE_RESET pixel not held/cleared");
        checks=checks+1;
    end endtask
    initial begin
        #1;rst_ni=0;pixel_reset_n=0;#1;clear_core();clear_pixel();
        // Releasing core cannot release the stopped pixel domain.
        rst_ni=1;#1;clear_core();clear_pixel();
        tick_core();clear_core();clear_pixel();
        tick_core();
        if(u_probe.u_pipeline.rst_ni!==1 || u_probe.core_input_q!==0 || u_probe.core_output_q!==0)
            $fatal(1,"PROBE_RESET core second edge boundary");
        tick_core();
        if(u_probe.core_input_q===0 || u_probe.core_output_q===0)
            $fatal(1,"PROBE_RESET core third edge did not work");
        clear_pixel();
        pixel_reset_n=1;#1;clear_pixel();tick_core();clear_pixel();
        tick_pixel();clear_pixel();tick_pixel();
        if(u_probe.u_pipeline.pixel_reset_n!==1 || u_probe.pixel_input_q!==0 || u_probe.pixel_output_q!==0)
            $fatal(1,"PROBE_RESET pixel second edge boundary");
        tick_pixel();
        if(u_probe.pixel_input_q===0 || u_probe.pixel_output_q===0)
            $fatal(1,"PROBE_RESET pixel third edge did not work");
        // Core-only pulse, shorter than a clock period, must assert at rest.
        #1;rst_ni=0;#1;clear_core();
        if(u_probe.u_pipeline.pixel_reset_n!==1 || u_probe.pixel_input_q===0)
            $fatal(1,"PROBE_RESET core affected pixel");
        rst_ni=1;#1;clear_core();tick_pixel();clear_core();
        tick_core();clear_core();tick_core();tick_core();
        if(u_probe.core_input_q===0)$fatal(1,"PROBE_RESET core did not restart");
        #1;pixel_reset_n=0;#1;clear_pixel();
        if(u_probe.u_pipeline.rst_ni!==1 || u_probe.core_input_q===0)
            $fatal(1,"PROBE_RESET pixel affected core");
        pixel_reset_n=1;#1;clear_pixel();tick_core();clear_pixel();
        tick_pixel();clear_pixel();tick_pixel();tick_pixel();
        if(u_probe.pixel_input_q===0)$fatal(1,"PROBE_RESET pixel did not restart");
        $display("PROBE_RESET_PASS checks=%0d",checks);$finish;
    end
    initial begin #10000;$fatal(1,"PROBE_RESET timeout");end
endmodule
