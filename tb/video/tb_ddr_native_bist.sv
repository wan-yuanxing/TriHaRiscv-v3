`timescale 1ns/1ps
module tb_ddr_native_bist;
    parameter integer TEST_WINDOW_BEATS = 64;
    parameter integer TEST_BURST_BEATS = 16;
    reg clk = 0;
    always #4 clk = !clk;
    reg reset_n = 0, init_done = 0, delayed = 0;
    integer fault_mode = 0;
    reg [27:0] address_mask = 28'hfffffff;
    wire busy, done, error;
    wire [7:0] phase, error_code;
    wire [31:0] compared_beats;
    wire [27:0] first_error_addr;
    wire [255:0] first_error_xor;
    wire [27:0] axi_awaddr, axi_araddr;
    wire [3:0] axi_awlen, axi_arlen, axi_awuser_id, axi_aruser_id;
    wire axi_awuser_ap, axi_aruser_ap, axi_awvalid, axi_arvalid, axi_awready, axi_arready;
    wire [255:0] axi_wdata, axi_rdata;
    wire [31:0] axi_wstrb;
    wire axi_wready, axi_wusero_last, axi_rvalid, axi_rlast;
    wire [3:0] axi_wusero_id, axi_rid;
    integer write_beats, read_beats, earliest_beats, masked_beats, aw_commands, ar_commands, write_gaps;
    integer tests = 0, cycles, n, alias_bit, monitor_index;
    reg [255:0] held_wdata;
    reg [31:0] held_wstrb;
    reg held_aw, held_ar, held_w;
    reg [36:0] held_aw_payload, held_ar_payload;
    reg [255:0] snapshot_xor;
    reg [27:0] snapshot_addr;
    reg [7:0] snapshot_code;
    reg [31:0] phase_counts [0:255];
    reg [31:0] phase_write_counts [0:255];
    integer sent_writes, sent_reads;
    reg seen_high, seen_top128, seen_max, seen_zero, seen_full_burst, seen_one_beat;
    reg seen_page_split;
    reg [31:0] oracle_mask, observed_word;
    reg [255:0] low_prng_first;
    integer lane_number;
    ddr_native_bist #(.TIMEOUT_CYCLES(40), .WINDOW_BEATS(TEST_WINDOW_BEATS),
                      .BURST_BEATS(TEST_BURST_BEATS)) dut (.*);
    ddr_native_model model (.*);

    task automatic check(input bit condition, input string message);
        if (condition !== 1'b1) $fatal(1, "FAIL %s phase=%h code=%h compares=%d", message, phase, error_code, compared_beats);
    endtask
    task automatic restart(input integer selected_fault, input bit use_delays, input [27:0] selected_mask);
        begin
            @(negedge clk); reset_n = 0; init_done = 0;
            fault_mode = selected_fault; delayed = use_delays; address_mask = selected_mask;
            repeat (4) @(negedge clk);
            reset_n = 1;
            repeat (5) @(negedge clk);
            check(!busy && !done && !error && !axi_awvalid && !axi_arvalid, "quiet before init");
            init_done = 1;
        end
    endtask
    task automatic await_result;
        begin
            cycles = 0;
            while (!done && !error && cycles < 200000) begin
                @(negedge clk); cycles = cycles + 1;
            end
            check(done || error, "bounded completion");
        end
    endtask
    task automatic expect_fault(input integer selected_fault, input [7:0] code, input string label_text);
        begin
            restart(selected_fault, 1, 28'hfffffff);
            await_result;
            check(error && !done && !busy && error_code == code, label_text);
            snapshot_xor = first_error_xor; snapshot_addr = first_error_addr; snapshot_code = error_code;
            repeat (5) @(negedge clk);
            check(error && !done && error_code == snapshot_code && first_error_addr == snapshot_addr && first_error_xor === snapshot_xor,
                  "sticky first failure");
            tests = tests + 1;
            $display("PASS fault %s code=%h address=%h", label_text, error_code, first_error_addr);
        end
    endtask

    always @(posedge clk) begin
        if (!reset_n) begin
            held_aw = 0; held_ar = 0; held_w = 0;
            sent_writes = 0; sent_reads = 0;
            seen_high = 0; seen_top128 = 0; seen_max = 0; seen_zero = 0;
            seen_full_burst = 0; seen_one_beat = 0; seen_page_split = 0; low_prng_first = 0;
            for (monitor_index = 0; monitor_index < 256; monitor_index = monitor_index + 1) begin
                phase_counts[monitor_index] = 0;
                phase_write_counts[monitor_index] = 0;
            end
        end else if (init_done && !error) begin
            if (held_aw) check(axi_awvalid && {axi_awaddr,axi_awlen,axi_awuser_id,axi_awuser_ap} == held_aw_payload, "AW stable during stall");
            if (held_ar) check(axi_arvalid && {axi_araddr,axi_arlen,axi_aruser_id,axi_aruser_ap} == held_ar_payload, "AR stable during stall");
            if (held_w) check(axi_wdata == held_wdata && axi_wstrb == held_wstrb, "write beat stable through gaps");
            held_aw = axi_awvalid && !axi_awready;
            held_ar = axi_arvalid && !axi_arready;
            held_aw_payload = {axi_awaddr,axi_awlen,axi_awuser_id,axi_awuser_ap};
            held_ar_payload = {axi_araddr,axi_arlen,axi_aruser_id,axi_aruser_ap};
            held_w = (dut.state == 2 || dut.state == 3) && !axi_wready;
            held_wdata = axi_wdata; held_wstrb = axi_wstrb;
            if (axi_awvalid && axi_awready) begin
                if (phase == 1) sent_writes = sent_writes + 1;
                if (axi_awaddr == 0) seen_zero = 1;
                if (axi_awaddr == 28'hffffff8) seen_max = 1;
                if (axi_awaddr == 28'h1fffff8) seen_top128 = 1;
                if (axi_awaddr[27]) seen_high = 1;
                if (axi_awlen == 15) seen_full_burst = 1;
                if (axi_awlen == 0) seen_one_beat = 1;
                if (phase != 1 && axi_awlen + 1 < TEST_BURST_BEATS &&
                    axi_awaddr[9:0] + (axi_awlen+1)*8 == 1024) seen_page_split = 1;
            end
            if (axi_arvalid && axi_arready && phase == 1) begin
                check(sent_writes == 29, "all sentinel addresses written before any verification");
                sent_reads = sent_reads + 1;
            end
            if (axi_rvalid) phase_counts[phase] = phase_counts[phase] + 1;
            if (axi_wready) begin
                oracle_mask = 32'hffffffff;
                if (phase >= 8'h20 && phase_write_counts[phase] >= 2*TEST_WINDOW_BEATS) begin
                    case (phase)
                        8'h20: oracle_mask = 0;
                        8'h21: oracle_mask = 32'hffffffff;
                        8'h22: oracle_mask = 32'haaaaaaaa;
                        8'h23: oracle_mask = 32'h55555555;
                        8'h24: oracle_mask = 32'h0000ffff;
                        8'h25: oracle_mask = 32'hffff0000;
                        default: oracle_mask = 32'h1 << (phase-8'h26);
                    endcase
                end
                check(axi_wstrb === oracle_mask, "independent byte mask contract");
                if (phase == 8'h11) check(axi_wdata === 256'h0, "all-zero data pattern");
                if (phase == 8'h12) check(axi_wdata === {256{1'b1}}, "all-one data pattern");
                if (phase == 8'h13 || phase == 8'h14)
                    check(axi_wdata === {8{((phase_write_counts[phase] % TEST_WINDOW_BEATS) % 2) ^
                          (phase == 8'h14) ^ ((phase_write_counts[phase] >= TEST_WINDOW_BEATS) && (TEST_WINDOW_BEATS % 2)) ?
                          32'haa55aa55 : 32'h55aa55aa}}, "alternating data pattern and inverse");
                if (phase == 8'h15 || phase == 8'h16)
                    for (lane_number = 0; lane_number < 8; lane_number = lane_number + 1) begin
                        observed_word = axi_wdata[lane_number*32 +: 32];
                        if (phase == 8'h16) observed_word = ~observed_word;
                        check(observed_word != 0 && (observed_word & (observed_word-1)) == 0, "walking one/zero per lane");
                    end
                if (phase == 8'h17 && phase_write_counts[phase] == 0) low_prng_first = axi_wdata;
                if (phase == 8'h17 && phase_write_counts[phase] == TEST_WINDOW_BEATS)
                    check(axi_wdata != low_prng_first, "PRNG distinguishes low and high physical windows");
                phase_write_counts[phase] = phase_write_counts[phase] + 1;
            end
        end
    end

    initial begin
        restart(0, 0, 28'hfffffff);
        await_result;
        check(done && !busy && !error, "clean earliest-ready completion");
        check(compared_beats == 29 + 46*2*TEST_WINDOW_BEATS, "exact compared beat coverage");
        check(sent_reads == 29 && seen_high && seen_top128 && seen_max && seen_zero && seen_one_beat, "physical sentinel coverage");
        check(earliest_beats == aw_commands && masked_beats > 0, "every write starts at AW acceptance and masks exercised");
        for (n = 8'h10; n <= 8'h17; n = n + 1)
            check(phase_counts[n] == 2*TEST_WINDOW_BEATS, "every full pattern compares both complete windows");
        for (n = 8'h20; n <= 8'h45; n = n + 1)
            check(phase_counts[n] == 2*TEST_WINDOW_BEATS, "every mask compares both complete windows");
        if (TEST_BURST_BEATS == 16 && TEST_WINDOW_BEATS >= 16) check(seen_full_burst, "LEN15 exercised");
        if (TEST_WINDOW_BEATS > 128 &&
            ((128 % TEST_BURST_BEATS != 0) || ((TEST_WINDOW_BEATS % 128) % TEST_BURST_BEATS != 0)))
            check(seen_page_split, "native page boundary splits burst");
        repeat (10) @(negedge clk);
        check(done && !busy && !axi_awvalid && !axi_arvalid, "pass stays latched and traffic stops");
        tests = tests + 1;
        $display("PASS clean beats=%0d writes=%0d AW=%0d AR=%0d", compared_beats, write_beats, aw_commands, ar_commands);
        // Calibration loss after PASS invalidates PASS and cannot restart locally.
        init_done = 0;
        repeat (2) @(negedge clk);
        check(error && !done && error_code == 1, "init loss clears completed PASS");
        init_done = 1; repeat (5) @(negedge clk);
        check(error && !busy && !done, "init rise does not restart interrupted controller");
        tests = tests + 1;
        restart(0, 1, 28'hfffffff); await_result;
        check(done && !error && (write_gaps > 0 || TEST_BURST_BEATS == 1), "delayed commands and gapped data complete after coordinated reset");
        tests = tests + 1;
        $display("PASS delayed compares=%0d write_gaps=%0d", compared_beats, write_gaps);
        restart(21, 1, 28'hfffffff); await_result;
        check(done && !error && earliest_beats == 0, "AW accepted before first WREADY and later recovers");
        tests = tests + 1;
        expect_fault(1, 8'h06, "corrupted read data");
        check(snapshot_xor == 1, "data mismatch records exact XOR");
        expect_fault(2, 8'h02, "wrong WID");
        expect_fault(3, 8'h03, "wrong WLAST");
        expect_fault(4, 8'h04, "wrong RID");
        expect_fault(5, 8'h05, "wrong RLAST");
        expect_fault(6, 8'h10, "AW timeout");
        expect_fault(7, 8'h11, "W timeout");
        expect_fault(8, 8'h12, "AR timeout");
        expect_fault(9, 8'h13, "R timeout");
        expect_fault(10, 8'h13, "dropped final R beat");
        expect_fault(11, 8'h07, "extra read beat");
        expect_fault(12, 8'h07, "unsolicited read beat");
        expect_fault(22, 8'h07, "unsolicited read on init startup edge");
        expect_fault(23, 8'h06, "unknown read data cannot pass comparison");
        expect_fault(24, 8'h04, "unknown RID cannot pass comparison");
        expect_fault(25, 8'h05, "unknown RLAST cannot pass comparison");
        expect_fault(26, 8'h02, "unknown WID cannot pass comparison");
        expect_fault(27, 8'h03, "unknown WLAST cannot pass comparison");
        expect_fault(13, 8'h06, "disabled bytes overwritten");
        expect_fault(14, 8'h06, "uppermost data bit corrupted");
        check(snapshot_xor == (256'h1 << 255), "all 256 data bits participate in XOR");
        if (TEST_BURST_BEATS >= 3 && TEST_WINDOW_BEATS >= 3) begin
            expect_fault(15, 8'h03, "early WLAST within burst");
            expect_fault(16, 8'h05, "early RLAST within burst");
        end
        if (TEST_BURST_BEATS >= 2 && TEST_WINDOW_BEATS >= 2) begin
            expect_fault(17, 8'h02, "wrong final burst WID");
            expect_fault(18, 8'h04, "wrong final burst RID");
            expect_fault(19, 8'h13, "dropped final burst R beat");
            expect_fault(20, 8'h07, "extra final burst R beat");
        end
        for (alias_bit = 3; alias_bit < 28; alias_bit = alias_bit + 1) begin
            restart(0, 1, 28'hfffffff ^ (28'h1 << alias_bit)); await_result;
            check(error && !done && error_code == 6 && first_error_xor != 0,
                  $sformatf("native word address bit%0d alias detected", alias_bit));
            tests = tests + 1;
        end
        $display("PASS aliases native word address bits 3..27 (physical byte bits 5..29)");
        for (n = 0; n < 2; n = n + 1) begin
            restart(21, 1, 28'hfffffff);
            if (n == 0) wait (dut.state == 3);
            else wait (dut.state == 5);
            @(negedge clk); init_done = 0;
            repeat (2) @(negedge clk);
            check(error && !done && !busy && error_code == 1 && !axi_awvalid && !axi_arvalid, "active init loss aborts");
            init_done = 1; repeat (5) @(negedge clk);
            check(error && !busy, "active init loss requires coordinated reset");
            tests = tests + 1;
        end
        for (n = 0; n < 2; n = n + 1) begin
            restart(21, 1, 28'hfffffff);
            if (n == 0) wait (dut.state == 3);
            else wait (dut.state == 5);
            @(negedge clk); reset_n = 0; init_done = 0;
            repeat (2) @(negedge clk);
            check(!done && !busy && !error && compared_beats == 0 && first_error_xor == 0 &&
                  first_error_addr == 0 && !axi_awvalid && !axi_arvalid, "coordinated mid-transaction reset clears all state");
            tests = tests + 1;
        end
        restart(0, 0, 28'hfffffff); await_result;
        check(done && !error, "final reset recovers cleanly");
        tests = tests + 1;
        $display("PASS tb_ddr_native_bist tests=%0d window=%0d burst=%0d", tests, TEST_WINDOW_BEATS, TEST_BURST_BEATS);
        $finish;
    end
    initial begin
        #20000000; $fatal(1, "FAIL overall simulation deadline");
    end
endmodule
