`timescale 1ns/1ps

// Serial-only MS7200 model. Register addresses are LOW BYTE FIRST on this
// vendor's bus. This model never reads transaction signals inside the DUT.
module ms7200_i2c_model (
    input wire reset_n,
    input wire present,
    input wire [7:0] scratch_value,
    input wire [7:0] status_209e,
    input integer nack_config_index,
    input integer nack_post_index,
    input wire scl,
    inout wire sda,
    output integer config_count,
    output integer scratch_count,
    output integer post_count,
    output integer poll_count,
    output integer read_count,
    output integer address_count
);
    reg [7:0] edid [0:255];
    initial $readmemh("config/video_edid.hex", edid);
    reg pull_low = 1'b0;
    assign sda = pull_low ? 1'b0 : 1'bz;
    reg active = 1'b0;
    reg transmit = 1'b0;
    reg advance_to_read = 1'b0;
    reg ack_complete = 1'b0;
    reg ack_low = 1'b0;
    reg probe_read = 1'b0;
    reg [7:0] shift_byte = 8'd0;
    reg [7:0] tx_byte = 8'd0;
    reg [15:0] register_addr = 16'd0;
    integer slot = 0;
    integer byte_index = 0;

    // Independent transcription of the selected vendor's non-EDID boot data.
    // Indices 30..37 and 38..45 intentionally repeat the EDID header writes.
    function automatic [23:0] expected_boot(input integer index);
        integer offset;
        begin
            if (index >= 30 && index < 294) begin
                offset = index < 38 ? index - 30 : index - 38;
                expected_boot = {8'h0d, offset[7:0], edid[offset]};
            end else begin
                case (index)
                    0: expected_boot = 24'h020402;
                    1: expected_boot = 24'h020540;
                    2: expected_boot = 24'h000401;
                    3: expected_boot = 24'h000926;
                    4: expected_boot = 24'h102e01;
                    5: expected_boot = 24'h1025b0;
                    6: expected_boot = 24'h102d83;
                    7: expected_boot = 24'h100020;
                    8: expected_boot = 24'h100f04;
                    9: expected_boot = 24'h0003c3;
                    10: expected_boot = 24'h103b02;
                    11: expected_boot = 24'h00e100;
                    12: expected_boot = 24'h00a808;
                    13: expected_boot = 24'h000a00;
                    14: expected_boot = 24'h001602;
                    15: expected_boot = 24'h00e201;
                    16: expected_boot = 24'h00c214;
                    17: expected_boot = 24'h102dc7;
                    18: expected_boot = 24'h100504;
                    19: expected_boot = 24'h100314;
                    20: expected_boot = 24'h100401;
                    21: expected_boot = 24'h100060;
                    22: expected_boot = 24'h102013;
                    23: expected_boot = 24'h102104;
                    24: expected_boot = 24'h102204;
                    25: expected_boot = 24'h10230c;
                    26: expected_boot = 24'h102b33;
                    27: expected_boot = 24'h102c33;
                    28: expected_boot = 24'h00f010;
                    29: expected_boot = 24'h000c80;
                    294: expected_boot = 24'h000c00;
                    295: expected_boot = 24'h000a04;
                    296: expected_boot = 24'h20000f;
                    297: expected_boot = 24'h200100;
                    298: expected_boot = 24'h200200;
                    299: expected_boot = 24'h200301;
                    default: expected_boot = 24'hxxxxxx;
                endcase
            end
        end
    endfunction

    function automatic [23:0] expected_post(input integer index);
        begin
            case (index % 7)
                0: expected_post = 24'h101001;
                1: expected_post = 24'h102400;
                2: expected_post = 24'h020000;
                3: expected_post = 24'h102470;
                4: expected_post = 24'h020007;
                5: expected_post = 24'h021501;
                6: expected_post = 24'h021500;
                default: expected_post = 24'hxxxxxx;
            endcase
        end
    endfunction

    always @(negedge reset_n) begin
        pull_low = 1'b0;
        active = 1'b0;
        transmit = 1'b0;
        advance_to_read = 1'b0;
        ack_complete = 1'b0;
        probe_read = 1'b0;
        slot = 0;
        config_count = 0;
        scratch_count = 0;
        post_count = 0;
        poll_count = 0;
        read_count = 0;
        address_count = 0;
        register_addr = 16'd0;
    end

    always @(negedge sda) begin
        if (reset_n && scl === 1'b1) begin
            active = 1'b1;
            transmit = 1'b0;
            advance_to_read = 1'b0;
            ack_complete = 1'b0;
            ack_low = 1'b0;
            shift_byte = 8'd0;
            slot = 0;
            byte_index = 0;
        end
    end

    always @(posedge sda) begin
        if (reset_n && scl === 1'b1) begin
            active = 1'b0;
            pull_low = 1'b0;
        end
    end

    always @(posedge scl) begin
        if (reset_n && active) begin
            if (slot < 8) begin
                if (!transmit) begin
                    shift_byte = {shift_byte[6:0], sda};
                    if (slot == 7) begin
                        ack_low = present;
                        case (byte_index)
                            0: begin
                                if (shift_byte[7:1] !== 7'h2b)
                                    $fatal(1, "Unexpected MS7200 address: %02x", shift_byte);
                                address_count = address_count + 1;
                                advance_to_read = shift_byte[0];
                                if (shift_byte[0]) begin
                                    if (!probe_read) begin
                                        if (register_addr !== 16'h0003)
                                            $fatal(1, "Expected scratch read, got %04x", register_addr);
                                        tx_byte = scratch_value;
                                    end else begin
                                        if (config_count != 300 ||
                                            register_addr !== 16'h209c + (poll_count % 4))
                                            $fatal(1, "Unexpected poll %04x at boot=%0d poll=%0d",
                                                register_addr, config_count, poll_count);
                                        case (register_addr)
                                            16'h209c: tx_byte = 8'h39;
                                            16'h209d: tx_byte = 8'h57;
                                            16'h209e: tx_byte = status_209e;
                                            16'h209f: tx_byte = 8'ha5;
                                        endcase
                                    end
                                end
                            end
                            1: register_addr[7:0] = shift_byte;
                            2: register_addr[15:8] = shift_byte;
                            3: begin
                                if (!probe_read) begin
                                    if ({register_addr, shift_byte} !== 24'h00035a)
                                        $fatal(1, "Unexpected scratch write: %04x=%02x", register_addr, shift_byte);
                                    scratch_count = scratch_count + 1;
                                end else if (config_count < 300) begin
                                    if ({register_addr, shift_byte} !== expected_boot(config_count))
                                        $fatal(1, "RX boot[%0d] got %04x=%02x expected %06x",
                                            config_count, register_addr, shift_byte, expected_boot(config_count));
                                    if (config_count == nack_config_index) ack_low = 1'b0;
                                    config_count = config_count + 1;
                                end else begin
                                    if (poll_count < 8 || {register_addr, shift_byte} !== expected_post(post_count))
                                        $fatal(1, "RX post[%0d] got %04x=%02x expected %06x poll=%0d",
                                            post_count, register_addr, shift_byte, expected_post(post_count), poll_count);
                                    if (post_count == nack_post_index) ack_low = 1'b0;
                                    post_count = post_count + 1;
                                end
                            end
                            default: $fatal(1, "Unexpected extra RX write byte");
                        endcase
                        byte_index = byte_index + 1;
                    end
                end
                slot = slot + 1;
            end else begin
                if (transmit) begin
                    if (sda !== 1'b1)
                        $fatal(1, "Single-byte RX read must end with master NACK");
                    read_count = read_count + 1;
                    if (!probe_read) begin
                        // The controller retries the probe if its echo is bad.
                        if (scratch_value == 8'h5a) probe_read = 1'b1;
                    end else poll_count = poll_count + 1;
                    transmit = 1'b0;
                end
                slot = 0;
                ack_complete = 1'b1;
            end
        end
    end

    always @(negedge scl) begin
        if (reset_n && active) begin
            if (slot == 8) begin
                pull_low = !transmit && ack_low;
            end else if (ack_complete) begin
                ack_complete = 1'b0;
                if (advance_to_read) begin
                    transmit = 1'b1;
                    advance_to_read = 1'b0;
                end
                pull_low = transmit && present && !tx_byte[7];
            end else begin
                pull_low = transmit && present && !tx_byte[7-slot];
            end
        end else pull_low = 1'b0;
    end
endmodule
