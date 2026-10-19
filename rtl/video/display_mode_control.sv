`timescale 1ns/1ps
`default_nettype none
// Core-domain request sequencer. A command's context is immutable once exposed.
// The downstream owner must atomically apply raw/context/mode at a safe raster
// boundary and return that actual commit. This module never releases a raw slot.
// Caller validates the context, and changes generation whenever its data changes.
module display_mode_control #(parameter integer CONTEXT_WIDTH=128)(
    input wire clk,reset_n,
    input wire request_valid,output wire request_ready,input wire [1:0] request_mode,
    output reg reject_valid,input wire reject_ready,output reg [1:0] rejected_mode,
    output reg [31:0] rejected_requests,
    input wire context_valid,input wire [31:0] context_frame_id,context_generation,
    input wire [1:0] context_slot,input wire [CONTEXT_WIDTH-1:0] context_data,
    input wire [2:0] capabilities,input wire result_valid,result_empty,avatar_ready,
    input wire [31:0] result_frame_id,
    output reg [1:0] requested_mode,active_mode,
    output reg [31:0] request_seq,committed_seq,
    output reg active_valid,output reg [31:0] active_frame_id,active_generation,
    output reg [1:0] active_slot,output reg [CONTEXT_WIDTH-1:0] active_data,
    output wire pending,unavailable,output reg protocol_error,
    output reg [31:0] request_count,command_count,commit_count,coalesced_count,protocol_errors,
    output reg cmd_valid,input wire cmd_ready,output reg [1:0] cmd_mode,cmd_slot,
    output reg [31:0] cmd_seq,cmd_frame_id,cmd_generation,
    output reg [CONTEXT_WIDTH-1:0] cmd_data,
    input wire commit_valid,output wire commit_ready,input wire [1:0] commit_mode,commit_slot,
    input wire [31:0] commit_seq,commit_frame_id,commit_generation
);
    reg awaiting_commit,desired_dirty,command_covers_desire;
    wire request_taken=request_valid&&request_ready;
    wire result_matches=result_valid&&result_frame_id==context_frame_id;
    wire qualified=context_valid&&context_frame_id!=0&&context_slot<3&&capabilities[requested_mode]&&
        (requested_mode==0||(result_matches&&(requested_mode==1||result_empty||avatar_ready)));
    wire needs_commit=!active_valid||desired_dirty||requested_mode!=active_mode||
        context_frame_id!=active_frame_id||context_slot!=active_slot||context_generation!=active_generation;
    wire feedback_matches=commit_mode==cmd_mode&&commit_seq==cmd_seq&&commit_frame_id==cmd_frame_id&&
        commit_slot==cmd_slot&&commit_generation==cmd_generation;
    wire current_desire_frozen=(cmd_valid||awaiting_commit)&&command_covers_desire;
    assign request_ready=!reject_valid||reject_ready;
    assign commit_ready=awaiting_commit;
    assign unavailable=!capabilities[requested_mode];
    assign pending=cmd_valid||awaiting_commit||!context_valid||needs_commit;
    generate if(CONTEXT_WIDTH<1)begin:invalid_parameters
        initial $fatal(1,"MODE context width must be positive");
    end endgenerate
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            requested_mode<=0;request_seq<=0;desired_dirty<=0;command_covers_desire<=0;
            reject_valid<=0;rejected_mode<=0;rejected_requests<=0;
            cmd_valid<=0;cmd_mode<=0;cmd_seq<=0;cmd_frame_id<=0;cmd_slot<=0;cmd_generation<=0;cmd_data<=0;
            awaiting_commit<=0;
            active_valid<=0;active_mode<=0;committed_seq<=0;
            active_frame_id<=0;active_slot<=0;active_generation<=0;active_data<=0;
            request_count<=0;command_count<=0;commit_count<=0;coalesced_count<=0;
            protocol_error<=0;protocol_errors<=0;
        end else begin
            if(reject_valid&&reject_ready)reject_valid<=0;
            if(request_taken)begin
                if(request_mode<3)begin
                    requested_mode<=request_mode;request_seq<=request_seq+1'b1;
                    desired_dirty<=1;command_covers_desire<=0;request_count<=request_count+1'b1;
                    if(desired_dirty&&!current_desire_frozen)
                        coalesced_count<=coalesced_count+1'b1;
                end else begin
                    reject_valid<=1;rejected_mode<=request_mode;rejected_requests<=rejected_requests+1'b1;
                end
            end
            // A simultaneous request supersedes preparation, but never an
            // already exposed offer or accepted downstream transaction.
            if(!cmd_valid&&!awaiting_commit&&!request_taken&&qualified&&needs_commit)begin
                cmd_valid<=1;cmd_mode<=requested_mode;cmd_seq<=request_seq;
                cmd_frame_id<=context_frame_id;cmd_slot<=context_slot;
                cmd_generation<=context_generation;cmd_data<=context_data;
                command_covers_desire<=1;
            end
            if(cmd_valid&&cmd_ready)begin
                cmd_valid<=0;awaiting_commit<=1;command_count<=command_count+1'b1;
            end
            if(commit_valid&&commit_ready)begin
                if(feedback_matches)begin
                    awaiting_commit<=0;active_valid<=1;active_mode<=cmd_mode;committed_seq<=cmd_seq;
                    active_frame_id<=cmd_frame_id;active_slot<=cmd_slot;
                    active_generation<=cmd_generation;active_data<=cmd_data;commit_count<=commit_count+1'b1;
                    command_covers_desire<=0;
                    // Sequence equality cannot prove freshness after a full
                    // modulo wrap. Any later legal request invalidates this
                    // command's coverage, including one accepted on this edge.
                    if(command_covers_desire&&!(request_taken&&request_mode<3))desired_dirty<=0;
                end else begin protocol_error<=1;protocol_errors<=protocol_errors+1'b1;end
            end
        end
    end
endmodule
`default_nettype wire
