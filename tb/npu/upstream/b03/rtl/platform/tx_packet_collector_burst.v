// Single-owner compute-domain collector. FIFO owns the data storage.
// release is a trusted, identity-checked transport retirement input; no fence.
module tx_packet_collector_burst #(
    parameter integer STALL_LIMIT = 1000000
)(
    input wire clk, input wire rst_n, input wire link_active,
    input wire cmd_valid, output wire cmd_ready,
    input wire [31:0] cmd_offset, input wire [4:0] cmd_beats,
    input wire [31:0] cmd_id, input wire [31:0] cmd_epoch,
    input wire [2:0] cmd_client,
    input wire data_valid, output wire data_ready,
    input wire [255:0] data, input wire [31:0] strb, input wire last,
    output wire fifo_valid, input wire fifo_ready, input wire [5:0] fifo_free,
    output wire [255:0] fifo_data, output wire [31:0] fifo_strb,
    output wire fifo_last,
    output wire packet_valid, input wire packet_ready,
    output reg [31:0] packet_offset, output reg [4:0] packet_beats,
    output reg [31:0] packet_id, output reg [31:0] packet_epoch,
    output reg [2:0] packet_client,
    input wire abort_req, output reg abort_pending,
    input wire release_valid, output wire release_ready,
    input wire [31:0] release_id, input wire [31:0] release_epoch,
    input wire [2:0] release_client, input wire [3:0] release_status,
    output wire done_valid, input wire done_ready,
    output reg [3:0] done_status,
    output reg session_reset_required,
    output reg [4:0] collected_beats
);
    localparam IDLE=0, COLLECT=1, OFFER=2, WAIT_RELEASE=3, DONE=4, ISOLATED=5;
    reg [2:0] state;
    reg [31:0] stalled;
    wire [32:0] end_offset = {1'b0,cmd_offset}+({28'b0,cmd_beats}<<5);
    wire [7:0] last_column={1'b0,cmd_offset[11:5]}+{3'b0,cmd_beats};
    wire legal=cmd_beats>=1 && cmd_beats<=16 && cmd_offset[4:0]==0 &&
        cmd_offset[31:30]==0 && last_column<=8'd128;
    wire unexpected_release = release_valid && state!=WAIT_RELEASE &&
                              state!=DONE && state!=ISOLATED;
    assign cmd_ready = state==IDLE && link_active && !abort_req &&
                       !release_valid && (!legal || fifo_free>=cmd_beats);
    assign data_ready = state==COLLECT && link_active && !abort_req &&
                        !unexpected_release && fifo_ready;
    assign fifo_valid = state==COLLECT && link_active && !abort_req &&
                        !unexpected_release && data_valid;
    assign fifo_data=data;
    assign fifo_strb=strb;
    assign fifo_last=last;
    // Once offered, only handshake or explicit session invalidation can end it.
    // A spurious release on this edge can coincide with packet acceptance;
    // the latched reset requirement must cover that downstream transaction too.
    assign packet_valid=state==OFFER && link_active;
    assign release_ready=state==WAIT_RELEASE && link_active;
    assign done_valid=state==DONE;
    wire active = state==COLLECT || state==OFFER || state==WAIT_RELEASE;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; stalled<=0; collected_beats<=0;
            packet_offset<=0; packet_beats<=0; packet_id<=0;
            packet_epoch<=0; packet_client<=0; abort_pending<=0;
            done_status<=0; session_reset_required<=0;
        end else if(active && !link_active) begin
            done_status<=5; session_reset_required<=1; state<=DONE;
        end else if(unexpected_release) begin
            done_status<=6; session_reset_required<=1; state<=DONE;
        end else begin
            case(state)
            IDLE: if(cmd_valid && cmd_ready) begin
                packet_offset<=cmd_offset; packet_beats<=cmd_beats;
                packet_id<=cmd_id; packet_epoch<=cmd_epoch; packet_client<=cmd_client;
                collected_beats<=0; stalled<=0; abort_pending<=0; done_status<=0;
                if(legal) state<=COLLECT;
                else begin done_status<=1; state<=DONE; end
            end
            COLLECT: begin
                if(abort_req) begin
                    abort_pending<=1; done_status<=3;
                    session_reset_required<=1; state<=DONE;
                end else if(data_valid && data_ready) begin
                    stalled<=0; collected_beats<=collected_beats+1'b1;
                    if(last!=(collected_beats+1'b1==packet_beats)) begin
                        done_status<=2; session_reset_required<=1; state<=DONE;
                    end else if(collected_beats+1'b1==packet_beats) state<=OFFER;
                end else if(STALL_LIMIT>0 && stalled>=STALL_LIMIT-1) begin
                    done_status<=4; session_reset_required<=1; state<=DONE;
                end else stalled<=stalled+1'b1;
            end
            OFFER: begin
                if(abort_req) abort_pending<=1;
                if(packet_valid && packet_ready) state<=WAIT_RELEASE;
            end
            WAIT_RELEASE: begin
                if(abort_req) abort_pending<=1;
                if(release_valid && release_ready) begin
                    if(release_id!=packet_id || release_epoch!=packet_epoch ||
                       release_client!=packet_client ||
                       !(release_status==0 || release_status==7 || release_status==8)) begin
                        done_status<=6; session_reset_required<=1;
                    end else if(release_status==8) begin
                        done_status<=8; session_reset_required<=1;
                    end else done_status<=(abort_pending || abort_req) ? 7 : release_status;
                    state<=DONE;
                end
            end
            DONE: if(done_ready) state<=session_reset_required ? ISOLATED : IDLE;
            ISOLATED: state<=ISOLATED;
            default: begin session_reset_required<=1; state<=ISOLATED; end
            endcase
        end
    end
endmodule
