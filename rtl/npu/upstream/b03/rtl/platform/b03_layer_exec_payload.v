// Complete general spatial layer: full-row ROI, actual SIMD Dense/DW,
// shared exact quantization, E1 output rows, and masked verified DDR stores.
module b03_layer_exec_payload #(
    // CPU-post board mode keeps transport/identity checks but omits the
    // per-array conflict/range/fault aggregation, which is diagnostic only
    // after the graph is validated and improves the critical path.
    parameter integer ENABLE_RUNTIME_DIAGNOSTICS = 1,
    parameter integer TRUSTED_MODEL = 0,
    parameter integer M_LANES = 16,
    // Board minimum mode may serialize the exact quantizer to one physical
    // arithmetic lane.  The default retains the upstream two-lane schedule.
    parameter integer QUANTIZER_LANES = 2
)(
    input wire clk,rst_n,run_ce,cancel_request,
    input wire start_valid,output wire start_ready,input wire [1023:0] op_words,
    input wire preflight,input wire [31:0] workspace_base,src0_base,src1_base,dst_base,epoch,tag,
    output reg done_valid,input wire done_ready,
    output reg [31:0] done_status,done_detail,done_tag,done_op_id,output reg [63:0] cycles,
    output wire mem_req_valid,input wire mem_req_ready,output wire mem_req_write,mem_req_verify,
    output wire [31:0] mem_req_offset,mem_req_tag,output wire [4:0] mem_req_beats,output wire [2:0] mem_req_client,
    output wire mem_w_valid,input wire mem_w_ready,output wire [255:0] mem_w_data,
    output wire [31:0] mem_w_strb,output wire mem_w_last,
    input wire mem_r_valid,output wire mem_r_ready,input wire [255:0] mem_r_data,input wire mem_r_last,
    input wire mem_rsp_valid,output wire mem_rsp_ready,input wire [3:0] mem_rsp_status,input wire [31:0] mem_rsp_tag,
    output wire busy,output wire [7:0] debug_stage,
    output reg [31:0] stat_mac_vectors,stat_quant_groups,stat_rows
);
    localparam IDLE=0,CHECK=1,PCMD=2,PWAIT=3,ROWCMD=4,ROWWAIT=5,ACMD=6,AWAIT=7,
        DINIT=8,DRUN=9,DDRAIN=10,QDENSE=11,QDRAIN=12,DWCLR=13,DWRUN=14,
        POOLRUN=15,PV0=16,PV1=17,STORESTART=18,STOREWAIT=19,NEXTROW=20,VSTART=21,VWAIT=22,HELD=23,TILECAP=24,ROWFINISH=25;
    reg [7:0] state;reg active,saved_preflight;
    // Decode once on the same accepted task edge as the full op snapshot.
    (* syn_keep=1 *) reg is_dense_op,is_dw_op;
    reg [1023:0] op;reg [31:0] workspace,src0,src1,dst,saved_epoch,saved_tag;
    wire [31:0] code=op[0+:32],sdt=op[160+:32],ddt=op[224+:32];
    wire [31:0] cin_full=op[256+:32],co_full=op[288+:32],hin_full=op[320+:32],win_full=op[352+:32],hout_full=op[384+:32],wout_full=op[416+:32];
    wire [6:0] cin=cin_full[6:0],co=co_full[6:0];
    wire [8:0] hin=hin_full[8:0],win=win_full[8:0],hout=hout_full[8:0],wout=wout_full[8:0];
    wire [31:0] kh=op[448+:32],kw=op[480+:32],kcount_full=op[896+:32],opid=op[928+:32];
    wire [7:0] kcount=kcount_full[7:0];
    wire [31:0] element_bytes=ddt>=3?32'd2:32'd1;
    reg [9:0] row_bytes_saved;
    wire [9:0] row_bytes=row_bytes_saved;
    wire [7:0] row_words=(row_bytes+10'd3)>>2;
    wire [18:0] plane_bytes=mul9n(row_bytes,hout);
    reg [8:0] y,x;reg [6:0] co_base;reg [4:0] m_count;
    reg [8:0] tile_y0,tile_rows_cap,tile_rows_actual;
    reg [12:0] tile_byte_offset;
    reg [12:0] tile_plane_bytes;reg [10:0] tile_plane_words;
    wire [12:0] next_tile_bytes=tile_plane_bytes+{3'd0,row_bytes};
    wire [10:0] next_tile_words=(next_tile_bytes+13'd3)>>2;
    wire [4:0] tile_co_groups=({1'b0,co}+8'd3)>>2;
    reg [15:0] tile_number;reg [9:0] q_issued,q_retired;
    reg [7:0] k_issued,k_returned;reg [3:0] tap_issue,tap_returned;
    reg [8:0] dw_issue_x,dw_return_x;reg dw_issue_done,dw_half;
    // One full 16Co result decouples the DW last-tap retirement from the two
    // Q8 halves. K9 can continue at one accepted tap per working cycle.
    reg dw_q_valid;reg [511:0] dw_q_psum;reg [127:0] dw_q_tag;
    reg [127:0] pool_acc,pool_value;
    wire [6:0] co_remaining=co-co_base;
    wire [15:0] co_mask=16'hffff>>(5'd16-(co_remaining>7'd16 ? 5'd16 : co_remaining[4:0]));
    wire [15:0] m_mask=16'hffff>>(16-m_count);
    wire [127:0] tile_tag={saved_tag,saved_epoch,opid,16'd0,tile_number};
    wire spatial=code==1||code==2||code==4||code==5;
    wire dw_out_valid,dw_out_ready,dw_advance;
    wire core_ce=run_ce&&(!is_dw_op||!dw_out_valid||dw_out_ready);
    wire step=rst_n&&core_ce;
    wire q_step=rst_n&&run_ce;
    // Co group changes enter DWCLR before any DWRUN input can be accepted.
    reg [15:0] dw_input_mask;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)dw_input_mask<=0;
        else if(state==DWCLR&&core_ce)dw_input_mask<=co_mask;
    end
    wire clear_math=state==CHECK||!active;
    assign busy=active||done_valid;assign debug_stage=state;
    assign start_ready=rst_n&&state==IDLE&&!done_valid&&!cancel_request;
    function [18:0] mul9n;input [9:0] a;input [8:0] b;
 begin mul9n=a*b;end endfunction
    function [15:0] mul5n;input [10:0] a;input [4:0] b;
 begin mul5n=a*b;end endfunction
    // Exact capacity identity for unsigned n[10:0], groups[4:0]:
    // n*groups<=1024 iff n<=floor(1024/groups), with groups=0 unbounded.
    function [10:0] capacity_words;input [4:0] groups;
    begin case(groups)
        5'd0:capacity_words=11'd2047;
        5'd1:capacity_words=11'd1024;
        5'd2:capacity_words=11'd512;
        5'd3:capacity_words=11'd341;
        5'd4:capacity_words=11'd256;
        5'd5:capacity_words=11'd204;
        5'd6:capacity_words=11'd170;
        5'd7:capacity_words=11'd146;
        5'd8:capacity_words=11'd128;
        5'd9:capacity_words=11'd113;
        5'd10:capacity_words=11'd102;
        5'd11:capacity_words=11'd93;
        5'd12:capacity_words=11'd85;
        5'd13:capacity_words=11'd78;
        5'd14:capacity_words=11'd73;
        5'd15:capacity_words=11'd68;
        5'd16:capacity_words=11'd64;
        5'd17:capacity_words=11'd60;
        5'd18:capacity_words=11'd56;
        5'd19:capacity_words=11'd53;
        5'd20:capacity_words=11'd51;
        5'd21:capacity_words=11'd48;
        5'd22:capacity_words=11'd46;
        5'd23:capacity_words=11'd44;
        5'd24:capacity_words=11'd42;
        5'd25:capacity_words=11'd40;
        5'd26:capacity_words=11'd39;
        5'd27:capacity_words=11'd37;
        5'd28:capacity_words=11'd36;
        5'd29:capacity_words=11'd35;
        5'd30:capacity_words=11'd34;
        5'd31:capacity_words=11'd33;
        default:capacity_words=11'd0;
    endcase end endfunction
    function [127:0] qtag;input[31:0] xx;input[15:0] cc;begin qtag={saved_tag,opid,{7'd0,y},cc,xx};end endfunction
    function [7:0] mask8;input[31:0] cc;integer n;begin for(n=0;n<8;n=n+1)mask8[n]=cc[31:7]==0&&({1'b0,cc[6:0]}+n[7:0])<{1'b0,co};end endfunction
    task finish;input[31:0] s,d;begin
        done_valid<=1;done_status<=s;done_detail<=d;done_tag<=saved_tag;done_op_id<=opid;active<=0;state<=HELD;
    end endtask

    wire input_cmd_ready,input_done_valid,input_param_valid,input_rows_valid,input_a_valid,input_busy,input_reset;
    wire [31:0] input_status,input_detail,input_done_tag,input_cycles,input_read_bytes;
    wire [7:0] input_state;wire [255:0] bias_flat,mult_flat;wire [47:0] shift_flat;wire [2:0] q_param_group;
    wire [63:0] shadow_valid;wire [95:0] aux_coeff;
    wire input_cmd_valid=state==PCMD||state==ROWCMD||state==ACMD;
    wire [1:0] input_cmd_kind=state==PCMD?2'd0:state==ROWCMD?2'd1:2'd2;
    wire a_req_ready,b_req_ready,dw_req_ready,a_rsp_valid,b_rsp_valid,dw_rsp_valid;
    wire [127:0] a_rsp_data,b_rsp_data,dw_rsp_data;wire [31:0] a_rsp_tag,b_rsp_tag,dw_rsp_tag;
    wire a_rsp_error,b_rsp_error,dw_rsp_error;
    wire dense_issue=state==DRUN&&k_issued<kcount;
    wire dw_issue=state==DWRUN&&!dw_issue_done;
    wire pool_issue=state==POOLRUN&&tap_issue<(code==5?1:4);
    // Both paired cache ports accept together; no unpaired K token can escape.
    wire a_req_valid=dense_issue&&b_req_ready;
    wire b_req_valid=(dense_issue&&a_req_ready)||(dw_issue&&dw_req_ready);
    wire dw_req_valid=(dw_issue&&b_req_ready)||pool_issue;
    wire [9:0] b_group_row=(co_base[4]?{2'd0,kcount}:10'd0)+(co_base[5]?{1'd0,kcount,1'b0}:10'd0);
    wire [9:0] b_req_row=b_group_row+(code==2?{6'd0,tap_issue}:{2'd0,k_issued});
    wire [31:0] read_tag=code==1?{24'd0,k_issued}:code==2?{19'd0,dw_issue_x,tap_issue}:{19'd0,x,tap_issue};

    wire i_req_valid,i_req_ready,i_req_write,i_req_verify,i_w_valid,i_w_ready,i_w_last,i_r_valid,i_r_ready,i_r_last,i_rsp_valid,i_rsp_ready;
    wire [31:0] i_req_offset,i_req_tag,i_w_strb,i_rsp_tag;wire [4:0] i_req_beats;wire [2:0] i_req_client;wire [3:0] i_rsp_status;
    wire [255:0] i_w_data,i_r_data;

    // spec155: declare identity outputs before their consumer instances.
    wire rg_input_path_rst_n;
    wire rg_dense_rst_n;
    wire rg_dense_clear;
    wire rg_depthwise_rst_n;
    wire rg_depthwise_clear;
    wire rg_quantizer_rst_n;
    wire rg_quantizer_clear;
    wire rg_O_rst_n;
    wire rg_row_writer_rst_n;
    wire rg_vector_path_rst_n;
    b03_model_input_payload #(.LATCH_OP(0),.LATCH_EPOCH(0),.TRUSTED_MODEL(TRUSTED_MODEL)) input_path(
        .clk(clk),.rst_n(rg_input_path_rst_n),.run_ce(core_ce),.cancel_request(cancel_request),
        .cmd_valid(input_cmd_valid),.cmd_ready(input_cmd_ready),.cmd_kind(input_cmd_kind),.op_words(op),
        .workspace_base(workspace),.resolved_src_base(src0),.epoch(saved_epoch),.cmd_tag(saved_tag),
        .row_y(y),.x_begin(x),.m_count(m_count),
        .done_valid(input_done_valid),.done_ready(state==PWAIT||state==ROWWAIT||state==AWAIT),
        .done_status(input_status),.done_detail(input_detail),.done_tag(input_done_tag),
        .param_valid(input_param_valid),.rows_valid(input_rows_valid),.a_valid(input_a_valid),
        .param_group(q_param_group),.bias_flat(bias_flat),.mult_flat(mult_flat),.shift_flat(shift_flat),.shadow_valid(shadow_valid),.aux_coeff(aux_coeff),
        .a_req_valid(a_req_valid),.a_req_ready(a_req_ready),.a_req_row({2'd0,k_issued}),.a_req_tag(read_tag),
        .a_rsp_valid(a_rsp_valid),.a_rsp_data(a_rsp_data),.a_rsp_tag(a_rsp_tag),.a_rsp_error(a_rsp_error),
        .b_req_valid(b_req_valid),.b_req_ready(b_req_ready),.b_req_row(b_req_row),.b_req_tag(read_tag),
        .b_rsp_valid(b_rsp_valid),.b_rsp_data(b_rsp_data),.b_rsp_tag(b_rsp_tag),.b_rsp_error(b_rsp_error),
        .dw_req_valid(dw_req_valid),.dw_req_ready(dw_req_ready),.dw_req_tap(tap_issue),
        .dw_req_ox(code==2?dw_issue_x:x),.dw_req_co_base(co_base),.dw_req_tag(read_tag),
        .dw_rsp_valid(dw_rsp_valid),.dw_rsp_data(dw_rsp_data),.dw_rsp_tag(dw_rsp_tag),.dw_rsp_error(dw_rsp_error),
        .mem_req_valid(i_req_valid),.mem_req_ready(i_req_ready),.mem_req_write(i_req_write),.mem_req_verify(i_req_verify),
        .mem_req_offset(i_req_offset),.mem_req_tag(i_req_tag),.mem_req_beats(i_req_beats),.mem_req_client(i_req_client),
        .mem_w_valid(i_w_valid),.mem_w_ready(i_w_ready),.mem_w_data(i_w_data),.mem_w_strb(i_w_strb),.mem_w_last(i_w_last),
        .mem_r_valid(i_r_valid),.mem_r_ready(i_r_ready),.mem_r_data(i_r_data),.mem_r_last(i_r_last),
        .mem_rsp_valid(i_rsp_valid),.mem_rsp_ready(i_rsp_ready),.mem_rsp_status(i_rsp_status),.mem_rsp_tag(i_rsp_tag),
        .busy(input_busy),.reset_required(input_reset),.debug_state(input_state),.cycles(input_cycles),.read_bytes(input_read_bytes));

    wire array_init_ready,array_ready,array_busy,array_active,array_retire;
    wire [8191:0] acc_flat;wire [3:0] array_fault;wire [7:0] array_fault_lane,array_retire_k;wire [127:0] array_retire_tag;
    wire dense_return=(state==DRUN||state==DDRAIN)&&a_rsp_valid&&b_rsp_valid;
    b03_array_apmacc_rowctrl #(.ENABLE_DIAGNOSTICS(ENABLE_RUNTIME_DIAGNOSTICS),.M_LANES(M_LANES)) dense(
        .clk(clk),.rst_n(rg_dense_rst_n),.clear(rg_dense_clear),.run_ce(core_ce),
        .init_valid(state==DINIT),.init_ready(array_init_ready),.init_m_mask(m_mask),.init_co_mask(co_mask),
        .init_signed(sdt==2),.init_tag(tile_tag),.zero_valid(1'b0),.zero_ready(),
        .load_valid(1'b0),.load_ready(),.load_index(6'd0),.load_data(128'd0),.pipe_clear(1'b0),
        .in_valid(dense_return),.in_ready(array_ready),.in_a(a_rsp_data),.in_b(b_rsp_data),
        .in_k(a_rsp_tag[7:0]),.in_tag(tile_tag),.acc_flat(acc_flat),.busy(array_busy),.active(array_active),
        .fault(array_fault),.fault_lane(array_fault_lane),.retire_valid(array_retire),.retire_k(array_retire_k),.retire_tag(array_retire_tag));

    wire [511:0] dw_psum;wire [15:0] dw_mask;wire [127:0] dw_tag;
    wire dw_ready,dw_busy;wire [3:0] dw_fault,dw_fault_lane;
    wire dw_return=state==DWRUN&&dw_rsp_valid&&b_rsp_valid;
    b03_full_dw16_parallelfault #(.ENABLE_DIAGNOSTICS(ENABLE_RUNTIME_DIAGNOSTICS)) depthwise(
        .clk(clk),.rst_n(rg_depthwise_rst_n),.clear(rg_depthwise_clear),.run_ce(run_ce),
        .in_valid(dw_return&&step),.in_ready(dw_ready),.input_signed(sdt==2),.in_mask(dw_input_mask),
        .in_a(dw_rsp_data),.in_w(b_rsp_data),.in_k(dw_rsp_tag[3:0]),.in_k_count(kcount[3:0]),
        .in_tag({saved_tag,opid,{7'd0,y},{9'd0,co_base},{23'd0,dw_rsp_tag[12:4]}}),
        .out_valid(dw_out_valid),.out_ready(dw_out_ready),.out_psum(dw_psum),.out_mask(dw_mask),.out_tag(dw_tag),
        .advance(dw_advance),.busy(dw_busy),.fault(dw_fault),.fault_lane(dw_fault_lane));

    wire v_q_valid,v_q_ready,v_q_add,v_q_out_valid,v_q_out_ready;
    wire [7:0] v_q_mask,v_q_out_mask;wire [255:0] v_q_psum,v_q_psum_b,v_q_bias,v_q_ma,v_q_mb;
    wire [1:0] v_q_dtype;wire [47:0] v_q_shift;wire [127:0] v_q_tag,v_q_out_values,v_q_out_tag;wire [23:0] v_q_out_error;
    reg q_in_valid,q_in_add;reg [7:0] q_in_mask;reg [255:0] q_psum,q_psum_b,q_bias,q_ma,q_mb;
    reg [1:0] q_dtype;reg [47:0] q_shift;reg [127:0] q_in_tag;
    wire q_in_ready,q_in_capacity,q_out_valid,q_out_ready,q_advance,q_busy;wire [7:0] q_out_mask;
    wire [127:0] q_out_values,q_out_tag;wire [23:0] q_error;
    wire [1:0] q_out_dtype;wire q_out_add;
    wire q_half=state==DWRUN?dw_half:q_issued[0];
    assign q_param_group={co_base[5:4],q_half};
    wire [6:0] q_co={co_base[6:4],q_half,3'b000};
    wire [255:0] selected_acc,selected_bias,selected_mult;
    wire [47:0] selected_shift;
    genvar qlane,qrow,qgroup;
    generate for(qlane=0;qlane<8;qlane=qlane+1)begin:qselect
        wire [767:0] col;
        for(qrow=0;qrow<16;qrow=qrow+1)begin:rows
            assign col[24*(2*qrow)+:24]=acc_flat[32*(16*qrow+qlane)+:24];
            assign col[24*(2*qrow+1)+:24]=acc_flat[32*(16*qrow+qlane+8)+:24];
        end
        wire [23:0] av=col[24*q_issued[4:0]+:24];
        assign selected_acc[32*qlane+:32]={{8{av[23]}},av};
        assign selected_bias[32*qlane+:32]=bias_flat[32*qlane+:32];
        assign selected_mult[32*qlane+:32]=mult_flat[32*qlane+:32];
        assign selected_shift[6*qlane+:6]=shift_flat[6*qlane+:6];
    end endgenerate
    always @*begin
        // Payload selection depends only on the accepted operation mode.
        // Inactive payload bits are unqualified; the original valid/tag/mask
        // conditions below still exclusively control token acceptance.
        q_psum_b=0;q_mb=0;q_in_add=0;q_dtype=ddt[1:0]-1;
        q_bias=selected_bias;q_ma=selected_mult;q_shift=selected_shift;
        if(is_dense_op)q_psum=selected_acc;
        else if(is_dw_op)q_psum=dw_half?dw_q_psum[256+:256]:dw_q_psum[0+:256];
        else begin
            q_psum=v_q_psum;q_psum_b=v_q_psum_b;q_bias=v_q_bias;
            q_ma=v_q_ma;q_mb=v_q_mb;q_shift=v_q_shift;q_dtype=v_q_dtype;q_in_add=v_q_add;
        end
        q_in_valid=0;q_in_mask=0;q_in_tag=0;
        if(state==QDENSE&&q_issued<({5'd0,m_count}<<1))begin
            q_in_valid=1;q_in_mask=mask8({25'd0,q_co});
            q_in_tag=qtag({23'd0,x}+{28'd0,q_issued[4:1]},{9'd0,q_co});
        end else if(state==DWRUN&&dw_q_valid)begin
            q_in_valid=1;q_in_mask=mask8({25'd0,q_co});
            q_in_tag={dw_q_tag[127:48],{9'd0,q_co},dw_q_tag[31:0]};
        end else if(state==VWAIT)begin
            q_in_valid=v_q_valid;q_in_mask=v_q_mask;q_in_tag=v_q_tag;
        end
    end
    assign dw_out_ready=state==DWRUN&&(!dw_q_valid||(dw_half&&q_in_capacity));
    assign q_out_ready=state==VWAIT?v_q_out_ready:1'b1;
    assign v_q_ready=state==VWAIT&&q_in_ready;
    assign v_q_out_valid=state==VWAIT&&q_out_valid;assign v_q_out_mask=q_out_mask;
    assign v_q_out_values=q_out_values;assign v_q_out_tag=q_out_tag;assign v_q_out_error=q_error;
    generate if (QUANTIZER_LANES == 1) begin : g_quantizer_tdm1
    b03_quant8_tdm1 quantizer(
        .clk(clk),.rst_n(rg_quantizer_rst_n),.clear(rg_quantizer_clear),.run_ce(run_ce),
        .in_valid(q_in_valid),.in_ready(q_in_ready),.in_capacity(q_in_capacity),.in_mask(q_in_mask),.in_psum(q_psum),.in_psum_b(q_psum_b),
        .in_add(q_in_add),.in_dtype(q_dtype),.in_bias(q_bias),.in_multiplier(q_ma),.in_multiplier_b(q_mb),.in_shift(q_shift),.in_tag(q_in_tag),
        .out_valid(q_out_valid),.out_ready(q_out_ready),.out_mask(q_out_mask),.out_values(q_out_values),.out_dtype(q_out_dtype),.out_add(q_out_add),
        .out_error(q_error),.out_tag(q_out_tag),.advance(q_advance),.busy(q_busy));
    end else begin : g_quantizer_tdm2
    b03_quant8_tdm2 quantizer(
        .clk(clk),.rst_n(rg_quantizer_rst_n),.clear(rg_quantizer_clear),.run_ce(run_ce),
        .in_valid(q_in_valid),.in_ready(q_in_ready),.in_capacity(q_in_capacity),.in_mask(q_in_mask),.in_psum(q_psum),.in_psum_b(q_psum_b),
        .in_add(q_in_add),.in_dtype(q_dtype),.in_bias(q_bias),.in_multiplier(q_ma),.in_multiplier_b(q_mb),.in_shift(q_shift),.in_tag(q_in_tag),
        .out_valid(q_out_valid),.out_ready(q_out_ready),.out_mask(q_out_mask),.out_values(q_out_values),.out_dtype(q_out_dtype),.out_add(q_out_add),
        .out_error(q_error),.out_tag(q_out_tag),.advance(q_advance),.busy(q_busy));
    end endgenerate

    // The complete actual-model row, all Co, is held in four E1 banks.
    reg [3:0] o_req_a,o_req_b,o_we_a,o_we_b;reg [43:0] o_addr_a,o_addr_b;
    reg [127:0] o_data_a,o_data_b;reg [15:0] o_mask_a,o_mask_b;
    wire [127:0] o_q_a,o_q_b;wire [3:0] o_valid_a,o_valid_b;wire o_busy,o_conflict,o_range;
    wire [3:0] store_req_a,store_req_b;wire [43:0] store_addr_a,store_addr_b;wire store_o_ce;
    wire pool_store=state==PV0||state==PV1;
    wire q_store=q_out_valid&&(state==QDENSE||state==QDRAIN||state==DWRUN);
    reg [127:0] store_values;reg [7:0] store_mask;reg [31:0] store_x,store_co;
    integer ol,bank;
    reg [12:0] o_byte;
    reg [10:0] o_plane_word,o_word_a,o_word_b;
    reg [1:0] lane_a;
    reg [2:0] lane_b;
    function [10:0] mul4o;input [10:0] a;input [3:0] b;
 begin mul4o=a*b;end endfunction
    always @*begin
        o_req_a=store_req_a;o_req_b=store_req_b;o_addr_a=store_addr_a;o_addr_b=store_addr_b;
        o_we_a=0;o_we_b=0;o_data_a=0;o_data_b=0;o_mask_a=0;o_mask_b=0;
        store_values=q_out_values;store_mask=q_out_mask;store_x=q_out_tag[31:0];store_co={16'd0,q_out_tag[47:32]};
        if(pool_store)begin
            store_mask=mask8({25'd0,co_base}+(state==PV1?8:0));store_x={23'd0,x};store_co={25'd0,co_base}+(state==PV1?8:0);store_values=0;
            for(ol=0;ol<8;ol=ol+1)store_values[16*ol+:16]={8'd0,pool_value[8*(ol+(state==PV1?8:0))+:8]};
        end
        o_byte=tile_byte_offset+({4'd0,store_x[8:0]}<<(ddt>=3));o_plane_word=o_byte[12:2];
        o_word_a=mul4o(tile_plane_words[10:0],store_co[5:2])+o_plane_word;
        o_word_b=o_word_a+tile_plane_words[10:0];lane_a=0;lane_b=0;
        if((q_store&&q_step)||(pool_store&&step))begin
            o_req_a=0;o_req_b=0;
            // Co group starts are eight-aligned. Each fixed SRAM bank receives
            // one lower and one upper lane after a four-lane rotation.
            for(bank=0;bank<4;bank=bank+1)begin
                lane_a=bank[1:0]-o_plane_word[1:0];lane_b={1'b1,lane_a};
                o_req_a[bank]=store_mask[lane_a];o_we_a[bank]=store_mask[lane_a];
                o_req_b[bank]=store_mask[lane_b];o_we_b[bank]=store_mask[lane_b];
                o_addr_a[11*bank+:11]=o_word_a;o_addr_b[11*bank+:11]=o_word_b;
                o_data_a[32*bank+:32]={16'd0,store_values[16*lane_a+:16]}<<{o_byte[1:0],3'b000};
                o_data_b[32*bank+:32]={16'd0,store_values[16*lane_b+:16]}<<{o_byte[1:0],3'b000};
                o_mask_a[4*bank+:4]=(ddt>=3?4'b0011:4'b0001)<<o_byte[1:0];
                o_mask_b[4*bank+:4]=(ddt>=3?4'b0011:4'b0001)<<o_byte[1:0];
            end
        end
    end
    b03_bank_array_payload #(.BANKS(4),.WIDTH(32),.DEPTH(1024)) O(
        .clk(clk),.rst_n(rg_O_rst_n),.run_ce((state==STORESTART||state==STOREWAIT)?store_o_ce:run_ce),.req_a(o_req_a),.we_a(o_we_a),.req_b(o_req_b),.we_b(o_we_b),
        .addr_a(o_addr_a),.addr_b(o_addr_b),.data_a(o_data_a),.data_b(o_data_b),.mask_a(o_mask_a),.mask_b(o_mask_b),
        .q_a(o_q_a),.q_b(o_q_b),.valid_a(o_valid_a),.valid_b(o_valid_b),.busy(o_busy),.conflict(o_conflict),.range_error(o_range));

    wire store_start_ready,store_done_valid;wire [31:0] store_status,store_detail,store_tag,store_bursts,store_bytes;wire [7:0] store_state;
    wire s_req_valid,s_req_ready,s_req_write,s_req_verify,s_w_valid,s_w_ready,s_w_last,s_r_valid,s_r_ready,s_r_last,s_rsp_valid,s_rsp_ready;
    wire [31:0] s_req_offset,s_req_tag,s_w_strb,s_rsp_tag;wire [4:0] s_req_beats;wire [2:0] s_req_client;wire [3:0] s_rsp_status;
    wire [255:0] s_w_data,s_r_data;
    b03_row_tile_store_rotate row_writer(
        .clk(clk),.rst_n(rg_row_writer_rst_n),.run_ce(run_ce),.cancel_request(cancel_request),
        .start_valid(state==STORESTART),.start_ready(store_start_ready),.dst_base(dst),.plane_bytes({13'd0,plane_bytes}),
        .row_bytes({22'd0,row_bytes}),.row_words({24'd0,row_words}),.co_count(co[6:0]),.row_y(tile_y0),
        .tile_rows(tile_rows_actual),.tile_capacity(tile_rows_cap),.tag(saved_tag),
        .done_valid(store_done_valid),.done_ready(state==STOREWAIT),.done_status(store_status),.done_detail(store_detail),.done_tag(store_tag),
        .o_run_ce(store_o_ce),.o_req_a(store_req_a),.o_req_b(store_req_b),.o_addr_a(store_addr_a),.o_addr_b(store_addr_b),
        .o_q_a(o_q_a),.o_q_b(o_q_b),.o_valid_a(o_valid_a),.o_valid_b(o_valid_b),
        .mem_req_valid(s_req_valid),.mem_req_ready(s_req_ready),.mem_req_write(s_req_write),.mem_req_verify(s_req_verify),
        .mem_req_offset(s_req_offset),.mem_req_tag(s_req_tag),.mem_req_beats(s_req_beats),.mem_req_client(s_req_client),
        .mem_w_valid(s_w_valid),.mem_w_ready(s_w_ready),.mem_w_data(s_w_data),.mem_w_strb(s_w_strb),.mem_w_last(s_w_last),
        .mem_r_valid(s_r_valid),.mem_r_ready(s_r_ready),.mem_r_data(s_r_data),.mem_r_last(s_r_last),
        .mem_rsp_valid(s_rsp_valid),.mem_rsp_ready(s_rsp_ready),.mem_rsp_status(s_rsp_status),.mem_rsp_tag(s_rsp_tag),
        .debug_state(store_state),.bursts(store_bursts),.stored_bytes(store_bytes));

    // Vector engine and memory owner mux are below. No second quantizer/bridge.
    wire vector_start_ready,vector_done_valid,vector_busy;wire [31:0] vector_status,vector_detail,vector_tag,vector_opid;
    wire [63:0] vector_cycles;wire [7:0] vector_stage;
    wire v_req_valid,v_req_ready,v_req_write,v_req_verify,v_w_valid,v_w_ready,v_w_last,v_r_valid,v_r_ready,v_r_last,v_rsp_valid,v_rsp_ready;
    wire [31:0] v_req_offset,v_req_tag,v_w_strb,v_rsp_tag;wire [4:0] v_req_beats;wire [2:0] v_req_client;wire [3:0] v_rsp_status;
    wire [255:0] v_w_data,v_r_data;
    b03_vector_exec_compact vector_path(
        .clk(clk),.rst_n(rg_vector_path_rst_n),.run_ce(run_ce),.cancel_request(cancel_request),
        .start_valid(state==VSTART),.start_ready(vector_start_ready),.op_words(op),
        .workspace_base(workspace),.src0_base(src0),.src1_base(src1),.dst_base(dst),.epoch(saved_epoch),.tag(saved_tag),
        .done_valid(vector_done_valid),.done_ready(state==VWAIT),.done_status(vector_status),.done_detail(vector_detail),
        .done_tag(vector_tag),.done_op_id(vector_opid),.cycles(vector_cycles),.busy(vector_busy),.debug_stage(vector_stage),
        .mem_req_valid(v_req_valid),.mem_req_ready(v_req_ready),.mem_req_write(v_req_write),.mem_req_verify(v_req_verify),
        .mem_req_offset(v_req_offset),.mem_req_tag(v_req_tag),.mem_req_beats(v_req_beats),.mem_req_client(v_req_client),
        .mem_w_valid(v_w_valid),.mem_w_ready(v_w_ready),.mem_w_data(v_w_data),.mem_w_strb(v_w_strb),.mem_w_last(v_w_last),
        .mem_r_valid(v_r_valid),.mem_r_ready(v_r_ready),.mem_r_data(v_r_data),.mem_r_last(v_r_last),
        .mem_rsp_valid(v_rsp_valid),.mem_rsp_ready(v_rsp_ready),.mem_rsp_status(v_rsp_status),.mem_rsp_tag(v_rsp_tag),
        .q_in_valid(v_q_valid),.q_in_ready(v_q_ready),.q_in_mask(v_q_mask),.q_in_psum(v_q_psum),.q_in_psum_b(v_q_psum_b),
        .q_in_bias(v_q_bias),.q_in_multiplier(v_q_ma),.q_in_multiplier_b(v_q_mb),.q_in_add(v_q_add),.q_in_dtype(v_q_dtype),.q_in_shift(v_q_shift),.q_in_tag(v_q_tag),
        .q_out_valid(v_q_out_valid),.q_out_ready(v_q_out_ready),.q_out_mask(v_q_out_mask),.q_out_values(v_q_out_values),.q_out_error(v_q_out_error),.q_out_tag(v_q_out_tag));
    wire select_input=state==PCMD||state==PWAIT||state==ROWCMD||state==ROWWAIT||state==ACMD||state==AWAIT;
    wire select_store=state==STORESTART||state==STOREWAIT;
    wire select_vector=state==VSTART||state==VWAIT;
    assign mem_req_valid=select_input?i_req_valid:select_store?s_req_valid:select_vector?v_req_valid:1'b0;
    assign mem_req_write=select_input?i_req_write:select_store?s_req_write:v_req_write;
    assign mem_req_verify=select_input?i_req_verify:select_store?s_req_verify:v_req_verify;
    assign mem_req_offset=select_input?i_req_offset:select_store?s_req_offset:v_req_offset;
    assign mem_req_tag=select_input?i_req_tag:select_store?s_req_tag:v_req_tag;
    assign mem_req_beats=select_input?i_req_beats:select_store?s_req_beats:v_req_beats;
    assign mem_req_client=select_input?i_req_client:select_store?s_req_client:v_req_client;
    assign mem_w_valid=select_input?i_w_valid:select_store?s_w_valid:select_vector?v_w_valid:1'b0;
    assign mem_w_data=select_input?i_w_data:select_store?s_w_data:v_w_data;
    assign mem_w_strb=select_input?i_w_strb:select_store?s_w_strb:v_w_strb;
    assign mem_w_last=select_input?i_w_last:select_store?s_w_last:v_w_last;
    assign mem_r_ready=select_input?i_r_ready:select_store?s_r_ready:select_vector?v_r_ready:1'b0;
    assign mem_rsp_ready=select_input?i_rsp_ready:select_store?s_rsp_ready:select_vector?v_rsp_ready:1'b0;
    assign i_req_ready=select_input&&mem_req_ready;assign s_req_ready=select_store&&mem_req_ready;assign v_req_ready=select_vector&&mem_req_ready;
    assign i_w_ready=select_input&&mem_w_ready;assign s_w_ready=select_store&&mem_w_ready;assign v_w_ready=select_vector&&mem_w_ready;
    assign i_r_valid=select_input&&mem_r_valid;assign s_r_valid=select_store&&mem_r_valid;assign v_r_valid=select_vector&&mem_r_valid;
    assign i_r_data=mem_r_data;assign s_r_data=mem_r_data;assign v_r_data=mem_r_data;
    assign i_r_last=mem_r_last;assign s_r_last=mem_r_last;assign v_r_last=mem_r_last;
    assign i_rsp_valid=select_input&&mem_rsp_valid;assign s_rsp_valid=select_store&&mem_rsp_valid;assign v_rsp_valid=select_vector&&mem_rsp_valid;
    assign i_rsp_status=mem_rsp_status;assign s_rsp_status=mem_rsp_status;assign v_rsp_status=mem_rsp_status;
    assign i_rsp_tag=mem_rsp_tag;assign s_rsp_tag=mem_rsp_tag;assign v_rsp_tag=mem_rsp_tag;

    reg [127:0] pool_next;
    integer pl;
    always @*begin
        pool_next=pool_acc;
        for(pl=0;pl<16;pl=pl+1)begin
            if(tap_returned==0)pool_next[8*pl+:8]=dw_rsp_data[8*pl+:8];
            else if(sdt==2)begin
                if($signed(dw_rsp_data[8*pl+:8])>$signed(pool_acc[8*pl+:8]))pool_next[8*pl+:8]=dw_rsp_data[8*pl+:8];
            end else if(dw_rsp_data[8*pl+:8]>pool_acc[8*pl+:8])pool_next[8*pl+:8]=dw_rsp_data[8*pl+:8];
        end
    end
    // Private payloads have no asynchronous reset mux. Their owning valid
    // state resets, and every first use follows the corresponding full write.
    // The task still latches all 1024 op bits on the external START handshake.
    always @(posedge clk)begin
        if(rst_n&&start_valid&&start_ready)begin
            op<=op_words;
            row_bytes_saved<=op_words[224+:32]>=3?{op_words[416+:9],1'b0}:{1'b0,op_words[416+:9]};
            workspace<=workspace_base;src0<=src0_base;src1<=src1_base;
            dst<=dst_base;saved_epoch<=epoch;saved_tag<=tag;
        end
        if(rst_n&&active&&state==DWRUN&&q_step&&dw_out_valid&&dw_out_ready&&dw_mask==co_mask)begin
            dw_q_psum<=dw_psum;dw_q_tag<=dw_tag;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;active<=0;saved_preflight<=0;is_dense_op<=0;is_dw_op<=0;
            done_valid<=0;done_status<=0;done_detail<=0;done_tag<=0;done_op_id<=0;cycles<=0;
            y<=0;x<=0;co_base<=0;m_count<=0;tile_number<=0;q_issued<=0;q_retired<=0;
            tile_y0<=0;tile_rows_cap<=0;tile_rows_actual<=0;tile_plane_bytes<=0;tile_plane_words<=0;tile_byte_offset<=0;
            k_issued<=0;k_returned<=0;tap_issue<=0;tap_returned<=0;dw_issue_x<=0;dw_return_x<=0;dw_issue_done<=0;dw_half<=0;
            stat_mac_vectors<=0;stat_quant_groups<=0;stat_rows<=0;
            dw_q_valid<=0;
        end else begin
            if(done_valid&&done_ready)begin done_valid<=0;state<=IDLE;end
            if(active)cycles<=cycles+1;
            if(start_valid&&start_ready)begin
                saved_preflight<=preflight;
                is_dense_op<=op_words[0+:32]==1;is_dw_op<=op_words[0+:32]==2;
                y<=0;x<=0;co_base<=0;m_count<=0;tile_number<=0;active<=1;state<=CHECK;cycles<=0;
                tile_y0<=0;tile_rows_cap<=0;tile_rows_actual<=0;tile_plane_bytes<=0;tile_plane_words<=0;tile_byte_offset<=0;
                stat_mac_vectors<=0;stat_quant_groups<=0;stat_rows<=0;
            end
            if(active&&!cancel_request)case(state)
                CHECK:begin
                    if(epoch!=saved_epoch||saved_epoch==0)finish(13,32'h45504f43);
                    else if(code<1||code>8||code==0)finish(21,code);
                    else if(spatial&&(cin_full==0||cin_full>64||co_full==0||co_full>64||hin_full==0||win_full==0||hout_full==0||wout_full==0||hin_full>320||win_full>320||hout_full>320||wout_full>320||
                        !(sdt==1||sdt==2)||ddt==0||ddt>4||{3'd0,row_words}>capacity_words(tile_co_groups)))finish(11,32'h43415053);
                    else if(code==1&&(kcount_full==0||kcount_full>128||!(kh==1||kh==3)||!(kw==1||kw==3)))finish(11,32'h444b4348);
                    else if(code==2&&(cin_full!=co_full||!(kcount_full==1||kcount_full==9)||kh!=kw))finish(11,32'h44574348);
                    else if((code==4||code==5)&&(cin_full!=co_full||sdt!=ddt||ddt>2))finish(11,32'h56454348);
                    else state<=PCMD;
                end
                PCMD:if(input_cmd_ready)state<=PWAIT;
                PWAIT:if(input_done_valid)begin
                    if(input_done_tag!=saved_tag)finish(22,32'h50494454);
                    else if(input_status!=0)finish(input_status,input_detail);
                    else if(saved_preflight)finish(0,0);
                    else if(spatial)begin
                        if((code==1||code==2)&&(!input_param_valid||shadow_valid!=(64'hffffffffffffffff>>(64-co))))finish(22,32'h50534844);
                        else begin m_count<=wout>M_LANES?M_LANES:wout[4:0];state<=TILECAP;end
                    end else state<=VSTART;
                end
                TILECAP:begin
                    if(tile_rows_cap<hout&&next_tile_words<=capacity_words(tile_co_groups))begin
                        tile_rows_cap<=tile_rows_cap+1;tile_plane_bytes<=next_tile_bytes;tile_plane_words<=next_tile_words;
                    end else begin tile_rows_actual<=tile_rows_cap;state<=ROWCMD;end
                end
                ROWCMD:if(input_cmd_ready)state<=ROWWAIT;
                ROWWAIT:if(input_done_valid)begin
                    if(input_status!=0||input_done_tag!=saved_tag||!input_rows_valid)finish(input_status!=0?input_status:22,input_detail);
                    else if(code==1)state<=ACMD;
                    else if(code==2)state<=DWCLR;
                    else begin tap_issue<=0;tap_returned<=0;pool_acc<=0;state<=POOLRUN;end
                end
                ACMD:if(input_cmd_ready)state<=AWAIT;
                AWAIT:if(input_done_valid)begin
                    if(input_status!=0||input_done_tag!=saved_tag||!input_a_valid)finish(input_status!=0?input_status:22,input_detail);
                    else state<=DINIT;
                end
                DINIT:if(core_ce&&array_init_ready)begin k_issued<=0;k_returned<=0;q_issued<=0;q_retired<=0;state<=DRUN;end
                DRUN:if(core_ce&&a_req_valid&&a_req_ready)begin k_issued<=k_issued+8'd1;if(k_issued+8'd1==kcount)state<=DDRAIN;end
                DDRAIN:if(core_ce&&k_returned==kcount&&!array_busy)state<=QDENSE;
                QDENSE:if(run_ce&&q_in_valid&&q_in_capacity)begin q_issued<=q_issued+10'd1;if(q_issued+10'd1==({5'd0,m_count}<<1))state<=QDRAIN;end
                QDRAIN:if(run_ce&&q_retired==({5'd0,m_count}<<1)&&!q_busy)begin
                    tile_number<=tile_number+1;
                    if(co_base+7'd16<co)begin co_base<=co_base+7'd16;state<=DINIT;end
                    else if(x+M_LANES<wout)begin
                        x<=x+M_LANES;co_base<=0;m_count<=wout-x-M_LANES>M_LANES?M_LANES:wout-x-M_LANES;state<=ACMD;
                    end else state<=ROWFINISH;
                end
                DWCLR:if(core_ce)begin
                    tap_issue<=0;tap_returned<=0;dw_issue_x<=0;dw_return_x<=0;dw_issue_done<=0;dw_half<=0;q_issued<=0;q_retired<=0;state<=DWRUN;
                end
                DWRUN:begin
                    if(core_ce&&dw_req_valid&&dw_req_ready)begin
                        if(tap_issue+1==kcount)begin tap_issue<=0;if(dw_issue_x+1==wout)dw_issue_done<=1;else dw_issue_x<=dw_issue_x+1;end
                        else tap_issue<=tap_issue+1;
                    end
                    if(run_ce&&q_in_valid&&q_in_capacity)begin dw_half<=!dw_half;q_issued<=q_issued+10'd1;end
                    if(run_ce&&dw_issue_done&&dw_return_x==wout&&q_retired==(wout<<1)&&!q_busy&&!dw_busy&&!dw_q_valid)begin
                        if(co_base+7'd16<co)begin co_base<=co_base+7'd16;state<=DWCLR;end
                        else state<=ROWFINISH;
                    end
                end
                POOLRUN:if(core_ce&&dw_req_valid&&dw_req_ready)tap_issue<=tap_issue+1;
                PV0:if(core_ce)state<=PV1;
                PV1:if(core_ce)begin
                    tap_issue<=0;tap_returned<=0;pool_acc<=0;
                    if(x+1<wout)begin x<=x+1;state<=POOLRUN;end
                    else if(co_base+7'd16<co)begin x<=0;co_base<=co_base+7'd16;state<=POOLRUN;end
                    else state<=ROWFINISH;
                end
                STORESTART:if(store_start_ready)state<=STOREWAIT;
                STOREWAIT:if(store_done_valid)begin
                    if(store_status!=0||store_tag!=saved_tag)finish(store_status!=0?store_status:22,store_detail);
                    else begin stat_rows<=stat_rows+tile_rows_actual;state<=NEXTROW;end
                end
                ROWFINISH:begin
                    if(y+1==tile_y0+tile_rows_actual)state<=STORESTART;
                    else begin
                        tile_byte_offset<=tile_byte_offset+row_bytes[9:0];
                        y<=y+1;x<=0;co_base<=0;m_count<=wout>M_LANES?M_LANES:wout[4:0];state<=ROWCMD;
                    end
                end
                NEXTROW:begin
                    if(y+1==hout)finish(0,0);
                    else begin
                        tile_y0<=y+1;tile_rows_actual<=hout-y-1>tile_rows_cap?tile_rows_cap:hout-y-1;tile_byte_offset<=0;
                        y<=y+1;x<=0;co_base<=0;m_count<=wout>M_LANES?M_LANES:wout[4:0];state<=ROWCMD;
                    end
                end
                VSTART:if(vector_start_ready)state<=VWAIT;
                VWAIT:if(vector_done_valid)begin
                    if(vector_tag!=saved_tag||vector_opid!=opid)finish(22,32'h56494454);
                    else finish(vector_status,vector_detail);
                end
                default:begin end
            endcase
            if(core_ce&&active&&(state==DRUN||state==DDRAIN)&&(a_rsp_valid||b_rsp_valid))begin
                if(!dense_return||a_rsp_error||b_rsp_error||a_rsp_tag!=b_rsp_tag||a_rsp_tag!={24'd0,k_returned}||!array_ready)finish(22,32'h44414252);
                else begin k_returned<=k_returned+1;stat_mac_vectors<=stat_mac_vectors+1;end
            end
            if(core_ce&&active&&state==DWRUN&&(dw_rsp_valid||b_rsp_valid))begin
                if(!dw_return||dw_rsp_error||b_rsp_error||dw_rsp_tag!=b_rsp_tag||dw_rsp_tag!={19'd0,dw_return_x,tap_returned}||!dw_ready)finish(22,32'h44575253);
                else begin
                    stat_mac_vectors<=stat_mac_vectors+1;
                    if(tap_returned+1==kcount)begin tap_returned<=0;dw_return_x<=dw_return_x+1;end else tap_returned<=tap_returned+1;
                end
            end
            if(core_ce&&active&&state==POOLRUN&&dw_rsp_valid)begin
                if(dw_rsp_error||dw_rsp_tag!={19'd0,x,tap_returned})finish(22,32'h50525350);
                else begin
                    pool_acc<=pool_next;tap_returned<=tap_returned+1;
                    if(tap_returned+1==(code==5?1:4))begin pool_value<=pool_next;state<=PV0;end
                end
            end
            if(q_store&&run_ce&&active)begin
                if(q_error!=0||q_out_tag[127:96]!=saved_tag||q_out_tag[95:64]!=opid||q_out_tag[63:48]!={7'd0,y}||
                    q_out_tag[34:32]!=0||(q_out_mask!=0&&q_out_tag[47:32]>=co)||q_out_tag[31:0]>=wout||q_out_mask!=mask8({16'd0,q_out_tag[47:32]})||q_out_dtype!=ddt[1:0]-1||q_out_add)finish(22,32'h51525350);
                else begin q_retired<=q_retired+10'd1;stat_quant_groups<=stat_quant_groups+1;end
            end
            if(!active||state==CHECK||state==DWCLR)begin dw_q_valid<=0;dw_half<=0;end
            else if(state==DWRUN&&run_ce)begin
                if(q_in_valid&&q_in_capacity&&dw_half)dw_q_valid<=0;
                if(dw_out_valid&&dw_out_ready)begin
                    if(dw_mask!=co_mask)finish(22,32'h44574d4b);
                    else begin dw_q_valid<=1;end
                end
            end
            if(ENABLE_RUNTIME_DIAGNOSTICS && active&&core_ce&&state!=CHECK&&state!=DWCLR&&(array_fault!=0||dw_fault!=0||o_conflict||o_range))finish(22,{16'd0,array_fault,dw_fault,6'd0,o_conflict,o_range});
            if(active&&cancel_request)begin
                if(select_input)begin if(!input_busy)finish(17,0);else if(input_done_valid)finish(17,input_detail);end
                else if(select_store)begin if(state==STORESTART||store_done_valid)finish(17,store_detail);end
                else if(select_vector)begin if(!vector_busy||vector_done_valid)finish(17,vector_detail);end
                else finish(17,0);
            end
        end
    end

    // spec155: physical identity controls, unchanged cycle/reset semantics.
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_input_path_rst_n_buffer(.I0(rst_n),.Z(rg_input_path_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_dense_rst_n_buffer(.I0(rst_n),.Z(rg_dense_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_dense_clear_buffer(.I0(clear_math),.Z(rg_dense_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_depthwise_rst_n_buffer(.I0(rst_n),.Z(rg_depthwise_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_depthwise_clear_buffer(.I0(clear_math||state==DWCLR),.Z(rg_depthwise_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_quantizer_rst_n_buffer(.I0(rst_n),.Z(rg_quantizer_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_quantizer_clear_buffer(.I0(clear_math),.Z(rg_quantizer_clear));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_O_rst_n_buffer(.I0(rst_n),.Z(rg_O_rst_n));
    (* syn_noprune=1, syn_keep=1, syn_maxfan=64 *) GTP_LUT1 #(.INIT(2'b10)) rg_row_writer_rst_n_buffer(.I0(rst_n),.Z(rg_row_writer_rst_n));
    (* syn_noprune=1 *) GTP_LUT1 #(.INIT(2'b10)) rg_vector_path_rst_n_buffer(.I0(rst_n),.Z(rg_vector_path_rst_n));
endmodule
