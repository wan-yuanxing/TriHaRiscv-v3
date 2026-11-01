// Ordinary-clock HEAD/TABLE reader with two shared 256-bit RX stages.
// reset_n is the complete session reset; cancel_request never withdraws a bus offer.
module b03_post_read_dma #(
    parameter [2:0] POST_CLIENT=3'd4,
    parameter [31:0] INITIAL_LOCAL_ID=32'd1,
    parameter integer STALL_LIMIT=1000000
)(
    input wire clk,reset_n,run_ce,cancel_request,bridge_fault,
    input wire head_start_valid,output wire head_start_ready,
    input wire [31:0] cfg_heads_offset,cfg_heads_bytes,cfg_table_offset,cfg_table_bytes,
    input wire [31:0] cfg_cmd_id,cfg_post_epoch,cfg_bridge_epoch,cfg_head_generation,
    input wire [63:0] cfg_frame_id,
    output wire head_done_valid,input wire head_done_ready,output reg [3:0] head_done_status,
    output wire [31:0] head_done_cmd_id,head_done_epoch,output wire [63:0] head_done_frame_id,
    output wire load_begin,output wire [31:0] load_generation,
    output wire head_valid,input wire head_ready,output wire [14:0] head_offset,
    output wire [255:0] head_data,output wire [31:0] head_generation,
    input wire heads_loaded,load_error,
    input wire table_req_valid,output wire table_req_ready,
    input wire [31:0] table_req_offset,table_req_epoch,
    output wire table_rsp_valid,input wire table_rsp_ready,output wire [255:0] table_rsp_data,
    output wire [31:0] table_rsp_offset,table_rsp_epoch,output wire table_rsp_error,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
    output wire [31:0] cmd_offset,cmd_id,cmd_epoch,
    output wire [4:0] cmd_beats,output wire [2:0] cmd_client,
    input wire read_valid,output wire read_ready,input wire [255:0] read_data,input wire read_last,
    input wire mem_done_valid,output wire mem_done_ready,input wire [3:0] mem_done_status,
    input wire [31:0] mem_done_id,mem_done_epoch,input wire [2:0] mem_done_client,
    output wire abort_req,output reg quarantined,reset_required,output reg [3:0] fault_status,
    output wire [3:0] debug_state,output wire debug_owner,debug_ingress_valid,debug_present_valid,
    output wire [9:0] debug_head_received,debug_head_presented,
    output wire [6:0] debug_head_commands,output wire [31:0] debug_commands,debug_next_local_id,
    output wire tag_exhausted
);
    localparam IDLE=0,CHECK=1,BEGIN_LOAD=2,HEAD_PLAN=3,OFFER=4,HEAD_RX=5,
        HEAD_RETIRE=6,HEAD_DONE=7,TABLE_READY=8,TABLE_CHECK=9,TABLE_RX=10,
        TABLE_RESPONSE=11,ISOLATED=12,HEAD_REJECT=13;
    reg [3:0] state;
    reg [31:0] heads_base,heads_bytes,table_base,table_bytes,saved_cmd,saved_post,saved_bridge,generation;
    reg [63:0] saved_frame;
    reg [31:0] relative,request_epoch;
    reg [31:0] next_local,command_id,command_offset,commands,stalled;
    reg local_exhausted,offer_valid,owner,command_table,table_retired,head_started;
    reg [4:0] command_beats,received;
    reg [9:0] head_received,head_presented;
    reg [6:0] head_commands;
    reg ingress_valid,ingress_table,ingress_last,ingress_error;
    reg [255:0] ingress_data;
    reg [14:0] ingress_offset;
    reg [31:0] ingress_relative,ingress_epoch,ingress_generation;
    reg present_valid,present_table,present_error;
    reg [255:0] present_data;
    reg [14:0] present_offset;
    reg [31:0] present_relative,present_epoch,present_generation;
    wire invalidating=quarantined || cancel_request || bridge_fault;
    wire idle_for_head=(state==IDLE || state==TABLE_READY) && !owner && !offer_valid && !ingress_valid && !present_valid;
    assign head_start_ready=idle_for_head && !table_req_valid && !invalidating;
    assign table_req_ready=state==TABLE_READY && !owner && !offer_valid && !ingress_valid && !present_valid && !invalidating;
    assign load_begin=state==BEGIN_LOAD && run_ce && !invalidating;
    assign load_generation=generation;
    assign head_valid=present_valid && !present_table && !invalidating;
    assign head_data=present_data;
    assign head_offset=present_offset;
    assign head_generation=present_generation;
    assign table_rsp_valid=present_valid && present_table && !invalidating;
    assign table_rsp_data=present_data;
    assign table_rsp_offset=present_relative;
    assign table_rsp_epoch=present_epoch;
    assign table_rsp_error=present_error;
    assign head_done_valid=state==HEAD_DONE && !invalidating;
    assign head_done_cmd_id=saved_cmd;
    assign head_done_epoch=saved_post;
    assign head_done_frame_id=saved_frame;
    wire head_fire=run_ce && head_valid && head_ready;
    wire table_fire=run_ce && table_rsp_valid && table_rsp_ready;
    wire present_consumed=head_fire || table_fire;
    wire ingress_move=run_ce && ingress_valid && (!present_valid || present_consumed) &&
        (!ingress_table || table_retired) && !invalidating;
    assign cmd_valid=offer_valid;
    assign cmd_write=1'b0;
    assign cmd_offset=command_offset;
    assign cmd_id=command_id;
    assign cmd_epoch=saved_bridge;
    assign cmd_beats=command_beats;
    assign cmd_client=POST_CLIENT;
    assign read_ready=quarantined || (owner && (state==HEAD_RX || state==TABLE_RX) &&
        received<command_beats && (!ingress_valid || ingress_move));
    assign mem_done_ready=owner || quarantined;
    assign abort_req=quarantined && owner;
    wire command_fire=cmd_valid && cmd_ready;
    wire read_fire=read_valid && read_ready;
    wire done_fire=mem_done_valid && mem_done_ready;
    wire bad_read=read_valid && (!owner || received>=command_beats ||
        (read_fire && read_last!=(received+1'b1==command_beats)));
    wire done_identity=mem_done_id==command_id && mem_done_epoch==saved_bridge && mem_done_client==POST_CLIENT;
    wire [5:0] received_after={1'b0,received}+{5'd0,(read_fire && !quarantined)};
    wire [10:0] heads_after={1'b0,head_received}+{10'd0,(read_fire && !quarantined && !command_table)};
    wire [32:0] heads_end={1'b0,heads_base}+{1'b0,heads_bytes};
    wire [32:0] table_end={1'b0,table_base}+{1'b0,table_bytes};
    wire configuration_legal=heads_bytes>=32'd26368 && table_bytes==32'd1572864 && generation!=0 &&
        heads_base[4:0]==0 && heads_bytes[4:0]==0 && table_base[4:0]==0 && table_bytes[4:0]==0 &&
        heads_end<=33'h040000000 && table_end<=33'h040000000 &&
        !( {1'b0,heads_base}<table_end && {1'b0,table_base}<heads_end );
    wire head_ids_available=!local_exhausted && next_local!=0 &&
        ({1'b0,next_local}+33'd52)<=33'h0ffffffff;
    wire [32:0] next_head_address={1'b0,heads_base}+({23'd0,head_received}<<5);
    wire [7:0] head_page_beats=(13'd4096-{1'b0,next_head_address[11:0]})>>5;
    wire [9:0] head_remaining=10'd824-head_received;
    wire [4:0] maximum_head_beats=head_remaining>16 ? 5'd16:head_remaining[4:0];
    wire [4:0] planned_head_beats={3'd0,maximum_head_beats}>head_page_beats ? head_page_beats[4:0]:maximum_head_beats;
    wire table_legal=relative[4:0]==0 && relative<=32'd1572832 && request_epoch==saved_post &&
        ({1'b0,table_base}+{1'b0,relative}+33'd32)<=table_end;
    wire [32:0] table_address={1'b0,table_base}+{1'b0,relative};
    wire waiting=state==BEGIN_LOAD || state==OFFER || state==HEAD_RX || state==HEAD_RETIRE ||
        state==TABLE_RX || state==TABLE_RESPONSE;
    wire progress=command_fire || read_fire || done_fire || ingress_move || present_consumed || load_begin;
    wire timed_out=waiting && STALL_LIMIT>0 && !progress && stalled>=STALL_LIMIT-1;
    assign debug_state=state;
    assign debug_owner=owner;
    assign debug_ingress_valid=ingress_valid;
    assign debug_present_valid=present_valid;
    assign debug_head_received=head_received;
    assign debug_head_presented=head_presented;
    assign debug_head_commands=head_commands;
    assign debug_commands=commands;
    assign debug_next_local_id=next_local;
    assign tag_exhausted=local_exhausted;

    task isolate;
        input [3:0] reason;
        begin
            if(!quarantined)begin quarantined<=1;reset_required<=1;fault_status<=reason;end
            state<=ISOLATED;
        end
    endtask
    task allocate;
        input is_table;
        input [31:0] address;
        input [4:0] beats;
        begin
            command_table<=is_table;command_offset<=address;command_beats<=beats;command_id<=next_local;
            if(next_local==32'hffffffff)local_exhausted<=1;else next_local<=next_local+1'b1;
            received<=0;offer_valid<=1;state<=OFFER;
        end
    endtask

    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;heads_base<=0;heads_bytes<=0;table_base<=0;table_bytes<=0;saved_cmd<=0;saved_post<=0;saved_bridge<=0;generation<=0;saved_frame<=0;
            relative<=0;request_epoch<=0;next_local<=INITIAL_LOCAL_ID;local_exhausted<=0;command_id<=0;command_offset<=0;commands<=0;stalled<=0;
            offer_valid<=0;owner<=0;command_table<=0;command_beats<=0;received<=0;table_retired<=0;head_started<=0;
            head_received<=0;head_presented<=0;head_commands<=0;head_done_status<=0;
            ingress_valid<=0;ingress_table<=0;ingress_last<=0;ingress_error<=0;ingress_data<=0;ingress_offset<=0;ingress_relative<=0;ingress_epoch<=0;ingress_generation<=0;
            present_valid<=0;present_table<=0;present_error<=0;present_data<=0;present_offset<=0;present_relative<=0;present_epoch<=0;present_generation<=0;
            quarantined<=0;reset_required<=0;fault_status<=0;
        end else begin
            if(!waiting || progress)stalled<=0;
            else if(stalled!=32'hffffffff)stalled<=stalled+1'b1;
            // Ordinary bus obligations survive local cancellation and isolation.
            if(command_fire)begin offer_valid<=0;owner<=1;commands<=commands+1'b1;if(!command_table)head_commands<=head_commands+1'b1;end
            if(done_fire && owner)owner<=0;
            if(!invalidating)begin
                if(head_fire)head_presented<=head_presented+1'b1;
                if(present_consumed)present_valid<=0;
                if(ingress_move)begin
                    present_valid<=1;present_table<=ingress_table;present_error<=ingress_error;present_data<=ingress_data;
                    present_offset<=ingress_offset;present_relative<=ingress_relative;present_epoch<=ingress_epoch;present_generation<=ingress_generation;
                    ingress_valid<=0;
                end
                if(read_fire && !bad_read)begin
                    ingress_valid<=1;ingress_table<=command_table;ingress_last<=read_last;ingress_error<=0;ingress_data<=read_data;
                    ingress_offset<={head_received,5'b0};ingress_relative<=relative;ingress_epoch<=request_epoch;ingress_generation<=generation;
                    received<=received+1'b1;if(!command_table)head_received<=head_received+1'b1;
                end
            end
            if(!quarantined)begin
                if(bridge_fault)isolate(4'd7);
                else if(cancel_request && state!=IDLE)isolate(4'd5);
                else if(head_started && load_error)isolate(4'd2);
                else if(bad_read)isolate(4'd4);
                else if(mem_done_valid && !owner)isolate(4'd3);
                else if(done_fire)begin
                    if(!done_identity || mem_done_status!=0 || received_after!={1'b0,command_beats} ||
                       !(state==HEAD_RX || state==TABLE_RX))isolate(4'd3);
                    else if(command_table)begin table_retired<=1;state<=TABLE_RESPONSE;end
                    else if(heads_after==824)state<=HEAD_RETIRE;
                    else state<=HEAD_PLAN;
                end else if(timed_out)isolate(4'd8);
                else case(state)
                    IDLE,TABLE_READY:begin
                        if(run_ce && table_req_valid && table_req_ready)begin
                            relative<=table_req_offset;request_epoch<=table_req_epoch;table_retired<=0;state<=TABLE_CHECK;
                        end else if(run_ce && head_start_valid && head_start_ready)begin
                            heads_base<=cfg_heads_offset;heads_bytes<=cfg_heads_bytes;table_base<=cfg_table_offset;table_bytes<=cfg_table_bytes;
                            saved_cmd<=cfg_cmd_id;saved_post<=cfg_post_epoch;saved_bridge<=cfg_bridge_epoch;generation<=cfg_head_generation;saved_frame<=cfg_frame_id;
                            head_received<=0;head_presented<=0;head_commands<=0;head_started<=0;head_done_status<=0;state<=CHECK;
                        end
                    end
                    CHECK:if(!configuration_legal)state<=HEAD_REJECT;
                        else if(!head_ids_available)isolate(4'd6);
                        else state<=BEGIN_LOAD;
                    BEGIN_LOAD:if(run_ce)begin head_started<=1;state<=HEAD_PLAN;end
                    HEAD_PLAN:allocate(1'b0,next_head_address[31:0],planned_head_beats);
                    OFFER:if(command_fire)state<=command_table ? TABLE_RX:HEAD_RX;
                    HEAD_RX:begin end
                    HEAD_RETIRE:if(run_ce && head_received==824 && head_presented==824 && !owner && !offer_valid &&
                        !ingress_valid && !present_valid && heads_loaded)begin head_done_status<=0;state<=HEAD_DONE;end
                    HEAD_REJECT:if(run_ce)begin head_done_status<=1;state<=HEAD_DONE;end
                    HEAD_DONE:if(run_ce && head_done_valid && head_done_ready)begin head_started<=0;state<=head_done_status==0 ? TABLE_READY:IDLE;end
                    TABLE_CHECK:if(!table_legal)begin
                        ingress_valid<=1;ingress_table<=1;ingress_error<=1;ingress_data<=0;ingress_relative<=relative;ingress_epoch<=request_epoch;
                        ingress_offset<=0;ingress_generation<=generation;table_retired<=1;state<=TABLE_RESPONSE;
                    end else if(local_exhausted || next_local==0)isolate(4'd6);
                    else allocate(1'b1,table_address[31:0],5'd1);
                    TABLE_RX:begin end
                    TABLE_RESPONSE:if(table_fire)begin table_retired<=0;state<=TABLE_READY;end
                    default:isolate(4'd3);
                endcase
            end else state<=ISOLATED;
        end
    end
endmodule
