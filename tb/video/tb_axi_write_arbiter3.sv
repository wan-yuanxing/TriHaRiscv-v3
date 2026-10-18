`timescale 1ns/1ps

module tb_axi_write_arbiter3;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg reset_n = 1'b0;
    wire [11:0] s_awid;
    wire [95:0] s_awaddr;
    wire [23:0] s_awlen;
    wire [8:0] s_awsize;
    wire [5:0] s_awburst;
    wire [2:0] s_awvalid, s_awready;
    wire [383:0] s_wdata;
    wire [47:0] s_wstrb;
    wire [2:0] s_wlast, s_wvalid, s_wready, s_bvalid;
    reg [2:0] s_bready = 3'b111;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid;
    reg awready = 1'b0;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    wire wlast, wvalid;
    reg wready = 1'b0;
    reg [3:0] bid = 4'b0;
    reg [1:0] bresp = 2'b00;
    reg bvalid = 1'b0;
    wire bready, fault, owner_active, idle;
    wire [7:0] fault_code;
    wire [1:0] owner;

    axi_write_arbiter3 dut (.*);

    // Real master state: AW and every W beat stay VALID, with stable payload,
    // until their own handshake; another request needs its previous B retirement.
    reg m_active [0:2];
    reg m_awpending [0:2];
    reg m_wenable [0:2];
    reg [3:0] m_id [0:2];
    reg [31:0] m_addr [0:2];
    integer m_beats [0:2];
    integer m_beat [0:2];
    integer completed [0:2];
    integer serial = 0;
    integer k;
    genvar g;
    generate for (g = 0; g < 3; g = g + 1) begin : masters
        assign s_awid[g*4 +: 4] = m_id[g];
        assign s_awaddr[g*32 +: 32] = m_addr[g];
        assign s_awlen[g*8 +: 8] = m_beats[g] - 1;
        assign s_awsize[g*3 +: 3] = 3'd4;
        assign s_awburst[g*2 +: 2] = 2'b01;
        assign s_awvalid[g] = m_awpending[g];
        assign s_wdata[g*128 +: 128] = {m_addr[g], m_id[g], 28'h1234567,
                                                 32'h55aacc33, m_beat[g]};
        assign s_wstrb[g*16 +: 16] = 16'hffff ^ (16'h0001 << g);
        assign s_wvalid[g] = m_active[g] && m_wenable[g] &&
                            (m_beat[g] < m_beats[g]);
        assign s_wlast[g] = (m_beat[g] == m_beats[g] - 1);
    end endgenerate

    always @(posedge clk) begin
        if (!reset_n) begin
            for (k = 0; k < 3; k = k + 1) begin
                m_active[k] <= 1'b0;
                m_awpending[k] <= 1'b0;
                m_wenable[k] <= 1'b1;
                m_id[k] <= 4'b0;
                m_addr[k] <= 32'b0;
                m_beats[k] <= 1;
                m_beat[k] <= 0;
                completed[k] <= 0;
            end
        end else begin
            for (k = 0; k < 3; k = k + 1) begin
                if (s_awvalid[k] && s_awready[k]) m_awpending[k] <= 1'b0;
                if (s_wvalid[k] && s_wready[k]) m_beat[k] <= m_beat[k] + 1;
                if (s_bvalid[k] && s_bready[k]) begin
                    if (!m_active[k] || m_awpending[k] || m_beat[k] != m_beats[k])
                        $fatal(1, "master %0d received premature/unsolicited B", k);
                    m_active[k] <= 1'b0;
                    completed[k] <= completed[k] + 1;
                end
            end
        end
    end

    integer expected_owner = -1;
    reg saw_aw = 1'b0, saw_last = 1'b0;
    integer selections = 0;
    integer selection_order [0:255];
    integer retirements = 0;
    reg previous_aw_stall = 1'b0, previous_w_stall = 1'b0;
    reg previous_waiting_selection = 1'b0;
    reg [48:0] previous_aw;
    reg [144:0] previous_w;
    reg [2:0] expected_awready, expected_wready, expected_bvalid;
    integer n;
    // Independent channel/ownership scoreboard. It never reads DUT state.
    always @(posedge clk) begin
        if (!reset_n) begin
            expected_owner = -1;
            saw_aw = 1'b0;
            saw_last = 1'b0;
            selections = 0;
            retirements = 0;
            previous_aw_stall = 1'b0;
            previous_w_stall = 1'b0;
            previous_waiting_selection = 1'b0;
        end else begin
            if (previous_waiting_selection && !owner_active)
                $fatal(1, "pending AW was not granted after the selection edge");
            previous_waiting_selection = !owner_active && (|s_awvalid);
            if (idle !== (!owner_active && !(|s_awvalid) && !bvalid))
                $fatal(1, "idle omitted an owner, waiting AW, or BVALID");
            if (previous_aw_stall && (!awvalid ||
                {awid, awaddr, awlen, awsize, awburst} !== previous_aw))
                $fatal(1, "AW changed while stalled");
            if (previous_w_stall && (!wvalid || {wdata, wstrb, wlast} !== previous_w))
                $fatal(1, "W changed while stalled");
            previous_aw_stall = awvalid && !awready;
            previous_w_stall = wvalid && !wready;
            previous_aw = {awid, awaddr, awlen, awsize, awburst};
            previous_w = {wdata, wstrb, wlast};
            expected_awready = 3'b000;
            expected_wready = 3'b000;
            expected_bvalid = 3'b000;
            if (!owner_active) begin
                if (expected_owner != -1) $fatal(1, "owner dropped before B retirement");
                if (awvalid || wvalid) $fatal(1, "VALID exposed before registering owner");
                if (bready !== 1'b1) $fatal(1, "stray B cannot drain");
            end else begin
                if (owner > 2) $fatal(1, "illegal owner");
                if (expected_owner == -1) begin
                    expected_owner = owner;
                    saw_aw = 1'b0;
                    saw_last = 1'b0;
                    if (!s_awvalid[owner]) $fatal(1, "selected master without pending AW");
                    selection_order[selections] = owner;
                    selections = selections + 1;
                end
                if (owner !== expected_owner[1:0]) $fatal(1, "owner changed before B");
                expected_awready[owner] = awready && !saw_aw;
                expected_wready[owner] = wready && !saw_last;
                expected_bvalid[owner] = bvalid && saw_aw && saw_last;
                if (bready !== (s_bready[owner] && saw_aw && saw_last))
                    $fatal(1, "BREADY outside owner's legal B phase");
                if (awvalid !== (s_awvalid[owner] && !saw_aw))
                    $fatal(1, "AWVALID was lost or repeated");
                if (wvalid !== (s_wvalid[owner] && !saw_last))
                    $fatal(1, "WVALID was lost or repeated");
                if (awvalid && {awid, awaddr, awlen, awsize, awburst} !==
                    {m_id[owner], m_addr[owner], s_awlen[owner*8 +: 8], 3'd4, 2'b01})
                    $fatal(1, "AW payload did not come from owner");
                if (wvalid && {wdata, wstrb, wlast} !==
                    {s_wdata[owner*128 +: 128], s_wstrb[owner*16 +: 16], s_wlast[owner]})
                    $fatal(1, "W payload did not come from owner");
                if (bvalid && bready) begin
                    if (!saw_aw || !saw_last) $fatal(1, "early B retired owner");
                    expected_owner = -1;
                    retirements = retirements + 1;
                end
                if (awvalid && awready) saw_aw = 1'b1;
                if (wvalid && wready && wlast) saw_last = 1'b1;
            end
            if (s_awready !== expected_awready || s_wready !== expected_wready ||
                s_bvalid !== expected_bvalid)
                $fatal(1, "READY/BVALID routed to wrong master");
        end
    end

    task tick(input integer cycles);
        begin repeat (cycles) begin @(posedge clk); #1; end end
    endtask

    task reset_dut;
        begin
            @(negedge clk);
            reset_n = 1'b0;
            awready = 1'b0;
            wready = 1'b0;
            bvalid = 1'b0;
            bid = 4'b0;
            bresp = 2'b00;
            s_bready = 3'b111;
            tick(3);
            if (owner_active || awvalid || wvalid || bready || |s_bvalid || fault || fault_code)
                $fatal(1, "coordinated reset did not clear port/fault");
            @(negedge clk);
            reset_n = 1'b1;
            tick(1);
            if (!idle) $fatal(1, "empty reset port is not idle");
        end
    endtask

    // Call only at a falling edge. Payload changes only when no request is live.
    task queue_master(input integer master, input integer beats);
        begin
            if (m_active[master]) $fatal(1, "TB replaced an outstanding transaction");
            serial = serial + 1;
            m_active[master] = 1'b1;
            m_awpending[master] = 1'b1;
            m_id[master] = (serial + master) & 15;
            m_addr[master] = 32'h82000000 + master * 32'h00200000 + serial * 64;
            m_beats[master] = beats;
            m_beat[master] = 0;
            m_wenable[master] = 1'b1;
        end
    endtask

    task wait_owner(input integer master);
        integer count;
        begin
            count = 0;
            while (!owner_active) begin
                tick(1);
                count = count + 1;
                if (count > 80) $fatal(1, "TIMEOUT waiting for owner %0d", master);
            end
            if (owner !== master[1:0])
                $fatal(1, "round-robin expected owner %0d, got %0d", master, owner);
        end
    endtask

    task wait_data(input integer master);
        integer count;
        begin
            wait_owner(master);
            count = 0;
            while (m_awpending[master] || m_beat[master] != m_beats[master]) begin
                tick(1);
                count = count + 1;
                if (count > 80) $fatal(1, "TIMEOUT waiting for AW/W master %0d", master);
            end
        end
    endtask

    task send_b(input [3:0] response_id, input [1:0] response_code);
        integer count;
        reg accepted;
        begin
            @(negedge clk);
            bid = response_id;
            bresp = response_code;
            bvalid = 1'b1;
            count = 0;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                accepted = bready;
                #1;
                count = count + 1;
                if (count > 80) $fatal(1, "TIMEOUT waiting for B retirement");
            end
            @(negedge clk);
            bvalid = 1'b0;
        end
    endtask

    task drain_good(input integer master);
        begin
            wait_data(master);
            send_b(m_id[master], 2'b00);
        end
    endtask

    task check_fault(input [7:0] code);
        begin
            if (fault !== 1'b1 || fault_code !== code)
                $fatal(1, "fault expected %0d, got fault=%b code=%0d", code, fault, fault_code);
        end
    endtask

    task check_empty(input integer total);
        begin
            tick(2);
            if (!idle || owner_active || retirements != total ||
                m_active[0] || m_active[1] || m_active[2])
                $fatal(1, "port/masters not fully drained, retired %0d/%0d", retirements, total);
        end
    endtask

    integer round_number;
    integer case_number;
    reg [3:0] response_id;
    reg [1:0] response_code;
    initial begin
        // Concurrent multi-round round-robin, independent AW/W stalls, and B
        // held with the owner not READY. Masters remain live while waiting.
        reset_dut();
        for (round_number = 0; round_number < 4; round_number = round_number + 1) begin
            @(negedge clk);
            queue_master(0, 3);
            queue_master(1, 2);
            queue_master(2, 4);
            if (round_number == 0) begin
                wait_owner(0);
                tick(11);
                @(negedge clk); awready = 1'b1;
                tick(7);
                @(negedge clk); wready = 1'b1;
                wait_data(0);
                tick(9);
                @(negedge clk);
                s_bready[0] = 1'b0;
                bid = m_id[0]; bresp = 2'b00; bvalid = 1'b1;
                tick(13);
                if (!owner_active || owner != 0 || !s_bvalid[0] || bready)
                    $fatal(1, "B stall lost owner/response");
                @(negedge clk); s_bready[0] = 1'b1;
                tick(1);
                @(negedge clk); bvalid = 1'b0;
            end else begin
                drain_good(0);
            end
            drain_good(1);
            drain_good(2);
        end
        check_empty(12);
        for (n = 0; n < 12; n = n + 1)
            if (selection_order[n] != n % 3) $fatal(1, "round-robin fairness/order failed");
        if (fault) $fatal(1, "legal traffic faulted");
        $display("PASS arbiter3 concurrent RR, stable AW/W/B, multi-round fairness");

        // Keep all contenders queued by replacing each completed request before
        // the next arbitration edge. Fixed priority would repeatedly select 0.
        reset_dut();
        @(negedge clk);
        queue_master(0, 2); queue_master(1, 2); queue_master(2, 2);
        awready = 1'b1; wready = 1'b1;
        for (round_number = 0; round_number < 3; round_number = round_number + 1) begin
            drain_good(0);
            if (round_number < 2) queue_master(0, 2);
            drain_good(1);
            if (round_number < 2) queue_master(1, 2);
            drain_good(2);
            if (round_number < 2) queue_master(2, 2);
        end
        check_empty(9);
        for (n = 0; n < 9; n = n + 1)
            if (selection_order[n] != n % 3) $fatal(1, "continuous contention fairness failed");
        $display("PASS arbiter3 continuous-contention round-robin fairness");

        // W can finish before AW. A later lower-numbered request cannot replace
        // an owner whose AW is already exposed and stalled.
        reset_dut();
        @(negedge clk); queue_master(2, 2); wready = 1'b1;
        wait_owner(2);
        @(negedge clk); queue_master(0, 1); queue_master(1, 3);
        tick(17);
        if (!owner_active || owner != 2 || m_beat[2] != 2 || !m_awpending[2])
            $fatal(1, "late request stole selected owner / independent W failed");
        @(negedge clk); awready = 1'b1;
        drain_good(2); drain_good(0); drain_good(1);
        check_empty(3);
        if (selection_order[0] != 2 || selection_order[1] != 0 || selection_order[2] != 1)
            $fatal(1, "round-robin wrap after late requests failed");
        $display("PASS arbiter3 late arrivals and W-before-AW");

        // A persistent early response has all three faults: phase has priority.
        // It must not escape to a master or retire ownership before AW/WLAST.
        reset_dut();
        @(negedge clk);
        queue_master(0, 3); queue_master(1, 2); queue_master(2, 1);
        wait_owner(0);
        @(negedge clk); bid = 4'bxxxx; bresp = 2'bxx; bvalid = 1'b1;
        tick(5);
        check_fault(8'd4);
        if (bready || |s_bvalid || !owner_active || owner != 0)
            $fatal(1, "early B consumed or ownership changed");
        @(negedge clk); awready = 1'b1; wready = 1'b1;
        wait_data(0);
        // The response is still VALID; legal B phase now permits draining it.
        tick(1);
        @(negedge clk); bvalid = 1'b0;
        check_fault(8'd4);
        drain_good(1); drain_good(2);
        check_empty(3); check_fault(8'd4);
        $display("PASS arbiter3 early B priority and post-fault pending-AW drain");

        // No-owner B drains without being misrouted. First cause remains sticky
        // through later bad BID/BRESP and every pending master's transaction.
        reset_dut();
        @(negedge clk); bid = 4'bxxxx; bresp = 2'bxx; bvalid = 1'b1;
        tick(3); check_fault(8'd1);
        if (|s_bvalid || owner_active || idle || !bready)
            $fatal(1, "stray response routing/idle failed");
        @(negedge clk); bvalid = 1'b0;
        queue_master(0, 1); queue_master(1, 2); queue_master(2, 3);
        awready = 1'b1; wready = 1'b1;
        wait_data(0); send_b(m_id[0] ^ 4'hf, 2'b10);
        drain_good(1); drain_good(2);
        check_empty(3); check_fault(8'd1);
        $display("PASS arbiter3 stray B, first cause, and fault does not gate arbitration");

        // An AXI master may change AW payload after its AW handshake. Response
        // validation must use the ID captured at owner selection, not live AWID.
        reset_dut();
        @(negedge clk); queue_master(2, 2); awready = 1'b1; wready = 1'b1;
        wait_data(2);
        response_id = m_id[2];
        @(negedge clk); m_id[2] = m_id[2] ^ 4'hf;
        send_b(response_id, 2'b00);
        check_empty(1);
        if (fault) $fatal(1, "response ID compared against inactive live AW payload");

        // Wrong BID is detected while the master holds BREADY low; the response
        // and owner persist and can still retire once the master becomes ready.
        reset_dut();
        @(negedge clk); queue_master(0, 1); awready = 1'b1; wready = 1'b1;
        wait_data(0);
        @(negedge clk);
        s_bready[0] = 1'b0; bid = m_id[0] ^ 4'hf; bresp = 2'b00; bvalid = 1'b1;
        tick(9); check_fault(8'd2);
        if (!owner_active || owner != 0 || s_bvalid != 3'b001 || bready)
            $fatal(1, "bad BID during B stall lost owner/VALID");
        @(negedge clk); s_bready[0] = 1'b1;
        tick(1);
        @(negedge clk); bvalid = 1'b0;
        check_empty(1); check_fault(8'd2);
        $display("PASS arbiter3 latched AWID and error detection under B backpressure");

        // Strict four-state response checks, including ID-over-RESP priority.
        for (case_number = 0; case_number < 7; case_number = case_number + 1) begin
            reset_dut();
            @(negedge clk); queue_master(1, 2); awready = 1'b1; wready = 1'b1;
            wait_data(1);
            response_id = m_id[1]; response_code = 2'b00;
            case (case_number)
                0: response_id = m_id[1] ^ 4'hf;
                1: response_id[3] = 1'bx;
                2: response_code = 2'b10;
                3: response_code = 2'b0x;
                4: begin response_id = m_id[1] ^ 4'hf; response_code = 2'b11; end
                5: response_id[0] = 1'bz;
                6: response_code = 2'bz0;
            endcase
            send_b(response_id, response_code);
            check_fault((case_number == 2 || case_number == 3 || case_number == 6) ? 8'd3 : 8'd2);
            check_empty(1);
        end
        $display("PASS arbiter3 bad/unknown BID and BRESP with priority");

        // Coordinated reset can cancel a held transaction and clears fault/RR.
        reset_dut();
        @(negedge clk); queue_master(1, 4);
        wait_owner(1); tick(4);
        reset_dut();
        @(negedge clk);
        queue_master(0, 1); queue_master(1, 1); queue_master(2, 1);
        awready = 1'b1; wready = 1'b1;
        drain_good(0); drain_good(1); drain_good(2);
        check_empty(3);
        if (fault || fault_code) $fatal(1, "reset recovery did not clear fault");
        $display("PASS tb_axi_write_arbiter3");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "TIMEOUT tb_axi_write_arbiter3");
    end
endmodule
