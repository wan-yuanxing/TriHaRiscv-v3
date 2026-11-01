// UI-domain read reservation/capture. Native RVALID cannot be backpressured.
// rsp_valid reports native capture only; caller holds ownership until local drain.
module native_rx_reserver #(parameter integer STALL_LIMIT=1000000)(
    input wire clk,rst_n,link_active,init_done,init_fail,align_error,
    input wire cmd_valid,output wire cmd_ready,
    input wire [31:0] cmd_offset,cmd_tag,input wire [4:0] cmd_beats,
    input wire cancel_valid,input wire [31:0] cancel_tag,
    input wire [5:0] fifo_free,input wire fifo_ready,
    output wire fifo_valid,output wire [255:0] fifo_data,output wire fifo_last,
    output wire arvalid,input wire arready,output wire [27:0] araddr,output wire [3:0] arlen,
    input wire rvalid,input wire [255:0] rdata,input wire [3:0] rid,input wire rlast,
    output wire rsp_valid,input wire rsp_ready,output reg [31:0] rsp_tag,
    output reg [3:0] rsp_status,output reg [4:0] rsp_count,
    output reg [4:0] reserved_left,output reg session_reset_req,output reg [3:0] fault_code
);
    localparam IDLE=0,RESERVE=1,AR=2,DATA=3,RESPONSE=4,ISOLATED=5;
    reg [2:0] state;
    reg [31:0] offset,stalled,cached_cancel;
    reg cached_valid,cancelled;
    reg [4:0] beats;
    wire legal=cmd_beats>=1 && cmd_beats<=16 && cmd_offset[4:0]==0 &&
        ({1'b0,cmd_offset}+({28'b0,cmd_beats}<<5)<=33'h040000000) &&
        ({1'b0,cmd_offset[11:0]}+{3'b0,cmd_beats,5'b0}<=13'd4096);
    assign cmd_ready=link_active && state==IDLE && !session_reset_req && init_done && !init_fail && !align_error;
    assign arvalid=link_active && state==AR;
    assign araddr=offset[29:2];
    assign arlen=beats-1'b1;
    wire ar_fire=arvalid && arready;
    wire receiving=(state==DATA || ar_fire) && rvalid;
    assign fifo_valid=link_active && receiving;
    assign fifo_data=rdata;
    assign fifo_last=(reserved_left==1);
    assign rsp_valid=link_active && state==RESPONSE;
    wire active=state==RESERVE || state==AR || state==DATA;
    wire cancel_match=(cancel_valid && cancel_tag==rsp_tag) || (cached_valid && cached_cancel==rsp_tag);
    wire overflow=receiving && !fifo_ready;
    wire unexpected=rvalid && !receiving;
    wire bad_meta=receiving && (rid!=0 || rlast!=(reserved_left==1));
    wire calib_bad=active && (!init_done || init_fail || align_error);
    wire progress=ar_fire || receiving || (state==RESERVE && fifo_free>=beats);
    wire timeout_now=active && !progress && STALL_LIMIT>0 && stalled>=STALL_LIMIT-1;
    wire fault_now=overflow || unexpected || bad_meta || calib_bad || timeout_now;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;offset<=0;beats<=0;reserved_left<=0;stalled<=0;
            cached_cancel<=0;cached_valid<=0;cancelled<=0;
            rsp_tag<=0;rsp_status<=0;rsp_count<=0;session_reset_req<=0;fault_code<=0;
        end else if(link_active)begin
            if(cancel_valid)begin cached_cancel<=cancel_tag;cached_valid<=1;end
            if(active && cancel_match)cancelled<=1;
            if(!active || progress)stalled<=0;else stalled<=stalled+1'b1;
            if(fault_now && !session_reset_req)begin
                session_reset_req<=1;
                fault_code<=overflow ? 5 : unexpected ? 9 : calib_bad ? 2 : bad_meta ? 7 : 4;
            end
            case(state)
            IDLE:begin
                if(unexpected)state<=ISOLATED;
                else if(cmd_valid && cmd_ready)begin
                    offset<=cmd_offset;beats<=cmd_beats;rsp_tag<=cmd_tag;
                    rsp_count<=0;reserved_left<=0;cancelled<=0;rsp_status<=0;stalled<=0;
                    if(legal)state<=RESERVE;
                    else begin session_reset_req<=1;fault_code<=1;rsp_status<=8;state<=RESPONSE;end
                end
            end
            RESERVE:begin
                if(session_reset_req || fault_now)begin rsp_status<=8;state<=RESPONSE;end
                else if(cancelled || cancel_match)begin rsp_status<=7;state<=RESPONSE;end
                else if(fifo_free>=beats)begin reserved_left<=beats;state<=AR;end
            end
            AR:if(ar_fire)state<=DATA;
            DATA:begin end
            RESPONSE:if(rsp_valid && rsp_ready)state<=session_reset_req ? ISOLATED : IDLE;
            ISOLATED:state<=ISOLATED;
            default:begin session_reset_req<=1;fault_code<=9;state<=ISOLATED;end
            endcase
            if(receiving)begin
                if(overflow)state<=ISOLATED;
                else begin
                    reserved_left<=reserved_left-1'b1;rsp_count<=rsp_count+1'b1;
                    if(reserved_left==1)begin
                        rsp_status<=(session_reset_req || fault_now) ? 8 : (cancelled || cancel_match) ? 7 : 0;
                        state<=RESPONSE;
                    end
                end
            end
        end
    end
endmodule
