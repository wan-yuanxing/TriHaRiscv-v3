`timescale 1ns / 1ps
// Reuses the local-system AXI128 model with three public-port IRQ triggers.
`include "biriscv_defs.v"
`include "cache_irq_symbols.vh"
module tb_cpu_cache_irq;
    parameter integer MAX_CYCLES = 200000;
    reg ddr_ready = 1, ddr_fault = 0;
    reg irq = 0;
    wire fault, uart_tx, done;
    wire [7:0] exit_code;
    parameter integer CORRUPT_DATA = 0;
    parameter integer CACHE_ENABLE = 1;
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
    wire awready = !have_aw && !bvalid && rng[0];
    wire wready = !have_w && !bvalid && rng[2];
    wire arready = !read_pending && !rvalid && rng[4];
    reg [1:0] bresp = 0, rresp = 0;
    reg [3:0] bid = 0, rid = 0;
    reg [127:0] rdata = 0, saved_wdata;
    reg [15:0] saved_strobe;
    reg [31:0] saved_awaddr, saved_araddr;
    integer write_wait = 0, read_beat = 0, read_count, read_wait = 0;
    triha_cached_soc #(.CACHE_ENABLE(CACHE_ENABLE)) u_dut (
        .ddr_ready_i(ddr_ready), .ddr_fault_i(ddr_fault), .ddr_fault_o(fault),
        .uart_tx_o(uart_tx), .done_o(done), .exit_code_o(exit_code),
        .clk_i(clk), .rst_ni(rst_n), .external_irq_i(irq),
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
                if (write_wait > 0) write_wait <= write_wait - 1;
                else begin
                    bvalid <= 1; bresp <= 0;
                    for (lane = 0; lane < 16; lane = lane + 1)
                        if (saved_strobe[lane])
                            memory[word_index(saved_awaddr) + lane/4][(lane%4)*8 +: 8] <= saved_wdata[lane*8 +: 8];
                end
            end
            if (bvalid && bready) begin
                bvalid <= 0; have_aw <= 0; have_w <= 0; writes <= writes + 1;
            end
            if (arvalid && arready) begin
                check(araddr[3:0] == 0 && arlen <= 1 && arsize == 4 && arburst == 1, "AR geometry");
                check(({1'b0,araddr[11:0]} + ((arlen+1)*16)) <= 4096, "read cannot cross 4KiB");
                read_pending <= 1; saved_araddr <= araddr; read_count <= arlen + 1;
                read_beat <= 0; rid <= arid; reads <= reads + 1;
                read_wait <= araddr == 32'h80002400 ? 64 : 3;
                if (arid != 2) i_reads <= i_reads + 1; else d_reads <= d_reads + 1;
            end
            if (rvalid && rready) begin
                rvalid <= 0;
                if (rlast) read_pending <= 0; else read_beat <= read_beat + 1;
            end
            if (read_pending && read_wait > 0) read_wait <= read_wait - 1;
            if (read_pending && !rvalid && read_wait == 0 && rng[6]) begin
                rvalid <= 1; rlast <= read_beat == read_count - 1;
                rresp <= 0;
                for (lane = 0; lane < 4; lane = lane + 1)
                    rdata[lane*32 +: 32] <= memory[word_index(saved_araddr)+read_beat*4+lane] ^ CORRUPT_DATA;
            end
        end
    end
    `define CORE u_dut.u_core.u_cpu
    `define CSR `CORE.u_csr.u_csrfile
    integer n, wb_file, event_file;
    integer phase = 0, fired = 0, entries = 0, returns = 0, resumes = 0, retired = 0;
    integer hit_reads = 0, wait_reads = 0, return_reads = 0, delayed_irq_cycles = 0;
    integer load_retired [1:3];
    integer after_retired [1:3];
    integer checkpoints = 0;
    reg target_pending = 0, resume_pending = 0;
    reg [31:0] target_addr = 0, saved_epc = 0;
    reg [10:0] target_tag = 0;
    wire [31:0] mepc = `CSR.csr_mepc_q;
    wire [31:0] mcause = `CSR.csr_mcause_q;
    wire [31:0] mstatus = `CSR.csr_sr_q;
    wire [31:0] mie = `CSR.csr_mie_q;
    wire [5:0] exception = `CSR.exception_i;
    wire [31:0] wb_pc = `CORE.u_issue.pipe0_pc_wb_w;
    wire wb_valid = `CORE.u_issue.pipe0_valid_wb_w;
    initial begin
        for (n = 0; n < 131072; n = n + 1) memory[n] = 32'h3155a72b ^ (n*32'h8721345);
        memory[word_index(32'h80002400)] = 32'h2468ace0;
        memory[word_index(32'h80002800)] = 32'h31415926;
        for (n = 1; n <= 3; n = n + 1) begin load_retired[n] = 0; after_retired[n] = 0; end
        wb_file = $fopen("cache-irq.wb.log", "w");
        event_file = $fopen("cache-irq.events.log", "w");
        check(wb_file != 0 && event_file != 0, "trace files open");
        #1;
        check(CACHE_ENABLE == 1 && u_dut.u_core.DUAL_ISSUE == 0 &&
            `CORE.NUM_BTB_ENTRIES == 512 && `CORE.BTB_DIRECT_MAPPED == 1 &&
            `CORE.NUM_BHT_ENTRIES == 512 && `CORE.NUM_RAS_ENTRIES == 4 && `CORE.GSHARE_ENABLE == 0,
            "actual cached single-issue predictor configuration");
        repeat (6) @(negedge clk); rst_n = 1;
    end
    // Sample the public data transaction and its tag, never force DUT state.
    always @(posedge clk) if (rst_n) begin
        if (u_dut.data_accept && |u_dut.data_wstrb && u_dut.data_addr == 32'h00017000) begin
            check(u_dut.data_wdata == phase + 1, "phase marker order");
            phase = u_dut.data_wdata;
        end
        if (u_dut.data_accept && |u_dut.data_wstrb && u_dut.data_addr == 32'h00017004) begin
            checkpoints = checkpoints + 1;
            check(u_dut.data_wdata == checkpoints && checkpoints == phase, "software effects occur once");
        end
        if (u_dut.data_ack && target_pending && u_dut.data_resp_tag == target_tag) target_pending <= 0;
        if (phase > 0 && u_dut.data_accept && u_dut.data_re &&
            (u_dut.data_addr == 32'h80002000 || u_dut.data_addr == 32'h80002400 || u_dut.data_addr == 32'h80002800)) begin
            target_pending <= 1; target_addr <= u_dut.data_addr; target_tag <= u_dut.data_req_tag;
        end
        if (arvalid && arready && arid == 2) begin
            if (araddr == 32'h80002000) hit_reads = hit_reads + 1;
            if (araddr == 32'h80002400) wait_reads = wait_reads + 1;
            if (araddr == 32'h80002800) return_reads = return_reads + 1;
        end
        if (irq && read_pending && saved_araddr == 32'h80002400 && !rvalid)
            delayed_irq_cycles = delayed_irq_cycles + 1;
        check(!`CORE.u_issue.pipe1_valid_wb_w, "single retirement port");
        if (wb_valid && (`CORE.u_issue.pipe0_exception_wb_w == 0 ||
            `CORE.u_issue.pipe0_exception_wb_w == `EXCEPTION_ERET_M ||
            `CORE.u_issue.pipe0_exception_wb_w == `EXCEPTION_FENCE)) begin
            retired = retired + 1;
            $fwrite(wb_file, "%08h %08h %02h %08h %02h\n", wb_pc, `CORE.u_issue.pipe0_opc_wb_w,
                `CORE.u_issue.pipe0_rd_wb_w, `CORE.u_issue.pipe0_result_wb_w, `CORE.u_issue.pipe0_exception_wb_w);
            if (resume_pending) begin
                check(wb_pc == saved_epc, "first retired PC after MRET equals original mepc");
                resumes = resumes + 1; resume_pending = 0;
            end
            if (wb_pc == `PHASE1_LOAD) load_retired[1] = load_retired[1] + 1;
            if (wb_pc == `PHASE2_LOAD) load_retired[2] = load_retired[2] + 1;
            if (wb_pc == `PHASE3_LOAD) load_retired[3] = load_retired[3] + 1;
            if (wb_pc == `PHASE1_AFTER) after_retired[1] = after_retired[1] + 1;
            if (wb_pc == `PHASE2_AFTER) after_retired[2] = after_retired[2] + 1;
            if (wb_pc == `PHASE3_AFTER) after_retired[3] = after_retired[3] + 1;
        end
        if ((exception & 6'h30) == `EXCEPTION_INTERRUPT) begin
            entries = entries + 1;
            check(entries == phase && entries == fired && irq, "one trap per external assertion");
            #1;
            saved_epc = mepc;
            check(mcause == 32'h8000000b && `CSR.csr_mtval_q == 0, "machine external interrupt CSR cause");
            check(mstatus == 32'h1880 && mie == 32'h800, "entry MIE MPIE MPP and mie");
            case (phase)
                1: check(mepc >= `PHASE1_LOAD && mepc < `PHASE1_END, "phase1 precise PC range");
                2: check(mepc >= `PHASE2_LOAD && mepc < `PHASE2_END, "phase2 precise PC range");
                3: check(mepc >= `PHASE3_LOAD && mepc < `PHASE3_END, "phase3 precise PC range");
            endcase
            $fwrite(event_file, "ENTRY phase=%0d time=%0t mepc=%08h mcause=%08h mstatus=%08h\n", phase, $time, mepc, mcause, mstatus);
            irq = 0;
        end
        if (exception == `EXCEPTION_ERET_M) begin
            check(mepc == saved_epc, "MRET must not skip original interrupted PC");
            returns = returns + 1;
            check(returns == entries && mie == 0, "handler clears mie and returns once");
            #1;
            check(mstatus == 32'h88, "MRET restores MIE and MPIE");
            resume_pending = 1;
            $fwrite(event_file, "RETURN phase=%0d time=%0t mepc=%08h mstatus=%08h\n", phase, $time, mepc, mstatus);
        end
    end
    // Drive half a cycle before the CPU consumes the selected response.
    always @(negedge clk) if (rst_n && fired < phase) begin
        if ((phase == 1 || phase == 3) && target_pending && u_dut.data_ack &&
            u_dut.data_resp_tag == target_tag) begin
            if (phase == 1) check(target_addr == 32'h80002000 && hit_reads == 1, "resident hit without lower refill");
            else check(target_addr == 32'h80002800 && return_reads == 1, "fresh miss returns before IRQ");
            fired = phase; irq = 1;
            $fwrite(event_file, "ASSERT phase=%0d time=%0t reason=load_response\n", phase, $time);
        end
        if (phase == 2 && read_pending && saved_araddr == 32'h80002400 && read_wait >= 50 && !rvalid) begin
            check(target_pending && target_addr == 32'h80002400, "IRQ during an outstanding cache miss");
            fired = phase; irq = 1;
            $fwrite(event_file, "ASSERT phase=2 time=%0t reason=refill_wait remaining=%0d\n", $time, read_wait);
        end
    end
    initial begin
        wait(rst_n && done);
        @(negedge clk);
        check(exit_code == 0, "IRQ firmware success exit");
        check(phase == 3 && fired == 3 && entries == 3 && returns == 3 && resumes == 3, "all three IRQ scenarios complete");
        check(checkpoints == 3 && !protocol_fault && !fault, "software and AXI complete without fault");
        check(hit_reads == 1 && wait_reads == 1 && return_reads == 1 && i_reads > 0, "I/D cache residency and refill coverage");
        check(delayed_irq_cycles >= 40, "interrupt asserted while lower read withheld");
        for (n = 1; n <= 3; n = n + 1) begin
            check(load_retired[n] == 1 && after_retired[n] == 1, "load and following instruction retire exactly once");
        end
        $display("CPU_CACHE_IRQ_PASS cycles=%0d checks=%0d reads=%0d writes=%0d entries=%0d returns=%0d resumes=%0d retired=%0d wait_irq_cycles=%0d",
            cycles, checks, reads, writes, entries, returns, resumes, retired, delayed_irq_cycles);
        $fclose(wb_file); $fclose(event_file);
        $finish;
    end
    `undef CORE
    `undef CSR
endmodule
