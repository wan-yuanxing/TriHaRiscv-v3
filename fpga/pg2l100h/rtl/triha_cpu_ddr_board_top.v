/* TriHa standalone cached CPU with actual board DDR/PLL/pin boundary.
 * Digital wrapper tests substitute only the IP models. Hardware builds use
 * the hash-locked HMIC IP and generated CPU PLL. No Video/NPU native owner.
 */
`include "cpu_ddr_board_cfg.vh"
`default_nettype none
module triha_cpu_ddr_board_top #(
    parameter ROM_FILE = "rom.hex",
    parameter SRAM_FILE = "sram.hex",
    parameter integer CACHE_ENABLE = 1,
    parameter integer STARTUP_CYCLES = `TRIHA_DDR_BOARD_STARTUP_CYCLES,
    parameter integer INIT_TIMEOUT_CYCLES = `TRIHA_DDR_BOARD_INIT_TIMEOUT_CYCLES,
    parameter integer CLOCK_TIMEOUT_CYCLES = `TRIHA_DDR_BOARD_CLOCK_TIMEOUT_CYCLES,
    parameter integer HEARTBEAT_CYCLES = `TRIHA_DDR_BOARD_HEARTBEAT_CYCLES
) (
    input wire sys_clk_i,
    input wire ref_clk_pi,
    input wire ref_clk_ni,
    input wire rst_ni,
    output wire uart_tx_o,
    output reg [3:0] led_o,
    output wire mem_cs_n, mem_rst_n, mem_ck, mem_ck_n, mem_cke,
    output wire mem_ras_n, mem_cas_n, mem_we_n, mem_odt,
    output wire [14:0] mem_a,
    output wire [2:0] mem_ba,
    inout wire [3:0] mem_dqs, mem_dqs_n,
    inout wire [31:0] mem_dq,
    output wire [3:0] mem_dm
);
    wire free_clk, reference_clk, cpu_clk, ddr_clk, cpu_pll_locked, epoch_n, free_rst_n, ddr_rst_n;
    GTP_CLKBUFG u_free_buffer (.CLKIN(sys_clk_i), .CLKOUT(free_clk));
    GTP_INBUFDS u_reference (.I(ref_clk_pi), .IB(ref_clk_ni), .O(reference_clk));
    // The PHY PLLs require reset before their own clocks exist. Release
    // their controller reset on the always-running reference clock;
    // do not wait for the generated DDR clock and create a startup loop.
    wire reference_reset_clk, controller_rst_n;
    GTP_CLKBUFG u_reset_reference_buffer (.CLKIN(reference_clk), .CLKOUT(reference_reset_clk));
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [1:0] reference_release_q;
    always @(posedge reference_reset_clk or negedge epoch_n) begin
        if (!epoch_n) reference_release_q <= 0;
        else reference_release_q <= {reference_release_q[0],1'b1};
    end
    assign controller_rst_n = reference_release_q[1];
    cpu_board_pll u_cpu_pll (.clkin1(reference_clk), .clkout0(cpu_clk), .lock(cpu_pll_locked));
    wire pll_lock, phy_pll_lock, gpll_lock, rst_gpll_lock, ddrphy_cpd_lock;
    wire ip_init_done, ip_init_fail, align_error;
    wire [7:0] ip_status = {align_error,ip_init_fail,ddrphy_cpd_lock,rst_gpll_lock,
        gpll_lock,phy_pll_lock,pll_lock,ip_init_done};
    wire board_error, supervised_ready;
    wire [7:0] board_error_code;
    triha_cpu_ddr_supervisor #(.STARTUP_CYCLES(STARTUP_CYCLES), .INIT_TIMEOUT_CYCLES(INIT_TIMEOUT_CYCLES),
        .CLOCK_TIMEOUT_CYCLES(CLOCK_TIMEOUT_CYCLES)) u_supervisor (
        .clk_i(free_clk), .rst_ni(rst_ni), .cpu_pll_locked_i(cpu_pll_locked),
        .ddr_clk_i(ddr_clk), .ddr_status_i(ip_status), .epoch_no(epoch_n),
        .free_reset_no(free_rst_n), .ddr_reset_no(ddr_rst_n),
        .ready_o(supervised_ready), .fault_o(board_error), .fault_code_o(board_error_code)
    );
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg board_fault_meta_q, board_fault_sync_q;
    always @(posedge ddr_clk or negedge ddr_rst_n) begin
        if (!ddr_rst_n) begin board_fault_meta_q <= 0; board_fault_sync_q <= 0; end
        else begin board_fault_meta_q <= board_error; board_fault_sync_q <= board_fault_meta_q; end
    end
    wire native_ready = (&ip_status[5:0]) && !(|ip_status[7:6]) && !board_fault_sync_q;
    wire [27:0] axi_awaddr, axi_araddr;
    wire [3:0] axi_awuser_id, axi_aruser_id, axi_awlen, axi_arlen, axi_wusero_id, axi_rid;
    wire axi_awvalid, axi_arvalid, axi_awready, axi_arready, axi_wready, axi_wusero_last, axi_rlast, axi_rvalid;
    wire [255:0] axi_wdata, axi_rdata;
    wire [31:0] axi_wstrb;
    wire done_w, cpu_fault_w, protocol_fault_w;
    wire [7:0] exit_code_w, bridge_code_w;
    triha_cpu_ddr #(.ROM_FILE(ROM_FILE), .SRAM_FILE(SRAM_FILE), .CACHE_ENABLE(CACHE_ENABLE)) u_system (
        .cpu_clk_i(cpu_clk), .ddr_clk_i(ddr_clk), .rst_ni(epoch_n), .external_irq_i(1'b0),
        .ddr_ready_i(native_ready), .ddr_fault_i(board_error || ip_init_fail || align_error),
        .cpu_ddr_fault_o(cpu_fault_w), .protocol_fault_o(protocol_fault_w), .bridge_fault_code_o(bridge_code_w),
        .uart_tx_o(uart_tx_o), .done_o(done_w), .exit_code_o(exit_code_w),
        .h_awaddr_o(axi_awaddr), .h_awlen_o(axi_awlen), .h_awid_o(axi_awuser_id), .h_awvalid_o(axi_awvalid), .h_awready_i(axi_awready),
        .h_wdata_o(axi_wdata), .h_wstrb_o(axi_wstrb), .h_wready_i(axi_wready), .h_wid_i(axi_wusero_id), .h_wlast_i(axi_wusero_last),
        .h_araddr_o(axi_araddr), .h_arlen_o(axi_arlen), .h_arid_o(axi_aruser_id), .h_arvalid_o(axi_arvalid), .h_arready_i(axi_arready),
        .h_rdata_i(axi_rdata), .h_rid_i(axi_rid), .h_rlast_i(axi_rlast), .h_rvalid_i(axi_rvalid)
    );
    ddr3_test #(.MEM_ROW_WIDTH(15),.MEM_COLUMN_WIDTH(10),.MEM_BANK_WIDTH(3),
        .MEM_DQ_WIDTH(32),.MEM_DM_WIDTH(4),.MEM_DQS_WIDTH(4),.CTRL_ADDR_WIDTH(28)) I_ips_ddr_top(
        .ref_clk(reference_clk),.resetn(controller_rst_n),.core_clk(ddr_clk),
        .pll_lock(pll_lock),.phy_pll_lock(phy_pll_lock),.gpll_lock(gpll_lock),
        .rst_gpll_lock(rst_gpll_lock),.ddrphy_cpd_lock(ddrphy_cpd_lock),.ddr_init_done(ip_init_done),
        .axi_awaddr(axi_awaddr),.axi_awuser_ap(1'b0),.axi_awuser_id(axi_awuser_id),
        .axi_awlen(axi_awlen),.axi_awready(axi_awready),.axi_awvalid(axi_awvalid),
        .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),
        .axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr),.axi_aruser_ap(1'b0),.axi_aruser_id(axi_aruser_id),
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
        .ck_dly_en(1'b0),.init_ck_dly_step(8'd0),.dbg_ddrphy_init_fail(ip_init_fail),.align_error(align_error),
        .debug_calib_ctrl(), .dbg_slice_status(), .dbg_slice_state(), .debug_data(),
        .dbg_dll_upd_state(), .debug_gpll_dps_phase(), .dbg_rst_dps_state(), .dbg_tran_err_rst_cnt(),
        .debug_dps_cnt_dir0(), .debug_dps_cnt_dir1(), .ck_dly_set_bin(), .debug_rst_state(), .debug_cpd_state());

    localparam integer HW = HEARTBEAT_CYCLES > 1 ? $clog2(HEARTBEAT_CYCLES) : 1;
    reg [HW-1:0] heartbeat_count_q;
    reg heartbeat_q;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [1:0] software_meta_q, software_sync_q;
    always @(posedge free_clk or negedge free_rst_n) begin
        if (!free_rst_n) begin
            heartbeat_count_q <= 0; heartbeat_q <= 0;
            software_meta_q <= 0; software_sync_q <= 0; led_o <= 0;
        end else begin
            if (heartbeat_count_q == HEARTBEAT_CYCLES-1) begin heartbeat_count_q <= 0; heartbeat_q <= !heartbeat_q; end
            else heartbeat_count_q <= heartbeat_count_q+1'b1;
            software_meta_q <= {done_w && (exit_code_w != 0), done_w && (exit_code_w == 0)};
            software_sync_q <= software_meta_q;
            led_o <= {board_error || software_sync_q[1], software_sync_q[0], supervised_ready, heartbeat_q};
        end
    end
endmodule
`default_nettype wire
