//-----------------------------------------------------------------
//                         biRISC-V CPU
//                            V0.8.1
//                     Ultra-Embedded.com
//                     Copyright 2019-2020
//
//                   admin@ultra-embedded.com
//
//                     License: Apache 2.0
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------

module triha_npc
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_BRANCH_PREDICTION = 1
    ,parameter NUM_BTB_ENTRIES  = 32
    ,parameter NUM_BTB_ENTRIES_W = 5
    ,parameter BTB_DIRECT_MAPPED = 0
    ,parameter NUM_BHT_ENTRIES  = 512
    ,parameter NUM_BHT_ENTRIES_W = 9
    ,parameter RAS_ENABLE       = 1
    ,parameter GSHARE_ENABLE    = 0
    ,parameter BHT_ENABLE       = 1
    ,parameter NUM_RAS_ENTRIES  = 8
    ,parameter NUM_RAS_ENTRIES_W = 3
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           invalidate_i
    ,input           branch_request_i
    ,input           branch_is_taken_i
    ,input           branch_is_not_taken_i
    ,input  [ 31:0]  branch_source_i
    ,input           branch_is_call_i
    ,input           branch_is_ret_i
    ,input           branch_is_jmp_i
    ,input  [ 31:0]  branch_pc_i
    ,input  [ 31:0]  pc_f_i
    ,input           pc_accept_i

    // Outputs
    ,output [ 31:0]  next_pc_f_o
    ,output [  1:0]  next_taken_f_o
);



localparam RAS_INVALID = 32'h00000001;

//-----------------------------------------------------------------
// Branch prediction (BTB, BHT, RAS)
//-----------------------------------------------------------------
generate
if (SUPPORT_BRANCH_PREDICTION)
begin: BRANCH_PREDICTION

