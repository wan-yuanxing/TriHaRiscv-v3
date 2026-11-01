`timescale 1ns / 1ps
// Exercises the common DDR boundary independently of cache tag/controller state.
module tb_cpu_cache_soc;
    parameter integer MAX_CYCLES = 200000;
    reg ddr_ready = 0, ddr_fault = 0;
    wire fault, uart_tx, done;
    wire [7:0] exit_code;
    integer status_polls = 0, local_writes = 0, fault_delay = 0;
    parameter integer CORRUPT_DATA = 0;
    parameter integer CACHE_ENABLE = 1;
    parameter integer COREMARK_MODE = 0;
    reg clk = 0, rst_n = 0;
    always #5 clk = !clk;
    reg [31:0] rng = 32'h763d93e1;
    integer cycles = 0, checks = 0, reads = 0, writes = 0;
    reg [31:0] memory [0:131071];
    task check;
        input ok;
        input [511:0] message;
        begin
            checks = checks + 1;
            if (ok !== 1'b1) begin $display("CPU_CACHE_FAIL %0s cycle=%0d", message, cycles); $fatal(1); end
        end
    endtask
    always @(posedge clk) begin
        rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
        cycles <= cycles + 1;
        if (cycles > MAX_CYCLES) check(0, "transport watchdog");
    end
    task fail;
        input [511:0] message;
        begin check(0, message); end
    endtask
    function integer word_index;
        input [31:0] address;
        begin word_index = {address[25], address[17:2]}; end
    endfunction
    integer i_reads = 0, d_reads = 0;
    wire protocol_fault;
    wire awvalid, wvalid, wlast, bready, arvalid, rready;
    wire [31:0] awaddr, araddr;
    wire [3:0] awid, arid;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire [1:0] awburst, arburst;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg have_aw = 0, have_w = 0, read_pending = 0;
    reg bvalid = 0, rvalid = 0, rlast = 0;
    wire awready = !have_aw && !bvalid && (COREMARK_MODE || rng[0]);
    wire wready = !have_w && !bvalid && (COREMARK_MODE || rng[2]);
    wire arready = !read_pending && !rvalid && (COREMARK_MODE || rng[4]);
    reg [1:0] bresp = 0, rresp = 0;
    reg [3:0] bid = 0, rid = 0;
    reg [127:0] rdata = 0, saved_wdata;
    reg [15:0] saved_strobe;
    reg [31:0] saved_awaddr, saved_araddr;
    integer write_wait = 0, read_beat = 0, read_count;
    reg write_error = 0;
    integer read_error_beat = -1;
    wire d_ack = u_dut.u_core.data_ack_i;
    triha_cached_soc #(.CACHE_ENABLE(CACHE_ENABLE)) u_dut (
        .ddr_ready_i(ddr_ready), .ddr_fault_i(ddr_fault), .ddr_fault_o(fault),
        .uart_tx_o(uart_tx), .done_o(done), .exit_code_o(exit_code),
        .clk_i(clk), .rst_ni(rst_n), .external_irq_i(1'b0),
        .protocol_fault_o(protocol_fault),
        .axi_awvalid_o(awvalid), .axi_awaddr_o(awaddr), .axi_awid_o(awid), .axi_awlen_o(awlen),
        .axi_awsize_o(awsize), .axi_awburst_o(awburst), .axi_awready_i(awready),
        .axi_wvalid_o(wvalid), .axi_wdata_o(wdata), .axi_wstrb_o(wstrb), .axi_wlast_o(wlast), .axi_wready_i(wready),
        .axi_bvalid_i(bvalid), .axi_bresp_i(bresp), .axi_bid_i(bid), .axi_bready_o(bready),
        .axi_arvalid_o(arvalid), .axi_araddr_o(araddr), .axi_arid_o(arid), .axi_arlen_o(arlen),
        .axi_arsize_o(arsize), .axi_arburst_o(arburst), .axi_arready_i(arready),
        .axi_rvalid_i(rvalid), .axi_rdata_i(rdata), .axi_rresp_i(rresp), .axi_rid_i(rid),
        .axi_rlast_i(rlast), .axi_rready_o(rready)
    );
    integer lane;
    reg hold_aw = 0, hold_w = 0, hold_ar = 0;
    reg [48:0] last_aw, last_ar;
    reg [144:0] last_w;
    always @(posedge clk) begin
        if (!rst_n) begin
            bvalid <= 0; rvalid <= 0; have_aw <= 0; have_w <= 0; read_pending <= 0;
            hold_aw <= 0; hold_w <= 0; hold_ar <= 0;
        end else begin
            if (hold_aw) check(awvalid && {awaddr,awid,awlen,awsize,awburst} === last_aw, "AW must remain stable");
            if (hold_w) check(wvalid && {wdata,wstrb,wlast} === last_w, "W must remain stable");
            if (hold_ar) check(arvalid && {araddr,arid,arlen,arsize,arburst} === last_ar, "AR must remain stable");
            hold_aw <= awvalid && !awready; last_aw <= {awaddr,awid,awlen,awsize,awburst};
            hold_w <= wvalid && !wready; last_w <= {wdata,wstrb,wlast};
            hold_ar <= arvalid && !arready; last_ar <= {araddr,arid,arlen,arsize,arburst};
            if (awvalid && awready) begin
                check(awaddr[3:0] == 0 && awlen == 0 && awsize == 4 && awburst == 1, "scalar AW geometry");
                have_aw <= 1; saved_awaddr <= awaddr; bid <= awid;
            end
            if (wvalid && wready) begin
                check(wlast, "scalar WLAST");
                have_w <= 1; saved_wdata <= wdata; saved_strobe <= wstrb; write_wait <= 30;
            end
            if (have_aw && have_w && !bvalid) begin
                if (write_wait > 0) begin write_wait <= write_wait - 1; check(!d_ack, "D store waits for B"); end
                else begin
                    bvalid <= 1; bresp <= write_error ? 2'b10 : 0;
                    if (!write_error)
                        for (lane = 0; lane < 16; lane = lane + 1)
                            if (saved_strobe[lane])
                                memory[word_index(saved_awaddr) + lane/4][(lane%4)*8 +: 8] <= saved_wdata[lane*8 +: 8];
                end
            end
            if (bvalid && bready) begin
                bvalid <= 0; have_aw <= 0; have_w <= 0; writes <= writes + 1;
                if (saved_awaddr == 32'h820000f0) fault_delay <= 10;
            end
            if (arvalid && arready) begin
                check(araddr[3:0] == 0 && arlen <= 1 && arsize == 4 && arburst == 1, "AR geometry");
                check(({1'b0,araddr[11:0]} + ((arlen+1)*16)) <= 4096, "read cannot cross 4KiB");
                read_pending <= 1; saved_araddr <= araddr; read_count <= arlen + 1;
                read_beat <= 0; rid <= arid; reads <= reads + 1;
                if (arid != 2) i_reads <= i_reads + 1; else d_reads <= d_reads + 1;
            end
            if (rvalid && rready) begin
                rvalid <= 0;
                if (rlast) read_pending <= 0; else read_beat <= read_beat + 1;
            end
            if (read_pending && !rvalid && (COREMARK_MODE || rng[6])) begin
                rvalid <= 1; rlast <= read_beat == read_count - 1;
                rresp <= (read_beat == read_error_beat || saved_araddr == 32'h80018000) ? 2'b10 : 0;
                for (lane = 0; lane < 4; lane = lane + 1)
                    rdata[lane*32 +: 32] <= memory[word_index(saved_araddr)+read_beat*4+lane] ^ CORRUPT_DATA;
            end
        end
    end
    integer n, serial_bit, serial_count = 0;
    reg [7:0] serial_byte;
    initial forever begin
        @(negedge uart_tx);
        repeat (1302) @(posedge clk);
        for (serial_bit = 0; serial_bit < 8; serial_bit = serial_bit + 1) begin
            serial_byte[serial_bit] = uart_tx;
            repeat (868) @(posedge clk);
        end
        check(uart_tx === 1'b1, "UART stop bit");
        check(serial_byte === (serial_count == 0 ? 8'h43 : 8'h4b), "actual UART byte");
        serial_count = serial_count + 1;
    end
    reg boot_seen = 0, private_exec = 0, shared_exec = 0;
    integer trap_count = 0;
    initial begin
        for (n = 0; n < 131072; n = n + 1) memory[n] = 32'h3155a72b ^ (n*32'h8721345);
        repeat (6) @(negedge clk); rst_n = 1;
    end
    always @(posedge clk) if (rst_n) begin
        if (u_dut.inst_req && u_dut.inst_accept) begin
            if (u_dut.inst_addr == 0) boot_seen <= 1;
            if (u_dut.inst_addr == 32'h80001000) private_exec <= 1;
            if (u_dut.inst_addr == 32'h82001000) shared_exec <= 1;
        end
        if (u_dut.data_accept && u_dut.data_re && u_dut.data_addr == 32'h2002000c)
            status_polls <= status_polls + 1;
        if (u_dut.data_accept && (|u_dut.data_wstrb) && !ddr_ready && u_dut.data_addr >= 32'h10000 && u_dut.data_addr < 32'h18000)
            local_writes <= local_writes + 1;
        if (status_polls >= 4 && !fault) ddr_ready <= 1;
        if (fault_delay > 0) begin
            fault_delay <= fault_delay - 1;
            if (fault_delay == 1) begin ddr_fault <= 1; ddr_ready <= 0; end
        end
        if (u_dut.data_ack && u_dut.data_error) trap_count <= trap_count + 1;
    end
    initial begin
        wait(rst_n && done);
        repeat (9000) @(negedge clk);
        check(exit_code == 0, "real firmware success exit");
        check(boot_seen && private_exec && shared_exec, "local/private/shared execution coverage");
        check(status_polls >= 4 && local_writes > 0 && fault && !ddr_ready, "DDR init and failure coverage");
        check(trap_count == 3 && !protocol_fault, "three owned access faults with intact AXI protocol");
        check(serial_count == 2, "two slow MMIO UART transactions");
        check(memory[word_index(32'h80000000)] == 32'h1357a5df, "true lower byte store");
        check(memory[word_index(32'h82000000)] == 32'h2468ace0, "true shared lower store");
        check(memory[word_index(32'h80001000)] == 32'h00900513, "modified private code reached lower memory");
        $display("CPU_CACHE_SOC_PASS cycles=%0d checks=%0d reads=%0d writes=%0d traps=%0d cache=%0d", cycles, checks, reads, writes, trap_count, CACHE_ENABLE);
        $finish;
    end
endmodule
