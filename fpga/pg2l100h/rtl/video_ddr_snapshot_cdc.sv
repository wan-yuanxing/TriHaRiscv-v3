`timescale 1ns/1ps
`default_nettype none
// The source holds the entire bundle from request until the NEXT request.
// req/ack cross two flops; destination waits one extra edge after ack before
// sampling. The FDC bounds bundle delay to80ns (< the111ns minimum settling).
module video_ddr_snapshot_cdc #(parameter integer WIDTH=128)(
    input wire src_clk,dst_clk,reset_n,input wire [WIDTH-1:0] src_data,
    output reg [WIDTH-1:0] snapshot,output reg snapshot_pulse
);
    reg request,ack;
    (* syn_preserve=1 *) reg req_meta,req_sync,ack_meta,ack_sync;
    (* syn_preserve=1 *) reg [WIDTH-1:0] stable_status;
    reg pending,capture_pending;
    (* syn_preserve=1 *) reg [1:0] source_release;
    always @(posedge src_clk or negedge reset_n)
        if(!reset_n)source_release<=0;else source_release<={source_release[0],1'b1};
    wire source_reset_n=reset_n && source_release[1];
    always @(posedge src_clk or negedge source_reset_n)begin
        if(!source_reset_n)begin req_meta<=0;req_sync<=0;ack<=0;stable_status<=0;end
        else begin
            req_meta<=request;req_sync<=req_meta;
            if(req_sync!=ack)begin stable_status<=src_data;ack<=req_sync;end
        end
    end
    always @(posedge dst_clk or negedge reset_n)begin
        if(!reset_n)begin
            request<=0;ack_meta<=0;ack_sync<=0;pending<=0;capture_pending<=0;
            snapshot<=0;snapshot_pulse<=0;
        end else begin
            ack_meta<=ack;ack_sync<=ack_meta;snapshot_pulse<=0;
            if(!pending && !capture_pending)begin request<=~request;pending<=1;end
            if(pending && ack_sync==request)begin pending<=0;capture_pending<=1;end
            if(capture_pending)begin snapshot<=stable_status;snapshot_pulse<=1;capture_pending<=0;end
        end
    end
endmodule
`default_nettype wire
