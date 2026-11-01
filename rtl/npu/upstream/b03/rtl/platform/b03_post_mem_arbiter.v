// Two ordinary-clock clients share one backend owner. Global IDs are translated
// only after their returned identity is checked. Complete session reset only.
module b03_post_mem_arbiter #(
    parameter [2:0] POST_CLIENT=3'd4,
    parameter [31:0] INITIAL_GLOBAL_ID=32'd1
)(
    input wire clk,reset_n,cancel_request,bridge_fault,
    input wire [31:0] bridge_epoch,
    input wire r_cmd_valid,output wire r_cmd_ready,input wire r_cmd_write,
    input wire [31:0] r_cmd_offset,r_cmd_id,r_cmd_epoch,
    input wire [4:0] r_cmd_beats,input wire [2:0] r_cmd_client,
    output wire r_done_valid,input wire r_done_ready,output wire [3:0] r_done_status,
    output wire [31:0] r_done_id,r_done_epoch,output wire [2:0] r_done_client,
    input wire r_abort_req,
    output wire r_read_valid,input wire r_read_ready,output wire [255:0] r_read_data,
    output wire r_read_last,
    input wire w_cmd_valid,output wire w_cmd_ready,input wire w_cmd_write,
    input wire [31:0] w_cmd_offset,w_cmd_id,w_cmd_epoch,
    input wire [4:0] w_cmd_beats,input wire [2:0] w_cmd_client,
    output wire w_done_valid,input wire w_done_ready,output wire [3:0] w_done_status,
    output wire [31:0] w_done_id,w_done_epoch,output wire [2:0] w_done_client,
    input wire w_abort_req,
    input wire w_write_valid,output wire w_write_ready,input wire [255:0] w_write_data,
    input wire [31:0] w_write_strb,input wire w_write_last,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
    output wire [31:0] cmd_offset,cmd_id,cmd_epoch,
    output wire [4:0] cmd_beats,output wire [2:0] cmd_client,
    output wire write_valid,input wire write_ready,output wire [255:0] write_data,
    output wire [31:0] write_strb,output wire write_last,
    input wire read_valid,output wire read_ready,input wire [255:0] read_data,input wire read_last,
    input wire mem_done_valid,output wire mem_done_ready,input wire [3:0] mem_done_status,
    input wire [31:0] mem_done_id,mem_done_epoch,input wire [2:0] mem_done_client,
    output wire abort_req,
    output wire busy,output reg quarantined,reset_required,
    output reg [3:0] fault_status,output reg tag_exhausted,
    output wire [1:0] debug_state,debug_owner,
    output wire [31:0] debug_local_id,debug_global_id,
    output reg [31:0] fault_done_id,fault_done_epoch,
    output reg [2:0] fault_done_client,output reg [3:0] fault_done_status
);
    localparam IDLE=0,OFFER=1,ACTIVE=2;
    reg [1:0] state;
    reg selected_write;
    reg [31:0] saved_offset,saved_local_id,saved_epoch,saved_global_id,next_global;
    reg [4:0] saved_beats;
    reg [2:0] saved_local_client;
    reg done_buffer_valid,completion_seen,pending_data;
    reg [3:0] done_buffer_status;
    wire has_owner=state==ACTIVE;
    wire offer=state==OFFER;
    wire selected_ready=selected_write ? w_done_ready:r_done_ready;
    wire selected_abort=selected_write ? w_abort_req:r_abort_req;
    wire selected_valid=selected_write ? w_cmd_valid:r_cmd_valid;
    wire selected_fields_same=selected_write ?
        (w_cmd_write && w_cmd_offset==saved_offset && w_cmd_id==saved_local_id &&
         w_cmd_epoch==saved_epoch && w_cmd_beats==saved_beats && w_cmd_client==saved_local_client):
        (!r_cmd_write && r_cmd_offset==saved_offset && r_cmd_id==saved_local_id &&
         r_cmd_epoch==saved_epoch && r_cmd_beats==saved_beats && r_cmd_client==saved_local_client);
    wire done_identity_ok=mem_done_id==saved_global_id && mem_done_epoch==saved_epoch && mem_done_client==POST_CLIENT;
    wire exposed_data=has_owner && (selected_write ? w_write_valid:read_valid);
    wire exposed_data_ready=selected_write ? write_ready:r_read_ready;
    // Metadata only: sample the first backend DONE before presenting it locally.
    // Error/success classification cannot change when an exposed data beat later
    // drains while the source holds DONE READY low.
    wire capture_done=has_owner && !completion_seen && !done_buffer_valid && mem_done_valid;
    wire [3:0] captured_status=!done_identity_ok ? 4'd6:
        mem_done_status!=0 ? mem_done_status:exposed_data ? 4'd6:4'd0;
    wire epoch_changed=state!=IDLE && bridge_epoch!=saved_epoch;
    wire command_fire=cmd_valid && cmd_ready;
    wire completion_fire=has_owner && !completion_seen && mem_done_valid && mem_done_ready;
    wire source_offer_changed=offer && (!selected_valid || !selected_fields_same);
    wire stale_response=(mem_done_valid && (!has_owner || completion_seen)) || (read_valid && !(has_owner && !selected_write));
    wire cancel_event=cancel_request || (has_owner && selected_abort);
    wire fault_event=bridge_fault || epoch_changed || cancel_event || source_offer_changed ||
        stale_response || (has_owner && mem_done_valid && (!done_identity_ok || mem_done_status!=0));
    wire choose_read=r_cmd_valid;
    wire [31:0] choice_epoch=choose_read ? r_cmd_epoch:w_cmd_epoch;
    wire [2:0] choice_client=choose_read ? r_cmd_client:w_cmd_client;
    wire choice_write=choose_read ? r_cmd_write:w_cmd_write;
    wire choice_legal=choice_epoch==bridge_epoch && choice_client==POST_CLIENT &&
        (choose_read ? !choice_write:choice_write);

    assign busy=state!=IDLE;
    assign debug_state=state;
    assign debug_owner=state==IDLE ? 2'd0:(selected_write ? 2'd2:2'd1);
    assign debug_local_id=saved_local_id;
    assign debug_global_id=saved_global_id;
    assign cmd_valid=offer;
    assign cmd_write=selected_write;
    assign cmd_offset=saved_offset;
    assign cmd_id=saved_global_id;
    assign cmd_epoch=saved_epoch;
    assign cmd_beats=saved_beats;
    assign cmd_client=POST_CLIENT;
    assign r_cmd_ready=offer && !selected_write && cmd_ready;
    assign w_cmd_ready=offer && selected_write && cmd_ready;
    assign write_valid=has_owner && selected_write && w_write_valid;
    assign w_write_ready=has_owner && selected_write && write_ready;
    assign write_data=w_write_data;
    assign write_strb=w_write_strb;
    assign write_last=w_write_last;
    assign r_read_valid=has_owner && !selected_write && read_valid;
    assign r_read_data=read_data;
    assign r_read_last=read_last;
    // Unexpected traffic is drained only once isolation has been latched.
    assign read_ready=(has_owner && !selected_write) ? r_read_ready:quarantined;
    assign r_done_valid=has_owner && !selected_write && !completion_seen && done_buffer_valid && mem_done_valid;
    assign w_done_valid=has_owner && selected_write && !completion_seen && done_buffer_valid && mem_done_valid;
    assign r_done_status=done_buffer_status;
    assign w_done_status=done_buffer_status;
    assign r_done_id=saved_local_id;
    assign w_done_id=saved_local_id;
    assign r_done_epoch=saved_epoch;
    assign w_done_epoch=saved_epoch;
    assign r_done_client=saved_local_client;
    assign w_done_client=saved_local_client;
    assign mem_done_ready=has_owner ? (completion_seen ? quarantined:(done_buffer_valid && selected_ready)):quarantined;
    assign abort_req=has_owner && (selected_abort || cancel_request || bridge_fault || epoch_changed || quarantined);

    task isolate;
        input [3:0] reason;
        begin
            if(!quarantined)begin
                quarantined<=1;reset_required<=1;fault_status<=reason;
                fault_done_id<=mem_done_id;fault_done_epoch<=mem_done_epoch;
                fault_done_client<=mem_done_client;fault_done_status<=mem_done_status;
            end
        end
    endtask

    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;selected_write<=0;saved_offset<=0;saved_local_id<=0;
            saved_epoch<=0;saved_global_id<=0;saved_beats<=0;saved_local_client<=0;
            next_global<=INITIAL_GLOBAL_ID;tag_exhausted<=INITIAL_GLOBAL_ID==0;
            done_buffer_valid<=0;done_buffer_status<=0;completion_seen<=0;pending_data<=0;
            quarantined<=0;reset_required<=0;fault_status<=0;
            fault_done_id<=0;fault_done_epoch<=0;fault_done_client<=0;fault_done_status<=0;
        end else begin
            // Existing offers/owners continue even during isolation; ordinary
            // valid may end only by its handshake or the complete session reset.
            if(command_fire)state<=ACTIVE;
            if(capture_done)begin done_buffer_valid<=1;done_buffer_status<=captured_status;end
            if(completion_fire)begin
                completion_seen<=1;done_buffer_valid<=0;
                pending_data<=exposed_data && !exposed_data_ready;
                if(!(exposed_data && !exposed_data_ready))state<=IDLE;
            end
            if(has_owner && completion_seen && pending_data && exposed_data && exposed_data_ready)begin
                pending_data<=0;state<=IDLE;
            end

            if(!quarantined)begin
                if(bridge_fault || epoch_changed)isolate(4'd6);
                else if(cancel_event)isolate(4'd5);
                else if(source_offer_changed)isolate(4'd8);
                else if(stale_response)isolate(4'd4);
                else if(has_owner && mem_done_valid && !done_identity_ok)isolate(4'd2);
                else if(has_owner && mem_done_valid && mem_done_status!=0)isolate(4'd3);
                else if(has_owner && mem_done_valid && exposed_data)isolate(4'd9);
                else if(state==IDLE && (r_cmd_valid || w_cmd_valid))begin
                    if(tag_exhausted || next_global==0)isolate(4'd7);
                    else if(!choice_legal)isolate(4'd1);
                    else begin
                        selected_write<=!choose_read;
                        saved_offset<=choose_read ? r_cmd_offset:w_cmd_offset;
                        saved_local_id<=choose_read ? r_cmd_id:w_cmd_id;
                        saved_epoch<=choice_epoch;saved_local_client<=choice_client;
                        saved_beats<=choose_read ? r_cmd_beats:w_cmd_beats;
                        saved_global_id<=next_global;
                        done_buffer_valid<=0;done_buffer_status<=0;completion_seen<=0;pending_data<=0;
                        if(next_global==32'hffffffff)tag_exhausted<=1;
                        else next_global<=next_global+1'b1;
                        state<=OFFER;
                    end
                end
            end
        end
    end
endmodule
