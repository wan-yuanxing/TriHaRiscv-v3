// 16 spatial rows x 16 output channels, 128 real SIMD postacc APMs.
// Each accepted vector performs one K contribution. All accumulators commit
// atomically, or none do when a front/return/control error is detected.
// Bounded K<=128, weights[-127,127], no arbitrary P reload.
// The complete raw sum fits signed 23 bits; hardware P lanes are signed 24.
module b03_array_apmacc_rowctrl #(
    // CPU-post board mode does not consume per-lane return/overflow
    // diagnostics.  Keeping the parameter here lets synthesis remove the
    // wide reduction network without changing the arithmetic datapath.
    parameter integer ENABLE_DIAGNOSTICS = 1,
    parameter integer M_LANES = 16
)(
    input wire clk, rst_n, clear, run_ce,
    input wire init_valid,
    output wire init_ready,
    input wire [15:0] init_m_mask, init_co_mask,
    input wire init_signed,
    input wire [127:0] init_tag,
    input wire zero_valid,
    output wire zero_ready,
    input wire load_valid,
    output wire load_ready,
    input wire [5:0] load_index,
    input wire [127:0] load_data,
    input wire pipe_clear,
    input wire in_valid,
    output wire in_ready,
    input wire [127:0] in_a, in_b,
    input wire [7:0] in_k,
    input wire [127:0] in_tag,
    output wire [8191:0] acc_flat,
    output wire busy,
    output reg active,
    output reg [3:0] fault,
    output reg [7:0] fault_lane,
    output wire retire_valid,
    output wire [7:0] retire_k,
    output wire [127:0] retire_tag
);
    reg [15:0] m_mask, co_mask;
    reg task_signed;
    reg [127:0] task_tag;
    reg [8:0] expected_k;
    reg [1:0] valid_pipe, good_pipe;
    reg [7:0] k_pipe [0:1];
    reg [127:0] tag_pipe [0:1];
    wire ce = rst_n && !clear && run_ce;
    wire control_present = init_valid || zero_valid || load_valid || pipe_clear;
    wire [2:0] control_count = {2'b0,init_valid} + {2'b0,zero_valid} +
                                {2'b0,load_valid} + {2'b0,pipe_clear};
    wire control_conflict = control_count > 1 || (control_present && in_valid);
    assign busy = |valid_pipe;
    // Along with the pending token, this event is sampled BEFORE the E2 edge.
    // CE=0 suppresses the event, so a held token cannot be counted twice.
    assign retire_valid = ce && valid_pipe[1];
    assign retire_k = k_pipe[1];
    assign retire_tag = tag_pipe[1];
    assign init_ready = ce && !busy && !control_conflict;
    assign zero_ready = ce && active && !busy && fault==0 && !control_conflict;
    assign load_ready = ce && active && !busy && fault==0 && !control_conflict && 1'b0;
    assign in_ready = ce && active && fault==0 && !control_present;
    wire init_fire = init_valid && init_ready;
    wire zero_fire = zero_valid && zero_ready;
    wire load_fire = load_valid && load_ready;
    wire pipe_clear_fire = ce && pipe_clear && active && !busy && fault==0 && !control_conflict;
    wire accept = in_valid && in_ready;
    wire leaf_clear = clear || init_fire || pipe_clear_fire;

    // The complete tag is checked centrally. Each leaf independently returns
    // the K index and epoch, avoiding 128 copies of the full 128-bit identity.
    reg [3:0] front_error;
    reg [7:0] front_lane;
    integer fm, fc;
    reg [15:0] bad_weights;
    reg [3:0] first_m, first_co;
    always @* begin
        bad_weights=0;first_m=0;first_co=0;
        for(fc=0;fc<16;fc=fc+1)bad_weights[fc]=co_mask[fc]&&in_b[8*fc+:8]==8'h80;
        for(fm=15;fm>=0;fm=fm-1)if(m_mask[fm])first_m=fm;
        for(fc=15;fc>=0;fc=fc-1)if(bad_weights[fc])first_co=fc;
        front_error=0;front_lane=0;
        if(in_k[7] || {1'b0,in_k}!=expected_k || in_tag!=task_tag)front_error=4'd2;
        else if((|m_mask)&&(|bad_weights))begin front_error=4'd1;front_lane={first_m,first_co};end
    end
    wire front_good = accept && front_error==0;
    wire [127:0] return_bad;
    wire [255:0] overflow;
    wire commit;
    // CEP is the sole accumulator mutation authority. The multiplier may
    // compute discarded bubbles; only disabled Co requires a shared zero B.
    genvar m, p;
    generate for (m=0; m<M_LANES; m=m+1) begin: row
        wire row_ce,row_apm_reset,row_apm_preset;
        (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) ce_buffer(.I0(ce),.Z(row_ce));
        (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) reset_buffer(.I0(!rst_n||leaf_clear),.Z(row_apm_reset));
        (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) preset_buffer(.I0(!rst_n||clear||init_fire||zero_fire),.Z(row_apm_preset));
        for (p=0; p<8; p=p+1) begin: pair
            localparam C0=2*p, C1=2*p+1;
            localparam I0=16*m+C0, I1=16*m+C1;
            wire enabled = m_mask[m] && (co_mask[C0] || co_mask[C1]);
            wire signed [23:0] product0, product1;
            wire leaf_valid, leaf_busy;
            wire [7:0] leaf_k;
            wire [31:0] leaf_epoch;
            b03_mac_pair_rowctrl leaf (
                .clk(clk), .rst_n(rst_n), .clear(leaf_clear), .run_ce(row_ce),
                .acc_clear(clear||init_fire||zero_fire),.acc_commit(commit&&enabled),
                .apm_reset(row_apm_reset),.apm_preset(row_apm_preset),
                .in_valid(front_good && enabled),
                .in_a0(in_a[8*m+:8]),
                .in_a1(in_a[8*m+:8]),
                .input_signed(task_signed),
                .in_w0(co_mask[C0] ? in_b[8*C0+:8] : 8'b0),
                .in_w1(co_mask[C1] ? in_b[8*C1+:8] : 8'b0),
                .in_k(in_k), .in_epoch(in_tag[31:0]),
                .product0(product0), .product1(product1), .out_valid(leaf_valid),
                .out_k(leaf_k), .out_epoch(leaf_epoch), .busy(leaf_busy));
            if (ENABLE_DIAGNOSTICS) begin : g_diag_leaf
                assign return_bad[8*m+p] = enabled &&
                    (!leaf_valid || leaf_k!=k_pipe[1] || leaf_epoch!=tag_pipe[1][31:0]);
            end else begin : g_no_diag_leaf
                assign return_bad[8*m+p] = 1'b0;
            end
            if (ENABLE_DIAGNOSTICS) begin : g_diag_overflow
                assign overflow[I0]=1'b0;
                assign overflow[I1]=1'b0;
            end else begin : g_no_diag_overflow
                assign overflow[I0]=1'b0;
                assign overflow[I1]=1'b0;
            end
            assign acc_flat[32*I0+:32]={{8{product0[23]}},product0};
            assign acc_flat[32*I1+:32]={{8{product1[23]}},product1};

        end
    end endgenerate
    // The layer keeps a fixed 16-row accumulator ABI.  A reduced profile
    // computes only the active M_LANES rows and ties the unused rows low so
    // the quantizer sees the same record layout.
    if (M_LANES < 16) begin : g_unused_rows
        assign acc_flat[8191:32*(16*M_LANES)] = {(8192-32*(16*M_LANES)){1'b0}};
    end

    reg [3:0] return_error;
    reg [7:0] return_lane;
    integer rm, rc;
    reg [15:0] bad_rows,overflow_rows;
    reg [3:0] first_bad_row,first_overflow_row,first_overflow_co;
    reg [2:0] first_bad_pair;
    reg [7:0] bad_row_pairs;
    reg [15:0] overflow_row_co;
    always @* begin
        bad_rows=0;overflow_rows=0;first_bad_row=0;first_overflow_row=0;first_bad_pair=0;first_overflow_co=0;
        return_error=0;return_lane=0;
        bad_row_pairs=0;overflow_row_co=0;
        if (ENABLE_DIAGNOSTICS) begin
            for(rm=0;rm<16;rm=rm+1)begin
                bad_rows[rm]=|return_bad[8*rm+:8];overflow_rows[rm]=|overflow[16*rm+:16];
            end
            for(rm=15;rm>=0;rm=rm-1)begin
                if(bad_rows[rm])first_bad_row=rm;
                if(overflow_rows[rm])first_overflow_row=rm;
            end
            bad_row_pairs=return_bad[8*first_bad_row+:8];overflow_row_co=overflow[16*first_overflow_row+:16];
            for(rc=7;rc>=0;rc=rc-1)if(bad_row_pairs[rc])first_bad_pair=rc;
            for(rc=15;rc>=0;rc=rc-1)if(overflow_row_co[rc])first_overflow_co=rc;
            if(valid_pipe[1]&&good_pipe[1])begin
                if(|bad_rows)begin return_error=3;return_lane={first_bad_row,first_bad_pair,!co_mask[{first_bad_pair,1'b0}]};end
                else if(|overflow_rows)begin return_error=4;return_lane={first_overflow_row,first_overflow_co};end
            end
        end
    end
    wire unsupported_load=load_valid;
    wire fault_now = control_conflict || unsupported_load || return_error!=0 || (accept && front_error!=0);
    assign commit = ce && valid_pipe[1] && good_pipe[1] && fault==0 && !fault_now;
    integer i, li;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            task_signed<=0; active<=0; fault<=0; fault_lane<=0; m_mask<=0; co_mask<=0; task_tag<=0;
            expected_k<=0; valid_pipe<=0; good_pipe<=0;
            k_pipe[0]<=0; k_pipe[1]<=0; tag_pipe[0]<=0; tag_pipe[1]<=0;
        end else if (clear) begin
            task_signed<=0; active<=0; fault<=0; fault_lane<=0; m_mask<=0; co_mask<=0; task_tag<=0;
            expected_k<=0; valid_pipe<=0; good_pipe<=0;
            k_pipe[0]<=0; k_pipe[1]<=0; tag_pipe[0]<=0; tag_pipe[1]<=0;
        end else if (ce) begin
            valid_pipe<={valid_pipe[0],accept};
            good_pipe<={good_pipe[0],front_good};
            k_pipe[0]<=in_k; k_pipe[1]<=k_pipe[0];
            tag_pipe[0]<=in_tag; tag_pipe[1]<=tag_pipe[0];
            if (accept && front_error==0) expected_k<=expected_k+9'd1;
            if (fault==0) begin
                if (control_conflict) begin fault<=4'd5; fault_lane<=0; end
                else if(unsupported_load)begin fault<=4'd6;fault_lane<=0;end
                else if (return_error!=0) begin fault<=return_error; fault_lane<=return_lane; end
                else if (accept && front_error!=0) begin fault<=front_error; fault_lane<=front_lane; end
            end
            if (init_fire) begin
                task_signed<=init_signed; active<=1; m_mask<=init_m_mask; co_mask<=init_co_mask; task_tag<=init_tag;
                expected_k<=0; fault<=0; fault_lane<=0; valid_pipe<=0; good_pipe<=0;
                k_pipe[0]<=0; k_pipe[1]<=0; tag_pipe[0]<=0; tag_pipe[1]<=0;
                end else if (pipe_clear_fire) begin
                valid_pipe<=0; good_pipe<=0;
                k_pipe[0]<=0; k_pipe[1]<=0; tag_pipe[0]<=0; tag_pipe[1]<=0;
            end
        end
    end
endmodule
