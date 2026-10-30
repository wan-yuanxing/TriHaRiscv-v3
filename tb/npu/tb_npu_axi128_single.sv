`timescale 1ns/1ps

module tb_npu_axi128_single;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg req_valid = 1'b0;
    reg req_write = 1'b0;
    reg [31:0] req_addr = 32'b0;
    reg [127:0] req_wdata = 128'b0;
    reg [15:0] req_wstrb = 16'b0;
    wire req_ready;
    wire rsp_valid;
    wire [127:0] rsp_rdata;
    wire rsp_error;
    wire fault;
    wire [3:0] arid, awid;
    wire [31:0] araddr, awaddr;
    wire [7:0] arlen, awlen;
    wire [2:0] arsize, awsize;
    wire [1:0] arburst, awburst;
    wire arvalid, awvalid, wvalid, wlast, rready, bready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg arready = 1'b0;
    reg awready = 1'b0;
    reg wready = 1'b0;
    reg [3:0] rid = 4'b0;
    reg [127:0] rdata = 128'b0;
    reg [1:0] rresp = 2'b0;
    reg rlast = 1'b1;
    reg rvalid = 1'b0;
    reg [3:0] bid = 4'b0;
    reg [1:0] bresp = 2'b0;
    reg bvalid = 1'b0;

    npu_axi128_single u_dut (
        .clk_i(clk), .rst_ni(rst_n),
        .req_valid_i(req_valid), .req_write_i(req_write),
        .req_addr_i(req_addr), .req_wdata_i(req_wdata),
        .req_wstrb_i(req_wstrb), .req_ready_o(req_ready),
        .rsp_valid_o(rsp_valid), .rsp_rdata_o(rsp_rdata),
        .rsp_error_o(rsp_error), .fault_o(fault),
        .m_axi_arid_o(arid), .m_axi_araddr_o(araddr),
        .m_axi_arlen_o(arlen), .m_axi_arsize_o(arsize),
        .m_axi_arburst_o(arburst), .m_axi_arvalid_o(arvalid),
        .m_axi_arready_i(arready), .m_axi_rid_i(rid),
        .m_axi_rdata_i(rdata), .m_axi_rresp_i(rresp),
        .m_axi_rlast_i(rlast), .m_axi_rvalid_i(rvalid),
        .m_axi_rready_o(rready),
        .m_axi_awid_o(awid), .m_axi_awaddr_o(awaddr),
        .m_axi_awlen_o(awlen), .m_axi_awsize_o(awsize),
        .m_axi_awburst_o(awburst), .m_axi_awvalid_o(awvalid),
        .m_axi_awready_i(awready), .m_axi_wdata_o(wdata),
        .m_axi_wstrb_o(wstrb), .m_axi_wlast_o(wlast),
        .m_axi_wvalid_o(wvalid), .m_axi_wready_i(wready),
        .m_axi_bid_i(bid), .m_axi_bresp_i(bresp),
        .m_axi_bvalid_i(bvalid), .m_axi_bready_o(bready)
    );

    integer ar_count = 0;
    integer aw_count = 0;
    integer w_count = 0;
    integer r_count = 0;
    integer b_count = 0;
    integer case_count = 0;
    reg ar_stalled = 1'b0;
    reg aw_stalled = 1'b0;
    reg w_stalled = 1'b0;
    reg [48:0] previous_ar;
    reg [48:0] previous_aw;
    reg [144:0] previous_w;
    reg previous_rsp = 1'b0;

    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("DMA_FAIL time=%0t case=%0d %s", $time, case_count, message);
            $fatal(1);
        end
    endtask

    // Sample before nonblocking state changes: a stalled VALID must remain
    // asserted with the same payload through the eventual handshake edge.
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_count = 0;
            aw_count = 0;
            w_count = 0;
            r_count = 0;
            b_count = 0;
            ar_stalled = 1'b0;
            aw_stalled = 1'b0;
            w_stalled = 1'b0;
            previous_rsp = 1'b0;
        end else begin
            if (ar_stalled)
                check(arvalid && {arid, araddr, arlen, arsize, arburst} === previous_ar,
                      "AR changed while stalled");
            if (aw_stalled)
                check(awvalid && {awid, awaddr, awlen, awsize, awburst} === previous_aw,
                      "AW changed while stalled");
            if (w_stalled)
                check(wvalid && {wdata, wstrb, wlast} === previous_w,
                      "W changed while stalled");
            if (arvalid)
                check(arid == 0 && arlen == 0 && arsize == 4 && arburst == 1,
                      "AR constants are not single-beat INCR128 ID0");
            if (awvalid)
                check(awid == 0 && awlen == 0 && awsize == 4 && awburst == 1,
                      "AW constants are not single-beat INCR128 ID0");
            if (wvalid)
                check(wlast && wstrb != 0, "W must be LAST with nonempty byte enables");
            check(!(rsp_valid && previous_rsp), "response lasted more than one cycle");
            ar_stalled = arvalid && !arready;
            aw_stalled = awvalid && !awready;
            w_stalled = wvalid && !wready;
            previous_ar = {arid, araddr, arlen, arsize, arburst};
            previous_aw = {awid, awaddr, awlen, awsize, awburst};
            previous_w = {wdata, wstrb, wlast};
            previous_rsp = rsp_valid;
            if (arvalid && arready) ar_count = ar_count + 1;
            if (awvalid && awready) aw_count = aw_count + 1;
            if (wvalid && wready) w_count = w_count + 1;
            if (rvalid && rready) r_count = r_count + 1;
            if (bvalid && bready) b_count = b_count + 1;
        end
    end

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic quiet(input integer cycles);
        repeat (cycles) begin
            tick();
            check(!rsp_valid, "response preceded actual AXI completion");
        end
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst_n = 1'b0;
        req_valid = 1'b0;
        arready = 1'b0;
        awready = 1'b0;
        wready = 1'b0;
        rvalid = 1'b0;
        bvalid = 1'b0;
        repeat (3) tick();
        check(!arvalid && !awvalid && !wvalid && !rready && !bready && !rsp_valid && !fault,
              "reset did not quiesce channels and fault");
        @(negedge clk);
        rst_n = 1'b1;
        tick();
        check(req_ready, "request not ready after reset");
    endtask

    task automatic submit(input bit write_cmd, input [31:0] address,
                          input [127:0] data_value, input [15:0] strobes);
        integer waited;
        @(negedge clk);
        req_valid = 1'b1;
        req_write = write_cmd;
        req_addr = address;
        req_wdata = data_value;
        req_wstrb = strobes;
        waited = 0;
        #1;
        while (!req_ready && waited < 20) begin
            @(negedge clk);
            #1;
            waited = waited + 1;
        end
        check(req_ready, "request handshake never became available");
        check(!rsp_valid, "response present before request handshake");
        tick();
        @(negedge clk);
        req_valid = 1'b0;
        // Prove the accepted command is latched, rather than using live inputs.
        req_addr = 32'hdeadbeef;
        req_wdata = ~data_value;
        req_wstrb = ~strobes;
        req_write = !write_cmd;
    endtask

    task automatic response(input bit error_expected, input [127:0] data_expected,
                            input bit compare_data);
        integer waited;
        waited = 0;
        while (!rsp_valid && waited < 20) begin
            tick();
            waited = waited + 1;
        end
        check(rsp_valid, "missing client response");
        check(rsp_error === error_expected, "wrong response error status");
        if (compare_data)
            check(rsp_rdata === data_expected, "wrong read payload");
        tick();
        check(!rsp_valid, "client response is not a single-cycle pulse");
    endtask

    task automatic accept_ar(input [31:0] address, input integer delay_cycles);
        check(arvalid && araddr === address, "read address missing or not latched");
        check(!awvalid && !wvalid && !req_ready && !rready,
              "read accepted another command or enabled response before AR");
        quiet(delay_cycles);
        check(!fault, "legal AR backpressure became a fault");
        @(negedge clk);
        arready = 1'b1;
        tick();
        check(!arvalid && rready, "read did not advance after AR handshake");
        @(negedge clk);
        arready = 1'b0;
    endtask

    task automatic send_r(input [127:0] value, input [3:0] id_value,
                          input [1:0] response_value, input bit last_value);
        @(negedge clk);
        rdata = value;
        rid = id_value;
        rresp = response_value;
        rlast = last_value;
        rvalid = 1'b1;
        check(rready, "R channel was not ready for pending read");
        tick();
        @(negedge clk);
        rvalid = 1'b0;
    endtask

    task automatic send_b(input [3:0] id_value, input [1:0] response_value);
        @(negedge clk);
        bid = id_value;
        bresp = response_value;
        bvalid = 1'b1;
        check(bready, "B channel was not ready after AW and W");
        tick();
        @(negedge clk);
        bvalid = 1'b0;
    endtask

    task automatic good_read(input [31:0] address, input [127:0] value,
                             input integer address_delay, input integer data_delay);
        integer ar_before, r_before;
        case_count = case_count + 1;
        ar_before = ar_count;
        r_before = r_count;
        submit(0, address, 0, 0);
        accept_ar(address, address_delay);
        quiet(data_delay);
        check(!fault && !req_ready && rready, "read response wait lost transaction");
        send_r(value, 0, 0, 1);
        response(0, value, 1);
        check(req_ready && !fault && ar_count == ar_before + 1 && r_count == r_before + 1,
              "read did not return idle with exactly one AR/R handshake");
    endtask

    task automatic good_write(input [31:0] address, input [127:0] value,
                              input [15:0] strobes, input integer first_channel,
                              input integer first_delay, input integer second_delay,
                              input integer response_delay);
        integer aw_before, w_before, b_before;
        case_count = case_count + 1;
        aw_before = aw_count;
        w_before = w_count;
        b_before = b_count;
        submit(1, address, value, strobes);
        check(awvalid && awaddr === address && wvalid && wdata === value && wstrb === strobes,
              "write command missing or not latched");
        check(!arvalid && !req_ready && !bready, "write enabled premature completion");
        quiet(first_delay);
        @(negedge clk);
        awready = first_channel != 1;
        wready = first_channel != 0;
        tick();
        if (first_channel == 0)
            check(!awvalid && wvalid && !bready, "AW-first did not retain pending W");
        if (first_channel == 1)
            check(awvalid && !wvalid && !bready, "W-first did not retain pending AW");
        @(negedge clk);
        awready = 1'b0;
        wready = 1'b0;
        quiet(second_delay);
        check(!fault, "legal write backpressure became a fault");
        if (first_channel != 2) begin
            @(negedge clk);
            awready = first_channel == 1;
            wready = first_channel == 0;
            tick();
            @(negedge clk);
            awready = 1'b0;
            wready = 1'b0;
        end
        check(!awvalid && !wvalid && bready, "write response preceded both write channels");
        quiet(response_delay);
        check(!fault && !req_ready, "B delay lost pending write");
        send_b(0, 0);
        response(0, 0, 0);
        check(aw_count == aw_before + 1 && w_count == w_before + 1 && b_count == b_before + 1,
              "write duplicated or omitted an AXI handshake");
        check(req_ready && !fault, "successful write did not return idle");
    endtask

    task automatic fault_locked;
        check(fault && !req_ready, "AXI error did not latch fault and block request");
        @(negedge clk);
        req_valid = 1'b1;
        req_write = 1'b1;
        req_addr = 32'h82000100;
        req_wstrb = 16'hffff;
        arready = 1'b1;
        awready = 1'b1;
        wready = 1'b1;
        repeat (12) begin
            tick();
            check(fault && !req_ready && !arvalid && !awvalid && !wvalid && !rready && !bready,
                  "fault allowed another transaction or response handshake");
            check(!rsp_valid, "fault repeated completion");
        end
        @(negedge clk);
        req_valid = 1'b0;
    endtask

    task automatic illegal(input bit write_cmd, input [31:0] address, input [15:0] strobes);
        integer ar_before, aw_before, w_before;
        case_count = case_count + 1;
        ar_before = ar_count;
        aw_before = aw_count;
        w_before = w_count;
        submit(write_cmd, address, 128'h1234, strobes);
        check(!arvalid && !awvalid && !wvalid, "illegal request reached AXI");
        response(1, 0, 0);
        check(!fault && req_ready, "local validation error latched platform fault");
        quiet(3);
        check(ar_count == ar_before && aw_count == aw_before && w_count == w_before,
              "illegal request emitted an AXI handshake");
    endtask

    integer i;
    reg [31:0] random_state = 32'h6d2b79f5;
    reg [127:0] sample_data;
    initial begin
        reset_dut();
        good_read(32'h80000000, 128'h00112233445566778899aabbccddeeff, 8, 11);
        reset_dut();
        good_write(32'h87fffff0, 128'hffeeddccbbaa99887766554433221100, 16'ha581, 0, 7, 13, 9);
        good_write(32'h82000100, 128'h1032547698badcfe0123456789abcdef, 16'h0001, 1, 5, 17, 12);
        good_write(32'h82000200, 128'hfedcba98765432100123456789abcdef, 16'h8000, 2, 3, 4, 6);
        good_read(32'h82000300, 128'habcdef, 0, 0);
        good_read(32'h82000310, 128'h987654, 0, 0);
        good_write(32'h82000320, 128'h765432, 16'hffff, 2, 0, 0, 0);
        reset_dut();
        // Deterministic pseudo-random independent AR/R and AW/W/B delays.
        for (i = 0; i < 16; i = i + 1) begin
            random_state = (random_state << 1) ^ ((random_state[31]) ? 32'h04c11db7 : 32'h0);
            sample_data = {random_state, ~random_state, random_state ^ 32'ha5a5f00d, i[31:0]};
            good_read(32'h82001000 + i * 16, sample_data,
                      random_state[3:0], random_state[7:4]);
            reset_dut();
            good_write(32'h83001000 + i * 16, ~sample_data, 16'h0101 << (i % 8),
                       i % 3, random_state[11:8], random_state[15:12], random_state[19:16]);
            reset_dut();
        end
        good_read(32'h87fffff0, 128'h42, 1100, 1100);
        reset_dut();
        good_write(32'h80000000, 128'h1234, 16'h00f0, 0, 1100, 1100, 1100);
        reset_dut();

        illegal(0, 32'h7ffffff0, 0);
        illegal(0, 32'h88000000, 0);
        illegal(0, 32'h80000001, 0);
        illegal(1, 32'h87fffff1, 16'hffff);
        illegal(1, 32'h82000000, 0);
        illegal(1, 32'hfffffff0, 16'hffff);
        good_read(32'h80000000, 128'h5678, 0, 0);

        // Even an incorrectly early downstream response cannot be accepted
        // before the request channels handshake. It must not trigger a fault
        // until it is actually transferred on R/B.
        reset_dut();
        case_count = case_count + 1;
        submit(0, 32'h82000100, 0, 0);
        @(negedge clk);
        rvalid = 1'b1;
        rid = 4'hf;
        rresp = 2'b10;
        rdata = 128'habad;
        rlast = 1'b1;
        quiet(7);
        check(!rready && !fault && r_count == 0, "early R response was transferred before AR");
        @(negedge clk);
        rvalid = 1'b0;
        accept_ar(32'h82000100, 3);
        send_r(128'h123456, 0, 0, 1);
        response(0, 128'h123456, 1);
        check(!fault, "unaccepted R response caused sticky fault");

        reset_dut();
        case_count = case_count + 1;
        submit(1, 32'h82000100, 128'hc001, 16'hffff);
        @(negedge clk);
        bvalid = 1'b1;
        bid = 4'hf;
        bresp = 2'b10;
        wready = 1'b1;
        tick();
        @(negedge clk);
        wready = 1'b0;
        quiet(11);
        check(!bready && !fault && b_count == 0 && awvalid && !wvalid,
              "early B response completed before AW");
        @(negedge clk);
        bvalid = 1'b0;
        awready = 1'b1;
        tick();
        @(negedge clk);
        awready = 1'b0;
        send_b(0, 0);
        response(0, 0, 0);
        check(!fault, "unaccepted B response caused sticky fault");

        // A second client holds VALID and its payload until the first request
        // finishes. Completion and acceptance on adjacent edges must not lose
        // either transaction or use the second payload for the first transfer.
        reset_dut();
        case_count = case_count + 1;
        submit(0, 32'h82000400, 0, 0);
        @(negedge clk);
        req_valid = 1'b1;
        req_write = 1'b1;
        req_addr = 32'h82000410;
        req_wdata = 128'h0123456789abcdef;
        req_wstrb = 16'h5aa5;
        accept_ar(32'h82000400, 5);
        quiet(9);
        check(!req_ready && !awvalid && !wvalid, "busy master accepted second client request");
        send_r(128'hfacefeed, 0, 0, 1);
        check(req_ready && !awvalid && !wvalid, "second request started without a handshake");
        response(0, 128'hfacefeed, 1);
        @(negedge clk);
        req_valid = 1'b0;
        check(awvalid && awaddr == 32'h82000410 && wvalid
              && wdata == 128'h0123456789abcdef && wstrb == 16'h5aa5,
              "pending client command was lost after prior completion");
        awready = 1'b1;
        wready = 1'b1;
        tick();
        @(negedge clk);
        awready = 1'b0;
        wready = 1'b0;
        send_b(0, 0);
        response(0, 0, 0);
        check(ar_count == 1 && r_count == 1 && aw_count == 1 && w_count == 1 && b_count == 1,
              "pending client test duplicated or dropped a transfer");

        // Every non-OKAY RESP, and a nonzero ID, are fatal to subsequent work.
        for (i = 1; i <= 4; i = i + 1) begin
            reset_dut();
            case_count = case_count + 1;
            submit(0, 32'h82000000, 0, 0);
            accept_ar(32'h82000000, i);
            send_r(128'h0123456789abcdef, (i == 4) ? 4'h7 : 4'h0,
                   (i == 4) ? 2'b00 : i[1:0], 1);
            response(1, 0, 0);
            fault_locked();
        end
        for (i = 1; i <= 4; i = i + 1) begin
            reset_dut();
            case_count = case_count + 1;
            submit(1, 32'h82000000, 128'hf00d, 16'hffff);
            @(negedge clk);
            awready = 1'b1;
            wready = 1'b1;
            tick();
            @(negedge clk);
            awready = 1'b0;
            wready = 1'b0;
            send_b((i == 4) ? 4'h9 : 4'h0, (i == 4) ? 2'b00 : i[1:0]);
            response(1, 0, 0);
            fault_locked();
        end

        reset_dut();
        case_count = case_count + 1;
        submit(0, 32'h82000000, 0, 0);
        accept_ar(32'h82000000, 2);
        send_r(128'h1111, 0, 0, 0);
        check(fault && !req_ready && rready && !rsp_valid,
              "missing LAST was not faulted and retained for draining");
        quiet(37);
        send_r(128'h2222, 4'hf, 2'b10, 0);
        check(fault && rready && !rsp_valid, "drain completed on a beat without LAST");
        quiet(19);
        send_r(128'h3333, 0, 0, 1);
        response(1, 0, 0);
        fault_locked();

        // Reset aborts only the local model transaction; coordinated system reset
        // is required in hardware to reset the AXI peer at the same time.
        reset_dut();
        case_count = case_count + 1;
        submit(0, 32'h82000000, 0, 0);
        quiet(3);
        reset_dut();
        good_read(32'h82000010, 128'habcd, 2, 2);
        reset_dut();
        case_count = case_count + 1;
        submit(1, 32'h82000000, 128'hcafe, 16'hffff);
        @(negedge clk);
        wready = 1'b1;
        tick();
        @(negedge clk);
        wready = 1'b0;
        reset_dut();
        good_write(32'h82000010, 128'hdead, 16'hffff, 1, 2, 2, 2);
        reset_dut();
        case_count = case_count + 1;
        submit(0, 32'h82000000, 0, 0);
        accept_ar(32'h82000000, 0);
        send_r(128'h1, 0, 0, 0);
        reset_dut();
        good_read(32'h82000020, 128'h9876, 2, 2);

        reset_dut();
        case_count = case_count + 1;
        submit(0, 32'h82000000, 0, 0);
        accept_ar(32'h82000000, 0);
        quiet(3);
        reset_dut();
        good_read(32'h82000030, 128'h6789, 1, 1);

        reset_dut();
        case_count = case_count + 1;
        submit(1, 32'h82000000, 128'h1111, 16'hffff);
        @(negedge clk);
        awready = 1'b1;
        tick();
        @(negedge clk);
        awready = 1'b0;
        reset_dut();
        good_write(32'h82000040, 128'h2222, 16'hffff, 0, 1, 1, 1);

        reset_dut();
        case_count = case_count + 1;
        submit(1, 32'h82000000, 128'h3333, 16'hffff);
        @(negedge clk);
        awready = 1'b1;
        wready = 1'b1;
        tick();
        @(negedge clk);
        awready = 1'b0;
        wready = 1'b0;
        check(bready, "write reset case did not reach B wait");
        quiet(3);
        reset_dut();
        good_write(32'h82000050, 128'h4444, 16'hffff, 2, 1, 1, 1);
        $display("NPU_AXI128_SINGLE_PASS cases=%0d", case_count);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "DMA global simulation timeout");
    end
endmodule
