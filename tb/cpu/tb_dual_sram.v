`timescale 1ns/1ps
`include "biriscv_defs.v"

module tb_dual_sram #(
    parameter integer MAX_CYCLES = 10000000
);
    reg clk = 0;
    reg rst_n = 0;
    wire tx, done;
    wire [7:0] code;
    integer cycles = 0;
    integer bit_index;
    reg [7:0] serial_byte;
    reg [63:0] wb_total = 0, wb_start = 0, wb_window = 0;
    reg [31:0] cycle_start = 0, cycle_window = 0;
    integer cycle_reads = 0;
    integer pairs = 0;
    integer boot_seen = 0;
    integer sram_seen = 0;
    always #5 clk = ~clk;
    triha_minimal_soc u_dut (
        .clk_i(clk), .rst_ni(rst_n), .external_irq_i(1'b0),
        .uart_tx_o(tx), .done_o(done), .exit_code_o(code)
    );

    initial begin
        repeat (5) @(negedge clk); rst_n = 1;
        if ($test$plusargs("FAULT_READ")) force u_dut.data_rdata = 32'b0;
    end

    initial forever begin
        @(negedge tx);
        repeat (1302) @(posedge clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            serial_byte[bit_index] = tx;
            repeat (868) @(posedge clk);
        end
        if (tx !== 1'b1) begin $display("SOC_FIRMWARE_FAIL UART framing"); $finish; end
        $write("%c", serial_byte);
    end

    function retirement_allowed;
        input [5:0] exception;
        begin
            case (exception)
                6'd0, `EXCEPTION_FENCE, `EXCEPTION_ERET_U,
                `EXCEPTION_ERET_S, `EXCEPTION_ERET_M: retirement_allowed = 1;
                default: retirement_allowed = 0;
            endcase
        end
    endfunction

    always @(posedge clk) if (rst_n) begin
        cycles = cycles + 1;
        if (u_dut.inst_req && u_dut.inst_accept) begin
            if (u_dut.inst_addr == 0) boot_seen = 1;
            if (u_dut.inst_addr == 32'h10000) sram_seen = 1;
        end
        if (u_dut.u_core.u_cpu.u_csr.u_csrfile.csr_ren_i &&
            u_dut.u_core.u_cpu.u_csr.u_csrfile.csr_raddr_i == 12'hc00) begin
            if (cycle_reads == 0) begin
                cycle_start = u_dut.u_core.u_cpu.u_csr.u_csrfile.csr_mcycle_q;
                wb_start = wb_total;
            end else if (cycle_reads == 1) begin
                cycle_window = u_dut.u_core.u_cpu.u_csr.u_csrfile.csr_mcycle_q - cycle_start;
                wb_window = wb_total - wb_start;
            end
            cycle_reads = cycle_reads + 1;
        end
        if (u_dut.u_core.u_cpu.u_issue.pipe0_valid_wb_w &&
            retirement_allowed(u_dut.u_core.u_cpu.u_issue.pipe0_exception_wb_w))
            wb_total = wb_total + 1;
        if (u_dut.u_core.u_cpu.u_issue.pipe1_valid_wb_w &&
            retirement_allowed(u_dut.u_core.u_cpu.u_issue.pipe1_exception_wb_w))
            wb_total = wb_total + 1;
        if (u_dut.u_core.u_cpu.u_issue.dual_issue_w) pairs=pairs+1;
        if (cycles > MAX_CYCLES) begin
            $display("SOC_FIRMWARE_FAIL timeout"); $finish;
        end
    end

    initial begin
        wait(done);
        // Drain the physical UART stop bit before reporting software status.
        repeat (9000) @(posedge clk);
        $display("\nSOC_PROGRAM_EXIT code=%0d", code);
        $display("SOC_DUAL_CONFIG actual=%0d pairs=%0d",u_dut.u_core.DUAL_ISSUE,pairs);
        $display("SOC_MEASURE cycles=%0d wb_completed=%0d reads=%0d", cycle_window, wb_window, cycle_reads);
        if (code !== 0 || !boot_seen || !sram_seen || pairs==0 || u_dut.u_core.DUAL_ISSUE!=1) $display("SOC_FIRMWARE_FAIL exit/ROM/SRAM");
        else $display("SOC_FIRMWARE_PASS cycles=%0d", cycles);
        $finish;
    end
endmodule
