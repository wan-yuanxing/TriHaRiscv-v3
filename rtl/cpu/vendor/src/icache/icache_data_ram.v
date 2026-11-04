
module icache_data_ram
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input  [  9:0]  addr_i
    ,input  [ 63:0]  data_i
    ,input           wr_i

    // Outputs
    ,output [ 63:0]  data_o
);




//-----------------------------------------------------------------
// Single Port RAM 8KB
// Mode: Read First
//-----------------------------------------------------------------
reg [63:0]   ram [1023:0] /*verilator public*/;
reg [63:0]   ram_read_q;

// Synchronous write
always @ (posedge clk_i)
begin
    if (wr_i)
        ram[addr_i] <= data_i;
    ram_read_q <= ram[addr_i];
end

assign data_o = ram_read_q;



endmodule
