`timescale 1ns/1ps
module tb_cpu_ddr_board;
    parameter integer TEST_MODE = 0;
    parameter integer CORRUPT_DATA = 0;
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
    integer cycles = 0, pass_lines = 0, fail_lines = 0, bit_index;
    reg [7:0] serial_byte;
    reg [1023:0] line = 0;
    triha_cpu_ddr_board_top #(.STARTUP_CYCLES(24), .INIT_TIMEOUT_CYCLES(512),
        .CLOCK_TIMEOUT_CYCLES(128), .HEARTBEAT_CYCLES(64)) u_dut (
        .sys_clk_i(free_clk), .ref_clk_pi(ref_clk), .ref_clk_ni(!ref_clk), .rst_ni(rst_n),
        .uart_tx_o(tx), .led_o(led),
        .mem_cs_n(mem_cs_n), .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n),
        .mem_cke(mem_cke), .mem_ras_n(mem_ras_n), .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n), .mem_odt(mem_odt),
        .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs), .mem_dqs_n(mem_dqs_n), .mem_dq(mem_dq), .mem_dm(mem_dm)
    );
    always @(posedge u_dut.cpu_clk) begin
        cycles = cycles+1;
        if (cycles > 3000000) $fatal(1,"CPU_DDR_BOARD_FAIL watchdog");
    end
    // Raw KEY0 release must not start free-domain board state before its
    // two-stage local release pipe has completed.
    always @(posedge free_clk) begin
        #1;
        if (rst_n && !u_dut.u_supervisor.free_reset_n && u_dut.heartbeat_count_q !== 0)
            $fatal(1,"CPU_DDR_BOARD_FAIL unsynchronized free reset release");
    end
    integer ddr_release_edges = 0;
    always @(negedge u_dut.epoch_n) ddr_release_edges = 0;
    always @(posedge u_dut.ddr_clk) begin
        if (!u_dut.epoch_n) ddr_release_edges = 0;
        else begin
            ddr_release_edges = ddr_release_edges+1;
            #1;
            if (ddr_release_edges <= 2 && u_dut.u_supervisor.ddr_count_q !== 0)
                $fatal(1,"CPU_DDR_BOARD_FAIL unsynchronized DDR heartbeat reset release");
        end
    end
    initial forever begin
        @(negedge tx);
        repeat (1302) @(posedge u_dut.cpu_clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index+1) begin
            serial_byte[bit_index] = tx;
            repeat (868) @(posedge u_dut.cpu_clk);
        end
        if (tx !== 1'b1) $fatal(1,"CPU_DDR_BOARD_FAIL UART framing");
        $write("%c",serial_byte);
        if (serial_byte == 10) begin
            if (line == "CPU_DDR_PASS private=8192 shared=8192 fence_i=1") pass_lines = pass_lines+1;
            if (line == "CPU_DDR_FAIL init") fail_lines = fail_lines+1;
            line = 0;
        end else line = {line[1015:0],serial_byte};
    end
    initial begin
        if (TEST_MODE == 1) u_dut.I_ips_ddr_top.model_init_enable = 0;
        if (CORRUPT_DATA) u_dut.I_ips_ddr_top.model_fault_mode = 1;
        #317; rst_n = 1;
        if (TEST_MODE > 1) begin
            wait(u_dut.u_supervisor.online_seen_q === 1'b1);
            @(negedge free_clk);
            case (TEST_MODE)
                2: u_dut.I_ips_ddr_top.model_drop_init = 1;
                3: u_dut.I_ips_ddr_top.model_core_enable = 0;
                4: force u_dut.cpu_pll_locked = 0;
            endcase
            if (TEST_MODE == 4) begin
                repeat (8) @(negedge free_clk);
                if (mem_rst_n !== 0 || u_dut.u_system.cpu_rst_n !== 0)
                    $fatal(1,"CPU_DDR_BOARD_FAIL PLL loss did not reset all participants");
                release u_dut.cpu_pll_locked;
            end
        end
        wait(u_dut.done_w);
        repeat (9000) @(posedge u_dut.cpu_clk);
        if (TEST_MODE == 0) begin
            if (u_dut.exit_code_w !== 0 || pass_lines != 1 || led[3:1] !== 3'b011)
                $fatal(1,"CPU_DDR_BOARD_FAIL first software run");
            #1; rst_n = 0;
            repeat (12) @(negedge free_clk); rst_n = 1;
            wait(u_dut.done_w);
            repeat (9000) @(posedge u_dut.cpu_clk);
            if (u_dut.exit_code_w !== 0 || pass_lines != 2 || led[3:1] !== 3'b011)
                $fatal(1,"CPU_DDR_BOARD_FAIL KEY0 software rerun");
            $display("CPU_DDR_BOARD_PASS boots=2 tested_private=8192 tested_shared=8192 cycles=%0d",cycles);
        end else begin
            if (u_dut.exit_code_w == 0 || led[3] !== 1 || fail_lines < 1)
                $fatal(1,"CPU_DDR_BOARD_FAIL fault did not reach local software");
            if ((TEST_MODE == 1 && u_dut.board_error_code !== 8'he0) ||
                (TEST_MODE == 2 && u_dut.board_error_code !== 8'he1) ||
                (TEST_MODE == 3 && u_dut.board_error_code !== 8'he4) ||
                (TEST_MODE == 4 && u_dut.board_error_code !== 8'he5))
                $fatal(1,"CPU_DDR_BOARD_FAIL first fault code");
            if (TEST_MODE != 4 && mem_rst_n !== 1)
                $fatal(1,"CPU_DDR_BOARD_FAIL DDR fault reset a live controller");
            $display("CPU_DDR_BOARD_MONITOR_PASS mode=%0d code=%02h local_software_reported=1",TEST_MODE,u_dut.board_error_code);
        end
        $finish;
    end
endmodule
