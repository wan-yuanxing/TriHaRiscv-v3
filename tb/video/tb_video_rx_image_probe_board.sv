`timescale 1ns/1ps
module tb_video_rx_image_probe_board;
    reg sys_clk=0,rst_in=0,pixclk_in=0,hs_in=0,vs_in=0,de_in=0;
    reg[7:0]r_in=0,g_in=0,b_in=0;
    wire rstn_out,hd_scl,pix_clk,hs_out,vs_out,de_out;
    wire[7:0]r_out,g_out,b_out;
    wire heart_beat_led,ddr_init_done,init_over_rx,hdmi_int_led,uart_tx;
    tri1 hd_sda;
    video_rx_image_probe_top dut(.*);
    always #18.5185185 sys_clk=~sys_clk;
    always #12.5 pixclk_in=~pixclk_in;
    integer tc,rc,post,polls;
    reg tx_model_reset_n=1,rx_model_reset_n=1;
    ms7210_i2c_model txmodel(.reset_n(tx_model_reset_n),.present(1'b1),
        .id_value(8'h5a),.nack_config_index(-1),.scl(hd_scl),.sda(hd_sda),.config_count(tc));
    ms7200_i2c_model rxmodel(.reset_n(rx_model_reset_n),.present(1'b1),
        .scratch_value(8'h5a),.status_209e(8'd0),.nack_config_index(-1),.nack_post_index(-1),
        .scl(hd_scl),.sda(hd_sda),.config_count(rc),.post_count(post),.poll_count(polls));
    initial begin
        wait(dut.tx.u_ctl.state==6'b001000);
        repeat(8)@(negedge dut.cfg_clk);
        force dut.tx.u_ctl.delay_cnt=22'h30d399;
        @(negedge dut.cfg_clk);release dut.tx.u_ctl.delay_cnt;
    end
    integer x=0,y=0,outputs=0;
    // Converter model launches after a rising PCLK edge. Board capture must
    // use the opposite edge before downstream rising-edge consumers.
    always @(posedge pixclk_in)begin
        #1;
        hs_in=x>=840&&x<968;vs_in=y>=601&&y<605;de_in=x<800&&y<600;
        r_in=x;g_in=y;b_in=x^y;
        if(x==1055)begin x=0;if(y==627)y=0;else y=y+1;end else x=x+1;
    end
    always @(posedge pix_clk)if(de_out)outputs=outputs+1;
    // Every downstream consumer must use one coherent pad capture. This is a
    // digital structural check; it does not assert external setup/hold closure.
    reg[26:0]expected_capture;
    reg capture_enabled;
    always @(negedge pixclk_in)begin
        capture_enabled=dut.rx_reset_n;
        expected_capture={hs_in,vs_in,de_in,r_in,g_in,b_in};
        #1;
        if(capture_enabled && dut.rx_capture!==expected_capture)
            $fatal(1,"RX pad capture lost bundle coherence");
    end
    defparam dut.diagnostic.INTERVAL_CYCLES=10000;
    integer image_packets=0;
    reg busy_q=0;
    reg [31:0] pair_sequence;
    always @(posedge dut.cfg_clk)begin
        busy_q=dut.uart_busy;
        #1;
        if(!busy_q && dut.uart_busy)begin
            if(dut.diagnostic.snapshot[7:0]==8)begin
                pair_sequence=dut.diagnostic.snapshot[63:32];
                if(pair_sequence!=0)begin
                    if(dut.diagnostic.snapshot[95:64]!==480000 ||
                       dut.diagnostic.snapshot[127:96]!==479988 ||
                       dut.diagnostic.snapshot[159:128]!==32'h031f0000 ||
                       dut.diagnostic.snapshot[191:160]!==32'h02570000 ||
                       dut.diagnostic.snapshot[223:192]!==32'h00c8965e ||
                       dut.diagnostic.snapshot[255:224]!==32'h005896ce)
                        $fatal(1,"type8 RX distribution mapping wrong");
                    image_packets=image_packets+1;
                end
            end
            if(dut.diagnostic.snapshot[7:0]==9 && dut.diagnostic.snapshot[63:32]!=0)begin
                if(dut.diagnostic.snapshot[63:32]!==pair_sequence ||
                   dut.diagnostic.snapshot[95:64]!==32'h00c8c20a ||
                   dut.diagnostic.snapshot[127:96]!==32'h0058c29a ||
                   dut.diagnostic.snapshot[159:128]!==32'hf24ade70 ||
                   dut.diagnostic.snapshot[255:160]!==96'd0)
                    $fatal(1,"type9 RX distribution mapping or held pair wrong");
                image_packets=image_packets+1;
            end
        end
    end
    initial begin
        #1;rst_in=0;tx_model_reset_n=0;rx_model_reset_n=0;
        repeat(5)@(negedge sys_clk);rst_in=1;
        wait(rstn_out);tx_model_reset_n=1;
        wait(dut.tx_done);#1;
        if(tc!=49||dut.rx_done)$fatal(1,"TX must finish all49writes before RX");
        tx_model_reset_n=0;rx_model_reset_n=1;
        wait(dut.rx_done);#1;
        if(rc!=300||dut.rx_error||dut.tx_error)$fatal(1,"Shared-bus RX boot failed");
        repeat(2500000)@(posedge pixclk_in);
        #1;
        if(!dut.snapshot[192]||!dut.freq_good||!dut.fresh||dut.mode_good||post!=0)
            $fatal(1,"Input timing/frequency or no-source sticky gating incorrect");
        if(dut.snapshot[247:216]!=4224||dut.snapshot[279:248]!=663168)
            $fatal(1,"Raw VS probe was not transferred coherently");
        if(outputs<480000||hdmi_int_led)$fatal(1,"RX activity disturbed TX output");
        if(dut.image_sequence<2||dut.image_pixels!==480000||dut.image_crc!==32'hf24ade70||image_packets<4)
            $fatal(1,"image observer did not publish coherent complete frames or packets");
        $display("VIDEO_RX_IMAGE_PROBE_BOARD_PASS packets=%0d seq=%0d",image_packets,dut.image_sequence);
        $display("VIDEO_RX_BOARD_PASS: ordered shared I2C, RX boot, timing/frequency, TX continues");$finish;
    end
    initial begin #150000000;$fatal(1,"Watchdog");end
endmodule
