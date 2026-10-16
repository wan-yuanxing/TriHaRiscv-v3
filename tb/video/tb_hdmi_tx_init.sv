`timescale 1ns/1ps

module tb_hdmi_tx_init;
`ifdef HDMI_TX_INIT_FULL_WAIT
    localparam integer TIMEOUT_CYCLES = 4_000_000;
`else
    localparam integer TIMEOUT_CYCLES = 100_000;
`endif
    reg clk_cfg = 1'b0;
    reg reset_n = 1'b1;
    reg present = 1'b1;
    reg [7:0] id_value = 8'h5a;
    integer nack_config_index = -1;
    wire iic_scl;
    tri1 iic_sda;
    wire init_done;
    wire init_error;
    integer config_count, scratch_count, read_count, address_count;
    integer cycles;
    integer saved_addresses;
    integer reset_phase;
    reg acceleration_used = 1'b0;
    reg externally_pull_low = 1'b0;

    always #50 clk_cfg = ~clk_cfg; // Actual 10 MHz configuration domain.
    assign iic_sda = externally_pull_low ? 1'b0 : 1'bz;

    initial begin
        #(TIMEOUT_CYCLES * 2000.0);
        $fatal(1, "Global TX init test watchdog expired");
    end

    hdmi_tx_init #(.INIT_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut (
        .clk_cfg(clk_cfg), .reset_n(reset_n), .iic_scl(iic_scl),
        .iic_sda(iic_sda), .init_done(init_done), .init_error(init_error)
    );

    ms7210_i2c_model device (
        .reset_n(reset_n && !externally_pull_low), .present(present), .id_value(id_value),
        .nack_config_index(nack_config_index), .scl(iic_scl), .sda(iic_sda),
        .config_count(config_count), .scratch_count(scratch_count),
        .read_count(read_count), .address_count(address_count)
    );

    // Only the vendor's 320 ms WAIT counter is accelerated. Real ms7210_ctl,
    // iic_dri, serial address/data/ACK bits, and all bus timings remain active.
    // Keep the WAIT-entry trigger separate from the WAIT-exit trigger even in
    // accelerated mode. Define HDMI_TX_INIT_FULL_WAIT for all 3,199,898 clocks.
