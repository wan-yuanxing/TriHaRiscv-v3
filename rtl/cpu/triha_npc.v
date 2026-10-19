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

// Info from BTB
wire        btb_valid_w;
wire        btb_upper_w;
wire [31:0] btb_next_pc_w;
wire        btb_is_call_w;
wire        btb_is_ret_w;

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
wire        ras_call_pred_w = RAS_ENABLE & (btb_valid_w & btb_is_call_w) & ~ras_pc_pred_w[0];
wire        ras_ret_pred_w  = RAS_ENABLE & (btb_valid_w & btb_is_ret_w) & ~ras_pc_pred_w[0];

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

integer i3;
always @ (posedge clk_i or posedge rst_i)
if (rst_i)
begin
    for (i3 = 0; i3 < NUM_RAS_ENTRIES; i3 = i3 + 1) 
    begin
        ras_stack_q[i3] <= RAS_INVALID;
    end

    ras_index_q <= {NUM_RAS_ENTRIES_W{1'b0}};
end
// On a call push return address onto RAS stack (current PC + 4)
else if (branch_request_i & branch_is_call_i)
begin
    ras_stack_q[ras_index_r] <= branch_source_i + 32'd4;
    ras_index_q              <= ras_index_r;
end
// On a call push return address onto RAS stack (current PC + 4)
else if (ras_call_pred_w & pc_accept_i)
begin
    ras_stack_q[ras_index_r] <= (btb_upper_w ? (pc_f_i | 32'd4) : pc_f_i) + 32'd4;
    ras_index_q              <= ras_index_r;
end
// Return - pop item from stack
else if ((ras_ret_pred_w & pc_accept_i) || (branch_request_i & branch_is_ret_i))
begin
    ras_index_q              <= ras_index_r;
end

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

wire bht_predict_taken_w = BHT_ENABLE && (bht_sat_q[bht_rd_entry_w] >= 2'd2);

//-----------------------------------------------------------------
// Branch target buffer
//-----------------------------------------------------------------
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
integer i0;
always @* begin
    match_pc_r = {NUM_BTB_ENTRIES{1'b0}};
    match_upper_r = {NUM_BTB_ENTRIES{1'b0}};
    match_write_r = {NUM_BTB_ENTRIES{1'b0}};
    for (i0=0; i0<NUM_BTB_ENTRIES; i0=i0+1) begin
        if (btb_pc_q[i0] == pc_f_i)
            match_pc_r[i0] = 1'b1;
        if (btb_pc_q[i0] == (pc_f_i | 32'd4))
            match_upper_r[i0] = 1'b1;
        if (branch_request_i)
            if (btb_pc_q[i0] == branch_source_i)
                match_write_r[i0] = 1'b1;
    end
end

reg [NUM_BTB_ENTRIES-1:0] match_read_r;
reg btb_upper_r;
always @* begin
    match_read_r = match_pc_r;
    btb_upper_r = 1'b0;
    if (|match_pc_r)
        btb_upper_r = pc_f_i[2];
    else if (~pc_f_i[2]) begin
        match_read_r = match_upper_r;
        if (|match_upper_r)
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
    if (|match_pc_r)
        select_read_r = select_pc_w;
    else if (~pc_f_i[2])
        select_read_r = select_upper_w;
end
assign select_read_w = select_read_r;
localparam BTB_PAYLOAD_W = 35 + NUM_BTB_ENTRIES_W;
wire [NUM_BTB_ENTRIES*BTB_PAYLOAD_W-1:0] btb_payload_w;
genvar entry;
for (entry=0; entry<NUM_BTB_ENTRIES; entry=entry+1) begin: g_btb_select
    localparam [NUM_BTB_ENTRIES_W-1:0] ENTRY = entry;
    // Preserve the original highest-numbered matching entry, even for
    // duplicate tags (including all PC=0 entries immediately after reset).
    assign select_pc_w[entry] = match_pc_r[entry] &
        ~(|(match_pc_r >> (entry+1)));
    assign select_upper_w[entry] = match_upper_r[entry] &
        ~(|(match_upper_r >> (entry+1)));
    assign select_write_w[entry] = match_write_r[entry] &
        ~(|(match_write_r >> (entry+1)));
    assign btb_payload_w[entry*BTB_PAYLOAD_W +: BTB_PAYLOAD_W] =
        {ENTRY,btb_is_call_q[entry],btb_is_ret_q[entry],btb_is_jmp_q[entry],btb_target_q[entry]};
end

wire btb_valid_r = |match_read_r;
wire btb_is_call_r;
wire btb_is_ret_r;
wire btb_is_jmp_r;
wire [NUM_BTB_ENTRIES_W-1:0] btb_entry_r;
wire [31:0] btb_selected_pc_w;
wire [31:0] btb_next_pc_r = btb_valid_r ? btb_selected_pc_w :
    ({pc_f_i[31:3],3'b0} + 32'd8);
triha_npc_select #(.WIDTH(BTB_PAYLOAD_W),.INPUTS(NUM_BTB_ENTRIES)) u_btb_select (
    .data_i(btb_payload_w),.select_i(select_read_w),
    .data_o({btb_entry_r,btb_is_call_r,btb_is_ret_r,btb_is_jmp_r,btb_selected_pc_w})
);

wire [NUM_BTB_ENTRIES_W-1:0] btb_wr_alloc_w;
wire btb_hit_r = |match_write_r;
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
assign next_pc_f_o   = ras_ret_pred_w      ? ras_pc_pred_w : 
                       (bht_predict_taken_w | btb_is_jmp_r) ? btb_next_pc_r :
                       {pc_f_i[31:3],3'b0} + 32'd8;

assign next_taken_f_o = (btb_valid_w & (ras_ret_pred_w | bht_predict_taken_w | btb_is_jmp_r)) ? 
                        pc_f_i[2] ? {btb_upper_r, 1'b0} :
                        {btb_upper_r, ~btb_upper_r} : 2'b0;

assign pred_taken_w   = btb_valid_w & (ras_ret_pred_w | bht_predict_taken_w | btb_is_jmp_r) & pc_accept_i;
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
    genvar bit_index,input_index;
    generate
    for (bit_index=0; bit_index<WIDTH; bit_index=bit_index+1) begin: g_bit
        wire [INPUTS-1:0] masked_w;
        for (input_index=0; input_index<INPUTS; input_index=input_index+1) begin: g_input
            assign masked_w[input_index] = data_i[input_index*WIDTH+bit_index] & select_i[input_index];
        end
        assign data_o[bit_index] = |masked_w;
    end
    endgenerate
endmodule
