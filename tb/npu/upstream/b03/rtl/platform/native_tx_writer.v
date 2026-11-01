// HMIC native write direction. No WVALID/B. Completion is transport-only.
module native_tx_writer #(parameter integer STALL_LIMIT=1000000)(
    input wire clk,rst_n,link_active,init_done,init_fail,align_error,
    input wire cmd_valid,output wire cmd_ready,
    input wire [31:0] cmd_offset,cmd_tag,cmd_id,cmd_epoch,
    input wire [4:0] cmd_beats,input wire [2:0] cmd_client,
    input wire cancel_valid,input wire [31:0] cancel_tag,
    input wire fifo_valid,output wire fifo_ready,input wire [5:0] fifo_available,
    input wire [255:0] fifo_data,input wire [31:0] fifo_strb,input wire fifo_last,
    output wire awvalid,input wire awready,output wire [27:0] awaddr,output wire [3:0] awlen,
    input wire wready,input wire [3:0] wid,input wire wlast,
    output wire [255:0] wdata,output wire [31:0] wstrb,
    output wire rsp_valid,input wire rsp_ready,
    output reg [31:0] rsp_tag,rsp_id,rsp_epoch,output reg [2:0] rsp_client,
    output reg [3:0] rsp_status,output reg session_reset_req,output reg [3:0] fault_code
);
    localparam IDLE=0,PREPARE=1,AW=2,DATA=3,DROP=4,RESPONSE=5,ISOLATED=6;
    reg [2:0] state;
    reg [31:0] offset,stalled,cached_cancel;
    reg cached_valid,cancelled;
    reg [4:0] beats,remaining;
    wire legal=cmd_beats>=1 && cmd_beats<=16 && cmd_offset[4:0]==0 &&
        ({1'b0,cmd_offset}+({28'b0,cmd_beats}<<5)<=33'h040000000) &&
        ({1'b0,cmd_offset[11:0]}+{3'b0,cmd_beats,5'b0}<=13'd4096);
    assign cmd_ready=link_active && state==IDLE && !session_reset_req && init_done && !init_fail && !align_error;
    assign awvalid=link_active && state==AW;
    assign awaddr=offset[29:2];
    assign awlen=beats-1'b1;
    wire aw_fire=awvalid && awready;
    wire supply=(state==DATA || aw_fire) && wready;
    assign fifo_ready=link_active && (supply || state==DROP);
    assign wdata=fifo_data;
    assign wstrb=fifo_strb;
    assign rsp_valid=link_active && state==RESPONSE;
    wire active=state==PREPARE || state==AW || state==DATA || state==DROP;
    wire cancel_match=(cancel_valid && cancel_tag==rsp_tag) ||
                      (cached_valid && cached_cancel==rsp_tag);
    wire unexpected=wready && !supply;
    wire bad_meta=supply && fifo_valid && (wid!=0 || wlast!=(remaining==1) || fifo_last!=(remaining==1));
    wire underflow=supply && !fifo_valid;
    wire calib_bad=active && (!init_done || init_fail || align_error);
    wire progress=aw_fire || (supply && fifo_valid) || (state==DROP && fifo_valid) ||
                  (state==PREPARE && fifo_valid && fifo_available>=beats);
    wire timeout_now=active && !progress && STALL_LIMIT>0 && stalled>=STALL_LIMIT-1;
    wire fault_now=unexpected || bad_meta || underflow || calib_bad || timeout_now;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;offset<=0;beats<=0;remaining<=0;stalled<=0;
            cached_cancel<=0;cached_valid<=0;cancelled<=0;
            rsp_tag<=0;rsp_id<=0;rsp_epoch<=0;rsp_client<=0;rsp_status<=0;
            session_reset_req<=0;fault_code<=0;
        end else if(link_active)begin
            if(cancel_valid)begin cached_cancel<=cancel_tag;cached_valid<=1;end
            if(active && cancel_match)cancelled<=1;
            if(!active || progress)stalled<=0;else stalled<=stalled+1'b1;
            if(fault_now && !session_reset_req)begin
                session_reset_req<=1;
                fault_code<=underflow ? 5 : unexpected ? 9 : calib_bad ? 2 : bad_meta ? 6 : 4;
            end
            case(state)
            IDLE:begin
                if(unexpected)state<=ISOLATED;
                else if(cmd_valid && cmd_ready)begin
                    offset<=cmd_offset;beats<=cmd_beats;remaining<=cmd_beats;
                    rsp_tag<=cmd_tag;rsp_id<=cmd_id;rsp_epoch<=cmd_epoch;rsp_client<=cmd_client;
                    cancelled<=0;rsp_status<=0;stalled<=0;
                    if(legal)state<=PREPARE;
                    else begin session_reset_req<=1;fault_code<=1;rsp_status<=8;state<=RESPONSE;end
                end
            end
            PREPARE:begin
                if(session_reset_req || fault_now)begin rsp_status<=8;state<=RESPONSE;end
                else if(cancel_match || cancelled)state<=DROP;
                else if(fifo_available>=beats && fifo_valid)state<=AW;
            end
            AW:begin
                // Preserve offered AW through cancellation, timeout and calibration loss.
                if(aw_fire)state<=DATA;
            end
            DATA:begin end
            DROP:begin
                if(session_reset_req || fault_now)begin rsp_status<=8;state<=RESPONSE;end
                else if(fifo_valid)begin
                    remaining<=remaining-1'b1;
                    if(remaining==1)begin rsp_status<=7;state<=RESPONSE;end
                end
            end
            RESPONSE:if(rsp_valid && rsp_ready)state<=session_reset_req ? ISOLATED : IDLE;
            ISOLATED:state<=ISOLATED;
            default:begin session_reset_req<=1;fault_code<=9;state<=ISOLATED;end
            endcase
            if(supply)begin
                if(underflow)state<=ISOLATED;
                else begin
                    remaining<=remaining-1'b1;
                    if(remaining==1)begin
                        rsp_status<=(session_reset_req || fault_now) ? 8 :
                                    (cancelled || cancel_match) ? 7 : 0;
                        state<=RESPONSE;
                    end
                end
            end
        end
    end
endmodule
