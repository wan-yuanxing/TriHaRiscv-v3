`timescale 1ns/1ps

// RX adapter around the unmodified ms7200_ctl and iic_dri reference sources.
// clk_cfg is 10 MHz. The board must finish TX initialization before releasing
// this reset on their shared bus. This module never drives the PHY reset pin.
// init_done: all 300 boot writes completed (ACK + STOP), independent of source.
// link_configured: sticky completion of the vendor's seven post-event writes;
// it is NOT source presence, clock lock, or validation of the live video mode.
// status_word: raw latest bytes {209F,209E,209D,209C}, with no assumed units.
module hdmi_rx_init #(
    parameter integer INIT_TIMEOUT_CYCLES = 10_000_000
) (
    input wire clk_cfg,
    input wire reset_n,
    output wire iic_scl,
    inout wire iic_sda,
    output reg init_done,
    output reg link_configured,
    output reg init_error,
    output reg [31:0] status_word
);
    `include "video_edid.vh"

    (* syn_preserve = 1 *) reg [1:0] reset_pipe;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) reset_pipe <= 2'b00;
        else reset_pipe <= {reset_pipe[0], 1'b1};
    end
    wire reset_cfg_n = reset_pipe[1];

    // iic_dri does not reset its trans_en, busy, SCL or T_WR state. Drain one
    // isolated dummy write, then rearm its FSM/divider before exposing the bus.
    // 1536 clocks cover 4*9*25 bit clocks + START/STOP + the10-clock T_WR.
    // ms7200_ctl stays reset throughout; its unreset busy history settles too.
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
                    end else startup_count <= startup_count + 1'b1;
                end
                REARM: begin
                    if (startup_count == 11'd3) startup_state <= RUN;
                    else startup_count <= startup_count + 1'b1;
                end
                default: startup_count <= 11'd0;
            endcase
        end
    end

    wire running = reset_cfg_n && startup_state == RUN && !init_error;
    wire driver_reset_n = reset_cfg_n && startup_state != REARM;
    wire vendor_done, trigger, write_nread;
    wire [7:0] device_id, vendor_write_data, read_data;
    wire [15:0] register_addr;
    wire busy, byte_over, scl_out, sda_out, sda_out_en;

    // Only EDID RAM data is replaced. The entire vendor sequence, including
    // the duplicated first8 bytes and000A/000C bracketing writes, is retained.
    wire [7:0] write_data = register_addr[15:8] == 8'h0d ?
                            video_edid_byte(register_addr[7:0]) : vendor_write_data;

    reg busy_previous;
    reg transaction_write;
    reg [15:0] transaction_addr;
    wire transaction_complete = running && busy_previous && !busy;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) begin
            busy_previous <= 1'b0;
            transaction_write <= 1'b1;
            transaction_addr <= 16'd0;
        end else if (!running) begin
            busy_previous <= 1'b0;
            transaction_write <= 1'b1;
            transaction_addr <= 16'd0;
        end else begin
            busy_previous <= busy;
            if (busy && !busy_previous) begin
                transaction_write <= write_nread;
                transaction_addr <= register_addr;
            end
        end
    end

    // The vendor event detector needs a00 baseline before209E[1:0] becomes10.
    // Its freq_rec_2d has no reset and an already-present source can otherwise
    // be missed forever. Prime ONLY the controller's first209E sample to zero;
    // keep the real serial byte in status_word. Hold the adapter through both
    // byte_over and busy_falling consumption edges, then pass every later byte.
    // This does not claim that any209x bit describes actual live video lock.
    reg first_status_seen;
    wire [7:0] ctl_read_data = !first_status_seen && !transaction_write &&
                              transaction_addr == 16'h209e ? 8'h00 : read_data;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) begin
            first_status_seen <= 1'b0;
            status_word <= 32'd0;
        end else if (running) begin
            if (transaction_complete && !transaction_write && transaction_addr == 16'h209e)
                first_status_seen <= 1'b1;
            if (byte_over && !transaction_write) begin
                case (transaction_addr)
                    16'h209c: status_word[7:0] <= read_data;
                    16'h209d: status_word[15:8] <= read_data;
                    16'h209e: status_word[23:16] <= read_data;
                    16'h209f: status_word[31:24] <= read_data;
                    default: ;
                endcase
            end
        end
    end

    ms7200_ctl u_ctl (
        .clk(clk_cfg), .rstn(running), .init_over(vendor_done),
        .device_id(device_id), .iic_trig(trigger), .w_r(write_nread),
        .addr(register_addr), .data_in(vendor_write_data), .busy(busy),
        .data_out(ctl_read_data), .byte_over(byte_over)
    );

    iic_dri #(
        .CLK_FRE(27'd10_000_000), .IIC_FREQ(20'd400_000),
        .T_WR(10'd1), .ADDR_BYTE(2'd2), .LEN_WIDTH(8'd3), .DATA_BYTE(2'd1)
    ) u_iic (
        .clk(clk_cfg), .rstn(driver_reset_n),
        .pluse(startup_state == DRAIN ? startup_count == 11'd1 : running && trigger),
        .device_id(device_id), .w_r(startup_state == DRAIN ? 1'b1 : write_nread),
        .byte_len(4'd1), .addr(register_addr), .data_in(write_data),
        .busy(busy), .byte_over(byte_over), .data_out(read_data),
        .scl(scl_out), .sda_in(running ? iic_sda : 1'b1),
        .sda_out(sda_out), .sda_out_en(sda_out_en)
    );

    // Vendor SCL is push-pull and has no clock stretching support. A one on
    // SDA always releases the pad, including reset, startup drain, and errors.
    assign iic_scl = reset_n && running ? scl_out : 1'b1;
    assign iic_sda = reset_n && running && sda_out_en && !sda_out ? 1'b0 : 1'bz;

    // Observe actual bus ACK slots: the reference driver ignores slave NACK.
    // Exclude read data's ninth bit, which is the master's intentional NACK.
    reg scl_previous, sda_previous, bus_active, address_byte, slave_read;
    reg [3:0] bit_count;
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
                    if (address_byte && bit_count == 4'd7) slave_read <= iic_sda;
                end
            end
        end
    end

    localparam integer TIMEOUT_WIDTH = INIT_TIMEOUT_CYCLES > 1 ? $clog2(INIT_TIMEOUT_CYCLES) : 1;
    reg [TIMEOUT_WIDTH-1:0] timeout_count;
    reg [8:0] completed_boot_writes;
    reg probe_complete;
    reg nack_error, timeout_error;
    always @(posedge clk_cfg or negedge reset_n) begin
        if (!reset_n) begin
            init_done <= 1'b0;
            link_configured <= 1'b0;
            init_error <= 1'b0;
            nack_error <= 1'b0;
            timeout_error <= 1'b0;
            timeout_count <= {TIMEOUT_WIDTH{1'b0}};
            completed_boot_writes <= 9'd0;
            probe_complete <= 1'b0;
        end else if (!reset_cfg_n) begin
            timeout_count <= {TIMEOUT_WIDTH{1'b0}};
        end else if (!init_error) begin
            if (nack_now) begin
                init_error <= 1'b1;
                nack_error <= 1'b1;
            end else if (!init_done && timeout_count == INIT_TIMEOUT_CYCLES - 1) begin
                init_error <= 1'b1;
                timeout_error <= 1'b1;
            end else begin
                if (!init_done) timeout_count <= timeout_count + 1'b1;
                if (transaction_complete) begin
                    if (!transaction_write && transaction_addr == 16'h0003 && read_data == 8'h5a)
                        probe_complete <= 1'b1;
                    // Boot includes cmd9:0003=C3; do not exclude this address.
                    if (probe_complete && transaction_write && !init_done) begin
                        completed_boot_writes <= completed_boot_writes + 1'b1;
                        if (completed_boot_writes == 9'd299) init_done <= 1'b1;
                    end
                end
                if (running && vendor_done) link_configured <= 1'b1;
            end
        end
    end
endmodule
