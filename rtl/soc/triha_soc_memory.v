/* TriHa synchronous local data fabric and pipelined instruction port.
 * Only accepted requests have side effects. Local reads respond in one cycle;
 * a slow UART write owns the port until its captured byte has been accepted.
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
    reg upper_word_q, sram_q, rom_q;
    reg inst_sram_q, inst_rom_q;
    reg [31:0] cycle_q;
    wire i_rom = inst_addr_i >= `TRIHA_ROM_BASE && inst_addr_i < `TRIHA_ROM_BASE + `TRIHA_ROM_BYTES;
    wire i_sram = inst_addr_i >= `TRIHA_SRAM_BASE && inst_addr_i < `TRIHA_SRAM_BASE + `TRIHA_SRAM_BYTES;
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
    wire d_write = d_fire && d_sram && !d_local_bad && (|data_wstrb_i);
    wire collision = d_write && i_sram && inst_addr_i[14:3] == data_addr_i[14:3];
    assign data_accept_o = rst_ni && !uart_pending_q;
    assign inst_accept_o = rst_ni && !collision;
    wire i_fire = inst_req_i && inst_accept_o;
    wire [63:0] ram_inst, ram_data, rom_inst, rom_data;
    wire [7:0] ram_we = d_write ? (data_addr_i[2] ? {data_wstrb_i, 4'b0} : {4'b0, data_wstrb_i}) : 8'b0;
    triha_sram #(.INIT_FILE(SRAM_FILE)) u_sram (
        .clk_i(clk_i), .inst_en_i(i_fire && i_sram), .inst_addr_i(inst_addr_i[14:3]), .inst_rdata_o(ram_inst),
        .data_en_i(d_fire && d_sram && !d_local_bad), .data_addr_i(data_addr_i[14:3]),
        .data_wdata_i({data_wdata_i, data_wdata_i}), .data_wstrb_i(ram_we), .data_rdata_o(ram_data)
    );
    triha_boot_rom #(.INIT_FILE(ROM_FILE)) u_rom (
        .clk_i(clk_i), .inst_en_i(i_fire && i_rom), .inst_addr_i(inst_addr_i[12:3]), .inst_rdata_o(rom_inst),
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
    assign data_rdata_o = sram_q ? (upper_word_q ? ram_data[63:32] : ram_data[31:0]) :
                          rom_q ? (upper_word_q ? rom_data[63:32] : rom_data[31:0]) : mmio_data_q;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            inst_valid_o <= 0; inst_error_o <= 0; inst_rom_q <= 0; inst_sram_q <= 0;
            uart_pending_q <= 0; uart_byte_q <= 0;
            data_ack_o <= 0; data_error_o <= 0; data_resp_tag_o <= 0;
            mmio_data_q <= 0; upper_word_q <= 0; sram_q <= 0; rom_q <= 0;
            done_o <= 0; exit_code_o <= 0; cycle_q <= 0;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            inst_valid_o <= i_fire;
            inst_error_o <= i_fire && !(i_rom || i_sram);
            if (i_fire) begin inst_rom_q <= i_rom; inst_sram_q <= i_sram; end
            data_ack_o <= 0;
            data_error_o <= 0;
            if (d_fire) begin
                data_ack_o <= !uart_write;
                data_error_o <= d_bad;
                data_resp_tag_o <= data_req_tag_i;
                upper_word_q <= data_addr_i[2];
                sram_q <= d_sram && data_re_i && !d_bad;
                rom_q <= d_rom && data_re_i && !d_bad;
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
