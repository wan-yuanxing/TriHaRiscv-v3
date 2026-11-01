/*
 * TriHa 512-entry indexed BTB, two banks for the existing64-bit fetch word.
 * Word-PC indexing and tag validation follow the maintained indexed BTB method.
 * Native asynchronous RAM and resettable validity reuse the register-file
 * storage pattern. No extra prediction pipeline stage is introduced.
 */
module triha_btb (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        invalidate_i,
    input  wire        train_i,
    input  wire        taken_i,
    input  wire [31:0] source_i,
    input  wire [31:0] target_i,
    input  wire [2:0]  kind_i,
    input  wire [31:0] pc_i,
    output wire        valid_o,
    output wire        upper_o,
    output wire [31:0] target_o,
    output wire [2:0]  kind_o
);
    wire [1:0] hit;
    wire [31:0] target [0:1];
    wire [2:0] kind [0:1];
    genvar bank;
    generate
    for (bank=0; bank<2; bank=bank+1) begin: g_bank
        triha_btb_bank u_bank (
            .clk_i(clk_i), .rst_i(rst_i), .invalidate_i(invalidate_i),
            .write_i(train_i && !rst_i && !invalidate_i && source_i[2] == bank),
            .taken_i(taken_i), .write_row_i(source_i[10:3]), .write_tag_i(source_i[31:11]),
            .write_target_i(target_i), .write_kind_i(kind_i),
            .read_row_i(pc_i[10:3]), .read_tag_i(pc_i[31:11]),
            .hit_o(hit[bank]), .target_o(target[bank]), .kind_o(kind[bank])
        );
    end
    endgenerate
    // Exact word first. When fetching the lower word, only an upper-word hit
    // may serve as fallback. Full index+tag identity prevents alias hits.
    assign upper_o = pc_i[2] || !hit[0];
    assign valid_o = (pc_i[1:0] == 0) && (pc_i[2] ? hit[1] : |hit);
    assign target_o = upper_o ? target[1] : target[0];
    assign kind_o = upper_o ? kind[1] : kind[0];
endmodule

module triha_btb_bank (
    input wire clk_i, rst_i, invalidate_i, write_i, taken_i,
    input wire [7:0] write_row_i, read_row_i,
    input wire [20:0] write_tag_i, read_tag_i,
    input wire [31:0] write_target_i,
    input wire [2:0] write_kind_i,
    output wire hit_o,
    output wire [31:0] target_o,
    output wire [2:0] kind_o
);
    reg [255:0] valid_q;
    wire [8*24-1:0] metadata_words;
    wire [8*22-1:0] write_tag_words;
    wire [8*32-1:0] target_words;
    wire [23:0] metadata = metadata_words[read_row_i[7:5]*24 +: 24];
    wire [21:0] write_tag = write_tag_words[write_row_i[7:5]*22 +: 22];
    wire query_equal, write_equal;
    triha_npc_equal #(.WIDTH(21)) u_query_tag (
        .left_i(metadata[23:3]), .right_i(read_tag_i), .equal_o(query_equal)
    );
    triha_npc_equal #(.WIDTH(21)) u_write_tag (
        .left_i(write_tag[20:0]), .right_i(write_tag_i), .equal_o(write_equal)
    );
    wire write_hit = valid_q[write_row_i] && write_equal;
    wire write_target = write_i && (taken_i || !write_hit);
    assign hit_o = valid_q[read_row_i] && query_equal;
    assign kind_o = metadata[2:0];
    assign target_o = target_words[read_row_i[7:5]*32 +: 32];

    genvar row, block_index, pair;
    generate
    for (row=0; row<256; row=row+1) begin: g_valid
        always @(posedge clk_i or posedge rst_i) begin
            if (rst_i) valid_q[row] <= 1'b0;
            else if (invalidate_i) valid_q[row] <= 1'b0;
            else if (write_i && write_row_i == row) valid_q[row] <= 1'b1;
        end
    end
    for (block_index=0; block_index<8; block_index=block_index+1) begin: g_block
        wire metadata_we = write_i && write_row_i[7:5] == block_index;
        wire target_we = write_target && write_row_i[7:5] == block_index;
        wire [23:0] write_metadata = {write_tag_i, write_kind_i};
        wire [21:0] write_tag_data = {1'b0, write_tag_i};
        for (pair=0; pair<12; pair=pair+1) begin: g_metadata
            GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ram (
                .DO(metadata_words[block_index*24+pair*2 +: 2]), .DI(write_metadata[pair*2 +: 2]),
                .RADDR(read_row_i[4:0]), .WADDR(write_row_i[4:0]), .WCLK(clk_i), .WE(metadata_we)
            );
        end
        // Independent training read keeps a known target on not-taken updates.
        // Native primitives have one asynchronous read port, so tags are copied.
        for (pair=0; pair<11; pair=pair+1) begin: g_write_tag
            GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ram (
                .DO(write_tag_words[block_index*22+pair*2 +: 2]), .DI(write_tag_data[pair*2 +: 2]),
                .RADDR(write_row_i[4:0]), .WADDR(write_row_i[4:0]), .WCLK(clk_i), .WE(metadata_we)
            );
        end
        for (pair=0; pair<16; pair=pair+1) begin: g_target
            GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ram (
                .DO(target_words[block_index*32+pair*2 +: 2]), .DI(write_target_i[pair*2 +: 2]),
                .RADDR(read_row_i[4:0]), .WADDR(write_row_i[4:0]), .WCLK(clk_i), .WE(target_we)
            );
        end
    end
    endgenerate
endmodule
