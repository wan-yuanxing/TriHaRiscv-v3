`timescale 1ns/1ps
`default_nettype none
// Derived from frozen F2 raw-board structure; its original source stays intact.
// One physical frame -> checked raw/preview/input -> RAW/BOX/AVATAR static output.
// KEY1 MODE never resubmits raw or restarts HDMI/DDR. Artificial results/material.
// Source SHA256: 0ffc86b3800940ac2e28127fb706db38a8f95d253f06cd4dac707eeec17b61a3
// Coordinated KEY0 reset only; diagnostic completion is not CPU MMIO INPUT_READY.
// UART type6/9/8/10 reports capture, raw display, input readback and modes separately.
module video_mode_board_top #(
    parameter integer CLOCK_HZ=27_000_000,
    parameter integer STARTUP_CYCLES=CLOCK_HZ/1000,
    parameter integer INIT_TIMEOUT_CYCLES=CLOCK_HZ*5,
    parameter integer CORE_TIMEOUT_CYCLES=CLOCK_HZ,
    parameter integer HEARTBEAT_CYCLES=CLOCK_HZ/2,
    parameter integer UART_BAUD=115200,
    parameter integer UART_INTERVAL_CYCLES=CLOCK_HZ,
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600,
    parameter integer PAD_TOP=40,PAD_BOTTOM=40,
    parameter integer CAPTURE_TIMEOUT_CYCLES=625_000_000,
    parameter integer RX_WARMUP_FRAMES=128,
    parameter integer MODE_CLOCK_HZ=125000000,MODE_STABLE_MS=20
)(
    input wire sys_clk,rst_in,ref_clk_p,ref_clk_n,mode_button_n,
    input wire pixclk_in,hs_in,vs_in,de_in,
    input wire [7:0] r_in,g_in,b_in,
    output wire rstn_out,hd_scl,pix_clk,
    inout wire hd_sda,
    output wire hs_out,vs_out,de_out,
    output wire [7:0] r_out,g_out,b_out,
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
    video_preview_clock_reset clocks(.sys_clk(sys_clk),.reset_n(rst_in),.pixel_clk(pix_clk),
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
    wire [10:0] display_x,display_y;
    wire [23:0] rgb;
    wire display_hs,display_vs,display_de;
    video_timing timing(.pixel_clk(pix_clk),.reset_n(pixel_reset_n),.x(display_x),.y(display_y),
        .hsync(hs),.vsync(vs),.de(de),.frame_start(frame_start));
    // Display bank ownership follows the coordinated reset epoch, not RX/PLL enable.
    (* syn_preserve=1 *) reg [1:0] display_pixel_release;
    always @(posedge pix_clk or negedge controller_reset_n)
        if(!controller_reset_n)display_pixel_release<=0;
        else display_pixel_release<={display_pixel_release[0],1'b1};
    wire display_pixel_reset_n=display_pixel_release[1];
    // raw_display registers pixel controls twice; coordinates and SOF follow
    // the same two registers before entering the indivisible mode/pixel path.
    reg [10:0] raw_x_d0,raw_x_d1,raw_y_d0,raw_y_d1;
    reg raw_sof_d0,raw_sof_d1;
    always @(posedge pix_clk or negedge display_pixel_reset_n)begin
        if(!display_pixel_reset_n)begin raw_x_d0<=0;raw_x_d1<=0;raw_y_d0<=0;raw_y_d1<=0;raw_sof_d0<=0;raw_sof_d1<=0;end
        else begin raw_x_d0<=display_x;raw_x_d1<=raw_x_d0;raw_y_d0<=display_y;raw_y_d1<=raw_y_d0;
            raw_sof_d0<=frame_start;raw_sof_d1<=raw_sof_d0;end
    end
    wire bist_busy,bist_done,bist_error;
    wire [31:0] frame_id;
    wire [23:0] mode_pad_rgb;
    wire [10:0] mode_pad_x,mode_pad_y;
    wire [31:0] mode_pad_frame,mode_state,mode_request_seq,mode_committed_seq;
    wire [31:0] mode_request_count,mode_commit_count,mode_coalesced_count;
    wire mode_first_pixel,mode_error,mode_asset_ready;
    video_demo_mode_output #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
        .BUTTON_CLOCK_HZ(MODE_CLOCK_HZ),.BUTTON_STABLE_MS(MODE_STABLE_MS)) mode_output(
        .core_clk(core_clk),.core_reset_n(core_reset_n),.pixel_clk(pix_clk),.pixel_reset_n(display_pixel_reset_n),
        .mode_button_n(mode_button_n),.context_valid(bist_done&&!bist_error&&frame_id!=0),
        .context_frame_id(frame_id),.context_generation(32'd1),.context_slot(2'd0),
        .raw_x(raw_x_d1),.raw_y(raw_y_d1),.raw_sof(raw_sof_d1),.raw_rgb(rgb),
        .raw_de(display_de),.raw_hs(display_hs),.raw_vs(display_vs),
        .out_rgb(mode_pad_rgb),.out_x(mode_pad_x),.out_y(mode_pad_y),.out_frame_id(mode_pad_frame),
        .out_de(de_out),.out_hs(hs_out),.out_vs(vs_out),.out_sof(),.mode_first_pixel(mode_first_pixel),
        .mode_state(mode_state),.request_seq(mode_request_seq),.committed_seq(mode_committed_seq),
        .request_count(mode_request_count),.commit_count(mode_commit_count),.coalesced_count(mode_coalesced_count),
        .mode_error(mode_error),.asset_ready(mode_asset_ready));
    assign r_out=mode_pad_rgb[23:16];assign g_out=mode_pad_rgb[15:8];assign b_out=mode_pad_rgb[7:0];
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
    wire capture_ready;
    video_capture_startup_guard #(.STABLE_FRAMES(RX_WARMUP_FRAMES)) startup_guard(
        .pixel_clk(pixclk_in),.reset_n(ingress_pixel_reset_n),
        .mode_good(geometry_locked&&timing_locked&&rx_health_sync[1]),.rx_ready(rx_enable_sync[1]),
        .frame_start(frame_begin),.frame_end(frame_end),.frame_good(frame_good),
        .capture_ready(capture_ready));
    wire fifo_valid,fifo_ready,source_fault,source_overflow,arm_toggle,cancel;
    wire [47:0] fifo_data;
    video_capture_ingress #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) ingress(
        .pixel_clk(pixclk_in),.pixel_reset_n(ingress_pixel_reset_n),.core_clk(core_clk),.core_reset_n(core_reset_n),
        .pixel_valid(candidate),.pixel_rgb(candidate_rgb),.pixel_x(candidate_x),.pixel_y(candidate_y),
        .frame_start(frame_begin),.frame_end(frame_end),.frame_good(frame_good),
        .mode_good(capture_ready),.rx_ready(rx_enable_sync[1]),
        .arm_toggle(arm_toggle),.cancel(cancel),.m_valid(fifo_valid),.m_data(fifo_data),
        .m_ready(fifo_ready),.source_fault(source_fault),.overflow(source_overflow));
    wire capture_stream_valid,capture_stream_ready;
    wire [47:0] capture_stream_data;
    // Cut the DRM-output -> packet/fault/ready -> DMA-counter enable path.
    // This core-domain word retains ownership through stalls and errors.
    video_stream_register #(.DATA_WIDTH(48)) capture_register(
        .clk(core_clk),.reset_n(core_reset_n),.s_valid(fifo_valid),.s_ready(fifo_ready),.s_data(fifo_data),
        .m_valid(capture_stream_valid),.m_ready(capture_stream_ready),.m_data(capture_stream_data));
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
    wire [7:0] bist_phase,bist_error_code;
    wire [31:0] captured_pixels,preview_pixels,source_crc,ddr_crc,preview_crc,preview_ddr_crc,fifo_peak;
    wire [31:0] commits,completed_scans,read_lines,underflows;
    wire [31:0] input_pixels,input_written_bytes,raw_written_bytes,preview_written_bytes;
    wire [31:0] input_ddr_crc,input_checked_bytes,capture_frame_id,preprocess_version;
    wire [31:0] raw_base,preview_base,input_base;
    wire capture_complete,port_drained;
    // Free-clock supervision is sticky. Propagate it without clearing local
    // ownership or withdrawing published native/AXI commands on an error.
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg board_fault_core_meta,board_fault_core_sync;
    always @(posedge core_clk or negedge core_reset_n)
        if(!core_reset_n)begin board_fault_core_meta<=0;board_fault_core_sync<=0;end
        else begin board_fault_core_meta<=board_error;board_fault_core_sync<=board_fault_core_meta;end
    video_raw_engine #(.TIMEOUT_CYCLES(CAPTURE_TIMEOUT_CYCLES),.FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),.PAD_TOP(PAD_TOP),.PAD_BOTTOM(PAD_BOTTOM)) bist(
        .clk(core_clk),.reset_n(core_reset_n),.init_done(native_ready),
        .pixel_clk(pix_clk),.pixel_reset_n(display_pixel_reset_n),.pixel_x(display_x),.pixel_y(display_y),
        .pixel_hs(hs),.pixel_vs(vs),.pixel_de(de),.frame_start(frame_start),
        .out_rgb(rgb),.out_hs(display_hs),.out_vs(display_vs),.out_de(display_de),
        .m_valid(capture_stream_valid),.m_data(capture_stream_data),.m_ready(capture_stream_ready),
        .arm_toggle(arm_toggle),.cancel(cancel),.source_fault(source_fault||board_fault_core_sync),.overflow(source_overflow),
        .busy(bist_busy),.done(bist_done),.error(bist_error),.phase(bist_phase),.error_code(bist_error_code),
        .captured_pixels(captured_pixels),.preview_pixels(preview_pixels),.source_crc(source_crc),
        .ddr_crc(ddr_crc),.preview_crc(preview_crc),.preview_ddr_crc(preview_ddr_crc),.fifo_peak(fifo_peak),
        .input_pixels(input_pixels),.input_written_bytes(input_written_bytes),
        .raw_written_bytes(raw_written_bytes),.preview_written_bytes(preview_written_bytes),
        .input_ddr_crc(input_ddr_crc),.input_checked_bytes(input_checked_bytes),
        .capture_frame_id(capture_frame_id),.preprocess_version(preprocess_version),
        .raw_base(raw_base),.preview_base(preview_base),.input_base(input_base),
        .capture_complete(capture_complete),.port_drained(port_drained),
        .frame_id(frame_id),.commits(commits),.completed_scans(completed_scans),.read_lines(read_lines),.underflows(underflows),
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
    wire [7:0] core_flags={source_overflow,2'b00,all_pll_lock,(bist_error||mode_error),bist_done,bist_busy,ip_init_done};
    wire [223:0] capture_status={preview_ddr_crc,preview_crc,ddr_crc,source_crc,preview_pixels,captured_pixels,
        bist_error_code,bist_phase,core_flags,8'd6};
    wire [223:0] display_status={fifo_peak,read_lines,underflows,completed_scans,commits,frame_id,
        bist_error_code,bist_phase,core_flags,8'd9};
    wire [223:0] input_status={input_ddr_crc,input_checked_bytes,input_written_bytes,input_pixels,
        preprocess_version,capture_frame_id,bist_error_code,bist_phase,core_flags,8'd8};
    wire [223:0] mode_status={mode_coalesced_count,mode_commit_count,mode_request_count,
        mode_committed_seq,mode_request_seq,mode_state,bist_error_code,bist_phase,core_flags,8'd10};
    wire [895:0] core_status={mode_status,input_status,display_status,capture_status};
    wire [895:0] snapshot;
    wire snapshot_pulse;
    video_ddr_snapshot_cdc #(.WIDTH(896)) telemetry(.src_clk(core_clk),.dst_clk(free_clk),
        .reset_n(controller_reset_n),.src_data(core_status),.snapshot(snapshot),.snapshot_pulse(snapshot_pulse));
    wire uart_busy;
    reg uart_busy_q;
    reg [1:0] diag_kind;
    always @(posedge free_clk or negedge free_reset_n)begin
        if(!free_reset_n)begin uart_busy_q<=0;diag_kind<=0;end
        else begin uart_busy_q<=uart_busy;if(uart_busy_q&&!uart_busy)diag_kind<=diag_kind+1'b1;end
    end
    wire [223:0] selected_status=diag_kind==3?snapshot[895:672]:diag_kind==2?snapshot[671:448]:diag_kind==1?snapshot[447:224]:snapshot[223:0];
    reg [255:0] diag_payload;
    always @* begin
        diag_payload={heartbeat_sequence,selected_status};
        diag_payload[7:0]=diag_kind==3?8'd10:diag_kind==1?8'd9:diag_kind==2?8'd8:8'd6;
        diag_payload[8]=status_sync[0];
        diag_payload[10]=selected_status[10] && !selected_status[11] && !board_error;
        diag_payload[11]=selected_status[11] || board_error;
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
        .clk(free_clk),.reset_n(free_reset_n),.payload(diag_payload),.tx(uart_tx),.busy(uart_busy));
endmodule
`default_nettype wire
