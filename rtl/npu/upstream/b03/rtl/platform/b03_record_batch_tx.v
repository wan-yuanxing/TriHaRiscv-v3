// One logical POST batch to ordinary-clock memory-bridge writes.
// reset_n is the complete bridge/FIFO/native session reset, never local cancel.
module b03_record_batch_tx #(
    parameter [2:0] POST_CLIENT=3'd4,
    parameter integer STALL_LIMIT=1000000
)(
    input wire clk,reset_n,run_ce,cancel_request,
    input wire batch_valid,output wire batch_ready,
    input wire [11:0] batch_base_record_index,input wire [4:0] batch_count,
    input wire [31:0] batch_cmd_id,batch_epoch,input wire [63:0] batch_frame_id,
    input wire [31:0] cfg_result_offset,cfg_result_bytes,
    input wire [11:0] cfg_capacity,
    input wire [31:0] cfg_cmd_id,cfg_post_epoch,cfg_bridge_epoch,cfg_first_burst_id,
    input wire [63:0] cfg_frame_id,
    input wire record_valid,output wire record_ready,input wire [255:0] record_data,
    input wire [11:0] record_index,input wire [31:0] record_cmd_id,record_epoch,
    input wire [63:0] record_frame_id,
    output wire batch_done_valid,input wire batch_done_ready,
    output reg [3:0] batch_done_status,
    output wire [11:0] batch_done_base,output wire [4:0] batch_done_count,
    output wire [31:0] batch_done_cmd_id,batch_done_epoch,
    output wire [63:0] batch_done_frame_id,output reg [31:0] batch_done_last_burst_id,
    output reg quarantined,reset_required,output reg [3:0] fault_status,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
    output wire [31:0] cmd_offset,cmd_id,cmd_epoch,
    output wire [4:0] cmd_beats,output wire [2:0] cmd_client,
    output wire write_valid,input wire write_ready,output wire [255:0] write_data,
    output wire [31:0] write_strb,output wire write_last,
    input wire mem_done_valid,output wire mem_done_ready,input wire [3:0] mem_done_status,
    input wire [31:0] mem_done_id,mem_done_epoch,input wire [2:0] mem_done_client,
    output wire abort_req,
    output wire [3:0] debug_state,output wire [4:0] debug_taken,debug_sent,debug_retired,
    output wire [1:0] debug_bursts,output wire debug_owner,debug_skid
);
    localparam IDLE=0,CHECK=1,PLAN=2,CMD_OFFER=3,STREAM=4,WAIT_DONE=5,HELD_DONE=6,QUARANTINE=7;
    reg [3:0] state;
    reg [11:0] saved_base,saved_capacity;
    reg [4:0] saved_count;
    reg [31:0] saved_cmd_id,saved_post_epoch,saved_bridge_epoch,saved_first_id;
    reg [31:0] saved_result_offset,saved_result_bytes;
    reg [31:0] expected_cmd_id,expected_post_epoch;
    reg [63:0] saved_frame_id,expected_frame_id;
    reg [4:0] taken,retired,sub_taken,sub_sent,sub_beats;
    reg [1:0] issued;
    reg [31:0] command_offset,command_id;
    reg offer_valid,owner;
    reg [255:0] skid_data;
    reg skid_valid,skid_last;
    reg high_water_valid;
    reg [31:0] high_water,stalled;

    wire [12:0] end_index={1'b0,saved_base}+{8'd0,saved_count};
    wire [32:0] allocation_end={1'b0,saved_result_offset}+{1'b0,saved_result_bytes};
    wire [32:0] required_bytes=33'd128+({21'd0,saved_capacity}<<5);
    wire [32:0] first_address={1'b0,saved_result_offset}+33'd128+({21'd0,saved_base}<<5);
    wire [32:0] first_page_room=33'd4096-{21'd0,first_address[11:0]};
    wire two_bursts=({28'd0,saved_count}<<5)>first_page_room;
    wire [32:0] reserved_last_id={1'b0,saved_first_id}+{32'd0,two_bursts};
    wire legal=saved_count>=1 && saved_count<=16 && saved_capacity>=1 && saved_capacity<=2100 &&
        end_index<={1'b0,saved_capacity} && saved_cmd_id==expected_cmd_id &&
        saved_post_epoch==expected_post_epoch && saved_frame_id==expected_frame_id &&
        saved_result_offset[4:0]==0 && saved_result_bytes[4:0]==0 &&
        {1'b0,saved_result_bytes}>=required_bytes && allocation_end<=33'h040000000 &&
        saved_first_id!=0 && !reserved_last_id[32] &&
        (!high_water_valid || saved_first_id>high_water);
    wire [32:0] next_address={1'b0,saved_result_offset}+33'd128+
        (({21'd0,saved_base}+{28'd0,taken})<<5);
    wire [7:0] next_page_beats=(13'd4096-{1'b0,next_address[11:0]})>>5;
    wire [4:0] remaining=saved_count-taken;
    wire [4:0] next_beats={3'd0,remaining}>next_page_beats ? next_page_beats[4:0] : remaining;
    wire [12:0] expected_record_index={1'b0,saved_base}+{8'd0,taken};
    wire record_identity_ok={1'b0,record_index}==expected_record_index &&
        record_cmd_id==saved_cmd_id && record_epoch==saved_post_epoch && record_frame_id==saved_frame_id;

    assign batch_ready=state==IDLE && !quarantined && !cancel_request && !mem_done_valid;
    assign batch_done_valid=state==HELD_DONE && !quarantined && !cancel_request;
    assign batch_done_base=saved_base;
    assign batch_done_count=saved_count;
    assign batch_done_cmd_id=saved_cmd_id;
    assign batch_done_epoch=saved_post_epoch;
    assign batch_done_frame_id=saved_frame_id;
    assign cmd_valid=offer_valid;
    assign cmd_write=1'b1;
    assign cmd_offset=command_offset;
    assign cmd_beats=sub_beats;
    assign cmd_id=command_id;
    assign cmd_epoch=saved_bridge_epoch;
    assign cmd_client=POST_CLIENT;
    assign record_ready=state==STREAM && owner && !quarantined && !cancel_request &&
        !mem_done_valid && sub_taken<sub_beats && (!skid_valid || write_ready);
    assign write_valid=skid_valid;
    assign write_data=skid_data;
    assign write_strb=32'hffffffff;
    assign write_last=skid_last;
    assign mem_done_ready=owner;
    assign abort_req=quarantined && owner;
    assign debug_state=state;
    assign debug_taken=taken;
    assign debug_sent=sub_sent;
    assign debug_retired=retired;
    assign debug_bursts=issued;
    assign debug_owner=owner;
    assign debug_skid=skid_valid;
    wire command_fire=cmd_valid && cmd_ready;
    wire write_fire=write_valid && write_ready;
    wire record_fire=run_ce && record_valid && record_ready;
    wire done_fire=mem_done_valid && mem_done_ready;
    wire progress=command_fire || write_fire || record_fire || done_fire;
    wire waiting=state==CMD_OFFER || state==STREAM || state==WAIT_DONE;
    wire timed_out=waiting && STALL_LIMIT>0 && !progress && stalled>=STALL_LIMIT-1;
    wire done_identity_ok=mem_done_id==command_id && mem_done_epoch==saved_bridge_epoch && mem_done_client==POST_CLIENT;

    task isolate;
        input [3:0] reason;
        begin
            if(!quarantined)begin quarantined<=1;reset_required<=1;fault_status<=reason;end
            state<=QUARANTINE;
        end
    endtask

    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;saved_base<=0;saved_capacity<=0;saved_count<=0;
            saved_cmd_id<=0;saved_post_epoch<=0;saved_bridge_epoch<=0;saved_first_id<=0;
            saved_result_offset<=0;saved_result_bytes<=0;expected_cmd_id<=0;expected_post_epoch<=0;
            saved_frame_id<=0;expected_frame_id<=0;taken<=0;retired<=0;sub_taken<=0;sub_sent<=0;sub_beats<=0;issued<=0;
            command_offset<=0;command_id<=0;offer_valid<=0;owner<=0;skid_data<=0;skid_valid<=0;skid_last<=0;
            high_water_valid<=0;high_water<=0;stalled<=0;batch_done_status<=0;batch_done_last_burst_id<=0;
            quarantined<=0;reset_required<=0;fault_status<=0;
        end else begin
            if(!waiting || progress)stalled<=0;
            else if(stalled!=32'hffffffff)stalled<=stalled+1'b1;

            // These ordinary-clock obligations remain live while POST is paused
            // or quarantined. Only complete session reset can discard an offer.
            if(command_fire)begin
                offer_valid<=0;owner<=1;issued<=issued+1'b1;
                high_water<=command_id;high_water_valid<=1;batch_done_last_burst_id<=command_id;
            end
            if(write_fire)begin skid_valid<=0;sub_sent<=sub_sent+1'b1;end
            if(done_fire)owner<=0;

            if(!quarantined)begin
                if(mem_done_valid && !owner)begin
                    isolate(4'd3);
                end else if(cancel_request && state!=IDLE)begin
                    if((state==CHECK || state==PLAN || (state==HELD_DONE && batch_done_status==1)) &&
                       issued==0 && !offer_valid && !owner && !skid_valid)begin
                        batch_done_status<=1;state<=HELD_DONE;
                    end else isolate(4'd5);
                end else if(done_fire)begin
                    if(!done_identity_ok || mem_done_status!=0 || sub_sent!=sub_beats || skid_valid ||
                       !(state==STREAM || state==WAIT_DONE))isolate(4'd3);
                    else begin
                        retired<=retired+sub_beats;
                        if(retired+sub_beats==saved_count && taken==saved_count)begin
                            batch_done_status<=0;state<=HELD_DONE;
                        end else state<=PLAN;
                    end
                end else if(timed_out)isolate(4'd4);
                else case(state)
                    IDLE:if(run_ce && batch_valid && batch_ready)begin
                        saved_base<=batch_base_record_index;saved_count<=batch_count;
                        saved_cmd_id<=batch_cmd_id;saved_post_epoch<=batch_epoch;saved_frame_id<=batch_frame_id;
                        saved_capacity<=cfg_capacity;saved_result_offset<=cfg_result_offset;saved_result_bytes<=cfg_result_bytes;
                        expected_cmd_id<=cfg_cmd_id;expected_post_epoch<=cfg_post_epoch;expected_frame_id<=cfg_frame_id;
                        saved_bridge_epoch<=cfg_bridge_epoch;saved_first_id<=cfg_first_burst_id;
                        taken<=0;retired<=0;sub_taken<=0;sub_sent<=0;sub_beats<=0;issued<=0;
                        batch_done_status<=0;batch_done_last_burst_id<=0;state<=CHECK;
                    end
                    CHECK:if(!legal)begin batch_done_status<=1;state<=HELD_DONE;end else state<=PLAN;
                    PLAN:begin
                        command_offset<=next_address[31:0];command_id<=saved_first_id+issued;
                        sub_beats<=next_beats;sub_taken<=0;sub_sent<=0;offer_valid<=1;state<=CMD_OFFER;
                    end
                    CMD_OFFER:if(command_fire)state<=STREAM;
                    STREAM:begin
                        if(record_fire)begin
                            if(!record_identity_ok)isolate(4'd2);
                            else begin
                                skid_data<=record_data;skid_valid<=1;skid_last<=sub_taken+1'b1==sub_beats;
                                sub_taken<=sub_taken+1'b1;taken<=taken+1'b1;
                            end
                        end
                        if(sub_sent==sub_beats && !skid_valid)state<=WAIT_DONE;
                    end
                    WAIT_DONE:begin end
                    HELD_DONE:if(run_ce && batch_done_valid && batch_done_ready)state<=IDLE;
                    default:isolate(4'd3);
                endcase
            end else state<=QUARANTINE;
        end
    end
endmodule
