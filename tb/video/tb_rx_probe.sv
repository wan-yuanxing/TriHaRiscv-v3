`timescale 1ns/1ps
`default_nettype none
module tb_rx_probe;
    localparam integer H_TOTAL=1056, V_TOTAL=628;
    localparam integer FRAME_CLOCKS=H_TOTAL*V_TOTAL;
    reg clk=0;
    always #12.5 clk=~clk;
    reg reset_n=1,enable=1,hs=0,vs=0,de=0;
    wire [31:0] vs_high_clocks,vs_period_clocks;
    wire [31:0] hs_rises,hs_falls,vs_rises,vs_falls,de_rises;
    video_rx_probe dut(.pixel_clk(clk),.reset_n(reset_n),.enable(enable),
        .hs_in(hs),.vs_in(vs),.de_in(de),
        .vs_high_clocks(vs_high_clocks),.vs_period_clocks(vs_period_clocks),
        .hs_rises(hs_rises),.hs_falls(hs_falls),
        .vs_rises(vs_rises),.vs_falls(vs_falls),.de_rises(de_rises));

    always @(posedge clk) begin
        #1;
        if ((^{vs_high_clocks,vs_period_clocks,hs_rises,hs_falls,
               vs_rises,vs_falls,de_rises})===1'bx)
            $fatal(1,"Probe outputs contain X/Z");
    end

    task check_metrics(input integer width_clocks,input integer period_clocks);
        begin
            if(vs_high_clocks!==width_clocks || vs_period_clocks!==period_clocks)
                $fatal(1,"VS clocks expected high=%0d period=%0d got high=%0d period=%0d",
                       width_clocks,period_clocks,vs_high_clocks,vs_period_clocks);
        end
    endtask

    task check_counts(input integer hr,input integer hf,input integer vr,
                      input integer vf,input integer dr);
        begin
            if(hs_rises!==hr || hs_falls!==hf || vs_rises!==vr ||
               vs_falls!==vf || de_rises!==dr)
                $fatal(1,"Edge counts expected %0d/%0d/%0d/%0d/%0d got %0d/%0d/%0d/%0d/%0d",
                       hr,hf,vr,vf,dr,hs_rises,hs_falls,vs_rises,vs_falls,de_rises);
        end
    endtask

    task sample(input reg h,input reg v,input reg d);
        begin
            @(negedge clk);hs=h;vs=v;de=d;
            @(posedge clk);#1;
        end
    endtask

    task async_reset;
        begin
            // Change reset away from either clock edge and check before the next one.
            #2;reset_n=0;#1;
            check_metrics(0,0);check_counts(0,0,0,0,0);
            @(negedge clk);hs=0;vs=0;de=0;enable=1;reset_n=1;
            @(posedge clk);#1;
            check_metrics(0,0);check_counts(0,0,0,0,0);
        end
    endtask

    task raster(input integer width_clocks,input integer phase,
                input integer interior_hs_per_pulse);
        integer f,y,x,position,start_clock,interior_hs;
        begin
            start_clock=601*H_TOTAL+phase;
            interior_hs=0;
            for(f=0;f<2;f=f+1)
                for(y=0;y<V_TOTAL;y=y+1)
                    for(x=0;x<H_TOTAL;x=x+1) begin
                        position=y*H_TOTAL+x;
                        @(negedge clk);
                        hs=(x>=840 && x<968);
                        vs=(position>=start_clock && position<start_clock+width_clocks);
                        de=(x<800 && y<600);
                        // Independent stimulus oracle: exclude edges coincident with
                        // either VS boundary, as a line-edge diagnostic might do.
                        if(x==840 && position>start_clock && position<start_clock+width_clocks)
                            interior_hs=interior_hs+1;
                        @(posedge clk);#1;
                        if(position==start_clock+width_clocks)
                            check_metrics(width_clocks,f==0 ? 0 : FRAME_CLOCKS);
                        if(f==1 && position==start_clock)
                            check_metrics(width_clocks,FRAME_CLOCKS);
                    end
            check_metrics(width_clocks,FRAME_CLOCKS);
            check_counts(2*V_TOTAL,2*V_TOTAL,2,2,2*600);
            if(interior_hs!=2*interior_hs_per_pulse)
                $fatal(1,"Independent HS interior-edge oracle disagrees: %0d",interior_hs);
            $display("RX_PROBE_RASTER: high=%0d period=%0d hs_rises=%0d hs_falls=%0d vs_rises=%0d vs_falls=%0d de_rises=%0d interior_hs_per_pulse=%0d",
                     vs_high_clocks,vs_period_clocks,hs_rises,hs_falls,
                     vs_rises,vs_falls,de_rises,interior_hs_per_pulse);
        end
    endtask

    initial begin
        #1;reset_n=0;#1;check_metrics(0,0);check_counts(0,0,0,0,0);
        // Starting high primes history; the first observed fall is counted,
        // but cannot complete a high pulse whose beginning was not observed.
        @(negedge clk);hs=1;vs=1;de=1;reset_n=1;
        @(posedge clk);#1;
        check_metrics(0,0);check_counts(0,0,0,0,0);
        sample(0,0,0);
        check_metrics(0,0);check_counts(0,1,0,1,0);
        sample(1,1,1);
        repeat(6) sample(1,1,1);
        check_metrics(0,0);check_counts(1,1,1,1,1);
        sample(0,0,0);
        check_metrics(7,0);check_counts(1,2,1,2,1);
        repeat(2) sample(0,0,0);
        sample(1,1,1);
        check_metrics(7,10);check_counts(2,2,2,2,2);
        // Completed results stay visible while the next pulse is unfinished.
        repeat(3) sample(1,1,1);
        check_metrics(7,10);check_counts(2,2,2,2,2);

        @(negedge clk);enable=0;
        @(posedge clk);#1;
        check_metrics(0,0);check_counts(0,0,0,0,0);
        sample(0,0,0);sample(1,1,1);
        check_metrics(0,0);check_counts(0,0,0,0,0);
        @(negedge clk);enable=1;
        @(posedge clk);#1;
        check_metrics(0,0);check_counts(0,0,0,0,0);
        sample(0,0,0);
        check_metrics(0,0);check_counts(0,1,0,1,0);
        sample(0,1,0);
        repeat(4) sample(0,1,0);
        sample(0,0,0);
        check_metrics(5,0);check_counts(0,1,1,2,0);
        repeat(5) sample(0,0,0);
        sample(0,1,0);
        check_metrics(5,11);check_counts(0,1,2,2,0);

        async_reset();
        // Exact four-line VS at HS rise: only three HS rises are strictly
        // inside the pulse, but four complete line periods have elapsed.
        raster(4224,840,3);
        async_reset();
        raster(3168,0,3);
        async_reset();
        // One extra pixel clock must remain visible rather than round to lines.
        raster(4225,840,4);
        async_reset();
        $display("VIDEO_RX_PROBE_PASS: raw VS clocks, independent edge counts, priming, reset, disable/recovery");
        $finish;
    end
    initial begin #150000000;$fatal(1,"Watchdog");end
endmodule
`default_nettype wire
