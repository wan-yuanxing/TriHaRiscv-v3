`timescale 1ns/1ps
// Explicit DIGITAL DDR substitute and forced candidate frontend metadata.
// Existing RX/I2C/PLL tests exercise real frontend behavior separately.
module tb_video_hdmi_capture_board;
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
    video_hdmi_capture_top #(.STARTUP_CYCLES(8),.INIT_TIMEOUT_CYCLES(1000),
        .CORE_TIMEOUT_CYCLES(64),.HEARTBEAT_CYCLES(16),.UART_BAUD(2_700_000),
        .UART_INTERVAL_CYCLES(20),.FRAME_WIDTH(16),.FRAME_HEIGHT(3),
        .CAPTURE_TIMEOUT_CYCLES(20000)) dut(.*);
    reg cv=0,fb=0,fe=0,fg=0;
    reg [10:0] cx=0,cy=0;
    reg [23:0] crgb=0;
    integer i,j,passed=0;
    task automatic check(input bit ok,input string why);
        if(ok!==1'b1)$fatal(1,"HDMI CAPTURE BOARD: %s",why);
    endtask
    task automatic reset_board;
        begin
            @(negedge sys_clk);rst_in=0;
            repeat(6)@(negedge sys_clk);rst_in=1;
            wait(dut.core_reset_n && dut.ingress_pixel_reset_n);
        end
    endtask
    task automatic source_frame;
        begin
            repeat(20)@(negedge pixclk_in);
            for(j=0;j<3;j=j+1)begin
                for(i=0;i<16;i=i+1)begin
                    @(negedge pixclk_in);cv=1;fb=(i==0&&j==0);cx=i;cy=j;
                    crgb={(8'h93^i[7:0]),(8'h65^j[7:0]),(8'hb7+i[7:0]+j[7:0])};
                end
                @(negedge pixclk_in);cv=0;fb=0;
                repeat(8)@(negedge pixclk_in);
            end
            @(negedge pixclk_in);fe=1;fg=1;
            @(negedge pixclk_in);fe=0;fg=0;
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
            check(checksum==packet[36] && packet[4]==5,"type5 checksum");
            if(success)begin
                check(packet[5]==8'h75 && packet[6]==8'ha5 && packet[7]==0,"PASS healthy flags");
                check({packet[11],packet[10],packet[9],packet[8]}==48,"pixel count");
                check({packet[15],packet[14],packet[13],packet[12]}==144,"byte count");
                check({packet[19],packet[18],packet[17],packet[16]}==
                      {packet[23],packet[22],packet[21],packet[20]},"source/read CRC");
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
        check(init_over_rx&&!hdmi_int_led,"capture/CRC with digital frontend");receive_packet(1);passed=passed+1;
        force dut.locked=0;
        #1;check(dut.ingress_pixel_reset_n,"HDMI PLL loss must not clear FIFO ownership");
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.board_error_code==8'he6,"HDMI PLL loss masks PASS");
        release dut.locked;
        repeat(30)@(negedge sys_clk);check(hdmi_int_led&&!init_over_rx,"HDMI fault remains sticky");
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"coordinated reset after HDMI fault");passed=passed+1;
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_core_enable=0;
        repeat(100)@(negedge sys_clk);
        check(hdmi_int_led&&!init_over_rx&&dut.board_error_code==8'he4,"core stop masks prior PASS");
        dut.I_ips_ddr_top.model_core_enable=1;
        reset_board;source_frame;wait(init_over_rx||hdmi_int_led);
        check(init_over_rx&&!hdmi_int_led,"KEY0 recaptures");passed=passed+1;
        dut.I_ips_ddr_top.model_drop_lock=1;
        repeat(30)@(negedge sys_clk);check(hdmi_int_led&&!init_over_rx,"DDR PLL loss masks prior PASS");
        $display("VIDEO_HDMI_CAPTURE_BOARD_PASS tests=%0d digital_only=1 forced_frontend=1 uart=1 reset=1",passed);$finish;
    end
    initial begin #5000000;$fatal(1,"HDMI capture board watchdog");end
endmodule
