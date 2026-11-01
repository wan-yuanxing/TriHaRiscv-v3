/* TriHa synchronous local data fabric and pipelined instruction port.
 * Only accepted requests have side effects. Local reads respond in one cycle;
 * a slow UART write owns the port until its captured byte has been accepted.
 * A one-entry instruction request slot absorbs same-word write collisions;
 * its ready signal depends on registered occupancy, not the data request.
 * Reset is coordinated with the CPU; memory contents survive reset. */
`include "soc_map.vh"
module triha_soc_memory #(
    parameter ROM_FILE = "rom.hex",
    parameter SRAM_FILE = "sram.hex",
    parameter integer UART_DIVISOR = (`TRIHA_CLOCK_HZ + `TRIHA_UART_BAUD/2) / `TRIHA_UART_BAUD
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        inst_req_i,
    input  wire [31:0] inst_addr_i,
    output wire        inst_accept_o,
    output reg         inst_valid_o,
    output reg         inst_error_o,
    output wire [63:0] inst_rdata_o,
    input  wire [31:0] data_addr_i,
    input  wire [31:0] data_wdata_i,
    input  wire        data_re_i,
    input  wire [3:0]  data_wstrb_i,
    input  wire [10:0] data_req_tag_i,
    input  wire        data_invalidate_i,
    input  wire        data_writeback_i,
    input  wire        data_flush_i,
    output wire        data_accept_o,
    output reg         data_ack_o,
    output reg         data_error_o,
    output wire [31:0] data_rdata_o,
    output reg  [10:0] data_resp_tag_o,
    output wire        uart_tx_o,
    output reg         done_o,
    output reg  [7:0]  exit_code_o
);
    reg uart_pending_q;
    reg [7:0] uart_byte_q;
    reg [31:0] mmio_data_q;
    reg [3:0] read_select_q;
    reg inst_sram_q, inst_rom_q;
    reg inst_pending_q;
    reg [11:0] inst_word_q;
    reg [31:0] cycle_q;
    // Only a valid SRAM collision can occupy the slot. Its target is implicit;
    // retain the word address rather than carrying another full address decode.
    wire [11:0] inst_service_word = inst_pending_q ? inst_word_q : inst_addr_i[14:3];
    wire i_rom = !inst_pending_q && inst_addr_i >= `TRIHA_ROM_BASE && inst_addr_i < `TRIHA_ROM_BASE + `TRIHA_ROM_BYTES;
    wire i_sram = inst_pending_q || (inst_addr_i >= `TRIHA_SRAM_BASE && inst_addr_i < `TRIHA_SRAM_BASE + `TRIHA_SRAM_BYTES);
    wire d_rom = data_addr_i >= `TRIHA_ROM_BASE && data_addr_i < `TRIHA_ROM_BASE + `TRIHA_ROM_BYTES;
    wire d_sram = data_addr_i >= `TRIHA_SRAM_BASE && data_addr_i < `TRIHA_SRAM_BASE + `TRIHA_SRAM_BYTES;
    wire d_request = data_re_i || (|data_wstrb_i) || data_invalidate_i || data_writeback_i || data_flush_i;
    wire d_uart = data_addr_i == `TRIHA_UART_BASE || data_addr_i == `TRIHA_UART_BASE + 4;
    wire d_system = data_addr_i == `TRIHA_SYSTEM_BASE || data_addr_i == `TRIHA_SYSTEM_BASE + 4 || data_addr_i == `TRIHA_SYSTEM_BASE + 8;
    // Config generation verifies disjoint target windows. A known SRAM hit
    // needs only these local checks; MMIO/ROM decode must not feed its write
    // enable or the same-word instruction-collision backpressure path.
    (* syn_keep = 1 *) wire d_local_bad = (data_addr_i[1:0] != 2'b00) ||
                 (data_re_i && (|data_wstrb_i)) || data_invalidate_i || data_writeback_i || data_flush_i;
    wire d_bad = d_local_bad ||
                 !(d_rom || d_sram || d_uart || d_system) ||
                 (d_rom && (|data_wstrb_i)) ||
                 (d_uart && ((data_addr_i == `TRIHA_UART_BASE && data_re_i) ||
                             (data_addr_i == `TRIHA_UART_BASE + 4 && (|data_wstrb_i)))) ||
                 (d_system && (|data_wstrb_i) && data_addr_i != `TRIHA_SYSTEM_BASE + 4);
    wire d_fire = data_accept_o && d_request;
    // Qualify the physical SRAM command locally. General maintenance requests
    // still use d_fire for their error response, but never enable this RAM.
    // Keep the original expression for unknown controls in RTL simulation.
    reg sram_data_command;
    always @* begin
        sram_data_command = d_fire && d_sram && !d_local_bad;
        case (data_invalidate_i | data_writeback_i | data_flush_i)
            1'b1: sram_data_command = 1'b0;
            1'b0: begin
                case ({data_re_i, |data_wstrb_i})
                    2'b00, 2'b11: sram_data_command = 1'b0;
                    2'b01, 2'b10: sram_data_command = data_accept_o && d_sram &&
                                                           (data_addr_i[1:0] == 2'b00);
                    default: sram_data_command = d_fire && d_sram && !d_local_bad;
                endcase
            end
            default: sram_data_command = d_fire && d_sram && !d_local_bad;
        endcase
    end
    wire d_write = sram_data_command && (|data_wstrb_i);
    wire collision = d_write && i_sram && inst_service_word == data_addr_i[14:3];
    assign data_accept_o = rst_ni && !uart_pending_q;
    assign inst_accept_o = rst_ni && !inst_pending_q;
    wire i_fire = inst_req_i && inst_accept_o;
    wire i_service = rst_ni && (inst_pending_q || i_fire) && !collision;
    // A decoded ROM fetch cannot collide with a SRAM write. Preserve the
    // old four-state expression when the ROM decode is not known true.
    reg rom_inst_service;
    always @* begin
        case (i_rom)
            1'b1: rom_inst_service = rst_ni && i_fire;
            default: rom_inst_service = i_service && i_rom;
        endcase
    end
    // These two selects already have an asynchronous reset branch. Their
    // update decision need not duplicate reset gating from external accepts.
    wire select_write = !uart_pending_q && d_request && d_sram &&
                        !d_local_bad && (|data_wstrb_i);
    wire select_collision = select_write && i_sram &&
                            inst_service_word == data_addr_i[14:3];
    wire select_service_raw = (inst_pending_q || (inst_req_i && !inst_pending_q)) &&
                              !select_collision;
    reg select_service;
    always @* begin
        case (rst_ni)
            1'b0, 1'b1: select_service = select_service_raw;
            default: select_service = i_service;
        endcase
    end
    wire [63:0] ram_inst, ram_data, rom_inst, rom_data;
    wire [7:0] ram_we = d_write ? (data_addr_i[2] ? {data_wstrb_i, 4'b0} : {4'b0, data_wstrb_i}) : 8'b0;
    triha_sram #(.INIT_FILE(SRAM_FILE)) u_sram (
        .clk_i(clk_i), .inst_en_i(i_service && i_sram), .inst_addr_i(inst_service_word), .inst_rdata_o(ram_inst),
        .data_en_i(sram_data_command), .data_addr_i(data_addr_i[14:3]),
        .data_wdata_i({data_wdata_i, data_wdata_i}), .data_wstrb_i(ram_we), .data_rdata_o(ram_data)
    );
    triha_boot_rom #(.INIT_FILE(ROM_FILE)) u_rom (
        .clk_i(clk_i), .inst_en_i(rom_inst_service), .inst_addr_i(inst_addr_i[12:3]), .inst_rdata_o(rom_inst),
        .data_en_i(d_fire && d_rom && !d_bad), .data_addr_i(data_addr_i[12:3]), .data_rdata_o(rom_data)
    );
    assign inst_rdata_o = inst_rom_q ? rom_inst : inst_sram_q ? ram_inst : 64'b0;
    wire uart_ready;
    wire uart_write = d_fire && !d_bad && !data_re_i && data_addr_i == `TRIHA_UART_BASE && data_wstrb_i[0];
    triha_uart_tx #(.DIVISOR(UART_DIVISOR)) u_uart (
        .clk_i(clk_i), .rst_ni(rst_ni), .valid_i(uart_pending_q), .data_i(uart_byte_q),
        .ready_o(uart_ready), .tx_o(uart_tx_o)
    );
    // SRAM and ROM outputs are clocked in the memory modules; these selects
    // and the response-valid/tag are captured at that same acceptance edge.
    // Decode bank/target before the synchronous RAM edge. The MMIO register
    // is zero on every memory response, so all response sources can merge in
    // parallel without a late RAM-word mux followed by a target-priority mux.
    assign data_rdata_o = ({32{read_select_q[0]}} & ram_data[31:0]) |
                          ({32{read_select_q[1]}} & ram_data[63:32]) |
                          ({32{read_select_q[2]}} & rom_data[31:0]) |
                          ({32{read_select_q[3]}} & rom_data[63:32]) | mmio_data_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            inst_valid_o <= 0; inst_error_o <= 0; inst_rom_q <= 0; inst_sram_q <= 0;
            inst_pending_q <= 0; inst_word_q <= 0;
            uart_pending_q <= 0; uart_byte_q <= 0;
            data_ack_o <= 0; data_error_o <= 0; data_resp_tag_o <= 0;
            mmio_data_q <= 0; read_select_q <= 0;
            done_o <= 0; exit_code_o <= 0; cycle_q <= 0;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            inst_valid_o <= i_service;
            inst_error_o <= i_service && !(i_rom || i_sram);
            if (select_service) begin inst_rom_q <= i_rom; inst_sram_q <= i_sram; end
            if (inst_pending_q) begin
                if (i_service) inst_pending_q <= 0;
            end else if (i_fire && collision) begin
                inst_pending_q <= 1;
                inst_word_q <= inst_addr_i[14:3];
            end
            data_ack_o <= 0;
            data_error_o <= 0;
            if (d_fire) begin
                data_ack_o <= !uart_write;
                data_error_o <= d_bad;
                data_resp_tag_o <= data_req_tag_i;
                read_select_q <= {d_rom && data_re_i && !d_bad && data_addr_i[2],
                                  d_rom && data_re_i && !d_bad && !data_addr_i[2],
                                  d_sram && data_re_i && !d_bad && data_addr_i[2],
                                  d_sram && data_re_i && !d_bad && !data_addr_i[2]};
                mmio_data_q <= 0;
                if (!d_bad && data_re_i) begin
                    if (data_addr_i == `TRIHA_UART_BASE + 4) mmio_data_q <= {31'b0, uart_ready};
                    else if (data_addr_i == `TRIHA_SYSTEM_BASE) mmio_data_q <= `TRIHA_SYSTEM_ID;
                    else if (data_addr_i == `TRIHA_SYSTEM_BASE + 4) mmio_data_q <= {23'b0, done_o, exit_code_o};
                    else if (data_addr_i == `TRIHA_SYSTEM_BASE + 8) mmio_data_q <= cycle_q;
                end
                if (!d_bad && !data_re_i && data_addr_i == `TRIHA_SYSTEM_BASE + 4 && data_wstrb_i[0]) begin
                    done_o <= 1;
                    exit_code_o <= data_wdata_i[7:0];
                end
                if (uart_write) begin
                    uart_pending_q <= 1;
                    uart_byte_q <= data_wdata_i[7:0];
                end
            end else if (uart_pending_q && uart_ready) begin
                data_ack_o <= 1;
                uart_pending_q <= 0;
            end
        end
    end
endmodule
