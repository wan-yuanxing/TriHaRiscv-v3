`timescale 1ns / 1ps
// Real CPU/local boot through the asynchronous boundary and pinned DDR bridge.
module tb_cpu_ddr_system;
    parameter integer MAX_CYCLES = 200000;
    reg ddr_ready = 0, ddr_fault = 0;
    wire fault, uart_tx, done;
    wire [7:0] exit_code;
    integer status_polls = 0, local_writes = 0, fault_delay = 0;
    parameter integer CORRUPT_DATA = 0;
    parameter integer CACHE_ENABLE = 1;
    reg clk = 0, rst_n = 0;
    always #5 clk = !clk;
    integer cycles = 0, checks = 0;
    task check;
        input ok;
        input [511:0] message;
        begin
            checks = checks + 1;
            if (ok !== 1'b1) begin $display("CPU_CACHE_FAIL %0s cycle=%0d", message, cycles); $fatal(1); end
        end
    endtask
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (cycles > MAX_CYCLES) check(0, "transport watchdog");
    end
    wire protocol_fault;
    reg ddr_clk = 0;
    always #4 ddr_clk = !ddr_clk;
    wire [27:0] h_awaddr, h_araddr;
    wire [3:0] h_awlen, h_arlen, h_awid, h_arid, h_wid, h_rid;
    wire h_awvalid, h_arvalid, h_awready, h_arready, h_wready, h_rvalid, h_wlast, h_rlast;
    wire [255:0] h_wdata, h_rdata;
    wire [31:0] h_wstrb;
    wire [7:0] bridge_code;
    wire [31:0] native_write_beats, native_read_beats, earliest, masked, native_aw, native_ar, native_gaps;
    reg request_fault = 0, mailbox_pending = 0;
    reg [10:0] mailbox_tag;
    reg inject_read_error = 0;
    reg store_pending = 0, native_written = 0, verify_active = 0, native_verified = 0;
    reg [31:0] store_addr, store_data;
    reg [3:0] store_strobe;
    reg [10:0] store_tag;
    reg [255:0] store_observed;
    integer completed_stores = 0, store_lane;
    wire [27:0] store_native_addr = (store_addr - 32'h80000000) >> 2 & 28'hffffff8;
    wire [1:0] faulted_rresp = inject_read_error ? 2'b10 : u_dut.bridge_rresp_w;
    initial force u_dut.ddr_rresp_w = faulted_rresp;
    always @(posedge ddr_clk) begin
        if (!rst_n) inject_read_error <= 0;
        else begin
            if (u_dut.ddr_arvalid_w && u_dut.ddr_arready_w)
                inject_read_error <= u_dut.ddr_araddr_w == 32'h80018000;
            if (u_dut.ddr_rvalid_w && u_dut.ddr_rready_w && u_dut.ddr_rlast_w)
                inject_read_error <= 0;
            if (store_pending && h_wready) native_written = 1;
            if (store_pending && native_written && h_arvalid && h_arready && h_araddr == store_native_addr)
                verify_active = 1;
            if (store_pending && verify_active && h_rvalid && h_rlast) native_verified = 1;
        end
    end
    triha_cpu_ddr #(.CACHE_ENABLE(CACHE_ENABLE)) u_dut (
        .cpu_clk_i(clk), .ddr_clk_i(ddr_clk), .rst_ni(rst_n), .external_irq_i(1'b0),
        .ddr_ready_i(ddr_ready), .ddr_fault_i(ddr_fault), .cpu_ddr_fault_o(fault),
        .protocol_fault_o(protocol_fault), .bridge_fault_code_o(bridge_code),
        .uart_tx_o(uart_tx), .done_o(done), .exit_code_o(exit_code),
        .h_awaddr_o(h_awaddr), .h_awlen_o(h_awlen), .h_awid_o(h_awid), .h_awvalid_o(h_awvalid), .h_awready_i(h_awready),
        .h_wdata_o(h_wdata), .h_wstrb_o(h_wstrb), .h_wready_i(h_wready), .h_wid_i(h_wid), .h_wlast_i(h_wlast),
        .h_araddr_o(h_araddr), .h_arlen_o(h_arlen), .h_arid_o(h_arid), .h_arvalid_o(h_arvalid), .h_arready_i(h_arready),
        .h_rdata_i(h_rdata), .h_rid_i(h_rid), .h_rlast_i(h_rlast), .h_rvalid_i(h_rvalid)
    );
    ddr_native_model #(.MEMORY_SLOTS(512)) u_memory (
        .clk(ddr_clk), .reset_n(u_dut.ddr_rst_n), .fault_mode(CORRUPT_DATA), .address_mask(28'hfffffff), .delayed(1'b1),
        .axi_awaddr(h_awaddr), .axi_awvalid(h_awvalid), .axi_awlen(h_awlen), .axi_awuser_id(h_awid), .axi_awready(h_awready),
        .axi_wdata(h_wdata), .axi_wstrb(h_wstrb), .axi_wready(h_wready), .axi_wusero_id(h_wid), .axi_wusero_last(h_wlast),
        .axi_araddr(h_araddr), .axi_arvalid(h_arvalid), .axi_arlen(h_arlen), .axi_aruser_id(h_arid), .axi_arready(h_arready),
        .axi_rdata(h_rdata), .axi_rid(h_rid), .axi_rlast(h_rlast), .axi_rvalid(h_rvalid),
        .write_beats(native_write_beats), .read_beats(native_read_beats), .earliest_beats(earliest), .masked_beats(masked),
        .aw_commands(native_aw), .ar_commands(native_ar), .write_gaps(native_gaps)
    );
    always @(negedge ddr_clk) begin
        if (!rst_n) begin ddr_ready = 0; ddr_fault = 0; end
        else begin
            if (status_polls >= 4 && !request_fault) ddr_ready = 1;
            if (request_fault) begin ddr_ready = 0; ddr_fault = 1; end
        end
    end
    reg [255:0] stored_private, stored_shared, stored_code;
    integer serial_bit, serial_count = 0;
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
    integer live_resets = 0;
    initial begin
        repeat (6) @(negedge clk); rst_n = 1;
        // Reset all participants after native AW/W but before the CPU response.
        begin : await_live_store
            forever begin
                @(posedge ddr_clk);
                if (h_awvalid && h_awready) disable await_live_store;
            end
        end
        #1; rst_n = 0; live_resets = live_resets+1;
        repeat (8) @(negedge clk); rst_n = 1;
    end
    always @(posedge clk or negedge rst_n) if (!rst_n) begin
        store_pending = 0; native_written = 0; verify_active = 0; native_verified = 0;
        completed_stores = 0; mailbox_pending <= 0; fault_delay <= 0; request_fault <= 0;
        status_polls <= 0; local_writes <= 0; trap_count <= 0;
        boot_seen <= 0; private_exec <= 0; shared_exec <= 0; serial_count = 0;
    end else begin
        if (u_dut.u_soc.data_accept && (|u_dut.u_soc.data_wstrb) && u_dut.u_soc.data_addr >= 32'h80000000) begin
            check(!store_pending, "blocking CPU store ownership");
            store_pending = 1; native_written = 0; verify_active = 0; native_verified = 0;
            store_addr = u_dut.u_soc.data_addr; store_data = u_dut.u_soc.data_wdata;
            store_strobe = u_dut.u_soc.data_wstrb; store_tag = u_dut.u_soc.data_req_tag;
        end
        if (store_pending && u_dut.u_soc.data_ack && u_dut.u_soc.data_resp_tag == store_tag) begin
            if (!u_dut.u_soc.data_error) begin
                check(native_written && native_verified, "each successful store waits for native write and readback");
                store_observed = u_memory.stored_beat(store_native_addr);
                for (store_lane = 0; store_lane < 4; store_lane = store_lane+1)
                    if (store_strobe[store_lane])
                        check(store_observed[store_addr[4:2]*32 + store_lane*8 +: 8] == store_data[store_lane*8 +: 8], "each acknowledged byte exists in native memory");
                completed_stores = completed_stores+1;
            end
            store_pending = 0;
        end
        if (u_dut.u_soc.inst_req && u_dut.u_soc.inst_accept) begin
            if (u_dut.u_soc.inst_addr == 0) boot_seen <= 1;
            if (u_dut.u_soc.inst_addr == 32'h80001000) private_exec <= 1;
            if (u_dut.u_soc.inst_addr == 32'h82001000) shared_exec <= 1;
        end
        if (u_dut.u_soc.data_accept && u_dut.u_soc.data_re && u_dut.u_soc.data_addr == 32'h2002000c)
            status_polls <= status_polls + 1;
        if (u_dut.u_soc.data_accept && (|u_dut.u_soc.data_wstrb) && !ddr_ready && u_dut.u_soc.data_addr >= 32'h10000 && u_dut.u_soc.data_addr < 32'h18000)
            local_writes <= local_writes + 1;
        if (u_dut.u_soc.data_accept && (|u_dut.u_soc.data_wstrb) && u_dut.u_soc.data_addr == 32'h820000f0) begin
            mailbox_pending <= 1; mailbox_tag <= u_dut.u_soc.data_req_tag;
        end
        if (mailbox_pending && u_dut.u_soc.data_ack && u_dut.u_soc.data_resp_tag == mailbox_tag) begin
            check(!u_dut.u_soc.data_error && native_ar > native_aw, "store acknowledged after native readback");
            mailbox_pending <= 0; fault_delay <= 10;
        end
        if (fault_delay > 0) begin
            fault_delay <= fault_delay - 1;
            if (fault_delay == 1) request_fault <= 1;
        end
        if (u_dut.u_soc.data_ack && u_dut.u_soc.data_error) trap_count <= trap_count + 1;
    end
    initial begin
        wait(rst_n && done);
        repeat (9000) @(negedge clk);
        stored_private = u_memory.stored_beat(28'h0);
        stored_shared = u_memory.stored_beat(28'h800000);
        stored_code = u_memory.stored_beat(28'h400);
        check(exit_code == 0, "real firmware success exit");
        check(boot_seen && private_exec && shared_exec, "local/private/shared execution coverage");
        check(status_polls >= 4 && local_writes > 0 && fault && !ddr_ready, "DDR init and failure coverage");
        check(trap_count == 3 && !protocol_fault, "three owned access faults with intact AXI protocol");
        check(serial_count == 2, "two slow MMIO UART transactions");
        check(completed_stores == 22 && bridge_code == 1, "store coverage and actual bridge init-loss detection");
        check(live_resets == 1, "full CPU/cache/CDC/bridge/native coordinated live reset");
        check(stored_private[31:0] == 32'h1357a5df, "true lower byte store");
        check(stored_shared[31:0] == 32'h2468ace0, "true shared lower store");
        check(stored_code[31:0] == 32'h00900513, "modified private code reached lower memory");
        $display("CPU_DDR_SYSTEM_PASS cycles=%0d checks=%0d native_reads=%0d native_writes=%0d traps=%0d cache=%0d live_reset=%0d", cycles, checks, native_read_beats, native_write_beats, trap_count, CACHE_ENABLE, live_resets);
        $finish;
    end
endmodule
