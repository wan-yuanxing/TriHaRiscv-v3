`timescale 1ns/1ps

module tb_hdmi_rx_init;
    localparam integer TIMEOUT_CYCLES = 500_000;
    reg clk_cfg = 1'b0;
    reg reset_n = 1'b1;
    reg present = 1'b1;
    reg [7:0] scratch_value = 8'h5a;
    reg [7:0] status_209e = 8'h02;
    integer nack_config_index = -1;
    integer nack_post_index = -1;
    wire iic_scl;
    tri1 iic_sda;
    wire init_done, link_configured, init_error;
    wire [31:0] status_word;
    integer config_count, scratch_count, post_count, poll_count, read_count, address_count;
    integer cycles, saved_polls, saved_addresses, phase;
    reg external_low = 1'b0;
    assign iic_sda = external_low ? 1'b0 : 1'bz;
    always #50 clk_cfg = ~clk_cfg;
    initial begin
        #3_000_000_000;
        $fatal(1, "RX global test watchdog");
    end

`ifdef HDMI_RX_INIT_MISSING
    assign iic_scl = 1'b1;
    assign init_done = 1'b0;
    assign link_configured = 1'b0;
    assign init_error = 1'b0;
    assign status_word = 32'd0;
`else
    hdmi_rx_init #(.INIT_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut (
        .clk_cfg(clk_cfg), .reset_n(reset_n), .iic_scl(iic_scl), .iic_sda(iic_sda),
        .init_done(init_done), .link_configured(link_configured), .init_error(init_error),
        .status_word(status_word)
    );
`endif
    ms7200_i2c_model device (
        .reset_n(reset_n && !external_low), .present(present), .scratch_value(scratch_value),
        .status_209e(status_209e), .nack_config_index(nack_config_index),
        .nack_post_index(nack_post_index), .scl(iic_scl), .sda(iic_sda),
        .config_count(config_count), .scratch_count(scratch_count), .post_count(post_count),
        .poll_count(poll_count), .read_count(read_count), .address_count(address_count)
    );

    task automatic reset_device;
        begin
            #17 reset_n = 1'b0;
            #1;
            if (init_done !== 0 || init_error !== 0 || link_configured !== 0 || iic_scl !== 1)
                $fatal(1, "Async reset must clear status and release clock");
            external_low = 1'b1;
            #1;
            if (iic_sda !== 0) $fatal(1, "SDA must be open drain during reset");
            external_low = 1'b0;
            repeat (12) @(negedge clk_cfg);
            #13 reset_n = 1'b1;
            #1;
            if (iic_scl !== 1 || iic_sda !== 1) $fatal(1, "Bus must stay idle during reset release");
        end
    endtask

    task automatic await_boot(input reg expected_done);
        begin
            cycles = 0;
            while (!init_done && !init_error && cycles < TIMEOUT_CYCLES + 30) begin
                @(negedge clk_cfg);
                cycles = cycles + 1;
            end
            if (init_done !== expected_done || init_error !== !expected_done)
                $fatal(1, "Expected boot done=%b got done=%b/error=%b at %0d clocks",
                    expected_done, init_done, init_error, cycles);
            if (expected_done && (config_count != 300 || scratch_count != 1 || read_count != 1))
                $fatal(1, "Boot must include scratch echo and exactly300 writes: %0d/%0d/%0d",
                    config_count, scratch_count, read_count);
        end
    endtask

    task automatic check_sticky_error;
        begin
            #200;
            if (iic_scl !== 1 || iic_sda !== 1) $fatal(1, "Error must release bus pads");
            saved_addresses = address_count;
            repeat (3000) @(negedge clk_cfg);
            if (!init_error || address_count != saved_addresses)
                $fatal(1, "Error must remain sticky and halt bus until reset");
        end
    endtask

    task automatic await_poll_count(input integer target_count);
        begin
            cycles = 0;
            while (poll_count < target_count && !init_error && cycles < 100_000) begin
                @(negedge clk_cfg);
                cycles = cycles + 1;
            end
            if (poll_count < target_count || init_error)
                $fatal(1, "RX polling stopped at %0d (target=%0d)", poll_count, target_count);
        end
    endtask

    task automatic await_link_config;
        begin
            cycles = 0;
            while (!link_configured && !init_error && cycles < 60_000) begin
                @(negedge clk_cfg);
                cycles = cycles + 1;
            end
            if (!link_configured || init_error || post_count != 7)
                $fatal(1, "Expected7 post config writes and sticky configured, got %0d/%b/%b",
                    post_count, link_configured, init_error);
            if (!init_done) $fatal(1, "Boot completion must remain sticky");
        end
    endtask

    // Bus-only check: init_done cannot precede the last boot write ACK/STOP.
    always @(posedge init_done) begin
        if (config_count != 300 || !iic_scl || !iic_sda)
            $fatal(1, "Boot done preceded final ACK/STOP");
    end

    initial begin
        // Run already-present status FIRST: the vendor's unreset history is
        // unknown at cold simulation startup, just as it is not guaranteed by
        // the RTL reset contract. An earlier00 test would hide that defect.
        reset_device();
        await_boot(1'b1);
        await_link_config();
        await_poll_count(poll_count + 8);
        if (post_count != 7 || status_word !== 32'ha5025739)
            $fatal(1, "Cold initial02 must configure once and preserve raw status");
        $display("HDMI_RX_INIT_CASE_PASS cold initial02 detector priming and raw status");

        status_209e = 8'h00;
        reset_device();
        await_boot(1'b1);
        // No source is a healthy waiting state, even beyond startup watchdog.
        repeat (TIMEOUT_CYCLES + 1000) @(negedge clk_cfg);
        if (!init_done || init_error || link_configured || post_count != 0 || poll_count < 12)
            $fatal(1, "No-source waiting must continue polling without error/configured");
        if (status_word !== 32'ha5005739)
            $fatal(1, "Raw status word lost serial bytes: %08x", status_word);
        $display("HDMI_RX_INIT_CASE_PASS boot300, fixed EDID264, no-source waiting");

        status_209e = 8'h02;
        await_link_config();
        saved_polls = poll_count;
        await_poll_count(saved_polls + 12);
        if (status_word !== 32'ha5025739) $fatal(1, "Raw209E status not reported");
        // Sticky configuration remains set after status returns to00. It is
        // deliberately not a live source/mode indicator.
        status_209e = 8'h00;
        await_poll_count(poll_count + 8);
        if (!link_configured || !init_done || init_error || post_count != 7)
            $fatal(1, "Configured flag must describe completed vendor writes, not current mode");
        $display("HDMI_RX_INIT_CASE_PASS real00-to02 event, seven writes, continued polling");

        // Hot-plug again without resetting the controller or disturbing TX.
        // The two completed00 poll quartets above establish the vendor's
        // previous-sample baseline for another00-to02 event.
        status_209e = 8'h02;
        cycles = 0;
        while (post_count < 14 && !init_error && cycles < 60_000) begin
            @(negedge clk_cfg);
            cycles = cycles + 1;
        end
        if (post_count != 14 || !init_done || !link_configured || init_error)
            $fatal(1, "Hot-plug must repeat exactly seven post writes without reset");
        await_poll_count(poll_count + 12);
        if (post_count != 14 || status_word !== 32'ha5025739)
            $fatal(1, "Hot-plug must resume polling and retain real raw status");
        $display("HDMI_RX_INIT_CASE_PASS hot-plug repeats7writes without resetting controller");

        status_209e = 8'h02;
        reset_device();
        await_boot(1'b1);
        await_link_config();
        await_poll_count(poll_count + 8);
        if (post_count != 7) $fatal(1, "Initial02 must configure exactly once");
        $display("HDMI_RX_INIT_CASE_PASS initial02 detector priming and raw status");

        present = 1'b0;
        reset_device();
        await_boot(1'b0);
        if (cycles >= TIMEOUT_CYCLES || config_count != 0)
            $fatal(1, "Absent address must NACK before boot writes/watchdog");
        check_sticky_error();
        $display("HDMI_RX_INIT_CASE_PASS absent MS7200 address NACK");

        present = 1'b1;
        scratch_value = 8'h00;
        reset_device();
        await_boot(1'b0);
        if (cycles < TIMEOUT_CYCLES || config_count != 0 || read_count < 1)
            $fatal(1, "Bad scratch echo must watchdog without boot configuration");
        check_sticky_error();
        $display("HDMI_RX_INIT_CASE_PASS bad scratch echo watchdog");

        scratch_value = 8'h5a;
        nack_config_index = 100;
        reset_device();
        await_boot(1'b0);
        if (config_count != 101) $fatal(1, "Boot data NACK was ignored");
        check_sticky_error();
        nack_config_index = 299;
        reset_device();
        await_boot(1'b0);
        if (config_count != 300) $fatal(1, "Final boot NACK trace wrong");
        check_sticky_error();
        $display("HDMI_RX_INIT_CASE_PASS middle/final boot NACK prevents completion");

        nack_config_index = -1;
        nack_post_index = 6;
        reset_device();
        await_boot(1'b1);
        wait (init_error);
        if (link_configured || !init_done || post_count != 7)
            $fatal(1, "Final post config NACK must not assert link_configured");
        check_sticky_error();
        nack_post_index = -1;
        $display("HDMI_RX_INIT_CASE_PASS postboot NACK remains detectable");

        for (phase = 0; phase < 6; phase = phase + 1) begin
            status_209e = 8'h02;
            reset_device();
            case (phase)
                0: begin wait (scratch_count == 1); @(negedge iic_scl); end
                1: begin wait (address_count == 3); repeat (3) @(posedge iic_scl); end
                2: begin wait (config_count == 80); @(negedge iic_scl); end
                3: begin wait (config_count == 299); @(posedge iic_scl); end
                4: begin wait (poll_count == 2); @(negedge iic_scl); end
                5: begin wait (post_count == 4); @(posedge iic_scl); end
            endcase
            if (phase == 3) begin
                #17 reset_n = 1'b0;
                #1;
                if (init_done || init_error || link_configured || !iic_scl)
                    $fatal(1, "Subclock reset did not clear/release immediately");
                #1 reset_n = 1'b1;
            end else reset_device();
            await_boot(1'b1);
            await_link_config();
            await_poll_count(poll_count + 4);
        end
        $display("HDMI_RX_INIT_CASE_PASS asynchronous reset in six bus phases");

        reset_device();
        external_low = 1'b1;
        cycles = 0;
        while (!init_error && cycles < TIMEOUT_CYCLES + 30) begin
            @(negedge clk_cfg);
            cycles = cycles + 1;
            if (iic_sda !== 0) $fatal(1, "Master actively drove SDA high");
        end
        if (init_done || !init_error || cycles < TIMEOUT_CYCLES)
            $fatal(1, "Stuck-low bus must fail boot watchdog");
        external_low = 1'b0;
        $display("HDMI_RX_INIT_CASE_PASS stuck-low bus and open drain");
        $display("HDMI_RX_INIT_PASS");
        $finish;
    end
endmodule
