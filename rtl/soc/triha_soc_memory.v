/* TriHa one-outstanding local data fabric and pipelined instruction port.
 * Only accepted requests have side effects. All responses are registered.
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
    output reg  [31:0] data_rdata_o,
    output reg  [10:0] data_resp_tag_o,
    output wire        uart_tx_o,
    output reg         done_o,
    output reg  [7:0]  exit_code_o
);
    localparam [1:0] IDLE = 0, EXECUTE = 1, RESPONSE = 2;
    reg [1:0] state_q;
    reg [31:0] addr_q, wdata_q;
    reg [3:0] wstrb_q;
    reg [10:0] tag_q;
    reg read_q, error_q, sram_q, rom_q;
    reg inst_sram_q, inst_rom_q;
    reg [31:0] cycle_q;
    wire i_rom = inst_addr_i >= `TRIHA_ROM_BASE && inst_addr_i < `TRIHA_ROM_BASE + `TRIHA_ROM_BYTES;
    wire i_sram = inst_addr_i >= `TRIHA_SRAM_BASE && inst_addr_i < `TRIHA_SRAM_BASE + `TRIHA_SRAM_BYTES;
    wire d_rom = data_addr_i >= `TRIHA_ROM_BASE && data_addr_i < `TRIHA_ROM_BASE + `TRIHA_ROM_BYTES;
    wire d_sram = data_addr_i >= `TRIHA_SRAM_BASE && data_addr_i < `TRIHA_SRAM_BASE + `TRIHA_SRAM_BYTES;
    wire d_request = data_re_i || (|data_wstrb_i) || data_invalidate_i || data_writeback_i || data_flush_i;
    wire d_uart = data_addr_i == `TRIHA_UART_BASE || data_addr_i == `TRIHA_UART_BASE + 4;
    wire d_system = data_addr_i == `TRIHA_SYSTEM_BASE || data_addr_i == `TRIHA_SYSTEM_BASE + 4 || data_addr_i == `TRIHA_SYSTEM_BASE + 8;
    wire d_bad = (data_addr_i[1:0] != 2'b00) || (data_re_i && (|data_wstrb_i)) || data_invalidate_i || data_writeback_i || data_flush_i ||
                 !(d_rom || d_sram || d_uart || d_system) ||
                 (d_rom && (|data_wstrb_i)) ||
                 (d_uart && ((data_addr_i == `TRIHA_UART_BASE && data_re_i) ||
                             (data_addr_i == `TRIHA_UART_BASE + 4 && (|data_wstrb_i)))) ||
                 (d_system && (|data_wstrb_i) && data_addr_i != `TRIHA_SYSTEM_BASE + 4);
    wire d_fire = data_accept_o && d_request;
    wire d_write = d_fire && d_sram && !d_bad && (|data_wstrb_i);
    wire collision = d_write && i_sram && inst_addr_i[14:3] == data_addr_i[14:3];
    assign data_accept_o = rst_ni && state_q == IDLE;
    assign inst_accept_o = rst_ni && !collision;
    wire i_fire = inst_req_i && inst_accept_o;
    wire [63:0] ram_inst, ram_data, rom_inst, rom_data;
    wire [7:0] ram_we = d_write ? (data_addr_i[2] ? {data_wstrb_i, 4'b0} : {4'b0, data_wstrb_i}) : 8'b0;
    triha_sram #(.INIT_FILE(SRAM_FILE)) u_sram (
        .clk_i(clk_i), .inst_en_i(i_fire && i_sram), .inst_addr_i(inst_addr_i[14:3]), .inst_rdata_o(ram_inst),
        .data_en_i(d_fire && d_sram && !d_bad), .data_addr_i(data_addr_i[14:3]),
        .data_wdata_i({data_wdata_i, data_wdata_i}), .data_wstrb_i(ram_we), .data_rdata_o(ram_data)
    );
    triha_boot_rom #(.INIT_FILE(ROM_FILE)) u_rom (
        .clk_i(clk_i), .inst_en_i(i_fire && i_rom), .inst_addr_i(inst_addr_i[12:3]), .inst_rdata_o(rom_inst),
        .data_en_i(d_fire && d_rom && !d_bad), .data_addr_i(data_addr_i[12:3]), .data_rdata_o(rom_data)
    );
    assign inst_rdata_o = inst_rom_q ? rom_inst : inst_sram_q ? ram_inst : 64'b0;
    wire uart_ready;
    wire uart_valid = state_q == EXECUTE && !error_q && !read_q && addr_q == `TRIHA_UART_BASE && wstrb_q[0];
    triha_uart_tx #(.DIVISOR(UART_DIVISOR)) u_uart (
        .clk_i(clk_i), .rst_ni(rst_ni), .valid_i(uart_valid), .data_i(wdata_q[7:0]),
        .ready_o(uart_ready), .tx_o(uart_tx_o)
    );
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            inst_valid_o <= 0; inst_error_o <= 0; inst_rom_q <= 0; inst_sram_q <= 0;
            state_q <= IDLE; data_ack_o <= 0; data_error_o <= 0; data_rdata_o <= 0; data_resp_tag_o <= 0;
            addr_q <= 0; wdata_q <= 0; wstrb_q <= 0; tag_q <= 0;
            read_q <= 0; error_q <= 0; sram_q <= 0; rom_q <= 0;
            done_o <= 0; exit_code_o <= 0; cycle_q <= 0;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            inst_valid_o <= i_fire;
            inst_error_o <= i_fire && !(i_rom || i_sram);
            if (i_fire) begin inst_rom_q <= i_rom; inst_sram_q <= i_sram; end
            data_ack_o <= 0;
            data_error_o <= 0;
            case (state_q)
                IDLE: if (d_fire) begin
                    addr_q <= data_addr_i; wdata_q <= data_wdata_i; wstrb_q <= data_wstrb_i;
                    tag_q <= data_req_tag_i; read_q <= data_re_i; error_q <= d_bad;
                    sram_q <= d_sram; rom_q <= d_rom; state_q <= EXECUTE;
                end
                EXECUTE: if (!uart_valid || uart_ready) begin
                    data_ack_o <= 1; data_error_o <= error_q; data_resp_tag_o <= tag_q;
                    data_rdata_o <= 0;
                    if (!error_q && read_q) begin
                        if (sram_q) data_rdata_o <= addr_q[2] ? ram_data[63:32] : ram_data[31:0];
                        else if (rom_q) data_rdata_o <= addr_q[2] ? rom_data[63:32] : rom_data[31:0];
                        else if (addr_q == `TRIHA_UART_BASE + 4) data_rdata_o <= {31'b0, uart_ready};
                        else if (addr_q == `TRIHA_SYSTEM_BASE) data_rdata_o <= `TRIHA_SYSTEM_ID;
                        else if (addr_q == `TRIHA_SYSTEM_BASE + 4) data_rdata_o <= {23'b0, done_o, exit_code_o};
                        else if (addr_q == `TRIHA_SYSTEM_BASE + 8) data_rdata_o <= cycle_q;
                    end
                    if (!error_q && !read_q && addr_q == `TRIHA_SYSTEM_BASE + 4 && wstrb_q[0]) begin
                        done_o <= 1; exit_code_o <= wdata_q[7:0];
                    end
                    state_q <= RESPONSE;
                end
                RESPONSE: state_q <= IDLE;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
