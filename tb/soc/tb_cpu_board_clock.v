`timescale 1ns/1ps
module tb_cpu_board_clock;
    reg ref_clk = 0;
    reg rst_n = 0;
    wire clk, locked, cpu_reset_n;
    integer checks = 0;
    integer n;
    realtime previous_edge;
    always #4 ref_clk = ~ref_clk;
    triha_cpu_clock_reset u_dut (
        .ref_clk_pi(ref_clk), .ref_clk_ni(~ref_clk), .rst_ni(rst_n),
        .cpu_clk_o(clk), .pll_locked_o(locked), .cpu_rst_no(cpu_reset_n)
    );
    task check;
        input condition;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                $display("CPU_BOARD_CLOCK_FAIL check=%0d time=%0t", checks, $time);
                $finish;
            end
        end
    endtask
    task release_key;
        begin
            @(negedge clk); #1; rst_n = 1;
            for (n = 0; n < 3; n = n + 1) begin
                @(posedge clk); #0.01;
                check(cpu_reset_n === (n == 2));
            end
        end
    endtask
    initial begin
        wait(locked === 1'b1);
        repeat(8) @(posedge clk);
        check(cpu_reset_n === 0);
        @(posedge clk); previous_edge = $realtime;
        repeat (100) begin
            @(posedge clk);
            check(($realtime - previous_edge > 9.999) && ($realtime - previous_edge < 10.001));
            previous_edge = $realtime;
        end
        release_key;
        #1; rst_n = 0; #0.01; check(cpu_reset_n === 0);
        repeat(6) @(posedge clk);
        check(cpu_reset_n === 0);
        release_key;
        #1; force u_dut.pll_locked_o = 0; #0.01;
        check(cpu_reset_n === 0);
        repeat(5) @(posedge clk);
        release u_dut.pll_locked_o;
        wait(locked === 1'b1);
        repeat(3) @(posedge clk); #0.01;
        check(cpu_reset_n === 1);
        $display("CPU_BOARD_CLOCK_PASS checks=%0d actual_period_ns=10", checks);
        $finish;
    end
    initial begin #1000000; $display("CPU_BOARD_CLOCK_FAIL timeout"); $finish; end
endmodule
