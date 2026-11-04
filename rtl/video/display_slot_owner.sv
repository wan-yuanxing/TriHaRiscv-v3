`timescale 1ns/1ps
`default_nettype none
`include "video_cfg.vh"
// Core-domain display references only. The caller validates result/material
// context; the downstream consumer supplies actual commit and complete DMA,
// bank and pixel retirement proofs. FREE here does not imply globally free.
// Reset must be coordinated with every consumer of the recorded references.
module display_slot_owner #(parameter integer CONTEXT_WIDTH=128)(
    input wire clk_i,rst_ni,
    input wire submit_valid_i,output wire submit_ready_o,
    input wire submit_mode_only_i,input wire [1:0] submit_slot_i,submit_mode_i,
    input wire [31:0] submit_frame_i,submit_generation_i,submit_base_i,submit_stride_i,submit_seq_i,
    input wire [CONTEXT_WIDTH-1:0] submit_data_i,
    output reg reject_valid_o,input wire reject_ready_i,
    output reg [7:0] reject_code_o,output reg [31:0] reject_seq_o,
    output reg cmd_valid_o,input wire cmd_ready_i,output reg cmd_mode_only_o,
    output reg [1:0] cmd_slot_o,cmd_mode_o,
    output reg [31:0] cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,
    output reg [CONTEXT_WIDTH-1:0] cmd_data_o,
    input wire feedback_valid_i,output wire feedback_ready_o,
    input wire [1:0] feedback_slot_i,feedback_mode_i,
    input wire [31:0] feedback_frame_i,feedback_generation_i,feedback_seq_i,
    output reg commit_valid_o,input wire commit_ready_i,output reg commit_mode_only_o,
    output reg [1:0] commit_slot_o,commit_mode_o,
    output reg [31:0] commit_frame_o,commit_generation_o,commit_seq_o,
    input wire retire_valid_i,output wire retire_ready_o,input wire [1:0] retire_slot_i,
    input wire [31:0] retire_frame_i,retire_generation_i,
    output reg release_valid_o,input wire release_ready_i,output reg [1:0] release_slot_o,
    output reg [31:0] release_frame_o,release_generation_o,
    output reg active_valid_o,output reg [1:0] active_slot_o,active_mode_o,
    output reg [31:0] active_frame_o,active_generation_o,active_base_o,active_stride_o,active_seq_o,
    output reg [CONTEXT_WIDTH-1:0] active_data_o,
    output wire [2:0] slot_free_o,output reg protocol_error_o,output reg [7:0] error_code_o,
    output reg [31:0] submits_o,commits_o,releases_o,rejected_o
);
    localparam [2:0] FREE=0,RESERVED=1,ACTIVE=2,RETIRING=3,WAIT_ACK=4;
    reg [2:0] slot_state[0:2];
    reg [31:0] slot_frame[0:2],slot_generation[0:2];
    reg awaiting_commit;
    integer k;
    generate
        if(CONTEXT_WIDTH<1)begin:invalid_width
            initial $fatal(1,"DISPLAY slot context width must be positive");
        end
        for(genvar s=0;s<3;s=s+1)begin:free_status
            assign slot_free_o[s]=slot_state[s]==FREE;
        end
    endgenerate
    function automatic [31:0] slot_base(input [1:0] slot);
        case(slot)
            0:slot_base=`VIDEO_FRAME_SLOT_A;
            1:slot_base=`VIDEO_FRAME_SLOT_B;
            2:slot_base=`VIDEO_FRAME_SLOT_C;
            default:slot_base=0;
        endcase
    endfunction
    // Preserve word boundaries: a single very wide equality maps to a
    // linear carry chain in PDS. Four-state != and OR semantics are unchanged.
    localparam integer COMPARE_GROUPS=(CONTEXT_WIDTH+31)/32;
    (* syn_keep=1 *) wire [COMPARE_GROUPS-1:0] context_difference;
    generate for(genvar g=0;g<COMPARE_GROUPS;g=g+1)begin:context_compare
        localparam integer BITS=(CONTEXT_WIDTH-g*32<32)?CONTEXT_WIDTH-g*32:32;
        assign context_difference[g]=(submit_data_i[g*32+:BITS]!=active_data_o[g*32+:BITS]);
    end endgenerate
    wire context_changed=|context_difference;
    // Bound the native carry depth of identity comparisons without adding a
    // cycle to submit, feedback or retirement handshakes.
    wire [127:0] submitted_identity={submit_frame_i,submit_generation_i,submit_base_i,submit_stride_i};
    wire [127:0] active_identity={active_frame_o,active_generation_o,active_base_o,active_stride_o};
    (* syn_keep=1 *) wire [7:0] mode_identity_difference;
    generate for(genvar part=0;part<8;part=part+1)begin:g_mode_identity
        assign mode_identity_difference[part]=(submitted_identity[part*16+:16]!=active_identity[part*16+:16]);
    end endgenerate
    reg [7:0] submission_error;
    always @* begin
        submission_error=0;
        if((^{submit_mode_only_i,submit_slot_i,submit_mode_i,submit_frame_i,submit_generation_i,
              submit_base_i,submit_stride_i,submit_seq_i,submit_data_i})===1'bx)submission_error=1;
        else if(submit_slot_i==3||submit_frame_i==0)submission_error=2;
        else if(submit_base_i!=slot_base(submit_slot_i)||submit_stride_i!=`VIDEO_FRAME_RAW_STRIDE)
            submission_error=3;
        else if(submit_mode_i==3)submission_error=4;
        else if(submit_mode_only_i)begin
            if(!active_valid_o||submit_slot_i!=active_slot_o||(|mode_identity_difference)||context_changed)submission_error=6;
        end else if(slot_state[submit_slot_i]!=FREE)submission_error=5;
    end
    // Offers/feedback never share an acceptance edge. This also makes incoming
    // protocol failures stop new submissions without a late rollback path.
    assign submit_ready_o=rst_ni&&!protocol_error_o&&!cmd_valid_o&&!awaiting_commit&&
        !commit_valid_o&&!reject_valid_o&&!feedback_valid_i&&!retire_valid_i;
    assign feedback_ready_o=rst_ni&&!commit_valid_o;
    assign retire_ready_o=rst_ni&&!release_valid_o;
    wire feedback_taken=feedback_valid_i&&feedback_ready_o;
    wire [99:0] feedback_identity={feedback_slot_i,feedback_mode_i,feedback_frame_i,feedback_generation_i,feedback_seq_i};
    wire [99:0] command_identity={cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,cmd_seq_o};
    (* syn_keep=1 *) wire [6:0] feedback_identity_matches;
    generate for(genvar part=0;part<7;part=part+1)begin:g_feedback_identity
        localparam integer BITS=part==6?4:16;
        assign feedback_identity_matches[part]=(feedback_identity[part*16+:BITS]===command_identity[part*16+:BITS]);
    end endgenerate
    wire feedback_matches=awaiting_commit&&(&feedback_identity_matches);
    wire new_frame_committed=feedback_taken&&feedback_matches&&!cmd_mode_only_o;
    reg retirement_matches;
    always @* begin
        retirement_matches=0;
        if((^{retire_slot_i,retire_frame_i,retire_generation_i})!==1'bx&&retire_slot_i<3)begin
            retirement_matches=(retire_frame_i==slot_frame[retire_slot_i]&&
                retire_generation_i==slot_generation[retire_slot_i])&&
                (slot_state[retire_slot_i]==RETIRING||
                 (new_frame_committed&&active_valid_o&&retire_slot_i==active_slot_o));
        end
    end
    wire retirement_taken=retire_valid_i&&retire_ready_o;
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            for(k=0;k<3;k=k+1)begin slot_state[k]<=FREE;slot_frame[k]<=0;slot_generation[k]<=0;end
            awaiting_commit<=0;cmd_valid_o<=0;cmd_mode_only_o<=0;cmd_slot_o<=0;cmd_mode_o<=0;
            cmd_frame_o<=0;cmd_generation_o<=0;cmd_base_o<=0;cmd_stride_o<=0;cmd_seq_o<=0;cmd_data_o<=0;
            reject_valid_o<=0;reject_code_o<=0;reject_seq_o<=0;
            commit_valid_o<=0;commit_mode_only_o<=0;commit_slot_o<=0;commit_mode_o<=0;
            commit_frame_o<=0;commit_generation_o<=0;commit_seq_o<=0;
            release_valid_o<=0;release_slot_o<=0;release_frame_o<=0;release_generation_o<=0;
            active_valid_o<=0;active_slot_o<=0;active_mode_o<=0;active_frame_o<=0;active_generation_o<=0;
            active_base_o<=0;active_stride_o<=0;active_seq_o<=0;active_data_o<=0;
            protocol_error_o<=0;error_code_o<=0;submits_o<=0;commits_o<=0;releases_o<=0;rejected_o<=0;
        end else begin
            if(reject_valid_o&&reject_ready_i)reject_valid_o<=0;
            if(commit_valid_o&&commit_ready_i)commit_valid_o<=0;
            if(release_valid_o&&release_ready_i)begin
                release_valid_o<=0;slot_state[release_slot_o]<=FREE;releases_o<=releases_o+1'b1;
            end
            if(submit_valid_i&&submit_ready_o)begin
                if(submission_error!=0)begin
                    reject_valid_o<=1;reject_code_o<=submission_error;reject_seq_o<=submit_seq_i;
                    rejected_o<=rejected_o+1'b1;
                end else begin
                    cmd_valid_o<=1;cmd_mode_only_o<=submit_mode_only_i;cmd_slot_o<=submit_slot_i;
                    cmd_mode_o<=submit_mode_i;cmd_frame_o<=submit_frame_i;cmd_generation_o<=submit_generation_i;
                    cmd_base_o<=submit_base_i;cmd_stride_o<=submit_stride_i;cmd_seq_o<=submit_seq_i;
                    cmd_data_o<=submit_data_i;submits_o<=submits_o+1'b1;
                    if(!submit_mode_only_i)begin
                        slot_state[submit_slot_i]<=RESERVED;slot_frame[submit_slot_i]<=submit_frame_i;
                        slot_generation[submit_slot_i]<=submit_generation_i;
                    end
                end
            end
            if(cmd_valid_o&&cmd_ready_i)begin cmd_valid_o<=0;awaiting_commit<=1;end
            if(feedback_taken&&feedback_matches)begin
                awaiting_commit<=0;active_valid_o<=1;active_slot_o<=cmd_slot_o;active_mode_o<=cmd_mode_o;
                active_frame_o<=cmd_frame_o;active_generation_o<=cmd_generation_o;active_base_o<=cmd_base_o;
                active_stride_o<=cmd_stride_o;active_seq_o<=cmd_seq_o;active_data_o<=cmd_data_o;
                commit_valid_o<=1;commit_mode_only_o<=cmd_mode_only_o;commit_slot_o<=cmd_slot_o;
                commit_mode_o<=cmd_mode_o;commit_frame_o<=cmd_frame_o;commit_generation_o<=cmd_generation_o;
                commit_seq_o<=cmd_seq_o;commits_o<=commits_o+1'b1;
                if(!cmd_mode_only_o)begin
                    if(active_valid_o)slot_state[active_slot_o]<=RETIRING;
                    slot_state[cmd_slot_o]<=ACTIVE;
                end
            end
            // This follows commit so an exact same-edge retirement of the old
            // active record goes to WAIT_ACK, without losing its proof.
            if(retirement_taken&&retirement_matches)begin
                slot_state[retire_slot_i]<=WAIT_ACK;release_valid_o<=1;release_slot_o<=retire_slot_i;
                release_frame_o<=retire_frame_i;release_generation_o<=retire_generation_i;
            end
            if(!protocol_error_o)begin
                if(feedback_taken&&!feedback_matches)begin
                    protocol_error_o<=1;error_code_o<=awaiting_commit?8'he2:8'he1;
                end else if(retirement_taken&&!retirement_matches)begin
                    protocol_error_o<=1;error_code_o<=8'he3;
                end
            end
        end
    end
endmodule
`default_nettype wire
