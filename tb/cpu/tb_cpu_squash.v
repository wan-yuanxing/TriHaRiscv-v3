/* Real core, external port stimulus; no force or hierarchical DUT writes. */
`timescale 1ns / 1ps
`include "biriscv_defs.v"
`include "squash_symbols.vh"
module tb_cpu_squash #(
    parameter integer RESPONSE_DELAY = 32,
    parameter integer CORRUPT_FAULT = 0
);
    reg clk = 0, rst_n = 0;
    always #5 clk = !clk;
    integer cycles = 0, checks = 0, retired = 0, traps = 0, returns = 0;
    integer normal_stores = 0, mmio_writes = 0, csr_writes = 0, fault_returns = 0;
    integer csr_commit_cycles = 0;
    integer wait_cycles = 0, suppressed_load_wait = 0, redirect_count = 0;
    reg [31:0] memory [0:32767];
    reg i_pending = 0, i_valid = 0;
    reg [31:0] saved_i_pc = 0;
    reg [63:0] i_data = 0;
    wire i_req;
    wire i_accept = !i_pending;
    wire [31:0] i_pc;
    reg d_pending = 0, d_ack = 0, d_error = 0;
    reg [31:0] d_data = 32'hdeafbeef, saved_addr = 0, saved_data = 0;
    reg saved_error = 0;
    reg [10:0] saved_tag = 0, d_tag = 0;
    integer delay_left = 0;
    wire d_rd;
    wire d_accept = !d_pending && cycles % 4 != 0;
    wire [3:0] d_wr;
    wire [31:0] d_addr, d_wdata;
    wire [10:0] d_req_tag;
    triha_core u_dut (
        .clk_i(clk), .rst_ni(rst_n), .external_irq_i(1'b0),
        .inst_req_o(i_req), .inst_addr_o(i_pc), .inst_accept_i(i_accept),
        .inst_valid_i(i_valid), .inst_error_i(1'b0), .inst_rdata_i(i_data),
        .inst_flush_o(), .inst_invalidate_o(),
        .data_addr_o(d_addr), .data_wdata_o(d_wdata), .data_re_o(d_rd), .data_wstrb_o(d_wr),
        .data_req_tag_o(d_req_tag), .data_accept_i(d_accept), .data_ack_i(d_ack),
        .data_error_i(d_error), .data_rdata_i(d_data), .data_resp_tag_i(d_tag),
        .data_cacheable_o(), .data_invalidate_o(), .data_writeback_o(), .data_flush_o()
    );
    `define CORE u_dut.u_cpu
    `define CSR `CORE.u_csr.u_csrfile
    wire wb_valid = `CORE.u_issue.pipe0_valid_wb_w;
    wire [31:0] wb_pc = `CORE.u_issue.pipe0_pc_wb_w;
    wire [31:0] wb_data = `CORE.u_issue.pipe0_result_wb_w;
    wire [31:0] wb_opcode = `CORE.u_issue.pipe0_opc_wb_w;
    wire [4:0] wb_rd = `CORE.u_issue.pipe0_rd_wb_w;
    wire [5:0] wb_exception = `CORE.u_issue.pipe0_exception_wb_w;
    wire squash = `CORE.u_issue.squash_w;
    wire redirect = `CORE.u_issue.branch_request_o;
    wire [31:0] redirect_pc = `CORE.u_issue.branch_pc_o;
    wire [31:0] mscratch = `CSR.csr_mscratch_q;
    wire [31:0] mepc = `CSR.csr_mepc_q;
    wire [31:0] mcause = `CSR.csr_mcause_q;
    wire [31:0] mtval = `CSR.csr_mtval_q;
    wire [31:0] decode_pc = `CORE.u_issue.opcode_a_pc_r;
    wire decode_valid = `CORE.u_issue.opcode_a_valid_r;
    reg [6:0] wrong_fetched = 0, wrong_decoded = 0;
    reg [3:0] recovered = 0;
    reg [2:0] branch_redirects = 0;
    integer wb_file, event_file, n, lane;

    task check;
        input good;
        input [511:0] message;
        begin
            checks = checks + 1;
            if (good !== 1'b1) begin
                $display("CPU_SQUASH_FAIL %0s cycles=%0d", message, cycles);
                $fatal(1);
            end
        end
    endtask
    function integer wrong_index;
        input [31:0] pc;
        begin
            case (pc)
                `BAD_B_1: wrong_index = 0;
                `BAD_B_2: wrong_index = 1;
                `BAD_B_3: wrong_index = 2;
                `BAD_F_1: wrong_index = 3;
                `BAD_F_2: wrong_index = 4;
                `BAD_F_3: wrong_index = 5;
                `BAD_F_4: wrong_index = 6;
                default: wrong_index = -1;
            endcase
        end
    endfunction
    initial begin
        $readmemh("firmware.hex", memory);
        memory[32'h1f000/4] = 32'hcafecafe;
        memory[32'h1f004/4] = 32'h11223344;
        memory[32'h1f080/4] = 32'hdeafbeef;
        wb_file = $fopen("squash.wb.log", "w");
        event_file = $fopen("squash.events.log", "w");
        check(wb_file != 0 && event_file != 0, "trace open");
        #1;
        check(u_dut.DUAL_ISSUE == 0 && `CORE.NUM_BTB_ENTRIES == 512 && `CORE.BTB_DIRECT_MAPPED == 1 &&
            `CORE.NUM_BHT_ENTRIES == 512 && `CORE.NUM_RAS_ENTRIES == 4 && `CORE.GSHARE_ENABLE == 0,
            "actual single-issue predictor configuration");
        repeat (6) @(negedge clk); rst_n = 1;
    end
    // One response per accepted transaction. Idle response data is poison.
    always @(posedge clk) if (rst_n) begin
        cycles = cycles + 1;
        check(cycles < 50000, "watchdog");
        i_valid <= 0;
        if (i_pending) begin
            i_pending <= 0; i_valid <= 1;
            i_data <= {memory[saved_i_pc[16:2]+1], memory[saved_i_pc[16:2]]};
            if (wrong_index(saved_i_pc) >= 0) wrong_fetched[wrong_index(saved_i_pc)] = 1;
            if (wrong_index(saved_i_pc+4) >= 0) wrong_fetched[wrong_index(saved_i_pc+4)] = 1;
        end
        if (i_req && i_accept) begin
            check(i_pc >= 32'h80000000 && i_pc < 32'h80020000 && i_pc[2:0] == 0, "fetch address");
            i_pending <= 1; saved_i_pc <= i_pc;
        end
        d_ack <= 0; d_error <= 0; d_data <= 32'hdeafbeef;
        if (d_pending) begin
            if (delay_left > 0) begin delay_left <= delay_left - 1; wait_cycles = wait_cycles + 1; end
            else begin
                d_pending <= 0; d_ack <= 1; d_data <= saved_data;
                d_error <= saved_error; d_tag <= saved_tag;
                if (saved_addr == 32'h8001f080) begin
                    fault_returns = fault_returns + 1;
                    $fwrite(event_file, "FAULT_RESPONSE time=%0t error=%0d data=%08h\n", $time, saved_error, saved_data);
                end
            end
        end
        if ((d_rd || |d_wr) && d_accept) begin
            check(!d_pending, "single accepted outstanding transaction");
            check(d_addr != 32'h8001f084, "wrong-path younger load blocked");
            check(d_addr == 32'h10000000 || (d_addr >= 32'h80000000 && d_addr < 32'h80020000), "data address");
            d_pending <= 1; saved_addr <= d_addr; saved_tag <= d_req_tag;
            saved_error <= d_addr == 32'h8001f080 && !CORRUPT_FAULT;
            saved_data <= d_addr == 32'h10000000 ? mmio_writes : memory[d_addr[16:2]];
            delay_left <= d_rd && (d_addr == 32'h8001f080 || d_addr == 32'h8001f004) ? RESPONSE_DELAY : 2;
            if (|d_wr) begin
                if (d_addr == 32'h10000000) begin
                    check(d_wdata == 32'h42, "wrong-path MMIO write"); mmio_writes = mmio_writes + 1;
                end else begin
                    if (d_addr == 32'h8001f000) begin
                        check(d_wdata == 32'h13579bdf, "wrong-path SRAM store"); normal_stores = normal_stores + 1;
                    end
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (d_wr[lane]) memory[d_addr[16:2]][lane*8+:8] <= d_wdata[lane*8+:8];
                end
            end
        end
        if (decode_valid && wrong_index(decode_pc) >= 0) wrong_decoded[wrong_index(decode_pc)] = 1;
        if (d_pending && saved_addr == 32'h8001f080 && !d_ack) begin
            check(!(d_rd && d_addr == 32'h8001f084 && d_accept), "no younger load accepted while fault waits");
            suppressed_load_wait = suppressed_load_wait + 1;
        end
        check(!`CORE.u_issue.pipe1_valid_wb_w, "single retirement port");
        if (redirect) begin
            redirect_count = redirect_count + 1;
            if (redirect_pc == `RESUME_B_1) branch_redirects[0] = 1;
            if (redirect_pc == `RESUME_B_2) branch_redirects[1] = 1;
            if (redirect_pc == `RESUME_B_3) branch_redirects[2] = 1;
            $fwrite(event_file, "REDIRECT time=%0t pc=%08h squash=%0d\n", $time, redirect_pc, squash);
        end
        if (`CSR.csr_waddr_i == 12'h340 && `CSR.exception_i == 0) begin
            check(`CSR.csr_wdata_i == 32'h12345678, "wrong-path CSR write");
            csr_commit_cycles = csr_commit_cycles + 1;
        end
        if (csr_commit_cycles > 0 && mscratch !== 32'h12345678 && mscratch !== 0)
            check(0, "mscratch sentinel changed");
        if (wb_valid && (wb_exception == 0 || wb_exception == `EXCEPTION_ERET_M)) begin
            check(wrong_index(wb_pc) < 0, "wrong-path instruction retired");
            check(wb_pc != `FAULT_1 && wb_pc != `FAULT_2 && wb_pc != `FAULT_3 && wb_pc != `FAULT_4,
                "faulting load wrote destination");
            retired = retired + 1;
            if (wb_opcode[31:20] == 12'h340 && wb_opcode[6:0] == 7'h73 &&
                (wb_opcode[14:12] == 1 || wb_opcode[14:12] == 5 ||
                 ((wb_opcode[14:12] == 2 || wb_opcode[14:12] == 3 || wb_opcode[14:12] == 6 || wb_opcode[14:12] == 7) &&
                  wb_opcode[19:15] != 0))) csr_writes = csr_writes + 1;
            $fwrite(wb_file, "%08h %08h %02h %08h %02h\n", wb_pc, `CORE.u_issue.pipe0_opc_wb_w, wb_rd, wb_data, wb_exception);
            if (wb_pc == `RESUME_F_1 || wb_pc == `RESUME_F_2 || wb_pc == `RESUME_F_3 || wb_pc == `RESUME_F_4) begin
                check(wb_rd == 20 && wb_data == 32'h11223344, "correct-path reused destination data");
                if (wb_pc == `RESUME_F_1) recovered[0] = 1;
                if (wb_pc == `RESUME_F_2) recovered[1] = 1;
                if (wb_pc == `RESUME_F_3) recovered[2] = 1;
                if (wb_pc == `RESUME_F_4) recovered[3] = 1;
            end
        end
        if (`CSR.exception_i == `EXCEPTION_FAULT_LOAD) begin
            traps = traps + 1;
            #1;
            check(mcause == 5 && mtval == 32'h8001f080, "precise load fault CSRs");
            case (traps)
                1: check(mepc == `FAULT_1, "fault1 mepc");
                2: check(mepc == `FAULT_2, "fault2 mepc");
                3: check(mepc == `FAULT_3, "fault3 mepc");
                4: check(mepc == `FAULT_4, "fault4 mepc");
                default: check(0, "unexpected extra trap");
            endcase
            $fwrite(event_file, "TRAP time=%0t count=%0d mepc=%08h mtval=%08h\n", $time,traps,mepc,mtval);
        end
        if (`CSR.exception_i == `EXCEPTION_ERET_M) returns = returns + 1;
    end
    always @(negedge clk) if (rst_n && `CSR.csr_waddr_i == 12'h8b2 && `CSR.exception_i == 0) begin
        check(`CSR.csr_wdata_i == 0, "firmware exit");
        check(wrong_fetched == 7'h7f, "all seven forbidden instructions actually fetched");
        check(branch_redirects == 3'h7, "three real branch misprediction redirects");
        check(normal_stores == 1 && mmio_writes == 1 && csr_writes == 1, "exactly one legal store MMIO CSR effect");
        check(traps == 4 && returns == 4 && fault_returns == 4 && recovered == 4'hf, "four delayed faults and recoveries");
        check(memory[32'h1f000/4] == 32'h13579bdf && mscratch == 32'h12345678, "protected state intact");
        check(suppressed_load_wait >= RESPONSE_DELAY * 4, "outstanding-fault backpressure observed");
        $display("CPU_SQUASH_PASS cycles=%0d checks=%0d retired=%0d traps=%0d returns=%0d fetched=%h decoded=%h normal_stores=%0d mmio=%0d csr=%0d recoveries=%h delay=%0d wait=%0d redirects=%0d",
            cycles,checks,retired,traps,returns,wrong_fetched,wrong_decoded,normal_stores,mmio_writes,csr_writes,recovered,RESPONSE_DELAY,wait_cycles,redirect_count);
        $fclose(wb_file); $fclose(event_file);
        $finish;
    end
    `undef CORE
    `undef CSR
endmodule
