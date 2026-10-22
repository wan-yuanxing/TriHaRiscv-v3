`timescale 1ns/1ps
module tb_record_probe_idle;
    reg clk_i=0,pixel_clk=0,rst_ni=0,pixel_reset_n=0;
    reg core_capture_i=0,pixel_capture_i=0;
    wire core_scan_o,pixel_scan_o;
    always #4 clk_i=~clk_i;
    always #12.5 pixel_clk=~pixel_clk;
    video_record_probe u_probe(
        .clk_i(clk_i),.rst_ni(rst_ni),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .core_scan_i(1'b0),.core_shift_i(1'b0),.core_capture_i(core_capture_i),.core_scan_o(core_scan_o),
        .pixel_scan_i(1'b0),.pixel_shift_i(1'b0),.pixel_capture_i(pixel_capture_i),.pixel_scan_o(pixel_scan_o));
    task check_idle;
        begin
            if (u_probe.u_pipeline.faults !== 0 || u_probe.u_pipeline.capture_busy !== 0 ||
                u_probe.u_pipeline.h_awvalid !== 0 || u_probe.u_pipeline.h_arvalid !== 0 ||
                u_probe.u_pipeline.asset_retire_valid !== 0 || u_probe.u_pipeline.out_de !== 0)
                $fatal(1,"record probe real DUT idle mismatch");
        end
    endtask
    initial begin
        #101;rst_ni=1;pixel_reset_n=1;
        repeat(200) begin @(negedge clk_i);check_idle();end
        core_capture_i=1;pixel_capture_i=1;
        #101;core_capture_i=0;pixel_capture_i=0;
        check_idle();
        // Asynchronous coordinated reset must clear the boundary without scan clocks.
        #1;rst_ni=0;pixel_reset_n=0;#1;
        if (u_probe.core_input_q !== 0 || u_probe.core_output_q !== 0 ||
            u_probe.pixel_input_q !== 0 || u_probe.pixel_output_q !== 0)
            $fatal(1,"record probe real reset mismatch");
        #101;rst_ni=1;pixel_reset_n=1;
        repeat(100) begin @(negedge clk_i);check_idle();end
        $display("RECORD_PROBE_REAL_IDLE_PASS");$finish;
    end
    initial begin #100000;$fatal(1,"record probe real idle timeout");end
endmodule
