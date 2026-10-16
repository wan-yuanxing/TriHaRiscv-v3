`timescale 1ns/1ps
`default_nettype none
// Standalone destructive native-port DDR acceptance target. No HDMI pins.
// sys_clk is the independent 27 MHz D18 oscillator; DDR uses N3/N2 at 125 MHz.
// TRV1 type 2 payload (little endian): byte0=2; byte1 flags init/busy/done/
// error/all-PLL at bits0..4; byte2=phase; byte3=error code; bytes4..7=compared;
// bytes8..11=first error native WORD address (zero extended); bytes12..15=low32
// of256-bit first error XOR; bytes16..19=low window BYTE offset; bytes20..23=
// high window BYTE offset; bytes24..27=window beats; bytes28..31=free-clock
// heartbeat sequence (increments every0.5s by default). Default high base is
// 0x3ff00000, windows each1MiB, finite pass count3,014,685 compared256-bit beats.
// Independent monitor codes: E0 init timeout, E1 init/PLL loss after init,
// E2 PHY initialization failure, E3 alignment error, E4 stale core snapshot.
// All stay until KEY0. Any failure masks the packet done flag and PASS LED.
module video_ddr_bist_top #(
    parameter integer CLOCK_HZ=27_000_000,
    parameter integer STARTUP_CYCLES=CLOCK_HZ/1000,
    parameter integer INIT_TIMEOUT_CYCLES=CLOCK_HZ*5,
    parameter integer CORE_TIMEOUT_CYCLES=CLOCK_HZ,
    parameter integer HEARTBEAT_CYCLES=CLOCK_HZ/2,
    parameter integer UART_BAUD=115200,
    parameter integer UART_INTERVAL_CYCLES=CLOCK_HZ,
    parameter integer BIST_WINDOW_BEATS=32768,
    parameter integer BIST_BURST_BEATS=16,
    parameter integer BIST_TIMEOUT_CYCLES=125_000_000
)(
    input wire sys_clk,rst_in,ref_clk_p,ref_clk_n,
    output wire heart_beat_led,ddr_init_done,init_over_rx,hdmi_int_led,uart_tx,
    output wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,
    output wire mem_ras_n,mem_cas_n,mem_we_n,mem_odt,
    output wire [14:0] mem_a,
    output wire [2:0] mem_ba,
    inout wire [3:0] mem_dqs,mem_dqs_n,
    inout wire [31:0] mem_dq,
    output wire [3:0] mem_dm
);
    wire free_clk,ref_clk,core_clk;
    GTP_CLKBUFG free_clk_ibufg(.CLKIN(sys_clk),.CLKOUT(free_clk));
    // Match the original standalone differential-buffer structure. Internal
    // GPLL/PPLL feedback and PHY reset/training topology stay inside pinned IP.
    GTP_INBUFDS refclk_inbuf(.I(ref_clk_p),.IB(ref_clk_n),.O(ref_clk));
    localparam integer SW=STARTUP_CYCLES>1?$clog2(STARTUP_CYCLES):1;
    localparam integer TW=INIT_TIMEOUT_CYCLES>1?$clog2(INIT_TIMEOUT_CYCLES):1;
    localparam integer HW=HEARTBEAT_CYCLES>1?$clog2(HEARTBEAT_CYCLES):1;
    localparam integer CW=CORE_TIMEOUT_CYCLES>1?$clog2(CORE_TIMEOUT_CYCLES):1;
    (* syn_preserve=1 *) reg [1:0] free_release;
    always @(posedge free_clk or negedge rst_in)
        if(!rst_in)free_release<=0;else free_release<={free_release[0],1'b1};
    wire free_reset_n=rst_in && free_release[1];
    reg [SW-1:0] startup_count;
    reg startup_done;
    always @(posedge free_clk or negedge free_reset_n)begin
        if(!free_reset_n)begin startup_count<=0;startup_done<=0;end
        else if(!startup_done)begin
            if(startup_count==STARTUP_CYCLES-1)startup_done<=1;
            else startup_count<=startup_count+1'b1;
        end
    end
    wire controller_reset_n=free_reset_n && startup_done;
    // Only coordinated KEY0/startup reset clears this pipe. In particular,
    // init/PLL loss never resets the engine and discards outstanding traffic.
    (* syn_preserve=1 *) reg [1:0] core_release;
    always @(posedge core_clk or negedge controller_reset_n)
        if(!controller_reset_n)core_release<=0;
        else core_release<={core_release[0],1'b1};
    wire core_reset_n=controller_reset_n && core_release[1];
    // Engine leaves reset before initialization so its status is observable;
    // it waits on native_ready and never issues pre-init commands. The test
    // starts exactly once per coordinated reset, including after init loss.
    wire pll_lock,phy_pll_lock,gpll_lock,rst_gpll_lock,ddrphy_cpd_lock;
    wire ip_init_done,ip_init_fail,align_error;
    wire all_pll_lock=pll_lock && phy_pll_lock && gpll_lock && rst_gpll_lock && ddrphy_cpd_lock;
    wire native_ready=ip_init_done && all_pll_lock && !ip_init_fail && !align_error;
    wire [27:0] axi_awaddr,axi_araddr;
    wire axi_awuser_ap,axi_aruser_ap,axi_awvalid,axi_arvalid,axi_awready,axi_arready;
    wire [3:0] axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen;
    wire [255:0] axi_wdata,axi_rdata;
    wire [31:0] axi_wstrb;
    wire axi_wready,axi_wusero_last,axi_rlast,axi_rvalid;
    wire [3:0] axi_wusero_id,axi_rid;
    wire bist_busy,bist_done,bist_error;
    wire [7:0] bist_phase,bist_error_code;
    wire [31:0] bist_compared_beats;
    wire [27:0] bist_first_error_addr;
    wire [255:0] bist_first_error_xor;
    ddr_native_bist #(.TIMEOUT_CYCLES(BIST_TIMEOUT_CYCLES),.WINDOW_BEATS(BIST_WINDOW_BEATS),
        .BURST_BEATS(BIST_BURST_BEATS)) bist(
        .clk(core_clk),.reset_n(core_reset_n),.init_done(native_ready),
        .busy(bist_busy),.done(bist_done),.error(bist_error),.phase(bist_phase),
        .error_code(bist_error_code),.compared_beats(bist_compared_beats),
        .first_error_addr(bist_first_error_addr),.first_error_xor(bist_first_error_xor),
        .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),
        .axi_awlen(axi_awlen),.axi_awready(axi_awready),.axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),
        .axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),
        .axi_arlen(axi_arlen),.axi_arready(axi_arready),.axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid));

    // Exact standalone hierarchy is required by BOTH the FDC and priority RCF.
    ddr3_test #(.MEM_ROW_WIDTH(15),.MEM_COLUMN_WIDTH(10),.MEM_BANK_WIDTH(3),
        .MEM_DQ_WIDTH(32),.MEM_DM_WIDTH(4),.MEM_DQS_WIDTH(4),.CTRL_ADDR_WIDTH(28)) I_ips_ddr_top(
        .ref_clk(ref_clk),.resetn(controller_reset_n),.core_clk(core_clk),
        .pll_lock(pll_lock),.phy_pll_lock(phy_pll_lock),.gpll_lock(gpll_lock),
        .rst_gpll_lock(rst_gpll_lock),.ddrphy_cpd_lock(ddrphy_cpd_lock),.ddr_init_done(ip_init_done),
        .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),
        .axi_awlen(axi_awlen),.axi_awready(axi_awready),.axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),
        .axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),
        .axi_arlen(axi_arlen),.axi_arready(axi_arready),.axi_arvalid(axi_arvalid),
        .axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid),
        // HDMI reference-equivalent APB/debug inactive inputs, all sized/known.
        .apb_clk(1'b0),.apb_rst_n(1'b1),.apb_sel(1'b0),.apb_enable(1'b0),
        .apb_addr(8'd0),.apb_write(1'b0),.apb_ready(),.apb_wdata(16'd0),.apb_rdata(),
        .mem_cs_n(mem_cs_n),.mem_rst_n(mem_rst_n),.mem_ck(mem_ck),.mem_ck_n(mem_ck_n),
        .mem_cke(mem_cke),.mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),.mem_we_n(mem_we_n),
        .mem_odt(mem_odt),.mem_a(mem_a),.mem_ba(mem_ba),.mem_dqs(mem_dqs),
        .mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm),
        .dbg_gate_start(1'b0),.dbg_cpd_start(1'b0),.dbg_ddrphy_rst_n(1'b1),.dbg_gpll_scan_rst(1'b0),
        .samp_position_dyn_adj(1'b0),.init_samp_position_even(32'd0),.init_samp_position_odd(32'd0),
        .wrcal_position_dyn_adj(1'b0),.init_wrcal_position(32'd0),.force_read_clk_ctrl(1'b0),
        .init_slip_step(16'd0),.init_read_clk_ctrl(12'd0),
        .debug_cpd_offset_adj(1'b0),.debug_cpd_offset_dir(1'b0),.debug_cpd_offset(10'd0),
        .ck_dly_en(1'b0),.init_ck_dly_step(8'd0),.dbg_ddrphy_init_fail(ip_init_fail),.align_error(align_error));

    // Independent single-bit observations: no bundled consistency is assumed.
    // These report missing init / PHY failure even when core_clk never starts.
    wire [7:0] ip_status={align_error,ip_init_fail,ddrphy_cpd_lock,rst_gpll_lock,
                          gpll_lock,phy_pll_lock,pll_lock,ip_init_done};
    (* syn_preserve=1 *) reg [7:0] status_meta,status_sync;
    always @(posedge free_clk or negedge controller_reset_n)begin
        if(!controller_reset_n)begin status_meta<=0;status_sync<=0;end
        else begin status_meta<=ip_status;status_sync<=status_meta;end
    end
    reg [TW-1:0] init_wait_count;
    reg [CW-1:0] snapshot_age;
    reg init_seen,board_error;
    reg [7:0] board_error_code;
    always @(posedge free_clk or negedge controller_reset_n)begin
        if(!controller_reset_n)begin
            init_wait_count<=0;snapshot_age<=0;init_seen<=0;board_error<=0;board_error_code<=0;
        end else begin
            if(!init_seen || snapshot_pulse)snapshot_age<=0;
            else if(snapshot_age<CORE_TIMEOUT_CYCLES-1)snapshot_age<=snapshot_age+1'b1;
            if(status_sync[0] && (&status_sync[5:1]))init_seen<=1;
            if(!init_seen && init_wait_count<INIT_TIMEOUT_CYCLES-1)init_wait_count<=init_wait_count+1'b1;
            if(!board_error)begin
                if(status_sync[6])begin board_error<=1;board_error_code<=8'he2;end
                else if(status_sync[7])begin board_error<=1;board_error_code<=8'he3;end
                else if(init_seen && !(status_sync[0] && (&status_sync[5:1])))begin
                    board_error<=1;board_error_code<=8'he1;
                end else if(!init_seen && !(status_sync[0] && (&status_sync[5:1])) &&
                            init_wait_count==INIT_TIMEOUT_CYCLES-1)begin
                    board_error<=1;board_error_code<=8'he0;
                end else if(init_seen && !snapshot_pulse && snapshot_age==CORE_TIMEOUT_CYCLES-1)begin
                    board_error<=1;board_error_code<=8'he4;
                end
            end
        end
    end
    reg [HW-1:0] heartbeat_count;
    reg [31:0] heartbeat_sequence;
    always @(posedge free_clk or negedge free_reset_n)begin
        if(!free_reset_n)begin heartbeat_count<=0;heartbeat_sequence<=0;end
        else if(heartbeat_count==HEARTBEAT_CYCLES-1)begin
            heartbeat_count<=0;heartbeat_sequence<=heartbeat_sequence+1'b1;
        end else heartbeat_count<=heartbeat_count+1'b1;
    end
    wire [7:0] core_flags={3'd0,all_pll_lock,bist_error,bist_done,bist_busy,ip_init_done};
    // Only LOW32 of the 256-bit first-error XOR is transmitted. A zero UART XOR
    // therefore does not exclude upper-lane corruption; error/code stay valid.
    wire [127:0] core_status={bist_first_error_xor[31:0],4'd0,bist_first_error_addr,
        bist_compared_beats,bist_error_code,bist_phase,core_flags,8'd2};
    wire [127:0] snapshot;
    wire snapshot_pulse;
    video_ddr_snapshot_cdc #(.WIDTH(128)) telemetry(.src_clk(core_clk),.dst_clk(free_clk),
        .reset_n(controller_reset_n),.src_data(core_status),.snapshot(snapshot),.snapshot_pulse(snapshot_pulse));
    localparam [31:0] WINDOW_BEATS_DIAG=BIST_WINDOW_BEATS;
    localparam [31:0] HIGH_BASE_BYTES=32'h40000000-BIST_WINDOW_BEATS*32;
    reg [255:0] diag_payload;
    always @* begin
        diag_payload={heartbeat_sequence,WINDOW_BEATS_DIAG,HIGH_BASE_BYTES,32'd0,snapshot};
        diag_payload[7:0]=8'd2;
        diag_payload[8]=status_sync[0];
        diag_payload[10]=snapshot[10] && !snapshot[11] && !board_error;
        diag_payload[11]=snapshot[11] || board_error;
        diag_payload[12]=&status_sync[5:1];
        if(board_error)diag_payload[31:24]=board_error_code;
    end
    assign heart_beat_led=heartbeat_sequence[0];
    assign ddr_init_done=status_sync[0];
    assign init_over_rx=snapshot[10] && !snapshot[11] && !board_error;
    assign hdmi_int_led=snapshot[11] || board_error;
    wire uart_busy;
    video_diag_uart #(.CLOCK_HZ(CLOCK_HZ),.BAUD(UART_BAUD),.INTERVAL_CYCLES(UART_INTERVAL_CYCLES))
        uart(.clk(free_clk),.reset_n(free_reset_n),.payload(diag_payload),.tx(uart_tx),.busy(uart_busy));
`ifndef SYNTHESIS
    initial if(STARTUP_CYCLES<1 || INIT_TIMEOUT_CYCLES<1 || CORE_TIMEOUT_CYCLES<1 || HEARTBEAT_CYCLES<1)
        $fatal(1,"Invalid DDR board clock/reset/diagnostic parameter");
`endif
endmodule

// The source holds the entire bundle from request until the NEXT request.
// req/ack cross two flops; destination waits one extra edge after ack before
// sampling. The FDC bounds bundle delay to80ns (< the111ns minimum settling).
module video_ddr_snapshot_cdc #(parameter integer WIDTH=128)(
    input wire src_clk,dst_clk,reset_n,input wire [WIDTH-1:0] src_data,
    output reg [WIDTH-1:0] snapshot,output reg snapshot_pulse
);
    reg request,ack;
    (* syn_preserve=1 *) reg req_meta,req_sync,ack_meta,ack_sync;
    (* syn_preserve=1 *) reg [WIDTH-1:0] stable_status;
    reg pending,capture_pending;
    (* syn_preserve=1 *) reg [1:0] source_release;
    always @(posedge src_clk or negedge reset_n)
        if(!reset_n)source_release<=0;else source_release<={source_release[0],1'b1};
    wire source_reset_n=reset_n && source_release[1];
    always @(posedge src_clk or negedge source_reset_n)begin
        if(!source_reset_n)begin req_meta<=0;req_sync<=0;ack<=0;stable_status<=0;end
        else begin
            req_meta<=request;req_sync<=req_meta;
            if(req_sync!=ack)begin stable_status<=src_data;ack<=req_sync;end
        end
    end
    always @(posedge dst_clk or negedge reset_n)begin
        if(!reset_n)begin
            request<=0;ack_meta<=0;ack_sync<=0;pending<=0;capture_pending<=0;
            snapshot<=0;snapshot_pulse<=0;
        end else begin
            ack_meta<=ack;ack_sync<=ack_meta;snapshot_pulse<=0;
            if(!pending && !capture_pending)begin request<=~request;pending<=1;end
            if(pending && ack_sync==request)begin pending<=0;capture_pending<=1;end
            if(capture_pending)begin snapshot<=stable_status;snapshot_pulse<=1;capture_pending<=0;end
        end
    end
endmodule
`default_nettype wire
