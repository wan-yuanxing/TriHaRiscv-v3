// Full real frame/bridge RTL with an address-exact native UI memory proxy.
// There is no HMIC or DDR3 device model. Host never uploads golden heads.
    reg run_ce=1,cancel_request=0,start_valid=0,done_ready=0,host_owner=1;
    reg [1023:0] task_words=0;
    reg [31:0] cfg_window_base=32'h01000000,cfg_window_bytes=32'h01000000,addr_cfg_version=1;
    reg h_req_valid=0,h_req_write=0,h_req_verify=0;reg [31:0] h_req_offset=0,h_req_tag=0;
    reg [4:0] h_req_beats=0;reg [2:0] h_req_client=6;
    reg h_w_valid=0,h_w_last=0;reg [255:0] h_w_data=0;reg [31:0] h_w_strb=32'hffffffff;
    reg h_r_ready=0,h_rsp_ready=0;
    wire  compute_running;
    wire  bridge_fault;
    wire [31:0] compute_epoch;
    wire  f_start_ready;
    wire  f_done_valid;
    wire [31:0] f_done_status;
    wire [31:0] f_done_detail;
    wire [31:0] f_done_cmd_id;
    wire [31:0] f_done_epoch;
    wire [63:0] f_done_frame_id;
    wire [11:0] f_done_faces;
    wire [31:0] f_done_result_offset;
    wire [31:0] f_done_result_bytes;
    wire [31:0] f_done_crc;
    wire [63:0] f_done_total_cycles;
    wire [63:0] f_done_model_cycles;
    wire [63:0] f_done_post_cycles;
    wire  f_done_live;
    wire  f_busy;
    wire  f_select_post;
    wire  f_cancel_all;
    wire  f_compute_fault_valid;
    wire [175:0] f_compute_fault_payload;
    wire [7:0] f_debug_stage;
    wire [7:0] f_debug_op;
    wire  f_mem_req_valid;
    wire  f_mem_req_ready;
    wire  f_mem_req_write;
    wire  f_mem_req_verify;
    wire [31:0] f_mem_req_offset;
    wire [31:0] f_mem_req_tag;
    wire [4:0] f_mem_req_beats;
    wire [2:0] f_mem_req_client;
    wire  f_mem_w_valid;
    wire  f_mem_w_ready;
    wire [255:0] f_mem_w_data;
    wire [31:0] f_mem_w_strb;
    wire  f_mem_w_last;
    wire  f_mem_r_valid;
    wire  f_mem_r_ready;
    wire [255:0] f_mem_r_data;
    wire  f_mem_r_last;
    wire  f_mem_rsp_valid;
    wire  f_mem_rsp_ready;
    wire [3:0] f_mem_rsp_status;
    wire [31:0] f_mem_rsp_tag;
    wire  p_cmd_valid;
    wire  p_cmd_ready;
    wire  p_cmd_write;
    wire [31:0] p_cmd_offset;
    wire [31:0] p_cmd_id;
    wire [31:0] p_cmd_epoch;
    wire [4:0] p_cmd_beats;
    wire [2:0] p_cmd_client;
    wire  p_write_valid;
    wire  p_write_ready;
    wire [255:0] p_write_data;
    wire [31:0] p_write_strb;
    wire  p_write_last;
    wire  p_read_valid;
    wire  p_read_ready;
    wire [255:0] p_read_data;
    wire  p_read_last;
    wire  p_done_valid;
    wire  p_done_ready;
    wire [3:0] p_done_status;
    wire [31:0] p_done_id;
    wire [31:0] p_done_epoch;
    wire [2:0] p_done_client;
    wire  p_abort_req;
    wire  p_quarantined;wire [175:0] post_fault_payload;
    wire  s_req_valid;
    wire  s_req_ready;
    wire  s_req_write;
    wire  s_req_verify;
    wire [31:0] s_req_offset;
    wire [31:0] s_req_tag;
    wire [4:0] s_req_beats;
    wire [2:0] s_req_client;
    wire  s_w_valid;
    wire  s_w_ready;
    wire [255:0] s_w_data;
    wire [31:0] s_w_strb;
    wire  s_w_last;
    wire  s_r_valid;
    wire  s_r_ready;
    wire [255:0] s_r_data;
    wire  s_r_last;
    wire  s_rsp_valid;
    wire  s_rsp_ready;
    wire [3:0] s_rsp_status;
    wire [31:0] s_rsp_tag;
    wire  d_cmd_valid;
    wire  d_cmd_ready;
    wire  d_cmd_write;
    wire [31:0] d_cmd_offset;
    wire [31:0] d_cmd_id;
    wire [31:0] d_cmd_epoch;
    wire [4:0] d_cmd_beats;
    wire [2:0] d_cmd_client;
    wire  d_write_valid;
    wire  d_write_ready;
    wire [255:0] d_write_data;
    wire [31:0] d_write_strb;
    wire  d_write_last;
    wire  d_read_valid;
    wire  d_read_ready;
    wire [255:0] d_read_data;
    wire  d_read_last;
    wire  d_mem_done_valid;
    wire  d_mem_done_ready;
    wire [3:0] d_mem_done_status;
    wire [31:0] d_mem_done_id;
    wire [31:0] d_mem_done_epoch;
    wire [2:0] d_mem_done_client;
    wire  d_quarantined;
    wire  d_reset_required;
    wire  d_abort_req;
    wire  d_busy;
    wire  d_fault_valid;
    wire [175:0] d_fault_payload;
    wire [3:0] d_debug_state;
    wire [31:0] d_commands;
    wire [31:0] d_read_beats;
    wire [31:0] d_write_beats;
    wire [31:0] d_verify_offset;
    wire [31:0] d_verify_expected;
    wire [31:0] d_verify_actual;
    wire  cmd_valid;
    wire  cmd_ready;
    wire  cmd_write;
    wire [31:0] cmd_offset;
    wire [31:0] cmd_id;
    wire [31:0] cmd_epoch;
    wire [4:0] cmd_beats;
    wire [2:0] cmd_client;
    wire  write_valid;
    wire  write_ready;
    wire [255:0] write_data;
    wire [31:0] write_strb;
    wire  write_last;
    wire  read_valid;
    wire  read_ready;
    wire [255:0] read_data;
    wire  read_last;
    wire  mem_done_valid;
    wire  mem_done_ready;
    wire [3:0] mem_done_status;
    wire [31:0] mem_done_id;
    wire [31:0] mem_done_epoch;
    wire [2:0] mem_done_client;
    wire  mux_fault_valid;
    wire [175:0] mux_fault_payload;
    wire  mux_quarantined;
    wire  mux_reset_required;
    wire  abort_req;
    wire  mux_busy;
    wire [1:0] mux_debug_owner;
    wire [31:0] mux_debug_global_id;
    wire [31:0] mux_commands;
    wire [31:0] mux_completions;
    wire  hmic_pll_lock;
    wire  compute_fault_valid;
    wire [175:0] compute_fault_payload;
    wire  run_enabled;
    wire  terminal;
    wire [31:0] session_epoch;
    wire [31:0] recovery_count;
    wire [31:0] fault_count;
    wire [31:0] stale_messages;
    wire  fault_event;
    wire  first_fault_valid;
    wire [7:0] first_reason;
    wire [7:0] last_reason;
    wire [31:0] first_epoch;
    wire [31:0] last_epoch;
    wire [1:0] first_detail_mask;
    wire [1:0] last_detail_mask;
    wire [175:0] first_compute_payload;
    wire [175:0] first_ui_payload;
    wire [175:0] last_compute_payload;
    wire [175:0] last_ui_payload;
    wire  bridge_busy;
    wire  owner_write;
    wire  compute_active;
    wire  ui_active;
    wire  session_reset_req;
    wire  ui_session_reset_req;
    wire [3:0] write_fault_code;
    wire [3:0] read_fault_code;
    wire [5:0] tx_level_ui;
    wire [5:0] rx_level_ui;
    wire [31:0] monitor_ui_epoch;
    wire  monitor_ui_armed;
    assign s_req_valid=host_owner?h_req_valid:f_mem_req_valid;
    assign s_req_write=host_owner?h_req_write:f_mem_req_write;
    assign s_req_verify=host_owner?h_req_verify:f_mem_req_verify;
    assign s_req_offset=host_owner?h_req_offset:f_mem_req_offset;
    assign s_req_tag=host_owner?h_req_tag:f_mem_req_tag;
    assign s_req_beats=host_owner?h_req_beats:f_mem_req_beats;
    assign s_req_client=host_owner?h_req_client:f_mem_req_client;
    assign s_w_valid=host_owner?h_w_valid:f_mem_w_valid;
    assign s_w_data=host_owner?h_w_data:f_mem_w_data;
    assign s_w_strb=host_owner?h_w_strb:f_mem_w_strb;
    assign s_w_last=host_owner?h_w_last:f_mem_w_last;
    assign s_r_ready=host_owner?h_r_ready:f_mem_r_ready;
    assign s_rsp_ready=host_owner?h_rsp_ready:f_mem_rsp_ready;
    assign f_mem_req_ready=!host_owner&&s_req_ready;
    assign f_mem_w_ready=!host_owner&&s_w_ready;
    assign f_mem_r_valid=!host_owner&&s_r_valid;
    assign f_mem_rsp_valid=!host_owner&&s_rsp_valid;
    assign f_mem_r_data=s_r_data;
    assign f_mem_r_last=s_r_last;
    assign f_mem_rsp_status=s_rsp_status;
    assign f_mem_rsp_tag=s_rsp_tag;
    assign hmic_pll_lock=pll_lock;
    assign bridge_fault=session_reset_req;
    assign compute_fault_valid=f_compute_fault_valid||d_fault_valid||mux_fault_valid;
    assign compute_fault_payload=f_compute_fault_valid?f_compute_fault_payload:mux_fault_valid?mux_fault_payload:d_fault_payload;
    b03_frame_exec_payload frame(
        .post_fault_payload(post_fault_payload),
        .host_write_valid(host_owner&&s_req_valid&&s_req_ready&&s_req_write),.host_write_offset(s_req_offset),.host_write_beats(s_req_beats),
        .clk(compute_clk),.board_reset_n(board_reset_n),.session_reset_n(session_reset_n),.compute_running(compute_running),.run_ce(run_ce),
        .cancel_request(cancel_request),.bridge_fault(bridge_fault),.epoch(compute_epoch),.addr_cfg_version(addr_cfg_version),.cfg_window_base(cfg_window_base),
        .cfg_window_bytes(cfg_window_bytes),.start_valid(start_valid),.start_ready(f_start_ready),.task_words(task_words),.done_valid(f_done_valid),
        .done_ready(done_ready),.done_status(f_done_status),.done_detail(f_done_detail),.done_cmd_id(f_done_cmd_id),.done_epoch(f_done_epoch),
        .done_frame_id(f_done_frame_id),.done_faces(f_done_faces),.done_result_offset(f_done_result_offset),.done_result_bytes(f_done_result_bytes),.done_crc(f_done_crc),
        .done_total_cycles(f_done_total_cycles),.done_model_cycles(f_done_model_cycles),.done_post_cycles(f_done_post_cycles),.done_live(f_done_live),.busy(f_busy),
        .select_post(f_select_post),.cancel_all(f_cancel_all),.compute_fault_valid(f_compute_fault_valid),.compute_fault_payload(f_compute_fault_payload),.debug_stage(f_debug_stage),
        .debug_op(f_debug_op),.mem_req_valid(f_mem_req_valid),.mem_req_ready(f_mem_req_ready),.mem_req_write(f_mem_req_write),.mem_req_verify(f_mem_req_verify),
        .mem_req_offset(f_mem_req_offset),.mem_req_tag(f_mem_req_tag),.mem_req_beats(f_mem_req_beats),.mem_req_client(f_mem_req_client),.mem_w_valid(f_mem_w_valid),
        .mem_w_ready(f_mem_w_ready),.mem_w_data(f_mem_w_data),.mem_w_strb(f_mem_w_strb),.mem_w_last(f_mem_w_last),.mem_r_valid(f_mem_r_valid),
        .mem_r_ready(f_mem_r_ready),.mem_r_data(f_mem_r_data),.mem_r_last(f_mem_r_last),.mem_rsp_valid(f_mem_rsp_valid),.mem_rsp_ready(f_mem_rsp_ready),
        .mem_rsp_status(f_mem_rsp_status),.mem_rsp_tag(f_mem_rsp_tag),.p_cmd_valid(p_cmd_valid),.p_cmd_ready(p_cmd_ready),.p_cmd_write(p_cmd_write),
        .p_cmd_offset(p_cmd_offset),.p_cmd_id(p_cmd_id),.p_cmd_epoch(p_cmd_epoch),.p_cmd_beats(p_cmd_beats),.p_cmd_client(p_cmd_client),
        .p_write_valid(p_write_valid),.p_write_ready(p_write_ready),.p_write_data(p_write_data),.p_write_strb(p_write_strb),.p_write_last(p_write_last),
        .p_read_valid(p_read_valid),.p_read_ready(p_read_ready),.p_read_data(p_read_data),.p_read_last(p_read_last),.p_done_valid(p_done_valid),
        .p_done_ready(p_done_ready),.p_done_status(p_done_status),.p_done_id(p_done_id),.p_done_epoch(p_done_epoch),.p_done_client(p_done_client),
        .p_abort_req(p_abort_req),.p_quarantined(p_quarantined));

    b03_block_dma dma(
        .clk(compute_clk),.rst_n(session_reset_n),.cancel_request(f_cancel_all),.bridge_fault(bridge_fault),.epoch(compute_epoch),
        .req_valid(s_req_valid),.req_ready(s_req_ready),.req_write(s_req_write),.req_verify(s_req_verify),.req_offset(s_req_offset),
        .req_tag(s_req_tag),.req_beats(s_req_beats),.req_client(s_req_client),.w_valid(s_w_valid),.w_ready(s_w_ready),
        .w_data(s_w_data),.w_strb(s_w_strb),.w_last(s_w_last),.r_valid(s_r_valid),.r_ready(s_r_ready),
        .r_data(s_r_data),.r_last(s_r_last),.rsp_valid(s_rsp_valid),.rsp_ready(s_rsp_ready),.rsp_status(s_rsp_status),
        .rsp_tag(s_rsp_tag),.cmd_valid(d_cmd_valid),.cmd_ready(d_cmd_ready),.cmd_write(d_cmd_write),.cmd_offset(d_cmd_offset),
        .cmd_id(d_cmd_id),.cmd_epoch(d_cmd_epoch),.cmd_beats(d_cmd_beats),.cmd_client(d_cmd_client),.write_valid(d_write_valid),
        .write_ready(d_write_ready),.write_data(d_write_data),.write_strb(d_write_strb),.write_last(d_write_last),.read_valid(d_read_valid),
        .read_ready(d_read_ready),.read_data(d_read_data),.read_last(d_read_last),.mem_done_valid(d_mem_done_valid),.mem_done_ready(d_mem_done_ready),
        .mem_done_status(d_mem_done_status),.mem_done_id(d_mem_done_id),.mem_done_epoch(d_mem_done_epoch),.mem_done_client(d_mem_done_client),.quarantined(d_quarantined),
        .reset_required(d_reset_required),.abort_req(d_abort_req),.busy(d_busy),.fault_valid(d_fault_valid),.fault_ready(1'b1),
        .fault_payload(d_fault_payload),.debug_state(d_debug_state),.commands(d_commands),.read_beats(d_read_beats),.write_beats(d_write_beats),
        .verify_offset(d_verify_offset),.verify_expected(d_verify_expected),.verify_actual(d_verify_actual));

    b03_phase_mem_mux_burst phase_mux(
        .clk(compute_clk),.rst_n(session_reset_n),.select_post(f_select_post),.cancel_request(f_cancel_all),.bridge_fault(bridge_fault),
        .epoch(compute_epoch),.d_cmd_valid(d_cmd_valid),.d_cmd_ready(d_cmd_ready),.d_cmd_write(d_cmd_write),.d_cmd_offset(d_cmd_offset),
        .d_cmd_id(d_cmd_id),.d_cmd_epoch(d_cmd_epoch),.d_cmd_beats(d_cmd_beats),.d_cmd_client(d_cmd_client),.d_abort_req(d_abort_req),
        .d_write_valid(d_write_valid),.d_write_ready(d_write_ready),.d_write_data(d_write_data),.d_write_strb(d_write_strb),.d_write_last(d_write_last),
        .d_read_valid(d_read_valid),.d_read_ready(d_read_ready),.d_read_data(d_read_data),.d_read_last(d_read_last),.d_done_valid(d_mem_done_valid),
        .d_done_ready(d_mem_done_ready),.d_done_status(d_mem_done_status),.d_done_id(d_mem_done_id),.d_done_epoch(d_mem_done_epoch),.d_done_client(d_mem_done_client),
        .p_cmd_valid(p_cmd_valid),.p_cmd_ready(p_cmd_ready),.p_cmd_write(p_cmd_write),.p_cmd_offset(p_cmd_offset),.p_cmd_id(p_cmd_id),
        .p_cmd_epoch(p_cmd_epoch),.p_cmd_beats(p_cmd_beats),.p_cmd_client(p_cmd_client),.p_abort_req(p_abort_req),.p_write_valid(p_write_valid),
        .p_write_ready(p_write_ready),.p_write_data(p_write_data),.p_write_strb(p_write_strb),.p_write_last(p_write_last),.p_read_valid(p_read_valid),
        .p_read_ready(p_read_ready),.p_read_data(p_read_data),.p_read_last(p_read_last),.p_done_valid(p_done_valid),.p_done_ready(p_done_ready),
        .p_done_status(p_done_status),.p_done_id(p_done_id),.p_done_epoch(p_done_epoch),.p_done_client(p_done_client),.cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_offset(cmd_offset),.cmd_id(cmd_id),.cmd_epoch(cmd_epoch),
        .cmd_beats(cmd_beats),.cmd_client(cmd_client),.write_valid(write_valid),.write_ready(write_ready),.write_data(write_data),
        .write_strb(write_strb),.write_last(write_last),.read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),
        .read_last(read_last),.mem_done_valid(mem_done_valid),.mem_done_ready(mem_done_ready),.mem_done_status(mem_done_status),.mem_done_id(mem_done_id),
        .mem_done_epoch(mem_done_epoch),.mem_done_client(mem_done_client),.fault_valid(mux_fault_valid),.fault_ready(1'b1),.fault_payload(mux_fault_payload),
        .quarantined(mux_quarantined),.reset_required(mux_reset_required),.abort_req(abort_req),.busy(mux_busy),.debug_owner(mux_debug_owner),
        .debug_global_id(mux_debug_global_id),.commands(mux_commands),.completions(mux_completions));

    npu_session_mem_bridge_burst #(.HEARTBEAT_HALF_CYCLES(16),.RESET_HOLD_CYCLES(6),.STARTUP_TIMEOUT_CYCLES(5000),.ARM_TIMEOUT_CYCLES(1000),.RUN_TIMEOUT_CYCLES(500000000),.CLOCK_TIMEOUT_CYCLES(256),.SNAPSHOT_TIMEOUT_CYCLES(40),.SNAPSHOT_GRACE_CYCLES(8),.CALIB_STABLE_CYCLES(3),.MAX_AUTOMATIC_RECOVERIES(0),.INITIAL_EPOCH(77)) platform(
        .free_clk(free_clk),.compute_clk(compute_clk),.ui_clk(ui_clk),.board_reset_n(board_reset_n),.compute_pll_lock(1'b1),
        .hmic_pll_lock(hmic_pll_lock),.init_done(init_done),.init_fail(init_fail),.align_error(align_error),.suite_done(1'b1),
        .force_recover(1'b0),.compute_fault_valid(compute_fault_valid),.ui_fault_valid(1'b0),.compute_fault_payload(compute_fault_payload),.ui_fault_payload(176'd0),
        .hmic_reset_n(hmic_reset_n),.session_reset_n(session_reset_n),.run_enabled(run_enabled),.compute_running(compute_running),.terminal(terminal),
        .session_epoch(session_epoch),.compute_epoch(compute_epoch),.recovery_count(recovery_count),.fault_count(fault_count),.stale_messages(stale_messages),
        .fault_event(fault_event),.first_fault_valid(first_fault_valid),.first_reason(first_reason),.last_reason(last_reason),.first_epoch(first_epoch),
        .last_epoch(last_epoch),.first_detail_mask(first_detail_mask),.last_detail_mask(last_detail_mask),.first_compute_payload(first_compute_payload),.first_ui_payload(first_ui_payload),
        .last_compute_payload(last_compute_payload),.last_ui_payload(last_ui_payload),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),
        .cmd_offset(cmd_offset),.cmd_id(cmd_id),.cmd_epoch(cmd_epoch),.cmd_beats(cmd_beats),.cmd_client(cmd_client),
        .write_valid(write_valid),.write_ready(write_ready),.write_data(write_data),.write_strb(write_strb),.write_last(write_last),
        .read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),.read_last(read_last),.abort_req(abort_req),
        .done_valid(mem_done_valid),.done_ready(mem_done_ready),.done_status(mem_done_status),.done_id(mem_done_id),.done_epoch(mem_done_epoch),
        .done_client(mem_done_client),.busy(bridge_busy),.owner_write(owner_write),.compute_active(compute_active),.ui_active(ui_active),
        .session_reset_req(session_reset_req),.ui_session_reset_req(ui_session_reset_req),.write_fault_code(write_fault_code),.read_fault_code(read_fault_code),.awvalid(awvalid),
        .awready(awready),.awaddr(awaddr),.awlen(awlen),.wready(wready),.wid(wid),
        .wlast(wlast),.wdata(wdata),.wstrb(wstrb),.arvalid(arvalid),.arready(arready),
        .araddr(araddr),.arlen(arlen),.rvalid(rvalid),.rdata(rdata),.rid(rid),
        .rlast(rlast),.tx_level_ui(tx_level_ui),.rx_level_ui(rx_level_ui),.monitor_ui_epoch(monitor_ui_epoch),.monitor_ui_armed(monitor_ui_armed));

    reg [7:0] host_bytes[0:1572863],head_expected[0:26367],record_expected[0:67327],task_bytes[0:127];
    string root_path,path,asset_name;
    integer plan_fd,scan,region_count,region,region_bytes,region_offset,cursor,nbeats,i,j,k,waited,out_fd;
    integer frame_index=0,frame_count=0,cases_fd,table_crc_commands=0;reg [31:0] expected_head_crc;
    integer ticks=0,host_commands=0,host_write_beats=0,host_read_beats=0,host_checked_bytes=0;
    integer model_ops=0,preflights=0,global_commands=0,global_dones=0,post_commands=0,model_commands=0;
    integer native_ar=0,native_aw=0,native_r=0,native_w=0,ce0_reads=0,ce0_dones=0;
    reg [31:0] next_tag=1,expected_faces,expected_crc,head_crc;
    reg [31:0] records_bytes,header_crc;
    reg [31:0] last_global_id=0;
    reg [63:0] held_total,held_model,held_post;
    reg model_started=0;
    function [31:0] word_at(input integer byte_offset);
        begin word_at={host_bytes[byte_offset+3],host_bytes[byte_offset+2],host_bytes[byte_offset+1],host_bytes[byte_offset]};end
    endfunction
    function [31:0] crc_byte(input [31:0] old,input [7:0] data);
        reg [31:0] c;integer bit_index;
        begin c=old^{24'd0,data};for(bit_index=0;bit_index<8;bit_index=bit_index+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
    endfunction
    task tick;begin @(posedge compute_clk);#1;end endtask
    task host_transfer(input bit wr,input [31:0] address,input integer beats,input integer buffer_offset,input bit compare);
        integer b,line,got;reg [31:0] this_tag;
        begin
            if(!host_owner||d_busy||mux_busy||bridge_busy)$fatal(1,"host ownership not idle");
            @(negedge compute_clk);this_tag=next_tag;next_tag=next_tag+1;
            h_req_valid=1;h_req_write=wr;h_req_verify=wr;h_req_offset=address;h_req_beats=beats;h_req_tag=this_tag;
            do @(posedge compute_clk);while(!s_req_ready);
            @(negedge compute_clk);h_req_valid=0;host_commands=host_commands+1;
            if(wr)begin
                for(line=0;line<beats;line=line+1)begin
                    h_w_valid=1;h_w_last=line+1==beats;
                    for(b=0;b<32;b=b+1)h_w_data[8*b+:8]=host_bytes[buffer_offset+line*32+b];
                    do @(posedge compute_clk);while(!s_w_ready);
                    @(negedge compute_clk);h_w_valid=0;host_write_beats=host_write_beats+1;
                end
            end else begin
                got=0;h_r_ready=1;
                while(got<beats)begin
                    @(posedge compute_clk);
                    if(s_r_valid)begin
                        if(s_r_last!==(got+1==beats))$fatal(1,"host R LAST");
                        for(b=0;b<32;b=b+1)begin
                            if(compare)begin
                                if(s_r_data[8*b+:8]!==host_bytes[buffer_offset+got*32+b])$fatal(1,"native proxy upload mismatch address=%h actual=%h expected=%h",address+got*32+b,s_r_data[8*b+:8],host_bytes[buffer_offset+got*32+b]);
                                host_checked_bytes=host_checked_bytes+1;
                            end else host_bytes[buffer_offset+got*32+b]=s_r_data[8*b+:8];
                        end
                        got=got+1;host_read_beats=host_read_beats+1;
                    end
                end
                @(negedge compute_clk);h_r_ready=0;
            end
            h_rsp_ready=1;
            do @(posedge compute_clk);while(!s_rsp_valid);
            if(s_rsp_tag!==this_tag||s_rsp_status!==0)$fatal(1,"host response failed status=%0d tag=%h expected=%h verify=%h/%h/%h",s_rsp_status,s_rsp_tag,this_tag,d_verify_offset,d_verify_expected,d_verify_actual);
            @(negedge compute_clk);h_rsp_ready=0;tick;
            if(d_busy||mux_busy||bridge_busy)$fatal(1,"host response left bridge debt");
        end
    endtask
    task host_region(input bit wr,input integer address,input integer bytes,input bit compare);
        integer pos,count;
        begin
            for(pos=0;pos<bytes;pos=pos+count*32)begin
                count=(bytes-pos)/32;if(count>16)count=16;
                if(count>128-((address+pos)>>5)%128)count=128-((address+pos)>>5)%128;
                host_transfer(wr,address+pos,count,pos,compare);
            end
        end
    endtask
    always @(posedge compute_clk)begin
        ticks=ticks+1;
        if(board_reset_n&&compute_running)begin
            if(init_fail||align_error||bridge_fault||d_quarantined||mux_quarantined||p_quarantined||compute_fault_valid||fault_count!=0)
                $fatal(1,"native-proxy complete-frame fault phase=%0d op=%0d DMA=%0d mux=%0d POST=%0d bridge=%0d/%0d CPAY=%h",f_debug_stage,f_debug_op,d_quarantined,mux_quarantined,p_quarantined,write_fault_code,read_fault_code,compute_fault_payload);
            if(cmd_valid&&cmd_ready)begin
                if(cmd_id<=last_global_id||cmd_epoch!=compute_epoch)$fatal(1,"global ID not monotonic or wrong epoch");
                last_global_id=cmd_id;global_commands=global_commands+1;
                if(!host_owner)begin if(f_select_post)post_commands=post_commands+1;else model_commands=model_commands+1;end
                if(!host_owner&&!f_select_post&&cmd_client==5&&!cmd_write&&
                    cmd_offset>=cfg_window_base+task_words[384+:32]&&cmd_offset<cfg_window_base+task_words[384+:32]+1572864)
                    table_crc_commands=table_crc_commands+1;
            end
            if(mem_done_valid&&mem_done_ready)begin global_dones=global_dones+1;if(!run_ce)ce0_dones=ce0_dones+1;end
            if(read_valid&&read_ready&&!run_ce)ce0_reads=ce0_reads+1;
            if(frame.l_start&&frame.l_start_ready)begin
                if(frame.l_preflight)preflights=preflights+1;
                else begin if(preflights!=79)$fatal(1,"MODEL read before all parameter admission");model_started=1;end
            end
            if(frame.l_done&&frame.l_done_ready&&!frame.l_preflight)begin
                if(frame.l_status!=0)$fatal(1,"real MODEL layer failed op=%0d status=%0d detail=%h",frame.l_done_opid,frame.l_status,frame.l_detail);
                model_ops=model_ops+1;$display("PROXY_MODEL_OP PASS op=%0d cycles=%0d",frame.l_done_opid,frame.l_cycles);
            end
        end
    end
    always @(posedge ui_clk)begin
        if(awvalid&&awready)native_aw=native_aw+1;
        if(arvalid&&arready)native_ar=native_ar+1;
        if(wready)native_w=native_w+1;
        if(rvalid)native_r=native_r+1;
    end
    // Compute holds exercise ordinary bridge progress through CE=0 as well.
    always @(negedge compute_clk)run_ce=!model_started||ticks%97>2;
    initial begin
        if(!$value$plusargs("ROOT=%s",root_path))$fatal(1,"ROOT missing");
        plan_fd=$fopen({root_path,"/uploads.txt"},"r");scan=$fscanf(plan_fd,"%d\n",region_count);
        $readmemh({root_path,"/task_0.hex"},task_bytes,0,127);
        for(i=0;i<128;i=i+1)task_words[8*i+:8]=task_bytes[i];
        plan_fd=plan_fd;
        repeat(10)tick;@(negedge compute_clk);grs_n=1;repeat(10)tick;@(negedge compute_clk);board_reset_n=1;
        waited=0;while(!compute_running||!init_done)begin tick;waited=waited+1;if(waited>200000)$fatal(1,"cold calibration timeout");end
        repeat(20)tick;
        if(compute_epoch!=77||!session_reset_n||!hmic_reset_n||!monitor_ui_armed)$fatal(1,"cold session ARM identity");
        $display("PROXY_SESSION_READY epoch=%0d init=%0d",compute_epoch,init_done);
        task_words[544+:32]=compute_epoch;
        for(region=0;region<region_count;region=region+1)begin
            scan=$fscanf(plan_fd,"%h %d %s\n",region_offset,region_bytes,asset_name);
            path={root_path,"/",asset_name};$readmemh(path,host_bytes,0,region_bytes-1);
            host_region(1,cfg_window_base+region_offset,region_bytes,0);
            host_region(0,cfg_window_base+region_offset,region_bytes,1);
            $display("PROXY_UPLOAD_VERIFIED region=%0d offset=%h bytes=%0d",region,region_offset,region_bytes);
        end
        $fclose(plan_fd);
        cases_fd=$fopen({root_path,"/frame_cases.txt"},"r");scan=$fscanf(cases_fd,"%d\n",frame_count);
        for(frame_index=0;frame_index<frame_count;frame_index=frame_index+1)begin
        scan=$fscanf(cases_fd,"%d %h %h\n",expected_faces,expected_crc,expected_head_crc);
        if(scan!=3)$fatal(1,"frame case parse");records_bytes=expected_faces*32;
        path=$sformatf("%s/task_%0d.hex",root_path,frame_index);$readmemh(path,task_bytes,0,127);
        for(i=0;i<128;i=i+1)task_words[8*i+:8]=task_bytes[i];
        task_words[544+:32]=compute_epoch;task_words[448+:32]=100+frame_index;task_words[480+:64]=1000+frame_index;
        path=$sformatf("%s/heads_golden_%0d.hex",root_path,frame_index);$readmemh(path,head_expected,0,26367);
        if(frame_index!=0)begin
            model_started=0;
            path=$sformatf("%s/input_%0d.hex",root_path,frame_index);$readmemh(path,host_bytes,0,307199);
            host_region(1,cfg_window_base+task_words[256+:32],307200,0);
            host_region(0,cfg_window_base+task_words[256+:32],307200,1);
            if(!frame.table_cache_valid||frame.table_cache_commits!=1)$fatal(1,"input update invalidated unchanged POST table");
        end
        model_ops=0;preflights=0;model_commands=0;post_commands=0;table_crc_commands=0;
        @(negedge compute_clk);host_owner=0;start_valid=1;
        do @(posedge compute_clk);while(!f_start_ready);
        @(negedge compute_clk);start_valid=0;
        waited=0;while(!f_done_valid)begin
            tick;waited=waited+1;if(waited>100000000)$fatal(1,"complete frame watchdog stage=%0d op=%0d",f_debug_stage,f_debug_op);
        end
        if(f_done_status!=0||!f_done_live||f_done_faces!=expected_faces||f_done_crc!=expected_crc||model_ops!=79||preflights!=79||
            f_done_cmd_id!=task_words[448+:32]||f_done_epoch!=compute_epoch||f_done_frame_id!=task_words[480+:64]||
            f_done_result_offset!=task_words[320+:32]||f_done_result_bytes!=128+records_bytes||bridge_busy||d_busy||mux_busy)
            $fatal(1,"complete frame metadata failure status=%0d detail=%h faces=%0d crc=%h ops=%0d stage=%0d",f_done_status,f_done_detail,f_done_faces,f_done_crc,model_ops,f_debug_stage);
        held_total=f_done_total_cycles;held_model=f_done_model_cycles;held_post=f_done_post_cycles;
        repeat(32)tick;
        if(f_done_total_cycles!==held_total||f_done_model_cycles!==held_model||f_done_post_cycles!==held_post)$fatal(1,"held frame timing changed");
        @(negedge compute_clk);host_owner=1;
        host_region(0,cfg_window_base+task_words[896+:32],26368,0);
        head_crc=32'hffffffff;
        path=$sformatf("%s/heads_actual_%0d.hex",root_path,frame_index);out_fd=$fopen(path,"w");
        for(i=0;i<26368;i=i+1)begin
            if(host_bytes[i]!==head_expected[i])$fatal(1,"native proxy final nine-head mismatch byte=%0d actual=%h expected=%h",i,host_bytes[i],head_expected[i]);
            head_crc=crc_byte(head_crc,host_bytes[i]);$fdisplay(out_fd,"%02h",host_bytes[i]);
        end
        $fclose(out_fd);
        if((~head_crc)!==expected_head_crc)$fatal(1,"complete HEAD824 CRC");
        path=$sformatf("%s/records_golden_%0d.hex",root_path,frame_index);
        if(records_bytes!=0)$readmemh(path,record_expected,0,records_bytes-1);
        host_region(0,cfg_window_base+task_words[320+:32],128+records_bytes,0);
        path=$sformatf("%s/result_actual_%0d.hex",root_path,frame_index);out_fd=$fopen(path,"w");
        for(i=0;i<128+records_bytes;i=i+1)$fdisplay(out_fd,"%02h",host_bytes[i]);$fclose(out_fd);
        for(i=0;i<records_bytes;i=i+1)if(host_bytes[128+i]!==record_expected[i])$fatal(1,"actual final record mismatch byte=%0d actual=%h expected=%h",i,host_bytes[128+i],record_expected[i]);
        header_crc=32'hffffffff;for(i=0;i<124;i=i+1)header_crc=crc_byte(header_crc,host_bytes[i]);
        if(word_at(0)!==32'h3352504e||word_at(4)!=1||word_at(8)!=128||word_at(12)!=1||word_at(16)!=0||word_at(20)!=0||
            word_at(24)!==f_done_cmd_id||word_at(28)!==f_done_epoch||{word_at(36),word_at(32)}!==f_done_frame_id||
            word_at(40)!=expected_faces||word_at(44)!=records_bytes||word_at(48)!==expected_crc||word_at(60)!=0||word_at(116)!=0||
            word_at(120)!=0||word_at(124)!==~header_crc)$fatal(1,"private header identity/scope/CRC");
        if(global_commands!=global_dones||recovery_count!=0||fault_count!=0||!f_done_live)$fatal(1,"native-proxy frame outstanding debt or recovery");
        if(table_crc_commands!=(frame_index==0?3072:0)||frame.table_cache_commits!=1)$fatal(1,"cold/warm table CRC observation count");
        $display("PASS B03_FULL_FRAME_PROXY frame=%0d ops=%0d preflights=%0d faces=%0d headbytes=26368 recordbytes=%0d framecycles=%0d modelcycles=%0d postcycles=%0d hostcommands=%0d hostW=%0d hostR=%0d checkeduploadbytes=%0d globalcommands=%0d globaldones=%0d modelcommands=%0d postcommands=%0d tableCRCcommands=%0d nativeAR=%0d nativeAW=%0d nativeR=%0d nativeW=%0d CE0reads=%0d CE0dones=%0d headCRC=%h recordsCRC=%h",frame_index,model_ops,preflights,f_done_faces,records_bytes,held_total,held_model,held_post,host_commands,host_write_beats,host_read_beats,host_checked_bytes,global_commands,global_dones,model_commands,post_commands,table_crc_commands,native_ar,native_aw,native_r,native_w,ce0_reads,ce0_dones,~head_crc,expected_crc);
        @(negedge compute_clk);done_ready=1;tick;@(negedge compute_clk);done_ready=0;tick;
        if(f_done_valid)$fatal(1,"frame result ACK did not retire");
        end
        $fclose(cases_fd);
        $finish;
    end
    initial begin #(64'd2000000000);$fatal(1,"native-proxy full-frame simulation timeout stage=%0d op=%0d",f_debug_stage,f_debug_op);end
