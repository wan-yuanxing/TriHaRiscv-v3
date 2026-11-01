// Independent unselected complete1024bit-key LUTRAM candidate; spec133.
// B03 parameter admission, full-row E1 cache, Dense A gather and DW vectors.
// The local block port is ordinary ready/valid; A/B/DW reads use common run_ce.
// Independent APM geometry candidate: exact same bounded unsigned products.
// PDS must confirm the inferred APM count; no register stage is added.
// No bridge is instantiated here. Input addresses are already controller bytes.
module b03_model_input_payload #(
    parameter LATCH_OP=1,
    parameter LATCH_EPOCH=1,
    // The sealed board model can omit content-only admission checks.  The
    // transport, address, epoch, tag and bank safety checks remain active.
    parameter integer TRUSTED_MODEL=0
)(
    input wire clk,rst_n,run_ce,cancel_request,
    input wire cmd_valid,output wire cmd_ready,input wire [1:0] cmd_kind,
    input wire [1023:0] op_words,
    input wire [31:0] workspace_base,resolved_src_base,epoch,cmd_tag,
    input wire [8:0] row_y,x_begin,input wire [4:0] m_count,
    output reg done_valid,input wire done_ready,
    output reg [31:0] done_status,done_detail,done_tag,
    output reg param_valid,rows_valid,a_valid,
    input wire [2:0] param_group,
    output wire [255:0] bias_flat,mult_flat,
    output wire [47:0] shift_flat,output reg [63:0] shadow_valid,
    output reg [95:0] aux_coeff,
    input wire a_req_valid,output wire a_req_ready,input wire [9:0] a_req_row,input wire [31:0] a_req_tag,
    output wire a_rsp_valid,output wire [127:0] a_rsp_data,output wire [31:0] a_rsp_tag,output wire a_rsp_error,
    input wire b_req_valid,output wire b_req_ready,input wire [9:0] b_req_row,input wire [31:0] b_req_tag,
    output wire b_rsp_valid,output wire [127:0] b_rsp_data,output wire [31:0] b_rsp_tag,output wire b_rsp_error,
    input wire dw_req_valid,output wire dw_req_ready,input wire [3:0] dw_req_tap,
    input wire [8:0] dw_req_ox,input wire [6:0] dw_req_co_base,input wire [31:0] dw_req_tag,
    output wire dw_rsp_valid,output reg [127:0] dw_rsp_data,output wire [31:0] dw_rsp_tag,output wire dw_rsp_error,
    output wire mem_req_valid,input wire mem_req_ready,output wire mem_req_write,mem_req_verify,
    output wire [31:0] mem_req_offset,mem_req_tag,output wire [4:0] mem_req_beats,output wire [2:0] mem_req_client,
    output wire mem_w_valid,input wire mem_w_ready,output wire [255:0] mem_w_data,
    output wire [31:0] mem_w_strb,output wire mem_w_last,
    input wire mem_r_valid,output wire mem_r_ready,input wire [255:0] mem_r_data,input wire mem_r_last,
    input wire mem_rsp_valid,output wire mem_rsp_ready,input wire [3:0] mem_rsp_status,input wire [31:0] mem_rsp_tag,
    output wire busy,output reg reset_required,output wire [7:0] debug_state,
    output reg [31:0] cycles,read_bytes
);
    localparam IDLE=0,CHECK=1,PARAM_SETUP=2,ROW_SETUP=3,PLAN=4,TRANSFER=5,
        PARAM_NEXT=6,PARAM_BOUND=7,ROW_WRITE=8,ROW_DRAIN=9,ROW_NEXT=10,
        BUILD_SETUP=11,GATHER_ISSUE=12,GATHER_DRAIN=13,A_WRITE=14,A_DRAIN=15,
        HELD=16,ABORT=17,FEATURE_DRAIN=18,FEATURE_READY=19,ID_COMPARE=20,ROW_OFFSET=21,GEO2=22,PARAM_BOUND_FETCH=23,KEY_SAVE=24;
    reg [7:0] state;
    wire step=rst_n&&run_ce;
    reg active,aborting,offer,inflight,rsp_seen;
    reg [1:0] kind,part;
    reg [1023:0] captured_op;
    wire [1023:0] op;
    generate if(LATCH_OP)begin:owned_op
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)captured_op<=0;
            else if(cmd_valid&&cmd_ready)captured_op<=op_words;
        end
        assign op=captured_op;
    end else begin:parent_op
        // Only use beneath an owner that keeps all op bits stable for the
        // complete layer lease, including A/B/DW reads and CE0 clocks.
        assign op=op_words;
    end endgenerate
    reg [31:0] saved_workspace,saved_src,tag;
    reg [31:0] captured_epoch;wire [31:0] saved_epoch;
    generate if(LATCH_EPOCH)begin:owned_epoch
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)captured_epoch<=0;
            else if(cmd_valid&&cmd_ready)captured_epoch<=epoch;
        end
        assign saved_epoch=captured_epoch;
    end else begin:parent_epoch
        // Parent owns this complete layer lease, including CE0 and all reads.
        assign saved_epoch=epoch;
    end endgenerate
    reg saved_stride2;reg [14:0] row_offset_hold;
    reg [6:0] spatial_words,cached_row_words;
    reg [14:0] feature_plane_words,cmd_cin_rows,cached_group_stride;
    reg [10:0] full_rows;
    reg [16:0] full_bank_words;
    reg [22:0] feature_logical;
    reg [31:0] row_src,row_epoch;reg [8:0] saved_y,saved_x,cached_y;reg [4:0] saved_m;
    reg [31:0] pbase,request_sequence;reg [22:0] pbytes,region_done;
    reg [22:0] next_region_done;reg region_more;
    reg [31:0] offered_offset,offered_tag;reg [4:0] offered_beats,received;
    reg [13:0] w_logical,w_alloc;reg [8:0] b_logical,b_alloc;reg [9:0] q_logical,q_alloc;
    reg [7:0] k_count;reg [6:0] co_count,cin_count;
    reg [31:0] region_kind;
    reg rx_valid;reg [255:0] rx_data;reg [13:0] rx_offset;
    reg resident_valid,resident_mode,resident_loading;
    reg [31:0] resident_src,resident_epoch;
    wire [63:0] feature_data;wire [6:0] feature_count;reg [6:0] feature_ci;
    wire feature_pack_ready,feature_pack_valid;
    reg [8:0] feature_y;reg [6:0] feature_word;reg [9:0] resident_yword[0:2];
    reg [1:0] row_slot[0:2];reg rolling;reg [1:0] rolling_shift;
    reg [31:0] param_equal_chunks,row_equal_chunks,resident_equal_chunks;
    reg prior_rows_valid;
    wire can_roll=prior_rows_valid&&(&row_equal_chunks)&&row_src==saved_src&&row_epoch==saved_epoch&&
        saved_y==cached_y+1&&op[448+:32]==3&&(op[512+:32]==1||op[512+:32]==2)&&
        (op[0+:32]==1||op[0+:32]==2);
    reg [63:0] row_seen;reg [191:0] row_present;
    reg [1:0] weight_block;reg [7:0] weight_krow;
    reg [31:0] param_workspace,param_epoch;
    reg [6:0] ci_index,check_co;reg [1:0] ky_index;
    reg [31:0] row_start;reg [6:0] row_word_count,row_write_word;reg [4:0] row_phase;
    // One additional true-TDP word RAM replaces the wide FF row buffer.
    // The ordinary R beat is held in rx_data while four CE writes retire.
    reg [1:0] row_rx_pair;
    reg [6:0] row_read_issue;
    reg row_prev_valid;
    reg [63:0] row_prev_data;
    wire row_stage_busy,row_stage_conf,row_stage_range;
    wire [31:0] row_stage_q_a,row_stage_q_b;
    wire row_stage_v_a,row_stage_v_b;
    wire row_rx_write=step&&active&&kind==1&&!resident_loading&&rx_valid&&!aborting&&!cancel_request;
    wire [6:0] row_pair_count=(row_word_count+7'd1)>>1;
    wire row_rd_issue=step&&state==ROW_WRITE&&!aborting&&!cancel_request&&row_read_issue<=row_pair_count;
    (* syn_maxfan=64 *) wire [10:0] row_stage_addr=row_rx_write?({4'd0,rx_offset[8:2]}+{8'd0,row_rx_pair,1'b0}):
        ({8'd0,row_phase[4:2]}+{3'd0,row_read_issue,1'b0});
    wire row_out_valid=state==ROW_WRITE&&row_prev_valid&&row_stage_v_a&&row_stage_v_b;
    wire [95:0] row_read_window={row_stage_q_a,row_prev_data};
    wire [63:0] row_read_data=row_read_window>>{row_phase[1:0],3'b000};

    // spec155: declare identity outputs before their consumer instances.
    wire rg_ROW_STAGE_rst_n;
    wire rg_feature_pack_rst_n;
    wire rg_feature_pack_clear;
    wire rg_gather_pipeline_rst_n;
    wire rg_gather_pipeline_clear;
    wire rg_A_rst_n;
    wire rg_B_rst_n;
    wire rg_ROI_rst_n;
    b03_bank_array_payload #(.BANKS(1),.WIDTH(32),.DEPTH(1024)) ROW_STAGE(
        .clk(clk),.rst_n(rg_ROW_STAGE_rst_n),.run_ce(run_ce),
        .req_a(row_rx_write||row_rd_issue),.req_b(row_rx_write||row_rd_issue),
        .we_a(row_rx_write),.we_b(row_rx_write),.addr_a(row_stage_addr),.addr_b(row_stage_addr+11'd1),
        .data_a(rx_data[64*row_rx_pair+:32]),.data_b(rx_data[64*row_rx_pair+32+:32]),.mask_a(4'hf),.mask_b(4'hf),
        .q_a(row_stage_q_a),.q_b(row_stage_q_b),.valid_a(row_stage_v_a),.valid_b(row_stage_v_b),
        .busy(row_stage_busy),.conflict(row_stage_conf),.range_error(row_stage_range));
    wire [31:0] bias_read[0:7],mult_read[0:7];wire [5:0] shift_read[0:7];reg [13:0] sumabs[0:63];
    wire [31:0] code_full=op[0+:32],src_dtype_full=op[160+:32];
    wire [31:0] cin_full=op[256+:32],co_full=op[288+:32],hin_full=op[320+:32],win_full=op[352+:32];
    wire [31:0] kh_full=op[448+:32],kw_full=op[480+:32],sh_full=op[512+:32],sw_full=op[544+:32];
    wire [3:0] code=code_full[3:0];wire [1:0] src_dtype=src_dtype_full[1:0];
    wire [6:0] cin=cin_full[6:0],co=co_full[6:0];wire [8:0] hin=hin_full[8:0],win=win_full[8:0];
    wire [1:0] kh=kh_full[1:0],kw=kw_full[1:0];
    wire [1:0] sh=saved_stride2?2'd2:2'd1,sw=sw_full==2?2'd2:2'd1;
    wire [7:0] pt=op[576+:8],pl=op[584+:8];
    reg [3:0] row_code;reg [6:0] row_cin;
    reg [8:0] row_win,row_hin;reg [1:0] row_kh,row_kw,row_sw;reg [7:0] row_pl;
    reg [4:0] key_index;reg [2:0] key_save_mask,key_written;
    reg [7:0] key_return;
    wire key_saving=step&&active&&!aborting&&!cancel_request&&epoch==saved_epoch&&state==KEY_SAVE;
    wire [31:0] key_word=op[32*key_index+:32];
    wire [95:0] key_q;
    genvar key_bank,key_bit;
    generate for(key_bank=0;key_bank<3;key_bank=key_bank+1)begin:identity_key
        for(key_bit=0;key_bit<32;key_bit=key_bit+1)begin:word_bit
            GTP_RAM32X1DP #(.INIT(32'd0)) ram(
                .WCLK(clk),.WE(key_saving&&key_save_mask[key_bank]),.WADDR(key_index),
                .DI(key_word[key_bit]),.RADDR(key_index),.DO(key_q[32*key_bank+key_bit]));
        end
    end endgenerate
    assign busy=active||done_valid;assign debug_state=state;
    // Internal receipt accounting lives entirely inside the !reset branch.
    // Use the packer's capacity/clear predicate directly here: routing the
    // external reset-qualified ready back into the FSM adds three reset LUT
    // buffers before its beat-count/error logic. Public ready stays reset-gated.
    wire pack_capacity=resident_loading&&!aborting&&!cancel_request&&epoch==saved_epoch&&feature_count<=8;
    wire receive_capacity=inflight&&(aborting||(kind==1&&resident_loading?pack_capacity:!rx_valid));
    wire mem_rf=mem_r_valid&&receive_capacity,mem_df=mem_rsp_valid&&inflight;
    wire [5:0] received_after={1'b0,received}+{5'b0,mem_rf};
    assign mem_req_valid=rst_n&&offer;
    assign mem_req_offset=offered_offset;assign mem_req_tag=offered_tag;
    assign mem_req_beats=offered_beats;assign mem_req_client=(kind==0)?3'd1:3'd2;
    assign mem_req_write=0;assign mem_req_verify=0;
    assign mem_w_valid=0;assign mem_w_data=0;assign mem_w_strb=0;assign mem_w_last=0;
    // Qualify once at this interface, not through the packer's reset-buffer tree.
    assign mem_r_ready=rst_n&&receive_capacity;
    assign mem_rsp_ready=rst_n&&inflight;
    wire shadow_write=active&&!aborting&&step&&state==TRANSFER&&kind==0&&rx_valid;
    wire [2:0] bias_group=(state==PARAM_BOUND_FETCH)?check_co[5:3]:param_group;
    genvar c,bit_index;
    generate for(c=0;c<8;c=c+1)begin:shadow
        wire wb=shadow_write&&part==1&&rx_offset<256&&
            ({1'b0,rx_offset[7:5],3'b000}+c)<co_count;
        wire wq=shadow_write&&part==2&&rx_offset<512&&rx_offset[5]==(c>=4)&&
            ({1'b0,rx_offset[8:5],2'b00}+(c%4))<co_count;
        for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:wordbit
            GTP_RAM32X1DP #(.INIT(32'd0)) BIAS(
                .WCLK(clk),.WE(wb),.WADDR({2'b0,rx_offset[7:5]}),
                .DI(rx_data[32*c+bit_index]),.RADDR({2'b0,bias_group}),.DO(bias_read[c][bit_index]));
            GTP_RAM32X1DP #(.INIT(32'd0)) MULT(
                .WCLK(clk),.WE(wq),.WADDR({2'b0,rx_offset[8:6]}),
                .DI(rx_data[64*(c%4)+bit_index]),.RADDR({2'b0,param_group}),.DO(mult_read[c][bit_index]));
        end
        for(bit_index=0;bit_index<6;bit_index=bit_index+1)begin:shiftbit
            GTP_RAM32X1DP #(.INIT(32'd0)) SHIFT(
                .WCLK(clk),.WE(wq),.WADDR({2'b0,rx_offset[8:6]}),
                .DI(rx_data[64*(c%4)+32+bit_index]),.RADDR({2'b0,param_group}),.DO(shift_read[c][bit_index]));
        end
        assign bias_flat[32*c+:32]=bias_read[c];assign mult_flat[32*c+:32]=mult_read[c];assign shift_flat[6*c+:6]=shift_read[c];
    end endgenerate

    // Spatial geometry is admitted in CHECK before these bounded products run.
    function [14:0] mul15;
        input [14:0] a;input [8:0] b;
        begin mul15=a*b;end
    endfunction
    function [16:0] mul17;
        input [10:0] a;input [8:0] b;
        begin mul17=a*b;end
    endfunction
    function [22:0] mul23;
        input [14:0] a;input [8:0] b;
        begin mul23=a*b;end
    endfunction
    function [13:0] mul14;
        input [7:0] a,b;
        begin mul14=a*b;end
    endfunction
    function [14:0] slot_offset;
        input [1:0] slot;input [6:0] words;
        begin
            case(slot)
                0:slot_offset=0;1:slot_offset={8'd0,words};
                2:slot_offset={7'd0,words,1'b0};
                3:slot_offset={8'd0,words}+{7'd0,words,1'b0};
            endcase
        end
    endfunction
    function [7:0] absw;input[7:0] v;begin absw=v[7]?(~v+8'd1):v;end endfunction
    wire [13:0] logical_w=mul14(({1'b0,co[6:0]}+8'd15)>>4,op[896+:8])<<4;
    wire [13:0] slot_w=(logical_w+14'd255)&14'h3f00;
    wire [8:0] slot_b=co<=64?9'd256:9'd0;
    wire [9:0] slot_q=co<=32?10'd256:10'd512;
    wire [9:0] b_row_count=mul14(({1'b0,co_count}+8'd15)>>4,k_count);
    // One 16-lane adder bank is shared across the four Co blocks.
    // At an odd-K crossing the next block has never been accumulated yet;
    // its first (high-half) row initializes it directly.
    wire weight_cross=weight_krow+9'd1>={1'b0,k_count};
    reg [223:0] current_sum_vector;
    integer sum_lane;
    always @*begin
        current_sum_vector=0;
        for(sum_lane=0;sum_lane<16;sum_lane=sum_lane+1)begin
            case(weight_block)
                0:current_sum_vector[14*sum_lane+:14]=sumabs[sum_lane];
                1:current_sum_vector[14*sum_lane+:14]=sumabs[16+sum_lane];
                2:current_sum_vector[14*sum_lane+:14]=sumabs[32+sum_lane];
                3:current_sum_vector[14*sum_lane+:14]=sumabs[48+sum_lane];
            endcase
        end
    end
    wire [223:0] next_sum_vector;
    genvar sum_c;
    generate for(sum_c=0;sum_c<16;sum_c=sum_c+1)begin:sum_update
        wire [7:0] lo=absw(rx_data[8*sum_c+:8]);
        wire [7:0] hi=(!weight_cross&&rx_offset+14'd16<w_logical)?absw(rx_data[128+8*sum_c+:8]):8'd0;
        assign next_sum_vector[14*sum_c+:14]=(weight_krow==0?14'd0:current_sum_vector[14*sum_c+:14])+{6'd0,lo}+{6'd0,hi};
    end endgenerate
    wire [22:0] remaining=pbytes-region_done;
    wire [31:0] actual_cursor=pbase+region_done;
    wire [8:0] page_beats=9'd128-{2'b0,actual_cursor[11:5]};
    wire [17:0] left_beats=remaining>>5;
    wire [4:0] planned=(left_beats>16)?(page_beats<16?page_beats[4:0]:5'd16):
        (left_beats>page_beats?page_beats[4:0]:left_beats[4:0]);
    // PLAN owns the immutable burst geometry. Preserve the original 32-bit
    // addition/comparison before narrowing the saved cursor to its register.
    wire [31:0] planned_region_end={9'd0,region_done}+({27'd0,planned}<<5);
    wire [1:0] row_effective_kh=code==5?2'd1:kh;
    wire signed [12:0] input_y=code==5?$signed({4'd0,saved_y[8:1]}):
        $signed({4'd0,saved_y}<<(sh==2))-$signed({5'd0,pt})+$signed({11'd0,ky_index});
    wire [14:0] row_offset=mul15({8'd0,ci_index},hin[8:0])+input_y;
    wire [31:0] next_row_start=saved_src+{9'd0,mul23(row_offset_hold,win[8:0])};
    wire [32:0] next_row_end={1'b0,next_row_start}+{1'b0,win};
    wire [31:0] next_row_aligned=next_row_start&32'hffffffe0;
    wire [31:0] next_row_bytes=(win+{27'd0,next_row_start[4:0]}+31)&32'hffffffe0;
    wire [3:0] roi_row_number=({2'd0,ci_index[5:4]}<<1)+{2'd0,ci_index[5:4]}+{2'd0,row_slot[ky_index]};
    wire [9:0] roi_slot_word=mul15({11'd0,roi_row_number},{2'd0,row_word_count});
    wire feature_fits=full_bank_words<=1024;
    wire resident_hit=resident_valid&&(&resident_equal_chunks)&&resident_src==saved_src&&resident_epoch==saved_epoch;
    wire [14:0] roi_group_stride=cached_group_stride;
    function [31:0] roi_ky_offset;
        input [1:0] ky;
        begin roi_ky_offset=resident_mode?{22'd0,resident_yword[ky]}:slot_offset(row_slot[ky],cached_row_words);end
    endfunction
    wire [9:0] feature_row_left={1'b0,win}-{1'b0,feature_word,2'b00};
    wire [3:0] feature_take=feature_row_left>=8?4'd8:feature_row_left[3:0];
    wire feature_consume=step&&resident_loading&&!aborting&&!cancel_request&&feature_ci<cin&&
        feature_count>=feature_take&&(state==TRANSFER||state==PLAN||state==FEATURE_DRAIN);
    b03_feature_pack_compact feature_pack(
        .clk(clk),.rst_n(rg_feature_pack_rst_n),.clear(rg_feature_pack_clear),.run_ce(run_ce),
        .in_valid(mem_r_valid&&inflight&&kind==1&&resident_loading&&!aborting&&!cancel_request),
        .in_ready(feature_pack_ready),.in_data(mem_r_data),.out_take(feature_take),
        .out_valid(feature_pack_valid),.out_data(feature_data),.out_ready(feature_consume),.count(feature_count));
    wire [16:0] feature_bank_address=(feature_ci[4]?{2'd0,feature_plane_words}:17'd0)+
        (feature_ci[5]?{1'b0,feature_plane_words,1'b0}:17'd0)+
        {2'd0,mul15({6'd0,feature_y},{2'd0,spatial_words})}+{8'd0,feature_word};
    wire [511:0] rq,rq_b;wire [15:0] rv,rv_b;
    wire gather_start_ready,gather_done_valid,gather_busy,gather_a_write;
    wire [31:0] gather_status,gather_tag,gather_groups,gather_vectors;
    wire [15:0] gather_roi_a,gather_roi_b;wire [175:0] gather_addr_a,gather_addr_b;
    wire [7:0] gather_a_index;wire [127:0] gather_a_data;
    // Keep the dependencies explicit: a constant-argument function call would
    // not reliably resensitize to the function's module-level array reads.
    wire [31:0] ky_offset0=resident_mode?{22'd0,resident_yword[0]}:slot_offset(row_slot[0],cached_row_words);
    wire [31:0] ky_offset1=resident_mode?{22'd0,resident_yword[1]}:slot_offset(row_slot[1],cached_row_words);
    wire [31:0] ky_offset2=resident_mode?{22'd0,resident_yword[2]}:slot_offset(row_slot[2],cached_row_words);
    b03_gather_lean gather_pipeline(
        .clk(clk),.rst_n(rg_gather_pipeline_rst_n),.clear(rg_gather_pipeline_clear),.run_ce(run_ce),
        .start_valid(step&&state==BUILD_SETUP&&active&&!aborting&&!cancel_request),.start_ready(gather_start_ready),
        .cfg_k_count(k_count[7:0]),.cfg_cin(cin[6:0]),.cfg_win(win[8:0]),.cfg_x(saved_x),.cfg_m(saved_m),
        .cfg_kernel3(kh==3),.cfg_stride2(sw==2),.cfg_pad_left(pl),.cfg_row_present(row_present),
        .cfg_row_offsets({ky_offset2[10:0],ky_offset1[10:0],ky_offset0[10:0]}),.cfg_group_stride(roi_group_stride[10:0]),.cfg_tag(tag),
        .done_valid(gather_done_valid),.done_ready(step&&state==GATHER_DRAIN),.done_status(gather_status),.done_tag(gather_tag),
        .roi_req_a(gather_roi_a),.roi_req_b(gather_roi_b),.roi_addr_a(gather_addr_a),.roi_addr_b(gather_addr_b),
        .roi_q_a(rq),.roi_q_b(rq_b),.roi_valid_a(rv),.roi_valid_b(rv_b),
        .a_write_valid(gather_a_write),.a_write_index(gather_a_index),.a_write_data(gather_a_data),
        .busy(gather_busy),.groups(gather_groups),.vectors(gather_vectors));
    reg [3:0] ar,aw,br,bw,ar_b,aw_b,br_b,bw_b;
    reg [43:0] aa,ab,ba,bb;reg [127:0] ad,ad_b,bd,bd_b;reg [15:0] am,am_b,bm,bm_b;
    wire [127:0] aq,aq_b,bq,bq_b;wire [3:0] av,av_b,bv,bv_b;
    wire a_busy,b_busy,a_conf,b_conf,a_range,b_range;
    b03_bank_array_payload #(.BANKS(4),.WIDTH(32),.DEPTH(1024)) A(
        .clk(clk),.rst_n(rg_A_rst_n),.run_ce(run_ce),.req_a(ar),.we_a(aw),.req_b(ar_b),.we_b(aw_b),
        .addr_a(aa),.addr_b(ab),.data_a(ad),.data_b(ad_b),.mask_a(am),.mask_b(am_b),
        .q_a(aq),.q_b(aq_b),.valid_a(av),.valid_b(av_b),.busy(a_busy),.conflict(a_conf),.range_error(a_range));
    b03_bank_array_payload #(.BANKS(4),.WIDTH(32),.DEPTH(1024)) B(
        .clk(clk),.rst_n(rg_B_rst_n),.run_ce(run_ce),.req_a(br),.we_a(bw),.req_b(br_b),.we_b(bw_b),
        .addr_a(ba),.addr_b(bb),.data_a(bd),.data_b(bd_b),.mask_a(bm),.mask_b(bm_b),
        .q_a(bq),.q_b(bq_b),.valid_a(bv),.valid_b(bv_b),.busy(b_busy),.conflict(b_conf),.range_error(b_range));
    reg [15:0] rr,rw,rr_b,rw_b;reg [175:0] raa,rab;
    reg [511:0] rd,rd_b;reg [63:0] rm,rm_b;
    wire r_busy,r_conf,r_range;
    b03_bank_array_payload #(.BANKS(16),.WIDTH(32),.DEPTH(1024)) ROI(
        .clk(clk),.rst_n(rg_ROI_rst_n),.run_ce(run_ce),.req_a(rr),.we_a(rw),.req_b(rr_b),.we_b(rw_b),
        .addr_a(raa),.addr_b(rab),.data_a(rd),.data_b(rd_b),.mask_a(rm),.mask_b(rm_b),
        .q_a(rq),.q_b(rq_b),.valid_a(rv),.valid_b(rv_b),.busy(r_busy),.conflict(r_conf),.range_error(r_range));

    reg [1:0] ap,bp,dp;reg [31:0] at0,at1,bt0,bt1,dt0,dt1;
    reg [15:0] dm0,dm1;reg [1:0] dx0,dx1;reg de0,de1;
    wire no_reads=!a_busy&&!b_busy&&!r_busy&&!row_stage_busy&&ap==0&&bp==0&&dp==0;
    assign cmd_ready=rst_n&&!active&&!done_valid&&!cancel_request&&!reset_required&&no_reads;
    assign a_req_ready=step&&!active&&!done_valid&&a_valid&&!cmd_valid&&epoch==saved_epoch;
    assign b_req_ready=step&&!active&&!done_valid&&param_valid&&!cmd_valid&&epoch==param_epoch&&(code_full==1||code_full==2);
    assign dw_req_ready=step&&!active&&!done_valid&&rows_valid&&!cmd_valid&&epoch==row_epoch;
    assign a_rsp_valid=ap[1];assign a_rsp_data=aq;assign a_rsp_tag=at1;assign a_rsp_error=ap[1]&&(av!=4'hf);
    assign b_rsp_valid=bp[1];assign b_rsp_data=bq;assign b_rsp_tag=bt1;assign b_rsp_error=bp[1]&&(bv!=4'hf);
    assign dw_rsp_valid=dp[1];assign dw_rsp_tag=dt1;assign dw_rsp_error=dp[1]&&(de1||((rv&dm1)!=dm1));
    integer dc;reg signed [12:0] dwx;reg [1:0] dky,dkx;reg [15:0] dw_mask;reg dw_bad;reg [47:0] dw_group_present;reg [7:0] dw_channel;
    reg signed [13:0] dw_word;
    always @*begin
        dky=0;dkx=0;dwx=0;dw_bad=0;dw_mask=0;dw_word=0;dw_channel=0;
        case(dw_req_co_base[5:4])
            0:dw_group_present=row_present[47:0];
            1:dw_group_present=row_present[95:48];
            2:dw_group_present=row_present[143:96];
            3:dw_group_present=row_present[191:144];
        endcase
        if(row_code==5)begin dky=0;dkx=0;dwx=$signed({5'd0,dw_req_ox[8:1]});end
        else begin
            if(row_kw==3)begin
                case(dw_req_tap)
                    0:begin dky=0;dkx=0;end 1:begin dky=0;dkx=1;end 2:begin dky=0;dkx=2;end
                    3:begin dky=1;dkx=0;end 4:begin dky=1;dkx=1;end 5:begin dky=1;dkx=2;end
                    6:begin dky=2;dkx=0;end 7:begin dky=2;dkx=1;end 8:begin dky=2;dkx=2;end
                    default:begin dky=0;dkx=0;end
                endcase
            end
            else if(row_kw==2)begin dky={3'd0,dw_req_tap[3:1]};dkx={3'd0,dw_req_tap[0]};end
            else begin dky=0;dkx=0;end
            dwx=$signed({4'd0,dw_req_ox}<<(row_sw==2))-$signed({5'd0,row_pl})+$signed({9'd0,dkx});
        end
        if(dw_req_co_base[3:0]!=0 || dw_req_co_base>=row_cin ||
           (row_code!=5 && dw_req_tap>=(row_kw==3?row_kh+row_kh+row_kh:row_kw==2?row_kh+row_kh:row_kh)) || (row_code==5&&dw_req_tap!=0))dw_bad=1;
        for(dc=0;dc<16;dc=dc+1)begin
            dw_channel={1'b0,dw_req_co_base}+dc[7:0];
            if(!dw_bad&&dw_channel<{1'b0,row_cin}&&dwx>=0&&dwx<$signed({4'd0,row_win})&&
               dw_group_present[dc*3+dky])dw_mask[dc]=1;
        end
        dw_word=((dw_req_co_base[4]?roi_group_stride[13:0]:14'd0)+(dw_req_co_base[5]?{roi_group_stride[12:0],1'b0}:14'd0))+roi_ky_offset(dky[1:0])+(dwx>>2);
        dw_rsp_data=0;
        for(dc=0;dc<16;dc=dc+1)if(dm1[dc])dw_rsp_data[8*dc+:8]=rq[32*dc+8*dx1+:8];
    end

    integer i,j;reg [3:0] bank_n;reg [10:0] wordaddr;
    always @*begin
        ar=0;aw=0;ar_b=0;aw_b=0;aa=0;ab=0;ad=0;ad_b=0;am=0;am_b=0;
        br=0;bw=0;br_b=0;bw_b=0;ba=0;bb=0;bd=0;bd_b=0;bm=0;bm_b=0;
        rr=0;rw=0;rr_b=0;rw_b=0;raa=0;rab=0;rd=0;rd_b=0;rm=0;rm_b=0;
        wordaddr=0;bank_n=0;
        if(a_req_valid&&a_req_ready&&a_req_row<k_count)begin ar=15;for(i=0;i<4;i=i+1)aa[11*i+:11]={1'b0,a_req_row};end
        if(b_req_valid&&b_req_ready&&b_req_row<b_row_count)begin br=15;for(i=0;i<4;i=i+1)ba[11*i+:11]={1'b0,b_req_row};end
        if(!aborting&&!cancel_request)begin
            if(kind==2&&active)begin
                rr=gather_roi_a;rr_b=gather_roi_b;raa=gather_addr_a;rab=gather_addr_b;
                if(gather_a_write)begin
                    ar=15;aw=15;am=16'hffff;ad=gather_a_data;
                    for(i=0;i<4;i=i+1)aa[11*i+:11]={3'd0,gather_a_index};
                end
            end
            if(state==TRANSFER&&kind==0&&part==0&&rx_valid)begin
                br=15;bw=15;br_b=15;bw_b=15;bm=16'hffff;bm_b=16'hffff;
                for(i=0;i<4;i=i+1)begin
                    ba[11*i+:11]=rx_offset>>4;bb[11*i+:11]=(rx_offset>>4)+1;
                    bd[32*i+:32]=rx_data[32*i+:32];bd_b[32*i+:32]=rx_data[128+32*i+:32];
                end
            end
            if(feature_consume)begin
                bank_n=feature_ci[3:0];rr[bank_n]=1;rw[bank_n]=1;
                if(feature_take>4)begin rr_b[bank_n]=1;rw_b[bank_n]=1;end
                for(i=0;i<16;i=i+1)begin
                    raa[11*i+:11]=feature_bank_address;rab[11*i+:11]=feature_bank_address+1;
                    rd[32*i+:32]=feature_data[31:0];rd_b[32*i+:32]=feature_data[63:32];
                    for(j=0;j<4;j=j+1)begin
                        if(j<feature_take)rm[4*i+j]=1;
                        if(j+4<feature_take)rm_b[4*i+j]=1;
                    end
                end
            end
            if(row_out_valid)begin
                bank_n=ci_index[3:0];wordaddr=roi_slot_word+row_write_word;
                rr[bank_n]=1;rw[bank_n]=1;
                if(row_write_word+1<row_word_count)begin rr_b[bank_n]=1;rw_b[bank_n]=1;end
                for(i=0;i<16;i=i+1)begin
                    raa[11*i+:11]=wordaddr;rab[11*i+:11]=wordaddr+1;
                    rd[32*i+:32]=row_read_data[31:0];rd_b[32*i+:32]=row_read_data[63:32];
                    for(j=0;j<4;j=j+1)begin
                        if(row_write_word*4+j<win)rm[4*i+j]=1;
                        if((row_write_word+1)*4+j<win)rm_b[4*i+j]=1;
                    end
                end
            end
            if(dw_req_valid&&dw_req_ready)begin
                rr=dw_mask;
                for(i=0;i<16;i=i+1)raa[11*i+:11]=dw_word;
            end
        end
    end

    wire [4:0] aux_off=saved_workspace[4:0]+op[704+:5];
    wire [31:0] aux_v0=rx_data[8*aux_off+:32],aux_v1=rx_data[8*aux_off+32+:32];
    wire [31:0] aux_v2=rx_data[8*aux_off+64+:32],aux_pad=rx_data[8*aux_off+96+:32];
    reg [31:0] admission_error;
    reg bad_content,bad_padding;
    reg [6:0] weight_low_channel,weight_high_channel;
    integer param_lane;
    always @*begin
        admission_error=0;bad_content=0;bad_padding=0;weight_low_channel=0;weight_high_channel=0;
        if(!TRUSTED_MODEL && part==0)begin
            for(param_lane=0;param_lane<16;param_lane=param_lane+1)begin
                weight_low_channel={1'b0,weight_block,4'd0}+param_lane[6:0];
                weight_high_channel={1'b0,weight_block,4'd0}+(weight_cross?7'd16:7'd0)+param_lane[6:0];
                if(rx_offset<w_logical && (rx_data[8*param_lane+:8]==8'h80 ||
                   (weight_low_channel>=co_count&&rx_data[8*param_lane+:8]!=0)))bad_content=1;
                if(rx_offset+14'd16<w_logical && (rx_data[128+8*param_lane+:8]==8'h80 ||
                   (weight_high_channel>=co_count&&rx_data[128+8*param_lane+:8]!=0)))bad_content=1;
            end
            bad_padding=(rx_offset>=w_logical&&rx_data[127:0]!=0)||
                (rx_offset+14'd16>=w_logical&&rx_data[255:128]!=0);
            if(bad_content)admission_error=32'h201;
            if(bad_padding)admission_error=32'h202;
        end else if(!TRUSTED_MODEL && part==1)begin
            for(param_lane=0;param_lane<8;param_lane=param_lane+1)
                if((rx_offset>>2)+param_lane>=co_count && rx_data[32*param_lane+:32]!=0)bad_padding=1;
            if(bad_padding)admission_error=32'h203;
        end else if(!TRUSTED_MODEL && part==2)begin
            for(param_lane=0;param_lane<4;param_lane=param_lane+1)begin
                if(rx_offset+8*param_lane<q_logical &&
                   (rx_data[64*param_lane+:32]==0 || rx_data[64*param_lane+31] ||
                    rx_data[64*param_lane+32+:32]==0 || rx_data[64*param_lane+38+:26]!=0 ||
                    rx_data[64*param_lane+32+:6]==63))bad_content=1;
                if((rx_offset>>3)+param_lane>=co_count && rx_data[64*param_lane+:64]!=0)bad_padding=1;
            end
            if(bad_content)admission_error=32'h204;
            if(bad_padding)admission_error=32'h205;
        end else if(!TRUSTED_MODEL && code==3)begin
            if(aux_v0==0||aux_v0[31]||aux_v1==0||aux_v1[31]||aux_v2==0||aux_v2>62||aux_pad!=0)
                admission_error=32'h206;
        end else if(!TRUSTED_MODEL && (aux_v0==0||aux_v0[31]||aux_v1==0||aux_v1>62))admission_error=32'h207;
    end

    task finish;
        input[31:0]status,detail;
        begin done_valid<=1;done_status<=status;done_detail<=detail;done_tag<=tag;active<=0;aborting<=0;state<=HELD;end
    endtask
    task fail;
        input[31:0]detail;
        begin
            if(!aborting)begin done_status<=detail[11:8]==4'h2 ? 32'd20 : 32'd18;done_detail<=detail;end
            if(detail[11:8]==4'h1 || detail[11:8]==4'h3)reset_required<=1;
            aborting<=1;resident_valid<=0;param_valid<=0;rows_valid<=0;a_valid<=0;shadow_valid<=0;state<=ABORT;
        end
    endtask
    reg [31:0] bound_bias,abs_bias;reg [13:0] bound_sum;
    reg [21:0] bound_activation;reg [32:0] bound;
    integer b,fc;reg signed [12:0] fy;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            param_equal_chunks<=0;row_equal_chunks<=0;resident_equal_chunks<=0;prior_rows_valid<=0;saved_stride2<=0;row_offset_hold<=0;spatial_words<=0;cached_row_words<=0;
            feature_plane_words<=0;cmd_cin_rows<=0;cached_group_stride<=0;full_rows<=0;full_bank_words<=0;feature_logical<=0;bound_bias<=0;bound_sum<=0;
            state<=IDLE;active<=0;aborting<=0;offer<=0;inflight<=0;rsp_seen<=0;
            resident_valid<=0;resident_mode<=0;resident_loading<=0;resident_src<=0;resident_epoch<=0;
            feature_ci<=0;feature_y<=0;feature_word<=0;
            resident_yword[0]<=0;resident_yword[1]<=0;resident_yword[2]<=0;
            row_slot[0]<=0;row_slot[1]<=1;row_slot[2]<=2;rolling<=0;rolling_shift<=0;
            kind<=0;part<=0;row_code<=0;row_cin<=0;row_win<=0;row_hin<=0;row_kh<=0;row_kw<=0;row_sw<=1;row_pl<=0;
            key_index<=0;key_save_mask<=0;key_written<=0;key_return<=0;saved_workspace<=0;saved_src<=0;tag<=0;
            row_src<=0;row_epoch<=0;saved_y<=0;saved_x<=0;cached_y<=0;saved_m<=0;
            pbase<=0;pbytes<=0;region_done<=0;next_region_done<=0;region_more<=0;request_sequence<=0;offered_offset<=0;offered_tag<=0;offered_beats<=0;received<=0;
            w_logical<=0;w_alloc<=0;b_logical<=0;b_alloc<=0;q_logical<=0;q_alloc<=0;k_count<=0;co_count<=0;cin_count<=0;region_kind<=0;
            rx_valid<=0;rx_data<=0;rx_offset<=0;row_seen<=0;row_rx_pair<=0;row_read_issue<=0;row_prev_valid<=0;row_prev_data<=0;row_present<=0;
            ci_index<=0;check_co<=0;ky_index<=0;row_start<=0;row_word_count<=0;row_phase<=0;row_write_word<=0;
            weight_block<=0;weight_krow<=0;param_workspace<=0;param_epoch<=0;
            ap<=0;bp<=0;dp<=0;at0<=0;at1<=0;bt0<=0;bt1<=0;dt0<=0;dt1<=0;dm0<=0;dm1<=0;dx0<=0;dx1<=0;de0<=0;de1<=0;
            done_valid<=0;done_status<=0;done_detail<=0;done_tag<=0;param_valid<=0;rows_valid<=0;a_valid<=0;shadow_valid<=0;aux_coeff<=0;
            reset_required<=0;cycles<=0;read_bytes<=0;
            for(b=0;b<64;b=b+1)sumabs[b]<=0;
        end else begin
            if(done_valid&&done_ready)begin done_valid<=0;state<=IDLE;end
            if(active)cycles<=cycles+1;
            if(step)begin
                ap<={ap[0],a_req_valid&&a_req_ready};at0<=a_req_tag;at1<=at0;
                bp<={bp[0],b_req_valid&&b_req_ready};bt0<=b_req_tag;bt1<=bt0;
                dp<={dp[0],dw_req_valid&&dw_req_ready};dt0<=dw_req_tag;dt1<=dt0;
                dm0<=dw_mask;dm1<=dm0;dx0<=dwx[1:0];dx1<=dx0;de0<=dw_bad;de1<=de0;

            end
            if(cmd_valid&&cmd_ready)begin
                kind<=cmd_kind;saved_workspace<=workspace_base;saved_src<=resolved_src_base;tag<=cmd_tag;
                saved_stride2<=(op_words[512+:32]==2);spatial_words<=(op_words[352+:9]+9'd3)>>2;
                saved_y<=row_y;saved_x<=x_begin;saved_m<=m_count;active<=1;aborting<=0;cycles<=0;read_bytes<=0;reset_required<=0;
                done_status<=0;done_detail<=0;done_tag<=cmd_tag;request_sequence<=0;key_index<=0;state<=ID_COMPARE;
                if(cmd_kind==0)begin
                    resident_valid<=0;resident_loading<=0;rows_valid<=0;a_valid<=0;
                    param_valid<=0;shadow_valid<=0;aux_coeff<=0;
                end
                if(cmd_kind==1)begin
                    resident_loading<=0;rows_valid<=0;a_valid<=0;row_seen<=0;prior_rows_valid<=rows_valid;
                end
                if(cmd_kind==2)a_valid<=0;
            end
            if(offer&&mem_req_ready)begin offer<=0;inflight<=1;received<=0;rsp_seen<=0;end
            if(mem_rf)begin
                received<=received+1;read_bytes<=read_bytes+32;
                if(!aborting)begin
                    if(mem_r_last!=(received_after=={1'b0,offered_beats}) || received>=offered_beats)fail(32'h101);
                    else if(kind==1&&!resident_loading)begin
                        rx_valid<=1;rx_data<=mem_r_data;rx_offset<=region_done+({27'd0,received}<<5);row_rx_pair<=0;
                    end
                    else if(kind!=1)begin rx_valid<=1;rx_data<=mem_r_data;rx_offset<=region_done+({27'd0,received}<<5);end
                end
            end
            if(row_rx_write)begin
                if(row_rx_pair==3)rx_valid<=0;
                else row_rx_pair<=row_rx_pair+1;
            end
            if(step&&state==ROW_WRITE)begin
                if(row_rd_issue)row_read_issue<=row_read_issue+1;
                if(row_stage_v_a&&row_stage_v_b)begin row_prev_data<={row_stage_q_b,row_stage_q_a};row_prev_valid<=1;end
            end
            if(feature_consume)begin
                if(feature_row_left<=8)begin
                    feature_word<=0;
                    if(feature_y+1>=hin)begin feature_y<=0;feature_ci<=feature_ci+1;end
                    else feature_y<=feature_y+1;
                end else feature_word<=feature_word+2;
            end
            if(mem_df)begin
                inflight<=0;rsp_seen<=1;
                if(mem_rsp_tag!=offered_tag || mem_rsp_status!=0 || received_after!={1'b0,offered_beats})begin reset_required<=1;fail({24'h000001,4'h2,mem_rsp_status});end
            end
            if(active&&!aborting&&!cancel_request&&run_ce)begin
                case(state)
                ID_COMPARE:begin
                    param_equal_chunks[key_index]<=(key_word==(key_written[0]?key_q[0+:32]:32'd0));
                    row_equal_chunks[key_index]<=(key_word==(key_written[1]?key_q[32+:32]:32'd0));
                    resident_equal_chunks[key_index]<=(key_word==(key_written[2]?key_q[64+:32]:32'd0));
                    if(key_index==0)begin
                        feature_plane_words<=mul15({6'd0,hin[8:0]},{2'd0,spatial_words});
                        cmd_cin_rows<=mul15({8'd0,cin[6:0]},hin[8:0]);
                        full_rows<=mul15({8'd0,((cin[6:0]+7'd15)>>4)},hin[8:0]);
                    end
                    if(key_index==31)state<=GEO2;
                    else key_index<=key_index+5'd1;
                end
                KEY_SAVE:if(epoch==saved_epoch)begin
                    if(key_index==31)begin
                        key_written<=key_written|key_save_mask;
                        if(key_save_mask==1)begin
                            // Publish loaded channels with the completed identity key.
                            // Skipping the bound scan must not leave the layer's
                            // parameter-valid mask empty or publish before cancel.
                            if(TRUSTED_MODEL && (code==1||code==2))
                                shadow_valid<=64'hffffffffffffffff>>(64-co_count);
                            param_valid<=1;finish(0,0);
                        end
                        else if(key_save_mask==4)begin
                            resident_valid<=1;resident_src<=saved_src;resident_epoch<=saved_epoch;
                            resident_loading<=0;state<=FEATURE_READY;
                        end else state<=key_return;
                    end else key_index<=key_index+5'd1;
                end
                GEO2:begin
                    feature_logical<=mul23(cmd_cin_rows,win[8:0]);
                    full_bank_words<=mul17(full_rows,{2'd0,spatial_words});
                    state<=CHECK;
                end
                CHECK:begin
                    if(saved_epoch==0 || saved_src[4:0]!=0 || saved_workspace[4:0]!=0)finish(10,1);
                    else if(kind==0)begin
                        if(code_full==1||code_full==2)begin
                            if(cin_full==0||cin_full>64||co_full==0||co_full>64||op[896+:32]==0||op[896+:32]>128 || !(src_dtype_full==1||src_dtype_full==2))finish(12,2);
                            else if(op[608+:32]==32'hffffffff||op[640+:32]==32'hffffffff||op[672+:32]==32'hffffffff)finish(11,3);
                            else begin
                                k_count<=op[896+:32];co_count<=co_full;cin_count<=cin_full;
                                w_logical<=logical_w;w_alloc<=slot_w;b_logical<=co_full<<2;b_alloc<=slot_b;q_logical<=co_full<<3;q_alloc<=slot_q;
                                part<=0;state<=PARAM_SETUP;
                            end
                        end else if(code_full==3||code_full==8)begin
                            if(op[704+:32]==32'hffffffff)finish(11,4);
                            else begin part<=3;state<=PARAM_SETUP;end
                        end else finish(0,0);
                    end else if(kind==1)begin
                        rolling<=can_roll;rolling_shift<=op[512+:2];
                    if(can_roll)begin
                        if(op[512+:32]==1)begin
                            row_slot[0]<=row_slot[1];row_slot[1]<=row_slot[2];row_slot[2]<=row_slot[0];
                            for(b=0;b<64;b=b+1)begin
                                row_present[3*b]<=row_present[3*b+1];row_present[3*b+1]<=row_present[3*b+2];row_present[3*b+2]<=0;
                            end
                        end else begin
                            row_slot[0]<=row_slot[2];row_slot[1]<=row_slot[0];row_slot[2]<=row_slot[1];
                            for(b=0;b<64;b=b+1)begin row_present[3*b]<=row_present[3*b+2];row_present[3*b+1]<=0;row_present[3*b+2]<=0;end
                        end
                    end else begin row_slot[0]<=0;row_slot[1]<=1;row_slot[2]<=2;row_present<=0;end
                        if(!(code_full==1||code_full==2||code_full==4||code_full==5)||!(src_dtype_full==1||src_dtype_full==2)||cin_full==0||cin_full>64||hin_full==0||hin_full>320||win_full==0||win_full>320 ||
                           (code_full!=5&&(kh_full==0||kh_full>3||kw_full==0||kw_full>3)) || saved_y>=op[384+:32])finish(12,5);
                        else if(op[768+:32]!=feature_logical)finish(12,11);
                        else if((code_full==1||code_full==2)&&(!param_valid||!(&param_equal_chunks)||param_workspace!=saved_workspace||param_epoch!=saved_epoch))finish(13,10);
                        else begin
                            row_code<=op[0+:4];row_cin<=op[256+:7];row_win<=op[352+:9];row_hin<=op[320+:9];
                            row_kh<=op[448+:2];row_kw<=op[480+:2];row_sw<=op[544+:32]==2?2:1;row_pl<=op[584+:8];
                            key_index<=0;key_save_mask<=2;key_written[1]<=0;state<=KEY_SAVE;row_src<=saved_src;row_epoch<=saved_epoch;cached_y<=saved_y;row_word_count<=(win_full+3)>>2;ci_index<=0;ky_index<=0;
                            resident_mode<=feature_fits;cached_row_words<=spatial_words;
                            cached_group_stride<=feature_fits?feature_plane_words:
                                ({8'd0,spatial_words}<<1)+{8'd0,spatial_words};
                            if(feature_fits)begin
                                if(resident_hit)key_return<=FEATURE_READY;
                                else begin
                                    resident_valid<=0;resident_loading<=1;feature_ci<=0;feature_y<=0;feature_word<=0;
                                    pbase<=saved_src;pbytes<=(op[768+:32]+31)&32'hffffffe0;region_done<=0;key_return<=PLAN;
                                end
                            end else begin resident_valid<=0;key_return<=ROW_OFFSET;end
                        end
                    end else if(kind==2)begin
                        if(!rows_valid||!(&row_equal_chunks)||saved_src!=row_src||saved_epoch!=row_epoch||saved_y!=cached_y)finish(13,6);
                        else if(code_full!=1||saved_m==0||saved_m>16||{1'b0,saved_x}+saved_m>op[416+:32]||op[896+:32]==0||op[896+:32]>128)finish(12,7);
                        else begin k_count<=op[896+:32];state<=BUILD_SETUP;end
                    end else finish(21,8);
                end
                PARAM_SETUP:begin
                    region_done<=0;rx_valid<=0;received<=0;
                    if(part==0)begin pbase<=saved_workspace+op[608+:32];pbytes<=w_alloc;weight_block<=0;weight_krow<=0;end
                    else if(part==1)begin pbase<=saved_workspace+op[640+:32];pbytes<=b_alloc;end
                    else if(part==2)begin pbase<=saved_workspace+op[672+:32];pbytes<=q_alloc;end
                    else begin pbase<=(saved_workspace+op[704+:32])&32'hffffffe0;pbytes<=32;end
                    state<=PLAN;
                end
                ROW_OFFSET:begin
                    if((rolling&&ky_index+rolling_shift<3)||input_y<0||input_y>=$signed({1'b0,hin}))state<=ROW_NEXT;
                    else begin row_offset_hold<=row_offset;state<=ROW_SETUP;end
                end
                ROW_SETUP:begin
                    row_start<=next_row_start;row_phase<={27'd0,next_row_start[4:0]};
                    pbase<=next_row_aligned;pbytes<=next_row_bytes;region_done<=0;state<=PLAN;
                end
                PLAN:begin
                    if(pbase[4:0]!=0 || pbytes==0 || pbytes[4:0]!=0 || {1'b0,pbase}+{1'b0,pbytes}>33'h040000000 || planned==0)finish(8,9);
                    else begin
                        next_region_done<=planned_region_end[22:0];region_more<=planned_region_end<{9'd0,pbytes};
                        offered_offset<=actual_cursor;offered_beats<=planned;offered_tag<=tag^request_sequence;request_sequence<=request_sequence+1;
                        offer<=1;received<=0;rsp_seen<=0;state<=TRANSFER;
                    end
                end
                TRANSFER:begin
                    if(kind==0&&rx_valid)begin
                        rx_valid<=0;
                        if(part==0)begin
                            // Each 32-byte response is two full 16-Co rows.
                            // Both contributions for a Co are accumulated together.
                            // Each unrolled Co owns one sumabs register. An odd K may put
                            // the second row in the next block; merge only matching rows.
                            if(!TRUSTED_MODEL)begin
                                for(b=0;b<64;b=b+1)begin
                                    if(b<co_count && rx_offset<w_logical && weight_block==(b/16))
                                        sumabs[b]<=next_sum_vector[14*(b%16)+:14];
                                    if(b<co_count && rx_offset+14'd16<w_logical && weight_cross &&
                                       ({1'b0,weight_block}+3'd1)==(b/16))
                                        sumabs[b]<={6'd0,absw(rx_data[128+8*(b%16)+:8])};
                                end
                            end
                            if(k_count==1)begin weight_block<=weight_block+2;weight_krow<=0;end
                            else if(weight_krow+2>=k_count)begin weight_block<=weight_block+1;weight_krow<=weight_krow+2-k_count;end
                            else weight_krow<=weight_krow+2;
                        end else if(part==1||part==2)begin
                            // Grouped LUTRAM performs the same parameter writes.
                        end else begin
                            if(code==3)aux_coeff<={aux_v2,aux_v1,aux_v0};
                            else aux_coeff<={32'd0,aux_v1,aux_v0};
                        end
                        if(!TRUSTED_MODEL && admission_error!=0)fail(admission_error);
                    end
                    if(rsp_seen&&!inflight&&!rx_valid&&!b_busy&&!row_stage_busy)begin
                        if(region_more)begin region_done<=next_region_done;state<=PLAN;end
                        else if(kind==1)begin
                            if(resident_loading)state<=FEATURE_DRAIN;
                            else begin row_write_word<=0;row_read_issue<=0;row_prev_valid<=0;state<=ROW_WRITE;end
                        end
                        else state<=PARAM_NEXT;
                    end
                end
                PARAM_NEXT:begin
                    if(part<2)begin part<=part+1;state<=PARAM_SETUP;end
                    else if(part==2)begin
                        if(TRUSTED_MODEL)begin
                            param_workspace<=saved_workspace;param_epoch<=saved_epoch;
                            key_index<=0;key_save_mask<=1;key_written[0]<=0;state<=KEY_SAVE;
                        end else begin
                            check_co<=0;state<=PARAM_BOUND_FETCH;
                        end
                    end
                    else begin param_workspace<=saved_workspace;param_epoch<=saved_epoch;key_index<=0;key_save_mask<=1;key_written[0]<=0;state<=KEY_SAVE;end
                end
                PARAM_BOUND_FETCH:begin
                    bound_bias<=bias_read[check_co[2:0]];bound_sum<=sumabs[check_co];state<=PARAM_BOUND;
                end
                PARAM_BOUND:begin
                    abs_bias=bound_bias[31]?(~bound_bias+32'd1):bound_bias;
                    bound_activation=src_dtype==2?({8'd0,bound_sum}<<7)-{8'd0,bound_sum}:
                        ({8'd0,bound_sum}<<8)-{8'd0,bound_sum};
                    bound={1'b0,abs_bias}+{11'd0,bound_activation};
                    if(bound[32]||bound[31])fail(32'h208);
                    else begin
                        shadow_valid[check_co]<=1;
                        if(check_co+1>=co_count)begin param_workspace<=saved_workspace;param_epoch<=saved_epoch;key_index<=0;key_save_mask<=1;key_written[0]<=0;state<=KEY_SAVE;end
                        else begin check_co<=check_co+1;state<=PARAM_BOUND_FETCH;end
                    end
                end
                FEATURE_DRAIN:if(feature_ci>=cin&&!r_busy)begin
                    key_index<=0;key_save_mask<=4;key_written[2]<=0;state<=KEY_SAVE;
                end
                FEATURE_READY:begin
                    for(b=0;b<3;b=b+1)begin
                        fy=code==5?(saved_y>>1):(saved_y<<(sh==2))-pt+b;
                        resident_yword[b]<=fy>=0&&fy<hin?mul15({{2{fy[12]}},fy},{2'd0,spatial_words}):0;
                        for(fc=0;fc<64;fc=fc+1)row_present[fc*3+b]<=fc<cin&&b<row_effective_kh&&fy>=0&&fy<hin;
                    end
                    rows_valid<=1;finish(0,0);
                end
                ROW_WRITE:if(row_out_valid)begin
                    if(row_write_word+2>=row_word_count)state<=ROW_DRAIN;
                    else row_write_word<=row_write_word+2;
                end
                ROW_DRAIN:if(!r_busy&&!row_stage_busy)begin row_present[ci_index*3+ky_index]<=1;state<=ROW_NEXT;end
                ROW_NEXT:begin
                    if(ky_index+1<row_effective_kh)begin ky_index<=ky_index+1;state<=ROW_OFFSET;end
                    else if(ci_index+1<cin)begin ci_index<=ci_index+1;ky_index<=0;state<=ROW_OFFSET;end
                    else begin rows_valid<=1;finish(0,0);end
                end
                BUILD_SETUP:if(gather_start_ready)state<=GATHER_DRAIN;
                GATHER_DRAIN:if(gather_done_valid)begin
                    if(gather_status!=0||gather_tag!=tag)fail(gather_status!=0?gather_status:32'h301);
                    else state<=A_DRAIN;
                end
                A_DRAIN:if(!a_busy)begin
                    a_valid<=1;finish(0,0);
                end
                default:begin end
                endcase
            end
            if(active&&(cancel_request||epoch!=saved_epoch))fail(32'h401);
            if(epoch!=saved_epoch)begin resident_valid<=0;param_valid<=0;rows_valid<=0;a_valid<=0;shadow_valid<=0;end
            if(aborting)begin
                rx_valid<=0;
                if(!offer&&!inflight&&!a_busy&&!b_busy&&!r_busy&&!row_stage_busy)finish(done_status,done_detail);
            end
            if(active&&(a_conf||b_conf||r_conf||row_stage_conf||a_range||b_range||r_range||row_stage_range))fail(32'h302);
        end
    end

    // spec155: physical identity controls, unchanged cycle/reset semantics.
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_ROW_STAGE_rst_n_buffer(.I0(rst_n),.Z(rg_ROW_STAGE_rst_n));
    (* syn_noprune=1, syn_keep=1, syn_maxfan=64 *) GTP_LUT1 #(.INIT(2'b10)) rg_feature_pack_rst_n_buffer(.I0(rst_n),.Z(rg_feature_pack_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_feature_pack_clear_buffer(.I0(!resident_loading||aborting||cancel_request||epoch!=saved_epoch),.Z(rg_feature_pack_clear));
    (* syn_noprune=1, syn_keep=1, syn_maxfan=64 *) GTP_LUT1 #(.INIT(2'b10)) rg_gather_pipeline_rst_n_buffer(.I0(rst_n),.Z(rg_gather_pipeline_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_gather_pipeline_clear_buffer(.I0(!active||aborting||cancel_request||epoch!=saved_epoch||kind!=2),.Z(rg_gather_pipeline_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_A_rst_n_buffer(.I0(rst_n),.Z(rg_A_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_B_rst_n_buffer(.I0(rst_n),.Z(rg_B_rst_n));
    (* syn_noprune=1, syn_keep=1, syn_maxfan=64 *) GTP_LUT1 #(.INIT(2'b10)) rg_ROI_rst_n_buffer(.I0(rst_n),.Z(rg_ROI_rst_n));
endmodule
