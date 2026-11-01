// Complete B03 Conv/Add quantization, dtype 0U8/1S8/2I16/3U16.
// MODEL Q8: eight exact bias/requantize lanes and thirty-two scalar APMs.
// Private common-CE interface: both input and output retirement require advance.
// E0 bias, E1/E2 APM, E3 parts, E4 product, E5 quotient, E6 RNE, E7 output.
// This unit does not establish complete-K, memory visibility or frame readiness.
module b03_quant4_core (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire run_ce,
    input wire in_valid,
    output wire in_ready,
    input wire [3:0] in_mask,
    input wire [127:0] in_psum,
    input wire [127:0] in_psum_b,
    input wire in_add,
    input wire [1:0] in_dtype,
    input wire [127:0] in_bias,
    input wire [127:0] in_multiplier,
    input wire [127:0] in_multiplier_b,
    input wire [23:0] in_shift,
    input wire [127:0] in_tag,
    output wire out_valid,
    input wire out_ready,
    output wire [3:0] out_mask,
    output wire [63:0] out_values,
    output wire [1:0] out_dtype, output wire out_add,
    output wire [11:0] out_error,
    output wire [127:0] out_tag,
    output wire advance,
    output wire busy
);
    reg [7:0] valid_pipe;
    reg [7:0] add_pipe;
    reg [1:0] dtype_pipe [0:7];
    assign out_add=add_pipe[7];
    assign out_dtype=dtype_pipe[7];
    reg [3:0] mask_pipe [0:7];
    reg [127:0] tag_pipe [0:7];
    wire leaf_clear = !rst_n || clear;
    integer stage;

    assign out_valid = valid_pipe[7];
    assign out_mask = mask_pipe[7];
    assign out_tag = tag_pipe[7];
    assign advance = rst_n && !clear && run_ce && (!out_valid || out_ready);
    assign in_ready = advance;
    assign busy = |valid_pipe;

    // Token state clears immediately with rst_n; leaf reset is synchronous and
    // rst_n must remain low across a clock edge to clear the APM registers too.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 0; add_pipe<=0;
            for (stage=0; stage<8; stage=stage+1) begin
                mask_pipe[stage] <= 0; dtype_pipe[stage]<=0;
                tag_pipe[stage] <= 0;
            end
        end else if (clear) begin
            valid_pipe <= 0; add_pipe<=0;
            for (stage=0; stage<8; stage=stage+1) begin
                mask_pipe[stage] <= 0; dtype_pipe[stage]<=0;
                tag_pipe[stage] <= 0;
            end
        end else if (advance) begin
            valid_pipe <= {valid_pipe[6:0], in_valid};
            add_pipe <= {add_pipe[6:0],in_add};
            dtype_pipe[0]<=in_dtype;
            mask_pipe[0] <= in_valid ? in_mask : 8'b0;
            tag_pipe[0] <= in_valid ? in_tag : 128'b0;
            for (stage=1; stage<8; stage=stage+1) begin
                mask_pipe[stage] <= mask_pipe[stage-1];
                dtype_pipe[stage]<=dtype_pipe[stage-1];
                tag_pipe[stage] <= tag_pipe[stage-1];
            end
        end
    end

    genvar g;
    generate for (g=0; g<4; g=g+1) begin: lane
        wire signed [31:0] psum_in = in_psum[32*g+:32];
        wire signed [31:0] psum_b_in=in_psum_b[32*g+:32];
        wire [31:0] multiplier_b_in=in_multiplier_b[32*g+:32];
        wire signed [31:0] bias_in = in_bias[32*g+:32];
        wire [31:0] multiplier_in = in_multiplier[32*g+:32];
        wire [5:0] shift_in = in_shift[6*g+:6];
        wire signed [32:0] bias_sum =
            $signed({psum_in[31], psum_in}) + $signed({bias_in[31], bias_in});
        wire bias_overflow = bias_sum[32] != bias_sum[31];
        wire [2:0] front_error = !in_mask[g] ? 3'd0 :
            (!in_add && bias_overflow) ? 3'd1 :
            (in_add && (psum_in < -255 || psum_in > 255 || psum_b_in < -255 || psum_b_in > 255 || bias_in!=0)) ? 3'd5 :
            (multiplier_in==0 || multiplier_in[31] || (in_add && (multiplier_b_in==0 || multiplier_b_in[31]))) ? 3'd2 :
            (shift_in==0 || shift_in>62) ? 3'd3 : 3'd0;
        wire front_good = in_valid && in_mask[g] && front_error==0;

        reg signed [31:0] a0,b0;
        reg [31:0] multiplier_b0;
        reg [31:0] multiplier0;
        reg [5:0] shift_pipe [0:6];
        reg [2:0] error_pipe [0:7];
        wire leaf_in_valid = valid_pipe[0] && mask_pipe[0][g] && error_pipe[0]==0;
        wire signed [24:0] a_lo = add_pipe[0] ? $signed(a0[24:0]) : $signed({9'b0, a0[15:0]});
        wire signed [24:0] a_hi = add_pipe[0] ? $signed(b0[24:0]) : $signed({{9{a0[31]}}, a0[31:16]});
        wire signed [17:0] mb_lo=$signed({2'b0,multiplier_b0[15:0]});
        wire signed [17:0] mb_hi=$signed({3'b0,multiplier_b0[30:16]});
        wire signed [17:0] m_lo = $signed({2'b0, multiplier0[15:0]});
        wire signed [17:0] m_hi = $signed({3'b0, multiplier0[30:16]});

        wire signed [47:0] p00, p01, p10, p11;
        wire p00_valid, p01_valid, p10_valid, p11_valid;
        wire [1:0] p00_mode, p01_mode, p10_mode, p11_mode;
        wire [31:0] p00_epoch, p01_epoch, p10_epoch, p11_epoch;
        wire p00_busy, p01_busy, p10_busy, p11_busy;

        b03_mul25x18_loan mul00 (
            .clk(clk), .clear(leaf_clear), .run_ce(advance), .in_valid(leaf_in_valid),
            .x(a_lo), .y(m_lo), .mode(2'd1), .epoch(tag_pipe[0][31:0]),
            .product(p00), .out_valid(p00_valid), .out_mode(p00_mode),
            .out_epoch(p00_epoch), .busy(p00_busy));
        b03_mul25x18_loan mul01 (
            .clk(clk), .clear(leaf_clear), .run_ce(advance), .in_valid(leaf_in_valid),
            .x(a_lo), .y(m_hi), .mode(2'd1), .epoch(tag_pipe[0][31:0]),
            .product(p01), .out_valid(p01_valid), .out_mode(p01_mode),
            .out_epoch(p01_epoch), .busy(p01_busy));
        b03_mul25x18_loan mul10 (
            .clk(clk), .clear(leaf_clear), .run_ce(advance), .in_valid(leaf_in_valid),
            .x(a_hi), .y(add_pipe[0] ? mb_lo : m_lo), .mode(2'd1), .epoch(tag_pipe[0][31:0]),
            .product(p10), .out_valid(p10_valid), .out_mode(p10_mode),
            .out_epoch(p10_epoch), .busy(p10_busy));
        b03_mul25x18_loan mul11 (
            .clk(clk), .clear(leaf_clear), .run_ce(advance), .in_valid(leaf_in_valid),
            .x(a_hi), .y(add_pipe[0] ? mb_hi : m_hi), .mode(2'd1), .epoch(tag_pipe[0][31:0]),
            .product(p11), .out_valid(p11_valid), .out_mode(p11_mode),
            .out_epoch(p11_epoch), .busy(p11_busy));

        wire expected_return = valid_pipe[2] && mask_pipe[2][g] && error_pipe[2]==0;
        wire leaf_mismatch = !(p00_valid && p01_valid && p10_valid && p11_valid) ||
            p00_mode!=2'd1 || p01_mode!=2'd1 || p10_mode!=2'd1 || p11_mode!=2'd1 ||
            p00_epoch!=tag_pipe[2][31:0] || p01_epoch!=tag_pipe[2][31:0] ||
            p10_epoch!=tag_pipe[2][31:0] || p11_epoch!=tag_pipe[2][31:0];

        reg signed [32:0] low3;
        reg signed [33:0] middle3;
        reg signed [31:0] high3;
        reg signed [63:0] product4;
        reg signed [17:0] quotient5;
        reg signed [18:0] rounded6;
        reg round_up5,wide5,negative5,wide6,negative6;
        reg [15:0] value7;
        // Base-2^16 carry composition avoids two wide shifted I64 adders.
        // low3 = low16 + 2^16*low_carry for both signs. Repeat once for
        // middle_plus, then concatenate the exact two's-complement product.
        wire signed [33:0] middle_plus=middle3+$signed({{17{low3[32]}},low3[32:16]});
        wire signed [32:0] high_plus=$signed({high3[31],high3})+
            $signed({{15{middle_plus[33]}},middle_plus[33:16]});
        wire signed [63:0] combined4={high_plus[31:0],middle_plus[15:0],low3[15:0]};
        // Only the clipped output is public. A signed 18-bit quotient covers
        // every target interval, including one extra bit beyond U16.
        reg signed [24:0] quotient_window;
        reg outside_window;
        always @* begin
            quotient_window=0;outside_window=0;
            case(shift_pipe[4][5:3])
            0:begin quotient_window=product4[0+:25];outside_window=product4[63:25]!={39{product4[63]}};end
            1:begin quotient_window=product4[8+:25];outside_window=product4[63:33]!={31{product4[63]}};end
            2:begin quotient_window=product4[16+:25];outside_window=product4[63:41]!={23{product4[63]}};end
            3:begin quotient_window=product4[24+:25];outside_window=product4[63:49]!={15{product4[63]}};end
            4:begin quotient_window=product4[32+:25];outside_window=product4[63:57]!={7{product4[63]}};end
            5:quotient_window={{1{product4[63]}},product4[63:40]};
            6:quotient_window={{9{product4[63]}},product4[63:48]};
            7:quotient_window={{17{product4[63]}},product4[63:56]};
            endcase
        end
        wire signed [24:0] window_shifted=quotient_window >>> shift_pipe[4][2:0];
        wire wide_next=outside_window || window_shifted[24:17]!={8{product4[63]}};
        wire [5:0] guard_index=shift_pipe[4]-6'd1;
        wire [7:0] guard_byte=product4[8*guard_index[5:3]+:8];
        reg prefix_sticky;
        always @* case(guard_index[5:3])
            0:prefix_sticky=0;1:prefix_sticky=|product4[7:0];
            2:prefix_sticky=|product4[15:0];3:prefix_sticky=|product4[23:0];
            4:prefix_sticky=|product4[31:0];5:prefix_sticky=|product4[39:0];
            6:prefix_sticky=|product4[47:0];7:prefix_sticky=|product4[55:0];
        endcase
        wire [7:0] fine_mask=(8'h01<<guard_index[2:0])-8'd1;
        wire sticky=prefix_sticky || (|(guard_byte&fine_mask));
        wire increment_next=guard_byte[guard_index[2:0]] && (sticky || window_shifted[0]);
        integer s;

        assign out_values[16*g+:16] = value7;
        assign out_error[3*g+:3] = error_pipe[7];

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                value7<=0;
                for (s=0; s<8; s=s+1) error_pipe[s]<=0;
            end else if (clear) begin
                value7<=0;
                for (s=0; s<8; s=s+1) error_pipe[s]<=0;
            end else if (advance) begin
                a0 <= front_good ? (in_add ? psum_in : bias_sum[31:0]) : 32'b0;
                b0<=front_good && in_add ? psum_b_in : 32'b0;
                multiplier_b0<=front_good && in_add ? multiplier_b_in : 32'd1;
                multiplier0 <= front_good ? multiplier_in : 32'd1;
                shift_pipe[0] <= front_good ? shift_in : 6'd1;
                error_pipe[0] <= in_valid ? front_error : 3'd0;
                for (s=1; s<7; s=s+1) shift_pipe[s]<=shift_pipe[s-1];
                for (s=1; s<8; s=s+1) error_pipe[s]<=error_pipe[s-1];

                // Missing/mismatched leaf output retires as an error token;
                // it must not gate progress or borrow a neighbouring result.
                if (expected_return && !leaf_mismatch) begin
                    low3 <= add_pipe[2] ? $signed(p00[32:0])+$signed(p10[32:0]) : $signed(p00[32:0]);
                    middle3 <= add_pipe[2] ? $signed(p01[33:0])+$signed(p11[33:0]) : $signed(p01[33:0])+$signed(p10[33:0]);
                    high3 <= add_pipe[2] ? 32'sd0 : p11[31:0];
                end else begin
                    low3<=0; middle3<=0; high3<=0;
                end
                if (expected_return && leaf_mismatch) error_pipe[3] <= 3'd4;

                product4 <= valid_pipe[3] && mask_pipe[3][g] && error_pipe[3]==0 ? combined4 : 64'b0;
                quotient5 <= window_shifted[17:0];
                wide5<=wide_next;negative5<=product4[63];
                round_up5 <= increment_next;
                wide6<=wide5;negative6<=negative5;
                rounded6 <= $signed({quotient5[17],quotient5}) + (round_up5 ? 19'sd1 : 19'sd0);
                if (valid_pipe[6] && mask_pipe[6][g] && error_pipe[6]==0) begin
                    if(wide6)case(dtype_pipe[6])
                    0:value7<=negative6?16'd0:16'd255;
                    1:value7<=negative6?16'hff81:16'd127;
                    2:value7<=negative6?16'h8001:16'h7fff;
                    3:value7<=negative6?16'd0:16'hffff;
                    endcase
                    else case(dtype_pipe[6])
                    0:value7<=rounded6<0 ? 16'd0 : rounded6>255 ? 16'd255 : {8'b0,rounded6[7:0]};
                    1:value7<=rounded6 < -127 ? 16'hff81 : rounded6>127 ? 16'd127 : {{8{rounded6[7]}},rounded6[7:0]};
                    2:value7<=rounded6 < -32767 ? 16'h8001 : rounded6>32767 ? 16'h7fff : rounded6[15:0];
                    3:value7<=rounded6<0 ? 16'd0 : rounded6>65535 ? 16'hffff : rounded6[15:0];
                    endcase
                end else begin
                    value7<=0;
                end
            end
        end
    end endgenerate
endmodule
