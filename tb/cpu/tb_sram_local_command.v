`timescale 1ns/1ps

// Exercise the real SRAM port of the complete memory fabric. The parent is
// frozen by the runner; the wire oracle follows accepted-request semantics.
module tb_sram_local_command;
    reg clk = 0;
    reg rst_n = 0;
    reg [31:0] addr = 32'h10000;
    reg rd = 0;
    reg [3:0] wr = 0;
    reg invalidate = 0, writeback = 0, flush = 0;
    reg busy = 0;
    integer checks = 0;
    integer pattern, low, mode, bank;
    reg expected_ce;
    reg expected_inst_ce;
    reg [7:0] expected_we;

    triha_soc_memory u_candidate (
        .clk_i(clk), .rst_ni(rst_n), .inst_req_i(1'b1), .inst_addr_i(32'h10000),
        .data_addr_i(addr), .data_wdata_i(32'h12345678), .data_re_i(rd),
        .data_wstrb_i(wr), .data_req_tag_i(11'b0),
        .data_invalidate_i(invalidate), .data_writeback_i(writeback), .data_flush_i(flush)
    );
    triha_soc_memory_parent u_parent (
        .clk_i(clk), .rst_ni(rst_n), .inst_req_i(1'b1), .inst_addr_i(32'h10000),
        .data_addr_i(addr), .data_wdata_i(32'h12345678), .data_re_i(rd),
        .data_wstrb_i(wr), .data_req_tag_i(11'b0),
        .data_invalidate_i(invalidate), .data_writeback_i(writeback), .data_flush_i(flush)
    );

    function four;
        input integer value;
        begin
            case (value & 3)
                0: four = 0;
                1: four = 1;
                2: four = 1'bx;
                3: four = 1'bz;
            endcase
        end
    endfunction

    task check_port;
        begin
            #1;
            expected_ce = (rst_n && !busy) &&
                (rd || (|wr) || invalidate || writeback || flush) &&
                (addr >= 32'h10000 && addr < 32'h18000) &&
                !((addr[1:0] != 0) || (rd && (|wr)) || invalidate || writeback || flush);
            if (u_candidate.u_sram.data_en_i !== expected_ce) begin
                $display("SRAM_COMMAND_FAIL ce pattern=%0d addr=%h actual=%b expected=%b", pattern,
                    addr, u_candidate.u_sram.data_en_i, expected_ce);
                $finish;
            end
            expected_inst_ce = rst_n &&
                !(expected_ce && (|wr) && (addr[14:3] == 12'b0));
            expected_we = (expected_ce && (|wr)) ?
                (addr[2] ? {wr, 4'b0} : {4'b0, wr}) : 8'b0;
            if (u_candidate.u_sram.inst_en_i !== expected_inst_ce ||
                u_candidate.u_sram.data_wstrb_i !== expected_we) begin
                $display("SRAM_COMMAND_FAIL inst/write pattern=%0d addr=%h ice=%b expected=%b we=%h expected=%h",
                    pattern, addr, u_candidate.u_sram.inst_en_i, expected_inst_ce,
                    u_candidate.u_sram.data_wstrb_i, expected_we);
                $finish;
            end
            if (!$test$plusargs("POISON_GENERIC") && !$test$plusargs("FAULT_CE") &&
                u_candidate.u_sram.data_en_i !== u_parent.u_sram.data_en_i) begin
                $display("SRAM_COMMAND_FAIL parent ce");
                $finish;
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        force u_candidate.uart_pending_q = busy;
        force u_parent.uart_pending_q = busy;
        force u_candidate.inst_pending_q = 0;
        force u_parent.inst_pending_q = 0;
        if ($test$plusargs("POISON_GENERIC")) force u_candidate.d_fire = 0;
        if ($test$plusargs("FAULT_CE")) force u_candidate.u_sram.data_en_i = 0;
        rst_n = 1; rd = 1;
        check_port;
        // Keep generic request poison active across actual writes. A candidate
        // changing only the data CE must fail the instruction collision/WE test.
        rd = 0; wr = 4'b1010; addr = 32'h10000;
        check_port;
        wr = 4'b0101; addr = 32'h10004;
        check_port;
        wr = 4'b1111; addr = 32'h10008;
        check_port;
        if ($test$plusargs("POISON_GENERIC")) release u_candidate.d_fire;
        // Exhaust all four-state request/maintenance combinations. Other
        // iterations vary alignment, target decode and acceptance separately.
        for (pattern = 0; pattern < 1024; pattern = pattern + 1) begin
            rd = four(pattern);
            wr = {3'b0, four(pattern >> 2)};
            invalidate = four(pattern >> 4);
            writeback = four(pattern >> 6);
            flush = four(pattern >> 8);
            for (low = 0; low < 16; low = low + 1) begin
                addr = 32'h10000;
                addr[0] = four(low); addr[1] = four(low >> 2);
                check_port;
            end
            for (mode = 0; mode < 16; mode = mode + 1) begin
                rst_n = four(mode); busy = four(mode >> 2);
                addr = 32'h10000;
                check_port;
            end
            rst_n = 1; busy = 0;
            for (bank = 0; bank < 6; bank = bank + 1) begin
                case (bank)
                    0: addr = 0;
                    1: addr = 32'h18000;
                    2: addr = 32'h20000000;
                    3: addr = 32'h0001x000;
                    4: addr = 32'h000z0000;
                    5: addr = 32'h17ffc;
                endcase
                check_port;
            end
        end
        $display("SRAM_COMMAND_PASS checks=%0d", checks);
        $finish;
    end
endmodule
