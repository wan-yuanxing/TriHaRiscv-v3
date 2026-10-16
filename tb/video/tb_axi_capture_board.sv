`timescale 1ns/1ps
// Uses an explicit digital DDR substitute, not vendor training/analog models.
module tb_axi_capture_board;
    reg sys_clk=0,ref_clk_p=0,rst_in=0;
    wire ref_clk_n=~ref_clk_p;
    always #18.5185185 sys_clk=~sys_clk;
    always #4 ref_clk_p=~ref_clk_p;
    wire heart_beat_led,ddr_init_done,init_over_rx,hdmi_int_led,uart_tx;
    wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_ras_n,mem_cas_n,mem_we_n,mem_odt;
    wire [14:0] mem_a;
    wire [2:0] mem_ba;
    tri [3:0] mem_dqs,mem_dqs_n;
    tri [31:0] mem_dq;
    wire [3:0] mem_dm;
    video_axi_capture_top #(.STARTUP_CYCLES(8),.INIT_TIMEOUT_CYCLES(1000),
        .CORE_TIMEOUT_CYCLES(64),.HEARTBEAT_CYCLES(16),.UART_BAUD(2_700_000),
        .UART_INTERVAL_CYCLES(20),.FRAME_WIDTH(16),.FRAME_HEIGHT(3),.BIST_TIMEOUT_CYCLES(1000)) dut(.*);
    task automatic check(input bit ok,input string message);
        if(ok!==1'b1)$fatal(1,"AXI CAPTURE BOARD: %s",message);
    endtask
    task automatic board_reset;
        begin
            @(negedge sys_clk);rst_in=0;
            #1;check(!dut.controller_reset_n && !dut.core_reset_n,"KEY0 reset assertion");
            repeat(4)@(negedge sys_clk);rst_in=1;
            wait(dut.controller_reset_n);
            #0.001;check(!dut.core_reset_n,"asynchronous release into core");
            repeat(2)@(posedge ref_clk_p);#0.001;check(dut.core_reset_n,"local two-edge release");
        end
    endtask
    reg [7:0] packet[0:36];
    integer b,bit_index;
    reg [7:0] value,checksum;
    task automatic receive_packet(input bit pass);
        begin
            wait(!dut.uart.busy);
            for(b=0;b<37;b=b+1)begin
                @(negedge uart_tx);#555.555555;
                value=0;
                for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
                    value[bit_index]=uart_tx;#370.370370;
                end
                check(uart_tx===1'b1,"UART stop bit");packet[b]=value;
            end
            check({packet[0],packet[1],packet[2],packet[3]}==32'h54525631,"TRV1 magic");
            checksum=0;for(b=0;b<36;b=b+1)checksum=checksum^packet[b];
            check(checksum==packet[36],"UART checksum");
            check(packet[4]==4,"distinct AXI DMA packet type");
            if(pass)begin
                check(packet[5]==8'h15 && packet[6]==8'ha5 && packet[7]==0,"fresh PASS flags/phase/code");
                check({packet[11],packet[10],packet[9],packet[8]}==9,"actual AXI128 comparison count");
                check({packet[23],packet[22],packet[21],packet[20]}==32'h87300000,"test allocation");
                check({packet[27],packet[26],packet[25],packet[24]}==144,"frame byte count");
            end else check(packet[5][3] && !packet[5][2] && packet[7]==8'he0,"missing-core timeout observable");
        end
    endtask
    initial begin
        dut.I_ips_ddr_top.model_core_enable=0;dut.I_ips_ddr_top.model_init_enable=0;
        repeat(4)@(negedge sys_clk);rst_in=1;
        repeat(1200)@(negedge sys_clk);
        check(!ddr_init_done && hdmi_int_led && !init_over_rx,"independent init failure");
        receive_packet(0);
        dut.I_ips_ddr_top.model_core_enable=1;dut.I_ips_ddr_top.model_init_enable=1;
        board_reset;wait(init_over_rx || hdmi_int_led);
        check(init_over_rx && !hdmi_int_led,"digital AXI DMA readback pass");
        repeat(30)@(negedge sys_clk);receive_packet(1);
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_core_enable=0;
        repeat(100)@(negedge sys_clk);
        check(ddr_init_done && hdmi_int_led && !init_over_rx && dut.board_error_code==8'he4,"stopped core masks stale PASS");
        dut.I_ips_ddr_top.model_core_enable=1;
        repeat(50)@(negedge sys_clk);check(hdmi_int_led && !init_over_rx,"failure remains sticky");
        board_reset;wait(init_over_rx || hdmi_int_led);check(init_over_rx && !hdmi_int_led,"KEY0 restarts AXI DMA test");
        dut.I_ips_ddr_top.model_drop_lock=1;
        repeat(30)@(negedge sys_clk);check(hdmi_int_led && !init_over_rx,"PLL loss masks prior PASS");
        $display("VIDEO_AXI_CAPTURE_BOARD_PASS digital_only=1 uart=1 watchdog=1 reset=1");$finish;
    end
    initial begin #5000000;$fatal(1,"AXI capture board watchdog");end
endmodule
