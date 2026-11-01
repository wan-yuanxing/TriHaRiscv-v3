// Four-phase bundled-data mailbox. Payload remains held until the complete
// req/ack return-to-zero cycle. Physical data/control delays require constraints.
module cdc_payload_mailbox #(parameter integer WIDTH=32)(
    input wire sclk, dclk, srst_n, drst_n,
    input wire s_valid, output wire s_ready, input wire [WIDTH-1:0] s_data,
    output wire d_valid, input wire d_ready, output reg [WIDTH-1:0] d_data,
    output wire s_active, d_active
);
    wire arst_n=srst_n && drst_n;
    (* syn_preserve=1 *) reg [2:0] s_release,d_release;
    always @(posedge sclk or negedge arst_n)
        if(!arst_n)s_release<=0;else s_release<={s_release[1:0],1'b1};
    always @(posedge dclk or negedge arst_n)
        if(!arst_n)d_release<=0;else d_release<={d_release[1:0],1'b1};
    wire s_local_n=s_release[2], d_local_n=d_release[2];
    (* syn_preserve=1 *) reg s_peer_meta,s_peer_sync,d_peer_meta,d_peer_sync;
    always @(posedge sclk or negedge s_local_n)
        if(!s_local_n)begin s_peer_meta<=0;s_peer_sync<=0;end
        else begin s_peer_meta<=d_local_n;s_peer_sync<=s_peer_meta;end
    always @(posedge dclk or negedge d_local_n)
        if(!d_local_n)begin d_peer_meta<=0;d_peer_sync<=0;end
        else begin d_peer_meta<=s_local_n;d_peer_sync<=d_peer_meta;end
    assign s_active=arst_n && s_local_n && s_peer_sync;
    assign d_active=arst_n && d_local_n && d_peer_sync;
    (* syn_preserve=1 *) reg req,ack,req_meta,req_sync,ack_meta,ack_sync;
    (* syn_preserve=1 *) reg [WIDTH-1:0] payload_hold;
    reg valid_hold;
    always @(posedge sclk or negedge s_local_n)
        if(!s_local_n)begin ack_meta<=0;ack_sync<=0;end
        else begin ack_meta<=ack;ack_sync<=ack_meta;end
    always @(posedge dclk or negedge d_local_n)
        if(!d_local_n)begin req_meta<=0;req_sync<=0;end
        else begin req_meta<=req;req_sync<=req_meta;end
    assign s_ready=s_active && !req && !ack_sync;
    assign d_valid=d_active && valid_hold;
    always @(posedge sclk or negedge s_local_n) begin
        if(!s_local_n)begin req<=0;payload_hold<=0;end
        else if(s_active)begin
            if(s_valid && s_ready)begin payload_hold<=s_data;req<=1;end
            else if(req && ack_sync)req<=0;
        end
    end
    always @(posedge dclk or negedge d_local_n) begin
        if(!d_local_n)begin ack<=0;valid_hold<=0;d_data<=0;end
        else if(d_active)begin
            if(!req_sync)ack<=0;
            else if(!ack && !valid_hold)begin d_data<=payload_hold;valid_hold<=1;end
            if(d_valid && d_ready)begin valid_hold<=0;ack<=1;end
        end
    end
endmodule
