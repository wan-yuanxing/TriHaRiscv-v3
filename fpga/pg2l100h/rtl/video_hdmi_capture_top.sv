`timescale 1ns/1ps
`default_nettype none
// Physical HDMI raw capture diagnostic with local output color bars.
// Coordinated-reset-only ingress FIFO; completed raw frame is checked by CRC.
// UART type5 does not publish the SoC three-branch CAPTURE_DONE event.
module video_hdmi_capture_top #(
    parameter integer CLOCK_HZ=27_000_000,
    parameter integer STARTUP_CYCLES=CLOCK_HZ/1000,
    parameter integer INIT_TIMEOUT_CYCLES=CLOCK_HZ*5,
    parameter integer CORE_TIMEOUT_CYCLES=CLOCK_HZ,
    parameter integer HEARTBEAT_CYCLES=CLOCK_HZ/2,
    parameter integer UART_BAUD=115200,
    parameter integer UART_INTERVAL_CYCLES=CLOCK_HZ,
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600,
    parameter integer CAPTURE_TIMEOUT_CYCLES=625_000_000
)(
    input wire sys_clk,rst_in,ref_clk_p,ref_clk_n,
    input wire pixclk_in,hs_in,vs_in,de_in,
    input wire [7:0] r_in,g_in,b_in,
    output wire rstn_out,hd_scl,pix_clk,
    inout wire hd_sda,
    output reg hs_out,vs_out,de_out,
    output reg [7:0] r_out,g_out,b_out,
    output wire heart_beat_led,ddr_init_done,init_over_rx,hdmi_int_led,uart_tx,
    output wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,
    output wire mem_ras_n,mem_cas_n,mem_we_n,mem_odt,
    output wire [14:0] mem_a,
    output wire [2:0] mem_ba,
    inout wire [3:0] mem_dqs,mem_dqs_n,
    inout wire [31:0] mem_dq,
    output wire [3:0] mem_dm
);
    wire free_clk,ref_clk,core_clk,core_reset_n,controller_reset_n;
    wire cfg_clk,locked,pixel_reset_n,cfg_reset_n;
    video_clock_reset clocks(.sys_clk(sys_clk),.reset_n(rst_in),.pixel_clk(pix_clk),
        .cfg_clk(cfg_clk),.locked(locked),.pixel_reset_n(pixel_reset_n),
        .cfg_reset_n(cfg_reset_n),.tx_reset_n(rstn_out));
    wire tx_scl,rx_scl,tx_done,tx_error,rx_done,rx_error,rx_configured;
    wire [31:0] raw_status;
    hdmi_tx_init tx(.clk_cfg(cfg_clk),.reset_n(rstn_out),.iic_scl(tx_scl),
        .iic_sda(hd_sda),.init_done(tx_done),.init_error(tx_error));
    hdmi_rx_init rx(.clk_cfg(cfg_clk),.reset_n(rstn_out&&tx_done),.iic_scl(rx_scl),
        .iic_sda(hd_sda),.init_done(rx_done),.link_configured(rx_configured),
        .init_error(rx_error),.status_word(raw_status));
    assign hd_scl=tx_done?rx_scl:tx_scl;
    wire hs,vs,de,frame_start;
    wire [23:0] rgb;
    video_pattern_core pattern(.pixel_clk(pix_clk),.reset_n(pixel_reset_n),
        .hsync(hs),.vsync(vs),.de(de),.frame_start(frame_start),.rgb(rgb));
    always @(posedge pix_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin hs_out<=0;vs_out<=0;de_out<=0;r_out<=0;g_out<=0;b_out<=0;end
        else begin hs_out<=hs;vs_out<=vs;de_out<=de;r_out<=rgb[23:16];g_out<=rgb[15:8];b_out<=rgb[7:0];end
    end
    (* syn_preserve=1 *) reg [1:0] rx_reset_release,rx_enable_sync,rx_health_sync;
    always @(posedge pixclk_in or negedge cfg_reset_n)begin
        if(!cfg_reset_n)begin rx_reset_release<=0;rx_enable_sync<=0;rx_health_sync<=0;end
        else begin
            rx_reset_release<={rx_reset_release[0],1'b1};
            rx_enable_sync<={rx_enable_sync[0],rx_done&&!rx_error};
            rx_health_sync<={rx_health_sync[0],mode_good_cfg};
        end
    end
    wire rx_reset_n=cfg_reset_n&&rx_reset_release[1];
    (* syn_preserve=1 *) reg [26:0] rx_capture;
    always @(negedge pixclk_in or negedge rx_reset_n)
        if(!rx_reset_n)rx_capture<=0;else rx_capture<={hs_in,vs_in,de_in,r_in,g_in,b_in};
    wire candidate,frame_begin,frame_end,frame_good,geometry_locked,timing_locked,timing_error;
    wire [23:0] candidate_rgb;
    wire [10:0] candidate_x,candidate_y;
    video_rx geometry(.pixel_clk(pixclk_in),.reset_n(rx_reset_n),.enable(rx_enable_sync[1]),
        .rx_ready(rx_enable_sync[1]),.hs_in(rx_capture[26]),.vs_in(rx_capture[25]),.de_in(rx_capture[24]),
        .rgb_in(rx_capture[23:0]),.pixel_valid(candidate),.rgb_out(candidate_rgb),
        .x(candidate_x),.y(candidate_y),.frame_start(frame_begin),.frame_end(frame_end),
        .frame_good(frame_good),.mode_locked(geometry_locked));
    wire [15:0] ha,va,ht,vt,hw,vw,hf,hb,vf,vb;
    wire [31:0] good,bad;
    video_rx_measure measure(.pixel_clk(pixclk_in),.reset_n(rx_reset_n),.enable(rx_enable_sync[1]),
        .hs_in(rx_capture[26]),.vs_in(rx_capture[25]),.de_in(rx_capture[24]),
        .timing_locked(timing_locked),.mode_error(timing_error),.h_active(ha),.v_active(va),
        .h_total(ht),.v_total(vt),.h_sync(hw),.v_sync(vw),.h_front(hf),.h_back(hb),
        .v_front(vf),.v_back(vb),.good_frames(good),.bad_frames(bad));
    wire [31:0] rx_snapshot,hz;
    wire fresh,alive,freq_good;
    video_rx_telemetry #(.STATUS_WIDTH(32)) rx_telemetry(.cfg_clk(cfg_clk),.pixel_clk(pixclk_in),
        .reset_n(cfg_reset_n),.pixel_status({30'd0,timing_error,geometry_locked&&timing_locked}),
        .snapshot(rx_snapshot),.snapshot_valid(fresh),.pixel_hz(hz),.clock_alive(alive),.frequency_good(freq_good));
    wire mode_good_cfg=fresh&&freq_good&&rx_snapshot[0]&&rx_done&&rx_configured&&!tx_error&&!rx_error;
    // Ingress reset never follows HDMI lock/readiness loss or DDR init loss.
    // Only global KEY0/startup assertion and local pixel release clear FIFO.
    (* syn_preserve=1 *) reg [1:0] ingress_pixel_release;
    always @(posedge pixclk_in or negedge controller_reset_n)
        if(!controller_reset_n)ingress_pixel_release<=0;
        else ingress_pixel_release<={ingress_pixel_release[0],1'b1};
    wire ingress_pixel_reset_n=ingress_pixel_release[1];
    wire fifo_valid,fifo_ready,source_fault,source_overflow,arm_toggle,cancel;
    wire [47:0] fifo_data;
    video_capture_ingress #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) ingress(
        .pixel_clk(pixclk_in),.pixel_reset_n(ingress_pixel_reset_n),.core_clk(core_clk),.core_reset_n(core_reset_n),
        .pixel_valid(candidate),.pixel_rgb(candidate_rgb),.pixel_x(candidate_x),.pixel_y(candidate_y),
        .frame_start(frame_begin),.frame_end(frame_end),.frame_good(frame_good),
        .mode_good(geometry_locked&&timing_locked&&rx_health_sync[1]),.rx_ready(rx_enable_sync[1]),
        .arm_toggle(arm_toggle),.cancel(cancel),.m_valid(fifo_valid),.m_data(fifo_data),
        .m_ready(fifo_ready),.source_fault(source_fault),.overflow(source_overflow));
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
    assign controller_reset_n=free_reset_n && startup_done;
    // Only coordinated KEY0/startup reset clears this pipe. In particular,
    // init/PLL loss never resets the engine and discards outstanding traffic.
    (* syn_preserve=1 *) reg [1:0] core_release;
    always @(posedge core_clk or negedge controller_reset_n)
        if(!controller_reset_n)core_release<=0;
        else core_release<={core_release[0],1'b1};
    // The local flop already asserts asynchronously. Using its Q alone keeps
    // the raw startup/reset net out of packer/FIFO ready and RAM enable cones.
    assign core_reset_n=core_release[1];
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
    wire [31:0] captured_pixels,checked_bytes,source_crc,ddr_crc,frame_tag,fifo_peak;
    video_capture_engine #(.TIMEOUT_CYCLES(CAPTURE_TIMEOUT_CYCLES),.FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)) bist(
        .clk(core_clk),.reset_n(core_reset_n),.init_done(native_ready),
        .m_valid(fifo_valid),.m_data(fifo_data),.m_ready(fifo_ready),
        .arm_toggle(arm_toggle),.cancel(cancel),.source_fault(source_fault),.overflow(source_overflow),
        .busy(bist_busy),.done(bist_done),.error(bist_error),.phase(bist_phase),.error_code(bist_error_code),
        .captured_pixels(captured_pixels),.checked_bytes(checked_bytes),.source_crc(source_crc),
        .ddr_crc(ddr_crc),.frame_tag(frame_tag),.fifo_peak(fifo_peak),
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
    (* syn_preserve=1 *) reg [3:0] hdmi_status_meta,hdmi_status_sync;
    always @(posedge free_clk or negedge controller_reset_n)begin
        if(!controller_reset_n)begin hdmi_status_meta<=0;hdmi_status_sync<=0;end
        else begin hdmi_status_meta<={tx_error||rx_error,locked,tx_done,mode_good_cfg};hdmi_status_sync<=hdmi_status_meta;end
    end
    reg hdmi_lock_seen;
    always @(posedge free_clk or negedge controller_reset_n)
        if(!controller_reset_n)hdmi_lock_seen<=0;else if(hdmi_status_sync[2])hdmi_lock_seen<=1;
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
                end else if(hdmi_status_sync[3])begin
                    board_error<=1;board_error_code<=8'he5;
                end else if(hdmi_lock_seen && !hdmi_status_sync[2])begin
                    board_error<=1;board_error_code<=8'he6;
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
    wire [7:0] core_flags={source_overflow,2'b00,all_pll_lock,bist_error,bist_done,bist_busy,ip_init_done};
    wire [223:0] core_status={fifo_peak,frame_tag,ddr_crc,source_crc,checked_bytes,captured_pixels,
        bist_error_code,bist_phase,core_flags,8'd5};
    wire [223:0] snapshot;
    wire snapshot_pulse;
    video_ddr_snapshot_cdc #(.WIDTH(224)) telemetry(.src_clk(core_clk),.dst_clk(free_clk),
        .reset_n(controller_reset_n),.src_data(core_status),.snapshot(snapshot),.snapshot_pulse(snapshot_pulse));
    reg [255:0] diag_payload;
    always @* begin
        diag_payload={heartbeat_sequence,snapshot};
        diag_payload[7:0]=8'd5;
        diag_payload[8]=status_sync[0];
        diag_payload[10]=snapshot[10] && !snapshot[11] && !board_error;
        diag_payload[11]=snapshot[11] || board_error;
        diag_payload[12]=&status_sync[5:1];
        diag_payload[13]=hdmi_status_sync[0];
        diag_payload[14]=hdmi_status_sync[1]&&hdmi_status_sync[2];
        if(board_error)diag_payload[31:24]=board_error_code;
    end
    assign heart_beat_led=heartbeat_sequence[0];
    assign ddr_init_done=status_sync[0];
    assign init_over_rx=diag_payload[10]&&diag_payload[13]&&diag_payload[14];
    assign hdmi_int_led=diag_payload[11];
    video_diag_uart #(.CLOCK_HZ(CLOCK_HZ),.BAUD(UART_BAUD),.INTERVAL_CYCLES(UART_INTERVAL_CYCLES)) uart(
        .clk(free_clk),.reset_n(free_reset_n),.payload(diag_payload),.tx(uart_tx));
endmodule
`default_nettype wire
