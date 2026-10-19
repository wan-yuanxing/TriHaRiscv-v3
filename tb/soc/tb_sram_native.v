`timescale 1ns/1ps
module tb_sram_native;
    reg clk = 0;
    always #5 clk = ~clk;
    reg ie = 0, de = 0;
    reg [11:0] ia = 0, da = 0;
    reg [63:0] dw = 0;
    reg [7:0] we = 0;
    wire [63:0] iq, dq;
    reg [63:0] expected [0:4095];
    reg [63:0] held_i, held_d;
    integer n, b;
    integer checks = 0;
    triha_sram u_dut (
        .clk_i(clk), .inst_en_i(ie), .inst_addr_i(ia), .inst_rdata_o(iq),
        .data_en_i(de), .data_addr_i(da), .data_wdata_i(dw), .data_wstrb_i(we), .data_rdata_o(dq)
    );
    task check;
        input condition;
        begin
            if (condition !== 1'b1) begin
                $display("SRAM_NATIVE_FAIL word=%0d time=%0t", n, $time); $finish;
            end
            checks = checks + 1;
        end
    endtask
    initial begin
        $readmemh("sram.hex", expected);
        if ($test$plusargs("FAULT_READ")) force u_dut.inst_rdata_o = 0;
        repeat (3) @(negedge clk);
        // Check every initialized byte and both synchronous output ports.
        for (n = 0; n < 4096; n = n + 1) begin
            @(negedge clk); ie = 1; ia = n; de = 1; da = n; we = 0;
            @(posedge clk); #1;
            check(iq === expected[n] && dq === expected[n]);
        end
        // Every address/lane, data-port read-before-write, concurrent I read
        // at a distinct word, then latest data visible through either copy.
        for (n = 0; n < 4096; n = n + 1) begin
            @(negedge clk); ia = (n + 1) % 4096; da = n;
            dw = 64'h3a591c37e8bc4d20 ^ (64'h91570025 * n);
            we = (n % 2) ? 8'hff : (8'b1 << (n % 8));
            @(posedge clk); #1;
            check(dq === expected[n] && iq === expected[(n + 1) % 4096]);
            for (b = 0; b < 8; b = b + 1)
                if (we[b]) expected[n][b*8 +: 8] = dw[b*8 +: 8];
            @(negedge clk); we = 0; ia = n;
            @(posedge clk); #1;
            check(iq === expected[n] && dq === expected[n]);
        end
        @(negedge clk); ie = 0; de = 0; held_i = iq; held_d = dq;
        repeat (8) begin
            @(negedge clk); ia = ia + 1; da = da + 1;
            @(posedge clk); #1; check(iq === held_i && dq === held_d);
        end
        $display("SRAM_NATIVE_PASS checks=%0d", checks); $finish;
    end
    initial begin #1000000; $display("SRAM_NATIVE_FAIL timeout"); $finish; end
endmodule
