`timescale 1ns/1ps

// TX-only reuse of the verified, unmodified ms7210_ctl / iic_dri sources.
// clk_cfg must be 10 MHz. No RX status or input video is required.
// At 400 kHz, the vendor's 0x30d399 WAIT is 320 ms in this clock domain;
// the default one-second watchdog includes startup and all configuration writes.
module hdmi_tx_init #(
    parameter integer INIT_TIMEOUT_CYCLES = 10_000_000
) (
    input wire clk_cfg,
    input wire reset_n,
    output wire iic_scl,
    inout wire iic_sda,
    output reg init_done,
    output reg init_error
);
    // Asynchronous assertion, two-edge synchronous release in this domain.
    (* syn_preserve = 1 *) reg [1:0] reset_pipe;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n)
            reset_pipe <= 2'b00;
        else
            reset_pipe <= {reset_pipe[0], 1'b1};
    end
    wire reset_cfg_n = reset_pipe[1];

    // The vendor engine does not reset trans_en, busy, scl_out or its T_WR
    // counter. A synchronous reset alone can therefore leave it mid-bit.
    // With pads isolated and ms7210_ctl held in reset, issue one internal write
    // and let its unconditional STOP drain those registers. 1536 clocks exceed
    // its 4*9*25 bit clocks + START/STOP + 10-clock T_WR at these fixed settings.
    // Then reset its FSM/divider once more before exposing the real transaction.
    // This hardware recovery is also used after an asynchronous reset in flight.
    localparam [1:0] DRAIN = 2'd0, REARM = 2'd1, RUN = 2'd2;
    reg [1:0] startup_state;
    reg [10:0] startup_count;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) begin
            startup_state <= DRAIN;
            startup_count <= 11'd0;
        end else if (!reset_cfg_n) begin
            startup_state <= DRAIN;
            startup_count <= 11'd0;
        end else begin
            case (startup_state)
                DRAIN: begin
                    if (startup_count == 11'd1535) begin
                        startup_state <= REARM;
                        startup_count <= 11'd0;
                    end else
                        startup_count <= startup_count + 1'b1;
                end
                REARM: begin
                    if (startup_count == 11'd3)
                        startup_state <= RUN;
                    else
                        startup_count <= startup_count + 1'b1;
                end
                default: startup_count <= 11'd0;
            endcase
        end
    end

    wire running = reset_cfg_n && startup_state == RUN && !init_done && !init_error;
    wire driver_reset_n = reset_cfg_n && startup_state != REARM;
    wire vendor_done;
    wire [7:0] device_id;
    wire trigger;
    wire write_nread;
    wire [15:0] register_addr;
    wire [7:0] write_data;
    wire busy;
    wire byte_over;
    wire [7:0] read_data;
    wire scl_out;
    wire sda_out;
    wire sda_out_en;

    // ms7210_ctl also pulses iic_trig when its 19th INIT write completes,
    // although it is entering WAIT. Forwarding that pulse writes command 19
    // during WAIT and duplicates it after 320 ms. Discard only this boundary
    // pulse; the controller's own end-of-WAIT pulse remains responsible for
    // starting SETING. Count public byte completion signals, not private state.
    reg [5:0] completed_config_bytes;
    reg wait_entry_discarded;
    wire discard_wait_entry = completed_config_bytes == 6'd19 && !wait_entry_discarded;
    wire config_trigger = trigger && !discard_wait_entry;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) begin
            completed_config_bytes <= 6'd0;
            wait_entry_discarded <= 1'b0;
        end else if (!running) begin
            completed_config_bytes <= 6'd0;
            wait_entry_discarded <= 1'b0;
        end else begin
            if (byte_over && write_nread && register_addr != 16'h0003)
                completed_config_bytes <= completed_config_bytes + 1'b1;
            if (trigger && discard_wait_entry)
                wait_entry_discarded <= 1'b1;
        end
    end

    ms7210_ctl u_ctl (
        .clk(clk_cfg), .rstn(running), .init_over(vendor_done),
        .device_id(device_id), .iic_trig(trigger), .w_r(write_nread),
        .addr(register_addr), .data_in(write_data), .busy(busy),
        .data_out(read_data), .byte_over(byte_over)
    );

    iic_dri #(
        .CLK_FRE(27'd10_000_000), .IIC_FREQ(20'd400_000),
        .T_WR(10'd1), .ADDR_BYTE(2'd2), .LEN_WIDTH(8'd3), .DATA_BYTE(2'd1)
    ) u_iic (
        .clk(clk_cfg), .rstn(driver_reset_n),
        .pluse(startup_state == DRAIN ? startup_count == 11'd1 : running && config_trigger),
        .device_id(device_id), .w_r(startup_state == DRAIN ? 1'b1 : write_nread),
        .byte_len(4'd1), .addr(register_addr), .data_in(write_data),
        .busy(busy), .byte_over(byte_over), .data_out(read_data),
        .scl(scl_out), .sda_in(running ? iic_sda : 1'b1),
        .sda_out(sda_out), .sda_out_en(sda_out_en)
    );

    // The reference engine provides push-pull SCL and no stretch input.
    // SDA is genuinely open drain: a logical one always releases the pad.
    assign iic_scl = reset_n && running ? scl_out : 1'b1;
    assign iic_sda = reset_n && running && sda_out_en && !sda_out ? 1'b0 : 1'bz;

    // The reference iic_dri ignores slave ACKs. Observe the actual serialized
    // bus independently, including ACKs on both sides of repeated START.
    // The address R/W bit identifies slave-read data, whose ninth bit is the
    // master's terminal NACK and must not be treated as a slave failure.
    reg scl_previous;
    reg sda_previous;
    reg bus_active;
    reg [3:0] bit_count;
    reg address_byte;
    reg slave_read;
    wire bus_start = scl_previous && iic_scl && sda_previous && !iic_sda;
    wire bus_stop = scl_previous && iic_scl && !sda_previous && iic_sda;
    wire scl_rising = !scl_previous && iic_scl;
    wire nack_now = running && bus_active && scl_rising && bit_count == 4'd8 &&
                    (address_byte || !slave_read) && iic_sda;

    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) begin
            scl_previous <= 1'b1;
            sda_previous <= 1'b1;
            bus_active <= 1'b0;
            bit_count <= 4'd0;
            address_byte <= 1'b1;
            slave_read <= 1'b0;
        end else if (!running) begin
            scl_previous <= 1'b1;
            sda_previous <= 1'b1;
            bus_active <= 1'b0;
            bit_count <= 4'd0;
            address_byte <= 1'b1;
            slave_read <= 1'b0;
        end else begin
            scl_previous <= iic_scl;
            sda_previous <= iic_sda;
            if (bus_start) begin
                bus_active <= 1'b1;
                bit_count <= 4'd0;
                address_byte <= 1'b1;
                slave_read <= 1'b0;
            end else if (bus_stop) begin
                bus_active <= 1'b0;
            end else if (bus_active && scl_rising) begin
                if (bit_count == 4'd8) begin
                    bit_count <= 4'd0;
                    address_byte <= 1'b0;
                end else begin
                    bit_count <= bit_count + 1'b1;
                    if (address_byte && bit_count == 4'd7)
                        slave_read <= iic_sda;
                end
            end
        end
    end

    localparam integer TIMEOUT_WIDTH = INIT_TIMEOUT_CYCLES > 1 ? $clog2(INIT_TIMEOUT_CYCLES) : 1;
    reg [TIMEOUT_WIDTH-1:0] timeout_count;
    // Separate sticky cause bits remain available to a debugger/logic analyzer.
    reg nack_error;
    reg timeout_error;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) begin
            init_done <= 1'b0;
            init_error <= 1'b0;
            nack_error <= 1'b0;
            timeout_error <= 1'b0;
            timeout_count <= {TIMEOUT_WIDTH{1'b0}};
        end else if (!reset_cfg_n) begin
            timeout_count <= {TIMEOUT_WIDTH{1'b0}};
        end else if (!init_done && !init_error) begin
            if (nack_now) begin
                init_error <= 1'b1;
                nack_error <= 1'b1;
            end else if (timeout_count == INIT_TIMEOUT_CYCLES - 1) begin
                init_error <= 1'b1;
                timeout_error <= 1'b1;
            end else if (running && vendor_done) begin
                init_done <= 1'b1;
            end else begin
                timeout_count <= timeout_count + 1'b1;
            end
        end
    end
endmodule
