`timescale 1ns/1ps
// Independent byte-addressed sparse memory for the HMIC simplified native port.
// No DUT pattern function is used: reads return the bytes actually written.
module ddr_native_model #(
    parameter integer MEMORY_SLOTS = 512
) (
    input wire clk, reset_n,
    input integer fault_mode,
    input wire [27:0] address_mask,
    input wire delayed,
    input wire [27:0] axi_awaddr,
    input wire axi_awvalid,
    input wire [3:0] axi_awlen, axi_awuser_id,
    output wire axi_awready,
    input wire [255:0] axi_wdata,
    input wire [31:0] axi_wstrb,
    output wire axi_wready,
    output wire [3:0] axi_wusero_id,
    output wire axi_wusero_last,
    input wire [27:0] axi_araddr,
    input wire axi_arvalid,
    input wire [3:0] axi_arlen, axi_aruser_id,
    output wire axi_arready,
    output reg [255:0] axi_rdata,
    output reg [3:0] axi_rid,
    output reg axi_rlast, axi_rvalid,
    output integer write_beats, read_beats, earliest_beats, masked_beats,
    output integer aw_commands, ar_commands, write_gaps
);
    reg [27:0] tags [0:MEMORY_SLOTS-1];
    reg [7:0] bytes [0:MEMORY_SLOTS*32-1];
    integer used_slots, ticks;
    reg writing, reading, extra_pending;
    reg [27:0] write_addr, read_addr;
    reg [3:0] write_id, read_id;
    integer write_index, write_length, read_index, read_length, read_delay;
    wire accept_aw = axi_awvalid && axi_awready;
    wire accept_ar = axi_arvalid && axi_arready;
    wire write_active = writing || accept_aw;
    wire [3:0] active_write_id = writing ? write_id : axi_awuser_id;
    wire active_write_last = writing ? (write_index == write_length) : (axi_awlen == 0);
    wire corrupt_write_id = fault_mode == 2 ||
                           (fault_mode == 17 && writing && write_length != 0 && active_write_last);
    wire corrupt_write_last = fault_mode == 3 ||
                             (fault_mode == 15 && writing && write_index == 1 && write_length > 1);
    assign axi_awready = reset_n && !writing && !reading && !extra_pending &&
                         (fault_mode != 6) && (!delayed || ticks % 5 == 1);
    assign axi_arready = reset_n && !writing && !reading && !extra_pending &&
                         (fault_mode != 8) && (!delayed || ticks % 7 == 2);
    // The acceptance-cycle beat is always enabled, deliberately testing the
    // earliest legal WREADY. Later beats have gaps when delayed is asserted.
    assign axi_wready = reset_n && write_active && (fault_mode != 7) &&
                        ((accept_aw && fault_mode != 21) ||
                         (writing && (!delayed || ticks % 4 != 0)));
    assign axi_wusero_id = fault_mode == 26 ? 4'bxxxx : active_write_id ^ (corrupt_write_id ? 4'h1 : 4'h0);
    assign axi_wusero_last = fault_mode == 27 ? 1'bx : active_write_last ^ corrupt_write_last;

    function automatic [255:0] stored_beat(input [27:0] address);
        integer slot, byte_number;
        begin
            stored_beat = 0;
            for (slot = 0; slot < used_slots; slot = slot + 1)
                if (tags[slot] == (address & address_mask))
                    for (byte_number = 0; byte_number < 32; byte_number = byte_number + 1)
                        stored_beat[byte_number*8 +: 8] = bytes[slot*32 + byte_number];
        end
    endfunction

    task automatic store_beat(input [27:0] address);
        integer slot, found, byte_number;
        begin
            found = -1;
            for (slot = 0; slot < used_slots; slot = slot + 1)
                if (tags[slot] == (address & address_mask)) found = slot;
            if (found < 0) begin
                if (used_slots == MEMORY_SLOTS) $fatal(1, "MODEL sparse memory exhausted");
                found = used_slots;
                tags[found] = address & address_mask;
                used_slots = used_slots + 1;
                for (byte_number = 0; byte_number < 32; byte_number = byte_number + 1)
                    bytes[found*32 + byte_number] = 0;
            end
            for (byte_number = 0; byte_number < 32; byte_number = byte_number + 1)
                if (axi_wstrb[byte_number] || fault_mode == 13)
                    bytes[found*32 + byte_number] = axi_wdata[byte_number*8 +: 8];
        end
    endtask

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ticks <= 0; used_slots = 0;
            writing <= 0; reading <= 0; extra_pending <= 0;
            write_addr <= 0; read_addr <= 0; write_id <= 0; read_id <= 0;
            write_index <= 0; write_length <= 0;
            read_index <= 0; read_length <= 0; read_delay <= 0;
            axi_rdata <= 0; axi_rid <= 0; axi_rlast <= 0; axi_rvalid <= 0;
            write_beats <= 0; read_beats <= 0; earliest_beats <= 0;
            masked_beats <= 0; aw_commands <= 0; ar_commands <= 0; write_gaps <= 0;
        end else begin
            ticks <= ticks + 1;
            axi_rvalid <= 0;
            if (accept_aw) begin
                if (axi_awaddr[2:0] != 0 || axi_awaddr[9:0] + (axi_awlen+1)*8 > 1024)
                    $fatal(1, "MODEL invalid/cross-page AW address=%h len=%d", axi_awaddr, axi_awlen);
                aw_commands <= aw_commands + 1;
                writing <= 1; write_addr <= axi_awaddr;
                write_id <= axi_awuser_id; write_index <= 0; write_length <= axi_awlen;
            end
            if (writing && !axi_wready) write_gaps <= write_gaps + 1;
            if (axi_wready) begin
                store_beat(writing ? write_addr + write_index*8 : axi_awaddr);
                write_beats <= write_beats + 1;
                if (axi_wstrb != 32'hffffffff) masked_beats <= masked_beats + 1;
                if (accept_aw) earliest_beats <= earliest_beats + 1;
                if (active_write_last) writing <= 0;
                else write_index <= writing ? write_index + 1 : 1;
            end
            if (accept_ar) begin
                if (axi_araddr[2:0] != 0 || axi_araddr[9:0] + (axi_arlen+1)*8 > 1024)
                    $fatal(1, "MODEL invalid/cross-page AR address=%h len=%d", axi_araddr, axi_arlen);
                ar_commands <= ar_commands + 1;
                reading <= 1; read_addr <= axi_araddr; read_id <= axi_aruser_id;
                read_index <= 0; read_length <= axi_arlen;
                read_delay <= delayed ? 5 : 0;
            end
            if (reading) begin
                if (read_delay != 0) read_delay <= read_delay - 1;
                else if (fault_mode != 9 && !(fault_mode == 10 && read_index == read_length) &&
                         !(fault_mode == 19 && read_length != 0 && read_index == read_length)) begin
                    axi_rvalid <= 1;
                    axi_rdata <= stored_beat(read_addr + read_index*8) ^ ((fault_mode == 1) ? 256'h1 :
                                 (fault_mode == 14) ? (256'h1 << 255) : 256'h0);
                    axi_rid <= read_id ^ ((fault_mode == 4 || (fault_mode == 18 && read_length != 0 &&
                                read_index == read_length)) ? 4'h1 : 4'h0);
                    axi_rlast <= (read_index == read_length) ^ (fault_mode == 5 ||
                                 (fault_mode == 16 && read_length > 1 && read_index == 1));
                    if (fault_mode == 23) axi_rdata[255] <= 1'bx;
                    if (fault_mode == 24) axi_rid <= 4'bxxxx;
                    if (fault_mode == 25) axi_rlast <= 1'bx;
                    read_beats <= read_beats + 1;
                    read_delay <= delayed ? (ticks % 3) : 0;
                    if (read_index == read_length) begin
                        reading <= 0;
                        if (fault_mode == 11 || (fault_mode == 20 && read_length != 0)) extra_pending <= 1;
                    end else read_index <= read_index + 1;
                end
            end
            if (extra_pending || (fault_mode == 12 && ticks == 8) || (fault_mode == 22 && ticks == 4)) begin
                axi_rvalid <= 1; axi_rlast <= 1; axi_rid <= read_id; axi_rdata <= 0;
                extra_pending <= 0;
            end
        end
    end
endmodule