wire        pred_taken_w;
wire        pred_ntaken_w;
// Compute sequential PC before late prediction metadata reaches selection.
(* syn_keep = 1 *) wire [31:0] sequential_pc_w = {pc_f_i[31:3],3'b0} + 32'd8;

// Info from BTB
wire        btb_valid_w;
wire        btb_upper_w;
wire [31:0] btb_next_pc_w;
wire        btb_is_call_w;
wire        btb_is_ret_w;
wire        btb_is_jmp_w;
wire btb_call_valid_w,btb_ret_valid_w;

//-----------------------------------------------------------------
// Return Address Stack (actual)
//-----------------------------------------------------------------
reg [NUM_RAS_ENTRIES_W-1:0] ras_index_real_q;
reg [NUM_RAS_ENTRIES_W-1:0] ras_index_real_r;

always @ *
begin
    ras_index_real_r = ras_index_real_q;

    if (branch_request_i & branch_is_call_i)
        ras_index_real_r = ras_index_real_q + 1;
    else if (branch_request_i & branch_is_ret_i)
        ras_index_real_r = ras_index_real_q - 1;
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    ras_index_real_q <= {NUM_RAS_ENTRIES_W{1'b0}};
else
    ras_index_real_q <= ras_index_real_r;

//-----------------------------------------------------------------
// Return Address Stack (speculative)
//-----------------------------------------------------------------
reg [31:0] ras_stack_q[NUM_RAS_ENTRIES-1:0];
reg [NUM_RAS_ENTRIES_W-1:0] ras_index_q;

reg [NUM_RAS_ENTRIES_W-1:0] ras_index_r;

wire [31:0] ras_pc_pred_w   = ras_stack_q[ras_index_q];
wire        ras_call_pred_w = RAS_ENABLE & btb_call_valid_w & ~ras_pc_pred_w[0];
wire        ras_ret_pred_w  = RAS_ENABLE & btb_ret_valid_w & ~ras_pc_pred_w[0];

always @ *
begin
    ras_index_r = ras_index_q;

    // Mispredict - go from confirmed call stack index
    if (branch_request_i & branch_is_call_i)
        ras_index_r = ras_index_real_q + 1;
    else if (branch_request_i & branch_is_ret_i)
        ras_index_r = ras_index_real_q - 1;
    // Speculative call / returns
    else if (ras_call_pred_w & pc_accept_i)
        ras_index_r = ras_index_q + 1;
    else if (ras_ret_pred_w & pc_accept_i)
        ras_index_r = ras_index_q - 1;
end

// Decode known index candidates before the late prediction controls arrive.
// A confirmed return overlapping a speculative call uses the confirmed
// return index, as in the original ras_index_r priority chain.
wire [NUM_RAS_ENTRIES_W-1:0] ras_actual_push_index_w = ras_index_real_q + 1'b1;
reg [NUM_RAS_ENTRIES_W-1:0] ras_spec_push_index_r;
reg ras_actual_push_r, ras_spec_push_r;
always @* begin
    ras_spec_push_index_r = ras_index_q + 1'b1;
    if (branch_request_i & branch_is_ret_i)
        ras_spec_push_index_r = ras_index_real_q - 1'b1;
    ras_actual_push_r = 1'b0;
    ras_spec_push_r = 1'b0;
    if (branch_request_i & branch_is_call_i)
        ras_actual_push_r = 1'b1;
    else if (ras_call_pred_w & pc_accept_i)
        ras_spec_push_r = 1'b1;
end
genvar ras_entry;
for (ras_entry=0; ras_entry<NUM_RAS_ENTRIES; ras_entry=ras_entry+1) begin: g_ras_write
    localparam [NUM_RAS_ENTRIES_W-1:0] ENTRY = ras_entry;
    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            ras_stack_q[ras_entry] <= RAS_INVALID;
        else if (ras_actual_push_r && ras_actual_push_index_w == ENTRY)
            ras_stack_q[ras_entry] <= branch_source_i + 32'd4;
        else if (ras_spec_push_r && ras_spec_push_index_r == ENTRY)
            ras_stack_q[ras_entry] <= (btb_upper_w ? (pc_f_i | 32'd4) : pc_f_i) + 32'd4;
    end
end
always @(posedge clk_i or posedge rst_i)
if (rst_i)
    ras_index_q <= {NUM_RAS_ENTRIES_W{1'b0}};
else if (branch_request_i & branch_is_call_i)
    ras_index_q <= ras_index_r;
else if (ras_call_pred_w & pc_accept_i)
    ras_index_q <= ras_index_r;
else if ((ras_ret_pred_w & pc_accept_i) || (branch_request_i & branch_is_ret_i))
    ras_index_q <= ras_index_r;

//-----------------------------------------------------------------
// Global history register (actual history)
//-----------------------------------------------------------------
reg [NUM_BHT_ENTRIES_W-1:0] global_history_real_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    global_history_real_q <= {NUM_BHT_ENTRIES_W{1'b0}};
else if (branch_is_taken_i || branch_is_not_taken_i)
    global_history_real_q <= {global_history_real_q[NUM_BHT_ENTRIES_W-2:0], branch_is_taken_i};

//-----------------------------------------------------------------
// Global history register (speculative)
//-----------------------------------------------------------------
reg [NUM_BHT_ENTRIES_W-1:0] global_history_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    global_history_q <= {NUM_BHT_ENTRIES_W{1'b0}};
// Mispredict - revert to actual branch history to flush out speculative errors
else if (branch_request_i)
    global_history_q <= {global_history_real_q[NUM_BHT_ENTRIES_W-2:0], branch_is_taken_i};
// Predicted branch
else if (pred_taken_w || pred_ntaken_w)
    global_history_q <= {global_history_q[NUM_BHT_ENTRIES_W-2:0], pred_taken_w};

wire [NUM_BHT_ENTRIES_W-1:0] gshare_wr_entry_w = (branch_request_i ? global_history_real_q : global_history_q) ^ branch_source_i[2+NUM_BHT_ENTRIES_W-1:2];
wire [NUM_BHT_ENTRIES_W-1:0] gshare_rd_entry_w = global_history_q ^ {pc_f_i[3+NUM_BHT_ENTRIES_W-2:3],btb_upper_w};

//-----------------------------------------------------------------
// Branch prediction bits
//-----------------------------------------------------------------
reg [1:0]                    bht_sat_q[NUM_BHT_ENTRIES-1:0];

wire [NUM_BHT_ENTRIES_W-1:0] bht_wr_entry_w = GSHARE_ENABLE ? gshare_wr_entry_w : branch_source_i[2+NUM_BHT_ENTRIES_W-1:2];
wire [NUM_BHT_ENTRIES_W-1:0] bht_rd_entry_w = GSHARE_ENABLE ? gshare_rd_entry_w : {pc_f_i[3+NUM_BHT_ENTRIES_W-2:3],btb_upper_w};

integer i4;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    for (i4 = 0; i4 < NUM_BHT_ENTRIES; i4 = i4 + 1)
    begin
        bht_sat_q[i4] <= 2'd3;
    end
end
else begin
    // Keep the two-bit saturation decision local to each entry; a write
    // address must not first traverse a dynamic counter read multiplexer.
    for (i4=0; i4<NUM_BHT_ENTRIES; i4=i4+1) begin
        if (bht_wr_entry_w == i4) begin
            if (branch_is_taken_i && bht_sat_q[i4] < 2'd3)
                bht_sat_q[i4] <= bht_sat_q[i4] + 2'd1;
            else if (branch_is_not_taken_i && bht_sat_q[i4] > 2'd0)
                bht_sat_q[i4] <= bht_sat_q[i4] - 2'd1;
        end
    end
end

// Read both fetch-word banks before the late BTB upper-word decision.
// Preserve relational comparison and unknown-address behavior in RTL.
wire [NUM_BHT_ENTRIES_W-1:0] bht_even_index_w =
    bht_rd_entry_w & ({NUM_BHT_ENTRIES_W{1'b1}} << 1);
wire [NUM_BHT_ENTRIES_W-1:0] bht_odd_index_w = bht_even_index_w | 1'b1;
(* syn_keep = 1 *) wire bht_even_taken_w = bht_sat_q[bht_even_index_w] >= 2'd2;
(* syn_keep = 1 *) wire bht_odd_taken_w = bht_sat_q[bht_odd_index_w] >= 2'd2;
reg bht_selected_taken_r;
always @* begin
    case (bht_rd_entry_w[0])
        1'b0: bht_selected_taken_r = bht_even_taken_w;
        1'b1: bht_selected_taken_r = bht_odd_taken_w;
        default: bht_selected_taken_r = 1'bx;
    endcase
end
wire bht_predict_taken_w = BHT_ENABLE && bht_selected_taken_r;

//-----------------------------------------------------------------
// Branch target buffer
//-----------------------------------------------------------------
if (BTB_DIRECT_MAPPED) begin: g_indexed
    wire [31:0] target;
    wire [2:0] kind;
    triha_btb u_btb (
        .clk_i(clk_i), .rst_i(rst_i), .invalidate_i(invalidate_i),
        .train_i(branch_request_i), .taken_i(branch_is_taken_i),
        .source_i(branch_source_i), .target_i(branch_pc_i),
        .kind_i({branch_is_call_i,branch_is_ret_i,branch_is_jmp_i}), .pc_i(pc_f_i),
        .valid_o(btb_valid_w), .upper_o(btb_upper_w), .target_o(target), .kind_o(kind),
        .call_valid_o(btb_call_valid_w),.ret_valid_o(btb_ret_valid_w)
    );
    assign {btb_is_call_w,btb_is_ret_w,btb_is_jmp_w} = kind;
    assign btb_next_pc_w = btb_valid_w ? target : sequential_pc_w;
    // synthesis translate_off
    initial if (NUM_BTB_ENTRIES != 512 || NUM_BTB_ENTRIES_W != 9)
        $fatal(1,"INDEXED_BTB_FAIL requires512entries");
    // synthesis translate_on
end else begin: g_associative
reg [31:0]  btb_pc_q[NUM_BTB_ENTRIES-1:0];
reg [31:0]  btb_target_q[NUM_BTB_ENTRIES-1:0];
reg         btb_is_call_q[NUM_BTB_ENTRIES-1:0];
reg         btb_is_ret_q[NUM_BTB_ENTRIES-1:0];
reg         btb_is_jmp_q[NUM_BTB_ENTRIES-1:0];

// Compare in parallel; procedural if retains the original treatment of an
// unknown PC comparison as a non-match.
reg [NUM_BTB_ENTRIES-1:0] match_pc_r;
reg [NUM_BTB_ENTRIES-1:0] match_upper_r;
reg [NUM_BTB_ENTRIES-1:0] match_write_r;
wire [NUM_BTB_ENTRIES-1:0] match_common_w;
wire [NUM_BTB_ENTRIES-1:0] match_source_w;
genvar compare_entry;
for (compare_entry=0; compare_entry<NUM_BTB_ENTRIES; compare_entry=compare_entry+1) begin: g_tag_compare
    // Only bit two differs between exact-PC and upper-word queries.
    // Share both the high tag and low alignment bits; retain every tag bit.
    triha_npc_equal #(.WIDTH(31)) u_query (
        .left_i({btb_pc_q[compare_entry][31:3],btb_pc_q[compare_entry][1:0]}),
        .right_i({pc_f_i[31:3],pc_f_i[1:0]}),
        .equal_o(match_common_w[compare_entry])
    );
    triha_npc_equal #(.WIDTH(32)) u_source (
        .left_i(btb_pc_q[compare_entry]), .right_i(branch_source_i),
        .equal_o(match_source_w[compare_entry])
    );
end
integer i0;
always @* begin
    match_pc_r = {NUM_BTB_ENTRIES{1'b0}};
    match_upper_r = {NUM_BTB_ENTRIES{1'b0}};
    match_write_r = {NUM_BTB_ENTRIES{1'b0}};
    for (i0=0; i0<NUM_BTB_ENTRIES; i0=i0+1) begin
        if (match_common_w[i0] && btb_pc_q[i0][2] == pc_f_i[2])
            match_pc_r[i0] = 1'b1;
        if (match_common_w[i0] && btb_pc_q[i0][2])
            match_upper_r[i0] = 1'b1;
        if (branch_request_i)
            if (match_source_w[i0])
                match_write_r[i0] = 1'b1;
    end
end

wire pc_hit_w, upper_hit_w, write_hit_w;
reg btb_valid_r;
reg btb_upper_r;
always @* begin
    btb_valid_r = pc_hit_w;
    btb_upper_r = 1'b0;
    if (pc_hit_w)
        btb_upper_r = pc_f_i[2];
    else if (~pc_f_i[2]) begin
        btb_valid_r = upper_hit_w;
        if (upper_hit_w)
            btb_upper_r = 1'b1;
    end
end

wire [NUM_BTB_ENTRIES-1:0] select_read_w;
wire [NUM_BTB_ENTRIES-1:0] select_write_w;
// Rank both lookup alternatives in parallel. Applying the upper-word fallback
// before priority selection serializes the all-entry hit reduction, a vector
// mux and another all-entry priority reduction on the next-PC feedback path.
(* syn_keep = 1 *) wire [NUM_BTB_ENTRIES-1:0] select_pc_w;
(* syn_keep = 1 *) wire [NUM_BTB_ENTRIES-1:0] select_upper_w;
reg [NUM_BTB_ENTRIES-1:0] select_read_r;
always @* begin
    select_read_r = select_pc_w;
    if (pc_hit_w)
        select_read_r = select_pc_w;
    else if (~pc_f_i[2])
        select_read_r = select_upper_w;
end
assign select_read_w = select_read_r;
localparam BTB_PAYLOAD_W = 35 + NUM_BTB_ENTRIES_W;
wire [NUM_BTB_ENTRIES*BTB_PAYLOAD_W-1:0] btb_payload_w;
triha_npc_priority #(.INPUTS(NUM_BTB_ENTRIES)) u_priority_pc (
    .match_i(match_pc_r), .select_o(select_pc_w), .hit_o(pc_hit_w)
);
triha_npc_priority #(.INPUTS(NUM_BTB_ENTRIES)) u_priority_upper (
    .match_i(match_upper_r), .select_o(select_upper_w), .hit_o(upper_hit_w)
);
triha_npc_priority #(.INPUTS(NUM_BTB_ENTRIES)) u_priority_write (
    .match_i(match_write_r), .select_o(select_write_w), .hit_o(write_hit_w)
);

genvar entry;
for (entry=0; entry<NUM_BTB_ENTRIES; entry=entry+1) begin: g_btb_select
    localparam [NUM_BTB_ENTRIES_W-1:0] ENTRY = entry;
    // Preserve the original highest-numbered matching entry, even for
    // duplicate tags (including all PC=0 entries immediately after reset).
    assign btb_payload_w[entry*BTB_PAYLOAD_W +: BTB_PAYLOAD_W] =
        {ENTRY,btb_is_call_q[entry],btb_is_ret_q[entry],btb_is_jmp_q[entry],btb_target_q[entry]};
end

wire btb_is_call_r;
wire btb_is_ret_r;
wire btb_is_jmp_r;
wire [NUM_BTB_ENTRIES_W-1:0] btb_entry_r;
wire [31:0] btb_selected_pc_w;
wire [31:0] btb_next_pc_r = btb_valid_r ? btb_selected_pc_w :
    (sequential_pc_w);
triha_npc_select #(.WIDTH(BTB_PAYLOAD_W),.INPUTS(NUM_BTB_ENTRIES)) u_btb_select (
    .data_i(btb_payload_w),.select_i(select_read_w),
    .data_o({btb_entry_r,btb_is_call_r,btb_is_ret_r,btb_is_jmp_r,btb_selected_pc_w})
);

wire [NUM_BTB_ENTRIES_W-1:0] btb_wr_alloc_w;
wire btb_hit_r = write_hit_w;
reg btb_miss_r;
always @* begin
    btb_miss_r = 1'b0;
    if (branch_request_i)
        btb_miss_r = ~btb_hit_r;
end

// synthesis translate_off
always @(posedge clk_i) begin
    if (!rst_i && (((select_read_w & (select_read_w-1'b1)) != 0) ||
                   ((select_write_w & (select_write_w-1'b1)) != 0)))
        $fatal(1,"PREDICTOR_SELECT_FAIL non_onehot_selection");
end
// synthesis translate_on

integer i2;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    for (i2 = 0; i2 < NUM_BTB_ENTRIES; i2 = i2 + 1)
    begin
        btb_pc_q[i2]     <= 32'b0;
        btb_target_q[i2] <= 32'b0;
        btb_is_call_q[i2]<= 1'b0;
        btb_is_ret_q[i2] <= 1'b0;
        btb_is_jmp_q[i2] <= 1'b0;
    end
end
else begin
    // Decode the already one-hot match at each table entry, avoiding a
    // priority-encode -> variable-array-insert -> decode path on writes.
    for (i2=0; i2<NUM_BTB_ENTRIES; i2=i2+1) begin
        if (select_write_w[i2]) begin
            btb_pc_q[i2] <= branch_source_i;
            if (branch_is_taken_i)
                btb_target_q[i2] <= branch_pc_i;
            btb_is_call_q[i2] <= branch_is_call_i;
            btb_is_ret_q[i2] <= branch_is_ret_i;
            btb_is_jmp_q[i2] <= branch_is_jmp_i;
        end else if (btb_miss_r && btb_wr_alloc_w == i2) begin
            btb_pc_q[i2] <= branch_source_i;
            btb_target_q[i2] <= branch_pc_i;
            btb_is_call_q[i2] <= branch_is_call_i;
            btb_is_ret_q[i2] <= branch_is_ret_i;
            btb_is_jmp_q[i2] <= branch_is_jmp_i;
        end
    end
end

//-----------------------------------------------------------------
// Replacement Selection
//-----------------------------------------------------------------
triha_npc_lfsr
#(
    .DEPTH(NUM_BTB_ENTRIES)
   ,.ADDR_W(NUM_BTB_ENTRIES_W)
)
u_lru
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.hit_i(btb_valid_r)
    ,.hit_entry_i(btb_entry_r)

    ,.alloc_i(btb_miss_r)
    ,.alloc_entry_o(btb_wr_alloc_w)
);

//-----------------------------------------------------------------
// Outputs
//-----------------------------------------------------------------
assign btb_valid_w   = btb_valid_r;
assign btb_upper_w   = btb_upper_r;
assign btb_is_call_w = btb_is_call_r;
assign btb_is_ret_w  = btb_is_ret_r;
assign btb_is_jmp_w  = btb_is_jmp_r;
assign btb_next_pc_w = btb_next_pc_r;
assign btb_call_valid_w=btb_valid_w & btb_is_call_w;
assign btb_ret_valid_w=btb_valid_w & btb_is_ret_w;
end
assign next_pc_f_o   = ras_ret_pred_w      ? ras_pc_pred_w : 
                       (bht_predict_taken_w | btb_is_jmp_w) ? btb_next_pc_w :
                       sequential_pc_w;

assign next_taken_f_o = (btb_valid_w & (ras_ret_pred_w | bht_predict_taken_w | btb_is_jmp_w)) ? 
                        pc_f_i[2] ? {btb_upper_w, 1'b0} :
                        {btb_upper_w, ~btb_upper_w} : 2'b0;

assign pred_taken_w   = btb_valid_w & (ras_ret_pred_w | bht_predict_taken_w | btb_is_jmp_w) & pc_accept_i;
assign pred_ntaken_w  = btb_valid_w & ~pred_taken_w & pc_accept_i;


end
//-----------------------------------------------------------------
// No branch prediction
//-----------------------------------------------------------------
else
begin: NO_BRANCH_PREDICTION

assign next_pc_f_o    = {pc_f_i[31:3],3'b0} + 32'd8;
assign next_taken_f_o = 2'b0;

end
endgenerate

endmodule


// Balanced full-width equality. Three bits per group fit a six-input LUT;
// explicit group boundaries avoid serial carry-chain tag comparisons.
module triha_npc_equal #(
    parameter integer WIDTH = 32
) (
    input  wire [WIDTH-1:0] left_i,
    input  wire [WIDTH-1:0] right_i,
    output wire equal_o
);
    localparam integer GROUPS = (WIDTH + 2) / 3;
    (* syn_keep = 1 *) wire [GROUPS-1:0] group_equal_w;
    genvar group_index;
    generate
    for (group_index=0; group_index<GROUPS; group_index=group_index+1) begin: g_group
        localparam integer FIRST = group_index * 3;
        localparam integer BITS = WIDTH - FIRST >= 3 ? 3 : WIDTH - FIRST;
        assign group_equal_w[group_index] = left_i[FIRST +: BITS] == right_i[FIRST +: BITS];
    end
    endgenerate
    localparam integer REDUCTIONS = (GROUPS + 5) / 6;
    (* syn_keep = 1 *) wire [REDUCTIONS-1:0] reduced_w;
    genvar reduction_index, term_index;
    generate
    for (reduction_index=0; reduction_index<REDUCTIONS; reduction_index=reduction_index+1) begin: g_reduce
        wire [5:0] terms_w;
        for (term_index=0; term_index<6; term_index=term_index+1) begin: g_term
            if (reduction_index*6+term_index < GROUPS) begin: g_used
                assign terms_w[term_index] = group_equal_w[reduction_index*6+term_index];
            end else begin: g_padding
                assign terms_w[term_index] = 1'b1;
            end
        end
        assign reduced_w[reduction_index] = &terms_w;
    end
    endgenerate
    assign equal_o = &reduced_w;
endmodule

module triha_npc_lfsr
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter DEPTH            = 32
    ,parameter ADDR_W           = 5
    ,parameter INITIAL_VALUE    = 16'h0001
    ,parameter TAP_VALUE        = 16'hB400
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           hit_i
    ,input  [ADDR_W-1:0]  hit_entry_i
    ,input           alloc_i

    // Outputs
    ,output [ADDR_W-1:0]  alloc_entry_o
);

//-----------------------------------------------------------------
// Scheme: LFSR
//-----------------------------------------------------------------
reg [15:0] lfsr_q;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    lfsr_q <= INITIAL_VALUE;
else if (alloc_i)
begin
    if (lfsr_q[0])
        lfsr_q <= {1'b0, lfsr_q[15:1]} ^ TAP_VALUE;
    else
        lfsr_q <= {1'b0, lfsr_q[15:1]};
end

assign alloc_entry_o = lfsr_q[ADDR_W-1:0];





endmodule

// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0; see vendor/LICENSE.
// SPDX-License-Identifier: Apache-2.0
// Adapted from prim_onehot_mux: flat Verilog ports and direct bitwise AND/OR.
// The caller supplies highest-priority one-hot-or-zero select vectors.
module triha_npc_select #(
    parameter WIDTH=32,
    parameter INPUTS=8
)(
    input [WIDTH*INPUTS-1:0] data_i,
    input [INPUTS-1:0] select_i,
    output [WIDTH-1:0] data_o
);
    localparam GROUPS = (INPUTS + 2) / 3;
    localparam REDUCTIONS = (GROUPS + 5) / 6;
    genvar bit_index,group_index,input_index,reduction_index;
    generate
    for (bit_index=0; bit_index<WIDTH; bit_index=bit_index+1) begin: g_bit
        // Three two-input AND terms fit one LUT6. Keep their group results
        // before six-input OR reductions to prevent a serial accumulator.
        (* syn_keep = 1 *) wire [GROUPS-1:0] grouped_w;
        (* syn_keep = 1 *) wire [REDUCTIONS-1:0] reduced_w;
        for (group_index=0; group_index<GROUPS; group_index=group_index+1) begin: g_group
            wire [2:0] terms_w;
            for (input_index=0; input_index<3; input_index=input_index+1) begin: g_term
                if (group_index*3+input_index < INPUTS) begin: g_used
                    assign terms_w[input_index] =
                        data_i[(group_index*3+input_index)*WIDTH+bit_index] &
                        select_i[group_index*3+input_index];
                end else begin: g_padding
                    assign terms_w[input_index] = 1'b0;
                end
            end
            assign grouped_w[group_index] = |terms_w;
        end
        for (reduction_index=0; reduction_index<REDUCTIONS; reduction_index=reduction_index+1) begin: g_reduce
            wire [5:0] terms_w;
            for (input_index=0; input_index<6; input_index=input_index+1) begin: g_term
                if (reduction_index*6+input_index < GROUPS) begin: g_used
                    assign terms_w[input_index] = grouped_w[reduction_index*6+input_index];
                end else begin: g_padding
                    assign terms_w[input_index] = 1'b0;
                end
            end
            assign reduced_w[reduction_index] = |terms_w;
        end
        assign data_o[bit_index] = |reduced_w;
    end
    endgenerate
endmodule

// Highest matching entry using bounded six-input lookahead groups.
// Native LUT truth tables prevent area factoring from serializing the prefix.
module triha_npc_priority #(
    parameter integer INPUTS=32
)(
    input wire [INPUTS-1:0] match_i,
    output wire [INPUTS-1:0] select_o,
    output wire hit_o
);
    localparam integer GROUPS=(INPUTS+5)/6;
    genvar group_index,entry,term;
    generate
    if (INPUTS<=36) begin: g_native
        (* syn_keep = 1 *) wire [GROUPS-1:0] group_valid_w;
        (* syn_keep = 1 *) wire [INPUTS-1:0] local_rank_w;
        for(group_index=0;group_index<GROUPS;group_index=group_index+1) begin: g_group
            wire [5:0] flags_w;
            for(term=0;term<6;term=term+1) begin: g_term
                if(group_index*6+term<INPUTS) begin: g_used
                    assign flags_w[term]=match_i[group_index*6+term];
                end else begin: g_padding
                    assign flags_w[term]=1'b0;
                end
            end
            GTP_LUT6 #(.INIT(64'hfffffffffffffffe)) u_any (
                .I0(flags_w[0]),.I1(flags_w[1]),.I2(flags_w[2]),
                .I3(flags_w[3]),.I4(flags_w[4]),.I5(flags_w[5]),.Z(group_valid_w[group_index])
            );
        end
        wire [5:0] hit_terms_w;
        for(term=0;term<6;term=term+1) begin: g_hit_term
            if(term<GROUPS) begin: g_used
                assign hit_terms_w[term]=group_valid_w[term];
            end else begin: g_padding
                assign hit_terms_w[term]=1'b0;
            end
        end
        GTP_LUT6 #(.INIT(64'hfffffffffffffffe)) u_hit (
            .I0(hit_terms_w[0]),.I1(hit_terms_w[1]),.I2(hit_terms_w[2]),
            .I3(hit_terms_w[3]),.I4(hit_terms_w[4]),.I5(hit_terms_w[5]),.Z(hit_o)
        );
        for(entry=0;entry<INPUTS;entry=entry+1) begin: g_entry
            wire [5:0] local_w,global_w;
            assign local_w[0]=match_i[entry];
            assign global_w[0]=local_rank_w[entry];
            for(term=1;term<6;term=term+1) begin: g_term
                if((entry%6)+term<6 && entry+term<INPUTS) begin: g_local
                    assign local_w[term]=match_i[entry+term];
                end else begin: g_local_padding
                    assign local_w[term]=1'b0;
                end
                if(entry/6+term<GROUPS) begin: g_global
                    assign global_w[term]=group_valid_w[entry/6+term];
                end else begin: g_global_padding
                    assign global_w[term]=1'b0;
                end
            end
            GTP_LUT6 #(.INIT(64'h0000000000000002)) u_local (
                .I0(local_w[0]),.I1(local_w[1]),.I2(local_w[2]),
                .I3(local_w[3]),.I4(local_w[4]),.I5(local_w[5]),.Z(local_rank_w[entry])
            );
            GTP_LUT6 #(.INIT(64'h0000000000000002)) u_global (
                .I0(global_w[0]),.I1(global_w[1]),.I2(global_w[2]),
                .I3(global_w[3]),.I4(global_w[4]),.I5(global_w[5]),.Z(select_o[entry])
            );
        end
    end else begin: g_large_table
        assign hit_o=|match_i;
        for(entry=0;entry<INPUTS;entry=entry+1) begin: g_entry
            assign select_o[entry]=match_i[entry] & ~(|(match_i>>(entry+1)));
        end
    end
    endgenerate
endmodule
