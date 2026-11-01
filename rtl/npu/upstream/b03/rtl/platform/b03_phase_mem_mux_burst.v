// Two phase-selected ordinary-clock clients, one serialized bridge owner.
// No DATA storage. Only the offered descriptor and one DONE tuple are saved.
// Reset is the complete bridge-session reset; arithmetic CE never gates this port.
module b03_phase_mem_mux_burst #(
    parameter [31:0] INITIAL_GLOBAL_ID=32'd1,
    parameter [31:0] TIMEOUT_CYCLES=32'd100000000
)(
    input wire clk,rst_n,select_post,cancel_request,bridge_fault,
    input wire [31:0] epoch,
    input wire d_cmd_valid,output wire d_cmd_ready,input wire d_cmd_write,
    input wire [31:0] d_cmd_offset,d_cmd_id,d_cmd_epoch,input wire [4:0] d_cmd_beats,input wire [2:0] d_cmd_client,
    input wire d_abort_req,
    input wire d_write_valid,output wire d_write_ready,input wire [255:0] d_write_data,
    input wire [31:0] d_write_strb,input wire d_write_last,
    output wire d_read_valid,input wire d_read_ready,output wire [255:0] d_read_data,output wire d_read_last,
    output wire d_done_valid,input wire d_done_ready,output wire [3:0] d_done_status,
    output wire [31:0] d_done_id,d_done_epoch,output wire [2:0] d_done_client,
    input wire p_cmd_valid,output wire p_cmd_ready,input wire p_cmd_write,
    input wire [31:0] p_cmd_offset,p_cmd_id,p_cmd_epoch,input wire [4:0] p_cmd_beats,input wire [2:0] p_cmd_client,
    input wire p_abort_req,
    input wire p_write_valid,output wire p_write_ready,input wire [255:0] p_write_data,
    input wire [31:0] p_write_strb,input wire p_write_last,
    output wire p_read_valid,input wire p_read_ready,output wire [255:0] p_read_data,output wire p_read_last,
    output wire p_done_valid,input wire p_done_ready,output wire [3:0] p_done_status,
    output wire [31:0] p_done_id,p_done_epoch,output wire [2:0] p_done_client,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
    output wire [31:0] cmd_offset,cmd_id,cmd_epoch,output wire [4:0] cmd_beats,output wire [2:0] cmd_client,
    output wire write_valid,input wire write_ready,output wire [255:0] write_data,
    output wire [31:0] write_strb,output wire write_last,
    input wire read_valid,output wire read_ready,input wire [255:0] read_data,input wire read_last,
    input wire mem_done_valid,output wire mem_done_ready,input wire [3:0] mem_done_status,
    input wire [31:0] mem_done_id,mem_done_epoch,input wire [2:0] mem_done_client,
    output reg fault_valid,input wire fault_ready,output reg [175:0] fault_payload,
    output reg quarantined,reset_required,output wire abort_req,busy,
    output wire [1:0] debug_owner,output wire [31:0] debug_global_id,
    output reg [31:0] commands,completions
);
    reg offer_valid,owner,saved_post,saved_write,id_exhausted,completion_seen;
    reg [31:0] saved_offset,saved_local_id,saved_epoch,saved_global_id,next_global,elapsed;
    reg [4:0] saved_beats,sent,received;
    reg write_credit,read_credit,write_last_credit,read_last_credit;
    reg [2:0] saved_client;
    reg done_buffer_valid;
    reg [3:0] done_buffer_status;
    reg fault_pending;

    wire choice_valid=select_post?p_cmd_valid:d_cmd_valid;
    wire choice_write=select_post?p_cmd_write:d_cmd_write;
    wire [31:0] choice_offset=select_post?p_cmd_offset:d_cmd_offset;
    wire [31:0] choice_id=select_post?p_cmd_id:d_cmd_id;
    wire [31:0] choice_epoch=select_post?p_cmd_epoch:d_cmd_epoch;
    wire [4:0] choice_beats=select_post?p_cmd_beats:d_cmd_beats;
    wire [2:0] choice_client=select_post?p_cmd_client:d_cmd_client;
    wire choice_abort=select_post?p_abort_req:d_abort_req;
    wire [32:0] choice_end={1'b0,choice_offset}+({28'd0,choice_beats}<<5);
    wire choice_legal=choice_offset[4:0]==0 && choice_beats>=1 && choice_beats<=16 &&
        choice_offset[31:30]==0 && ({1'b0,choice_offset[11:5]}+{3'b0,choice_beats})<=8'd128 &&
        choice_epoch==epoch && epoch!=0 && next_global!=0 && !id_exhausted;
    wire selected_cmd_valid=saved_post?p_cmd_valid:d_cmd_valid;
    wire selected_fields_same=saved_post ?
        (p_cmd_write==saved_write && p_cmd_offset==saved_offset && p_cmd_id==saved_local_id &&
         p_cmd_epoch==saved_epoch && p_cmd_beats==saved_beats && p_cmd_client==saved_client):
        (d_cmd_write==saved_write && d_cmd_offset==saved_offset && d_cmd_id==saved_local_id &&
         d_cmd_epoch==saved_epoch && d_cmd_beats==saved_beats && d_cmd_client==saved_client);
    wire selected_abort=saved_post?p_abort_req:d_abort_req;
    wire selected_w_valid=saved_post?p_write_valid:d_write_valid;
    wire selected_w_last=saved_post?p_write_last:d_write_last;
    wire selected_r_ready=saved_post?p_read_ready:d_read_ready;
    wire selected_done_ready=saved_post?p_done_ready:d_done_ready;
    wire command_fire=cmd_valid&&cmd_ready;
    wire effective_owner=owner||command_fire;
    wire wf=write_valid&&write_ready;
    wire rf=read_valid&&read_ready;
    wire count_complete_after=saved_write?(wf?write_last_credit:!write_credit):(rf?read_last_credit:!read_credit);
    wire df=mem_done_valid&&mem_done_ready;
    wire local_done_fire=done_buffer_valid&&selected_done_ready;
    wire [5:0] w_after={1'b0,sent}+{5'd0,wf};
    wire [5:0] r_after={1'b0,received}+{5'd0,rf};
    wire identity_ok=mem_done_id==saved_global_id && mem_done_epoch==saved_epoch && mem_done_client==saved_client;
    wire bad_read=read_valid && (!effective_owner || saved_write || completion_seen || !read_credit ||
        (rf && read_last!=read_last_credit));
    wire bad_write=effective_owner && saved_write && selected_w_valid &&
        (completion_seen || !write_credit || (wf && selected_w_last!=write_last_credit));
    wire bad_done=mem_done_valid && (!effective_owner || completion_seen || !identity_ok || mem_done_status!=0 ||
        (df && !count_complete_after));
    wire changed_offer=offer_valid && (!selected_cmd_valid || !selected_fields_same);
    wire epoch_changed=(offer_valid||owner)&&epoch!=saved_epoch;
    wire timed_out=(offer_valid||(owner&&!completion_seen))&&elapsed+1>=TIMEOUT_CYCLES;
    wire invalid_choice=!offer_valid&&!owner&&!done_buffer_valid&&choice_valid&&!choice_legal;
    wire idle_cancel=!offer_valid&&!owner&&choice_valid&&(cancel_request||choice_abort||bridge_fault);
    wire transport_fault=!quarantined&&(bad_read||bad_write||bad_done||changed_offer||epoch_changed||timed_out||
        ((offer_valid||owner)&&(cancel_request||bridge_fault||selected_abort))||invalid_choice||idle_cancel);
    wire [3:0] fault_reason=bad_read||bad_write?4'd4:
        bad_done?(!identity_ok?4'd3:mem_done_status!=0?4'd2:4'd4):
        invalid_choice?4'd1:changed_offer?4'd6:4'd5;

    assign cmd_valid=rst_n&&offer_valid;
    assign cmd_write=saved_write;assign cmd_offset=saved_offset;assign cmd_id=saved_global_id;
    assign cmd_epoch=saved_epoch;assign cmd_beats=saved_beats;assign cmd_client=saved_client;
    assign d_cmd_ready=rst_n&&offer_valid&&!saved_post&&cmd_ready;
    assign p_cmd_ready=rst_n&&offer_valid&&saved_post&&cmd_ready;
    // Direct ordinary-clock data paths remain live for their owner in isolation.
    assign write_valid=rst_n&&effective_owner&&saved_write&&write_credit&&selected_w_valid;
    assign write_data=saved_post?p_write_data:d_write_data;
    assign write_strb=saved_post?p_write_strb:d_write_strb;
    assign write_last=selected_w_last;
    assign d_write_ready=rst_n&&effective_owner&&!saved_post&&saved_write&&write_credit&&write_ready;
    assign p_write_ready=rst_n&&effective_owner&&saved_post&&saved_write&&write_credit&&write_ready;
    assign d_read_valid=rst_n&&effective_owner&&!saved_post&&!saved_write&&read_credit&&read_valid;
    assign p_read_valid=rst_n&&effective_owner&&saved_post&&!saved_write&&read_credit&&read_valid;
    assign d_read_data=read_data;assign p_read_data=read_data;assign d_read_last=read_last;assign p_read_last=read_last;
    assign read_ready=rst_n&&((effective_owner&&!saved_write&&read_credit)?selected_r_ready:quarantined);
    assign mem_done_ready=rst_n&&((effective_owner&&!completion_seen&&!done_buffer_valid)||quarantined);
    assign d_done_valid=rst_n&&done_buffer_valid&&!saved_post;
    assign p_done_valid=rst_n&&done_buffer_valid&&saved_post;
    assign d_done_status=done_buffer_status;assign p_done_status=done_buffer_status;
    assign d_done_id=saved_local_id;assign p_done_id=saved_local_id;
    assign d_done_epoch=saved_epoch;assign p_done_epoch=saved_epoch;
    assign d_done_client=saved_client;assign p_done_client=saved_client;
    assign abort_req=quarantined&&(offer_valid||owner);
    assign busy=offer_valid||owner||done_buffer_valid||quarantined;
    assign debug_owner=offer_valid||owner ? (saved_post?2'd2:2'd1):2'd0;
    assign debug_global_id=saved_global_id;

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            offer_valid<=0;owner<=0;saved_post<=0;saved_write<=0;id_exhausted<=INITIAL_GLOBAL_ID==0;
            completion_seen<=0;saved_offset<=0;saved_local_id<=0;saved_epoch<=0;saved_global_id<=0;
            next_global<=INITIAL_GLOBAL_ID;elapsed<=0;saved_beats<=0;sent<=0;received<=0;write_credit<=0;read_credit<=0;write_last_credit<=0;read_last_credit<=0;saved_client<=0;
            done_buffer_valid<=0;done_buffer_status<=0;fault_valid<=0;fault_pending<=0;fault_payload<=0;
            quarantined<=0;reset_required<=0;commands<=0;completions<=0;
        end else begin
            if(fault_valid&&fault_ready)fault_valid<=0;
            if(fault_pending)begin fault_pending<=0;fault_valid<=1;end
            if(offer_valid||(owner&&!completion_seen))elapsed<=elapsed+1;
            if(!quarantined&&!transport_fault&&!offer_valid&&!owner&&!done_buffer_valid&&choice_valid)begin
                saved_post<=select_post;saved_write<=choice_write;saved_offset<=choice_offset;
                saved_local_id<=choice_id;saved_epoch<=choice_epoch;saved_beats<=choice_beats;
                saved_client<=choice_client;saved_global_id<=next_global;offer_valid<=1;
                completion_seen<=0;sent<=0;received<=0;elapsed<=0;
                write_credit<=choice_beats!=0;read_credit<=choice_beats!=0;
                write_last_credit<=choice_beats==1;read_last_credit<=choice_beats==1;
            end
            if(command_fire)begin
                offer_valid<=0;owner<=1;commands<=commands+1;
                if(next_global==32'hffffffff)id_exhausted<=1;else next_global<=next_global+1;
            end
            if(wf&&effective_owner&&saved_write&&write_credit)begin sent<=sent+1;write_credit<=({1'b0,sent}+6'd1)<{1'b0,saved_beats};write_last_credit<=({1'b0,sent}+6'd2)=={1'b0,saved_beats};end
            if(rf&&effective_owner&&!saved_write&&read_credit)begin received<=received+1;read_credit<=({1'b0,received}+6'd1)<{1'b0,saved_beats};read_last_credit<=({1'b0,received}+6'd2)=={1'b0,saved_beats};end
            // The classification is fixed before the tuple is exposed locally.
            if(df&&effective_owner&&!completion_seen&&!done_buffer_valid)begin
                done_buffer_valid<=1;completion_seen<=1;
                done_buffer_status<=transport_fault?fault_reason:(quarantined?4'd5:4'd0);
            end
            if(local_done_fire)begin
                done_buffer_valid<=0;
                if(!quarantined&&!transport_fault&&done_buffer_status==0)begin
                    owner<=0;completion_seen<=0;completions<=completions+1;
                end
            end
            if(transport_fault)begin
                quarantined<=1;reset_required<=1;fault_pending<=1;
                fault_payload<={8'hb4,{effective_owner,3'b0,saved_write,saved_client},
                    effective_owner?saved_offset:32'd0,effective_owner?saved_global_id:32'd0,
                    (offer_valid||owner)?saved_epoch:epoch,
                    effective_owner?{27'd0,saved_beats}:32'd0,
                    effective_owner?(saved_write?{26'd0,w_after}:{26'd0,r_after}):{28'd0,fault_reason}};
            end
        end
    end
endmodule
