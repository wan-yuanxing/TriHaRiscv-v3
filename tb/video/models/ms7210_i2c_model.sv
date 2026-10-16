`timescale 1ns/1ps

// Serial bus model: no access to the DUT's transaction or data signals.
// The device uses 7-bit address 0x59 and sends register low byte first.
module ms7210_i2c_model (
    input wire reset_n,
    input wire present,
    input wire [7:0] id_value,
    input integer nack_config_index,
    input wire scl,
    inout wire sda,
    output integer config_count,
    output integer scratch_count,
    output integer read_count,
    output integer address_count
);
    reg pull_low = 1'b0;
    assign sda = pull_low ? 1'b0 : 1'bz;

    reg active = 1'b0;
    reg transmit = 1'b0;
    reg advance_to_read = 1'b0;
    reg ack_complete = 1'b0;
    reg ack_low = 1'b0;
    reg [7:0] shift_byte = 8'd0;
    reg [7:0] tx_byte = 8'd0;
    reg [15:0] register_addr = 16'd0;
    integer slot = 0;
    integer byte_index = 0;

    // Independent transcription of the selected TX-only reference sequence.
    function automatic [23:0] expected_config(input integer index);
        begin
            case (index)
                0: expected_config = 24'h128104;
                1: expected_config = 24'h001604;
                2: expected_config = 24'h000901;
                3: expected_config = 24'h000709;
                4: expected_config = 24'h0008f0;
                5: expected_config = 24'h000af0;
                6: expected_config = 24'h000611;
                7: expected_config = 24'h053184;
                8: expected_config = 24'h090020;
                9: expected_config = 24'h090147;
                10: expected_config = 24'h090409;
                11: expected_config = 24'h092307;
                12: expected_config = 24'h092444;
                13: expected_config = 24'h092544;
                14: expected_config = 24'h090f80;
                15: expected_config = 24'h091f07;
                16: expected_config = 24'h09201e;
                17: expected_config = 24'h001820;
                18: expected_config = 24'h05c0fe;
                19: expected_config = 24'h000b00;
                20: expected_config = 24'h050706;
                21: expected_config = 24'h090604;
                22: expected_config = 24'h09205e;
                23: expected_config = 24'h0926dd;
                24: expected_config = 24'h09270d;
                25: expected_config = 24'h092888;
                26: expected_config = 24'h092908;
                27: expected_config = 24'h091001;
                28: expected_config = 24'h000b11;
                29: expected_config = 24'h050e00;
                30: expected_config = 24'h050a82;
                31: expected_config = 24'h050902;
                32: expected_config = 24'h050b0d;
                33: expected_config = 24'h050d06;
                34: expected_config = 24'h050d11;
                35: expected_config = 24'h050d58;
                36,37,38,39,40,41,42,43,44,45,46:
                    expected_config = 24'h050d00;
                47: expected_config = 24'h050e40;
                48: expected_config = 24'h050700;
                default: expected_config = 24'hxxxxxx;
            endcase
        end
    endfunction

    always @(negedge reset_n) begin
        pull_low = 1'b0;
        active = 1'b0;
        transmit = 1'b0;
        slot = 0;
        config_count = 0;
        scratch_count = 0;
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
                        if (byte_index == 0) begin
                            if (shift_byte[7:1] !== 7'h59)
                                $fatal(1, "Unexpected I2C chip address: %02x", shift_byte);
                            address_count = address_count + 1;
                            advance_to_read = shift_byte[0];
                            if (shift_byte[0]) begin
                                if (register_addr !== 16'h0003)
                                    $fatal(1, "Unexpected TX read register: %04x", register_addr);
                                tx_byte = id_value;
                            end
                        end else if (byte_index == 1) begin
                            register_addr[7:0] = shift_byte;
                        end else if (byte_index == 2) begin
                            register_addr[15:8] = shift_byte;
                        end else if (byte_index == 3) begin
                            if (register_addr == 16'h0003) begin
                                if (shift_byte !== 8'h5a)
                                    $fatal(1, "Unexpected scratch value: %02x", shift_byte);
                                scratch_count = scratch_count + 1;
                            end else begin
                                if (config_count >= 49 ||
                                    {register_addr, shift_byte} !== expected_config(config_count))
                                    $fatal(1, "TX config[%0d]: got %04x=%02x expected %06x",
                                        config_count, register_addr, shift_byte,
                                        expected_config(config_count));
                                if (config_count == nack_config_index)
                                    ack_low = 1'b0;
                                config_count = config_count + 1;
                            end
                        end else begin
                            $fatal(1, "Unexpected extra write byte");
                        end
                        byte_index = byte_index + 1;
                    end
                end
                slot = slot + 1;
            end else begin
                if (transmit) begin
                    if (sda !== 1'b1)
                        $fatal(1, "Single-byte ID read must end with master NACK");
                    read_count = read_count + 1;
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
        end else begin
            pull_low = 1'b0;
        end
    end
endmodule
