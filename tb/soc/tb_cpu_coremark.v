`timescale 1ns/1ps
/* Physical UART decoding of the short board preflight; no accelerated UART. */
module tb_cpu_coremark;
    reg ref_clk = 0;
    reg rst_n = 0;
    wire tx;
    wire [3:0] led;
    integer cycles = 0, bit_index, reads = 0;
    reg [7:0] serial_byte;
    reg [31:0] started = 0, elapsed = 0;
    always #4 ref_clk = ~ref_clk;
    triha_cpu_board_top u_dut (
        .ref_clk_pi(ref_clk), .ref_clk_ni(~ref_clk), .rst_ni(rst_n),
        .uart_tx_o(tx), .led_o(led)
    );
    initial begin
        #1;
        if (u_dut.u_soc.u_core.u_cpu.NUM_BTB_ENTRIES != 512 ||
            u_dut.u_soc.u_core.u_cpu.BTB_DIRECT_MAPPED != 1 ||
            u_dut.u_soc.u_core.u_cpu.NUM_BTB_ENTRIES_W != 9 ||
            u_dut.u_soc.u_core.u_cpu.NUM_BHT_ENTRIES != 512 ||
            u_dut.u_soc.u_core.u_cpu.NUM_BHT_ENTRIES_W != 9 ||
            u_dut.u_soc.u_core.u_cpu.NUM_RAS_ENTRIES != 4 ||
            u_dut.u_soc.u_core.u_cpu.NUM_RAS_ENTRIES_W != 2 ||
            u_dut.u_soc.u_core.u_cpu.GSHARE_ENABLE != 0) begin
            $display("CPU_COREMARK_SIM_FAIL actual predictor profile must be BTB512/BHT512/RAS4 PC-indexed");
            $finish;
        end
        $display("CPU_COREMARK_CONFIG btb=512 bht=512 ras=4 gshare=0 single_issue=1 indexed_btb=1");
        #316; rst_n = 1;
    end
    initial forever begin
        @(negedge tx);
        repeat (1302) @(posedge u_dut.cpu_clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            serial_byte[bit_index] = tx;
            repeat (868) @(posedge u_dut.cpu_clk);
        end
        if (tx !== 1'b1) begin $display("CPU_COREMARK_SIM_FAIL UART stop"); $finish; end
        $write("%c", serial_byte);
    end
    always @(posedge u_dut.cpu_clk) if (u_dut.cpu_reset_n) begin
        cycles = cycles + 1;
        // csr_ren_i is the issued-opcode valid, including ordinary instructions.
        // Decode the actual rdcycle instruction; jalr -1024 also has bits31:20=c00.
        if (u_dut.u_soc.u_core.u_cpu.u_csr.opcode_valid_i &&
            (u_dut.u_soc.u_core.u_cpu.u_csr.opcode_opcode_i & 32'hfffff07f) == 32'hc0002073) begin
            if (reads == 0) started = u_dut.u_soc.u_core.u_cpu.u_csr.u_csrfile.csr_mcycle_q;
            else if (reads == 1) elapsed = u_dut.u_soc.u_core.u_cpu.u_csr.u_csrfile.csr_mcycle_q - started;
            reads = reads + 1;
        end
        if (cycles > 20000000 || u_dut.u_soc.u_core.u_cpu.u_issue.pipe1_valid_wb_w) begin
            $display("CPU_COREMARK_SIM_FAIL timeout/dual lane"); $finish;
        end
    end
    initial begin
        wait(u_dut.done);
        repeat (9000) @(posedge u_dut.cpu_clk);
        if (u_dut.exit_code !== 0 || reads != 2)
            $display("CPU_COREMARK_SIM_FAIL exit=%0d reads=%0d cycles=%0d", u_dut.exit_code, reads, elapsed);
        else $display("\nCPU_COREMARK_SIM_PASS cycles=%0d reads=%0d", elapsed, reads);
        $finish;
    end
endmodule
