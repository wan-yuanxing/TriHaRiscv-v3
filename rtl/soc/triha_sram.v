/* TriHa synchronous 32KiB unified SRAM. No reset on the memory array.
 * Instruction and data ports are read-first; the fabric excludes same-word
 * instruction/write collisions. Native block mapping is checked by PDS. */
module triha_sram #(
    parameter INIT_FILE = "sram.hex"
) (
    input  wire        clk_i,
    input  wire        inst_en_i,
    input  wire [11:0] inst_addr_i,
    output reg  [63:0] inst_rdata_o,
    input  wire        data_en_i,
    input  wire [11:0] data_addr_i,
    input  wire [63:0] data_wdata_i,
    input  wire [7:0]  data_wstrb_i,
    output reg  [63:0] data_rdata_o
);
    (* syn_ramstyle = "block_ram" *) reg [63:0] memory [0:4095];
    integer lane;
    initial $readmemh(INIT_FILE, memory);
    always @(posedge clk_i) begin
        if (inst_en_i)
            inst_rdata_o <= memory[inst_addr_i];
    end
    always @(posedge clk_i) begin
        if (data_en_i) begin
            for (lane = 0; lane < 8; lane = lane + 1)
                if (data_wstrb_i[lane])
                    memory[data_addr_i][lane*8 +: 8] <= data_wdata_i[lane*8 +: 8];
            data_rdata_o <= memory[data_addr_i];
        end
    end
endmodule
