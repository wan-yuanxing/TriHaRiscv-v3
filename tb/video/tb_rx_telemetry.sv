`timescale 1ns/1ps
module tb_rx_telemetry;
    reg cfg=0,pix=0,reset_n=0,run_pixel=1;
    real pixel_half=12.5;
    always #50 cfg=~cfg;
    always begin #(pixel_half);if(run_pixel)pix=~pix;end
    reg[31:0] source_count=0;
    function automatic[215:0] pattern(input[31:0] n);
        pattern={24'hc0ffee,n^32'h12345678,n+32'h937b21,{n[15:0],n[31:16]},~n,n^32'h5a5a5a5a,n};
    endfunction
    reg[215:0]data;
    initial data=pattern(0);
    always @(posedge pix)begin source_count<=source_count+1'b1;data<=pattern(source_count+1'b1);end
    wire[215:0] snapshot;
    wire[31:0] hz;
    wire valid,alive,good;
    video_rx_telemetry #(.GATE_CYCLES(1000)) dut(.cfg_clk(cfg),.pixel_clk(pix),
        .reset_n(reset_n),.pixel_status(data),.snapshot(snapshot),
        .snapshot_valid(valid),.pixel_hz(hz),.clock_alive(alive),.frequency_good(good));
    reg[215:0] old;
    initial begin
        #1;reset_n=0;repeat(3)@(negedge cfg);reset_n=1;
        repeat(3300)@(negedge cfg);
        if(!valid||!alive||!good||hz<39800000||hz>40200000||snapshot==0)
            $fatal(1,"40MHz measurement failed hz%0d valid%b good%b",hz,valid,good);
        if(snapshot!==pattern(snapshot[31:0]))$fatal(1,"Full-width snapshot torn");
        old=snapshot;repeat(20)@(negedge cfg);
        if(snapshot!==old)$fatal(1,"Snapshot changed without handshake");
        pixel_half=25.0;repeat(3300)@(negedge cfg);
        if(!alive||good||hz<19800000||hz>20200000)$fatal(1,"20MHz wrongly qualified");
        run_pixel=0;repeat(3300)@(negedge cfg);
        if(alive||good||valid||hz!=0)$fatal(1,"Stopped pixel clock retained validity");
        run_pixel=1;pixel_half=12.5;repeat(3300)@(negedge cfg);
        if(!valid||!good)$fatal(1,"Clock recovery failed");
        reset_n=0;#1;if(valid||good||alive)$fatal(1,"Async reset failed");
        $display("VIDEO_RX_TELEMETRY_PASS: independent frequency, coherent CDC, stop and recovery");$finish;
    end
    initial begin #3000000;$fatal(1,"Watchdog");end
endmodule
