// Serial-NMS and qualified-command broadcast candidate. Exact algorithm unchanged.
// Autonomous POST application over one shared A/P/O set and one 32-APM pool.
// Batch metadata precedes each O1 flush. All core channels use common run_ce.
// A completed algorithm does not publish DDR records or prove transport retirement.
module b03_post_frame_payload(
    input wire clk,rst_n,run_ce,cancel,ddr_drained,
    input wire load_begin,input wire [31:0] load_generation,
    input wire head_valid,output wire head_ready,input wire [14:0] head_offset,
    input wire [255:0] head_data,input wire [31:0] head_generation,
    output reg load_error,output wire heads_loaded,
    input wire task_valid,output wire task_ready,
    input wire [31:0] task_cmd_id,task_epoch,task_head_generation,input wire [63:0] task_frame_id,
    input wire [13:0] task_source_w,task_source_h,
    input wire [8:0] task_resized_w,task_resized_h,task_pad_left,task_pad_top,
    input wire [11:0] task_capacity,
    input wire [1:0] raw_mem,raw_req,raw_we,input wire [31:0] raw_epoch,
    input wire [4:0] raw_bank_a,raw_bank_b,input wire [10:0] raw_addr_a,raw_addr_b,
    input wire [31:0] raw_data_a,raw_data_b,input wire [3:0] raw_mask_a,raw_mask_b,
    output wire raw_ready,output reg raw_fault,output wire [31:0] raw_q_a,raw_q_b,output wire [1:0] raw_valid,
    output wire table_req_valid,input wire table_req_ready,output wire [31:0] table_req_offset,table_req_epoch,
    input wire table_rsp_valid,output wire table_rsp_ready,input wire [255:0] table_rsp_data,
    input wire [31:0] table_rsp_offset,table_rsp_epoch,input wire table_rsp_error,
    output wire batch_valid,input wire batch_ready,output wire [11:0] batch_base_record_index,
    output wire [4:0] batch_count,output wire [31:0] batch_cmd_id,batch_epoch,output wire [63:0] batch_frame_id,
    output wire record_valid,input wire record_ready,output wire [255:0] record_data,
    output wire [11:0] record_index,output wire [31:0] record_cmd_id,record_epoch,output wire [63:0] record_frame_id,
    output wire done_valid,input wire done_ready,output reg [4:0] done_status,output reg [7:0] done_detail,
    output reg [11:0] done_face_count,done_nms_count,output reg [31:0] done_crc,done_cmd_id,done_epoch,
    output reg [63:0] done_frame_id,total_cycles,wait_cycles,paused_cycles,
    output reg [31:0] context_epoch,output reg quarantined,
    output wire [7:0] debug_state,output wire [11:0] debug_scan_index,debug_preselected,debug_sorted,
    output reg [31:0] stat_scan_cycles,stat_score_cycles,stat_sort_cycles,stat_decode_cycles,
    output reg [31:0] stat_nms_cycles,stat_roi_cycles,stat_record_cycles,stat_table_beats
);
    localparam IDLE=0,PREFLIGHT=1,GEOM_DIV=2,GEOM_CHECK=3,PRE_BBOX=4,PROB_SCAN=6,PROB_DRAIN=7,
        SCORES=8,SORT_START=10,SORT_WAIT=11,KEY_READ=12,KEY_CAPTURE=13,BBOX_READ=14,BBOX_CAPTURE=15,
        DEC_START=16,DEC_WAIT=17,NMS_START=18,NMS_WAIT=19,ROI_START=20,ROI_WAIT=21,WRITE_RECORD=22,
        CRC_RECORD=23,FLUSH_READ=24,FLUSH_CAPTURE=25,FLUSH_SEND=26,ADVANCE=27,FINAL_FLUSH=28,
        CRC_FINAL=29,CRC_WAIT=30,DRAIN=31,COMPLETE=32,ERROR=33,
        SORT_CHECK=34,DEC_CHECK=35,NMS_CHECK=36,ROI_CHECK=37,CRC_CHECK=38,KEY_CHECK=39,BBOX_CHECK=40,KEY_MEMWAIT=41,BBOX_MEMWAIT=42,FLUSH_MEMWAIT=43,FLUSH_META=44;
    reg [7:0] state,resume_state;
    // next_state is a blocking clock-process temporary, not another FSM.
    reg [7:0] next_state;reg [6:0] phase_mask;reg account_start,frame_active_reg;
    reg [4:0] key_status_reg,bbox_status_reg;
    function [6:0] phase_for(input [7:0] value);
        begin case(value)
            IDLE,COMPLETE:phase_for=0;
            PREFLIGHT,GEOM_DIV,GEOM_CHECK,PRE_BBOX,PROB_SCAN,PROB_DRAIN:phase_for=7'b0000001;
            SCORES:phase_for=7'b0000010;
            SORT_START,SORT_WAIT,SORT_CHECK:phase_for=7'b0000100;
            KEY_READ,KEY_MEMWAIT,KEY_CAPTURE,KEY_CHECK,BBOX_READ,BBOX_MEMWAIT,BBOX_CAPTURE,BBOX_CHECK,DEC_START,DEC_WAIT,DEC_CHECK:phase_for=7'b0001000;
            NMS_START,NMS_WAIT,NMS_CHECK:phase_for=7'b0010000;
            ROI_START,ROI_WAIT,ROI_CHECK:phase_for=7'b0100000;
            default:phase_for=7'b1000000;
        endcase end
    endfunction
    wire clear=!rst_n||cancel;
    wire frame_clear=clear||state==IDLE||state==ERROR||state==COMPLETE;
    wire active=frame_active_reg;
    reg [823:0] coverage;reg [9:0] loaded_count;reg [31:0] loaded_generation;
    reg [31:0] cmd,accepted_epoch;reg [63:0] frame;
    reg [13:0] source_w,source_h;reg [8:0] resized_w,resized_h,pad_left,pad_top;
    reg [11:0] capacity,faces;
    wire memory_busy,pool_busy;
    // Load/raw retirement is independent of frame_clear: IDLE is the load phase.
    reg head_buffer_valid,head_buffer_new;reg [9:0] head_buffer_row;
    reg [255:0] head_buffer_data;
    reg raw_front_valid;reg [1:0] raw_front_mem,raw_front_req,raw_front_we;
    reg [4:0] raw_front_a,raw_front_b;
    reg [31:0] raw_front_sel_a,raw_front_sel_b,raw_front_data_a,raw_front_data_b;
    reg [10:0] raw_front_addr_a,raw_front_addr_b;
    reg [3:0] raw_front_mask_a,raw_front_mask_b;
    reg [1:0] raw_pending,raw_saved_mem;reg [4:0] raw_saved_a,raw_saved_b;
    reg memory_fault_reg,wait_event;reg [1:0] quiet_count;
    reg fault_a_reg,fault_p_reg,fault_o_reg;
    reg [1:0] write_retire_a,write_retire_p,write_retire_o;
    reg quiet_a_reg,quiet_p_reg,quiet_o_reg,pool_quiet_reg,frontend_armed;
    reg load_init_pending,head_invalidate_pending,head_write_pending,head_write_new;
    reg [31:0] load_init_generation;
    reg raw_command_dispatch;
    wire raw_response_busy;
    wire [1:0] raw_result_mem;wire [4:0] raw_result_bank_a,raw_result_bank_b;
    wire [31:0] raw_result_epoch;
    reg [63:0] raw_selected_a,raw_selected_b;
    wire raw_output_busy=raw_response_busy;
    wire local_fault_busy=fault_a_reg||fault_p_reg||fault_o_reg||memory_fault_reg;
    wire write_busy=(|write_retire_a)||(|write_retire_p)||(|write_retire_o);
    wire frontend_quiet=!head_buffer_valid&&!head_write_pending&&!load_init_pending&&!head_invalidate_pending&&!raw_front_valid&&!raw_command_dispatch&&!(|raw_pending)&&!raw_output_busy&&!local_fault_busy&&!write_busy&&quiet_a_reg&&quiet_p_reg&&quiet_o_reg&&pool_quiet_reg;
    wire load_accept=state==IDLE&&frontend_armed&&!(|raw_req)&&!quarantined&&run_ce&&!clear&&load_begin;

    reg [4:0] precheck_status;
    reg [4:0] sort_status_reg,dec_status_reg,nms_status_reg,roi_status_reg,crc_status_reg;
    reg sort_buffer_reg,nms_keep_reg,roi_empty_reg,roi_capacity_bad;
    reg [31:0] crc_value_reg;
    reg [255:0] roi_record_reg;
    assign heads_loaded=loaded_count==824&&loaded_generation!=0&&!load_init_pending&&!head_invalidate_pending;
    assign head_ready=state==IDLE&&!load_begin&&!load_init_pending&&!head_invalidate_pending&&!task_valid&&!(|raw_req)&&!raw_front_valid&&!raw_command_dispatch&&!(|raw_pending)&&!raw_output_busy&&!local_fault_busy&&!quarantined&&run_ce&&!clear;
    assign task_ready=state==IDLE&&frontend_armed&&!load_begin&&!head_valid&&!(|raw_req)&&!quarantined&&run_ce&&!clear;
    assign raw_ready=state==IDLE&&frontend_armed&&!load_begin&&!head_valid&&!task_valid&&!quarantined&&run_ce&&!clear;
    wire raw_ok=raw_ready&&raw_epoch==context_epoch&&raw_mem<3&&
        (raw_mem==2||(raw_bank_a<16&&raw_bank_b<16));
    wire invalidate_accept=raw_ok&&raw_front_valid==0&&raw_mem==2&&
        ((raw_we[0]&&raw_req[0]&&raw_bank_a<16)||(raw_we[1]&&raw_req[1]&&raw_bank_b<16));
    wire head_ok=head_ready&&head_valid&&loaded_generation!=0&&head_generation==loaded_generation&&
        head_offset[4:0]==0&&head_offset<=15'd26336;
    assign done_valid=state==COMPLETE&&!clear;
    assign debug_state=state;
    reg [9:0] bbox_issued,bbox_received;reg bbox_pending,bbox_request;
    reg [11:0] scan_issued,scan_received,pre_count,key_count,key_index;
    reg scan_pending,scan_request;reg [11:0] scan_tag,scan_request_tag;reg [3:0] scan_bank,scan_request_bank;
    assign debug_scan_index=scan_issued;assign debug_preselected=pre_count;assign debug_sorted=key_count;
    reg [11:0] pre_read;reg pre_pending,pre_request,next_valid;reg [3:0] pre_bank;
    reg [31:0] next_product,next_id,root_expected_id;
    reg [4:0] next_status;reg next_eligible;
    reg p_front_valid,p_front_bad;reg [15:0] p_front_cls,p_front_obj;reg [31:0] p_front_id;
    reg p_ret_valid,p_ret_ge,p_ret_last;reg [4:0] p_ret_status;
    reg [31:0] p_ret_product,p_ret_id;
    reg root_ret_valid;reg [4:0] root_ret_status;reg [63:0] root_ret_key;
    reg sorted_buffer;reg [31:0] cid,score_bits;reg [1:0] scale;reg [10:0] position;reg [63:0] raw_codes;
    reg [255:0] current_q,current_record;reg [63:0] current_rectangle;reg [20:0] current_area;
    reg [4:0] buffered_count,flush_index;reg [11:0] flush_base,record_index_reg;
    reg [255:0] record_register;
    assign batch_valid=state==FLUSH_META&&!clear;
    assign batch_base_record_index=flush_base;assign batch_count=buffered_count;
    assign batch_cmd_id=cmd;assign batch_epoch=accepted_epoch;assign batch_frame_id=frame;
    assign record_valid=state==FLUSH_SEND&&!clear;
    assign record_data=record_register;assign record_index=record_index_reg;
    assign record_cmd_id=cmd;assign record_epoch=accepted_epoch;assign record_frame_id=frame;
    reg tail_pending,first_record;reg [31:0] tail_word;reg [3:0] crc_step;
    reg table_identity_bad;
    function [13:0] cls_element(input [11:0] id);
        begin cls_element=id<1600 ? id:id<2000 ? 14'd1664+(id-1600):14'd2176+(id-2000);end
    endfunction
    function [13:0] obj_element(input [11:0] id);
        begin obj_element=id<1600 ? 14'd2304+id:id<2000 ? 14'd3968+(id-1600):14'd4480+(id-2000);end
    endfunction
    function [13:0] bbox_element(input [31:0] id);
        begin bbox_element=id<1600 ? 14'd4608+4*id:id<2000 ? 14'd11008+4*(id-1600):14'd12672+4*(id-2000);end
    endfunction
    wire [13:0] cls_e=cls_element(scan_issued),obj_e=obj_element(scan_issued),bbox_e=bbox_element(cid);
    wire [13:0] pre_word=14'd8448+{pre_read,1'b0};
    wire [13:0] key_word=(sorted_buffer ? 14'd4224:14'd0)+{key_index,1'b0};
    wire [3:0] key_bank=key_word[3:0];
    wire [9:0] check_row=bbox_issued<500 ? 10'd288+bbox_issued:10'd792+(bbox_issued-500);

    reg [15:0] ar_a,aw_a,ar_b,aw_b,pr_a,pw_a,pr_b,pw_b;
    reg [31:0] or_a,ow_a,or_b,ow_b;
    reg [175:0] aa_a,aa_b,pa_a,pa_b;reg [351:0] oa_a,oa_b;
    reg [511:0] ad_a,ad_b,pd_a,pd_b,od_a,od_b;
    reg [63:0] am_a,am_b,pm_a,pm_b,om_a,om_b;
    wire [511:0] aq_a,aq_b,pq_a,pq_b,oq_a,oq_b;
    wire [15:0] av_a,av_b,pv_a,pv_b;wire [31:0] ov_a,ov_b;
    wire absy,pbsy,obsy,ac,pc,oc,ae,pe,oe;
    assign memory_busy=absy||pbsy||obsy;

    // spec155: declare identity outputs before their consumer instances.
    wire rg_A_rst_n;
    wire rg_P_rst_n;
    wire rg_O_rst_n;
    wire rg_raw_response_clear;
    wire rg_probability_clear;
    wire rg_root_clear;
    wire rg_sorter_clear;
    wire rg_decoder_clear;
    wire rg_nms_clear;
    wire rg_roi_clear;
    wire rg_pool_clear;
    wire rg_crc_clear;
    b03_bank_array_payload #(.BANKS(16),.WIDTH(32),.DEPTH(2048)) A(.clk(clk),.rst_n(rg_A_rst_n),.run_ce(run_ce),
        .req_a(ar_a),.we_a(aw_a),.req_b(ar_b),.we_b(aw_b),.addr_a(aa_a),.addr_b(aa_b),
        .data_a(ad_a),.data_b(ad_b),.mask_a(am_a),.mask_b(am_b),.q_a(aq_a),.q_b(aq_b),
        .valid_a(av_a),.valid_b(av_b),.busy(absy),.conflict(ac),.range_error(ae));
    b03_bank_array_payload #(.BANKS(16),.WIDTH(32),.DEPTH(1024)) P(.clk(clk),.rst_n(rg_P_rst_n),.run_ce(run_ce),
        .req_a(pr_a),.we_a(pw_a),.req_b(pr_b),.we_b(pw_b),.addr_a(pa_a),.addr_b(pa_b),
        .data_a(pd_a),.data_b(pd_b),.mask_a(pm_a),.mask_b(pm_b),.q_a(pq_a),.q_b(pq_b),
        .valid_a(pv_a),.valid_b(pv_b),.busy(pbsy),.conflict(pc),.range_error(pe));
    b03_bank_array_payload #(.BANKS(32),.WIDTH(16),.DEPTH(1024)) O(.clk(clk),.rst_n(rg_O_rst_n),.run_ce(run_ce),
        .req_a(or_a),.we_a(ow_a),.req_b(or_b),.we_b(ow_b),.addr_a(oa_a),.addr_b(oa_b),
        .data_a(od_a),.data_b(od_b),.mask_a(om_a),.mask_b(om_b),.q_a(oq_a),.q_b(oq_b),
        .valid_a(ov_a),.valid_b(ov_b),.busy(obsy),.conflict(oc),.range_error(oe));
    // Isolated candidate: constant bank slices, one-hot mask, balanced OR tree.
    wire [31:0] raw_mux_a_0_0 = ({32{raw_selected_a[0]}} & aq_a[0+:32]) | ({32{raw_selected_a[16]}} & pq_a[0+:32]) | ({32{raw_selected_a[32]}} & {16'b0,oq_a[0+:16]});
    wire [31:0] raw_mux_a_0_1 = ({32{raw_selected_a[1]}} & aq_a[32+:32]) | ({32{raw_selected_a[17]}} & pq_a[32+:32]) | ({32{raw_selected_a[33]}} & {16'b0,oq_a[16+:16]});
    wire [31:0] raw_mux_a_0_2 = ({32{raw_selected_a[2]}} & aq_a[64+:32]) | ({32{raw_selected_a[18]}} & pq_a[64+:32]) | ({32{raw_selected_a[34]}} & {16'b0,oq_a[32+:16]});
    wire [31:0] raw_mux_a_0_3 = ({32{raw_selected_a[3]}} & aq_a[96+:32]) | ({32{raw_selected_a[19]}} & pq_a[96+:32]) | ({32{raw_selected_a[35]}} & {16'b0,oq_a[48+:16]});
    wire [31:0] raw_mux_a_0_4 = ({32{raw_selected_a[4]}} & aq_a[128+:32]) | ({32{raw_selected_a[20]}} & pq_a[128+:32]) | ({32{raw_selected_a[36]}} & {16'b0,oq_a[64+:16]});
    wire [31:0] raw_mux_a_0_5 = ({32{raw_selected_a[5]}} & aq_a[160+:32]) | ({32{raw_selected_a[21]}} & pq_a[160+:32]) | ({32{raw_selected_a[37]}} & {16'b0,oq_a[80+:16]});
    wire [31:0] raw_mux_a_0_6 = ({32{raw_selected_a[6]}} & aq_a[192+:32]) | ({32{raw_selected_a[22]}} & pq_a[192+:32]) | ({32{raw_selected_a[38]}} & {16'b0,oq_a[96+:16]});
    wire [31:0] raw_mux_a_0_7 = ({32{raw_selected_a[7]}} & aq_a[224+:32]) | ({32{raw_selected_a[23]}} & pq_a[224+:32]) | ({32{raw_selected_a[39]}} & {16'b0,oq_a[112+:16]});
    wire [31:0] raw_mux_a_0_8 = ({32{raw_selected_a[8]}} & aq_a[256+:32]) | ({32{raw_selected_a[24]}} & pq_a[256+:32]) | ({32{raw_selected_a[40]}} & {16'b0,oq_a[128+:16]});
    wire [31:0] raw_mux_a_0_9 = ({32{raw_selected_a[9]}} & aq_a[288+:32]) | ({32{raw_selected_a[25]}} & pq_a[288+:32]) | ({32{raw_selected_a[41]}} & {16'b0,oq_a[144+:16]});
    wire [31:0] raw_mux_a_0_10 = ({32{raw_selected_a[10]}} & aq_a[320+:32]) | ({32{raw_selected_a[26]}} & pq_a[320+:32]) | ({32{raw_selected_a[42]}} & {16'b0,oq_a[160+:16]});
    wire [31:0] raw_mux_a_0_11 = ({32{raw_selected_a[11]}} & aq_a[352+:32]) | ({32{raw_selected_a[27]}} & pq_a[352+:32]) | ({32{raw_selected_a[43]}} & {16'b0,oq_a[176+:16]});
    wire [31:0] raw_mux_a_0_12 = ({32{raw_selected_a[12]}} & aq_a[384+:32]) | ({32{raw_selected_a[28]}} & pq_a[384+:32]) | ({32{raw_selected_a[44]}} & {16'b0,oq_a[192+:16]});
    wire [31:0] raw_mux_a_0_13 = ({32{raw_selected_a[13]}} & aq_a[416+:32]) | ({32{raw_selected_a[29]}} & pq_a[416+:32]) | ({32{raw_selected_a[45]}} & {16'b0,oq_a[208+:16]});
    wire [31:0] raw_mux_a_0_14 = ({32{raw_selected_a[14]}} & aq_a[448+:32]) | ({32{raw_selected_a[30]}} & pq_a[448+:32]) | ({32{raw_selected_a[46]}} & {16'b0,oq_a[224+:16]});
    wire [31:0] raw_mux_a_0_15 = ({32{raw_selected_a[15]}} & aq_a[480+:32]) | ({32{raw_selected_a[31]}} & pq_a[480+:32]) | ({32{raw_selected_a[47]}} & {16'b0,oq_a[240+:16]});
    wire [31:0] raw_mux_a_0_16 = ({32{raw_selected_a[48]}} & {16'b0,oq_a[256+:16]});
    wire [31:0] raw_mux_a_0_17 = ({32{raw_selected_a[49]}} & {16'b0,oq_a[272+:16]});
    wire [31:0] raw_mux_a_0_18 = ({32{raw_selected_a[50]}} & {16'b0,oq_a[288+:16]});
    wire [31:0] raw_mux_a_0_19 = ({32{raw_selected_a[51]}} & {16'b0,oq_a[304+:16]});
    wire [31:0] raw_mux_a_0_20 = ({32{raw_selected_a[52]}} & {16'b0,oq_a[320+:16]});
    wire [31:0] raw_mux_a_0_21 = ({32{raw_selected_a[53]}} & {16'b0,oq_a[336+:16]});
    wire [31:0] raw_mux_a_0_22 = ({32{raw_selected_a[54]}} & {16'b0,oq_a[352+:16]});
    wire [31:0] raw_mux_a_0_23 = ({32{raw_selected_a[55]}} & {16'b0,oq_a[368+:16]});
    wire [31:0] raw_mux_a_0_24 = ({32{raw_selected_a[56]}} & {16'b0,oq_a[384+:16]});
    wire [31:0] raw_mux_a_0_25 = ({32{raw_selected_a[57]}} & {16'b0,oq_a[400+:16]});
    wire [31:0] raw_mux_a_0_26 = ({32{raw_selected_a[58]}} & {16'b0,oq_a[416+:16]});
    wire [31:0] raw_mux_a_0_27 = ({32{raw_selected_a[59]}} & {16'b0,oq_a[432+:16]});
    wire [31:0] raw_mux_a_0_28 = ({32{raw_selected_a[60]}} & {16'b0,oq_a[448+:16]});
    wire [31:0] raw_mux_a_0_29 = ({32{raw_selected_a[61]}} & {16'b0,oq_a[464+:16]});
    wire [31:0] raw_mux_a_0_30 = ({32{raw_selected_a[62]}} & {16'b0,oq_a[480+:16]});
    wire [31:0] raw_mux_a_0_31 = ({32{raw_selected_a[63]}} & {16'b0,oq_a[496+:16]});
    wire [31:0] raw_mux_a_1_0 = raw_mux_a_0_0 | raw_mux_a_0_1;
    wire [31:0] raw_mux_a_1_1 = raw_mux_a_0_2 | raw_mux_a_0_3;
    wire [31:0] raw_mux_a_1_2 = raw_mux_a_0_4 | raw_mux_a_0_5;
    wire [31:0] raw_mux_a_1_3 = raw_mux_a_0_6 | raw_mux_a_0_7;
    wire [31:0] raw_mux_a_1_4 = raw_mux_a_0_8 | raw_mux_a_0_9;
    wire [31:0] raw_mux_a_1_5 = raw_mux_a_0_10 | raw_mux_a_0_11;
    wire [31:0] raw_mux_a_1_6 = raw_mux_a_0_12 | raw_mux_a_0_13;
    wire [31:0] raw_mux_a_1_7 = raw_mux_a_0_14 | raw_mux_a_0_15;
    wire [31:0] raw_mux_a_1_8 = raw_mux_a_0_16 | raw_mux_a_0_17;
    wire [31:0] raw_mux_a_1_9 = raw_mux_a_0_18 | raw_mux_a_0_19;
    wire [31:0] raw_mux_a_1_10 = raw_mux_a_0_20 | raw_mux_a_0_21;
    wire [31:0] raw_mux_a_1_11 = raw_mux_a_0_22 | raw_mux_a_0_23;
    wire [31:0] raw_mux_a_1_12 = raw_mux_a_0_24 | raw_mux_a_0_25;
    wire [31:0] raw_mux_a_1_13 = raw_mux_a_0_26 | raw_mux_a_0_27;
    wire [31:0] raw_mux_a_1_14 = raw_mux_a_0_28 | raw_mux_a_0_29;
    wire [31:0] raw_mux_a_1_15 = raw_mux_a_0_30 | raw_mux_a_0_31;
    wire [31:0] raw_mux_a_2_0 = raw_mux_a_1_0 | raw_mux_a_1_1;
    wire [31:0] raw_mux_a_2_1 = raw_mux_a_1_2 | raw_mux_a_1_3;
    wire [31:0] raw_mux_a_2_2 = raw_mux_a_1_4 | raw_mux_a_1_5;
    wire [31:0] raw_mux_a_2_3 = raw_mux_a_1_6 | raw_mux_a_1_7;
    wire [31:0] raw_mux_a_2_4 = raw_mux_a_1_8 | raw_mux_a_1_9;
    wire [31:0] raw_mux_a_2_5 = raw_mux_a_1_10 | raw_mux_a_1_11;
    wire [31:0] raw_mux_a_2_6 = raw_mux_a_1_12 | raw_mux_a_1_13;
    wire [31:0] raw_mux_a_2_7 = raw_mux_a_1_14 | raw_mux_a_1_15;
    wire [31:0] raw_mux_a_3_0 = raw_mux_a_2_0 | raw_mux_a_2_1;
    wire [31:0] raw_mux_a_3_1 = raw_mux_a_2_2 | raw_mux_a_2_3;
    wire [31:0] raw_mux_a_3_2 = raw_mux_a_2_4 | raw_mux_a_2_5;
    wire [31:0] raw_mux_a_3_3 = raw_mux_a_2_6 | raw_mux_a_2_7;
    wire [31:0] raw_mux_a_4_0 = raw_mux_a_3_0 | raw_mux_a_3_1;
    wire [31:0] raw_mux_a_4_1 = raw_mux_a_3_2 | raw_mux_a_3_3;
    wire [31:0] raw_mux_a_5_0 = raw_mux_a_4_0 | raw_mux_a_4_1;
    // RAW output is driven only by the bank-local registered response client.
    wire [31:0] raw_mux_b_0_0 = ({32{raw_selected_b[0]}} & aq_b[0+:32]) | ({32{raw_selected_b[16]}} & pq_b[0+:32]) | ({32{raw_selected_b[32]}} & {16'b0,oq_b[0+:16]});
    wire [31:0] raw_mux_b_0_1 = ({32{raw_selected_b[1]}} & aq_b[32+:32]) | ({32{raw_selected_b[17]}} & pq_b[32+:32]) | ({32{raw_selected_b[33]}} & {16'b0,oq_b[16+:16]});
    wire [31:0] raw_mux_b_0_2 = ({32{raw_selected_b[2]}} & aq_b[64+:32]) | ({32{raw_selected_b[18]}} & pq_b[64+:32]) | ({32{raw_selected_b[34]}} & {16'b0,oq_b[32+:16]});
    wire [31:0] raw_mux_b_0_3 = ({32{raw_selected_b[3]}} & aq_b[96+:32]) | ({32{raw_selected_b[19]}} & pq_b[96+:32]) | ({32{raw_selected_b[35]}} & {16'b0,oq_b[48+:16]});
    wire [31:0] raw_mux_b_0_4 = ({32{raw_selected_b[4]}} & aq_b[128+:32]) | ({32{raw_selected_b[20]}} & pq_b[128+:32]) | ({32{raw_selected_b[36]}} & {16'b0,oq_b[64+:16]});
    wire [31:0] raw_mux_b_0_5 = ({32{raw_selected_b[5]}} & aq_b[160+:32]) | ({32{raw_selected_b[21]}} & pq_b[160+:32]) | ({32{raw_selected_b[37]}} & {16'b0,oq_b[80+:16]});
    wire [31:0] raw_mux_b_0_6 = ({32{raw_selected_b[6]}} & aq_b[192+:32]) | ({32{raw_selected_b[22]}} & pq_b[192+:32]) | ({32{raw_selected_b[38]}} & {16'b0,oq_b[96+:16]});
    wire [31:0] raw_mux_b_0_7 = ({32{raw_selected_b[7]}} & aq_b[224+:32]) | ({32{raw_selected_b[23]}} & pq_b[224+:32]) | ({32{raw_selected_b[39]}} & {16'b0,oq_b[112+:16]});
    wire [31:0] raw_mux_b_0_8 = ({32{raw_selected_b[8]}} & aq_b[256+:32]) | ({32{raw_selected_b[24]}} & pq_b[256+:32]) | ({32{raw_selected_b[40]}} & {16'b0,oq_b[128+:16]});
    wire [31:0] raw_mux_b_0_9 = ({32{raw_selected_b[9]}} & aq_b[288+:32]) | ({32{raw_selected_b[25]}} & pq_b[288+:32]) | ({32{raw_selected_b[41]}} & {16'b0,oq_b[144+:16]});
    wire [31:0] raw_mux_b_0_10 = ({32{raw_selected_b[10]}} & aq_b[320+:32]) | ({32{raw_selected_b[26]}} & pq_b[320+:32]) | ({32{raw_selected_b[42]}} & {16'b0,oq_b[160+:16]});
    wire [31:0] raw_mux_b_0_11 = ({32{raw_selected_b[11]}} & aq_b[352+:32]) | ({32{raw_selected_b[27]}} & pq_b[352+:32]) | ({32{raw_selected_b[43]}} & {16'b0,oq_b[176+:16]});
    wire [31:0] raw_mux_b_0_12 = ({32{raw_selected_b[12]}} & aq_b[384+:32]) | ({32{raw_selected_b[28]}} & pq_b[384+:32]) | ({32{raw_selected_b[44]}} & {16'b0,oq_b[192+:16]});
    wire [31:0] raw_mux_b_0_13 = ({32{raw_selected_b[13]}} & aq_b[416+:32]) | ({32{raw_selected_b[29]}} & pq_b[416+:32]) | ({32{raw_selected_b[45]}} & {16'b0,oq_b[208+:16]});
    wire [31:0] raw_mux_b_0_14 = ({32{raw_selected_b[14]}} & aq_b[448+:32]) | ({32{raw_selected_b[30]}} & pq_b[448+:32]) | ({32{raw_selected_b[46]}} & {16'b0,oq_b[224+:16]});
    wire [31:0] raw_mux_b_0_15 = ({32{raw_selected_b[15]}} & aq_b[480+:32]) | ({32{raw_selected_b[31]}} & pq_b[480+:32]) | ({32{raw_selected_b[47]}} & {16'b0,oq_b[240+:16]});
    wire [31:0] raw_mux_b_0_16 = ({32{raw_selected_b[48]}} & {16'b0,oq_b[256+:16]});
    wire [31:0] raw_mux_b_0_17 = ({32{raw_selected_b[49]}} & {16'b0,oq_b[272+:16]});
    wire [31:0] raw_mux_b_0_18 = ({32{raw_selected_b[50]}} & {16'b0,oq_b[288+:16]});
    wire [31:0] raw_mux_b_0_19 = ({32{raw_selected_b[51]}} & {16'b0,oq_b[304+:16]});
    wire [31:0] raw_mux_b_0_20 = ({32{raw_selected_b[52]}} & {16'b0,oq_b[320+:16]});
    wire [31:0] raw_mux_b_0_21 = ({32{raw_selected_b[53]}} & {16'b0,oq_b[336+:16]});
    wire [31:0] raw_mux_b_0_22 = ({32{raw_selected_b[54]}} & {16'b0,oq_b[352+:16]});
    wire [31:0] raw_mux_b_0_23 = ({32{raw_selected_b[55]}} & {16'b0,oq_b[368+:16]});
    wire [31:0] raw_mux_b_0_24 = ({32{raw_selected_b[56]}} & {16'b0,oq_b[384+:16]});
    wire [31:0] raw_mux_b_0_25 = ({32{raw_selected_b[57]}} & {16'b0,oq_b[400+:16]});
    wire [31:0] raw_mux_b_0_26 = ({32{raw_selected_b[58]}} & {16'b0,oq_b[416+:16]});
    wire [31:0] raw_mux_b_0_27 = ({32{raw_selected_b[59]}} & {16'b0,oq_b[432+:16]});
    wire [31:0] raw_mux_b_0_28 = ({32{raw_selected_b[60]}} & {16'b0,oq_b[448+:16]});
    wire [31:0] raw_mux_b_0_29 = ({32{raw_selected_b[61]}} & {16'b0,oq_b[464+:16]});
    wire [31:0] raw_mux_b_0_30 = ({32{raw_selected_b[62]}} & {16'b0,oq_b[480+:16]});
    wire [31:0] raw_mux_b_0_31 = ({32{raw_selected_b[63]}} & {16'b0,oq_b[496+:16]});
    wire [31:0] raw_mux_b_1_0 = raw_mux_b_0_0 | raw_mux_b_0_1;
    wire [31:0] raw_mux_b_1_1 = raw_mux_b_0_2 | raw_mux_b_0_3;
    wire [31:0] raw_mux_b_1_2 = raw_mux_b_0_4 | raw_mux_b_0_5;
    wire [31:0] raw_mux_b_1_3 = raw_mux_b_0_6 | raw_mux_b_0_7;
    wire [31:0] raw_mux_b_1_4 = raw_mux_b_0_8 | raw_mux_b_0_9;
    wire [31:0] raw_mux_b_1_5 = raw_mux_b_0_10 | raw_mux_b_0_11;
    wire [31:0] raw_mux_b_1_6 = raw_mux_b_0_12 | raw_mux_b_0_13;
    wire [31:0] raw_mux_b_1_7 = raw_mux_b_0_14 | raw_mux_b_0_15;
    wire [31:0] raw_mux_b_1_8 = raw_mux_b_0_16 | raw_mux_b_0_17;
    wire [31:0] raw_mux_b_1_9 = raw_mux_b_0_18 | raw_mux_b_0_19;
    wire [31:0] raw_mux_b_1_10 = raw_mux_b_0_20 | raw_mux_b_0_21;
    wire [31:0] raw_mux_b_1_11 = raw_mux_b_0_22 | raw_mux_b_0_23;
    wire [31:0] raw_mux_b_1_12 = raw_mux_b_0_24 | raw_mux_b_0_25;
    wire [31:0] raw_mux_b_1_13 = raw_mux_b_0_26 | raw_mux_b_0_27;
    wire [31:0] raw_mux_b_1_14 = raw_mux_b_0_28 | raw_mux_b_0_29;
    wire [31:0] raw_mux_b_1_15 = raw_mux_b_0_30 | raw_mux_b_0_31;
    wire [31:0] raw_mux_b_2_0 = raw_mux_b_1_0 | raw_mux_b_1_1;
    wire [31:0] raw_mux_b_2_1 = raw_mux_b_1_2 | raw_mux_b_1_3;
    wire [31:0] raw_mux_b_2_2 = raw_mux_b_1_4 | raw_mux_b_1_5;
    wire [31:0] raw_mux_b_2_3 = raw_mux_b_1_6 | raw_mux_b_1_7;
    wire [31:0] raw_mux_b_2_4 = raw_mux_b_1_8 | raw_mux_b_1_9;
    wire [31:0] raw_mux_b_2_5 = raw_mux_b_1_10 | raw_mux_b_1_11;
    wire [31:0] raw_mux_b_2_6 = raw_mux_b_1_12 | raw_mux_b_1_13;
    wire [31:0] raw_mux_b_2_7 = raw_mux_b_1_14 | raw_mux_b_1_15;
    wire [31:0] raw_mux_b_3_0 = raw_mux_b_2_0 | raw_mux_b_2_1;
    wire [31:0] raw_mux_b_3_1 = raw_mux_b_2_2 | raw_mux_b_2_3;
    wire [31:0] raw_mux_b_3_2 = raw_mux_b_2_4 | raw_mux_b_2_5;
    wire [31:0] raw_mux_b_3_3 = raw_mux_b_2_6 | raw_mux_b_2_7;
    wire [31:0] raw_mux_b_4_0 = raw_mux_b_3_0 | raw_mux_b_3_1;
    wire [31:0] raw_mux_b_4_1 = raw_mux_b_3_2 | raw_mux_b_3_3;
    wire [31:0] raw_mux_b_5_0 = raw_mux_b_4_0 | raw_mux_b_4_1;
    // Per-bank native valid qualifies capture in raw_response.
    wire [1:0] raw_memory_valid;
    assign raw_memory_valid[0]=raw_pending[0]&&(raw_saved_mem==0 ? av_a[raw_saved_a]:raw_saved_mem==1 ? pv_a[raw_saved_a]:ov_a[raw_saved_a]);
    assign raw_memory_valid[1]=raw_pending[1]&&(raw_saved_mem==0 ? av_b[raw_saved_b]:raw_saved_mem==1 ? pv_b[raw_saved_b]:ov_b[raw_saved_b]);
    wire raw_dispatch=raw_command_dispatch;
    b03_raw_bank_response_pipe raw_response(.clk(clk),.clear(rg_raw_response_clear),.run_ce(run_ce),
        .read_pending(raw_pending),.selected_a(raw_selected_a),.selected_b(raw_selected_b),
        .aq_a(aq_a),.aq_b(aq_b),.pq_a(pq_a),.pq_b(pq_b),.oq_a(oq_a),.oq_b(oq_b),
        .av_a(av_a),.av_b(av_b),.pv_a(pv_a),.pv_b(pv_b),.ov_a(ov_a),.ov_b(ov_b),
        .saved_mem(raw_saved_mem),.saved_bank_a(raw_saved_a),.saved_bank_b(raw_saved_b),.saved_epoch(context_epoch),
        .q_a(raw_q_a),.q_b(raw_q_b),.out_valid(raw_valid),.out_mem(raw_result_mem),
        .out_bank_a(raw_result_bank_a),.out_bank_b(raw_result_bank_b),.out_epoch(raw_result_epoch),.busy(raw_response_busy));
    always @(posedge clk)begin
        if(clear)begin
            raw_command_dispatch<=0;raw_selected_a<=0;raw_selected_b<=0;account_start<=0;
        end else begin
            account_start<=run_ce&&task_valid&&task_ready;
            if(run_ce)begin
                raw_command_dispatch<=raw_front_valid;
                if(raw_dispatch)begin
                    case(raw_front_mem)
                        0:begin raw_selected_a<={48'b0,raw_front_sel_a[15:0]};raw_selected_b<={48'b0,raw_front_sel_b[15:0]};end
                        1:begin raw_selected_a<={32'b0,raw_front_sel_a[15:0],16'b0};raw_selected_b<={32'b0,raw_front_sel_b[15:0],16'b0};end
                        2:begin raw_selected_a<={raw_front_sel_a,32'b0};raw_selected_b<={raw_front_sel_b,32'b0};end
                        default:begin raw_selected_a<=0;raw_selected_b<=0;end
                    endcase
                end
            end
        end
    end

    wire p_ready,p_advance,p_mul_valid,p_out_valid,p_error,p_busy;wire [24:0] p_x;wire [17:0] p_y;
    wire [31:0] p_product,p_id,p_epoch;
    wire scanning=state==PROB_SCAN||state==PROB_DRAIN;
    wire [1535:0] products;wire [31:0] product_valid;wire [63:0] product_modes;wire [1023:0] product_epochs;
    b03_probability_pipe probability(.clk(clk),.clear(rg_probability_clear),.run_ce(run_ce),.in_valid(p_front_valid&&scanning&&!p_front_bad),.in_ready(p_ready),
         .cls(p_front_cls),.obj(p_front_obj),.candidate_id(p_front_id),.epoch(accepted_epoch),
        .advance(p_advance),.mul_valid(p_mul_valid),.mul_x(p_x),.mul_y(p_y),
        .mul_product(products[47:0]),.mul_rsp_valid(scanning&&product_valid[0]),.mul_mode(product_modes[1:0]),.mul_epoch(product_epochs[31:0]),
        .out_valid(p_out_valid),.out_ready(1'b1),.out_error(p_error),.product(p_product),.out_id(p_id),.out_epoch(p_epoch),.busy(p_busy));
    wire root_ready,root_valid,root_error,root_busy;wire [31:0] root_score,root_id,root_epoch,root_cycles;wire [63:0] root_key;
    wire root_eligible=next_eligible&&next_status==0;
    wire root_take=state==SCORES&&next_valid&&root_eligible&&root_ready;
    wire skip_next=state==SCORES&&next_valid&&!root_eligible;
    wire prefetch=state==SCORES&&pre_read<pre_count&&!pre_request&&!pre_pending&&(!next_valid||root_take||skip_next);
    b03_score_root root(.clk(clk),.clear(rg_root_clear),.run_ce(run_ce),.in_valid(state==SCORES&&next_valid&&root_eligible),.in_ready(root_ready),
        .product(next_product),.candidate_id(next_id),.epoch(accepted_epoch),.out_valid(root_valid),.out_ready(state==SCORES),.out_error(root_error),
        .score(root_score),.out_id(root_id),.out_epoch(root_epoch),.cycles(root_cycles),.sort_key(root_key),.busy(root_busy),.debug_state(),.debug_digit());
    wire [15:0] sr_a,sw_a,sr_b,sw_b;wire [175:0] sa_a,sa_b;wire [511:0] sd_a,sd_b;
    wire sort_busy,sort_done,sort_error,sort_buffer;wire [31:0] sort_epoch,sort_cycles;
    b03_key_sort_mem2 sorter(.clk(clk),.clear(rg_sorter_clear),.run_ce(run_ce),.start(state==SORT_START),.count(key_count),.epoch(accepted_epoch),
        .busy(sort_busy),.done(sort_done),.done_ready(state==SORT_WAIT),.error(sort_error),.result_buffer(sort_buffer),
        .result_epoch(sort_epoch),.cycles(sort_cycles),.req_a(sr_a),.we_a(sw_a),.req_b(sr_b),.we_b(sw_b),
        .addr_a(sa_a),.addr_b(sa_b),.data_a(sd_a),.data_b(sd_b),.q_a(pq_a),.q_b(pq_b),.valid_a(pv_a),.valid_b(pv_b),.debug_state());

    wire dec_ready,dec_valid,dec_error,dec_busy,dec_mul_valid;wire [24:0] dec_x;wire [17:0] dec_y;
    wire [127:0] dec_box;wire [255:0] dec_q;wire [63:0] dec_rectangle;wire [20:0] dec_area;
    wire [31:0] dec_id,dec_epoch,dec_cycles,dec_wait,dec_math_cycles,dec_mul_epoch;wire [2:0] dec_beats;wire [3:0] dec_state;
    wire decoding=state==DEC_START||state==DEC_WAIT;
    b03_decode_lookup_roundstage decoder(.clk(clk),.clear(rg_decoder_clear),.run_ce(run_ce),.in_valid(state==DEC_START&&!pool_busy),.in_ready(dec_ready),
        .stride_index(scale),.index(position),.raw_codes(raw_codes),.candidate_id(cid),.epoch(accepted_epoch),
        .req_valid(table_req_valid),.req_ready(table_req_ready),.req_offset(table_req_offset),.req_epoch(table_req_epoch),
        .rsp_valid(table_rsp_valid),.rsp_ready(table_rsp_ready),.rsp_data(table_rsp_data),.rsp_offset(table_rsp_offset),.rsp_epoch(table_rsp_epoch),.rsp_error(table_rsp_error),
        .out_valid(dec_valid),.out_ready(state==DEC_WAIT),.out_error(dec_error),.box_bits(dec_box),.box_q40(dec_q),.rectangle(dec_rectangle),
        .current_area(dec_area),.out_id(dec_id),.out_epoch(dec_epoch),.local_cycles(dec_cycles),.wait_cycles(dec_wait),.lookup_beats(dec_beats),.arithmetic_cycles(dec_math_cycles),
        .mul_valid(dec_mul_valid),.mul_x(dec_x),.mul_y(dec_y),.mul_epoch(dec_mul_epoch),.mul_product(products[47:0]),
        .mul_rsp_valid(decoding&&product_valid[0]),.mul_mode(product_modes[1:0]),.mul_rsp_epoch(product_epochs[31:0]),.busy(dec_busy),.debug_state(dec_state),.math_state());
    wire [15:0] nr_a,nw_a,nr_b,nw_b;wire [175:0] na_a,na_b;wire [511:0] nd_a,nd_b;
    wire [31:0] n_mul_valid,n_mul_epoch;wire [799:0] n_x;wire [575:0] n_y;
    wire n_ready,n_valid,n_keep,n_error,n_busy;wire [31:0] n_id,n_epoch,n_cycles,n_groups;wire [11:0] n_kept;
    wire nms_phase=state==NMS_START||state==NMS_WAIT;
    b03_nms1_faultreg nms(.clk(clk),.clear(rg_nms_clear),.run_ce(run_ce),.frame_start(state==PREFLIGHT),
        .in_valid(state==NMS_START&&!pool_busy),.in_ready(n_ready),.rectangle(current_rectangle),.current_area(current_area),.candidate_id(cid),.epoch(accepted_epoch),
        .busy(n_busy),.out_valid(n_valid),.out_ready(state==NMS_WAIT),.out_keep(n_keep),.out_error(n_error),.out_id(n_id),.out_epoch(n_epoch),.kept_count(n_kept),.cycles(n_cycles),.groups_issued(n_groups),
        .req_a(nr_a),.we_a(nw_a),.req_b(nr_b),.we_b(nw_b),.addr_a(na_a),.addr_b(na_b),.data_a(nd_a),.data_b(nd_b),
        .q_a(aq_a),.q_b(aq_b),.valid_a(av_a),.valid_b(av_b),.mul_valid(n_mul_valid),.mul_x(n_x),.mul_y(n_y),.mul_epoch(n_mul_epoch),
        .products(products),.product_valid(nms_phase ? product_valid:32'b0),.product_modes(product_modes),.product_epochs(product_epochs),.debug_state(),.debug_mask(),.debug_hits());
    wire roi_ready,roi_valid,roi_empty,roi_error,roi_busy,roi_mul_valid;wire [299:0] roi_xs;wire [215:0] roi_ys;
    wire [31:0] roi_epoch,roi_mul_epoch;wire [13:0] rx,ry,rw,rh;
    wire roi_phase=state==ROI_START||state==ROI_WAIT;
    b03_roi4_loan_registered roi(.clk(clk),.clear(rg_roi_clear),.run_ce(run_ce),.in_valid(state==ROI_START&&!pool_busy),.in_ready(roi_ready),
        .x(current_q[63:0]),.y(current_q[127:64]),.w(current_q[191:128]),.h(current_q[255:192]),
        .source_w(source_w),.source_h(source_h),.resized_w(resized_w),.resized_h(resized_h),.pad_left(pad_left),.pad_top(pad_top),.epoch(accepted_epoch),
        .mul_req_valid(roi_mul_valid),.mul_ready(1'b1),.mul_req_epoch(roi_mul_epoch),.mul_x(roi_xs),.mul_y(roi_ys),
        .mul_rsp_valid(roi_phase&&(&product_valid[11:0])),.mul_products(products[575:0]),.mul_epoch(product_epochs[31:0]),.mul_mode(product_modes[1:0]),
        .out_valid(roi_valid),.out_ready(state==ROI_WAIT),.roi_x(rx),.roi_y(ry),.roi_w(rw),.roi_h(rh),.out_empty(roi_empty),.out_error(roi_error),.out_epoch(roi_epoch),
        .busy(roi_busy),.debug_state(),.debug_bit(),.debug_remainder0());
    reg [799:0] pool_x;reg [575:0] pool_y;reg [31:0] pool_valid,pool_epoch;reg [1:0] pool_mode;
    always @* begin
        pool_x=0;pool_y=0;pool_valid=0;pool_epoch=accepted_epoch;pool_mode=0;
        if(scanning)begin pool_x[24:0]=p_x;pool_y[17:0]=p_y;pool_valid[0]=p_mul_valid;pool_mode=2;end
        else if(decoding)begin pool_x[24:0]=dec_x;pool_y[17:0]=dec_y;pool_valid[0]=dec_mul_valid;pool_epoch=dec_mul_epoch;pool_mode=1;end
        else if(nms_phase)begin pool_x=n_x;pool_y=n_y;pool_valid=n_mul_valid;pool_epoch=n_mul_epoch;pool_mode=1;end
        else if(roi_phase)begin pool_x[299:0]=roi_xs;pool_y[215:0]=roi_ys;pool_valid[11:0]={12{roi_mul_valid}};pool_epoch=roi_mul_epoch;pool_mode=3;end
    end
    b03_mul_pool32_probe pool(.clk(clk),.clear(rg_pool_clear),.run_ce(scanning ? p_advance:run_ce),.in_valid(pool_valid),.x(pool_x),.y(pool_y),.mode(pool_mode),.epoch(pool_epoch),
        .products(products),.out_valid(product_valid),.out_modes(product_modes),.out_epochs(product_epochs),.busy(pool_busy));
    wire crc_ready,crc_valid,crc_error,crc_busy;wire [31:0] crc_value,crc_id,crc_epoch;
    wire crc_input=state==CRC_FINAL||(state==CRC_RECORD&&(tail_pending||crc_step<7));
    wire [2:0] crc_word_index=tail_pending ? crc_step[2:0]-3'd1:crc_step[2:0];
    wire [31:0] crc_data=state==CRC_FINAL||(tail_pending&&crc_step==0) ? tail_word:current_record[32*crc_word_index+:32];
    b03_crc32_word_pipe crc(.clk(clk),.clear(rg_crc_clear),.run_ce(run_ce),.in_valid(crc_input),.in_ready(crc_ready),.data(crc_data),
        .byte_count(state==CRC_FINAL&&!tail_pending ? 3'd0:3'd4),.first(state==CRC_FINAL ? !tail_pending:(first_record&&crc_step==0)),.last(state==CRC_FINAL),
        .stream_id(cmd),.epoch(accepted_epoch),.out_valid(crc_valid),.out_ready(state==CRC_WAIT),.out_error(crc_error),.crc(crc_value),.out_id(crc_id),.out_epoch(crc_epoch),.busy(crc_busy));

    integer b,k;
    wire [13:0] pre_store_word=14'd8448+{pre_count,1'b0};
    wire [13:0] score_store_word={key_count,1'b0};
    wire [3:0] pre_store_bank=pre_store_word[3:0],score_store_bank=score_store_word[3:0];
    wire [3:0] pre_second_bank=pre_store_bank+4'd1,score_second_bank=score_store_bank+4'd1;
    wire [3:0] prefetch_second_bank=pre_word[3:0]+4'd1,key_second_bank=key_bank+4'd1;
    always @* begin
        ar_a=0;aw_a=0;ar_b=0;aw_b=0;aa_a=0;aa_b=0;ad_a=0;ad_b=0;am_a=64'hffffffffffffffff;am_b=64'hffffffffffffffff;
        pr_a=0;pw_a=0;pr_b=0;pw_b=0;pa_a=0;pa_b=0;pd_a=0;pd_b=0;pm_a=64'hffffffffffffffff;pm_b=64'hffffffffffffffff;
        or_a=0;ow_a=0;or_b=0;ow_b=0;oa_a=0;oa_b=0;od_a=0;od_b=0;om_a=64'hffffffffffffffff;om_b=64'hffffffffffffffff;
        for(b=0;b<32;b=b+1)begin
            if(state==IDLE&&raw_front_valid)begin
                if(raw_front_mem==0&&b<16)begin
                    ar_a[b]=raw_front_sel_a[b]&&raw_front_req[0];aw_a[b]=raw_front_sel_a[b]&&raw_front_we[0];aa_a[11*b+:11]=raw_front_addr_a;ad_a[32*b+:32]=raw_front_data_a;am_a[4*b+:4]=raw_front_mask_a;
                    ar_b[b]=raw_front_sel_b[b]&&raw_front_req[1];aw_b[b]=raw_front_sel_b[b]&&raw_front_we[1];aa_b[11*b+:11]=raw_front_addr_b;ad_b[32*b+:32]=raw_front_data_b;am_b[4*b+:4]=raw_front_mask_b;
                end else if(raw_front_mem==1&&b<16)begin
                    pr_a[b]=raw_front_sel_a[b]&&raw_front_req[0];pw_a[b]=raw_front_sel_a[b]&&raw_front_we[0];pa_a[11*b+:11]=raw_front_addr_a;pd_a[32*b+:32]=raw_front_data_a;pm_a[4*b+:4]=raw_front_mask_a;
                    pr_b[b]=raw_front_sel_b[b]&&raw_front_req[1];pw_b[b]=raw_front_sel_b[b]&&raw_front_we[1];pa_b[11*b+:11]=raw_front_addr_b;pd_b[32*b+:32]=raw_front_data_b;pm_b[4*b+:4]=raw_front_mask_b;
                end else if(raw_front_mem==2)begin
                    or_a[b]=raw_front_sel_a[b]&&raw_front_req[0];ow_a[b]=raw_front_sel_a[b]&&raw_front_we[0];oa_a[11*b+:11]=raw_front_addr_a;od_a[16*b+:16]=raw_front_data_a[15:0];om_a[2*b+:2]=raw_front_mask_a[1:0];
                    or_b[b]=raw_front_sel_b[b]&&raw_front_req[1];ow_b[b]=raw_front_sel_b[b]&&raw_front_we[1];oa_b[11*b+:11]=raw_front_addr_b;od_b[16*b+:16]=raw_front_data_b[15:0];om_b[2*b+:2]=raw_front_mask_b[1:0];
                end
            end
            if(b<16)begin
                if(head_buffer_valid)begin or_a[b]=1;ow_a[b]=1;oa_a[11*b+:11]={1'b0,head_buffer_row};od_a[16*b+:16]=head_buffer_data[16*b+:16];end
                if(state==PRE_BBOX&&bbox_issued<525)begin or_a[b]=1;oa_a[11*b+:11]={1'b0,check_row};end
                if(state==PROB_SCAN&&scan_issued<2100)begin
                    or_a[b]=cls_e[3:0]==b;oa_a[11*b+:11]={1'b0,cls_e[13:4]};
                    or_b[b]=obj_e[3:0]==b;oa_b[11*b+:11]={1'b0,obj_e[13:4]};
                end
                if(scanning&&p_ret_valid&&p_ret_status==0&&p_ret_ge)begin
                    pr_a[b]=(pre_store_bank==b||pre_second_bank==b);pw_a[b]=pr_a[b];pa_a[11*b+:11]={1'b0,pre_store_word[13:4]};pd_a[32*b+:32]=b[0] ? p_ret_product:p_ret_id;
                end
                if(prefetch)begin
                    pr_b[b]=(pre_word[3:0]==b||prefetch_second_bank==b);pa_b[11*b+:11]={1'b0,pre_word[13:4]};
                end
                if(state==SCORES&&root_ret_valid&&root_ret_status==0)begin
                    pr_a[b]=(score_store_bank==b||score_second_bank==b);pw_a[b]=pr_a[b];pa_a[11*b+:11]={1'b0,score_store_word[13:4]};pd_a[32*b+:32]=b[0] ? root_ret_key[63:32]:root_ret_key[31:0];
                end
            end
        end
        if(sort_busy)begin pr_a=sr_a;pr_b=sr_b;pw_a=sw_a;pw_b=sw_b;pa_a=sa_a;pa_b=sa_b;pd_a=sd_a;pd_b=sd_b;end
        for(b=0;b<16;b=b+1)begin
            if(state==KEY_READ)begin pr_a[b]=(key_bank==b||key_second_bank==b);pa_a[11*b+:11]={1'b0,key_word[13:4]};end
            if(state==BBOX_READ)begin or_a[b]=b[3:2]==bbox_e[3:2];oa_a[11*b+:11]={1'b0,bbox_e[13:4]};end
        end
        if(nms_phase)begin ar_a=nr_a;aw_a=nw_a;ar_b=nr_b;aw_b=nw_b;aa_a=na_a;aa_b=na_b;ad_a=nd_a;ad_b=nd_b;end
        if(state==WRITE_RECORD)for(b=0;b<16;b=b+1)begin
            k=b+16;or_a[k]=1;ow_a[k]=1;oa_a[11*k+:11]={7'b0,buffered_count[3:0]};od_a[16*k+:16]=current_record[16*b+:16];
        end
        if(state==FLUSH_READ)for(b=16;b<32;b=b+1)begin or_a[b]=1;oa_a[11*b+:11]={7'b0,flush_index[3:0]};end
    end

    reg [21:0] geom_rem_w,geom_rem_h;reg [13:0] geom_den;reg [8:0] geom_qw,geom_qh;reg [3:0] geom_bit;
    reg [21:0] geom_trial;
    wire [9:0] expected_w0={1'b0,geom_qw}+(({1'b0,geom_rem_w}<<1)>geom_den||((({1'b0,geom_rem_w}<<1)==geom_den)&&geom_qw[0]));
    wire [9:0] expected_h0={1'b0,geom_qh}+(({1'b0,geom_rem_h}<<1)>geom_den||((({1'b0,geom_rem_h}<<1)==geom_den)&&geom_qh[0]));
    wire [8:0] expected_w=expected_w0==0 ? 9'd1:expected_w0[8:0],expected_h=expected_h0==0 ? 9'd1:expected_h0[8:0];
    wire [63:0] pre_pair=pq_b[64*pre_bank[3:1]+:64];
    wire [63:0] bbox_pack=oq_a[64*bbox_e[3:2]+:64];
    reg bad_bbox,valid_bbox;reg [63:0] fetched_key;integer j;
    always @* begin
        bad_bbox=0;valid_bbox=&ov_a[15:0];for(j=0;j<16;j=j+1)if(oq_a[16*j+:16]==16'h8000)bad_bbox=1;
        fetched_key=pq_a[64*key_bank[3:1]+:64];
    end
    task fail(input [4:0] status,input [7:0] detail);
        begin done_status<=status;done_detail<=detail;done_nms_count<=n_kept;quiet_count<=0;next_state=ERROR;end
    endtask
    // These registers have explicit ownership and retire before task acceptance.
    always @(posedge clk)begin
        if(clear)begin
            head_buffer_valid<=0;head_buffer_new<=0;head_buffer_row<=0;head_buffer_data<=0;
            raw_front_valid<=0;raw_front_mem<=0;raw_front_req<=0;raw_front_we<=0;
            raw_front_a<=0;raw_front_b<=0;raw_front_sel_a<=0;raw_front_sel_b<=0;
            raw_front_addr_a<=0;raw_front_addr_b<=0;raw_front_data_a<=0;raw_front_data_b<=0;raw_front_mask_a<=0;raw_front_mask_b<=0;
            memory_fault_reg<=0;fault_a_reg<=0;fault_p_reg<=0;fault_o_reg<=0;
            write_retire_a<=0;write_retire_p<=0;write_retire_o<=0;wait_event<=0;
            quiet_a_reg<=1;quiet_p_reg<=1;quiet_o_reg<=1;pool_quiet_reg<=1;frontend_armed<=1;
            load_init_pending<=0;head_invalidate_pending<=0;load_init_generation<=0;head_write_pending<=0;head_write_new<=0;
        end else begin
            // Capture an event on its qualified physical edge; retire even on CE0.
            wait_event<=active&&run_ce&&((table_req_valid&&!table_req_ready)||(table_rsp_ready&&!table_rsp_valid)||(record_valid&&!record_ready)||(batch_valid&&!batch_ready));
            if(run_ce)begin
                fault_a_reg<=ac||ae;fault_p_reg<=pc||pe;fault_o_reg<=oc||oe;
                memory_fault_reg<=fault_a_reg||fault_p_reg||fault_o_reg;
                write_retire_a<={write_retire_a[0],(|(ar_a&aw_a))||(|(ar_b&aw_b))};
                write_retire_p<={write_retire_p[0],(|(pr_a&pw_a))||(|(pr_b&pw_b))};
                write_retire_o<={write_retire_o[0],(|(or_a&ow_a))||(|(or_b&ow_b))};
                quiet_a_reg<=!absy;quiet_p_reg<=!pbsy;quiet_o_reg<=!obsy;pool_quiet_reg<=!pool_busy;
                if(state==COMPLETE&&done_ready)frontend_armed<=1;
                else if(load_accept||(raw_ok&&(|raw_req))||(task_valid&&task_ready)||head_ok)frontend_armed<=0;
                else if(state==IDLE&&frontend_quiet)frontend_armed<=1;
                load_init_pending<=load_accept;head_invalidate_pending<=invalidate_accept;
                if(load_accept)load_init_generation<=load_generation;
                head_write_pending<=head_buffer_valid;head_write_new<=head_buffer_new;
                head_buffer_valid<=head_ok;
                if(head_ok)begin head_buffer_row<=head_offset[14:5];head_buffer_data<=head_data;head_buffer_new<=!coverage[head_offset[14:5]]&&!(head_buffer_valid&&head_buffer_row==head_offset[14:5]);end
                raw_front_valid<=raw_ok&&(|raw_req);
                if(raw_ok&&(|raw_req))begin
                    raw_front_mem<=raw_mem;raw_front_req<=raw_req;raw_front_we<=raw_we;
                    raw_front_a<=raw_bank_a;raw_front_b<=raw_bank_b;
                    raw_front_sel_a<=32'b1<<raw_bank_a;raw_front_sel_b<=32'b1<<raw_bank_b;
                    raw_front_addr_a<=raw_addr_a;raw_front_addr_b<=raw_addr_b;
                    raw_front_data_a<=raw_data_a;raw_front_data_b<=raw_data_b;raw_front_mask_a<=raw_mask_a;raw_front_mask_b<=raw_mask_b;
                end
            end
        end
    end
    // Arithmetic return checks terminate at registers, never at the main FSM.
    always @(posedge clk)begin
        if(frame_clear)begin
            p_front_valid<=0;p_front_bad<=0;p_front_cls<=0;p_front_obj<=0;p_front_id<=0;
            p_ret_valid<=0;p_ret_ge<=0;p_ret_last<=0;p_ret_status<=0;p_ret_product<=0;p_ret_id<=0;
            root_ret_valid<=0;root_ret_status<=0;root_ret_key<=0;
            sort_status_reg<=0;sort_buffer_reg<=0;dec_status_reg<=0;key_status_reg<=0;bbox_status_reg<=0;nms_status_reg<=0;nms_keep_reg<=0;
            roi_status_reg<=0;roi_empty_reg<=0;roi_capacity_bad<=0;roi_record_reg<=0;crc_status_reg<=0;crc_value_reg<=0;
        end else if(run_ce)begin
            p_front_valid<=scan_pending&&scanning;
            if(scan_pending&&scanning)begin
                p_front_cls<=oq_a[16*scan_bank+:16];p_front_obj<=oq_b[16*scan_bank+:16];p_front_id<={20'b0,scan_tag};
                p_front_bad<=!ov_a[scan_bank]||!ov_b[scan_bank];
            end
            p_ret_valid<=scanning&&p_out_valid;
            if(scanning&&p_out_valid)begin
                p_ret_status<=p_error ? 5'd20:(p_epoch!=accepted_epoch||p_id!={20'b0,scan_received}) ? 5'd13:5'd0;
                p_ret_product<=p_product;p_ret_id<=p_id;p_ret_ge<=p_product>=32'h5c28f5c0;p_ret_last<=scan_received==2099;
            end
            root_ret_valid<=state==SCORES&&root_valid;
            if(state==SCORES&&root_valid)begin
                root_ret_status<=root_error ? 5'd20:(root_epoch!=accepted_epoch||root_id!=root_expected_id) ? 5'd13:5'd0;
                root_ret_key<=root_key;
            end
            if(state==KEY_CAPTURE)key_status_reg<=(!pv_a[key_bank]||!pv_a[key_bank+1]) ? 5'd22:fetched_key[31:0]>=2100 ? 5'd19:5'd0;
            if(state==BBOX_CAPTURE)bbox_status_reg<=(!ov_a[bbox_e[3:0]]||!ov_a[bbox_e[3:0]+1]||!ov_a[bbox_e[3:0]+2]||!ov_a[bbox_e[3:0]+3]) ? 5'd22:5'd0;
            if(state==SORT_WAIT&&sort_done)begin sort_status_reg<=sort_error ? 5'd22:sort_epoch!=accepted_epoch ? 5'd13:5'd0;sort_buffer_reg<=sort_buffer;end
            if(state==DEC_WAIT&&dec_valid)dec_status_reg<=(dec_epoch!=accepted_epoch||dec_id!=cid||table_identity_bad) ? 5'd13:dec_error ? 5'd20:5'd0;
            if(state==NMS_WAIT&&n_valid)begin nms_status_reg<=(n_epoch!=accepted_epoch||n_id!=cid) ? 5'd13:n_error ? 5'd20:5'd0;nms_keep_reg<=n_keep;end
            if(state==ROI_WAIT&&roi_valid)begin
                roi_status_reg<=roi_epoch!=accepted_epoch ? 5'd13:roi_error ? 5'd20:5'd0;
                roi_empty_reg<=roi_empty;roi_capacity_bad<=faces>=capacity;
                roi_record_reg<={32'b0,(scale==0 ? 32'd8:scale==1 ? 32'd16:32'd32),cid,score_bits,{18'b0,rh},{18'b0,rw},{18'b0,ry},{18'b0,rx}};
            end
            if(state==CRC_WAIT&&crc_valid)begin crc_status_reg<=(crc_id!=cmd||crc_epoch!=accepted_epoch) ? 5'd13:crc_error ? 5'd20:5'd0;crc_value_reg<=crc_value;end
        end
    end
    always @(posedge clk)begin
        next_state=state;
        if(!rst_n)begin
            state<=IDLE;phase_mask<=0;frame_active_reg<=0;context_epoch<=1;quarantined<=0;load_error<=0;raw_fault<=0;coverage<=0;loaded_count<=0;loaded_generation<=0;
            done_status<=0;done_detail<=0;done_face_count<=0;done_nms_count<=0;done_crc<=0;done_cmd_id<=0;done_epoch<=0;done_frame_id<=0;
            total_cycles<=0;wait_cycles<=0;paused_cycles<=0;stat_scan_cycles<=0;stat_score_cycles<=0;stat_sort_cycles<=0;stat_decode_cycles<=0;stat_nms_cycles<=0;stat_roi_cycles<=0;stat_record_cycles<=0;stat_table_beats<=0;
            cmd<=0;accepted_epoch<=0;frame<=0;source_w<=0;source_h<=0;resized_w<=0;resized_h<=0;pad_left<=0;pad_top<=0;capacity<=0;faces<=0;
            bbox_issued<=0;bbox_received<=0;bbox_pending<=0;bbox_request<=0;scan_issued<=0;scan_received<=0;scan_pending<=0;scan_request<=0;scan_request_tag<=0;scan_request_bank<=0;scan_tag<=0;scan_bank<=0;pre_count<=0;key_count<=0;key_index<=0;
            pre_read<=0;pre_pending<=0;pre_request<=0;pre_bank<=0;next_valid<=0;next_product<=0;next_id<=0;root_expected_id<=0;sorted_buffer<=0;
            cid<=0;score_bits<=0;scale<=0;position<=0;raw_codes<=0;current_q<=0;current_rectangle<=0;current_area<=0;current_record<=0;
            buffered_count<=0;flush_index<=0;flush_base<=0;record_index_reg<=0;record_register<=0;resume_state<=0;
            tail_pending<=0;tail_word<=0;first_record<=0;crc_step<=0;table_identity_bad<=0;
            geom_rem_w<=0;geom_rem_h<=0;geom_den<=0;geom_qw<=0;geom_qh<=0;geom_bit<=0;geom_trial<=0;quiet_count<=0;precheck_status<=0;next_status<=0;next_eligible<=0;
            raw_pending<=0;raw_saved_mem<=0;raw_saved_a<=0;raw_saved_b<=0;
        end else if(cancel)begin
            state<=IDLE;phase_mask<=0;frame_active_reg<=0;coverage<=0;loaded_count<=0;loaded_generation<=0;raw_pending<=0;load_error<=0;raw_fault<=0;
            if(context_epoch==32'hffffffff)quarantined<=1;else context_epoch<=context_epoch+1'b1;
            bbox_pending<=0;bbox_request<=0;scan_pending<=0;scan_request<=0;pre_pending<=0;pre_request<=0;next_valid<=0;done_face_count<=0;done_crc<=0;
        end else begin
            if(active)begin total_cycles<=total_cycles+1'b1;if(!run_ce)paused_cycles<=paused_cycles+1'b1;end
            if(wait_event)wait_cycles<=wait_cycles+1'b1;
            if(run_ce)begin
                load_error<=0;raw_fault<=0;
                raw_pending<=raw_dispatch ? (raw_front_req&~raw_front_we):2'b0;
                if(raw_dispatch)begin raw_saved_mem<=raw_front_mem;raw_saved_a<=raw_front_a;raw_saved_b<=raw_front_b;end
                if(state==IDLE&&memory_fault_reg)raw_fault<=1;
                if(|raw_req)begin
                    if(!raw_ok)raw_fault<=1;
                end
                if(load_begin)begin
                    if(load_accept)begin if(load_generation==0)load_error<=1;end
                    else load_error<=1;
                end
                if(head_valid)begin
                    if(!head_ok)load_error<=1;
                end
                if(load_init_pending)begin coverage<=0;loaded_count<=0;loaded_generation<=load_init_generation;end
                else if(head_invalidate_pending)begin coverage<=0;loaded_count<=0;loaded_generation<=0;end
                else begin
                    if(head_buffer_valid)coverage[head_buffer_row]<=1;
                    if(head_write_pending&&head_write_new)loaded_count<=loaded_count+1'b1;
                end
                if(scanning&&p_out_valid)scan_received<=scan_received+1'b1;
                bbox_pending<=bbox_request;bbox_request<=state==PRE_BBOX&&bbox_issued<525;
                scan_pending<=scan_request;scan_request<=state==PROB_SCAN&&scan_issued<2100;
                if(scan_request)begin scan_tag<=scan_request_tag;scan_bank<=scan_request_bank;end
                if(state==PROB_SCAN&&scan_issued<2100)begin scan_request_tag<=scan_issued;scan_request_bank<=cls_e[3:0];scan_issued<=scan_issued+1'b1;end
                pre_pending<=pre_request;pre_request<=prefetch;
                if(prefetch)begin pre_bank<=pre_word[3:0];pre_read<=pre_read+1'b1;end
                if(root_take||skip_next)next_valid<=0;
                if(root_take)root_expected_id<=next_id;
                if(pre_pending)begin
                    next_valid<=1;next_id<=pre_pair[31:0];next_product<=pre_pair[63:32];
                    next_status<=(!pv_b[pre_bank]||!pv_b[pre_bank+1]) ? 5'd22:pre_pair[31:0]>=2100 ? 5'd19:5'd0;
                    next_eligible<=pre_count==1||pre_pair[63:32]>=32'h5c28f6c0;
                end
                if(active)begin
                    if(table_req_valid&&table_req_ready)stat_table_beats<=stat_table_beats+1'b1;
                    if(table_rsp_valid&&table_rsp_ready&&table_rsp_epoch!=accepted_epoch)table_identity_bad<=1;
                    if(phase_mask[0])stat_scan_cycles<=stat_scan_cycles+1'b1;
                    if(phase_mask[1])stat_score_cycles<=stat_score_cycles+1'b1;
                    if(phase_mask[2])stat_sort_cycles<=stat_sort_cycles+1'b1;
                    if(phase_mask[3])stat_decode_cycles<=stat_decode_cycles+1'b1;
                    if(phase_mask[4])stat_nms_cycles<=stat_nms_cycles+1'b1;
                    if(phase_mask[5])stat_roi_cycles<=stat_roi_cycles+1'b1;
                    if(phase_mask[6])stat_record_cycles<=stat_record_cycles+1'b1;
                end
                case(state)
                    IDLE:if(task_valid&&task_ready)begin
                        cmd<=task_cmd_id;accepted_epoch<=task_epoch;frame<=task_frame_id;done_cmd_id<=task_cmd_id;done_epoch<=task_epoch;done_frame_id<=task_frame_id;
                        source_w<=task_source_w;source_h<=task_source_h;resized_w<=task_resized_w;resized_h<=task_resized_h;pad_left<=task_pad_left;pad_top<=task_pad_top;capacity<=task_capacity;
                        done_status<=0;done_detail<=0;done_face_count<=0;done_nms_count<=0;done_crc<=0;faces<=0;
                        bbox_issued<=0;bbox_received<=0;scan_issued<=0;scan_received<=0;pre_count<=0;key_count<=0;key_index<=0;pre_read<=0;next_valid<=0;
                        buffered_count<=0;flush_index<=0;tail_pending<=0;tail_word<=0;crc_step<=0;table_identity_bad<=0;
                        precheck_status<=task_epoch!=context_epoch ? 5'd13:!heads_loaded ? 5'd11:
                            task_head_generation!=loaded_generation ? 5'd13:!ddr_drained ? 5'd15:
                            (task_capacity==0||task_capacity>2100) ? 5'd12:
                            (task_source_w==0||task_source_w>8192||task_source_h==0||task_source_h>8192||task_resized_w==0||task_resized_w>320||task_resized_h==0||task_resized_h>320||task_pad_left>319||task_pad_top>319) ? 5'd14:5'd0;
                        quiet_count<=0;next_state=PREFLIGHT;
                    end
                    PREFLIGHT:begin
                        if(precheck_status!=0)fail(precheck_status,1);
                        else begin
                            geom_den<=source_w>source_h ? source_w:source_h;geom_trial<=source_w>source_h ? {source_w,8'b0}:{source_h,8'b0};
                            geom_rem_w<=({8'b0,source_w}<<8)+({8'b0,source_w}<<6);geom_rem_h<=({8'b0,source_h}<<8)+({8'b0,source_h}<<6);
                            geom_qw<=0;geom_qh<=0;geom_bit<=8;next_state=GEOM_DIV;
                        end
                    end
                    GEOM_DIV:begin
                        geom_trial<=geom_trial>>1;
                        if(geom_rem_w>=geom_trial)begin geom_rem_w<=geom_rem_w-geom_trial;geom_qw[geom_bit]<=1;end
                        if(geom_rem_h>=geom_trial)begin geom_rem_h<=geom_rem_h-geom_trial;geom_qh[geom_bit]<=1;end
                        if(geom_bit==0)next_state=GEOM_CHECK;else geom_bit<=geom_bit-1'b1;
                    end
                    GEOM_CHECK:begin
                        if(resized_w!=expected_w||resized_h!=expected_h||pad_left!=((9'd320-expected_w)>>1)||pad_top!=((9'd320-expected_h)>>1))fail(14,2);
                        else next_state=PRE_BBOX;
                    end
                    PRE_BBOX:begin
                        if(bbox_issued<525)bbox_issued<=bbox_issued+1'b1;
                        if(bbox_pending)begin
                            bbox_received<=bbox_received+1'b1;
                            if(!valid_bbox)fail(22,4);else if(bad_bbox)fail(19,4);else if(bbox_received==524)next_state=PROB_SCAN;
                        end
                    end
                    PROB_SCAN,PROB_DRAIN:begin
                        if(p_front_valid&&(p_front_bad||!p_ready))fail(22,6);
                        else if(p_ret_valid)begin
                            if(p_ret_status!=0)fail(p_ret_status,6);
                            else begin if(p_ret_ge)pre_count<=pre_count+1'b1;if(p_ret_last)next_state=PROB_DRAIN;end
                        end
                        if(state==PROB_DRAIN&&!scan_request&&!scan_pending&&!p_front_valid&&!p_ret_valid&&!p_busy&&!pool_busy&&!memory_busy&&!write_busy&&!local_fault_busy)begin
                            if(pre_count==0)next_state=FINAL_FLUSH;else next_state=SCORES;
                        end
                    end
                    SCORES:begin
                        if(next_valid&&next_status!=0)fail(next_status,8);
                        else if(root_ret_valid)begin
                            if(root_ret_status!=0)fail(root_ret_status,8);else key_count<=key_count+1'b1;
                        end
                        if(pre_read==pre_count&&!pre_request&&!pre_pending&&!next_valid&&!root_busy&&!root_ret_valid&&!write_busy&&!local_fault_busy)begin if(key_count==0)next_state=FINAL_FLUSH;else next_state=SORT_START;end
                    end
                    SORT_START:next_state=SORT_WAIT;
                    SORT_WAIT:if(sort_done)next_state=SORT_CHECK;
                    SORT_CHECK:begin
                        if(sort_status_reg!=0)fail(sort_status_reg,10);else begin sorted_buffer<=sort_buffer_reg;key_index<=0;next_state=KEY_READ;end
                    end
                    KEY_READ:next_state=KEY_MEMWAIT;
                    KEY_MEMWAIT:next_state=KEY_CAPTURE;
                    KEY_CAPTURE:begin
                        cid<=fetched_key[31:0];score_bits<=~fetched_key[63:32];scale<=fetched_key[31:0]<1600 ? 0:fetched_key[31:0]<2000 ? 1:2;
                        position<=fetched_key[31:0]<1600 ? fetched_key[10:0]:fetched_key[31:0]<2000 ? fetched_key[31:0]-1600:fetched_key[31:0]-2000;next_state=KEY_CHECK;
                    end
                    KEY_CHECK:begin if(key_status_reg!=0)fail(key_status_reg,12);else next_state=BBOX_READ;end
                    BBOX_READ:next_state=BBOX_MEMWAIT;
                    BBOX_MEMWAIT:next_state=BBOX_CAPTURE;
                    BBOX_CAPTURE:begin raw_codes<=bbox_pack;next_state=BBOX_CHECK;end
                    BBOX_CHECK:begin if(bbox_status_reg!=0)fail(bbox_status_reg,14);else next_state=DEC_START;end
                    DEC_START:if(dec_ready&&!pool_busy)next_state=DEC_WAIT;
                    DEC_WAIT:if(dec_valid)begin current_q<=dec_q;current_rectangle<=dec_rectangle;current_area<=dec_area;next_state=DEC_CHECK;end
                    DEC_CHECK:begin if(dec_status_reg!=0)fail(dec_status_reg,16);else next_state=NMS_START;end
                    NMS_START:if(n_ready&&!pool_busy)next_state=NMS_WAIT;
                    NMS_WAIT:if(n_valid)next_state=NMS_CHECK;
                    NMS_CHECK:begin if(nms_status_reg!=0)fail(nms_status_reg,18);else next_state=nms_keep_reg ? ROI_START:ADVANCE;end
                    ROI_START:if(roi_ready&&!pool_busy)next_state=ROI_WAIT;
                    ROI_WAIT:if(roi_valid)next_state=ROI_CHECK;
                    ROI_CHECK:begin
                        if(roi_status_reg!=0)fail(roi_status_reg,20);
                        else if(roi_empty_reg)next_state=ADVANCE;else if(roi_capacity_bad)fail(12,20);
                        else begin current_record<=roi_record_reg;first_record<=faces==0;next_state=WRITE_RECORD;end
                    end
                    WRITE_RECORD:begin faces<=faces+1'b1;buffered_count<=buffered_count+1'b1;crc_step<=0;next_state=CRC_RECORD;end
                    CRC_RECORD:begin
                        if(crc_valid&&crc_error)fail(20,23);
                        else if(!crc_input||crc_ready)begin
                            if(crc_step==7)begin
                                tail_word<=current_record[255:224];tail_pending<=1;
                                if(buffered_count==16)begin flush_base<=faces-buffered_count;flush_index<=0;resume_state<=ADVANCE;next_state=FLUSH_META;end
                                else next_state=ADVANCE;
                            end else crc_step<=crc_step+1'b1;
                        end
                    end
                    FLUSH_META:if(batch_ready)next_state=FLUSH_READ;
                    FLUSH_READ:next_state=FLUSH_MEMWAIT;
                    FLUSH_MEMWAIT:next_state=FLUSH_CAPTURE;
                    FLUSH_CAPTURE:begin
                        if(!(&ov_a[31:16]))fail(22,24);else begin record_register<=oq_a[511:256];record_index_reg<=flush_base+flush_index;next_state=FLUSH_SEND;end
                    end
                    FLUSH_SEND:if(record_ready)begin
                        if(flush_index+1==buffered_count)begin buffered_count<=0;next_state=resume_state;end else begin flush_index<=flush_index+1'b1;next_state=FLUSH_READ;end
                    end
                    ADVANCE:begin if(key_index+1==key_count)next_state=FINAL_FLUSH;else begin key_index<=key_index+1'b1;next_state=KEY_READ;end end
                    FINAL_FLUSH:begin
                        if(buffered_count!=0)begin flush_base<=faces-buffered_count;flush_index<=0;resume_state<=CRC_FINAL;next_state=FLUSH_META;end else next_state=CRC_FINAL;
                    end
                    CRC_FINAL:if(crc_ready)next_state=CRC_WAIT;
                    CRC_WAIT:if(crc_valid)next_state=CRC_CHECK;
                    CRC_CHECK:begin
                        if(crc_status_reg!=0)fail(crc_status_reg,29);
                        else begin done_face_count<=faces;done_nms_count<=n_kept;done_crc<=crc_value_reg;quiet_count<=0;next_state=DRAIN;end
                    end
                    DRAIN:begin
                        if(!memory_busy&&!pool_busy&&!p_busy&&!root_busy&&!sort_busy&&!dec_busy&&!n_busy&&!roi_busy&&!crc_busy&&!p_front_valid&&!p_ret_valid&&!root_ret_valid&&!local_fault_busy&&!write_busy&&!raw_output_busy&&!wait_event)begin
                            if(quiet_count==1)next_state=COMPLETE;else quiet_count<=quiet_count+1'b1;
                        end else quiet_count<=0;
                    end
                    ERROR:begin
                        done_face_count<=0;done_crc<=0;
                        if(!memory_busy&&!pool_busy&&!local_fault_busy&&!write_busy&&!raw_output_busy&&!wait_event)begin if(quiet_count==1)next_state=COMPLETE;else quiet_count<=quiet_count+1'b1;end else quiet_count<=0;
                    end
                    COMPLETE:if(done_ready)next_state=IDLE;
                    default:fail(22,255);
                endcase
                if(active&&state!=ERROR&&memory_fault_reg)fail(22,254);
                state<=next_state;phase_mask<=phase_for(next_state);frame_active_reg<=next_state!=IDLE&&next_state!=COMPLETE;
            end
            // The first post-accept physical edge is itself one wall cycle.
            // Initialize from that edge, including a possible CE pause.
            if(account_start)begin
                total_cycles<=64'd1;paused_cycles<=run_ce ? 64'd0:64'd1;wait_cycles<=0;
                stat_scan_cycles<=run_ce ? 32'd1:32'd0;stat_score_cycles<=0;stat_sort_cycles<=0;
                stat_decode_cycles<=0;stat_nms_cycles<=0;stat_roi_cycles<=0;stat_record_cycles<=0;stat_table_beats<=0;
            end
        end
    end

    // spec155: physical identity controls, unchanged cycle/reset semantics.
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_A_rst_n_buffer(.I0(!clear),.Z(rg_A_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_P_rst_n_buffer(.I0(!clear),.Z(rg_P_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_O_rst_n_buffer(.I0(!clear),.Z(rg_O_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_raw_response_clear_buffer(.I0(clear),.Z(rg_raw_response_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_probability_clear_buffer(.I0(frame_clear),.Z(rg_probability_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_root_clear_buffer(.I0(frame_clear),.Z(rg_root_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_sorter_clear_buffer(.I0(frame_clear),.Z(rg_sorter_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_decoder_clear_buffer(.I0(frame_clear),.Z(rg_decoder_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_nms_clear_buffer(.I0(frame_clear),.Z(rg_nms_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_roi_clear_buffer(.I0(frame_clear),.Z(rg_roi_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_pool_clear_buffer(.I0(frame_clear),.Z(rg_pool_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_crc_clear_buffer(.I0(frame_clear),.Z(rg_crc_clear));
endmodule
