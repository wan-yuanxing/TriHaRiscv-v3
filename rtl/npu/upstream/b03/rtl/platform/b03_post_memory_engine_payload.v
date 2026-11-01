// Complete local POST memory flow; this is not a CPU release/fence service.
// reset_n invalidates the entire engine + bridge/FIFO/native session together.
module b03_post_memory_engine_payload #(
    parameter [2:0] POST_CLIENT=3'd4,
    parameter [31:0] INITIAL_GLOBAL_ID=32'd1,INITIAL_LOCAL_ID=32'd1,INITIAL_WRITER_ID=32'd1,
    parameter integer STALL_LIMIT=1000000,ENGINE_STALL_LIMIT=10000000
)(
    input wire clk,reset_n,run_ce,cancel_request,bridge_fault,
    input wire [31:0] bridge_epoch,
    input wire start_valid,output wire start_ready,
    input wire [31:0] cfg_heads_offset,cfg_heads_bytes,cfg_table_offset,cfg_table_bytes,
    input wire [31:0] cfg_result_offset,cfg_result_bytes,cfg_head_generation,cfg_cmd_id,cfg_bridge_epoch,
    input wire [11:0] cfg_capacity,input wire [63:0] cfg_frame_id,input wire cfg_heads_readable,
    input wire [13:0] cfg_source_w,cfg_source_h,
    input wire [8:0] cfg_resized_w,cfg_resized_h,cfg_pad_left,cfg_pad_top,
    output wire done_valid,input wire done_ready,output reg [3:0] done_status,
    output reg [7:0] done_detail,output reg [11:0] done_face_count,done_nms_count,
    output reg [31:0] done_crc,output wire [31:0] done_cmd_id,done_bridge_epoch,done_post_epoch,
    output wire [63:0] done_frame_id,output reg [63:0] total_cycles,post_cycles,post_wait,post_paused,
    output reg quarantined,reset_required,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
    output wire [31:0] cmd_offset,cmd_id,cmd_epoch,output wire [4:0] cmd_beats,output wire [2:0] cmd_client,
    output wire write_valid,input wire write_ready,output wire [255:0] write_data,
    output wire [31:0] write_strb,output wire write_last,
    input wire read_valid,output wire read_ready,input wire [255:0] read_data,input wire read_last,
    input wire mem_done_valid,output wire mem_done_ready,input wire [3:0] mem_done_status,
    input wire [31:0] mem_done_id,mem_done_epoch,input wire [2:0] mem_done_client,
    output wire abort_req,output wire [3:0] debug_state,output wire [7:0] debug_post_state,
    output wire [1:0] debug_owner,output wire [31:0] debug_global_id,
    output reg [10:0] debug_head_beats,output reg [31:0] debug_table_requests,
    output reg [11:0] debug_records_taken,debug_batches_retired,
    output reg [31:0] debug_bridge_commands,debug_bridge_completions
);
    localparam IDLE=0,CHECK=1,HEAD_IDLE=2,HEAD_START=3,HEAD_WAIT=4,SUBMIT=5,RUN=6,
        WAIT_TX=7,HELD=8,ISOLATED=9;
    reg [3:0] state;
    reg done_pending,post_cancel,saved_readable,batch_inflight,writer_id_exhausted;
    reg [31:0] heads_offset,heads_bytes,table_offset,table_bytes,result_offset,result_bytes;
    reg [31:0] head_generation,identity,epoch,post_epoch,writer_next_id,stalled;
    reg [63:0] frame;
    reg [11:0] capacity;
    reg [11:0] pending_batch_base,retired_record_count;
    reg [4:0] pending_batch_count;
    reg [13:0] source_w,source_h;
    reg [8:0] resized_w,resized_h,pad_left,pad_top;
    reg [7:0] previous_post_state;
    wire r_q,r_reset,w_q,w_reset,m_q,m_reset,post_q,m_busy,global_exhausted;
    wire active=state!=IDLE && state!=HELD && state!=ISOLATED;
    wire core_ce=run_ce && !quarantined;
    wire cancel_children=quarantined || (cancel_request && active) ||
        r_q || r_reset || w_q || w_reset || m_q || m_reset || post_q;
    wire [32:0] heads_end={1'b0,heads_offset}+{1'b0,heads_bytes};
    wire [32:0] table_end={1'b0,table_offset}+{1'b0,table_bytes};
    wire [32:0] result_end={1'b0,result_offset}+{1'b0,result_bytes};
    wire [32:0] result_needed=33'd128+({21'd0,capacity}<<5);
    wire windows_legal=heads_offset[4:0]==0 && heads_bytes[4:0]==0 && heads_bytes>=26368 &&
        table_offset[4:0]==0 && table_bytes==1572864 && result_offset[4:0]==0 && result_bytes[4:0]==0 &&
        {1'b0,result_bytes}>=result_needed && heads_end<=33'h040000000 &&
        table_end<=33'h040000000 && result_end<=33'h040000000 &&
        (heads_end<={1'b0,table_offset} || table_end<={1'b0,heads_offset}) &&
        (heads_end<={1'b0,result_offset} || result_end<={1'b0,heads_offset}) &&
        (table_end<={1'b0,result_offset} || result_end<={1'b0,table_offset});
    wire cfg_legal=windows_legal && capacity>=1 && capacity<=2100 && head_generation!=0 &&
        saved_readable && epoch==bridge_epoch;
    wire [3:0] r_fault,w_fault,m_fault;
    wire [31:0] context_epoch;
    assign start_ready=state==IDLE && !done_pending && !quarantined && !cancel_request && !bridge_fault &&
        !r_q && !r_reset && !w_q && !w_reset && !m_q && !m_reset && !post_q;
    assign done_valid=done_pending;
    assign done_cmd_id=identity;assign done_bridge_epoch=epoch;assign done_post_epoch=post_epoch;
    assign done_frame_id=frame;assign debug_state=state;

    wire load_begin,head_valid,head_ready,heads_loaded,load_error,core_task_ready;
    wire [31:0] load_generation,head_tag;
    wire [14:0] head_offset;
    wire [255:0] head_data;
    wire head_start_ready,head_done_valid;
    wire [3:0] head_done_status;
    wire [31:0] head_done_cmd,head_done_epoch;
    wire [63:0] head_done_frame;
    wire table_req_valid,table_req_ready,table_rsp_valid,table_rsp_ready,table_rsp_error;
    wire [31:0] table_req_offset,table_req_epoch,table_rsp_offset,table_rsp_epoch;
    wire [255:0] table_rsp_data;
    wire batch_valid,batch_ready,writer_batch_ready;
    wire [11:0] batch_base;
    wire [4:0] batch_count;
    wire [31:0] batch_cmd,batch_epoch;
    wire [63:0] batch_frame;
    wire record_valid,record_ready;
    wire [255:0] record_data;
    wire [11:0] record_index;
    wire [31:0] record_cmd,record_epoch;
    wire [63:0] record_frame;
    wire writer_done_valid;
    wire [3:0] writer_done_status;
    wire [11:0] writer_done_base;
    wire [4:0] writer_done_count;
    wire [31:0] writer_done_cmd,writer_done_epoch,writer_last_id;
    wire [63:0] writer_done_frame;
    wire allow_batch=(state==RUN || state==WAIT_TX) && !quarantined && !writer_id_exhausted;
    assign batch_ready=allow_batch && writer_batch_ready;
    wire core_done_valid;
    wire [4:0] core_done_status;
    wire [7:0] core_done_detail;
    wire [11:0] core_faces,core_nms;
    wire [31:0] core_crc,core_cmd,core_epoch;
    wire [63:0] core_frame,core_cycles,core_wait,core_paused;
    wire raw_ready,raw_fault;
    wire [31:0] raw_q_a,raw_q_b;
    wire [1:0] raw_valid;
    wire [11:0] scan_index,preselected,sorted_count;
    wire [31:0] stat_scan,stat_score,stat_sort,stat_decode,stat_nms,stat_roi,stat_record,stat_table;

    // spec155: declare identity outputs before their consumer instances.
    wire rg_core_rst_n;
    wire rg_read_dma_reset_n;
    wire rg_writer_reset_n;
    wire rg_memory_arbiter_reset_n;

    b03_post_frame_payload core(.clk(clk),.rst_n(rg_core_rst_n),.run_ce(core_ce),.cancel(post_cancel),.ddr_drained(saved_readable),
        .load_begin(load_begin),.load_generation(load_generation),.head_valid(head_valid),.head_ready(head_ready),
        .head_offset(head_offset),.head_data(head_data),.head_generation(head_tag),.load_error(load_error),.heads_loaded(heads_loaded),
        .task_valid(state==SUBMIT),.task_ready(core_task_ready),.task_cmd_id(identity),.task_epoch(post_epoch),
        .task_head_generation(head_generation),.task_frame_id(frame),.task_source_w(source_w),.task_source_h(source_h),
        .task_resized_w(resized_w),.task_resized_h(resized_h),.task_pad_left(pad_left),.task_pad_top(pad_top),.task_capacity(capacity),
        .raw_mem(2'd0),.raw_req(2'd0),.raw_we(2'd0),.raw_epoch(context_epoch),.raw_bank_a(5'd0),.raw_bank_b(5'd0),
        .raw_addr_a(11'd0),.raw_addr_b(11'd0),.raw_data_a(32'd0),.raw_data_b(32'd0),.raw_mask_a(4'd0),.raw_mask_b(4'd0),
        .raw_ready(raw_ready),.raw_fault(raw_fault),.raw_q_a(raw_q_a),.raw_q_b(raw_q_b),.raw_valid(raw_valid),
        .table_req_valid(table_req_valid),.table_req_ready(table_req_ready),.table_req_offset(table_req_offset),.table_req_epoch(table_req_epoch),
        .table_rsp_valid(table_rsp_valid),.table_rsp_ready(table_rsp_ready),.table_rsp_data(table_rsp_data),.table_rsp_offset(table_rsp_offset),
        .table_rsp_epoch(table_rsp_epoch),.table_rsp_error(table_rsp_error),
        .batch_valid(batch_valid),.batch_ready(batch_ready),.batch_base_record_index(batch_base),.batch_count(batch_count),
        .batch_cmd_id(batch_cmd),.batch_epoch(batch_epoch),.batch_frame_id(batch_frame),
        .record_valid(record_valid),.record_ready(record_ready),.record_data(record_data),.record_index(record_index),
        .record_cmd_id(record_cmd),.record_epoch(record_epoch),.record_frame_id(record_frame),
        .done_valid(core_done_valid),.done_ready(state==RUN),.done_status(core_done_status),.done_detail(core_done_detail),
        .done_face_count(core_faces),.done_nms_count(core_nms),.done_crc(core_crc),.done_cmd_id(core_cmd),.done_epoch(core_epoch),
        .done_frame_id(core_frame),.total_cycles(core_cycles),.wait_cycles(core_wait),.paused_cycles(core_paused),
        .context_epoch(context_epoch),.quarantined(post_q),.debug_state(debug_post_state),.debug_scan_index(scan_index),
        .debug_preselected(preselected),.debug_sorted(sorted_count),.stat_scan_cycles(stat_scan),.stat_score_cycles(stat_score),
        .stat_sort_cycles(stat_sort),.stat_decode_cycles(stat_decode),.stat_nms_cycles(stat_nms),.stat_roi_cycles(stat_roi),
        .stat_record_cycles(stat_record),.stat_table_beats(stat_table));

    wire r_cmd_valid,r_cmd_ready,r_cmd_write,r_read_valid,r_read_ready,r_read_last,r_done_valid,r_done_ready,r_abort;
    wire [31:0] r_cmd_offset,r_cmd_id,r_cmd_epoch,r_done_id,r_done_epoch;
    wire [4:0] r_cmd_beats;wire [2:0] r_cmd_client,r_done_client;wire [3:0] r_done_status;
    wire [255:0] r_read_data;
    wire [3:0] read_debug_state;wire read_owner,rx_ingress_valid,rx_present_valid,read_exhausted;
    wire [9:0] head_received,head_presented;wire [6:0] head_commands;wire [31:0] read_commands,read_next_id;
    b03_post_read_dma #(.POST_CLIENT(POST_CLIENT),.INITIAL_LOCAL_ID(INITIAL_LOCAL_ID),.STALL_LIMIT(STALL_LIMIT)) read_dma(
        .clk(clk),.reset_n(rg_read_dma_reset_n),.run_ce(core_ce),.cancel_request(cancel_children),.bridge_fault(bridge_fault),
        .head_start_valid(state==HEAD_START),.head_start_ready(head_start_ready),.cfg_heads_offset(heads_offset),.cfg_heads_bytes(heads_bytes),
        .cfg_table_offset(table_offset),.cfg_table_bytes(table_bytes),.cfg_cmd_id(identity),.cfg_post_epoch(post_epoch),
        .cfg_bridge_epoch(epoch),.cfg_head_generation(head_generation),.cfg_frame_id(frame),
        .head_done_valid(head_done_valid),.head_done_ready(state==HEAD_WAIT),.head_done_status(head_done_status),
        .head_done_cmd_id(head_done_cmd),.head_done_epoch(head_done_epoch),.head_done_frame_id(head_done_frame),
        .load_begin(load_begin),.load_generation(load_generation),.head_valid(head_valid),.head_ready(head_ready),
        .head_offset(head_offset),.head_data(head_data),.head_generation(head_tag),.heads_loaded(heads_loaded),.load_error(load_error),
        .table_req_valid(table_req_valid),.table_req_ready(table_req_ready),.table_req_offset(table_req_offset),.table_req_epoch(table_req_epoch),
        .table_rsp_valid(table_rsp_valid),.table_rsp_ready(table_rsp_ready),.table_rsp_data(table_rsp_data),
        .table_rsp_offset(table_rsp_offset),.table_rsp_epoch(table_rsp_epoch),.table_rsp_error(table_rsp_error),
        .cmd_valid(r_cmd_valid),.cmd_ready(r_cmd_ready),.cmd_write(r_cmd_write),.cmd_offset(r_cmd_offset),.cmd_id(r_cmd_id),
        .cmd_epoch(r_cmd_epoch),.cmd_beats(r_cmd_beats),.cmd_client(r_cmd_client),.read_valid(r_read_valid),.read_ready(r_read_ready),
        .read_data(r_read_data),.read_last(r_read_last),.mem_done_valid(r_done_valid),.mem_done_ready(r_done_ready),
        .mem_done_status(r_done_status),.mem_done_id(r_done_id),.mem_done_epoch(r_done_epoch),.mem_done_client(r_done_client),
        .abort_req(r_abort),.quarantined(r_q),.reset_required(r_reset),.fault_status(r_fault),.debug_state(read_debug_state),
        .debug_owner(read_owner),.debug_ingress_valid(rx_ingress_valid),.debug_present_valid(rx_present_valid),
        .debug_head_received(head_received),.debug_head_presented(head_presented),.debug_head_commands(head_commands),
        .debug_commands(read_commands),.debug_next_local_id(read_next_id),.tag_exhausted(read_exhausted));

    wire w_cmd_valid,w_cmd_ready,w_cmd_write,w_write_valid,w_write_ready,w_write_last,w_done_valid,w_done_ready,w_abort;
    wire [31:0] w_cmd_offset,w_cmd_id,w_cmd_epoch,w_done_id,w_done_epoch,w_write_strb;
    wire [4:0] w_cmd_beats;wire [2:0] w_cmd_client,w_done_client;wire [3:0] w_done_status;
    wire [255:0] w_write_data;
    wire [3:0] write_debug_state;wire [4:0] write_taken,write_sent,write_retired;
    wire [1:0] write_bursts;wire write_owner,tx_skid_valid;
    b03_record_batch_tx #(.POST_CLIENT(POST_CLIENT),.STALL_LIMIT(STALL_LIMIT)) writer(
        .clk(clk),.reset_n(rg_writer_reset_n),.run_ce(core_ce),.cancel_request(cancel_children),
        .batch_valid(allow_batch && batch_valid),.batch_ready(writer_batch_ready),.batch_base_record_index(batch_base),.batch_count(batch_count),
        .batch_cmd_id(batch_cmd),.batch_epoch(batch_epoch),.batch_frame_id(batch_frame),.cfg_result_offset(result_offset),
        .cfg_result_bytes(result_bytes),.cfg_capacity(capacity),.cfg_cmd_id(identity),.cfg_post_epoch(post_epoch),
        .cfg_bridge_epoch(epoch),.cfg_first_burst_id(writer_next_id),.cfg_frame_id(frame),
        .record_valid(record_valid),.record_ready(record_ready),.record_data(record_data),.record_index(record_index),
        .record_cmd_id(record_cmd),.record_epoch(record_epoch),.record_frame_id(record_frame),
        .batch_done_valid(writer_done_valid),.batch_done_ready(1'b1),.batch_done_status(writer_done_status),
        .batch_done_base(writer_done_base),.batch_done_count(writer_done_count),.batch_done_cmd_id(writer_done_cmd),
        .batch_done_epoch(writer_done_epoch),.batch_done_frame_id(writer_done_frame),.batch_done_last_burst_id(writer_last_id),
        .quarantined(w_q),.reset_required(w_reset),.fault_status(w_fault),
        .cmd_valid(w_cmd_valid),.cmd_ready(w_cmd_ready),.cmd_write(w_cmd_write),.cmd_offset(w_cmd_offset),.cmd_id(w_cmd_id),
        .cmd_epoch(w_cmd_epoch),.cmd_beats(w_cmd_beats),.cmd_client(w_cmd_client),
        .write_valid(w_write_valid),.write_ready(w_write_ready),.write_data(w_write_data),.write_strb(w_write_strb),.write_last(w_write_last),
        .mem_done_valid(w_done_valid),.mem_done_ready(w_done_ready),.mem_done_status(w_done_status),.mem_done_id(w_done_id),
        .mem_done_epoch(w_done_epoch),.mem_done_client(w_done_client),.abort_req(w_abort),.debug_state(write_debug_state),
        .debug_taken(write_taken),.debug_sent(write_sent),.debug_retired(write_retired),.debug_bursts(write_bursts),
        .debug_owner(write_owner),.debug_skid(tx_skid_valid));

    wire [1:0] arbiter_state;wire [31:0] arbiter_local_id,fault_done_id,fault_done_epoch;
    wire [2:0] fault_done_client;wire [3:0] fault_done_status;
    b03_post_mem_arbiter #(.POST_CLIENT(POST_CLIENT),.INITIAL_GLOBAL_ID(INITIAL_GLOBAL_ID)) memory_arbiter(
        .clk(clk),.reset_n(rg_memory_arbiter_reset_n),.cancel_request(cancel_children),.bridge_fault(bridge_fault),.bridge_epoch(bridge_epoch),
        .r_cmd_valid(r_cmd_valid),.r_cmd_ready(r_cmd_ready),.r_cmd_write(r_cmd_write),.r_cmd_offset(r_cmd_offset),.r_cmd_id(r_cmd_id),
        .r_cmd_epoch(r_cmd_epoch),.r_cmd_beats(r_cmd_beats),.r_cmd_client(r_cmd_client),
        .r_read_valid(r_read_valid),.r_read_ready(r_read_ready),.r_read_data(r_read_data),.r_read_last(r_read_last),
        .r_done_valid(r_done_valid),.r_done_ready(r_done_ready),.r_done_status(r_done_status),.r_done_id(r_done_id),
        .r_done_epoch(r_done_epoch),.r_done_client(r_done_client),.r_abort_req(r_abort),
        .w_cmd_valid(w_cmd_valid),.w_cmd_ready(w_cmd_ready),.w_cmd_write(w_cmd_write),.w_cmd_offset(w_cmd_offset),.w_cmd_id(w_cmd_id),
        .w_cmd_epoch(w_cmd_epoch),.w_cmd_beats(w_cmd_beats),.w_cmd_client(w_cmd_client),
        .w_write_valid(w_write_valid),.w_write_ready(w_write_ready),.w_write_data(w_write_data),.w_write_strb(w_write_strb),.w_write_last(w_write_last),
        .w_done_valid(w_done_valid),.w_done_ready(w_done_ready),.w_done_status(w_done_status),.w_done_id(w_done_id),
        .w_done_epoch(w_done_epoch),.w_done_client(w_done_client),.w_abort_req(w_abort),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_offset(cmd_offset),.cmd_id(cmd_id),.cmd_epoch(cmd_epoch),
        .cmd_beats(cmd_beats),.cmd_client(cmd_client),.write_valid(write_valid),.write_ready(write_ready),.write_data(write_data),
        .write_strb(write_strb),.write_last(write_last),.read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),.read_last(read_last),
        .mem_done_valid(mem_done_valid),.mem_done_ready(mem_done_ready),.mem_done_status(mem_done_status),.mem_done_id(mem_done_id),
        .mem_done_epoch(mem_done_epoch),.mem_done_client(mem_done_client),.abort_req(abort_req),.busy(m_busy),
        .quarantined(m_q),.reset_required(m_reset),.fault_status(m_fault),.tag_exhausted(global_exhausted),
        .debug_state(arbiter_state),.debug_owner(debug_owner),.debug_local_id(arbiter_local_id),.debug_global_id(debug_global_id),
        .fault_done_id(fault_done_id),.fault_done_epoch(fault_done_epoch),.fault_done_client(fault_done_client),.fault_done_status(fault_done_status));

    wire head_fire=core_ce && head_valid && head_ready;
    wire table_fire=core_ce && table_req_valid && table_req_ready;
    wire record_fire=core_ce && record_valid && record_ready;
    wire batch_fire=core_ce && batch_valid && batch_ready;
    wire writer_retire=core_ce && writer_done_valid;
    wire writer_identity_ok=writer_done_cmd==identity && writer_done_epoch==post_epoch && writer_done_frame==frame &&
        writer_done_base==pending_batch_base && writer_done_count==pending_batch_count;
    wire writer_bad=writer_retire && (writer_done_status!=0 || !writer_identity_ok || !batch_inflight);
    wire batch_identity_ok=batch_cmd==identity && batch_epoch==post_epoch && batch_frame==frame &&
        batch_base==debug_records_taken && batch_count>=1 && batch_count<=16 &&
        ({1'b0,batch_base}+{8'd0,batch_count})<={1'b0,capacity} && !batch_inflight;
    wire progress=(cmd_valid&&cmd_ready)||(read_valid&&read_ready)||(write_valid&&write_ready)||
        (mem_done_valid&&mem_done_ready)||head_fire||table_fire||record_fire||batch_fire||writer_retire||
        (previous_post_state!=debug_post_state);
    wire timeout_event=active && ENGINE_STALL_LIMIT>0 && !progress && stalled>=ENGINE_STALL_LIMIT-1;
    task isolate;
        input [3:0] reason;input [7:0] detail;
        begin
            if(!quarantined)begin
                quarantined<=1;reset_required<=1;post_cancel<=1;
                if(!done_pending)begin
                    done_status<=reason;done_detail<=detail;done_face_count<=0;done_nms_count<=0;done_crc<=0;done_pending<=1;
                end
            end
            state<=ISOLATED;
        end
    endtask
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;done_pending<=0;post_cancel<=0;quarantined<=0;reset_required<=0;saved_readable<=0;
            heads_offset<=0;heads_bytes<=0;table_offset<=0;table_bytes<=0;result_offset<=0;result_bytes<=0;
            head_generation<=0;identity<=0;epoch<=0;post_epoch<=0;frame<=0;capacity<=0;source_w<=0;source_h<=0;
            resized_w<=0;resized_h<=0;pad_left<=0;pad_top<=0;writer_next_id<=INITIAL_WRITER_ID;
            pending_batch_base<=0;pending_batch_count<=0;retired_record_count<=0;
            writer_id_exhausted<=INITIAL_WRITER_ID==0;batch_inflight<=0;stalled<=0;previous_post_state<=0;
            done_status<=0;done_detail<=0;done_face_count<=0;done_nms_count<=0;done_crc<=0;
            total_cycles<=0;post_cycles<=0;post_wait<=0;post_paused<=0;debug_head_beats<=0;debug_table_requests<=0;
            debug_records_taken<=0;debug_batches_retired<=0;debug_bridge_commands<=0;debug_bridge_completions<=0;
        end else begin
            post_cancel<=0;previous_post_state<=debug_post_state;
            if(done_valid && done_ready)done_pending<=0;
            if(active)total_cycles<=total_cycles+1'b1;
            if(!active || progress)stalled<=0;else if(stalled!=32'hffffffff)stalled<=stalled+1'b1;
            if(head_fire)debug_head_beats<=debug_head_beats+1'b1;
            if(table_fire)debug_table_requests<=debug_table_requests+1'b1;
            if(record_fire)debug_records_taken<=debug_records_taken+1'b1;
            if(cmd_valid&&cmd_ready)debug_bridge_commands<=debug_bridge_commands+1'b1;
            if(mem_done_valid&&mem_done_ready)debug_bridge_completions<=debug_bridge_completions+1'b1;
            if(batch_fire)begin batch_inflight<=1;pending_batch_base<=batch_base;pending_batch_count<=batch_count;end
            if(writer_retire && !writer_bad)begin
                batch_inflight<=0;debug_batches_retired<=debug_batches_retired+1'b1;
                retired_record_count<=retired_record_count+{7'd0,writer_done_count};
                if(writer_last_id==32'hffffffff)writer_id_exhausted<=1;
                else writer_next_id<=writer_last_id+1'b1;
            end
            if(state!=ISOLATED && bridge_fault)isolate(7,1);
            else if(active && state!=CHECK && bridge_epoch!=epoch)isolate(7,2);
            else if(active && cancel_request)isolate(6,0);
            else if(state!=ISOLATED && (r_q||r_reset))isolate(2,{4'd0,r_fault});
            else if(state!=ISOLATED && (w_q||w_reset))isolate(3,{4'd0,w_fault});
            else if(state!=ISOLATED && (m_q||m_reset))isolate(4,{4'd0,m_fault});
            else if(state!=ISOLATED && post_q)isolate(5,255);
            else if(writer_bad)isolate(3,{4'd0,writer_done_status});
            else if(batch_fire && !batch_identity_ok)isolate(3,129);
            else if(active && writer_id_exhausted && batch_valid)isolate(3,128);
            else if(timeout_event)isolate(8,0);
            else case(state)
                IDLE:if(start_valid&&start_ready)begin
                    heads_offset<=cfg_heads_offset;heads_bytes<=cfg_heads_bytes;table_offset<=cfg_table_offset;table_bytes<=cfg_table_bytes;
                    result_offset<=cfg_result_offset;result_bytes<=cfg_result_bytes;head_generation<=cfg_head_generation;
                    identity<=cfg_cmd_id;epoch<=cfg_bridge_epoch;post_epoch<=context_epoch;frame<=cfg_frame_id;capacity<=cfg_capacity;
                    saved_readable<=cfg_heads_readable;source_w<=cfg_source_w;source_h<=cfg_source_h;
                    resized_w<=cfg_resized_w;resized_h<=cfg_resized_h;pad_left<=cfg_pad_left;pad_top<=cfg_pad_top;
                    done_status<=0;done_detail<=0;done_face_count<=0;done_nms_count<=0;done_crc<=0;done_pending<=0;
                    total_cycles<=0;post_cycles<=0;post_wait<=0;post_paused<=0;batch_inflight<=0;stalled<=0;
                    pending_batch_base<=0;pending_batch_count<=0;retired_record_count<=0;
                    debug_head_beats<=0;debug_table_requests<=0;debug_records_taken<=0;debug_batches_retired<=0;
                    debug_bridge_commands<=0;debug_bridge_completions<=0;state<=CHECK;
                end
                CHECK:if(!cfg_legal)begin done_status<=1;done_detail<=0;done_pending<=1;state<=HELD;end else state<=HEAD_IDLE;
                // Observe public quiet with load_begin low; issue the reader descriptor later.
                HEAD_IDLE:if(core_ce&&core_task_ready)state<=HEAD_START;
                HEAD_START:if(core_ce&&head_start_ready)state<=HEAD_WAIT;
                HEAD_WAIT:if(core_ce&&head_done_valid)begin
                    if(head_done_status!=0)begin done_status<=1;done_detail<={4'd0,head_done_status};done_pending<=1;state<=HELD;end
                    else if(head_done_cmd!=identity || head_done_epoch!=post_epoch || head_done_frame!=frame ||
                            debug_head_beats!=824 || !heads_loaded)isolate(2,129);
                    else state<=SUBMIT;
                end
                SUBMIT:if(core_ce&&core_task_ready)state<=RUN;
                RUN:if(core_ce&&core_done_valid)begin
                    post_cycles<=core_cycles;post_wait<=core_wait;post_paused<=core_paused;
                    if(core_done_status!=0)isolate(5,{3'd0,core_done_status});
                    else if(core_cmd!=identity || core_epoch!=post_epoch || core_frame!=frame || core_faces!=debug_records_taken)
                        isolate(5,128);
                    else begin done_face_count<=core_faces;done_nms_count<=core_nms;done_crc<=core_crc;state<=WAIT_TX;end
                end
                WAIT_TX:if(!batch_inflight && writer_batch_ready && head_start_ready && !m_busy && core_task_ready)begin
                    if(retired_record_count!=done_face_count || debug_records_taken!=done_face_count)isolate(3,130);
                    else begin done_status<=0;done_detail<=0;done_pending<=1;state<=HELD;end
                end
                HELD:if(done_valid&&done_ready)state<=quarantined ? ISOLATED : IDLE;
                ISOLATED:state<=ISOLATED;
                default:isolate(8,255);
            endcase
        end
    end

    // spec155: physical identity controls, unchanged cycle/reset semantics.
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_core_rst_n_buffer(.I0(reset_n),.Z(rg_core_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_read_dma_reset_n_buffer(.I0(reset_n),.Z(rg_read_dma_reset_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_writer_reset_n_buffer(.I0(reset_n),.Z(rg_writer_reset_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_memory_arbiter_reset_n_buffer(.I0(reset_n),.Z(rg_memory_arbiter_reset_n));
endmodule
