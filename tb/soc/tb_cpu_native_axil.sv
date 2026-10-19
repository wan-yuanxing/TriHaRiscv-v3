`timescale 1ns/1ps

// Port-only oracle: expected transactions are literal stimuli, and every native
// acceptance, AXI channel handshake and completion is counted independently.
module tb_cpu_native_axil;
    reg clk_i = 1'b0;
    always #5 clk_i = ~clk_i;
    reg rst_ni = 1'b0;
    reg [31:0] cpu_addr_i = 32'b0;
    reg [31:0] cpu_wdata_i = 32'b0;
    reg cpu_re_i = 1'b0;
    reg [3:0] cpu_wstrb_i = 4'b0;
    reg cpu_cacheable_i = 1'b0;
    reg [10:0] cpu_req_tag_i = 11'b0;
    reg cpu_invalidate_i = 1'b0;
    reg cpu_writeback_i = 1'b0;
    reg cpu_flush_i = 1'b0;
    wire [31:0] cpu_rdata_o;
    wire cpu_accept_o, cpu_ack_o, cpu_error_o;
    wire [10:0] cpu_resp_tag_o;
    wire [31:0] m_axi_awaddr_o, m_axi_wdata_o, m_axi_araddr_o;
    wire [2:0] m_axi_awprot_o, m_axi_arprot_o;
    wire [3:0] m_axi_wstrb_o;
    wire m_axi_awvalid_o, m_axi_wvalid_o, m_axi_arvalid_o;
    wire m_axi_bready_o, m_axi_rready_o;
    reg m_axi_awready_i = 1'b0;
    reg m_axi_wready_i = 1'b0;
    reg [1:0] m_axi_bresp_i = 2'b0;
    reg m_axi_bvalid_i = 1'b0;
    reg m_axi_arready_i = 1'b0;
    reg [31:0] m_axi_rdata_i = 32'b0;
    reg [1:0] m_axi_rresp_i = 2'b0;
    reg m_axi_rvalid_i = 1'b0;

    cpu_native_axil u_dut (.*);

    integer accepted = 0, completed = 0, aborted = 0;
    integer aw_total = 0, w_total = 0, ar_total = 0;
    integer b_total = 0, r_total = 0;
    integer cycle = 0, cases = 0, resets = 0;
    integer tag, strobe, i, phase;
    reg [2047:0] tags_seen = 2048'b0;
    reg [15:0] strobes_seen = 16'b0;
    reg outstanding = 1'b0;
    reg planned = 1'b0;
    reg expected_read, expected_local, expected_error;
    reg [31:0] expected_addr, expected_wdata, expected_rdata;
    reg [3:0] expected_wstrb;
    reg [10:0] expected_tag;
    integer aw_count = 0, w_count = 0, ar_count = 0;
    integer b_count = 0, r_count = 0;
    reg aw_stalled = 1'b0, w_stalled = 1'b0, ar_stalled = 1'b0;
    reg [31:0] last_rdata = 32'b0;
    reg [10:0] last_tag = 11'b0;
    reg previous_ack = 1'b0;
    reg native_request, sample_accept, sample_b, sample_r;

    // Check gates before updating handshake counts: a response is legal only
    // after the prerequisite handshake has occurred on an earlier edge.
    always @(posedge clk_i) begin
        cycle = cycle + 1;
        if (!rst_ni) begin
            if (outstanding) aborted = aborted + 1;
            outstanding = 1'b0;
            planned = 1'b0;
            aw_count = 0; w_count = 0; ar_count = 0;
            b_count = 0; r_count = 0;
            aw_stalled = 1'b0; w_stalled = 1'b0; ar_stalled = 1'b0;
            last_rdata = 32'b0; last_tag = 11'b0;
            previous_ack = 1'b0;
            #1;
            if ({cpu_accept_o, cpu_ack_o, cpu_error_o, m_axi_awvalid_o,
                 m_axi_wvalid_o, m_axi_arvalid_o, m_axi_bready_o,
                 m_axi_rready_o} !== 8'b0 || cpu_rdata_o !== 0 ||
                 cpu_resp_tag_o !== 0)
                $fatal(1, "reset outputs not cleared");
        end else begin
            native_request = (cpu_re_i !== 1'b0) || (cpu_wstrb_i !== 4'b0) ||
                             (cpu_invalidate_i !== 1'b0) ||
                             (cpu_writeback_i !== 1'b0) || (cpu_flush_i !== 1'b0);
            sample_accept = cpu_accept_o && native_request;
            sample_b = m_axi_bready_o && m_axi_bvalid_i;
            sample_r = m_axi_rready_o && m_axi_rvalid_i;
            if (cpu_ack_o && cpu_accept_o)
                $fatal(1, "accept overlaps response pulse");
            if (outstanding && cpu_accept_o)
                $fatal(1, "accept while outstanding");
            if (sample_accept) begin
                if (!planned || outstanding) $fatal(1, "unplanned native acceptance");
                outstanding = 1'b1;
                accepted = accepted + 1;
                aw_count = 0; w_count = 0; ar_count = 0;
                b_count = 0; r_count = 0;
            end
            if (m_axi_bready_o && (!outstanding || expected_read || expected_local ||
                                  aw_count != 1 || w_count != 1))
                $fatal(1, "BREADY before both AW and W accepted");
            if (m_axi_rready_o && (!outstanding || !expected_read || expected_local ||
                                  ar_count != 1))
                $fatal(1, "RREADY before AR accepted");
            if (aw_stalled && m_axi_awvalid_o !== 1'b1)
                $fatal(1, "AWVALID withdrawn while stalled");
            if (w_stalled && m_axi_wvalid_o !== 1'b1)
                $fatal(1, "WVALID withdrawn while stalled");
            if (ar_stalled && m_axi_arvalid_o !== 1'b1)
                $fatal(1, "ARVALID withdrawn while stalled");
            if (m_axi_awvalid_o) begin
                if (!outstanding || expected_read || expected_local || aw_count != 0 ||
                    m_axi_awaddr_o !== expected_addr || m_axi_awprot_o !== 3'b0)
                    $fatal(1, "unexpected/repeated AW or stale AW payload");
                if (m_axi_awready_i) begin aw_count = aw_count + 1; aw_total = aw_total + 1; end
            end
            if (m_axi_wvalid_o) begin
                if (!outstanding || expected_read || expected_local || w_count != 0 ||
                    m_axi_wdata_o !== expected_wdata || m_axi_wstrb_o !== expected_wstrb)
                    $fatal(1, "unexpected/repeated W or stale W payload");
                if (m_axi_wready_i) begin w_count = w_count + 1; w_total = w_total + 1; end
            end
            if (m_axi_arvalid_o) begin
                if (!outstanding || !expected_read || expected_local || ar_count != 0 ||
                    m_axi_araddr_o !== expected_addr || m_axi_arprot_o !== 3'b0)
                    $fatal(1, "unexpected/repeated AR or stale AR payload");
                if (m_axi_arready_i) begin ar_count = ar_count + 1; ar_total = ar_total + 1; end
            end
            if (sample_b) begin b_count = b_count + 1; b_total = b_total + 1; end
            if (sample_r) begin r_count = r_count + 1; r_total = r_total + 1; end
            aw_stalled = m_axi_awvalid_o && !m_axi_awready_i;
            w_stalled = m_axi_wvalid_o && !m_axi_wready_i;
            ar_stalled = m_axi_arvalid_o && !m_axi_arready_i;
            #1;
            if (cpu_ack_o === 1'b1) begin
                if (!outstanding || previous_ack || cpu_accept_o !== 1'b0)
                    $fatal(1, "unexpected/repeated ACK or response accept overlap");
                if (cpu_resp_tag_o !== expected_tag || cpu_error_o !== expected_error ||
                    cpu_rdata_o !== expected_rdata)
                    $fatal(1, "native completion mismatch tag=%h/%h err=%b/%b data=%h/%h",
                           cpu_resp_tag_o, expected_tag, cpu_error_o, expected_error,
                           cpu_rdata_o, expected_rdata);
                if (expected_local) begin
                    if (aw_count || w_count || ar_count || b_count || r_count)
                        $fatal(1, "local rejection reached AXI");
                end else if (expected_read) begin
                    if (ar_count != 1 || r_count != 1 || aw_count || w_count || b_count)
                        $fatal(1, "read completion without exactly one AR/R");
                end else begin
                    if (aw_count != 1 || w_count != 1 || b_count != 1 || ar_count || r_count)
                        $fatal(1, "write completion without exactly one AW/W/B");
                end
                completed = completed + 1;
                tags_seen[expected_tag] = 1'b1;
                if (!expected_read && !expected_local) strobes_seen[expected_wstrb] = 1'b1;
                outstanding = 1'b0;
                planned = 1'b0;
                last_rdata = cpu_rdata_o;
                last_tag = cpu_resp_tag_o;
            end else begin
                if (cpu_ack_o !== 1'b0 || cpu_error_o !== 1'b0)
                    $fatal(1, "unknown ACK or error without ACK");
                if (cpu_rdata_o !== last_rdata || cpu_resp_tag_o !== last_tag)
                    $fatal(1, "response payload changed between completions");
            end
            previous_ack = cpu_ack_o;
        end
    end

    task automatic idle_inputs;
        begin
            cpu_re_i = 0; cpu_wstrb_i = 0; cpu_cacheable_i = 0;
            cpu_invalidate_i = 0; cpu_writeback_i = 0; cpu_flush_i = 0;
            m_axi_awready_i = 0; m_axi_wready_i = 0; m_axi_arready_i = 0;
            m_axi_bvalid_i = 0; m_axi_rvalid_i = 0;
        end
    endtask

    task automatic wait_idle;
        integer count;
        begin
            count = 0;
            while (cpu_accept_o !== 1'b1) begin
                @(negedge clk_i);
                count = count + 1;
                if (count > 10) $fatal(1, "accept did not return after completion");
            end
        end
    endtask

    task automatic plan_request(input bit rd, input bit local_error,
                                input bit error, input [31:0] addr,
                                input [31:0] wd, input [3:0] strb,
                                input [10:0] req_tag, input [31:0] result);
        begin
            planned = 1;
            expected_read = rd; expected_local = local_error; expected_error = error;
            expected_addr = addr; expected_wdata = wd; expected_wstrb = strb;
            expected_tag = req_tag; expected_rdata = result;
        end
    endtask

    task automatic good_request(input bit rd, input [31:0] addr, input [31:0] wd,
                                input [3:0] strb, input [10:0] req_tag,
                                input integer aw_delay, input integer w_delay,
                                input integer ar_delay, input integer resp_delay,
                                input [1:0] resp, input bit early, input bit held,
                                input bit corrupt_read_data = 0,
                                input bit random_ready = 0);
        integer n, before_completed;
        reg [31:0] rd_result;
        reg [15:0] ready_sequence;
        begin
            @(negedge clk_i); wait_idle(); idle_inputs();
            rd_result = 32'h93d2_5ab7 ^ addr ^ {21'b0, req_tag};
            plan_request(rd, 0, resp !== 2'b00 || corrupt_read_data,
                         addr, wd, strb, req_tag,
                         rd && resp === 2'b00 && !corrupt_read_data ? rd_result : 32'b0);
            cpu_addr_i = addr; cpu_wdata_i = wd; cpu_req_tag_i = req_tag;
            cpu_re_i = rd; cpu_wstrb_i = rd ? 4'b0 : strb;
            before_completed = completed;
            ready_sequence = 16'hc3d2 ^ {5'b0, req_tag};
            @(posedge clk_i); #2;
            if (accepted != completed + aborted + 1)
                $fatal(1, "native request not accepted exactly once");
            n = 0;
            while (completed == before_completed) begin
                @(negedge clk_i);
                // Change every live native field after acceptance. With held=1
                // a different active request remains asserted until the ACK.
                cpu_addr_i = 32'hffff_fffd; cpu_wdata_i = ~wd;
                cpu_req_tag_i = ~req_tag; cpu_cacheable_i = 1;
                cpu_re_i = held; cpu_wstrb_i = held ? 4'hf : 4'b0;
                cpu_invalidate_i = held; cpu_writeback_i = held; cpu_flush_i = held;
                m_axi_awready_i = n >= aw_delay && (!random_ready || ready_sequence[0]);
                m_axi_wready_i = n >= w_delay && (!random_ready || ready_sequence[3]);
                m_axi_arready_i = n >= ar_delay && (!random_ready || ready_sequence[5]);
                m_axi_bresp_i = resp; m_axi_rresp_i = resp;
                m_axi_rdata_i = corrupt_read_data ? 32'h12x4_5678 : rd_result;
                m_axi_bvalid_i = early || n >= resp_delay;
                m_axi_rvalid_i = early || n >= resp_delay;
                #1;
                if (cpu_ack_o !== 0 || cpu_error_o !== 0)
                    $fatal(1, "native response changed before clock edge");
                @(posedge clk_i); #2;
                ready_sequence = {ready_sequence[14:0], ready_sequence[15] ^
                                  ready_sequence[13] ^ ready_sequence[12] ^ ready_sequence[10]};
                n = n + 1;
                if (n > 200) $fatal(1, "AXI/native progress timeout");
            end
            @(negedge clk_i); idle_inputs();
            cases = cases + 1;
        end
    endtask

    // Mutation index is a literal invalid case, not a copy of DUT validity logic.
    task automatic bad_request(input integer mutation);
        integer n, before_completed;
        reg [10:0] response_tag;
        begin
            @(negedge clk_i); wait_idle(); idle_inputs();
            cpu_addr_i = 32'h2001_0010; cpu_wdata_i = 32'h0123_4567;
            cpu_req_tag_i = 11'h65a; cpu_re_i = 1;
            response_tag = 11'h65a;
            case (mutation)
                0: cpu_addr_i = 32'h2000_fffc;
                1: cpu_addr_i = 32'h2002_0000;
                2: cpu_addr_i = 32'h2001_0001;
                3: cpu_addr_i = 32'h2001_0002;
                4: cpu_addr_i = 32'h2001_0003;
                5: cpu_cacheable_i = 1;
                6: cpu_wstrb_i = 4'h1;
                7: begin cpu_re_i = 0; cpu_invalidate_i = 1; end
                8: begin cpu_re_i = 0; cpu_writeback_i = 1; end
                9: begin cpu_re_i = 0; cpu_flush_i = 1; end
                10: cpu_addr_i[8] = 1'bx;
                11: cpu_req_tag_i[10] = 1'bx;
                12: cpu_cacheable_i = 1'bx;
                13: cpu_re_i = 1'bx;
                14: cpu_wstrb_i[0] = 1'bx;
                15: cpu_invalidate_i = 1'bx;
                16: cpu_writeback_i = 1'bx;
                17: cpu_flush_i = 1'bx;
                18: begin cpu_re_i = 0; cpu_wstrb_i = 4'h2; cpu_wdata_i[17] = 1'bx; end
                19: begin cpu_re_i = 0; cpu_wstrb_i = 4'h8; cpu_wdata_i[0] = 1'bx; end
                20: begin cpu_addr_i = 32'hffff_ffff; cpu_req_tag_i = 11'bx; end
                21: begin cpu_re_i = 0; cpu_wstrb_i = 4'b000x; end
                22: begin cpu_re_i = 0; cpu_invalidate_i = 1'bx; end
                23: begin cpu_re_i = 0; cpu_writeback_i = 1'bx; end
                24: begin cpu_re_i = 0; cpu_flush_i = 1'bx; end
                25: cpu_addr_i[31] = 1'bz;
                26: cpu_req_tag_i[0] = 1'bz;
                27: begin cpu_re_i = 0; cpu_wstrb_i = 4'h4; cpu_wdata_i[31] = 1'bz; end
                default: $fatal(1, "unknown invalid-case stimulus");
            endcase
            if (mutation == 11 || mutation == 20 || mutation == 26) response_tag = 0;
            plan_request(0, 1, 1, 0, 0, 0, response_tag, 0);
            before_completed = completed;
            @(posedge clk_i); #2;
            @(negedge clk_i); idle_inputs();
            n = 0;
            while (completed == before_completed) begin
                @(negedge clk_i); n = n + 1;
                if (n > 8) $fatal(1, "local error response timeout case=%0d", mutation);
            end
            cases = cases + 1;
        end
    endtask

    task automatic coordinated_reset;
        begin
            @(negedge clk_i);
            rst_ni = 0; idle_inputs();
            // Endpoint's pending response is reset with the adapter and CPU.
            cpu_addr_i = 0; cpu_wdata_i = 0; cpu_req_tag_i = 0;
            m_axi_bresp_i = 0; m_axi_rresp_i = 0; m_axi_rdata_i = 0;
            repeat (3) @(negedge clk_i);
            rst_ni = 1;
            resets = resets + 1;
            @(negedge clk_i);
        end
    endtask

    // Six externally observable incomplete phases, plus response-pulse reset.
    task automatic reset_phase(input integer which);
        integer n;
        bit rd;
        begin
            @(negedge clk_i); wait_idle(); idle_inputs();
            rd = which >= 3 && which <= 4;
            plan_request(rd, 0, 0, 32'h2001_0040, 32'hbadc_0123,
                         4'ha, 11'h7c3, rd ? 32'hca11_ab1e : 0);
            cpu_addr_i = 32'h2001_0040; cpu_wdata_i = 32'hbadc_0123;
            cpu_req_tag_i = 11'h7c3; cpu_re_i = rd;
            cpu_wstrb_i = rd ? 0 : 4'ha;
            @(posedge clk_i); #2;
            @(negedge clk_i); idle_inputs();
            // 0: neither AW/W; 1: only AW; 2: only W;
            // 3: AR stalled; 4: R wait; 5: B wait; 6: ACK active.
            m_axi_awready_i = which == 1 || which == 5 || which == 6;
            m_axi_wready_i = which == 2 || which == 5 || which == 6;
            m_axi_arready_i = which == 4;
            repeat (4) @(negedge clk_i);
            if (which == 1 && (aw_count != 1 || w_count)) $fatal(1, "reset AW-only setup");
            if (which == 2 && (w_count != 1 || aw_count)) $fatal(1, "reset W-only setup");
            if (which == 4 && ar_count != 1) $fatal(1, "reset R-wait setup");
            if (which == 5 && (aw_count != 1 || w_count != 1)) $fatal(1, "reset B-wait setup");
            if (which == 6) begin
                m_axi_bvalid_i = 1;
                @(posedge clk_i); #2;
                if (!cpu_ack_o) $fatal(1, "reset ACK setup");
            end
            coordinated_reset();
            good_request(1, 32'h2001_0000, 0, 0, 11'h127, 0, 0, 1, 4, 0, 0, 0);
            good_request(0, 32'h2001_fffc, 32'h1937_abcd, 4'hb,
                         11'h6f2, 2, 0, 0, 7, 0, 0, 0);
        end
    endtask

    initial begin
        #2000000;
        $fatal(1, "global timeout");
    end

    initial begin
        coordinated_reset();
        // Unknown idle payload is harmless; it cannot create a transaction.
        cpu_addr_i = 32'bx; cpu_wdata_i = 32'bx; cpu_req_tag_i = 11'bx;
        cpu_cacheable_i = 1'bx;
        repeat (5) @(negedge clk_i);
        if (accepted || completed || !cpu_accept_o) $fatal(1, "idle payload created request");
        cpu_cacheable_i = 0;

        // Exact window endpoints and unused read WDATA unknowns.
        good_request(1, 32'h2001_0000, 32'bx, 0, 11'h400, 0, 0, 17, 29, 0, 1, 1);
        good_request(1, 32'h2001_fffc, 32'bx, 0, 11'h7ff, 0, 0, 43, 79, 0, 0, 0);
        good_request(0, 32'h2001_0000, 32'h1234_5678, 4'h5, 11'h501, 0, 39, 0, 65, 0, 1, 1);
        good_request(0, 32'h2001_fffc, 32'h8765_4321, 4'ha, 11'h602, 47, 0, 0, 71, 0, 1, 1);

        // Each tag is a literal native request and must survive the port path.
        for (tag = 0; tag < 2048; tag = tag + 1) begin
            good_request(tag[0], 32'h2001_0100 + 4 * (tag % 64),
                         32'hbeef_0000 ^ tag, (tag % 15) + 1, tag,
                         (tag * 7 + 3) % 6, (tag * 11 + 1) % 7,
                         (tag * 13 + 2) % 5, 10 + tag % 5, 0,
                         tag % 3 == 0, tag % 31 == 0, 0, 1);
        end
        for (strobe = 1; strobe < 16; strobe = strobe + 1)
            good_request(0, 32'h2001_0200 + strobe * 4,
                         32'hf1e2_d3c4 ^ (strobe * 32'h0102_0304), strobe,
                         11'h700 + strobe, strobe % 4, (15 - strobe) % 4,
                         0, 9, 0, 0, 0);
        // Every AXI response code, including an unknown bit, read and write.
        for (i = 0; i < 4; i = i + 1) begin
            good_request(1, 32'h2001_0030, 0, 0, 11'h315 + i, 0, 0, 2, 6, i, 0, 0);
            good_request(0, 32'h2001_0034, 32'hba98_7654, 4'h9,
                         11'h715 + i, 1, 3, 0, 7, i, 0, 0);
        end
        good_request(1, 32'h2001_0038, 0, 0, 11'h334, 0, 0, 2, 6, 2'b0x, 0, 0);
        good_request(0, 32'h2001_003c, 32'h1212_abab, 4'hc,
                     11'h734, 3, 1, 0, 7, 2'bz0, 0, 0);
        good_request(1, 32'h2001_0038, 0, 0, 11'h335, 0, 0, 2, 6, 0, 0, 0, 1);
        for (i = 0; i < 28; i = i + 1) bad_request(i);
        for (phase = 0; phase < 7; phase = phase + 1) reset_phase(phase);

        @(negedge clk_i); wait_idle(); idle_inputs();
        repeat (6) @(negedge clk_i);
        if (tags_seen !== {2048{1'b1}} || strobes_seen[15:1] !== 15'h7fff)
            $fatal(1, "tag/strobe coverage incomplete");
        if (accepted != completed + aborted || outstanding || planned || aborted != 6)
            $fatal(1, "final native accounting accepted=%0d completed=%0d aborted=%0d",
                   accepted, completed, aborted);
        $display("CPU_NATIVE_AXIL_PASS cases=%0d accepted=%0d completed=%0d aborted=%0d tags=2048 strobes=15 resets=%0d AW=%0d W=%0d AR=%0d B=%0d R=%0d",
                 cases, accepted, completed, aborted, resets,
                 aw_total, w_total, ar_total, b_total, r_total);
        $finish;
    end
endmodule
