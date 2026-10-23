`timescale 1ns/1ps
// Explicit DIGITAL DDR substitute and forced candidate frontend metadata.
// Existing RX/I2C/PLL tests exercise real frontend behavior separately.
module tb_video_live_board;
    reg sys_clk=0,ref_clk_p=0,rst_in=0,pixclk_in=0;
    wire ref_clk_n=~ref_clk_p;
    reg hs_in=0,vs_in=0,de_in=0;
    reg [7:0] r_in=0,g_in=0,b_in=0;
    wire heart_beat_led,ddr_init_done,init_over_rx,hdmi_int_led,uart_tx;
    wire rstn_out,hd_scl,pix_clk,hs_out,vs_out,de_out;
    wire [7:0] r_out,g_out,b_out;
    tri1 hd_sda;
    wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_ras_n,mem_cas_n,mem_we_n,mem_odt;
    wire [14:0] mem_a;
    wire [2:0] mem_ba;
    tri [3:0] mem_dqs,mem_dqs_n;
    tri [31:0] mem_dq;
    wire [3:0] mem_dm;
    always #18.5185185 sys_clk=~sys_clk;
    always #4 ref_clk_p=~ref_clk_p;
    always #12.5 pixclk_in=~pixclk_in;
    reg [7:0] pad_sequence=0;
    always @(posedge pixclk_in)begin
        #1;pad_sequence=pad_sequence+1'b1;
        r_in=pad_sequence;g_in=~pad_sequence;b_in=pad_sequence^8'h96;
        hs_in=pad_sequence[0];vs_in=pad_sequence[1];de_in=pad_sequence[2];
    end
    reg [26:0] expected_capture;
    reg capture_enabled;
    always @(negedge pixclk_in)begin
        capture_enabled=dut.rx_reset_n;
        expected_capture={hs_in,vs_in,de_in,r_in,g_in,b_in};
        #1;
        if(capture_enabled && dut.rx_reset_n && dut.rx_capture!==expected_capture)
            $fatal(1,"HDMI capture pad bundle must use falling PCLK");
    end
    `ifndef VIDEO_LIVE_BOARD_DUT
    `define VIDEO_LIVE_BOARD_DUT video_live_board_top
    `endif
    `VIDEO_LIVE_BOARD_DUT #(.STARTUP_CYCLES(8),.INIT_TIMEOUT_CYCLES(1000),
        .CORE_TIMEOUT_CYCLES(64),.HEARTBEAT_CYCLES(16),.UART_BAUD(2_700_000),
        .UART_INTERVAL_CYCLES(20),.FRAME_WIDTH(10),.FRAME_HEIGHT(10),.PAD_TOP(1),.PAD_BOTTOM(1),
        .CAPTURE_TIMEOUT_CYCLES(20000),.RX_WARMUP_FRAMES(2)) dut(.*);
    defparam dut.clocks.STARTUP_CYCLES=8;
    reg protect_hdmi_link=0;
    initial begin wait(rstn_out);protect_hdmi_link=1;end
    always @(negedge rstn_out)
        if(protect_hdmi_link && dut.locked)$fatal(1,"KEY0 must preserve the running HDMI link");

    reg [10:0] sx=0,sy=0;
    always @(posedge pix_clk)begin
        if(!dut.display_pixel_reset_n)begin sx<=0;sy<=0;end
        else if(sx==95)begin sx<=0;sy<=sy==17?0:sy+1'b1;end
        else sx<=sx+1'b1;
    end
    wire sh=sx>=40&&sx<50,sv=sy>=14,sd=sx<10&&sy<10,ss=sx==0&&sy==0;
    reg cv=0,fb=0,fe=0,fg=1;reg [10:0] cx=0,cy=0;reg [23:0] crgb=0;
    initial begin
        force dut.display_x=sx;force dut.display_y=sy;
        force dut.hs=sh;force dut.vs=sv;force dut.de=sd;force dut.frame_start=ss;
        force dut.tx_done=1;force dut.rx_done=1;force dut.rx_configured=1;
        force dut.tx_error=0;force dut.rx_error=0;force dut.mode_good_cfg=1;
        force dut.geometry_locked=1;force dut.timing_locked=1;
        force dut.candidate=cv;force dut.frame_begin=fb;force dut.frame_end=fe;force dut.frame_good=fg;
        force dut.candidate_x=cx;force dut.candidate_y=cy;force dut.candidate_rgb=crgb;
    end
    function automatic [23:0] src(input integer x,y,tag);
        src={8'(tag*41+x),8'(tag*17+y),8'(tag*73+x+y)};
    endfunction
    task automatic send_frame(input integer tag);
        integer x,y;
        begin
            repeat(20)@(negedge pixclk_in);
            for(y=0;y<10;y=y+1)begin
                for(x=0;x<10;x=x+1)begin
                    cv=1;fb=x==0&&y==0;cx=x;cy=y;crgb=src(x,y,tag);@(negedge pixclk_in);
                end
                cv=0;fb=0;repeat(64)@(negedge pixclk_in);
            end
            fe=1;@(negedge pixclk_in);fe=0;
        end
    endtask
    integer tag=0,checked=0;
    reg seen=0;
    initial forever begin
        @(negedge pixclk_in);
        if(!dut.core_reset_n)begin seen=0;tag=0;end
        else if(dut.arm_toggle!=seen)begin
            seen=dut.arm_toggle;tag=tag+1;repeat(6)@(negedge pixclk_in);
            if(tag==1)begin send_frame(0);send_frame(0);end
            send_frame(tag);
        end
    end
    reg [23:0] pad_rgb;reg [2:0] pad_sync;
    always @(posedge pix_clk)if(dut.display_pixel_reset_n)begin
        pad_rgb=dut.rgb;pad_sync={dut.display_hs,dut.display_vs,dut.display_de};
        #1;
        if({r_out,g_out,b_out}!==pad_rgb||{hs_out,vs_out,de_out}!==pad_sync)$fatal(1,"LIVE_BOARD_PAD_PIPE");
    end
    always @(negedge pix_clk)if(dut.display_pixel_reset_n&&dut.bist.display.out_context_valid)begin
        if(dut.rgb!==src(dut.bist.display.out_x,dut.bist.display.out_y,dut.bist.display.out_frame_id))
            $fatal(1,"LIVE_BOARD_PIXEL id=%0d",dut.bist.display.out_frame_id);
        checked=checked+1;
    end
    reg [7:0] packet[0:36];reg [7:0] value,checksum;integer i,k,kinds=0;
    task automatic packet_check;
        begin
            wait(!dut.uart.busy);
            for(i=0;i<37;i=i+1)begin
                @(negedge uart_tx);#555.555555;value=0;
                for(k=0;k<8;k=k+1)begin value[k]=uart_tx;#370.370370;end
                if(!uart_tx)$fatal(1,"LIVE_BOARD_UART_STOP");packet[i]=value;
            end
            checksum=0;for(i=0;i<36;i=i+1)checksum=checksum^packet[i];
            if({packet[0],packet[1],packet[2],packet[3]}!==32'h54525631||checksum!==packet[36])$fatal(1,"LIVE_BOARD_UART_CRC");
            case(packet[4])9:kinds=kinds|1;11:kinds=kinds|2;12:kinds=kinds|4;default:$fatal(1,"LIVE_BOARD_UART_TYPE");endcase
            if(packet[5][3]||packet[7]!=0)$fatal(1,"LIVE_BOARD_UART_ERROR");
        end
    endtask
    integer epoch;
    initial begin
        for(epoch=0;epoch<2;epoch=epoch+1)begin
            rst_in=0;repeat(10)@(negedge sys_clk);rst_in=1;
            wait(dut.bist.commits>=5);
            // raw_display publishes held events first; lifecycle consumes the
            // release on the following core edge. Check its own retirement.
            wait(dut.bist.releases>=4);repeat(4)@(negedge dut.core_clk);
            if(dut.bist.releases<4||dut.bist.error||dut.board_error||dut.underflows!=0)
                $fatal(1,"LIVE_BOARD_PROGRESS releases=%0d error=%h board=%h underflows=%0d",dut.bist.releases,dut.bist_error_code,dut.board_error_code,dut.underflows);
            packet_check;packet_check;packet_check;
            if(kinds!=7||checked<400)$fatal(1,"LIVE_BOARD_INCOMPLETE");
        end
        $display("VIDEO_LIVE_BOARD_PASS pixels=%0d",checked);$finish;
    end
    initial begin #10000000;$fatal(1,"LIVE_BOARD_TIMEOUT phase=%h error=%h",dut.bist_phase,dut.bist_error_code);end
endmodule
