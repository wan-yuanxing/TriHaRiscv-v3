`timescale 1ns/1ps
// Only coordinated resets may start a new FIFO epoch. Ordinary cancellation,
// clock loss and source errors must not reset either side independently.
module video_async_fifo #(
    parameter integer DATA_WIDTH = 48,
    parameter integer ADDR_WIDTH = 11
) (
    input  wire                  wr_clk,
    input  wire                  wr_reset_n,
    input  wire                  wr_valid,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_ready,
    output wire [ADDR_WIDTH:0]   wr_occupancy,
    input  wire                  rd_clk,
    input  wire                  rd_reset_n,
    output reg                   rd_valid,
    output reg  [DATA_WIDTH-1:0] rd_data,
    input  wire                  rd_ready
);
    localparam integer DEPTH = 1 << ADDR_WIDTH;
    localparam [ADDR_WIDTH:0] FULL_MASK = {2'b11, {(ADDR_WIDTH-1){1'b0}}};
    (* syn_ramstyle = "block_ram" *) reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_binary, rd_binary;
    (* syn_preserve = 1 *) reg [ADDR_WIDTH:0] wr_gray, rd_gray;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [ADDR_WIDTH:0] rd_gray_wr_sync1, rd_gray_wr_sync2;
    (* ASYNC_REG = "TRUE", syn_preserve = 1 *) reg [ADDR_WIDTH:0] wr_gray_rd_sync1, wr_gray_rd_sync2;
    (* syn_preserve = 1 *) reg wr_run, rd_run;
    reg wr_full, rd_empty;
    wire write_fire = wr_valid && wr_ready;
    // The memory is dequeued into its synchronous read/output register. That
    // register is one additional word of capacity and holds while stalled.
    wire prefetch = rd_run && (!rd_valid || rd_ready) && !rd_empty;
    wire [ADDR_WIDTH:0] wr_binary_next = wr_binary + {{ADDR_WIDTH{1'b0}},write_fire};
    wire [ADDR_WIDTH:0] rd_binary_next = rd_binary + {{ADDR_WIDTH{1'b0}},prefetch};
    wire [ADDR_WIDTH:0] wr_gray_next = (wr_binary_next >> 1) ^ wr_binary_next;
    wire [ADDR_WIDTH:0] rd_gray_next = (rd_binary_next >> 1) ^ rd_binary_next;
    function automatic [ADDR_WIDTH:0] gray_to_binary(input [ADDR_WIDTH:0] gray);
        integer i;
        begin
            gray_to_binary[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (i=ADDR_WIDTH-1; i>=0; i=i-1)
                gray_to_binary[i] = gray_to_binary[i+1] ^ gray[i];
        end
    endfunction
    assign wr_ready = wr_run && !wr_full;
    // RAM words only: synchronized reads lag real reads, so this observation
    // is conservative. The held output word is intentionally excluded.
    assign wr_occupancy = wr_binary - gray_to_binary(rd_gray_wr_sync2);
    // Keep raw reset off RAM address/data/clock-enable cones. These local
    // guard flops assert inactive asynchronously and enable only after a
    // local clock edge following release of the coordinated reset.
    always @(posedge wr_clk or negedge wr_reset_n) begin
        if (!wr_reset_n) wr_run <= 0;
        else wr_run <= 1;
    end
    always @(posedge rd_clk or negedge rd_reset_n) begin
        if (!rd_reset_n) rd_run <= 0;
        else rd_run <= 1;
    end
    always @(posedge wr_clk or negedge wr_reset_n) begin
        if (!wr_reset_n) begin
            rd_gray_wr_sync1 <= 0;
            rd_gray_wr_sync2 <= 0;
        end else begin
            rd_gray_wr_sync1 <= rd_gray;
            rd_gray_wr_sync2 <= rd_gray_wr_sync1;
        end
    end
    always @(posedge rd_clk or negedge rd_reset_n) begin
        if (!rd_reset_n) begin
            wr_gray_rd_sync1 <= 0;
            wr_gray_rd_sync2 <= 0;
        end else begin
            wr_gray_rd_sync1 <= wr_gray;
            wr_gray_rd_sync2 <= wr_gray_rd_sync1;
        end
    end
    // Separate clocked write and synchronous read ports permit dual-port RAM
    // inference. RAM contents need no reset; only ownership pointers reset.
    always @(posedge wr_clk) begin
        if (write_fire) memory[wr_binary[ADDR_WIDTH-1:0]] <= wr_data;
    end
    always @(posedge wr_clk or negedge wr_reset_n) begin
        if (!wr_reset_n) begin
            wr_binary <= 0; wr_gray <= 0; wr_full <= 0;
        end else begin
            wr_binary <= wr_binary_next;
            wr_gray <= wr_gray_next;
            wr_full <= (wr_gray_next == (rd_gray_wr_sync2 ^ FULL_MASK));
        end
    end
    always @(posedge rd_clk) begin
        if (prefetch) rd_data <= memory[rd_binary[ADDR_WIDTH-1:0]];
    end
    always @(posedge rd_clk or negedge rd_reset_n) begin
        if (!rd_reset_n) begin
            rd_binary <= 0; rd_gray <= 0; rd_empty <= 1; rd_valid <= 0;
        end else begin
            rd_binary <= rd_binary_next;
            rd_gray <= rd_gray_next;
            rd_empty <= (rd_gray_next == wr_gray_rd_sync2);
            if (!rd_valid || rd_ready) rd_valid <= prefetch;
        end
    end
endmodule
