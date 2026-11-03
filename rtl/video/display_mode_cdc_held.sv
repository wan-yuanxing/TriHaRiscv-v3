`timescale 1ns/1ps
`default_nettype none
// Application-only immutable record lease. The owner MUST keep cmd_data
// stable from command handshake until commit handshake (or coordinated reset).
// Only metadata is copied. The pixel consumer captures the held record once at
// its frame boundary; request/ack toggles prove the complete stable window.
// Board constraints must bound owner record Q to pixel active descriptor D.
// Either reset assertion clears both handshake domains; platform consumers
// and ownership still require coordinated reset before storage may be reused.
module display_mode_cdc_held #(parameter integer CONTEXT_WIDTH=128)(
    input wire core_clk,core_reset_n,pixel_clk,pixel_reset_n,
    input wire cmd_valid,output wire cmd_ready,
    input wire [1:0] cmd_mode,cmd_slot,
    input wire [31:0] cmd_seq,cmd_frame_id,cmd_generation,
    input wire [CONTEXT_WIDTH-1:0] cmd_data,
    output reg commit_valid,input wire commit_ready,
    output wire [1:0] commit_mode,commit_slot,
    output wire [31:0] commit_seq,commit_frame_id,commit_generation,
    output wire [CONTEXT_WIDTH-1:0] commit_data,
    output reg pixel_cmd_valid,input wire pixel_cmd_ready,pixel_commit,
    output wire [1:0] pixel_cmd_mode,pixel_cmd_slot,
    output wire [31:0] pixel_cmd_seq,pixel_cmd_frame_id,pixel_cmd_generation,
    output wire [CONTEXT_WIDTH-1:0] pixel_cmd_data,
    output reg pixel_waiting_commit,pixel_protocol_error,
    output wire protocol_error
);
    generate if(CONTEXT_WIDTH<1)begin:invalid_parameters
        initial $fatal(1,"display_mode_cdc requires positive context width");
    end endgenerate
    wire lease_reset_n=core_reset_n&&pixel_reset_n;
    // Assert either reset immediately; release functional flops only through
    // the destination clock's two-stage chain. Cross-domain reset exceptions
    // apply to these four async C pins only, never to local data/reset fanout.
    (* ASYNC_REG="TRUE" *) reg [1:0] core_release,pixel_release;
    wire core_lease_reset_n=core_release[1];
    wire pixel_lease_reset_n=pixel_release[1];
    always @(posedge core_clk or negedge lease_reset_n)begin
        if(!lease_reset_n)core_release<=0;
        else core_release<={core_release[0],1'b1};
    end
    always @(posedge pixel_clk or negedge lease_reset_n)begin
        if(!lease_reset_n)pixel_release<=0;
        else pixel_release<={pixel_release[0],1'b1};
    end
    reg [99:0] mailbox_payload,pixel_payload;
    reg request_toggle,core_busy,request_seen,pixel_ack;
    (* ASYNC_REG="TRUE" *) reg request_meta,request_sync;
    (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync,error_meta,error_sync;
    assign cmd_ready=core_lease_reset_n&&!core_busy;
    assign pixel_cmd_data=cmd_data;
    assign commit_data=cmd_data;
    assign {pixel_cmd_mode,pixel_cmd_slot,pixel_cmd_seq,pixel_cmd_frame_id,
            pixel_cmd_generation}=pixel_payload;
    // Mailbox remains held through feedback consumption, so no reverse data
    // crossing is needed: the ack identifies this exact in-flight transaction.
    assign {commit_mode,commit_slot,commit_seq,commit_frame_id,
            commit_generation}=mailbox_payload;
    assign protocol_error=error_sync;
    always @(posedge core_clk or negedge core_lease_reset_n)begin
        if(!core_lease_reset_n)begin ack_meta<=0;ack_sync<=0;error_meta<=0;error_sync<=0;end
        else begin ack_meta<=pixel_ack;ack_sync<=ack_meta;
            error_meta<=pixel_protocol_error;error_sync<=error_meta;end
    end
    always @(posedge core_clk or negedge core_lease_reset_n)begin
        if(!core_lease_reset_n)begin mailbox_payload<=0;request_toggle<=0;core_busy<=0;commit_valid<=0;end
        else begin
            if(cmd_valid&&cmd_ready)begin
                mailbox_payload<={cmd_mode,cmd_slot,cmd_seq,cmd_frame_id,cmd_generation};
                request_toggle<=~request_toggle;core_busy<=1;
            end
            if(core_busy&&!commit_valid&&ack_sync==request_toggle)commit_valid<=1;
            if(commit_valid&&commit_ready)begin commit_valid<=0;core_busy<=0;end
        end
    end
    always @(posedge pixel_clk or negedge pixel_lease_reset_n)begin
        if(!pixel_lease_reset_n)begin request_meta<=0;request_sync<=0;end
        else begin request_meta<=request_toggle;request_sync<=request_meta;end
    end
    always @(posedge pixel_clk or negedge pixel_lease_reset_n)begin
        if(!pixel_lease_reset_n)begin
            pixel_payload<=0;request_seen<=0;pixel_ack<=0;
            pixel_cmd_valid<=0;pixel_waiting_commit<=0;pixel_protocol_error<=0;
        end else begin
            if(!pixel_cmd_valid&&!pixel_waiting_commit&&request_sync!=request_seen)begin
                // Source bundle has been stable throughout the two scalar
                // synchronization edges. FDC bounds mailbox Q -> capture D.
                pixel_payload<=mailbox_payload;request_seen<=request_sync;pixel_cmd_valid<=1;
            end
            if(pixel_cmd_valid&&pixel_cmd_ready)begin
                pixel_cmd_valid<=0;pixel_waiting_commit<=1;
            end
            if(pixel_commit)begin
                if(pixel_waiting_commit)begin
                    pixel_waiting_commit<=0;pixel_ack<=request_seen;
                end else pixel_protocol_error<=1;
            end
        end
    end
    // synthesis translate_off
    reg checked_lease;
    reg [CONTEXT_WIDTH-1:0] checked_data;
    always @(posedge core_clk or negedge core_lease_reset_n)begin
        if(!core_lease_reset_n)begin checked_lease<=0;checked_data<=0;end
        else begin
            if(checked_lease&&cmd_data!==checked_data)
                $fatal(1,"HELD_RECORD_SOURCE_CHANGED");
            if(cmd_valid&&cmd_ready)begin checked_lease<=1;checked_data<=cmd_data;end
            if(commit_valid&&commit_ready)checked_lease<=0;
        end
    end
    // synthesis translate_on
endmodule
`default_nettype wire
