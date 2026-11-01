// Board-lifetime complete frame: real autonomous MODEL -> POST -> observed

// final records -> private header. This remains diagnostic scope zero.

module b03_frame_exec_payload #(
    // The face application only needs the graph heads.  When disabled, the
    // CPU consumes heads_base and performs decode/NMS, so the sizeable table
    // scan, decoder, sorter and record writer are removed from the FPGA.
    parameter integer ENABLE_HARDWARE_POST = 1,
    parameter integer TRUSTED_MODEL = 0,
    parameter integer PREVALIDATED_TASK_LAYOUT = 0,
    parameter integer M_LANES = 16,
    parameter integer QUANTIZER_LANES = 2
)(

    input wire clk,board_reset_n,session_reset_n,compute_running,run_ce,cancel_request,bridge_fault,

    input wire [31:0] epoch,addr_cfg_version,cfg_window_base,cfg_window_bytes,

    input wire host_write_valid,input wire [31:0] host_write_offset,input wire [4:0] host_write_beats,

    input wire start_valid,output wire start_ready,input wire [1023:0] task_words,

    output reg done_valid,input wire done_ready,

    output reg [31:0] done_status,done_detail,done_cmd_id,done_epoch,

    output reg [63:0] done_frame_id,output reg [11:0] done_faces,

    output reg [31:0] done_result_offset,done_result_bytes,done_crc,

    output reg [63:0] done_total_cycles,done_model_cycles,done_post_cycles,

    output wire done_live,busy,select_post,cancel_all,

    output reg compute_fault_valid,output reg [175:0] compute_fault_payload,

    output wire [7:0] debug_stage,debug_op,

    output wire mem_req_valid,input wire mem_req_ready,output wire mem_req_write,mem_req_verify,

    output wire [31:0] mem_req_offset,mem_req_tag,output wire [4:0] mem_req_beats,output wire [2:0] mem_req_client,

    output wire mem_w_valid,input wire mem_w_ready,output wire [255:0] mem_w_data,

    output wire [31:0] mem_w_strb,output wire mem_w_last,

    input wire mem_r_valid,output wire mem_r_ready,input wire [255:0] mem_r_data,input wire mem_r_last,

    input wire mem_rsp_valid,output wire mem_rsp_ready,input wire [3:0] mem_rsp_status,input wire [31:0] mem_rsp_tag,

    output wire p_cmd_valid,input wire p_cmd_ready,output wire p_cmd_write,

    output wire [31:0] p_cmd_offset,p_cmd_id,p_cmd_epoch,output wire [4:0] p_cmd_beats,output wire [2:0] p_cmd_client,

    output wire p_write_valid,input wire p_write_ready,output wire [255:0] p_write_data,

    output wire [31:0] p_write_strb,output wire p_write_last,

    input wire p_read_valid,output wire p_read_ready,input wire [255:0] p_read_data,input wire p_read_last,

    input wire p_done_valid,output wire p_done_ready,input wire [3:0] p_done_status,

    input wire [31:0] p_done_id,p_done_epoch,input wire [2:0] p_done_client,

    output wire p_abort_req,p_quarantined,output wire [175:0] post_fault_payload

);

    localparam IDLE=0,GSTART=1,GWAIT=2,SCANPLAN=3,SCANREQ=4,SCANRUN=5,

        PSTART=6,PWAIT=7,HBUILD=8,HCRC=9,HREQ=10,HWRITE=11,HWAIT=12,HELD=13;

    reg [7:0] state;reg active,rsp_live;reg [1:0] owner;

    reg [1023:0] task_saved;reg [31:0] base_saved,bytes_saved,version_saved,watchdog;

    reg [31:0] identity,task_epoch,locked_epoch,generation,next_generation;

    reg [63:0] frame,total,model_cycles,post_cycles;

    reg [31:0] heads_base,table_base,result_base,result_alloc,expected_table_crc,model_tag;

    reg [11:0] faces,capacity;reg [31:0] records_crc;

    reg [13:0] source_w,source_h;reg [8:0] resized_w,resized_h,pad_left,pad_top;

    wire [7:0] g_stage,g_op;wire [3:0] p_stage;

    wire leaf_reset_n=board_reset_n&&session_reset_n;

    wire poison=!session_reset_n||!compute_running||epoch!=locked_epoch||bridge_fault||

        cfg_window_base!=base_saved||cfg_window_bytes!=bytes_saved||addr_cfg_version!=version_saved;

    reg [31:0] deadline_left;reg deadline_expired;

    wire expired=active&&deadline_expired;

    assign cancel_all=active&&(cancel_request||poison||expired);

    assign start_ready=board_reset_n&&session_reset_n&&compute_running&&epoch!=0&&state==IDLE&&

        !active&&!done_valid&&!cancel_request&&!bridge_fault&&!compute_fault_valid&&next_generation!=0;

    assign done_live=done_valid&&rsp_live&&session_reset_n&&compute_running&&epoch==done_epoch&&!bridge_fault&&!compute_fault_valid;

    assign busy=active||done_valid;assign select_post=owner==3;

    assign debug_stage=state==GWAIT?g_stage:state==PWAIT?{4'h8,p_stage}:state;

    assign debug_op=g_op;

    task finish;

        input [31:0] s,d;input live,reset_needed;

        begin

            done_valid<=1;done_status<=s;done_detail<=d;done_cmd_id<=identity;done_epoch<=task_epoch;done_frame_id<=frame;

            done_faces<=s==0?(ENABLE_HARDWARE_POST?faces:12'd0):12'd0;done_crc<=s==0?(ENABLE_HARDWARE_POST?records_crc:32'd0):32'd0;

            done_result_offset<=s==0?(ENABLE_HARDWARE_POST?result_base-base_saved:heads_base-base_saved):32'd0;
            done_result_bytes<=s==0?(ENABLE_HARDWARE_POST?(32'd128+{15'd0,faces,5'd0}):32'd26368):32'd0;

            done_total_cycles<=total;done_model_cycles<=model_cycles;done_post_cycles<=post_cycles;

            rsp_live<=live;active<=0;state<=HELD;

            if(reset_needed)begin

                compute_fault_valid<=1;compute_fault_payload<={8'hb6,8'd0,identity,task_epoch,frame[31:0],s,d};

            end else owner<=0;

        end

    endtask



    wire g_start_ready,g_done_valid,g_busy;

    wire [31:0] g_status,g_detail,g_cmd,g_epoch,g_heads,g_table,g_result,g_alloc,g_table_crc,g_model_tag;

    wire [63:0] g_frame,g_cycles;wire [11:0] g_capacity;wire [13:0] g_sw,g_sh;

    wire [8:0] g_rw,g_rh,g_pl,g_pt;

    wire l_start,l_start_ready,l_preflight,l_done,l_done_ready;

    wire [1023:0] l_op;wire [31:0] l_workspace,l_src0,l_src1,l_dst,l_epoch,l_tag,l_status,l_detail,l_done_tag,l_done_opid;

    wire [63:0] l_cycles;

    wire g_req_valid,g_req_ready,g_req_write,g_req_verify,g_w_valid,g_w_ready,g_w_last,g_r_valid,g_r_ready,g_r_last,g_rsp_valid,g_rsp_ready;

    wire [31:0] g_req_offset,g_req_tag,g_w_strb,g_rsp_tag;wire [4:0] g_req_beats;wire [2:0] g_req_client;wire [3:0] g_rsp_status;

    wire [255:0] g_w_data,g_r_data;

    wire l_req_valid,l_req_ready,l_req_write,l_req_verify,l_w_valid,l_w_ready,l_w_last,l_r_valid,l_r_ready,l_r_last,l_rsp_valid,l_rsp_ready;

    wire [31:0] l_req_offset,l_req_tag,l_w_strb,l_rsp_tag;wire [4:0] l_req_beats;wire [2:0] l_req_client;wire [3:0] l_rsp_status;

    wire [255:0] l_w_data,l_r_data;wire l_busy;wire [7:0] l_stage;wire [31:0] l_macs,l_qgroups,l_rows;

    // spec155: declare identity outputs before their consumer instances.
    wire rg_graph_rst_n;
    wire rg_layer_rst_n;
    wire rg_post_reset_n;
    wire rg_table_cache_rst_n;

    b03_graph_engine_cap #(.LATCH_TASK(0),.TRUSTED_MODEL(TRUSTED_MODEL),.PREVALIDATED_TASK_LAYOUT(PREVALIDATED_TASK_LAYOUT)) graph(

        .clk(clk),.rst_n(rg_graph_rst_n),.run_ce(run_ce),.cancel_request(cancel_all),.bridge_fault(bridge_fault),

        .epoch(epoch),.cfg_window_base(cfg_window_base),.cfg_window_bytes(cfg_window_bytes),.addr_cfg_version(addr_cfg_version),

        .start_valid(state==GSTART&&active&&!cancel_all),.start_ready(g_start_ready),.task_words(task_saved),

        .done_valid(g_done_valid),.done_ready(state==GWAIT),.status(g_status),.detail(g_detail),.cmd_id(g_cmd),.frame_id(g_frame),.done_epoch(g_epoch),.cycles(g_cycles),

        .done_heads_offset(g_heads),.done_table_offset(g_table),.done_result_offset(g_result),.done_result_alloc(g_alloc),

        .done_capacity(g_capacity),.done_source_w(g_sw),.done_source_h(g_sh),.done_resized_w(g_rw),.done_resized_h(g_rh),.done_pad_left(g_pl),.done_pad_top(g_pt),

        .done_expected_table_crc32(g_table_crc),.done_model_tag(g_model_tag),.busy(g_busy),.debug_stage(g_stage),.debug_op(g_op),

        .layer_start_valid(l_start),.layer_start_ready(l_start_ready),.layer_op_words(l_op),.layer_preflight(l_preflight),

        .layer_workspace_base(l_workspace),.layer_src0_base(l_src0),.layer_src1_base(l_src1),.layer_dst_base(l_dst),.layer_epoch(l_epoch),.layer_tag(l_tag),

        .layer_done_valid(l_done),.layer_done_ready(l_done_ready),.layer_done_status(l_status),.layer_done_detail(l_detail),.layer_done_tag(l_done_tag),.layer_done_op_id(l_done_opid),.layer_done_cycles(l_cycles),

        .mem_req_valid(g_req_valid),.mem_req_ready(g_req_ready),.mem_req_write(g_req_write),.mem_req_verify(g_req_verify),.mem_req_offset(g_req_offset),.mem_req_tag(g_req_tag),.mem_req_beats(g_req_beats),.mem_req_client(g_req_client),

        .mem_w_valid(g_w_valid),.mem_w_ready(g_w_ready),.mem_w_data(g_w_data),.mem_w_strb(g_w_strb),.mem_w_last(g_w_last),

        .mem_r_valid(g_r_valid),.mem_r_ready(g_r_ready),.mem_r_data(g_r_data),.mem_r_last(g_r_last),.mem_rsp_valid(g_rsp_valid),.mem_rsp_ready(g_rsp_ready),.mem_rsp_status(g_rsp_status),.mem_rsp_tag(g_rsp_tag),

        .layer_mem_req_valid(l_req_valid),.layer_mem_req_ready(l_req_ready),.layer_mem_req_write(l_req_write),.layer_mem_req_verify(l_req_verify),.layer_mem_req_offset(l_req_offset),.layer_mem_req_tag(l_req_tag),.layer_mem_req_beats(l_req_beats),.layer_mem_req_client(l_req_client),

        .layer_mem_w_valid(l_w_valid),.layer_mem_w_ready(l_w_ready),.layer_mem_w_data(l_w_data),.layer_mem_w_strb(l_w_strb),.layer_mem_w_last(l_w_last),

        .layer_mem_r_valid(l_r_valid),.layer_mem_r_ready(l_r_ready),.layer_mem_r_data(l_r_data),.layer_mem_r_last(l_r_last),.layer_mem_rsp_valid(l_rsp_valid),.layer_mem_rsp_ready(l_rsp_ready),.layer_mem_rsp_status(l_rsp_status),.layer_mem_rsp_tag(l_rsp_tag));

    b03_layer_exec_payload #(.ENABLE_RUNTIME_DIAGNOSTICS(ENABLE_HARDWARE_POST),.TRUSTED_MODEL(TRUSTED_MODEL),.M_LANES(M_LANES),.QUANTIZER_LANES(QUANTIZER_LANES)) layer(

        .clk(clk),.rst_n(rg_layer_rst_n),.run_ce(run_ce),.cancel_request(cancel_all),.start_valid(l_start),.start_ready(l_start_ready),.op_words(l_op),.preflight(l_preflight),

        .workspace_base(l_workspace),.src0_base(l_src0),.src1_base(l_src1),.dst_base(l_dst),.epoch(l_epoch),.tag(l_tag),

        .done_valid(l_done),.done_ready(l_done_ready),.done_status(l_status),.done_detail(l_detail),.done_tag(l_done_tag),.done_op_id(l_done_opid),.cycles(l_cycles),

        .mem_req_valid(l_req_valid),.mem_req_ready(l_req_ready),.mem_req_write(l_req_write),.mem_req_verify(l_req_verify),.mem_req_offset(l_req_offset),.mem_req_tag(l_req_tag),.mem_req_beats(l_req_beats),.mem_req_client(l_req_client),

        .mem_w_valid(l_w_valid),.mem_w_ready(l_w_ready),.mem_w_data(l_w_data),.mem_w_strb(l_w_strb),.mem_w_last(l_w_last),

        .mem_r_valid(l_r_valid),.mem_r_ready(l_r_ready),.mem_r_data(l_r_data),.mem_r_last(l_r_last),.mem_rsp_valid(l_rsp_valid),.mem_rsp_ready(l_rsp_ready),.mem_rsp_status(l_rsp_status),.mem_rsp_tag(l_rsp_tag),

        .busy(l_busy),.debug_stage(l_stage),.stat_mac_vectors(l_macs),.stat_quant_groups(l_qgroups),.stat_rows(l_rows));



    wire p_start_ready,p_engine_done,p_reset,p_busy;

    wire [3:0] p_status;wire [7:0] p_detail,p_post_stage;wire [11:0] p_faces,p_nms;

    wire [31:0] p_crc,p_cmd,p_bridge_epoch,p_post_epoch,p_global,p_trequests,p_commands,p_completions;

    wire [63:0] p_frame,p_total,p_cycles,p_wait,p_paused;wire [1:0] p_owner;wire [10:0] p_head_beats;wire [11:0] p_records,p_batches;

    assign post_fault_payload={8'hb7,8'h04,identity,task_epoch,frame[31:0],

        {8'd0,p_status,p_detail,p_stage,p_post_stage},result_base};

    generate
    if (ENABLE_HARDWARE_POST) begin : g_hardware_post
    b03_post_memory_engine_payload post(

        .clk(clk),.reset_n(rg_post_reset_n),.run_ce(run_ce),.cancel_request(cancel_all),.bridge_fault(bridge_fault),.bridge_epoch(epoch),

        .start_valid(state==PSTART&&active&&!cancel_all),.start_ready(p_start_ready),

        .cfg_heads_offset(heads_base),.cfg_heads_bytes(32'd26368),.cfg_table_offset(table_base),.cfg_table_bytes(32'd1572864),

        .cfg_result_offset(result_base),.cfg_result_bytes(result_alloc),.cfg_head_generation(generation),.cfg_cmd_id(identity),.cfg_bridge_epoch(task_epoch),

        .cfg_capacity(capacity),.cfg_frame_id(frame),.cfg_heads_readable(1'b1),.cfg_source_w(source_w),.cfg_source_h(source_h),

        .cfg_resized_w(resized_w),.cfg_resized_h(resized_h),.cfg_pad_left(pad_left),.cfg_pad_top(pad_top),

        .done_valid(p_engine_done),.done_ready(state==PWAIT),.done_status(p_status),.done_detail(p_detail),.done_face_count(p_faces),.done_nms_count(p_nms),.done_crc(p_crc),

        .done_cmd_id(p_cmd),.done_bridge_epoch(p_bridge_epoch),.done_post_epoch(p_post_epoch),.done_frame_id(p_frame),.total_cycles(p_total),.post_cycles(p_cycles),.post_wait(p_wait),.post_paused(p_paused),

        .quarantined(p_quarantined),.reset_required(p_reset),

        .cmd_valid(p_cmd_valid),.cmd_ready(p_cmd_ready),.cmd_write(p_cmd_write),.cmd_offset(p_cmd_offset),.cmd_id(p_cmd_id),.cmd_epoch(p_cmd_epoch),.cmd_beats(p_cmd_beats),.cmd_client(p_cmd_client),

        .write_valid(p_write_valid),.write_ready(p_write_ready),.write_data(p_write_data),.write_strb(p_write_strb),.write_last(p_write_last),

        .read_valid(p_read_valid),.read_ready(p_read_ready),.read_data(p_read_data),.read_last(p_read_last),

        .mem_done_valid(p_done_valid),.mem_done_ready(p_done_ready),.mem_done_status(p_done_status),.mem_done_id(p_done_id),.mem_done_epoch(p_done_epoch),.mem_done_client(p_done_client),

        .abort_req(p_abort_req),.debug_state(p_stage),.debug_post_state(p_post_stage),.debug_owner(p_owner),.debug_global_id(p_global),

        .debug_head_beats(p_head_beats),.debug_table_requests(p_trequests),.debug_records_taken(p_records),.debug_batches_retired(p_batches),.debug_bridge_commands(p_commands),.debug_bridge_completions(p_completions));
    end else begin : g_cpu_post
        // No post engine owns the phase mux in CPU-post mode.  The frame
        // state machine completes immediately after graph retirement and the
        // software endpoint reads heads_base from DDR.
        assign p_start_ready = 1'b1;
        assign p_engine_done = 1'b0;
        assign p_status = 4'd0;
        assign p_detail = 8'd0;
        assign p_faces = 12'd0;
        assign p_nms = 12'd0;
        assign p_crc = 32'd0;
        assign p_cmd = 32'd0;
        assign p_bridge_epoch = 32'd0;
        assign p_post_epoch = 32'd0;
        assign p_frame = 64'd0;
        assign p_total = 64'd0;
        assign p_cycles = 64'd0;
        assign p_wait = 64'd0;
        assign p_paused = 64'd0;
        assign p_owner = 2'd0;
        assign p_head_beats = 11'd0;
        assign p_records = 12'd0;
        assign p_batches = 12'd0;
        assign p_trequests = 32'd0;
        assign p_commands = 32'd0;
        assign p_completions = 32'd0;
        assign p_cmd_valid = 1'b0;
        assign p_cmd_write = 1'b0;
        assign p_cmd_offset = 32'd0;
        assign p_cmd_id = 32'd0;
        assign p_cmd_epoch = 32'd0;
        assign p_cmd_beats = 5'd0;
        assign p_cmd_client = 3'd0;
        assign p_write_valid = 1'b0;
        assign p_write_data = 256'd0;
        assign p_write_strb = 32'd0;
        assign p_write_last = 1'b0;
        assign p_read_ready = 1'b0;
        assign p_done_ready = 1'b0;
        assign p_abort_req = 1'b0;
        assign p_quarantined = 1'b0;
        assign p_reset = 1'b0;
        assign p_stage = 8'd0;
        assign p_post_stage = 8'd0;
    end
    endgenerate



    // Readback scanner and private-header writer use the same local service.

    reg scan_records,scan_offer,scan_inflight,scan_rsp_seen,rx_valid,scan_write;

    reg [31:0] scan_base,scan_bytes,scan_cursor,scan_processed,scan_crc,scan_expected,scan_sequence,scan_tag,scan_offset;

    reg [4:0] scan_beats,scan_received;reg [255:0] rx_data;reg [2:0] rx_word;

    reg [1023:0] header;reg [5:0] header_word;reg [1:0] header_beat;reg header_data_done;

    wire table_cache_hit,table_cache_valid;wire [31:0] table_cache_commits,table_cache_invalidations;

    wire table_observed=active&&!cancel_all&&state==SCANRUN&&!scan_records&&scan_rsp_seen&&

        scan_received==scan_beats&&!rx_valid&&scan_processed==scan_bytes&&(~scan_crc)==scan_expected;

    b03_table_validation_cache table_cache(

        .clk(clk),.rst_n(rg_table_cache_rst_n),.invalidate(bridge_fault),

        .host_write_valid(host_write_valid),.host_write_offset(host_write_offset),.host_write_beats(host_write_beats),

        .commit_valid(table_observed),.commit_base(scan_base),.commit_crc(scan_expected),.commit_epoch(locked_epoch),.commit_version(version_saved),

        .query_base(g_table),.query_crc(g_table_crc),.query_epoch(locked_epoch),.query_version(version_saved),

        .hit(table_cache_hit),.valid(table_cache_valid),.commits(table_cache_commits),.invalidations(table_cache_invalidations));

    wire [31:0] crc_data=state==HCRC?header[32*header_word+:32]:rx_data[32*rx_word+:32];

    wire [31:0] crc_updated;

    b03_crc32_parallel4 crc_unit(.seed(scan_crc),.data(crc_data),.value(crc_updated));

    wire [31:0] scan_remaining=scan_bytes-scan_cursor;

    wire [7:0] page_offset=((scan_base+scan_cursor)>>5)&127;

    wire [8:0] page_left=9'd128-{1'b0,page_offset};

    wire [31:0] remaining_beats=scan_remaining>>5;

    wire [4:0] planned_beats=remaining_beats>16?(page_left<16?page_left[4:0]:5'd16):

        (remaining_beats>page_left?page_left[4:0]:remaining_beats[4:0]);

    wire scan_read=owner==2&&state==SCANRUN;

    wire rf=scan_read&&mem_r_valid&&mem_r_ready;

    wire sf=owner==2&&mem_rsp_valid&&mem_rsp_ready;

    wire [5:0] received_after={1'b0,scan_received}+{5'd0,rf};

    assign mem_req_valid=owner==1?g_req_valid:owner==2?scan_offer:1'b0;

    assign mem_req_write=owner==1?g_req_write:scan_write;

    assign mem_req_verify=owner==1?g_req_verify:scan_write;

    assign mem_req_offset=owner==1?g_req_offset:scan_offset;

    assign mem_req_tag=owner==1?g_req_tag:scan_tag;

    assign mem_req_beats=owner==1?g_req_beats:scan_beats;

    assign mem_req_client=owner==1?g_req_client:3'd5;

    assign mem_w_valid=owner==1?g_w_valid:owner==2&&state==HWRITE&&header_beat<4;

    assign mem_w_data=owner==1?g_w_data:header[256*header_beat+:256];

    assign mem_w_strb=owner==1?g_w_strb:32'hffffffff;

    assign mem_w_last=owner==1?g_w_last:header_beat==3;

    assign mem_r_ready=owner==1?g_r_ready:scan_read&&scan_inflight&&!rx_valid;

    assign mem_rsp_ready=owner==1?g_rsp_ready:owner==2&&scan_inflight&&!scan_rsp_seen;

    assign g_req_ready=owner==1&&mem_req_ready;assign g_w_ready=owner==1&&mem_w_ready;

    assign g_r_valid=owner==1&&mem_r_valid;assign g_r_data=mem_r_data;assign g_r_last=mem_r_last;

    assign g_rsp_valid=owner==1&&mem_rsp_valid;assign g_rsp_status=mem_rsp_status;assign g_rsp_tag=mem_rsp_tag;

    wire header_wf=mem_w_valid&&mem_w_ready&&owner==2;

    integer n;

    always @(posedge clk or negedge board_reset_n)begin

        if(!board_reset_n)begin

            state<=IDLE;active<=0;rsp_live<=0;owner<=0;task_saved<=0;base_saved<=0;bytes_saved<=0;version_saved<=0;watchdog<=0;deadline_left<=0;deadline_expired<=0;

            identity<=0;task_epoch<=0;locked_epoch<=0;generation<=0;next_generation<=1;frame<=0;total<=0;model_cycles<=0;post_cycles<=0;

            heads_base<=0;table_base<=0;result_base<=0;result_alloc<=0;expected_table_crc<=0;model_tag<=0;faces<=0;capacity<=0;records_crc<=0;

            source_w<=0;source_h<=0;resized_w<=0;resized_h<=0;pad_left<=0;pad_top<=0;

            done_valid<=0;done_status<=0;done_detail<=0;done_cmd_id<=0;done_epoch<=0;done_frame_id<=0;done_faces<=0;done_result_offset<=0;done_result_bytes<=0;done_crc<=0;

            done_total_cycles<=0;done_model_cycles<=0;done_post_cycles<=0;compute_fault_valid<=0;compute_fault_payload<=0;

            scan_records<=0;scan_offer<=0;scan_inflight<=0;scan_rsp_seen<=0;rx_valid<=0;scan_write<=0;scan_base<=0;scan_bytes<=0;scan_cursor<=0;scan_processed<=0;

            scan_crc<=32'hffffffff;scan_expected<=0;scan_sequence<=0;scan_tag<=0;scan_offset<=0;scan_beats<=0;scan_received<=0;rx_data<=0;rx_word<=0;header<=0;header_word<=0;header_beat<=0;header_data_done<=0;

        end else begin

            if(done_valid&&done_ready)begin done_valid<=0;if(!active&&!compute_fault_valid)state<=IDLE;end

            if(done_valid&&(!session_reset_n||!compute_running||epoch!=done_epoch||bridge_fault))rsp_live<=0;

            if(active)begin

                total<=total+1;

                if(deadline_left!=0)begin

                    deadline_left<=deadline_left-32'd1;

                    if(deadline_left==1)deadline_expired<=1;

                end

            end

            if(!session_reset_n)begin

                owner<=0;scan_offer<=0;scan_inflight<=0;scan_rsp_seen<=0;rx_valid<=0;compute_fault_valid<=0;

                if(active)finish(18,32'h53455352,0,0);

                else if(!done_valid||done_ready)state<=IDLE;

            end else begin

                if(start_valid&&start_ready)begin

                    task_saved<=task_words;base_saved<=cfg_window_base;bytes_saved<=cfg_window_bytes;version_saved<=addr_cfg_version;

                    watchdog<=task_words[960+:32];deadline_left<=task_words[960+:32];deadline_expired<=0;identity<=task_words[448+:32];frame<=task_words[480+:64];task_epoch<=task_words[544+:32];locked_epoch<=epoch;

                    generation<=next_generation;next_generation<=next_generation+1;

                    active<=1;rsp_live<=1;total<=0;model_cycles<=0;post_cycles<=0;faces<=0;records_crc<=0;owner<=1;state<=GSTART;

                end

                if(owner==2&&scan_offer&&mem_req_ready)begin

                    scan_offer<=0;scan_inflight<=1;scan_received<=0;scan_rsp_seen<=0;

                    if(state==HREQ)begin header_beat<=0;header_data_done<=0;state<=HWRITE;end else state<=SCANRUN;

                end

                if(rf)begin

                    scan_received<=scan_received+1;rx_valid<=1;rx_data<=mem_r_data;rx_word<=0;

                    if(scan_received>=scan_beats||mem_r_last!=(received_after=={1'b0,scan_beats}))finish(18,32'h534c4153,0,1);

                end

                if(sf)begin

                    scan_rsp_seen<=1;

                    if(mem_rsp_status!=0||mem_rsp_tag!=scan_tag||

                        (state==SCANRUN&&received_after!={1'b0,scan_beats})||

                        (state!=SCANRUN&&state!=HWAIT&&state!=HWRITE)||

                        (scan_write&&!header_data_done&&!(header_wf&&header_beat==3)))finish(18,{24'd0,mem_rsp_status,4'd2},0,1);

                end

                if(active&&!cancel_all)case(state)

                    GSTART:if(g_start_ready)state<=GWAIT;

                    GWAIT:if(g_done_valid)begin

                        model_cycles<=g_cycles;

                        if(g_cmd!=identity||g_epoch!=locked_epoch||g_frame!=frame)finish(22,32'h47494454,0,1);

                        else if(g_status!=0)finish(g_status,g_detail,1,g_status==18||g_status==22);

                        else begin

                            heads_base<=g_heads;table_base<=g_table;result_base<=g_result;result_alloc<=g_alloc;expected_table_crc<=g_table_crc;model_tag<=g_model_tag;

                            capacity<=g_capacity;source_w<=g_sw;source_h<=g_sh;resized_w<=g_rw;resized_h<=g_rh;pad_left<=g_pl;pad_top<=g_pt;

                            if(!ENABLE_HARDWARE_POST)begin
                                // Graph retirement is the frame completion
                                // point in CPU-post mode.  heads_base is
                                // returned through the completion record.
                                finish(0,0,1,0);
                                // g_heads is a same-cycle graph result, so
                                // override the task helper's old register
                                // value with the freshly retired address.
                                done_faces<=0;
                                done_crc<=0;
                                done_result_offset<=g_heads-base_saved;
                                done_result_bytes<=32'd26368;
                            end else if(table_cache_hit)begin owner<=3;state<=PSTART;end

                            else begin

                                owner<=2;scan_records<=0;scan_base<=g_table;scan_bytes<=1572864;scan_cursor<=0;scan_processed<=0;scan_crc<=32'hffffffff;scan_expected<=g_table_crc;state<=SCANPLAN;

                            end

                        end

                    end

                    SCANPLAN:begin

                        if(scan_sequence==32'hffffffff)finish(18,32'h53494445,0,1);

                        else begin

                            scan_offset<=scan_base+scan_cursor;scan_beats<=planned_beats;scan_tag<=scan_sequence+1;scan_sequence<=scan_sequence+1;scan_write<=0;

                            scan_offer<=1;scan_inflight<=0;scan_rsp_seen<=0;scan_received<=0;rx_valid<=0;state<=SCANREQ;

                        end

                    end

                    SCANRUN:begin

                        if(run_ce&&rx_valid)begin

                            scan_crc<=crc_updated;

                            if(rx_word==7)begin rx_valid<=0;scan_processed<=scan_processed+32;end else rx_word<=rx_word+1;

                        end

                        if(scan_rsp_seen&&scan_received==scan_beats&&!rx_valid)begin

                            scan_inflight<=0;

                            if(scan_processed==scan_bytes)begin

                                if((~scan_crc)!=scan_expected)finish(scan_records?18:3,scan_records?32'h52435243:32'h54435243,1,scan_records);

                                else if(scan_records)state<=HBUILD;

                                else begin owner<=3;state<=PSTART;end

                            end else begin scan_cursor<=scan_cursor+{22'd0,scan_beats,5'd0};state<=SCANPLAN;end

                        end

                    end

                    PSTART:if(p_start_ready)state<=PWAIT;

                    PWAIT:if(p_engine_done)begin

                        post_cycles<=p_total;

                        if(p_cmd!=identity||p_frame!=frame||p_bridge_epoch!=task_epoch)finish(22,32'h50494454,0,1);

                        else if(p_status!=0)finish(p_status==1?8:18,{24'd0,p_detail},p_status==1,p_status!=1);

                        else begin

                            faces<=p_faces;records_crc<=p_crc;owner<=2;

                            if(p_faces==0)begin if(p_crc!=0)finish(22,32'h454d5054,0,1);else state<=HBUILD;end

                            else begin scan_records<=1;scan_base<=result_base+128;scan_bytes<={15'd0,p_faces,5'd0};scan_cursor<=0;scan_processed<=0;scan_crc<=32'hffffffff;scan_expected<=p_crc;state<=SCANPLAN;end

                        end

                    end

                    HBUILD:begin

                        header<=0;

                        header[0+:32]<=32'h3352504e;header[32+:32]<=1;header[64+:32]<=128;header[96+:32]<=1;

                        header[192+:32]<=identity;header[224+:32]<=task_epoch;header[256+:64]<=frame;

                        header[320+:32]<={20'd0,faces};header[352+:32]<={15'd0,faces,5'd0};header[384+:32]<=records_crc;

                        header[416+:32]<=result_base-base_saved+128;header[448+:32]<=model_tag;

                        header[512+:64]<=total;header[576+:64]<=model_cycles;header[640+:64]<=post_cycles;

                        header[704+:32]<={18'd0,source_w};header[736+:32]<={18'd0,source_h};

                        header[768+:32]<={23'd0,resized_w};header[800+:32]<={23'd0,resized_h};header[832+:32]<={23'd0,pad_left};header[864+:32]<={23'd0,pad_top};header[896+:32]<=version_saved;

                        header_word<=0;scan_crc<=32'hffffffff;scan_inflight<=0;scan_rsp_seen<=0;state<=HCRC;

                    end

                    HCRC:if(run_ce)begin

                        scan_crc<=crc_updated;

                        if(header_word==30)begin

                            header[992+:32]<=~crc_updated;scan_offset<=result_base;scan_beats<=4;scan_tag<=scan_sequence+1;scan_sequence<=scan_sequence+1;scan_write<=1;

                            scan_offer<=1;state<=HREQ;

                        end else header_word<=header_word+1;

                    end

                    HWRITE:if(header_wf)begin header_beat<=header_beat+1;if(header_beat==3)begin header_data_done<=1;state<=HWAIT;end end

                    HWAIT:if(scan_rsp_seen)begin scan_inflight<=0;finish(0,0,1,0);end

                    default:begin end

                endcase

                if(active&&cancel_all)finish(expired?16:cancel_request?17:18,expired?32'h57415443:cancel_request?32'h43414e43:32'h504f4953,0,1);

            end

        end

    end


    // spec155: physical identity controls, unchanged cycle/reset semantics.
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_graph_rst_n_buffer(.I0(leaf_reset_n),.Z(rg_graph_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_layer_rst_n_buffer(.I0(leaf_reset_n),.Z(rg_layer_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_post_reset_n_buffer(.I0(leaf_reset_n),.Z(rg_post_reset_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_table_cache_rst_n_buffer(.I0(leaf_reset_n),.Z(rg_table_cache_rst_n));
endmodule

