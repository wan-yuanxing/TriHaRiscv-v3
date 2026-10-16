`timescale 1ns/1ps
// This is a digital wrapper/CDC test. The DDR IP below is an explicit behavioral
// substitute; this test does not model DDR3 training, PLL analog behavior or pins.
module tb_ddr_board;
    reg sys_clk=0, ref_clk_p=0, rst_in=0;
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
    video_ddr_bist_top #(.STARTUP_CYCLES(8),.INIT_TIMEOUT_CYCLES(1000),
        .CORE_TIMEOUT_CYCLES(64),.HEARTBEAT_CYCLES(16),.UART_BAUD(2_700_000),.UART_INTERVAL_CYCLES(20),
        .BIST_WINDOW_BEATS(8),.BIST_BURST_BEATS(4),.BIST_TIMEOUT_CYCLES(100)) dut(.*);

    // Standalone CDC test changes every field every source clock. The relations
    // provide an independent coherence oracle, including rollover/carry bits.
    reg cdc_reset_n=0,src_enable=1;
    reg [31:0] source_count=32'hfffffff0;
    wire src_clk=ref_clk_p && src_enable;
    wire [127:0] source_data={source_count,~source_count,source_count^32'h55aa37c0,source_count+32'd1};
    wire [127:0] snapshot;
    wire snapshot_pulse;
    integer coherent_samples=0;
    reg ack_seen=0,expected_valid=0;
    reg [127:0] sampled_source,expected_bundle;
    // Remember the source value on the edge that acknowledges this request.
    // A direct sample of the changing source bus at the destination must fail.
    always @(posedge src_clk)begin
        sampled_source=source_data;
        #0.001;
        if(cdc_reset_n && cdc_test.ack!=ack_seen)begin
            expected_bundle=sampled_source;expected_valid=1;ack_seen=cdc_test.ack;
        end
    end
    video_ddr_snapshot_cdc #(.WIDTH(128)) cdc_test(.src_clk(src_clk),.dst_clk(sys_clk),
        .reset_n(cdc_reset_n),.src_data(source_data),.snapshot(snapshot),.snapshot_pulse(snapshot_pulse));
    always @(posedge src_clk) if(cdc_reset_n) source_count<=source_count+1'b1;
    always @(negedge sys_clk) if(cdc_reset_n && snapshot_pulse)begin
        if(!expected_valid || snapshot!==expected_bundle)
            $fatal(1,"CDC snapshot does not match acknowledged source sample");
        if(snapshot[95:64]!==~snapshot[127:96] ||
           snapshot[63:32] !== (snapshot[127:96]^32'h55aa37c0) ||
           snapshot[31:0] !== snapshot[127:96]+32'd1)
            $fatal(1,"CDC incoherent snapshot %h",snapshot);
        coherent_samples=coherent_samples+1;
    end

    task automatic check(input bit ok,input string message);
        if(ok!==1'b1)$fatal(1,"DDR BOARD FAIL: %s",message);
    endtask
    task automatic board_reset;
        begin
            @(negedge sys_clk);rst_in=0;
            #1;check(!dut.controller_reset_n && !dut.core_reset_n,"KEY0 asynchronously resets both domains");
            repeat(4)@(negedge sys_clk);rst_in=1;
            repeat(7)begin @(negedge sys_clk);check(!dut.controller_reset_n,"startup hold too short");end
            wait(dut.controller_reset_n);
            #0.001;check(!dut.core_reset_n,"core reset must not release on free-clock edge");
            @(posedge ref_clk_p);#0.001;check(!dut.core_reset_n,"core reset needs two local edges");
            @(posedge ref_clk_p);#0.001;check(dut.core_reset_n,"core reset release missing");
        end
    endtask
    // Independently decode one complete TRV1 packet while core_clk is stopped.
    reg [7:0] packet [0:36];
    integer b,bit_number;
    reg [7:0] byte_value,sum;
    task automatic receive_packet;
        begin
            wait(!dut.uart.busy);
            for(b=0;b<37;b=b+1)begin
                @(negedge uart_tx);#555.555555;
                byte_value=0;
                for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
                    byte_value[bit_number]=uart_tx;#370.370370;
                end
                check(uart_tx===1'b1,"UART stop bit");packet[b]=byte_value;
            end
            check({packet[0],packet[1],packet[2],packet[3]}==32'h54525631,"UART magic");
            sum=0;for(b=0;b<36;b=b+1)sum=sum^packet[b];
            check(sum==packet[36],"UART checksum");
            check(packet[4]==2,"DDR packet type");
            check(packet[5][0]==0 && packet[5][3]==1 && packet[7]==8'he0,"stopped-core init timeout is observable");
        end
    endtask
    reg [127:0] stopped_snapshot;
    initial begin
        #1;rst_in=0;cdc_reset_n=0;
        dut.I_ips_ddr_top.model_init_enable=0;
        dut.I_ips_ddr_top.model_core_enable=0;
        repeat(4)@(negedge sys_clk);cdc_reset_n=1;
        // First show that independent watchdog/status/UART work without core.
        repeat(4)@(negedge sys_clk);rst_in=1;
        wait(dut.controller_reset_n);
        repeat(1200)@(negedge sys_clk);
        check(!ddr_init_done && hdmi_int_led && !init_over_rx,"init stall fails safely");
        check(!dut.axi_awvalid && !dut.axi_arvalid,"no pre-init native commands");
        receive_packet;
        dut.I_ips_ddr_top.model_core_enable=1;
        repeat(150)@(negedge sys_clk);
        check(coherent_samples>10,"CDC did not produce samples");
        @(negedge ref_clk_p);src_enable=0;
        repeat(20)@(negedge sys_clk);stopped_snapshot=snapshot;
        repeat(20)@(negedge sys_clk);
        check(snapshot===stopped_snapshot,"stopped-source CDC must hold last coherent data");
        src_enable=1;
        dut.I_ips_ddr_top.model_init_enable=1;
        board_reset;
        wait(ddr_init_done);
        wait(init_over_rx || hdmi_int_led);
        check(init_over_rx && !hdmi_int_led,"behavioral native memory BIST pass");
        check(dut.bist_compared_beats==765,"reduced-window exact comparison count");
        repeat(30)@(negedge sys_clk);
        check(dut.diag_payload[63:32]==765 && dut.diag_payload[15:8]==8'h15,"coherent pass packet flags/count");
        // A stopped core can leave init/locks high and a prior PASS snapshot.
        // The independent snapshot watchdog must clear PASS and report E4.
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_core_enable=0;
        repeat(100)@(negedge sys_clk);
        check(ddr_init_done && dut.diag_payload[12],"stop-only test must retain init/PLL high");
        check(hdmi_int_led && !init_over_rx && !dut.diag_payload[10] &&
              dut.diag_payload[11] && dut.diag_payload[31:24]==8'he4,"stale PASS must become watchdog failure");
        dut.I_ips_ddr_top.model_core_enable=1;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led && !init_over_rx,"clock recovery must not clear sticky watchdog");
        board_reset;
        wait(init_over_rx || hdmi_int_led);
        check(init_over_rx && !hdmi_int_led,"KEY0 clears clock watchdog and repeats test");
        // Init loss while a PASS snapshot is frozen also masks PASS immediately.
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_core_enable=0;
        dut.I_ips_ddr_top.model_drop_init=1;
        repeat(30)@(negedge sys_clk);
        check(!ddr_init_done && hdmi_int_led && !init_over_rx && !dut.diag_payload[10] &&
              dut.diag_payload[31:24]==8'he1,"stopped-core init loss must mask stale PASS");
        dut.I_ips_ddr_top.model_core_enable=1;
        dut.I_ips_ddr_top.model_drop_init=0;
        // KEY0 interrupts an in-flight native burst by resetting BOTH owners.
        board_reset;
        wait(dut.I_ips_ddr_top.native.writing);
        board_reset;
        wait(dut.I_ips_ddr_top.native.writing);
        // Lost init during traffic latches error without locally resetting
        // either endpoint or treating interrupted writes as completed.
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_drop_init=1;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led && dut.bist_error && dut.bist_error_code==1,"init loss is sticky BIST error");
        check(dut.controller_reset_n && dut.core_reset_n,"init loss must not reset only the BIST");
        dut.I_ips_ddr_top.model_drop_init=0;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led && dut.bist_error,"restored init does not clear failure");
        // KEY0 provides coordinated controller/BIST restart and fresh pass.
        board_reset;
        wait(init_over_rx || hdmi_int_led);
        check(init_over_rx && !hdmi_int_led,"KEY0 reinitializes and reruns BIST");
        // A PHY error remains diagnosable even when the core clock stops.
        @(negedge ref_clk_p);dut.I_ips_ddr_top.model_core_enable=0;
        dut.I_ips_ddr_top.model_init_fail=1;
        repeat(30)@(negedge sys_clk);
        check(hdmi_int_led && dut.diag_payload[31:24]==8'he2,"independent PHY failure status");
        $display("VIDEO_DDR_BOARD_PASS: coherent CDC, stopped-core UART/init timeout, stale-core watchdog and PASS masking, local reset, native BIST, sticky in-flight init loss, KEY0 in-flight restart");
        $finish;
    end
    initial begin #10000000;$fatal(1,"DDR board watchdog");end
endmodule
