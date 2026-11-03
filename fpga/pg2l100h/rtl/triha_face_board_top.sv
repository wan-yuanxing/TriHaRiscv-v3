`timescale 1ns/1ps
`default_nettype none
// Final face application board top.
//
// HDMI capture, the TriHa application CPU, the B03 frame service and HDMI
// scanout share the single native DDR owner. The DDR IP supplies the 125 MHz
// video/DDR-user clock. CPU and B03 run from the separate 50 MHz compute PLL;
// triha_face_system contains the AXI CDC at that boundary.
module triha_face_full_top #(
    parameter integer CLOCK_HZ=27_000_000,
    parameter integer STARTUP_CYCLES=CLOCK_HZ/1000,
    parameter integer INIT_TIMEOUT_CYCLES=CLOCK_HZ*5,
    parameter integer UART_BAUD=115200,
    parameter integer UART_INTERVAL_CYCLES=CLOCK_HZ,
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600,
    parameter integer PAD_TOP=40,
    parameter integer PAD_BOTTOM=40,
    parameter integer RX_WARMUP_FRAMES=128,
    // Minimal face-box demonstration: keep the CPU control path, but omit
    // private instruction/data caches so the complete B03 graph and BOX
    // renderer fit the PG2L100H device.
    parameter integer CACHE_ENABLE=0,
    parameter integer ENABLE_MINIMAL_BOX=0,
    parameter integer ENABLE_AVATAR=1,
    // Full CPU control remains selectable; the board default uses the
    // resource/timing-bounded control profile. CPU/B03 run at 50 MHz;
    // capture, UART/model-loader and DDR/video use the 125 MHz user clock.
    parameter integer MINIMAL_CONTROL_CPU=1,
    parameter integer ENABLE_HARDWARE_POST=0,
    parameter integer TRUSTED_MODEL=1,
    // Resource profile for the minimum face-box application.  Two dense
    // output lanes keep the same fixed 16-row ABI while reducing the number
    // of replicated APM/accumulator slices that placement must pack.
    parameter integer M_LANES=2,
    parameter integer QUANTIZER_LANES=1
)(
    input wire sys_clk,rst_in,ref_clk_p,ref_clk_n,uart_rx,mode_button_n,
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
    wire free_clk,ref_clk,ddr_clk,compute_clk,video_reset_n,controller_reset_n;
    wire cfg_clk,locked,pixel_reset_n,cfg_reset_n;
    video_preview_clock_reset clocks(
        .sys_clk(sys_clk),.reset_n(rst_in),.pixel_clk(pix_clk),.cfg_clk(cfg_clk),
        .locked(locked),.pixel_reset_n(pixel_reset_n),.cfg_reset_n(cfg_reset_n),
        .tx_reset_n(rstn_out));

    wire tx_scl,rx_scl,tx_done,tx_error,rx_done,rx_error,rx_configured;
    wire [31:0] rx_status;
    hdmi_tx_init tx(.clk_cfg(cfg_clk),.reset_n(rstn_out),.iic_scl(tx_scl),.iic_sda(hd_sda),
        .init_done(tx_done),.init_error(tx_error));
    hdmi_rx_init rx(.clk_cfg(cfg_clk),.reset_n(rstn_out&&tx_done),.iic_scl(rx_scl),.iic_sda(hd_sda),
        .init_done(rx_done),.link_configured(rx_configured),.init_error(rx_error),.status_word(rx_status));
    assign hd_scl=tx_done?rx_scl:tx_scl;

    wire hs,vs,de,frame_start;
    wire [10:0] display_x,display_y;
    video_timing timing(.pixel_clk(pix_clk),.reset_n(pixel_reset_n),.x(display_x),.y(display_y),
        .hsync(hs),.vsync(vs),.de(de),.frame_start(frame_start));

    GTP_CLKBUFG free_clk_ibufg(.CLKIN(sys_clk),.CLKOUT(free_clk));
    GTP_INBUFDS refclk_inbuf(.I(ref_clk_p),.IB(ref_clk_n),.O(ref_clk));
    localparam integer SW=STARTUP_CYCLES>1?$clog2(STARTUP_CYCLES):1;
    (* syn_preserve=1 *) reg [1:0] free_release;
    reg [SW-1:0] startup_count;
    reg startup_done;
    always @(posedge free_clk or negedge rst_in) begin
        if(!rst_in) free_release<=0;
        else free_release<={free_release[0],1'b1};
    end
    wire free_reset_n=rst_in&&free_release[1];
    always @(posedge free_clk or negedge free_reset_n) begin
        if(!free_reset_n) begin startup_count<=0;startup_done<=0;end
        else if(!startup_done) begin
            if(startup_count==STARTUP_CYCLES-1) startup_done<=1;
            else startup_count<=startup_count+1'b1;
        end
    end
    assign controller_reset_n=free_reset_n&&startup_done;
    wire compute_pll_lock;
    triha_compute_pll compute_clock_gen(
        .clkin1(ref_clk),.clkout0(compute_clk),.lock(compute_pll_lock));
    // PLL loss starts one coordinated application reset epoch. DDR PHY reset
    // remains controlled by the independent board startup sequence.
    wire application_reset_n=controller_reset_n&&compute_pll_lock;
    (* syn_preserve=1 *) reg [1:0] core_release,display_release,ingress_release;
    always @(posedge ddr_clk or negedge application_reset_n)
        if(!application_reset_n) core_release<=0;
        else core_release<={core_release[0],1'b1};
    assign video_reset_n=core_release[1];
    always @(posedge pix_clk or negedge application_reset_n)
        if(!application_reset_n) display_release<=0;
        else display_release<={display_release[0],1'b1};
    wire display_reset_n=display_release[1];
    always @(posedge pixclk_in or negedge application_reset_n)
        if(!application_reset_n) ingress_release<=0;
        else ingress_release<={ingress_release[0],1'b1};
    wire ingress_reset_n=ingress_release[1];

    (* syn_preserve=1 *) reg [1:0] rx_release,rx_enable_sync,rx_health_sync;
    wire mode_good_cfg;
    always @(posedge pixclk_in or negedge cfg_reset_n) begin
        if(!cfg_reset_n) begin rx_release<=0;rx_enable_sync<=0;rx_health_sync<=0;end
        else begin
            rx_release<={rx_release[0],1'b1};
            rx_enable_sync<={rx_enable_sync[0],rx_done&&!rx_error};
            rx_health_sync<={rx_health_sync[0],mode_good_cfg};
        end
    end
    wire rx_reset_n=cfg_reset_n&&rx_release[1];
    (* syn_preserve=1 *) reg [26:0] rx_capture;
    always @(negedge pixclk_in or negedge rx_reset_n)
        if(!rx_reset_n) rx_capture<=0;
        else rx_capture<={hs_in,vs_in,de_in,r_in,g_in,b_in};
    wire candidate,frame_begin,frame_end,frame_good,geometry_locked,timing_locked,timing_error;
    wire [23:0] candidate_rgb;
    wire [10:0] candidate_x,candidate_y;
    video_rx geometry(.pixel_clk(pixclk_in),.reset_n(rx_reset_n),.enable(rx_enable_sync[1]),
        .rx_ready(rx_enable_sync[1]),.hs_in(rx_capture[26]),.vs_in(rx_capture[25]),.de_in(rx_capture[24]),
        .rgb_in(rx_capture[23:0]),.pixel_valid(candidate),.rgb_out(candidate_rgb),
        .x(candidate_x),.y(candidate_y),.frame_start(frame_begin),.frame_end(frame_end),
        .frame_good(frame_good),.mode_locked(geometry_locked));
    wire [15:0] ha,va,ht,vt,hw,vw,hf,hb,vf,vb;
    wire [31:0] good,bad,rx_snapshot,hz;
    wire fresh,alive,freq_good;
    video_rx_measure measure(.pixel_clk(pixclk_in),.reset_n(rx_reset_n),.enable(rx_enable_sync[1]),
        .hs_in(rx_capture[26]),.vs_in(rx_capture[25]),.de_in(rx_capture[24]),
        .timing_locked(timing_locked),.mode_error(timing_error),.h_active(ha),.v_active(va),
        .h_total(ht),.v_total(vt),.h_sync(hw),.v_sync(vw),.h_front(hf),.h_back(hb),
        .v_front(vf),.v_back(vb),.good_frames(good),.bad_frames(bad));
    video_rx_telemetry #(.STATUS_WIDTH(32)) rx_telemetry(.cfg_clk(cfg_clk),.pixel_clk(pixclk_in),
        .reset_n(cfg_reset_n),.pixel_status({30'd0,timing_error,geometry_locked&&timing_locked}),
        .snapshot(rx_snapshot),.snapshot_valid(fresh),.pixel_hz(hz),.clock_alive(alive),.frequency_good(freq_good));
    assign mode_good_cfg=fresh&&freq_good&&rx_snapshot[0]&&rx_done&&rx_configured&&!tx_error&&!rx_error;
    wire capture_ready;
    video_capture_startup_guard #(.STABLE_FRAMES(RX_WARMUP_FRAMES)) startup_guard(
        .pixel_clk(pixclk_in),.reset_n(ingress_reset_n),
        .mode_good(geometry_locked&&timing_locked&&rx_health_sync[1]),.rx_ready(rx_enable_sync[1]),
        .frame_start(frame_begin),.frame_end(frame_end),.frame_good(frame_good),.capture_ready(capture_ready));
    wire fifo_valid,fifo_ready,source_fault,source_overflow,arm_toggle,cancel;
    wire [47:0] fifo_data;
    video_capture_ingress #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),.ENABLE_REARM(1)) ingress(
        .pixel_clk(pixclk_in),.pixel_reset_n(ingress_reset_n),.core_clk(ddr_clk),.core_reset_n(video_reset_n),
        .pixel_valid(candidate),.pixel_rgb(candidate_rgb),.pixel_x(candidate_x),.pixel_y(candidate_y),
        .frame_start(frame_begin),.frame_end(frame_end),.frame_good(frame_good),
        .mode_good(capture_ready),.rx_ready(rx_enable_sync[1]),.arm_toggle(arm_toggle),.cancel(cancel),
        .m_valid(fifo_valid),.m_data(fifo_data),.m_ready(fifo_ready),
        .source_fault(source_fault),.overflow(source_overflow));
    wire capture_stream_valid,capture_stream_ready;
    wire [47:0] capture_stream_data;
    video_stream_register #(.DATA_WIDTH(48)) capture_register(.clk(ddr_clk),.reset_n(video_reset_n),
        .s_valid(fifo_valid),.s_ready(fifo_ready),.s_data(fifo_data),.m_valid(capture_stream_valid),
        .m_ready(capture_stream_ready),.m_data(capture_stream_data));

    wire pll_lock,phy_pll_lock,gpll_lock,rst_gpll_lock,ddrphy_cpd_lock;
    wire ip_init_done,ip_init_fail,align_error;
    wire native_ready=ip_init_done&&pll_lock&&phy_pll_lock&&gpll_lock&&rst_gpll_lock&&ddrphy_cpd_lock&&!ip_init_fail&&!align_error;
    wire [27:0] h_awaddr,h_araddr;
    wire [3:0] h_awlen,h_arlen,h_awid,h_arid;
    wire h_awvalid,h_arvalid,h_awready,h_arready,h_wready,h_rvalid,h_wlast,h_rlast;
    wire [255:0] h_wdata,h_rdata;
    wire [31:0] h_wstrb;
    wire [3:0] h_wid,h_rid;
    ddr3_test #(.MEM_ROW_WIDTH(15),.MEM_COLUMN_WIDTH(10),.MEM_BANK_WIDTH(3),
        .MEM_DQ_WIDTH(32),.MEM_DM_WIDTH(4),.CTRL_ADDR_WIDTH(28)) I_ips_ddr_top(
        .ref_clk(ref_clk),.resetn(controller_reset_n),.core_clk(ddr_clk),
        .pll_lock(pll_lock),.phy_pll_lock(phy_pll_lock),.gpll_lock(gpll_lock),
        .rst_gpll_lock(rst_gpll_lock),.ddrphy_cpd_lock(ddrphy_cpd_lock),.ddr_init_done(ip_init_done),
        .axi_awaddr(h_awaddr),.axi_awuser_ap(1'b0),.axi_awuser_id(h_awid),.axi_awlen(h_awlen),
        .axi_awready(h_awready),.axi_awvalid(h_awvalid),.axi_wdata(h_wdata),.axi_wstrb(h_wstrb),
        .axi_wready(h_wready),.axi_wusero_id(h_wid),.axi_wusero_last(h_wlast),
        .axi_araddr(h_araddr),.axi_aruser_ap(1'b0),.axi_aruser_id(h_arid),.axi_arlen(h_arlen),
        .axi_arready(h_arready),.axi_arvalid(h_arvalid),.axi_rdata(h_rdata),.axi_rid(h_rid),
        .axi_rlast(h_rlast),.axi_rvalid(h_rvalid),
        .apb_clk(1'b0),.apb_rst_n(1'b1),.apb_sel(1'b0),.apb_enable(1'b0),.apb_addr(8'd0),.apb_write(1'b0),
        .apb_ready(),.apb_wdata(16'd0),.apb_rdata(),.mem_cs_n(mem_cs_n),.mem_rst_n(mem_rst_n),
        .mem_ck(mem_ck),.mem_ck_n(mem_ck_n),.mem_cke(mem_cke),.mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),
        .mem_we_n(mem_we_n),.mem_odt(mem_odt),.mem_a(mem_a),.mem_ba(mem_ba),.mem_dqs(mem_dqs),
        .mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm),.dbg_gate_start(1'b0),.dbg_cpd_start(1'b0),
        .dbg_ddrphy_rst_n(1'b1),.dbg_gpll_scan_rst(1'b0),.samp_position_dyn_adj(1'b0),
        .init_samp_position_even(32'd0),.init_samp_position_odd(32'd0),.wrcal_position_dyn_adj(1'b0),
        .init_wrcal_position(32'd0),.force_read_clk_ctrl(1'b0),.init_slip_step(16'd0),
        .init_read_clk_ctrl(12'd0),.debug_cpd_offset_adj(1'b0),.debug_cpd_offset_dir(1'b0),
        .debug_cpd_offset(10'd0),.ck_dly_en(1'b0),.init_ck_dly_step(8'd0),.dbg_ddrphy_init_fail(ip_init_fail),
        .align_error(align_error));

    wire face_fault,recovery_request,npu_idle,compute_idle,ddr_idle;
    wire [7:0] npu_stage,npu_op;
    wire [31:0] epoch=32'd1,addr_version=32'd1;
    wire [31:0] raw_commits,raw_scans,underflows,raw_frame;
    wire boot_rx_valid,boot_rx_ready,boot_rx_error,boot_tx_valid,boot_tx_ready,model_sealed;
    wire [7:0] boot_rx_data,boot_tx_data;
    localparam integer BOOT_UART_DIVISOR=(125_000_000+UART_BAUD/2)/UART_BAUD;
    triha_uart_rx #(.DIVISOR(BOOT_UART_DIVISOR)) boot_uart_rx(
        .clk_i(ddr_clk),.rst_ni(video_reset_n),.rx_i(uart_rx),.ready_i(boot_rx_ready),
        .valid_o(boot_rx_valid),.data_o(boot_rx_data),.error_o(boot_rx_error));
    triha_uart_tx #(.DIVISOR(BOOT_UART_DIVISOR)) boot_uart_tx(
        .clk_i(ddr_clk),.rst_ni(video_reset_n),.valid_i(boot_tx_valid),.data_i(boot_tx_data),
        .ready_o(boot_tx_ready),.tx_o(uart_tx));
    // This admitted NPU emits rectangles, without a five-point landmark head.
    triha_face_system #(.CACHE_ENABLE(CACHE_ENABLE),.ENABLE_AVATAR(ENABLE_AVATAR),.BOOT_AVATAR(ENABLE_AVATAR),.ENABLE_MODE_KEY(ENABLE_AVATAR),.ENABLE_CAPTURE_PREVIEW(0),.ENABLE_LANDMARKS(0),.ENABLE_MODEL_LOADER(1),.ENABLE_ROW_CACHE(0),.COMPACT_AVATAR(ENABLE_AVATAR),.ENABLE_MINIMAL_BOX(ENABLE_MINIMAL_BOX),.MINIMAL_CONTROL_CPU(MINIMAL_CONTROL_CPU),.ENABLE_HARDWARE_POST(ENABLE_HARDWARE_POST),.TRUSTED_MODEL(TRUSTED_MODEL),.M_LANES(M_LANES),.QUANTIZER_LANES(QUANTIZER_LANES)) face(
        .compute_clk_i(compute_clk),.video_clk_i(ddr_clk),.pixel_clk(pix_clk),.rst_ni(application_reset_n),
        .mode_button_n(mode_button_n),
        .pixel_reset_n(display_reset_n),.init_done_i(native_ready),.model_sealed_i(1'b0),
        .boot_rx_valid_i(boot_rx_valid),.boot_rx_data_i(boot_rx_data),.boot_rx_error_i(boot_rx_error),
        .boot_rx_ready_o(boot_rx_ready),.boot_tx_ready_i(boot_tx_ready),.boot_tx_valid_o(boot_tx_valid),
        .boot_tx_data_o(boot_tx_data),.model_sealed_o(model_sealed),
        .epoch_i(epoch),.addr_version_i(addr_version),.fault_o(face_fault),.recovery_request_o(recovery_request),
        .npu_idle_o(npu_idle),.compute_idle_o(compute_idle),.ddr_idle_o(ddr_idle),.npu_stage_o(npu_stage),.npu_op_o(npu_op),
        .h_awaddr(h_awaddr),.h_araddr(h_araddr),.h_awlen(h_awlen),.h_arlen(h_arlen),.h_awid(h_awid),.h_arid(h_arid),
        .h_awvalid(h_awvalid),.h_arvalid(h_arvalid),.h_awready(h_awready),.h_arready(h_arready),.h_wready(h_wready),
        .h_rvalid(h_rvalid),.h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_rdata(h_rdata),.h_wid(h_wid),.h_rid(h_rid),
        .h_wlast(h_wlast),.h_rlast(h_rlast),.source_fault(source_fault),.overflow(source_overflow),
        .src_valid(capture_stream_valid),.src_data(capture_stream_data),.src_ready(capture_stream_ready),
        .arm_toggle(arm_toggle),.cancel(cancel),.capture_busy(),.capture_port_drained(),
        .pixel_x(display_x),.pixel_y(display_y),.pixel_de(de),.pixel_hs(hs),.pixel_vs(vs),.pixel_frame_start(frame_start),
        .out_rgb({r_out,g_out,b_out}),.out_de(de_out),.out_hs(hs_out),.out_vs(vs_out),.raw_commits(raw_commits),
        .raw_scans(raw_scans),.underflows(underflows),.raw_frame(raw_frame),.result_ready(1'b1),.asset_retire_ready(1'b1),
        .load_valid(1'b0),.load_base(32'd0),.load_bytes(32'd0),.load_asset_id(32'd0),.load_generation(32'd0),.expected_crc(32'd0));

    reg [31:0] heartbeat;
    always @(posedge free_clk or negedge free_reset_n)
        if(!free_reset_n) heartbeat<=0; else heartbeat<=heartbeat+1'b1;
    assign heart_beat_led=heartbeat[23];
    assign ddr_init_done=native_ready;
    assign init_over_rx=native_ready&&model_sealed&&mode_good_cfg&&!face_fault;
    assign hdmi_int_led=face_fault||tx_error||rx_error;
    // Keep TX reserved for boot ACKs, including retries of the final packet.
    // Ready/fault LEDs remain live; video-only periodic telemetry is omitted.
endmodule
`default_nettype wire



// Resource-bounded first board demonstration. It keeps the real HDMI TX
// clock/reset and timing path and renders the BOX ABI shape at the output.
// The full CPU+B03 implementation is the shipped default.  DEMO_BOX_ONLY=1
// remains available as a TX-only bring-up mode when the board is being probed.
module triha_face_board_top #(
    parameter integer CLOCK_HZ=27_000_000,
    parameter integer STARTUP_CYCLES=CLOCK_HZ/1000,
    parameter integer INIT_TIMEOUT_CYCLES=CLOCK_HZ*5,
    parameter integer UART_BAUD=115200,
    parameter integer UART_INTERVAL_CYCLES=CLOCK_HZ,
    parameter integer FRAME_WIDTH=800,
    parameter integer FRAME_HEIGHT=600,
    parameter integer PAD_TOP=40,
    parameter integer PAD_BOTTOM=40,
    parameter integer RX_WARMUP_FRAMES=128,
    parameter integer CACHE_ENABLE=0,
    parameter integer ENABLE_MINIMAL_BOX=0,
    parameter integer ENABLE_AVATAR=1,
    parameter integer DEMO_BOX_ONLY=0,
    parameter integer MINIMAL_CONTROL_CPU=1,
    parameter integer ENABLE_HARDWARE_POST=0,
    parameter integer TRUSTED_MODEL=1,
    parameter integer M_LANES=2,
    parameter integer QUANTIZER_LANES=1
)(
    input wire sys_clk,rst_in,ref_clk_p,ref_clk_n,uart_rx,mode_button_n,
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
    generate
        if (DEMO_BOX_ONLY) begin : g_box_demo
            wire cfg_clk,locked,pixel_reset_n,cfg_reset_n;
            video_preview_clock_reset #(.STARTUP_CYCLES(STARTUP_CYCLES)) clocks(
                .sys_clk(sys_clk),.reset_n(rst_in),.pixel_clk(pix_clk),.cfg_clk(cfg_clk),
                .locked(locked),.pixel_reset_n(pixel_reset_n),.cfg_reset_n(cfg_reset_n),.tx_reset_n(rstn_out));
            wire tx_scl,tx_done,tx_error;
            hdmi_tx_init tx(.clk_cfg(cfg_clk),.reset_n(rstn_out),.iic_scl(tx_scl),.iic_sda(hd_sda),
                .init_done(tx_done),.init_error(tx_error));
            assign hd_scl=tx_scl;
            wire [10:0] x,y;
            wire hs,vs,de,frame_start;
            video_timing timing(.pixel_clk(pix_clk),.reset_n(pixel_reset_n),.x(x),.y(y),
                .hsync(hs),.vsync(vs),.de(de),.frame_start(frame_start));
            // BOX record equivalent: one visible face rectangle in the active
            // 800x600 raster. Border uses the renderer's red BOX convention.
            wire in_box=(x>=11'd220 && x<11'd580 && y>=11'd140 && y<11'd500);
            wire on_edge=in_box && (x<11'd224 || x>=11'd576 || y<11'd144 || y>=11'd496);
            assign hs_out=hs; assign vs_out=vs; assign de_out=de;
            assign r_out=de ? (on_edge ? 8'hff : (x[8] ? 8'h20 : 8'h10)) : 8'd0;
            assign g_out=de ? (on_edge ? 8'h20 : (y[8] ? 8'h30 : 8'h18)) : 8'd0;
            assign b_out=de ? (on_edge ? 8'h20 : 8'h40) : 8'd0;
            assign heart_beat_led=locked;
            assign ddr_init_done=1'b0; assign init_over_rx=tx_done;
            assign hdmi_int_led=tx_error; assign uart_tx=1'b1;
            assign mem_cs_n=1'b1; assign mem_rst_n=1'b1; assign mem_ck=1'b0; assign mem_ck_n=1'b0;
            assign mem_cke=1'b0; assign mem_ras_n=1'b1; assign mem_cas_n=1'b1; assign mem_we_n=1'b1;
            assign mem_odt=1'b0; assign mem_a=15'd0; assign mem_ba=3'd0; assign mem_dm=4'd0;
            assign hd_sda=1'bz; assign mem_dqs=4'bz; assign mem_dqs_n=4'bz; assign mem_dq=32'bz;
        end else begin : g_full
            triha_face_full_top #(.CLOCK_HZ(CLOCK_HZ),.STARTUP_CYCLES(STARTUP_CYCLES),
                .INIT_TIMEOUT_CYCLES(INIT_TIMEOUT_CYCLES),.UART_BAUD(UART_BAUD),
                .UART_INTERVAL_CYCLES(UART_INTERVAL_CYCLES),.FRAME_WIDTH(FRAME_WIDTH),
                .FRAME_HEIGHT(FRAME_HEIGHT),.PAD_TOP(PAD_TOP),.PAD_BOTTOM(PAD_BOTTOM),
                .RX_WARMUP_FRAMES(RX_WARMUP_FRAMES),.CACHE_ENABLE(CACHE_ENABLE),
                .ENABLE_MINIMAL_BOX(ENABLE_MINIMAL_BOX),.ENABLE_AVATAR(ENABLE_AVATAR),.MINIMAL_CONTROL_CPU(MINIMAL_CONTROL_CPU),.ENABLE_HARDWARE_POST(ENABLE_HARDWARE_POST),.TRUSTED_MODEL(TRUSTED_MODEL),.M_LANES(M_LANES),.QUANTIZER_LANES(QUANTIZER_LANES)) impl(
                .sys_clk(sys_clk),.rst_in(rst_in),.ref_clk_p(ref_clk_p),.ref_clk_n(ref_clk_n),.uart_rx(uart_rx),
                .mode_button_n(mode_button_n),
                .pixclk_in(pixclk_in),.hs_in(hs_in),.vs_in(vs_in),.de_in(de_in),
                .r_in(r_in),.g_in(g_in),.b_in(b_in),.rstn_out(rstn_out),.hd_scl(hd_scl),
                .pix_clk(pix_clk),.hd_sda(hd_sda),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),
                .r_out(r_out),.g_out(g_out),.b_out(b_out),.heart_beat_led(heart_beat_led),
                .ddr_init_done(ddr_init_done),.init_over_rx(init_over_rx),.hdmi_int_led(hdmi_int_led),
                .uart_tx(uart_tx),.mem_cs_n(mem_cs_n),.mem_rst_n(mem_rst_n),.mem_ck(mem_ck),
                .mem_ck_n(mem_ck_n),.mem_cke(mem_cke),.mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),
                .mem_we_n(mem_we_n),.mem_odt(mem_odt),.mem_a(mem_a),.mem_ba(mem_ba),
                .mem_dqs(mem_dqs),.mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm));
        end
    endgenerate
endmodule
