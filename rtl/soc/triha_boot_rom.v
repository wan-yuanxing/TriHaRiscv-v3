/* TriHa synchronous read-only 8KiB boot window. */
module triha_boot_rom #(
    parameter INIT_FILE = "rom.hex"
) (
    input  wire        clk_i,
    input  wire        inst_en_i,
    input  wire [9:0]  inst_addr_i,
    output reg  [63:0] inst_rdata_o,
    input  wire        data_en_i,
    input  wire [9:0]  data_addr_i,
    output reg  [63:0] data_rdata_o /* synthesis syn_romstyle = "logic" */
);
    (* syn_romstyle = "block_rom" *) reg [63:0] memory [0:1023];
    // Separate immutable views let each read port use its intended resource.
    // Both views load the same complete image and retain synchronous enables.
    reg [63:0] data_memory [0:1023];
    initial begin
        $readmemh(INIT_FILE, memory);
        $readmemh(INIT_FILE, data_memory);
    end
    always @(posedge clk_i) begin
        if (inst_en_i) inst_rdata_o <= memory[inst_addr_i];
        if (data_en_i) data_rdata_o <= data_memory[data_addr_i];
    end
endmodule