`ifndef HDMI_TX_INIT_FULL_WAIT
    always @(negedge clk_cfg) begin
        if (reset_n && !acceleration_used && dut.u_ctl.state == 6'b001000) begin
            acceleration_used = 1'b1;
            repeat (8) @(negedge clk_cfg);
            force dut.u_ctl.delay_cnt = 22'h30d399;
            @(negedge clk_cfg);
            release dut.u_ctl.delay_cnt;
        end
    end
`endif

    task automatic reset_device;
        begin
            #17 reset_n = 1'b0;
            #1;
            if (init_done !== 1'b0 || init_error !== 1'b0 || iic_scl !== 1'b1)
                $fatal(1, "Asynchronous reset must clear status and release SCL");
            externally_pull_low = 1'b1;
            #1;
            if (iic_sda !== 1'b0)
                $fatal(1, "SDA must be released during reset");
            externally_pull_low = 1'b0;
            repeat (12) @(negedge clk_cfg);
            acceleration_used = 1'b0;
            #13 reset_n = 1'b1;
            #1;
            if (iic_scl !== 1'b1 || iic_sda !== 1'b1)
                $fatal(1, "Reset release must keep bus idle until synchronized");
        end
    endtask

    task automatic await_result(input reg expected_done);
        begin
            cycles = 0;
            while (!init_done && !init_error && cycles < TIMEOUT_CYCLES + 30) begin
                @(negedge clk_cfg);
                cycles = cycles + 1;
            end
            if (init_done !== expected_done || init_error !== !expected_done)
                $fatal(1, "Expected done=%b/error=%b got done=%b/error=%b after %0d clocks",
                    expected_done, !expected_done, init_done, init_error, cycles);
            if (iic_scl !== 1'b1 || iic_sda !== 1'b1)
                $fatal(1, "Finished or failed init must release bus");
            saved_addresses = address_count;
            repeat (2500) @(negedge clk_cfg);
            if (init_done !== expected_done || init_error !== !expected_done)
                $fatal(1, "Init result must remain sticky until reset");
            if (address_count != saved_addresses)
                $fatal(1, "Init must stop issuing transactions after result");
        end
    endtask

    task automatic check_healthy_trace;
        begin
            if (config_count != 49 || scratch_count != 1 || read_count != 1 || address_count != 52)
                $fatal(1, "Incomplete trace: config=%0d scratch=%0d reads=%0d addresses=%0d",
                    config_count, scratch_count, read_count, address_count);
        end
    endtask

    // Reset while SCL is high/low, in the read, during WAIT, and with an
    // asynchronous pulse shorter than a configuration clock. Only the final
    // restarted transaction is checked; the serial model also resets its trace.
    task automatic check_reset_phase(input integer phase);
        begin
            reset_device();
            case (phase)
                0: begin
                    wait (scratch_count == 1);
                    @(negedge iic_scl);
                end
                1: begin
                    wait (address_count == 3);
                    repeat (3) @(posedge iic_scl);
                end
                2: begin
                    wait (config_count == 4);
                    @(negedge iic_scl);
                end
                3: begin
                    wait (config_count == 19);
                    wait (iic_scl && iic_sda);
                end
                default: begin
                    wait (config_count == 40);
                    @(posedge iic_scl);
                end
            endcase
            if (phase == 4) begin
                #17 reset_n = 1'b0;
                #1;
                if (init_done || init_error || !iic_scl)
                    $fatal(1, "Short asynchronous reset did not release outputs");
                #1 reset_n = 1'b1;
                acceleration_used = 1'b0;
            end else begin
                reset_device();
            end
            await_result(1'b1);
            check_healthy_trace();
        end
    endtask

    initial begin
        reset_device();
        await_result(1'b1);
        check_healthy_trace();
        $display("HDMI_TX_INIT_CASE_PASS healthy: 0x59, ID 0x5A, all 49 config writes");
`ifdef HDMI_TX_INIT_FULL_WAIT
        if (cycles < 3_200_000)
            $fatal(1, "Full WAIT run completed too early");
        $display("HDMI_TX_INIT_PASS full vendor WAIT (%0d clocks)", cycles);
        $finish;
`endif

        present = 1'b0;
        reset_device();
        await_result(1'b0);
        if (cycles >= TIMEOUT_CYCLES || config_count != 0)
            $fatal(1, "No-device NACK must fail before timeout/configuration");
        $display("HDMI_TX_INIT_CASE_PASS absent device NACK");

        present = 1'b1;
        id_value = 8'h00;
        reset_device();
        await_result(1'b0);
        if (cycles < TIMEOUT_CYCLES || config_count != 0 || read_count < 1)
            $fatal(1, "Wrong ID must reach watchdog without configuring TX");
        $display("HDMI_TX_INIT_CASE_PASS wrong ID watchdog");

        id_value = 8'h5a;
        nack_config_index = 10;
        reset_device();
        await_result(1'b0);
        if (config_count != 11 || cycles >= TIMEOUT_CYCLES)
            $fatal(1, "Configuration data NACK must abort initialization");
        $display("HDMI_TX_INIT_CASE_PASS configuration data NACK");

        nack_config_index = 48;
        reset_device();
        await_result(1'b0);
        if (config_count != 49 || cycles >= TIMEOUT_CYCLES)
            $fatal(1, "Final configuration ACK is required before init_done");
        $display("HDMI_TX_INIT_CASE_PASS final configuration NACK prevents done");

        nack_config_index = -1;
        for (reset_phase = 0; reset_phase < 5; reset_phase = reset_phase + 1)
            check_reset_phase(reset_phase);
        $display("HDMI_TX_INIT_CASE_PASS asynchronous reset recovery in five bus phases");

        reset_device();
        externally_pull_low = 1'b1;
        cycles = 0;
        while (!init_error && cycles < TIMEOUT_CYCLES + 30) begin
            @(negedge clk_cfg);
            cycles = cycles + 1;
            if (iic_sda !== 1'b0)
                $fatal(1, "Master must never actively drive SDA high");
        end
        if (init_done || !init_error || cycles < TIMEOUT_CYCLES)
            $fatal(1, "Stuck-low SDA must fail watchdog without success");
        externally_pull_low = 1'b0;
        $display("HDMI_TX_INIT_CASE_PASS stuck-low bus/open-drain watchdog");
        $display("HDMI_TX_INIT_PASS");
        $finish;
    end
endmodule
