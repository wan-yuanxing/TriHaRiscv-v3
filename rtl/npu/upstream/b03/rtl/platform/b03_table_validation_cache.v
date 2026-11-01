// One same-session read-only POST-table CRC observation. Any accepted HOST
// write spanning that table invalidates it, even an eventual failed/masked one.
// This is a local diagnostic optimization, not a CPU/cache visibility fence.
module b03_table_validation_cache(
    input wire clk,rst_n,invalidate,
    input wire host_write_valid,input wire [31:0] host_write_offset,input wire [4:0] host_write_beats,
    input wire commit_valid,input wire [31:0] commit_base,commit_crc,commit_epoch,commit_version,
    input wire [31:0] query_base,query_crc,query_epoch,query_version,
    output wire hit,output reg valid,output reg [31:0] commits,invalidations
);
    reg [31:0] saved_base,saved_crc,saved_epoch,saved_version;
    wire [32:0] write_end={1'b0,host_write_offset}+({28'd0,host_write_beats}<<5);
    wire overlaps_old=host_write_valid&&host_write_beats!=0&&
        {1'b0,host_write_offset}<({1'b0,saved_base}+33'd1572864)&&write_end>{1'b0,saved_base};
    wire overlaps_new=host_write_valid&&host_write_beats!=0&&
        {1'b0,host_write_offset}<({1'b0,commit_base}+33'd1572864)&&write_end>{1'b0,commit_base};
    assign hit=rst_n&&valid&&!invalidate&&!overlaps_old&&saved_base==query_base&&saved_crc==query_crc&&
        saved_epoch==query_epoch&&saved_version==query_version&&query_epoch!=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin valid<=0;saved_base<=0;saved_crc<=0;saved_epoch<=0;saved_version<=0;commits<=0;invalidations<=0;end
        else begin
            if(commit_valid)begin
                saved_base<=commit_base;saved_crc<=commit_crc;saved_epoch<=commit_epoch;saved_version<=commit_version;
                valid<=commit_epoch!=0&&!invalidate&&!overlaps_new;commits<=commits+1;
            end
            if(invalidate||(valid&&overlaps_old)||(commit_valid&&overlaps_new))begin
                valid<=0;invalidations<=invalidations+1;
            end
        end
    end
endmodule
