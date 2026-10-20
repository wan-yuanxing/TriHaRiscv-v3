`timescale 1ns/1ps
`default_nettype none
// RAW-only bridge between the frozen display owner and raw_display events.
// This ledger holds Video references, not the CPU's global FREE qualification.
// Core, pixel, raw scanner, owner and AXI peers must reset together.
module display_scanout_link(
    input wire clk,reset_n,pixel_clk,pixel_reset_n,pixel_sof,
    input wire cmd_valid,output wire cmd_ready,input wire cmd_mode_only,
    input wire [1:0] cmd_slot,cmd_mode,
    input wire [31:0] cmd_frame,cmd_generation,cmd_base,cmd_stride,cmd_seq,
    output wire record_valid,input wire record_ready,
    output wire [31:0] record_base,record_stride,record_frame,output wire [1:0] record_slot,
    input wire raw_commit_valid,output wire raw_commit_ready,
    input wire [31:0] raw_commit_frame,input wire [1:0] raw_commit_slot,
    input wire raw_release_valid,output wire raw_release_ready,
    input wire [31:0] raw_release_frame,input wire [1:0] raw_release_slot,
    input wire raw_reject,raw_error,
    output wire feedback_valid,input wire feedback_ready,
    output wire [1:0] feedback_slot,feedback_mode,
    output wire [31:0] feedback_frame,feedback_generation,feedback_seq,
    output reg retire_valid,input wire retire_ready,output reg [1:0] retire_slot,
    output reg [31:0] retire_frame,retire_generation,
    output reg fault,output reg [7:0] fault_code
);
    localparam [2:0] IDLE=0,OFFER=1,WAIT_RAW=2,MODE_OFFER=3,WAIT_MODE=4,FEEDBACK=5;
    reg [2:0] state;
    reg [1:0] pending_slot;
    reg [31:0] pending_frame,pending_generation,pending_base,pending_stride,pending_seq;
    reg [2:0] leased;
    reg [31:0] slot_frame[0:2],slot_generation[0:2];
    reg active_valid;reg [1:0] active_slot;reg [31:0] active_frame,active_generation;
    wire cdc_ready,cdc_commit,cdc_error,pixel_cmd_valid,pixel_waiting,pixel_error;
    wire [1:0] unused_mode,unused_slot,pixel_mode,pixel_slot;
    wire [31:0] unused_seq,unused_frame,unused_gen,pixel_seq,pixel_frame,pixel_gen;
    wire unused_data,pixel_data;
    reg [7:0] fault_now;
    reg release_matches,release_is_active;
    wire pixel_accept=pixel_cmd_valid&&pixel_mode==0&&pixel_slot<3&&pixel_frame!=0;
    display_mode_cdc #(.CONTEXT_WIDTH(1)) u_mode(
        .core_clk(clk),.core_reset_n(reset_n),.pixel_clk(pixel_clk),.pixel_reset_n(pixel_reset_n),
        .cmd_valid(state==MODE_OFFER),.cmd_ready(cdc_ready),.cmd_mode(2'd0),.cmd_slot(pending_slot),
        .cmd_seq(pending_seq),.cmd_frame_id(pending_frame),.cmd_generation(pending_generation),.cmd_data(1'b0),
        .commit_valid(cdc_commit),.commit_ready(state==WAIT_MODE&&!fault&&fault_now==0),
        .commit_mode(unused_mode),.commit_slot(unused_slot),.commit_seq(unused_seq),.commit_frame_id(unused_frame),
        .commit_generation(unused_gen),.commit_data(unused_data),
        .pixel_cmd_valid(pixel_cmd_valid),.pixel_cmd_ready(pixel_accept),.pixel_commit(pixel_waiting&&pixel_sof),
        .pixel_cmd_mode(pixel_mode),.pixel_cmd_slot(pixel_slot),.pixel_cmd_seq(pixel_seq),.pixel_cmd_frame_id(pixel_frame),
        .pixel_cmd_generation(pixel_gen),.pixel_cmd_data(pixel_data),.pixel_waiting_commit(pixel_waiting),
        .pixel_protocol_error(pixel_error),.protocol_error(cdc_error));
    assign record_valid=reset_n&&state==OFFER;
    assign record_base=pending_base;assign record_stride=pending_stride;
    assign record_frame=pending_frame;assign record_slot=pending_slot;
    assign feedback_valid=reset_n&&state==FEEDBACK;
    assign feedback_slot=pending_slot;assign feedback_mode=0;
    assign feedback_frame=pending_frame;assign feedback_generation=pending_generation;assign feedback_seq=pending_seq;
    assign cmd_ready=reset_n&&state==IDLE&&!retire_valid&&!fault&&
        raw_commit_valid===1'b0&&raw_release_valid===1'b0&&raw_reject===1'b0&&raw_error===1'b0&&cdc_error===1'b0;
    assign raw_commit_ready=reset_n&&!fault&&state!=FEEDBACK;
    assign raw_release_ready=reset_n&&!fault&&state!=FEEDBACK&&!retire_valid&&release_matches&&fault_now==0;
    wire command_taken=cmd_valid&&cmd_ready;
    wire commit_matches=raw_commit_slot===pending_slot&&raw_commit_frame===pending_frame;
    always @* begin
        release_matches=0;release_is_active=0;
        if((^{raw_release_slot,raw_release_frame})!==1'bx&&raw_release_slot<3)begin
            release_matches=leased[raw_release_slot]&&slot_frame[raw_release_slot]==raw_release_frame&&
                (!active_valid||raw_release_slot!=active_slot);
            release_is_active=active_valid&&raw_release_slot==active_slot&&raw_release_frame==active_frame;
        end
    end
    always @* begin
        fault_now=0;
        if(raw_error!==1'b0)fault_now=1;
        else if(raw_reject!==1'b0)fault_now=2;
        else if(cdc_error!==1'b0)fault_now=3;
        else if(raw_commit_valid===1'b1&&(state!=WAIT_RAW||!commit_matches))fault_now=4;
        // A much older nonactive release must drain even while the next raw
        // record is offered/in flight, or raw's own event ACK guard can stall
        // both parties. The current active release waits for its replacement.
        else if(raw_release_valid===1'b1&&!release_matches&&
            !((state==WAIT_RAW||state==FEEDBACK)&&release_is_active))fault_now=5;
        else if(command_taken)begin
            if((^{cmd_mode_only,cmd_slot,cmd_mode,cmd_frame,cmd_generation,cmd_base,cmd_stride,cmd_seq})===1'bx||
                cmd_slot>2||cmd_frame==0||cmd_mode!=0||cmd_stride!=2400||
                cmd_base!=(32'h82000000+{30'd0,cmd_slot}*32'h200000))fault_now=6;
            else if(cmd_mode_only)begin
                if(!active_valid||cmd_slot!=active_slot||cmd_frame!=active_frame||cmd_generation!=active_generation)fault_now=7;
            end else if(leased[cmd_slot])fault_now=8;
        end
        if(fault_now==0&&((raw_commit_valid!==1'b0&&raw_commit_valid!==1'b1)||
            (raw_release_valid!==1'b0&&raw_release_valid!==1'b1)||
            (cmd_valid!==1'b0&&cmd_valid!==1'b1)||
            (record_valid&&record_ready!==1'b0&&record_ready!==1'b1)))fault_now=9;
    end
    integer k;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;pending_slot<=0;pending_frame<=0;pending_generation<=0;pending_base<=0;pending_stride<=0;pending_seq<=0;
            leased<=0;active_valid<=0;active_slot<=0;active_frame<=0;active_generation<=0;
            retire_valid<=0;retire_slot<=0;retire_frame<=0;retire_generation<=0;fault<=0;fault_code<=0;
            for(k=0;k<3;k=k+1)begin slot_frame[k]<=0;slot_generation[k]<=0;end
        end else begin
            if(!fault&&fault_now!=0)begin fault<=1;fault_code<=fault_now;end
            if(retire_valid&&retire_ready)begin retire_valid<=0;leased[retire_slot]<=0;end
            if(raw_release_valid&&raw_release_ready)begin
                retire_valid<=1;retire_slot<=raw_release_slot;retire_frame<=raw_release_frame;
                retire_generation<=slot_generation[raw_release_slot];
            end
            case(state)
                IDLE:if(command_taken&&fault_now==0)begin
                    pending_slot<=cmd_slot;pending_frame<=cmd_frame;pending_generation<=cmd_generation;
                    pending_base<=cmd_base;pending_stride<=cmd_stride;pending_seq<=cmd_seq;
                    if(cmd_mode_only)state<=MODE_OFFER;
                    else begin
                        leased[cmd_slot]<=1;slot_frame[cmd_slot]<=cmd_frame;slot_generation[cmd_slot]<=cmd_generation;
                        state<=OFFER;
                    end
                end
                OFFER:if(record_ready)state<=WAIT_RAW; // Published record survives a later fault.
                WAIT_RAW:if(raw_commit_valid&&raw_commit_ready&&!fault&&fault_now==0)begin
                    active_valid<=1;active_slot<=pending_slot;active_frame<=pending_frame;active_generation<=pending_generation;
                    state<=FEEDBACK;
                end
                MODE_OFFER:if(cdc_ready)state<=WAIT_MODE;
                WAIT_MODE:if(cdc_commit&&!fault&&fault_now==0)state<=FEEDBACK;
                FEEDBACK:if(feedback_ready)state<=IDLE; // Historical proven event remains valid through a later fault.
                default:begin end
            endcase
        end
    end
endmodule
`default_nettype wire
