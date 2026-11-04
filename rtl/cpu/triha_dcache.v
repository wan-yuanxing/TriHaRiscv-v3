/*
 * @file       triha_dcache.v
 * @brief      TriHa blocking 16KiB two-way write-back data cache
 * @details    256 sets, 32B line; read/write allocate and dirty eviction.
 *             Private DDR is cacheable; shared DDR and MMIO always bypass.
 *             The lower port is scalar for writeback words so the existing
 *             response-checked DDR bridge remains authoritative.
 *             Load data retains the registered response boundary required by
 *             the accepted 100MHz implementation.
 * Derived from the fixed source recorded in CACHE_ADAPTATIONS.json.
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
    localparam [4:0] RESET=0, IDLE=1, LOOKUP=2, REFILL_REQ=3,
        REFILL=4, RELOOKUP=5, RESPONSE=6, STORE_UPDATE=7,
        UNCACHED_REQ=8, UNCACHED_WAIT=9, INVALIDATE=10,
        MAINT_CHECK=11, MAINT_ADV=12, WB_READ=13, WB_REQ=14,
        WB_WAIT=15, MAINT_READ=16, CLEAN=17;
    localparam [1:0] WB_MISS=0, WB_CLEAN=1, WB_MAINT=2;

    reg [4:0] state_q;
    reg [31:0] addr_q, write_data_q, response_data_q;
    reg [3:0] write_mask_q;
    reg [10:0] request_tag_q;
    reg cacheable_q, response_error_q, refill_error_q, mem_rd_q;
    reg [7:0] sweep_q;
    reg sweep_way_q, fill_way_q, replace_way_q;
    reg [2:0] fill_beat_q, wb_word_q;
    reg [1:0] wb_context_q;
    reg [31:0] wb_base_q;
    reg wb_way_q;

    wire request_w = mem_rd_i || |mem_wr_i || mem_invalidate_i ||
                     mem_writeback_i || mem_flush_i;
    wire private_address_w = mem_addr_i >= 32'h80000000 &&
                             mem_addr_i < 32'h82000000;
    // Reuse the completion edge for the next synchronous lookup. Old data
    // and tag still come from response registers. Keep writes and errors
    // serialized: read-first RAM must not hide a just-written dirty bit.
    wire accept_phase_w = state_q == IDLE ||
        (state_q == RESPONSE && mem_rd_q && cacheable_q && !response_error_q);
    wire maintenance_state_w = state_q == MAINT_CHECK || state_q == MAINT_ADV || state_q == MAINT_READ;
    wire [7:0] lookup_set_w = maintenance_state_w ? sweep_q :
                               (accept_phase_w ? mem_addr_i[12:5] : addr_q[12:5]);
    wire [10:0] lookup_word_w = (state_q == WB_READ || state_q == WB_REQ ||
                                 state_q == WB_WAIT) ?
                                {wb_base_q[12:5], wb_word_q} :
                                (accept_phase_w ? mem_addr_i[12:2] : addr_q[12:2]);
    wire [20:0] tag0_w, tag1_w;
    wire hit0_w = tag0_w[20] && tag0_w[18:0] == addr_q[31:13];
    wire hit1_w = tag1_w[20] && tag1_w[18:0] == addr_q[31:13];
    wire hit_w = hit0_w || hit1_w;
    wire choose_way_w = !tag0_w[20] ? 1'b0 : !tag1_w[20] ? 1'b1 : replace_way_q;
    wire victim_dirty_w = choose_way_w ? (tag1_w[20] && tag1_w[19]) :
                                         (tag0_w[20] && tag0_w[19]);
    wire [18:0] victim_tag_w = choose_way_w ? tag1_w[18:0] : tag0_w[18:0];
    wire invalidate_dirty_w = hit1_w ? tag1_w[19] : hit0_w ? tag0_w[19] : 1'b0;
    wire [18:0] invalidate_tag_w = hit1_w ? tag1_w[18:0] : tag0_w[18:0];
    wire maint_valid_w = sweep_way_q ? tag1_w[20] : tag0_w[20];
    wire maint_dirty_w = sweep_way_q ? tag1_w[19] : tag0_w[19];
    wire [18:0] maint_tag_w = sweep_way_q ? tag1_w[18:0] : tag0_w[18:0];
    wire fill_response_w = outport_ack_i &&
        (state_q == REFILL || (state_q == REFILL_REQ && outport_accept_i));
    wire uncached_response_w = outport_ack_i &&
        (state_q == UNCACHED_WAIT || (state_q == UNCACHED_REQ && outport_accept_i));
    wire wb_response_w = outport_ack_i &&
        (state_q == WB_WAIT || (state_q == WB_REQ && outport_accept_i));

    reg tag0_write_r, tag1_write_r;
    reg [20:0] tag_write_data_r;
    wire [7:0] tag_write_addr_w = state_q == RESET ? sweep_q :
                                  (state_q == WB_WAIT || state_q == WB_REQ ||
                                   state_q == WB_READ) ? wb_base_q[12:5] :
                                  maintenance_state_w ? sweep_q : addr_q[12:5];
    wire wb_last_success_w = wb_response_w && !outport_error_i && wb_word_q == 7;
    wire wb_tag_write_w = wb_last_success_w;
    always @* begin
        tag0_write_r = 1'b0;
        tag1_write_r = 1'b0;
        tag_write_data_r = {1'b0, 1'b0, addr_q[31:13]};
        if (state_q == RESET) begin
            tag0_write_r = 1'b1;
            tag1_write_r = 1'b1;
            tag_write_data_r = 21'b0;
        end else if (state_q == LOOKUP && cacheable_q && !hit_w && !victim_dirty_w) begin
            if (!choose_way_w) tag0_write_r = 1'b1;
            else tag1_write_r = 1'b1;
            tag_write_data_r = 21'b0;
        end else if (fill_response_w && fill_beat_q == 7) begin
            if (!fill_way_q) tag0_write_r = 1'b1;
            else tag1_write_r = 1'b1;
            tag_write_data_r = {!(refill_error_q || outport_error_i), 1'b0, addr_q[31:13]};
        end else if (state_q == STORE_UPDATE) begin
            if (hit0_w) tag0_write_r = 1'b1;
            if (hit1_w) tag1_write_r = 1'b1;
            tag_write_data_r = {1'b1, 1'b1, addr_q[31:13]};
        end else if (state_q == INVALIDATE && hit_w) begin
            if (hit0_w) tag0_write_r = 1'b1;
            if (hit1_w) tag1_write_r = 1'b1;
            tag_write_data_r = 21'b0;
        end else if (state_q == MAINT_CHECK && !maint_valid_w) begin
            if (!sweep_way_q) tag0_write_r = 1'b1;
            else tag1_write_r = 1'b1;
            tag_write_data_r = 21'b0;
        end else if (state_q == MAINT_CHECK && !maint_dirty_w) begin
            if (!sweep_way_q) tag0_write_r = 1'b1;
            else tag1_write_r = 1'b1;
            tag_write_data_r = 21'b0;
        end else if (wb_tag_write_w) begin
            if (!wb_way_q) tag0_write_r = 1'b1;
            else tag1_write_r = 1'b1;
            tag_write_data_r = wb_context_q == WB_CLEAN ? {1'b1,1'b0,wb_base_q[31:13]} : 21'b0;
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
    wire [10:0] data_write_addr_w = fill_response_w ?
        {addr_q[12:5], fill_beat_q} : addr_q[12:2];
    wire [31:0] data_write_w = fill_response_w ? outport_read_data_i : write_data_q;
    wire store_update_w = state_q == STORE_UPDATE && cacheable_q && !response_error_q;
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
    wire [31:0] wb_data_w = wb_way_q ? data1_w : data0_w;

    assign mem_accept_o = rst_ni && accept_phase_w;
    assign mem_ack_o = rst_ni && (state_q == STORE_UPDATE || state_q == RESPONSE);
    assign mem_error_o = response_error_q;
    assign mem_data_rd_o = response_data_q;
    assign mem_resp_tag_o = request_tag_q;
    assign outport_rd_o = rst_ni &&
        ((state_q == REFILL_REQ) || (state_q == UNCACHED_REQ && mem_rd_q));
    assign outport_wr_o = rst_ni && state_q == WB_REQ ? 4'hf :
        (rst_ni && state_q == UNCACHED_REQ ? write_mask_q : 4'b0);
    assign outport_len_o = state_q == REFILL_REQ ? 8'd7 : 8'd0;
    assign outport_addr_o = state_q == REFILL_REQ ? {addr_q[31:5],5'b0} :
        state_q == WB_REQ ? {wb_base_q[31:5],wb_word_q,2'b0} : {addr_q[31:2],2'b0};
    assign outport_write_data_o = state_q == WB_REQ ? wb_data_w : write_data_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= RESET;
            addr_q <= 0; write_data_q <= 0; write_mask_q <= 0; request_tag_q <= 0;
            cacheable_q <= 0; response_data_q <= 0; response_error_q <= 0;
            refill_error_q <= 0; sweep_q <= 0; sweep_way_q <= 0;
            fill_way_q <= 0; replace_way_q <= 0; fill_beat_q <= 0;
            wb_word_q <= 0; wb_context_q <= WB_MISS;
            wb_base_q <= 0; wb_way_q <= 0; mem_rd_q <= 0;
        end else begin
            case (state_q)
                RESET: begin
                    sweep_q <= sweep_q + 1'b1;
                    if (sweep_q == 8'hff) state_q <= IDLE;
                end
                IDLE: begin end
                LOOKUP: begin
                    if (!cacheable_q) state_q <= UNCACHED_REQ;
                    else if (|write_mask_q) begin
                        if (hit_w) state_q <= STORE_UPDATE;
                        else begin
                            fill_way_q <= choose_way_w; replace_way_q <= !choose_way_w;
                            wb_way_q <= choose_way_w; wb_word_q <= 0;
                            wb_context_q <= WB_MISS;
                            wb_base_q <= {victim_tag_w, addr_q[12:5],5'b0}; refill_error_q <= 0;
                            state_q <= victim_dirty_w ? WB_READ : REFILL_REQ;
                        end
                    end else if (hit_w) begin
                        response_data_q <= hit0_w ? data0_w : data1_w; state_q <= RESPONSE;
                    end else begin
                        fill_way_q <= choose_way_w; replace_way_q <= !choose_way_w;
                        wb_way_q <= choose_way_w; wb_word_q <= 0;
                        wb_context_q <= WB_MISS;
                        wb_base_q <= {victim_tag_w, addr_q[12:5],5'b0}; refill_error_q <= 0;
                        state_q <= victim_dirty_w ? WB_READ : REFILL_REQ;
                    end
                end
                REFILL_REQ: if (outport_accept_i) begin fill_beat_q <= 0; state_q <= REFILL; end
                REFILL: begin end
                RELOOKUP: state_q <= LOOKUP;
                STORE_UPDATE: state_q <= IDLE;
                UNCACHED_REQ: if (outport_accept_i) state_q <= UNCACHED_WAIT;
                UNCACHED_WAIT: begin end
                // Discard semantics match the maintenance ABI. Software must
                // clean before releasing ownership, invalidate after DMA writes.
                INVALIDATE: state_q <= RESPONSE;
                CLEAN: begin
                    if (hit_w && invalidate_dirty_w) begin
                        wb_way_q <= hit1_w; wb_word_q <= 0; wb_context_q <= WB_CLEAN;
                        wb_base_q <= {invalidate_tag_w, addr_q[12:5],5'b0};
                        state_q <= WB_READ;
                    end else state_q <= RESPONSE;
                end
                MAINT_READ: state_q <= MAINT_CHECK;
                MAINT_CHECK: begin
                    if ((sweep_way_q ? tag1_w[20] : tag0_w[20]) &&
                        (sweep_way_q ? tag1_w[19] : tag0_w[19])) begin
                        wb_way_q <= sweep_way_q; wb_word_q <= 0; wb_context_q <= WB_MAINT;
                        wb_base_q <= {(sweep_way_q ? tag1_w[18:0] : tag0_w[18:0]), sweep_q,5'b0};
                        state_q <= WB_READ;
                    end else state_q <= MAINT_ADV;
                end
                MAINT_ADV: begin
                    if (!sweep_way_q) begin sweep_way_q <= 1'b1; state_q <= MAINT_READ; end
                    else if (sweep_q == 8'hff) state_q <= RESPONSE;
                    else begin sweep_q <= sweep_q + 1'b1; sweep_way_q <= 1'b0; state_q <= MAINT_READ; end
                end
                WB_READ: state_q <= WB_REQ;
                WB_REQ: if (outport_accept_i) state_q <= WB_WAIT;
                WB_WAIT: begin end
                RESPONSE: state_q <= IDLE;
                default: state_q <= RESET;
            endcase
            if (mem_accept_o && request_w) begin
                    addr_q <= mem_addr_i; write_data_q <= mem_data_wr_i;
                    write_mask_q <= mem_wr_i; request_tag_q <= mem_req_tag_i;
                    mem_rd_q <= mem_rd_i; response_error_q <= 0; response_data_q <= 0;
                    cacheable_q <= CACHE_ENABLE && mem_cacheable_i && private_address_w;
                    if (mem_flush_i) begin
                        sweep_q <= 0; sweep_way_q <= 0;
                        state_q <= MAINT_READ;
                    end else if (mem_writeback_i) begin
                        state_q <= CLEAN;
                    end else if (mem_invalidate_i) state_q <= INVALIDATE;
                    else if (mem_addr_i[1:0] != 0 || (mem_rd_i && |mem_wr_i)) begin
                        response_error_q <= 1; state_q <= RESPONSE;
                    end else state_q <= LOOKUP;
            end
            if (wb_response_w) begin
                    if (outport_error_i) begin response_error_q <= 1'b1; state_q <= RESPONSE; end
                    else if (wb_word_q == 7) begin
                        if (wb_context_q == WB_MISS) state_q <= REFILL_REQ;
                        else if (wb_context_q == WB_CLEAN) state_q <= RESPONSE;
                        else state_q <= MAINT_ADV;
                    end else begin wb_word_q <= wb_word_q + 1'b1; state_q <= WB_READ; end
            end
            if (fill_response_w) begin
                refill_error_q <= refill_error_q || outport_error_i;
                fill_beat_q <= fill_beat_q + 1'b1;
                if (fill_beat_q == 7) begin
                    if (refill_error_q || outport_error_i) begin response_error_q <= 1'b1; state_q <= RESPONSE; end
                    else begin replace_way_q <= !fill_way_q; state_q <= RELOOKUP; end
                end
            end
            if (uncached_response_w) begin
                response_data_q <= outport_read_data_i; response_error_q <= outport_error_i;
                state_q <= RESPONSE;
            end
        end
    end
endmodule
