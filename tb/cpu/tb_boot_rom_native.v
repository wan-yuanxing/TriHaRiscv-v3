`timescale 1ns/1ps
module tb_boot_rom_native;
    reg clk = 0;
    always #5 clk = ~clk;
    reg ie = 0, de = 0;
    reg [9:0] ia = 0, da = 0;
    wire [63:0] idata, ddata;
    reg [63:0] image [0:1023];
    reg [63:0] expected_i, expected_d;
    reg seen_i = 0, seen_d = 0;
    integer n, checks = 0;
    triha_boot_rom u_dut(.clk_i(clk), .inst_en_i(ie), .inst_addr_i(ia),
        .inst_rdata_o(idata), .data_en_i(de), .data_addr_i(da), .data_rdata_o(ddata));
    initial $readmemh("rom.hex", image);
    always @(posedge clk) begin
        if (ie) begin expected_i = image[ia]; seen_i = 1; end
        if (de) begin expected_d = image[da]; seen_d = 1; end
        #1;
        if ((seen_i && idata !== expected_i) || (seen_d && ddata !== expected_d))
            $fatal(1,"ROM_NATIVE_FAIL checks=%0d ia=%h da=%h", checks, ia, da);
        checks = checks + 1;
    end
    initial begin
        if ($test$plusargs("FAULT_READ")) force ddata = 64'b0;
        // Both ports independently cover every address, then exercise holds
        // while their addresses change. Compare every cycle, not just valid data.
        for (n = 0; n < 1024; n = n + 1) begin
            @(negedge clk); ie = 1; de = 1; ia = n; da = 1023-n;
        end
        for (n = 0; n < 4096; n = n + 1) begin
            @(negedge clk); ie = n[0]; de = n[1]; ia = n*17; da = n*29;
        end
        @(negedge clk); ie = 0; de = 0;
        repeat (3) @(negedge clk);
        $display("ROM_NATIVE_PASS checks=%0d", checks);
        $finish;
    end
endmodule
