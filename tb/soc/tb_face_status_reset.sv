`timescale 1ns/1ps
// Exercise the actual face-system observation registers. Unrelated datapaths
// are blackboxed; local release outputs and status sources are driven here.
module tb_face_status_reset;
    parameter integer PHASE=1;
    reg cpu_clk=0,video_clk=0,raw_reset=0,cpu_reset=0,video_reset=0;
    reg irq=1,fault=1;
    integer which=0,epoch;
    always #5 cpu_clk=~cpu_clk;
    initial begin #(PHASE);forever #4 video_clk=~video_clk;end
    triha_face_system dut(.compute_clk_i(cpu_clk),.video_clk_i(video_clk),
        .pixel_clk(1'b0),.rst_ni(raw_reset),.pixel_reset_n(1'b0));
    initial begin
        if($value$plusargs("CASE=%d",which))begin end
        force dut.compute_reset_n=cpu_reset;
        force dut.video_reset_n=video_reset;
        force dut.capture_irq=irq;
        force dut.display_irq=1'b0;
        force dut.compute_fault=fault;
        for(epoch=0;epoch<3;epoch=epoch+1)begin
            raw_reset=0;cpu_reset=0;video_reset=0;
            repeat(3)@(negedge cpu_clk);
            raw_reset=1;
            repeat(5)@(negedge cpu_clk);
            if(which!=2&&dut.video_irq_sync!==0)$fatal(1,"IRQ_ESCAPED_LOCAL_RESET");
            if(which!=1&&dut.compute_fault_sync!==0)$fatal(1,"FAULT_ESCAPED_LOCAL_RESET");
            cpu_reset=1;
            @(posedge cpu_clk);#1;
            if(dut.video_irq_sync!==2'b01)$fatal(1,"IRQ_FIRST_STAGE");
            @(posedge cpu_clk);#1;
            if(dut.video_irq_sync!==2'b11)$fatal(1,"IRQ_SECOND_STAGE");
            @(negedge video_clk);video_reset=1;
            @(posedge video_clk);#1;
            if(dut.compute_fault_sync!==2'b01)$fatal(1,"FAULT_FIRST_STAGE");
            @(posedge video_clk);#1;
            if(dut.compute_fault_sync!==2'b11)$fatal(1,"FAULT_SECOND_STAGE");
            // Local coordinated reset must clear observations even while the
            // asynchronous board reset remains deasserted.
            #2;cpu_reset=0;video_reset=0;#1;
            if(dut.video_irq_sync!==0||dut.compute_fault_sync!==0)
                $fatal(1,"STATUS_LOCAL_REASSERT");
        end
        $display("FACE_STATUS_RESET_PASS phase=%0d epochs=3",PHASE);$finish;
    end
    initial begin #5000;$fatal(1,"STATUS_RESET_TIMEOUT");end
endmodule
