`timescale 1ns/1ps
/* CPU and native bridge execute normally. Only the digital UART divisor is
 * accelerated; timing scores come from cycle CSRs, not simulator wall time. */
module tb_cpu_ddr_coremark;
    parameter integer CACHE_ENABLE = 1;
    parameter [31:0] PAYLOAD_BASE = 32'h80000000;
    reg ref_clk = 0, free_clk = 0, rst_n = 0;
    always #4 ref_clk = !ref_clk;
    always #18.5185 free_clk = !free_clk;
    wire tx;
    wire [3:0] led;
    wire mem_cs_n, mem_rst_n, mem_ck, mem_ck_n, mem_cke, mem_ras_n, mem_cas_n, mem_we_n, mem_odt;
    wire [14:0] mem_a;
    wire [2:0] mem_ba;
    wire [3:0] mem_dqs, mem_dqs_n, mem_dm;
    wire [31:0] mem_dq;
    integer cycles = 0, ddr_fetches = 0, ddr_data = 0;
    triha_cpu_ddr_board_top #(.CACHE_ENABLE(CACHE_ENABLE), .STARTUP_CYCLES(24),
        .INIT_TIMEOUT_CYCLES(512), .CLOCK_TIMEOUT_CYCLES(128), .HEARTBEAT_CYCLES(64)) u_dut (
        .sys_clk_i(free_clk), .ref_clk_pi(ref_clk), .ref_clk_ni(!ref_clk), .rst_ni(rst_n),
        .uart_tx_o(tx), .led_o(led),
        .mem_cs_n(mem_cs_n), .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n),
        .mem_cke(mem_cke), .mem_ras_n(mem_ras_n), .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n), .mem_odt(mem_odt),
        .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs), .mem_dqs_n(mem_dqs_n), .mem_dq(mem_dq), .mem_dm(mem_dm)
    );
    defparam u_dut.u_system.u_soc.u_router.u_memory.UART_DIVISOR = 4;
    `define MEMORY u_dut.u_system.u_soc.u_router.u_memory
    `define SOC u_dut.u_system.u_soc
    always @(posedge u_dut.cpu_clk) begin
        cycles = cycles + 1;
        if (cycles > 40000000) $fatal(1, "CPU_DDR_COREMARK_SIM_FAIL watchdog");
        if (`MEMORY.uart_write) $write("%c", `MEMORY.data_wdata_i[7:0]);
        if (`SOC.inst_req && `SOC.inst_accept && `SOC.inst_addr >= PAYLOAD_BASE && `SOC.inst_addr < PAYLOAD_BASE+32'h20000)
            ddr_fetches = ddr_fetches + 1;
        if (`SOC.data_accept && (`SOC.data_re || |`SOC.data_wstrb) &&
            `SOC.data_addr >= PAYLOAD_BASE && `SOC.data_addr < PAYLOAD_BASE+32'h20000)
            ddr_data = ddr_data + 1;
    end
    initial begin
        #1;
        if (u_dut.u_system.CACHE_ENABLE != CACHE_ENABLE ||
            u_dut.u_system.u_soc.u_core.u_cpu.SUPPORT_DUAL_ISSUE != 0)
            $fatal(1, "CPU_DDR_COREMARK_SIM_FAIL actual configuration");
        #316; rst_n = 1;
        wait (u_dut.done_w);
        repeat (64) @(posedge u_dut.cpu_clk);
        if (u_dut.exit_code_w !== 0 || ddr_fetches < 1000 || ddr_data < 1000)
            $fatal(1, "CPU_DDR_COREMARK_SIM_FAIL software or DDR execution");
        $display("CPU_DDR_COREMARK_SIM_PASS cache=%0d fetches=%0d data=%0d total_cycles=%0d",
            CACHE_ENABLE, ddr_fetches, ddr_data, cycles);
        $finish;
    end
endmodule
