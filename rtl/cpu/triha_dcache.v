/*
 * @file       triha_dcache.v
 * @brief      TriHa blocking 16KiB two-way write-through data cache
 * @details    256 sets, 32B line; read allocate, no write allocate or dirty state.
 *             Synchronous tag/data organization and two-way replacement are
 *             adapted from the fixed source recorded in CACHE_ADAPTATIONS.json.
 *             Complete stores only after lower response; invalidate on failure.
 *             Stores bypass unused lookup/response bubbles; load data retains
 *             its response register to isolate Cache RAM from CPU bypass logic.
 * SPDX-License-Identifier: Apache-2.0
 * Derived storage/lookup organization: Copyright 2020 Ultra-Embedded.com.
 */
module triha_dcache #(
    parameter integer CACHE_ENABLE = 1
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [31:0] mem_addr_i,
    input  wire [31:0] mem_data_wr_i,
    input  wire        mem_rd_i,
    input  wire [3:0]  mem_wr_i,
    input  wire        mem_cacheable_i,
    input  wire [10:0] mem_req_tag_i,
    input  wire        mem_invalidate_i,
    input  wire        mem_writeback_i,
    input  wire        mem_flush_i,
    output wire [31:0] mem_data_rd_o,
    output wire        mem_accept_o,
    output wire        mem_ack_o,
    output wire        mem_error_o,
    output wire [10:0] mem_resp_tag_o,
    input  wire        outport_accept_i,
    input  wire        outport_ack_i,
    input  wire        outport_error_i,
    input  wire [31:0] outport_read_data_i,
    output wire [3:0]  outport_wr_o,
    output wire        outport_rd_o,
    output wire [7:0]  outport_len_o,
    output wire [31:0] outport_addr_o,
    output wire [31:0] outport_write_data_o
);
    localparam [3:0] RESET = 0, IDLE = 1, LOOKUP = 2, REFILL_REQ = 3,
        REFILL = 4, RELOOKUP = 5, RESPONSE = 6, WRITE_REQ = 7,
        WRITE_WAIT = 8, STORE_UPDATE = 9, UNCACHED_REQ = 10,
        UNCACHED_WAIT = 11, INVALIDATE = 12, FLUSH = 13;
    reg [3:0] state_q;
    reg [31:0] addr_q, write_data_q, response_data_q;
    reg [3:0] write_mask_q;
    reg [10:0] request_tag_q;
    reg cacheable_q, response_error_q, refill_error_q;
    reg [7:0] sweep_q;
    reg [2:0] fill_beat_q;
    reg fill_way_q, replace_way_q;
    wire request_w = mem_rd_i || |mem_wr_i || mem_invalidate_i || mem_writeback_i || mem_flush_i;
    wire private_address_w = mem_addr_i >= 32'h80000000 && mem_addr_i < 32'h82000000;
    wire [7:0] lookup_set_w = state_q == IDLE ? mem_addr_i[12:5] : addr_q[12:5];
    wire [10:0] lookup_word_w = state_q == IDLE ? mem_addr_i[12:2] : addr_q[12:2];
    wire [19:0] tag0_w, tag1_w;
    wire hit0_w = tag0_w[19] && tag0_w[18:0] == addr_q[31:13];
    wire hit1_w = tag1_w[19] && tag1_w[18:0] == addr_q[31:13];
    wire hit_w = hit0_w || hit1_w;
    wire choose_way_w = !tag0_w[19] ? 1'b0 : !tag1_w[19] ? 1'b1 : replace_way_q;
    wire miss_w = state_q == LOOKUP && cacheable_q && !(|write_mask_q) && !hit_w;
    wire fill_response_w = outport_ack_i &&
        (state_q == REFILL || (state_q == REFILL_REQ && outport_accept_i));
    wire store_response_w = outport_ack_i &&
        (state_q == WRITE_WAIT || (state_q == WRITE_REQ && outport_accept_i));
    wire uncached_response_w = outport_ack_i &&
        (state_q == UNCACHED_WAIT || (state_q == UNCACHED_REQ && outport_accept_i));

    reg tag0_write_r, tag1_write_r;
    reg [19:0] tag_write_data_r;
    wire [7:0] tag_write_addr_w = state_q == RESET || state_q == FLUSH ? sweep_q : addr_q[12:5];
    always @* begin
        tag0_write_r = 0;
        tag1_write_r = 0;
        tag_write_data_r = {1'b0, addr_q[31:13]};
        if (state_q == RESET || state_q == FLUSH) begin
            tag0_write_r = 1;
            tag1_write_r = 1;
            tag_write_data_r = 0;
        end else if (miss_w) begin
            // Remove the victim before any partial refill can change data.
            tag0_write_r = !choose_way_w;
            tag1_write_r = choose_way_w;
        end else if (fill_response_w && fill_beat_q == 7) begin
            tag0_write_r = !fill_way_q;
            tag1_write_r = fill_way_q;
            tag_write_data_r[19] = !(refill_error_q || outport_error_i);
        end else if (state_q == INVALIDATE ||
                     (state_q == STORE_UPDATE && response_error_q && cacheable_q)) begin
            tag0_write_r = hit0_w;
            tag1_write_r = hit1_w;
        end
    end
    triha_dcache_tag_ram u_tag0 (
        .clk0_i(clk_i), .rst0_i(!rst_ni), .addr0_i(lookup_set_w),
        .clk1_i(clk_i), .rst1_i(!rst_ni), .addr1_i(tag_write_addr_w),
        .data1_i(tag_write_data_r), .wr1_i(tag0_write_r), .data0_o(tag0_w)
    );
    triha_dcache_tag_ram u_tag1 (
        .clk0_i(clk_i), .rst0_i(!rst_ni), .addr0_i(lookup_set_w),
        .clk1_i(clk_i), .rst1_i(!rst_ni), .addr1_i(tag_write_addr_w),
        .data1_i(tag_write_data_r), .wr1_i(tag1_write_r), .data0_o(tag1_w)
    );
    wire [31:0] data0_w, data1_w;
    wire [10:0] data_write_addr_w = fill_response_w ? {addr_q[12:5], fill_beat_q} : addr_q[12:2];
    wire [31:0] data_write_w = fill_response_w ? outport_read_data_i : write_data_q;
    wire store_update_w = state_q == STORE_UPDATE && !response_error_q && cacheable_q;
    wire [3:0] data0_mask_w = fill_response_w && !fill_way_q ? 4'hf :
        store_update_w && hit0_w ? write_mask_q : 4'b0;
    wire [3:0] data1_mask_w = fill_response_w && fill_way_q ? 4'hf :
        store_update_w && hit1_w ? write_mask_q : 4'b0;
    triha_dcache_data_ram u_data0 (
        .clk0_i(clk_i), .rst0_i(!rst_ni), .addr0_i(lookup_word_w), .data0_i(32'b0),
        .wr0_i(4'b0), .data0_o(data0_w), .clk1_i(clk_i), .rst1_i(!rst_ni),
        .addr1_i(data_write_addr_w), .data1_i(data_write_w), .wr1_i(data0_mask_w), .data1_o()
    );
    triha_dcache_data_ram u_data1 (
        .clk0_i(clk_i), .rst0_i(!rst_ni), .addr0_i(lookup_word_w), .data0_i(32'b0),
        .wr0_i(4'b0), .data0_o(data1_w), .clk1_i(clk_i), .rst1_i(!rst_ni),
        .addr1_i(data_write_addr_w), .data1_i(data_write_w), .wr1_i(data1_mask_w), .data1_o()
    );
    assign mem_accept_o = rst_ni && state_q == IDLE;
    assign mem_ack_o = rst_ni && (state_q == STORE_UPDATE || state_q == RESPONSE);
    assign mem_error_o = response_error_q;
    assign mem_data_rd_o = response_data_q;
    assign mem_resp_tag_o = request_tag_q;
    assign outport_rd_o = rst_ni && (state_q == REFILL_REQ || state_q == UNCACHED_REQ);
    assign outport_wr_o = rst_ni && state_q == WRITE_REQ ? write_mask_q : 4'b0;
    assign outport_len_o = state_q == REFILL_REQ ? 8'd7 : 8'd0;
    assign outport_addr_o = state_q == REFILL_REQ ? {addr_q[31:5], 5'b0} : {addr_q[31:2], 2'b0};
    assign outport_write_data_o = write_data_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= RESET;
            addr_q <= 0; write_data_q <= 0; write_mask_q <= 0;
            request_tag_q <= 0; cacheable_q <= 0;
            response_data_q <= 0; response_error_q <= 0; refill_error_q <= 0;
            sweep_q <= 0; fill_beat_q <= 0; fill_way_q <= 0; replace_way_q <= 0;
        end else begin
            case (state_q)
                RESET: begin
                    sweep_q <= sweep_q + 1'b1;
                    if (sweep_q == 255) state_q <= IDLE;
                end
                IDLE: if (request_w) begin
                    addr_q <= mem_addr_i;
                    write_data_q <= mem_data_wr_i;
                    write_mask_q <= mem_wr_i;
                    request_tag_q <= mem_req_tag_i;
                    cacheable_q <= CACHE_ENABLE && mem_cacheable_i && private_address_w;
                    response_error_q <= 0;
                    response_data_q <= 0;
                    if (mem_flush_i) begin sweep_q <= 0; state_q <= FLUSH; end
                    else if (mem_invalidate_i) state_q <= INVALIDATE;
                    else if (mem_writeback_i) state_q <= RESPONSE;
                    else if (mem_addr_i[1:0] != 0 || (mem_rd_i && |mem_wr_i)) begin
                        response_error_q <= 1; state_q <= RESPONSE;
                    end else if (|mem_wr_i) state_q <= WRITE_REQ;
                    else state_q <= LOOKUP;
                end
                LOOKUP: begin
                    if (|write_mask_q) state_q <= WRITE_REQ;
                    else if (!cacheable_q) state_q <= UNCACHED_REQ;
                    else if (hit_w) begin
                        response_data_q <= hit0_w ? data0_w : data1_w;
                        state_q <= RESPONSE;
                    end else begin
                        fill_way_q <= choose_way_w;
                        fill_beat_q <= 0;
                        refill_error_q <= 0;
                        state_q <= REFILL_REQ;
                    end
                end
                REFILL_REQ: if (outport_accept_i) state_q <= REFILL;
                REFILL: begin end
                RELOOKUP: state_q <= LOOKUP;
                WRITE_REQ: if (outport_accept_i) state_q <= WRITE_WAIT;
                WRITE_WAIT: begin end
                STORE_UPDATE: state_q <= IDLE;
                UNCACHED_REQ: if (outport_accept_i) state_q <= UNCACHED_WAIT;
                UNCACHED_WAIT: begin end
                INVALIDATE: state_q <= RESPONSE;
                FLUSH: begin
                    sweep_q <= sweep_q + 1'b1;
                    if (sweep_q == 255) state_q <= RESPONSE;
                end
                RESPONSE: state_q <= IDLE;
                default: state_q <= RESET;
            endcase
            if (fill_response_w) begin
                refill_error_q <= refill_error_q || outport_error_i;
                fill_beat_q <= fill_beat_q + 1'b1;
                if (fill_beat_q == 7) begin
                    if (refill_error_q || outport_error_i) begin
                        response_error_q <= 1;
                        state_q <= RESPONSE;
                    end else begin
                        replace_way_q <= !fill_way_q;
                        state_q <= RELOOKUP;
                    end
                end
            end
            if (store_response_w) begin
                response_error_q <= outport_error_i;
                state_q <= STORE_UPDATE;
            end
            if (uncached_response_w) begin
                response_data_q <= outport_read_data_i;
                response_error_q <= outport_error_i;
                state_q <= RESPONSE;
            end
        end
    end
endmodule
