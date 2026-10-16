`timescale 1ns/1ps
module tb_rx_measure;
    reg clk=0;
    always #12.5 clk=~clk;
    reg reset_n=0,enable=1,hs=0,vs=0,de=0;
    wire locked,error;
    wire [15:0] ha,va,ht,vt,hw,vw,hf,hb,vf,vb;
    wire [31:0] good,bad;
    video_rx_measure dut(.pixel_clk(clk),.reset_n(reset_n),.enable(enable),
        .hs_in(hs),.vs_in(vs),.de_in(de),.timing_locked(locked),.mode_error(error),
        .h_active(ha),.v_active(va),.h_total(ht),.v_total(vt),
        .h_sync(hw),.v_sync(vw),.h_front(hf),.h_back(hb),.v_front(vf),.v_back(vb),
        .good_frames(good),.bad_frames(bad));
    task raster(input integer frames,input integer shifted_h,input integer changed_v,input integer vs_shift=0);
        integer f,x,y,v_tick;
        begin
            for(f=0;f<frames;f=f+1)
                for(y=0;y<628;y=y+1)
                    for(x=0;x<1056;x=x+1) begin
                        @(negedge clk);
                        hs=x>=840+shifted_h && x<968+shifted_h;
                        v_tick=(y*1056+x-vs_shift+663168)%663168;
                        vs=v_tick>=601*1056 && v_tick<(605+changed_v)*1056;
                        de=x<800 && y<600;
                    end
            @(posedge clk);#1;
        end
    endtask
    initial begin
        #1;reset_n=0;repeat(3)@(negedge clk);reset_n=1;
        raster(3,0,0);
        if(!locked || error || good<2 || ha!=800 || va!=600 || ht!=1056 || vt!=628 ||
            hw!=128 || vw!=4 || hf!=40 || hb!=88 || vf!=1 || vb!=23)
            $fatal(1,"Good mode measurements incorrect ha=%d va=%d ht=%d vt=%d hw=%d vw=%d hf=%d hb=%d vf=%d vb=%d",ha,va,ht,vt,hw,vw,hf,hb,vf,vb);
        // Legal VS at HS boundary rather than local active-x0 convention.
        raster(3,0,0,-216);
        if(!locked || vf!=1 || vb!=23 || vw!=4)
            $fatal(1,"Legal VS/HS phase convention was rejected");
        // Same totals/active/sync width, wrong front and back porch.
        raster(2,1,0);
        if(locked || !error || bad==0 || hf!=41 || hb!=87)
            $fatal(1,"Wrong horizontal porch was not rejected/measured");
        raster(2,0,0);
        if(!locked || !error) $fatal(1,"Full good frame did not recover; error must remain sticky");
        raster(2,0,1);
        if(locked || vw!=5 || vb!=22) $fatal(1,"Wrong VS width/back porch not detected");
        enable=0;@(posedge clk);#1;
        if(locked) $fatal(1,"Disabled receiver retained mode lock");
        reset_n=0;#1;
        if(error || good!=0 || bad!=0) $fatal(1,"Asynchronous reset failed");
        $display("VIDEO_RX_MEASURE_PASS: exact sync/porch checks, measured geometry, recovery");
        $finish;
    end
    initial begin #300000000; $fatal(1,"Watchdog"); end
endmodule
