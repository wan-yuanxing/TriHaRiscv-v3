`timescale 1ns/1ps

module tb_soc_memory;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    reg i_req = 0;
    reg [31:0] i_addr = 0;
    wire i_accept, i_valid, i_error;
    wire [63:0] i_data;
    reg [31:0] d_addr = 0, d_wdata = 0;
    reg d_re = 0;
    reg [3:0] d_we = 0;
    reg [10:0] d_tag = 0;
    reg d_flush = 0;
    reg d_invalidate = 0, d_writeback = 0;
    wire d_accept, d_ack, d_error;
    wire [31:0] d_data;
    wire [10:0] d_resp;
    wire tx, done;
    wire [7:0] code;
    integer checks = 0;
    integer n;
    integer uart_count = 0;
    reg [7:0] uart_bytes [0:3];
    reg [7:0] serial_byte;
    integer bit_index;
    reg [31:0] expected [0:31];

    triha_soc_memory #(.UART_DIVISOR(8)) u_dut (
        .clk_i(clk), .rst_ni(rst_n),
        .inst_req_i(i_req), .inst_addr_i(i_addr),
        .inst_accept_o(i_accept), .inst_valid_o(i_valid),
        .inst_error_o(i_error), .inst_rdata_o(i_data),
        .data_addr_i(d_addr), .data_wdata_i(d_wdata),
        .data_re_i(d_re), .data_wstrb_i(d_we), .data_req_tag_i(d_tag),
        .data_invalidate_i(d_invalidate), .data_writeback_i(d_writeback), .data_flush_i(d_flush),
        .data_accept_o(d_accept), .data_ack_o(d_ack), .data_error_o(d_error),
        .data_rdata_o(d_data), .data_resp_tag_o(d_resp),
        .uart_tx_o(tx), .done_o(done), .exit_code_o(code)
    );

    // Independent wire-level receiver, not the transmitter's internal data.
    initial forever begin
        @(negedge tx);
        repeat (12) @(posedge clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            serial_byte[bit_index] = tx;
            repeat (8) @(posedge clk);
        end
        check(tx === 1'b1, "UART stop bit");
        uart_bytes[uart_count] = serial_byte;
        uart_count = uart_count + 1;
    end

    task check;
        input condition;
        input [255:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("SOC_MEMORY_FAIL %0s time=%0t", message, $time);
                $finish;
            end
            checks = checks + 1;
        end
    endtask

    task access;
        input [31:0] address, value;
        input read;
        input [3:0] lanes;
        input error;
        input [31:0] want;
        integer waits;
        begin
            @(negedge clk);
            while (!d_accept) @(negedge clk);
            d_addr = address; d_wdata = value; d_re = read; d_we = lanes;
            d_tag = (d_tag + 11'd37);
            @(posedge clk); #1;
            @(negedge clk); d_re = 0; d_we = 0;
            // Keep the old address but corrupt payload after acceptance.
            // The delayed UART transaction must use its captured byte.
            d_wdata = ~value;
            waits = 0;
            while (!d_ack && waits < 300) begin
                @(negedge clk); waits = waits + 1;
            end
            check(d_ack && d_error === error && d_resp === d_tag, "completion/error/tag");
            if (read && !error) check(d_data === want, "read value");
            check(d_accept, "next request allowed with registered response");
            @(negedge clk);
            check(!d_ack, "ack exactly once");
        end
    endtask

    task fetch;
        input [31:0] address;
        input error;
        input [63:0] want;
        begin
            @(negedge clk); i_req = 1; i_addr = address;
            while (!i_accept) @(negedge clk);
            @(posedge clk); #1;
            check(i_valid && i_error === error, "fetch response");
            if (!error) check(i_data === want, "fetch lanes");
            @(negedge clk); i_req = 0;
        end
    endtask

    initial begin
        if ($test$plusargs("FAULT_READ")) force u_dut.data_rdata_o = 32'b0;
        repeat (3) @(negedge clk); rst_n = 1;
        // A local synchronous read must respond after the acceptance edge.
        // The initial controller unnecessarily waited an additional cycle.
        @(negedge clk); d_addr = 0; d_re = 1; d_tag = 11'd7;
        @(posedge clk); #1;
        check(d_ack && !d_error && d_data === 32'h000102b7, "local one-cycle response");
        @(negedge clk); d_re = 0;
        fetch(0, 0, 64'h00028067000102b7);
        fetch(32'h2000, 1, 0);
        fetch(32'h18000, 1, 0);
        for (n = 0; n < 32; n = n + 1) begin
            expected[n] = 32'h3f12a500 ^ (n * 32'h192731);
            access(32'h10000 + n * 4, expected[n], 0, 15, 0, 0);
        end
        for (n = 0; n < 32; n = n + 1)
            access(32'h10000 + n * 4, 0, 1, 0, 0, expected[n]);
        access(32'h10004, 32'h00aa00bb, 0, 5, 0, 0);
        expected[1] = (expected[1] & 32'hff00ff00) | 32'h00aa00bb;
        access(32'h10004, 0, 1, 0, 0, expected[1]);
        fetch(32'h10000, 0, {expected[1], expected[0]});
        // Each accepted stream beat must have a matching response/tag;
        // reads immediately following stores see the latest written values.
        for (n = 0; n < 32; n = n + 1) begin
            @(negedge clk);
            expected[n] = 32'h591b4c00 ^ (n * 32'h125731);
            d_addr = 32'h10000 + n * 4; d_wdata = expected[n];
            d_we = 15; d_re = 0; d_tag = n;
            @(posedge clk); #1;
            check(d_accept && d_ack && !d_error && d_resp == n, "streamed store response");
        end
        for (n = 0; n < 32; n = n + 1) begin
            @(negedge clk);
            d_addr = 32'h10000 + n * 4; d_we = 0; d_re = 1; d_tag = 100 + n;
            @(posedge clk); #1;
            check(d_accept && d_ack && !d_error && d_resp == 100 + n && d_data === expected[n], "streamed read data/tag");
        end
        @(negedge clk); d_re = 0;
        access(32'h17ffc, 32'h5adbcafe, 0, 15, 0, 0);
        access(32'h17ffc, 0, 1, 0, 0, 32'h5adbcafe);
        access(32'h18000, 0, 1, 0, 1, 0);
        access(32'h80000000, 0, 1, 0, 1, 0);
        access(32'h10001, 0, 1, 0, 1, 0);
        access(0, 32'hdeadbeef, 0, 15, 1, 0);
        access(0, 0, 1, 0, 0, 32'h000102b7);
        access(32'h10000, 0, 1, 15, 1, 0);
        // A maintenance request is completed with an error, never hung.
        @(negedge clk); while (!d_accept) @(negedge clk);
        d_flush = 1;
        @(posedge clk); #1;
        @(negedge clk); d_flush = 0;
        while (!d_ack) @(negedge clk);
        check(d_error, "unsupported maintenance");
        @(negedge clk);
        // Every maintenance combination forbids a simultaneous SRAM write.
        // Rejected writes must not stall a same-word instruction fetch or
        // alter any byte; verify both the I response and a subsequent D read.
        for (n = 1; n < 8; n = n + 1) begin
            @(negedge clk); while (!d_accept) @(negedge clk);
            d_addr = 32'h10000; d_wdata = 32'hdeadbeef; d_we = 15;
            d_invalidate = n[0]; d_writeback = n[1]; d_flush = n[2];
            d_tag = 128 + n; i_req = 1; i_addr = 32'h10000;
            #1; check(i_accept, "invalid SRAM write no collision stall");
            @(posedge clk); #1;
            check(d_ack && d_error && d_resp == 128 + n, "invalid SRAM write completed once");
            check(i_valid && !i_error && i_data === {expected[1], expected[0]}, "invalid write I memory retained");
            @(negedge clk); d_we = 0; d_invalidate = 0; d_writeback = 0; d_flush = 0; i_req = 0;
            access(32'h10000, 0, 1, 0, 0, expected[0]);
        end
        access(32'h10000004, 0, 1, 0, 0, 1);
        access(32'h10000000, 32'h41, 0, 1, 0, 0);
        access(32'h10000000, 32'h42, 0, 1, 0, 0);
        repeat (82) @(negedge clk);
        check(uart_count == 2 && uart_bytes[0] == 8'h41 && uart_bytes[1] == 8'h42, "UART captured bytes once");
        // Simultaneous same-word store suppresses I-port acceptance for one cycle.
        @(negedge clk); while (!d_accept) @(negedge clk);
        i_req = 1; i_addr = 32'h10000; d_addr = 32'h10000;
        d_wdata = expected[0]; d_we = 15;
        #1; check(!i_accept, "read/write collision blocked");
        @(posedge clk); #1; check(!i_valid, "collision no spurious valid");
        @(negedge clk); d_we = 0;
        @(posedge clk); #1;
        check(i_valid && i_data === {expected[1], expected[0]}, "post-store fetch visible");
        @(negedge clk); i_req = 0;
        while (!d_accept) @(negedge clk);
        // Continuous fetches are not serialized by data acknowledgements.
        @(negedge clk); i_req = 1; i_addr = 32'h10000;
        repeat (8) begin
            @(posedge clk); #1;
            check(i_accept && i_valid && i_data === {expected[1], expected[0]}, "continuous fetch");
        end
        @(negedge clk); i_req = 0;
        // Reset discards a pending completion; memory is retained.
        d_addr = 32'h10000; d_re = 1;
        @(posedge clk); #1;
        @(negedge clk); rst_n = 0; d_re = 0;
        @(negedge clk); check(!d_ack && !i_valid && tx && !done, "coordinated reset");
        rst_n = 1;
        access(32'h10000, 0, 1, 0, 0, expected[0]);
        access(32'h20020000, 0, 1, 0, 0, 32'h54524801);
        access(32'h20020004, 32'h5a, 0, 1, 0, 0);
        check(done && code == 8'h5a, "debug exit");
        $display("SOC_MEMORY_PASS checks=%0d", checks);
        $finish;
    end

    initial begin
        #1000000; $display("SOC_MEMORY_FAIL timeout"); $finish;
    end
endmodule
