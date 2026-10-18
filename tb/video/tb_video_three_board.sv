`timescale 1ns/1ps
// Explicit DIGITAL DDR substitute and forced candidate frontend metadata.
// Existing RX/I2C/PLL tests exercise real frontend behavior separately.
module tb_video_three_board;
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
    video_three_board_top #(.STARTUP_CYCLES(8),.INIT_TIMEOUT_CYCLES(1000),
        .CORE_TIMEOUT_CYCLES(64),.HEARTBEAT_CYCLES(16),.UART_BAUD(2_700_000),
        .UART_INTERVAL_CYCLES(20),.FRAME_WIDTH(10),.FRAME_HEIGHT(10),.PREVIEW_WINDOW_Y(2),.PAD_TOP(1),.PAD_BOTTOM(1),
        .CAPTURE_TIMEOUT_CYCLES(20000),.RX_WARMUP_FRAMES(2)) dut(.*);
    defparam dut.clocks.STARTUP_CYCLES=8;
    reg protect_hdmi_link=0;
    initial begin wait(rstn_out);protect_hdmi_link=1;end
    always @(negedge rstn_out)
        if(protect_hdmi_link && dut.locked)$fatal(1,"KEY0 must preserve the running HDMI link");

    // Independent shortened OUTPUT raster for integration. Default-mode raster
    // and per-pixel visual oracle are exercised by the display component TB.
    reg [10:0] scan_x=0,scan_y=0;
    always @(posedge pix_clk)begin
        if(!dut.pixel_reset_n)begin scan_x<=0;scan_y<=0;end
        else if(scan_x==23)begin scan_x<=0;if(scan_y==15)scan_y<=0;else scan_y<=scan_y+1'b1;end
        else scan_x<=scan_x+1'b1;
    end
    wire scan_hs=scan_x>=18&&scan_x<21;
    wire scan_vs=scan_y>=13&&scan_y<15;
    wire scan_de=scan_x<10&&scan_y<12;
    wire scan_start=scan_x==0&&scan_y==0;
    initial begin
        force dut.display_x=scan_x;force dut.display_y=scan_y;
        force dut.hs=scan_hs;force dut.vs=scan_vs;
        force dut.de=scan_de;force dut.frame_start=scan_start;
    end
    reg cv=0,fb=0,fe=0,fg=0;
    reg [10:0] cx=0,cy=0;
    reg [23:0] crgb=0;
    integer i,j,passed=0;
    task automatic check(input bit ok,input string why);
        if(ok!==1'b1)$fatal(1,"PREVIEW BOARD: %s",why);
    endtask
    task automatic reset_board;
        begin
            seen_kinds=0;
            @(negedge sys_clk);rst_in=0;
            repeat(6)@(negedge sys_clk);rst_in=1;
            wait(dut.core_reset_n && dut.ingress_pixel_reset_n);
        end
    endtask
    task automatic send_source_frame(input bit startup_black);
        begin
            repeat(20)@(negedge pixclk_in);
            for(j=0;j<10;j=j+1)begin
                for(i=0;i<10;i=i+1)begin
                    @(negedge pixclk_in);cv=1;fb=(i==0&&j==0);cx=i;cy=j;
                    crgb=startup_black?24'd0:
                        {(8'h93^i[7:0]),(8'h65^j[7:0]),(8'hb7+i[7:0]+j[7:0])};
                end
                @(negedge pixclk_in);cv=0;fb=0;
                repeat(8)@(negedge pixclk_in);
            end
            @(negedge pixclk_in);fe=1;fg=1;
            @(negedge pixclk_in);fe=0;fg=0;
        end
    endtask
    task automatic source_frame;
        begin
            send_source_frame(1);
            check(dut.ingress.pixel_count==0,"startup frames must not enter capture FIFO");
            send_source_frame(1);
            check(dut.ingress.pixel_count==0,"last startup frame must retire before capture");
            send_source_frame(0);
        end
    endtask
    task automatic receive_capture_packet;
        begin
            // Consume complete rotation; type8 is required in every healthy epoch.
            receive_packet(1);receive_packet(1);receive_packet(1);
            check(seen_kinds==3'b111,"three coherent UART types required");
        end
    endtask
    initial begin
        force dut.tx_done=1;force dut.rx_done=1;force dut.rx_configured=1;
        force dut.tx_error=0;force dut.rx_error=0;force dut.mode_good_cfg=1;
        force dut.geometry_locked=1;force dut.timing_locked=1;
        force dut.candidate=cv;force dut.frame_begin=fb;force dut.frame_end=fe;force dut.frame_good=fg;
        force dut.candidate_x=cx;force dut.candidate_y=cy;force dut.candidate_rgb=crgb;
    end
    reg [7:0] packet[0:36];
    reg [7:0] value,checksum;
    integer n,k;
    reg [2:0] seen_kinds=0;
    task automatic receive_packet(input bit success);
        begin
            wait(!dut.uart.busy);
            for(n=0;n<37;n=n+1)begin
                @(negedge uart_tx);#555.555555;value=0;
                for(k=0;k<8;k=k+1)begin value[k]=uart_tx;#370.370370;end
                check(uart_tx===1'b1,"UART stop");packet[n]=value;
            end
            check({packet[0],packet[1],packet[2],packet[3]}==32'h54525631,"magic");
            checksum=0;for(n=0;n<36;n=n+1)checksum=checksum^packet[n];
            check(checksum==packet[36] && (packet[4]==6||packet[4]==7||packet[4]==8),"preview checksum/type");
            if(success)begin
                check(packet[5]==8'h75 && packet[6]==8'ha5 && packet[7]==0,"PASS healthy flags");
                seen_kinds[packet[4]-6]=1;
                if(packet[4]==6)begin
                    check({packet[11],packet[10],packet[9],packet[8]}==100,"raw pixel count");
                    check({packet[15],packet[14],packet[13],packet[12]}==25,"preview pixel count");
                    check({packet[19],packet[18],packet[17],packet[16]}==
                          {packet[23],packet[22],packet[21],packet[20]},"raw source/read CRC");
                    // Independent RGB byte oracle for the 10x10 source above;
                    // transport equality alone would also accept a black frame.
                    check({packet[19],packet[18],packet[17],packet[16]}==32'h0effe9e5,
                          "captured source pattern after startup black frames");
                    check({packet[27],packet[26],packet[25],packet[24]}==
                          {packet[31],packet[30],packet[29],packet[28]},"preview source/read CRC");
                    check({packet[27],packet[26],packet[25],packet[24]}==32'hc6322d1e,
                          "preview pattern independent oracle");
                end else if(packet[4]==7)begin
                    check({packet[11],packet[10],packet[9],packet[8]}==1,"display frame_id");
                    check({packet[15],packet[14],packet[13],packet[12]}==1,"single commit");
                    check({packet[19],packet[18],packet[17],packet[16]}>=2,"completed scans");
                    check({packet[23],packet[22],packet[21],packet[20]}==0,"no underflow");
                end else begin
                    check({packet[11],packet[10],packet[9],packet[8]}==1,"capture frame_id");
                    check({packet[15],packet[14],packet[13],packet[12]}==1,"preprocess version");
                    check({packet[19],packet[18],packet[17],packet[16]}==16,"active input pixels");
                    check({packet[23],packet[22],packet[21],packet[20]}==72,"input bytes written");
                    check({packet[27],packet[26],packet[25],packet[24]}==72,"input bytes checked");
                    check({packet[31],packet[30],packet[29],packet[28]}==32'h68dfad25,"independent padded BGR input CRC");
                end
            end else check(packet[5][3] && !packet[5][2],"error masks stale PASS");
        end
    endtask
    initial begin
        dut.I_ips_ddr_top.model_core_enable=0;dut.I_ips_ddr_top.model_init_enable=0;
        repeat(6)@(negedge sys_clk);rst_in=1;
        repeat(1200)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx,"no core/init independently reported");receive_packet(0);
        dut.I_ips_ddr_top.model_core_enable=1;dut.I_ips_ddr_top.model_init_enable=1;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"capture/CRC with digital frontend");receive_capture_packet;passed=passed+1;
        reset_board;source_frame;wait(dut.bist.capture_complete);
        @(negedge dut.core_clk);force dut.tx_error=1;
        repeat(120)@(negedge sys_clk);
        check(dut.board_error_code==8'he5&&dut.bist.error&&dut.bist.commits==0,
              "board health fault must reach engine before display submission");
        repeat(300)@(negedge sys_clk);
        check(dut.bist.commits==0&&!init_over_rx&&hdmi_int_led,"sticky board fault cannot commit later");
        force dut.tx_error=0;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"KEY0 recovers after board health fault");receive_capture_packet;passed=passed+1;
        force dut.locked=0;
        #1;check(dut.ingress_pixel_reset_n,"HDMI PLL loss must not clear FIFO ownership");
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.board_error_code==8'he6,"HDMI PLL loss masks PASS");
        release dut.locked;
        repeat(30)@(negedge sys_clk);check(hdmi_int_led&&!init_over_rx,"HDMI fault remains sticky");
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"coordinated reset after HDMI fault");receive_capture_packet;passed=passed+1;
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_core_enable=0;
        repeat(100)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.board_error_code==8'he4,"core stop masks prior PASS");
        dut.I_ips_ddr_top.model_core_enable=1;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"KEY0 recaptures");receive_capture_packet;passed=passed+1;
        dut.I_ips_ddr_top.model_drop_lock=1;
        repeat(30)@(negedge sys_clk);check(hdmi_int_led&&!init_over_rx,"DDR PLL loss masks prior PASS");
        dut.I_ips_ddr_top.model_drop_lock=0;
        reset_board;source_frame;wait(dut.bist.capture_complete);
        @(negedge dut.core_clk);force dut.source_fault=1;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.bist.error_code==3,"sticky source fault during CRC rejects display");
        receive_packet(0);release dut.source_fault;passed=passed+1;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"reset recovers after source fault");receive_capture_packet;
        @(negedge dut.core_clk);force dut.source_fault=1;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.bist.error_code==3,"source fault revokes held PASS");
        release dut.source_fault;passed=passed+1;
        $display("VIDEO_THREE_BOARD_PASS tests=%0d digital_only=1 forced_frontend=1 uart=1 reset=1",passed);$finish;
    end
    initial begin #5000000;$fatal(1,"HDMI capture board watchdog");end
endmodule
