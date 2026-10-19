`timescale 1ns/1ps
module tb_cpu_board;
    reg ref_clk = 0;
    reg rst_n = 0;
    wire tx;
    wire [3:0] led;
    integer cycles = 0, pass_lines = 0, alive_zero_lines = 0;
    integer bit_index;
    reg [7:0] serial_byte;
    reg [1279:0] line = 0;
    always #4 ref_clk = ~ref_clk;
    triha_cpu_board_top u_dut (
        .ref_clk_pi(ref_clk), .ref_clk_ni(~ref_clk), .rst_ni(rst_n),
        .uart_tx_o(tx), .led_o(led)
    );
    initial begin
        #317; rst_n = 1;
        wait(pass_lines == 1 && alive_zero_lines == 1);
        #1;
        if (led[3:1] !== 3'b011) begin $display("CPU_BOARD_SYSTEM_FAIL status LEDs"); $finish; end
        #13; rst_n = 0;
        #1;
        if (u_dut.cpu_reset_n !== 0) begin $display("CPU_BOARD_SYSTEM_FAIL asynchronous reset"); $finish; end
        #103; rst_n = 1;
        wait(pass_lines == 2 && alive_zero_lines == 2);
        #1;
        if (led[3:1] !== 3'b011) begin $display("CPU_BOARD_SYSTEM_FAIL reset status"); $finish; end
        $display("CPU_BOARD_SYSTEM_PASS boots=2 checked_bytes_per_boot=8192 serial_8n1=1");
        $finish;
    end
    always @(posedge u_dut.cpu_clk) begin
        cycles = cycles + 1;
        if (cycles > 10000000) begin $display("CPU_BOARD_SYSTEM_FAIL timeout"); $finish; end
        if (u_dut.cpu_reset_n && u_dut.u_soc.u_core.u_cpu.u_issue.pipe1_valid_wb_w) begin
            $display("CPU_BOARD_SYSTEM_FAIL dual lane active"); $finish;
        end
    end
    initial forever begin
        @(negedge tx);
        repeat(1302) @(posedge u_dut.cpu_clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            serial_byte[bit_index] = tx;
            repeat(868) @(posedge u_dut.cpu_clk);
        end
        if (tx !== 1'b1) begin $display("CPU_BOARD_SYSTEM_FAIL UART stop"); $finish; end
        $write("%c", serial_byte);
        if (serial_byte == 10) begin
            if (line == "CPU_BOARD_PASS checked_bytes=8192") pass_lines = pass_lines + 1;
            else if ((line >> 64) == "CPU_ALIVE seq=00000000 cycle=") alive_zero_lines = alive_zero_lines + 1;
            else begin $display("CPU_BOARD_SYSTEM_FAIL unexpected serial line=%0s", line); $finish; end
            line = 0;
        end else line = {line[1271:0], serial_byte};
    end
endmodule
