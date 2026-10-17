`timescale 1ns/1ps
`default_nettype none
module preview_display #(
 parameter integer PREVIEW_WIDTH=400, PREVIEW_HEIGHT=300, WINDOW_Y=150,
 parameter [23:0] BACKGROUND_RGB=24'h101820,
 parameter integer TIMEOUT_CYCLES=1000000
)(
 input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,ddr_ready,
 input wire record_valid, output wire record_ready,
 input wire [31:0] record_base,record_stride,record_frame_id,
 input wire [1:0] record_slot,
 output reg commit_valid,input wire commit_ready,
 output reg [31:0] commit_frame_id,output reg [1:0] commit_slot,
 output reg release_valid,input wire release_ready,
 output reg [31:0] release_frame_id,output reg [1:0] release_slot,
 input wire [10:0] pixel_x,pixel_y,
 input wire pixel_de,pixel_hs,pixel_vs,pixel_frame_start,
 output reg [23:0] out_rgb,output reg out_de,out_hs,out_vs,
 output reg error, output reg [7:0] error_code,
 output reg [31:0] commits,completed_scans,read_lines,underflows,frame_id,
 output wire [3:0] m_axi_arid,output reg [31:0] m_axi_araddr,
 output reg [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
 output wire [1:0] m_axi_arburst,output reg m_axi_arvalid,input wire m_axi_arready,
 input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
 input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,
 output wire m_axi_rready
);
    // RGB888 rows are padded to AXI beats; padding is never shown.
    localparam integer ROW_BYTES = PREVIEW_WIDTH*3;
    localparam integer ROW_WORDS = (ROW_BYTES+15)/16;
    localparam [2:0] P_IDLE=0,P_CLEAN=1,P_PREFETCH=2,P_SCAN=3,P_FAULT=4;
    localparam [2:0] D_IDLE=0,D_AR=1,D_R=2,D_MULT=3,D_ADDR=4;
    reg [127:0] row_ram0 [0:ROW_WORDS-1];
    reg [127:0] row_ram1 [0:ROW_WORDS-1];
    reg core_run=0,pixel_run=0;
    // Synchronous local enables are the only reset-derived RAM controls.
    always @(posedge core_clk) core_run<=core_reset_n;
    always @(posedge pixel_clk) pixel_run<=pixel_reset_n;

    // CDC contract (all destinations use explicit two-stage scalar sync):
    // core record_toggle + mailbox_* -> record_sync2 + pending_*.
    // Hold mailbox from valid/ready acceptance through commit consumption.
    // pixel request_toggle[k] + req_{base,stride,row}[k]
    // -> request_sync2[k] + dma_{base,stride,row}_latched. Bundle held until done_sync2[k],
    // and longer while its completed bank is used by either window.
    // req_{frame,slot,epoch} remain pixel-local ownership tags.
    // core done_toggle[k] + bank_success[k] -> done_sync2[k] + bank_ready[k].
    // Success held until the next request (which acknowledges the response).
    // pixel commit_toggle + commit_pixel_{id,slot} -> commit_sync2 + core
    // commit output registers; release_toggle + release_pixel_{id,slot}
    // similarly. Hold event bundles until their core handshake ack returns
    // via *_ack_sync2. Core acceptance waits until both event queues retire.
    // pixel scan_toggle,underflow_toggle -> *_sync2 -> core counters.
    // core error -> fault_sync2; pixel underflow is sticky and reports once.
    // FDC: exempt only each *_sync1 D from its asynchronous scalar source;
    // set_max_delay -datapath_only on every bundle source Q to listed capture
    // D, <= min(core period,pixel period), including bank_success and events.
    // Do not false-path whole clock groups. Resets must be coordinated.
    reg record_toggle,record_busy;
    reg protected_valid;
    reg [31:0] protected_base;
    reg [1:0] protected_slot;
    reg [31:0] mailbox_base,mailbox_stride,mailbox_frame;
    reg [1:0] mailbox_slot;
    reg [1:0] request_toggle,done_toggle,bank_success;
    reg [31:0] req_base[0:1],req_stride[0:1],req_frame[0:1],req_epoch[0:1];
    reg [1:0] req_slot[0:1];
    reg [10:0] req_row[0:1];
    (* async_reg="true" *) reg [1:0] request_sync1,request_sync2;
    (* async_reg="true" *) reg [1:0] done_sync1,done_sync2;
    (* async_reg="true" *) reg record_sync1,record_sync2;
    reg record_seen;
    reg commit_toggle,release_toggle,scan_toggle,underflow_toggle;
    reg commit_ack,release_ack;
    reg [31:0] commit_pixel_id,release_pixel_id;
    reg [1:0] commit_pixel_slot,release_pixel_slot;
    (* async_reg="true" *) reg commit_sync1,commit_sync2,release_sync1,release_sync2;
    (* async_reg="true" *) reg scan_sync1,scan_sync2,underflow_sync1,underflow_sync2;
    (* async_reg="true" *) reg commit_ack_sync1,commit_ack_sync2,release_ack_sync1,release_ack_sync2;
    (* async_reg="true" *) reg fault_sync1,fault_sync2;
    reg commit_seen,release_seen,scan_seen,underflow_seen;
    assign record_ready=core_run && !record_busy && !commit_valid && !release_valid && !error &&
        (!protected_valid || (record_base!==protected_base && record_slot!==protected_slot));
    localparam [63:0] LAST_ROW=PREVIEW_HEIGHT-1,ROW_BUS_BYTES=ROW_WORDS*16;
    wire [63:0] record_bus_end={32'd0,record_base}+
        {32'd0,record_stride}*LAST_ROW+ROW_BUS_BYTES;
    assign m_axi_arid=4'd0;
    assign m_axi_arsize=3'd4;
    assign m_axi_arburst=2'b01;
    reg [2:0] dma_state;
    reg dma_bank,dma_bad;
    reg [31:0] dma_address;
    reg [31:0] dma_base_latched,dma_stride_latched;
    reg [10:0] dma_row_latched;
    reg [63:0] dma_row_product;
    integer dma_words_left,dma_word_offset,dma_burst_beats,dma_beat,watchdog;
    integer chosen_words,boundary_words;
    wire r_transfer=(dma_state==D_R && m_axi_rvalid && m_axi_rready);
    wire response_ok=(m_axi_rid===4'd0 && m_axi_rresp===2'b00 &&
                     m_axi_rlast===(dma_beat==dma_burst_beats-1));
    assign m_axi_rready=core_run && dma_state==D_R;
    wire ram_write=core_run && r_transfer && !dma_bad && !error && response_ok && ddr_ready;
    // RAM contents and read data have no asynchronous-reset data/CE cone.
    always @(posedge core_clk) begin
        if(ram_write) begin
            if(dma_bank) row_ram1[dma_word_offset+dma_beat]<=m_axi_rdata;
            else row_ram0[dma_word_offset+dma_beat]<=m_axi_rdata;
        end
    end
    always @(posedge core_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin
            request_sync1<=0;request_sync2<=0;commit_sync1<=0;commit_sync2<=0;
            release_sync1<=0;release_sync2<=0;scan_sync1<=0;scan_sync2<=0;
            underflow_sync1<=0;underflow_sync2<=0;
        end else begin
            request_sync1<=request_toggle;request_sync2<=request_sync1;
            commit_sync1<=commit_toggle;commit_sync2<=commit_sync1;
            release_sync1<=release_toggle;release_sync2<=release_sync1;
            scan_sync1<=scan_toggle;scan_sync2<=scan_sync1;
            underflow_sync1<=underflow_toggle;underflow_sync2<=underflow_sync1;
        end
    end
    always @(posedge core_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin
            record_toggle<=0;record_busy<=0;mailbox_base<=0;mailbox_stride<=0;mailbox_frame<=0;mailbox_slot<=0;
            protected_valid<=0;protected_base<=0;protected_slot<=0;
            commit_valid<=0;release_valid<=0;commit_frame_id<=0;commit_slot<=0;release_frame_id<=0;release_slot<=0;
            commit_ack<=0;release_ack<=0;commit_seen<=0;release_seen<=0;scan_seen<=0;underflow_seen<=0;
            error<=0;error_code<=0;commits<=0;completed_scans<=0;read_lines<=0;underflows<=0;frame_id<=0;
            done_toggle<=0;bank_success<=0;dma_state<=D_IDLE;dma_bank<=0;dma_bad<=0;dma_address<=0;
            dma_words_left<=0;dma_word_offset<=0;dma_burst_beats<=0;dma_beat<=0;watchdog<=0;
            dma_base_latched<=0;dma_stride_latched<=0;dma_row_latched<=0;dma_row_product<=0;
            m_axi_arvalid<=0;m_axi_araddr<=0;m_axi_arlen<=0;
        end else if(core_run) begin
            if(record_valid && record_ready) begin
                mailbox_base<=record_base;mailbox_stride<=record_stride;mailbox_frame<=record_frame_id;mailbox_slot<=record_slot;
                record_toggle<=~record_toggle;record_busy<=1;
                if(record_base[3:0]!==0 || record_stride[3:0]!==0 || record_stride<ROW_BYTES ||
                   record_base<32'h80000000 || record_bus_end>64'h0000000088000000 ||
                   PREVIEW_WIDTH<1 || PREVIEW_WIDTH>1024 || PREVIEW_HEIGHT<1 ||
                   PREVIEW_HEIGHT>2048 || WINDOW_Y<1 || WINDOW_Y>2048-PREVIEW_HEIGHT ||
                   (^record_base===1'bx) || (^record_stride===1'bx) ||
                   (^record_frame_id===1'bx) || (^record_slot===1'bx)) begin error<=1;error_code<=8'd1;end
            end
            if(commit_sync2!=commit_seen) begin
                commit_seen<=commit_sync2;commit_valid<=1;commit_frame_id<=commit_pixel_id;commit_slot<=commit_pixel_slot;
                commits<=commits+1'b1;frame_id<=commit_pixel_id;
                protected_valid<=1;protected_base<=mailbox_base;protected_slot<=mailbox_slot;
            end
            if(commit_valid && commit_ready) begin commit_valid<=0;commit_ack<=commit_seen;record_busy<=0;end
            if(release_sync2!=release_seen) begin
                release_seen<=release_sync2;release_valid<=1;release_frame_id<=release_pixel_id;release_slot<=release_pixel_slot;
            end
            if(release_valid && release_ready) begin release_valid<=0;release_ack<=release_seen;end
            if(scan_sync2!=scan_seen) begin scan_seen<=scan_sync2;completed_scans<=completed_scans+1'b1;end
            if(underflow_sync2!=underflow_seen) begin
                underflow_seen<=underflow_sync2;underflows<=underflows+1'b1;
                if(!error) begin error<=1;error_code<=8'd6;end
            end
            if((record_busy || protected_valid || dma_state!=D_IDLE) && ddr_ready!==1'b1 && !error)
                begin error<=1;error_code<=8'd5;end
            case(dma_state)
            D_IDLE: begin
                watchdog<=0;
                if(request_sync2!=done_toggle) begin
                    dma_bank<=(request_sync2[0]==done_toggle[0]);
                    if(error || !ddr_ready) begin
                        if(request_sync2[0]!=done_toggle[0]) begin done_toggle[0]<=request_sync2[0];bank_success[0]<=0;end
                        else begin done_toggle[1]<=request_sync2[1];bank_success[1]<=0;end
                    end else begin
                        dma_bad<=0;dma_words_left<=ROW_WORDS;dma_word_offset<=0;dma_beat<=0;
                        if(request_sync2[0]!=done_toggle[0]) begin
                            dma_base_latched<=req_base[0];dma_stride_latched<=req_stride[0];dma_row_latched<=req_row[0];
                        end else begin
                            dma_base_latched<=req_base[1];dma_stride_latched<=req_stride[1];dma_row_latched<=req_row[1];
                        end
                        dma_state<=D_MULT;
                    end
                end
            end
            D_MULT: begin
                dma_row_product<={53'd0,dma_row_latched}*{32'd0,dma_stride_latched};dma_state<=D_ADDR;
            end
            D_ADDR: begin dma_address<=dma_base_latched+dma_row_product[31:0];dma_state<=D_AR;end
            D_AR: begin
                if(!m_axi_arvalid) begin
                    if(error || !ddr_ready) begin
                        bank_success[dma_bank]<=0;done_toggle[dma_bank]<=request_sync2[dma_bank];dma_state<=D_IDLE;
                    end else begin
                        chosen_words=(dma_words_left>16 ? 16 : dma_words_left);
                        boundary_words=(4096-{20'd0,dma_address[11:0]})/16;
                        if(chosen_words>boundary_words) chosen_words=boundary_words;
                        m_axi_araddr<=dma_address;m_axi_arlen<=chosen_words[7:0]-8'd1;m_axi_arvalid<=1;
                        dma_burst_beats<=chosen_words;dma_beat<=0;watchdog<=0;
                    end
                end else if(m_axi_arready) begin m_axi_arvalid<=0;dma_state<=D_R;watchdog<=0;end
                else if(watchdog<TIMEOUT_CYCLES) watchdog<=watchdog+1;
                else begin dma_bad<=1;if(!error) begin error<=1;error_code<=8'd4;end end
            end
            D_R: begin
                if(m_axi_rvalid) begin
                    watchdog<=0;
                    if(!response_ok || !ddr_ready) begin
                        dma_bad<=1;
                        if(!error) begin error<=1;error_code<=(!ddr_ready ? 8'd5 : 8'd2);end
                    end
                    if(dma_beat==dma_burst_beats-1) begin
                        if(dma_bad || error || !response_ok || !ddr_ready) begin
                            bank_success[dma_bank]<=0;done_toggle[dma_bank]<=request_sync2[dma_bank];dma_state<=D_IDLE;
                        end else if(dma_words_left==dma_burst_beats) begin
                            bank_success[dma_bank]<=1;done_toggle[dma_bank]<=request_sync2[dma_bank];
                            read_lines<=read_lines+1'b1;dma_state<=D_IDLE;
                        end else begin
                            dma_words_left<=dma_words_left-dma_burst_beats;dma_word_offset<=dma_word_offset+dma_burst_beats;
                            dma_address<=dma_address+{dma_burst_beats[27:0],4'd0};dma_state<=D_AR;
                        end
                    end else dma_beat<=dma_beat+1;
                end else if(watchdog<TIMEOUT_CYCLES) watchdog<=watchdog+1;
                else begin dma_bad<=1;if(!error) begin error<=1;error_code<=8'd4;end end
            end
            default:dma_state<=D_IDLE;
            endcase
        end
    end

    reg [2:0] pixel_state;
    reg pending_valid,target_pending,active_valid,prefetch_started,scan_bad;
    reg [31:0] pending_base,pending_stride,pending_frame;
    reg [1:0] pending_slot;
    reg [31:0] target_base,target_stride,target_frame,active_base,active_stride,active_frame,epoch;
    reg [1:0] target_slot,active_slot;
    reg [1:0] bank_inflight,bank_ready;
    reg consume_d1,consume_d2,consume_bank_d1,consume_bank_d2;
    reg consume_last_d1,consume_last_d2;
    reg [10:0] consume_row_d1,consume_row_d2;
    integer b;
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            record_sync1<=0;record_sync2<=0;done_sync1<=0;done_sync2<=0;
            commit_ack_sync1<=0;commit_ack_sync2<=0;release_ack_sync1<=0;release_ack_sync2<=0;
            fault_sync1<=0;fault_sync2<=0;
        end else begin
            record_sync1<=record_toggle;record_sync2<=record_sync1;done_sync1<=done_toggle;done_sync2<=done_sync1;
            commit_ack_sync1<=commit_ack;commit_ack_sync2<=commit_ack_sync1;
            release_ack_sync1<=release_ack;release_ack_sync2<=release_ack_sync1;
            fault_sync1<=error;fault_sync2<=fault_sync1;
        end
    end
    wire in_window=pixel_de && pixel_x<PREVIEW_WIDTH*2 && pixel_y>=WINDOW_Y && pixel_y<WINDOW_Y+PREVIEW_HEIGHT;
    wire [10:0] source_row=pixel_y-WINDOW_Y[10:0];
    wire source_bank=source_row[0];
    wire [10:0] source_col=(pixel_x>=PREVIEW_WIDTH ? pixel_x-PREVIEW_WIDTH[10:0] : pixel_x);
    wire matching_bank=bank_ready[source_bank] && req_row[source_bank]==source_row &&
        req_frame[source_bank]==active_frame && req_epoch[source_bank]==epoch;
    wire show_pixel=pixel_state==P_SCAN && active_valid && !scan_bad && !fault_sync2 && in_window && matching_bank;
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            pixel_state<=P_IDLE;record_seen<=0;pending_valid<=0;target_pending<=0;active_valid<=0;prefetch_started<=0;scan_bad<=0;
            pending_base<=0;pending_stride<=0;pending_frame<=0;pending_slot<=0;
            target_base<=0;target_stride<=0;target_frame<=0;target_slot<=0;
            active_base<=0;active_stride<=0;active_frame<=0;active_slot<=0;epoch<=0;
            request_toggle<=0;bank_inflight<=0;bank_ready<=0;
            commit_toggle<=0;release_toggle<=0;scan_toggle<=0;underflow_toggle<=0;
            commit_pixel_id<=0;commit_pixel_slot<=0;release_pixel_id<=0;release_pixel_slot<=0;
            consume_d1<=0;consume_d2<=0;consume_bank_d1<=0;consume_bank_d2<=0;
            consume_last_d1<=0;consume_last_d2<=0;consume_row_d1<=0;consume_row_d2<=0;
            for(b=0;b<2;b=b+1) begin req_base[b]<=0;req_stride[b]<=0;req_frame[b]<=0;req_slot[b]<=0;req_row[b]<=0;req_epoch[b]<=0;end
        end else if(pixel_run) begin
            consume_d1<=pixel_state==P_SCAN && in_window && pixel_x==PREVIEW_WIDTH*2-1;
            consume_d2<=consume_d1;consume_bank_d1<=source_bank;consume_bank_d2<=consume_bank_d1;
            consume_last_d1<=source_row==PREVIEW_HEIGHT-1;consume_last_d2<=consume_last_d1;
            consume_row_d1<=source_row;consume_row_d2<=consume_row_d1;
            for(b=0;b<2;b=b+1) begin
                if(bank_inflight[b] && done_sync2[b]==request_toggle[b]) begin
                    bank_inflight[b]<=0;bank_ready[b]<=bank_success[b];
                end
            end
            if(record_sync2!=record_seen) begin
                record_seen<=record_sync2;pending_valid<=1;
                pending_base<=mailbox_base;pending_stride<=mailbox_stride;pending_frame<=mailbox_frame;pending_slot<=mailbox_slot;
            end
            if(fault_sync2) begin pixel_state<=P_FAULT;scan_bad<=1;end
            else case(pixel_state)
            P_IDLE: if(pending_valid) begin
                target_base<=pending_base;target_stride<=pending_stride;target_frame<=pending_frame;target_slot<=pending_slot;
                target_pending<=1;epoch<=epoch+1'b1;pixel_state<=P_CLEAN;
            end
            P_CLEAN: if(bank_inflight==0) begin bank_ready<=0;prefetch_started<=0;pixel_state<=P_PREFETCH;end
            P_PREFETCH: begin
                if(!prefetch_started) begin
                    for(b=0;b<2;b=b+1) begin
                        if(b<PREVIEW_HEIGHT) begin
                            req_base[b]<=target_base;req_stride[b]<=target_stride;req_frame[b]<=target_frame;req_slot[b]<=target_slot;
                            req_row[b]<=b[10:0];req_epoch[b]<=epoch;request_toggle[b]<=~request_toggle[b];bank_inflight[b]<=1;
                        end
                    end
                    prefetch_started<=1;
                end
                if(pixel_frame_start && bank_ready[0] && prefetch_started &&
                   (!target_pending || (commit_ack_sync2==commit_toggle && release_ack_sync2==release_toggle))) begin
                    // An event consumer can stall indefinitely while the same
                    // committed image keeps scanning. Only a new publication
                    // needs both previous event bundles to have retired.
                    if(target_pending) begin
                        if(active_valid) begin
                            release_pixel_id<=active_frame;release_pixel_slot<=active_slot;release_toggle<=~release_toggle;
                        end
                        active_base<=target_base;active_stride<=target_stride;active_frame<=target_frame;active_slot<=target_slot;
                        active_valid<=1;pending_valid<=0;target_pending<=0;
                        commit_pixel_id<=target_frame;commit_pixel_slot<=target_slot;commit_toggle<=~commit_toggle;
                    end
                    scan_bad<=0;pixel_state<=P_SCAN;
                end
            end
            P_SCAN: begin
                if(in_window && pixel_x==0 && !matching_bank && !scan_bad) begin
                    scan_bad<=1;underflow_toggle<=~underflow_toggle;
                end
                if(consume_d2) begin
                    bank_ready[consume_bank_d2]<=0;
                    if(!scan_bad && consume_row_d2+2<PREVIEW_HEIGHT) begin
                        req_base[consume_bank_d2]<=active_base;req_stride[consume_bank_d2]<=active_stride;
                        req_frame[consume_bank_d2]<=active_frame;req_slot[consume_bank_d2]<=active_slot;
                        req_row[consume_bank_d2]<=consume_row_d2+11'd2;req_epoch[consume_bank_d2]<=epoch;
                        request_toggle[consume_bank_d2]<=~request_toggle[consume_bank_d2];bank_inflight[consume_bank_d2]<=1;
                    end
                    if(consume_last_d2) begin
                        if(!scan_bad) scan_toggle<=~scan_toggle;
                        epoch<=epoch+1'b1;
                        if(pending_valid) begin
                            target_base<=pending_base;target_stride<=pending_stride;target_frame<=pending_frame;target_slot<=pending_slot;target_pending<=1;
                        end else begin
                            target_base<=active_base;target_stride<=active_stride;target_frame<=active_frame;target_slot<=active_slot;target_pending<=0;
                        end
                        pixel_state<=(scan_bad ? P_FAULT : P_CLEAN);
                    end
                end
            end
            default:begin end
            endcase
        end
    end

    // One synchronous 128-bit RAM read per pixel. Keep the previous word to
    // assemble the two RGB pixels per 16-byte beat that straddle a boundary.
    reg [127:0] ram_word,ram_previous;
    integer ram_address;
    wire [12:0] byte_offset={2'b0,source_col}*13'd3;
    wire [12:0] final_byte=byte_offset+13'd2;
    wire [8:0] next_ram_address=final_byte[12:4];
    reg [3:0] offset_pipe;
    reg show_pipe,de_pipe,hs_pipe,vs_pipe;
    reg [255:0] assembled;
    reg [23:0] rgb_bytes;
    always @(posedge pixel_clk) begin
        if(pixel_run && show_pixel) begin
            if(source_bank) ram_word<=row_ram1[next_ram_address];
            else ram_word<=row_ram0[next_ram_address];
            if(ram_address!={23'd0,next_ram_address}) ram_previous<=ram_word;
            ram_address<={23'd0,next_ram_address};
        end
    end
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            offset_pipe<=0;show_pipe<=0;de_pipe<=0;hs_pipe<=0;vs_pipe<=0;
            out_rgb<=BACKGROUND_RGB;out_de<=0;out_hs<=0;out_vs<=0;
        end else if(pixel_run) begin
            offset_pipe<=byte_offset[3:0];show_pipe<=show_pixel;
            de_pipe<=pixel_de;hs_pipe<=pixel_hs;vs_pipe<=pixel_vs;
            out_de<=de_pipe;out_hs<=hs_pipe;out_vs<=vs_pipe;
            if(offset_pipe>=14) assembled={ram_word,ram_previous};else assembled={128'd0,ram_word};
            rgb_bytes=assembled[offset_pipe*8+:24];
            out_rgb<=(show_pipe ? {rgb_bytes[7:0],rgb_bytes[15:8],rgb_bytes[23:16]} : BACKGROUND_RGB);
        end
    end
endmodule
`default_nettype wire
