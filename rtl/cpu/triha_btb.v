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
    output wire [2:0]  kind_o,
    output wire call_valid_o, ret_valid_o
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
    // Qualify the two needed RAS classes in parallel with bank priority.
    // These narrow boundaries avoid the wide upper/target mux control.
    wire [1:0] lower_class_w /* synthesis syn_keep=1 */;
    wire [1:0] upper_class_w /* synthesis syn_keep=1 */;
    assign lower_class_w={2{hit[0]}} & kind[0][2:1];
    assign upper_class_w={2{hit[1]}} & kind[1][2:1];
    reg [1:0] qualified_class_r;
    always @* begin
        // The default preserves the original four-state merge contract.
        // All eight binary selector cases below are explicitly covered.
        qualified_class_r={valid_o && kind_o[2],valid_o && kind_o[1]};
        case({pc_i[2],hit[1],hit[0]})
            3'b000,3'b100,3'b101: qualified_class_r=2'b0;
            3'b001,3'b011: qualified_class_r=lower_class_w & {2{pc_i[1:0]==0}};
            3'b010,3'b110,3'b111: qualified_class_r=upper_class_w & {2{pc_i[1:0]==0}};
        endcase
    end
    assign {call_valid_o,ret_valid_o}=qualified_class_r;
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

    genvar row, block_index, pair, address_bit;
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
        // Compare this block's training tag before any wide block selection.
        wire local_equal;
        triha_npc_equal #(.WIDTH(21)) u_local_write_tag (
            .left_i(write_tag_words[block_index*22 +: 21]),
            .right_i(write_tag_i), .equal_o(local_equal)
        );
        wire local_valid = valid_q[block_index*32 + write_row_i[4:0]];
        wire local_target_we = metadata_we && (taken_i || !(local_valid && local_equal));
        reg target_we;
        always @* begin
            // Unknown block indices retain the parent's four-state contract.
            target_we = write_target && write_row_i[7:5] == block_index;
            case (write_row_i[7:5])
                3'd0,3'd1,3'd2,3'd3,3'd4,3'd5,3'd6,3'd7: target_we = local_target_we;
            endcase
        end
        // Native write-address minimum delay, local to each32-row block.
        // An actual block write selects both stable row predicates.
        // Keep reset/train on WE only, outside the write-address data cone.
        // Keep the training tag read address and all read ports unchanged.
        (* syn_keep = 1 *) wire [4:0] write_address_delay_w;
        (* syn_keep = 1 *) wire [4:0] write_address_w;
        wire address_half_match = write_row_i[7:6] == (block_index >> 1);
        wire address_pair_mismatch = write_row_i[5] != (block_index & 1);
        for(address_bit=0;address_bit<5;address_bit=address_bit+1) begin:g_write_address_hold
            (* syn_keep = 1 *) GTP_LUT6 #(.INIT(64'h8888888888888888)) u_first (
                .I0(write_row_i[address_bit]),.I1(address_half_match),.I2(1'b0),.I3(1'b0),
                .I4(1'b0),.I5(1'b0),.Z(write_address_delay_w[address_bit]));
            (* syn_keep = 1 *) GTP_LUT6 #(.INIT(64'h2222222222222222)) u_second (
                .I0(write_address_delay_w[address_bit]),.I1(address_pair_mismatch),.I2(1'b0),.I3(1'b0),
                .I4(1'b0),.I5(1'b0),.Z(write_address_w[address_bit]));
        end
        wire [23:0] write_metadata = {write_tag_i, write_kind_i};
        wire [21:0] write_tag_data = {1'b0, write_tag_i};
        for (pair=0; pair<12; pair=pair+1) begin: g_metadata
            GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ram (
                .DO(metadata_words[block_index*24+pair*2 +: 2]), .DI(write_metadata[pair*2 +: 2]),
                .RADDR(read_row_i[4:0]), .WADDR(write_address_w), .WCLK(clk_i), .WE(metadata_we)
            );
        end
        // Independent training read keeps a known target on not-taken updates.
        // Native primitives have one asynchronous read port, so tags are copied.
        for (pair=0; pair<11; pair=pair+1) begin: g_write_tag
            GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ram (
                .DO(write_tag_words[block_index*22+pair*2 +: 2]), .DI(write_tag_data[pair*2 +: 2]),
                .RADDR(write_row_i[4:0]), .WADDR(write_address_w), .WCLK(clk_i), .WE(metadata_we)
            );
        end
        for (pair=0; pair<16; pair=pair+1) begin: g_target
            GTP_RAM32X2DP #(.INIT_0(32'b0), .INIT_1(32'b0)) u_ram (
                .DO(target_words[block_index*32+pair*2 +: 2]), .DI(write_target_i[pair*2 +: 2]),
                .RADDR(read_row_i[4:0]), .WADDR(write_address_w), .WCLK(clk_i), .WE(target_we)
            );
        end
    end
    endgenerate
endmodule
