// Registered Q40 ROI: input-domain decision and rounding each terminate at registers.
// All state and arithmetic advance on run_ce; clear cancels even while paused.
module b03_roi4_loan_registered(
    input wire clk,clear,run_ce,in_valid,output wire in_ready,
    input wire signed [63:0] x,y,w,h,
    input wire [13:0] source_w,source_h,
    input wire [8:0] resized_w,resized_h,pad_left,pad_top,
    input wire [31:0] epoch,
    output wire mul_req_valid,input wire mul_ready,output wire [31:0] mul_req_epoch,
    output wire [299:0] mul_x,output wire [215:0] mul_y,
    input wire mul_rsp_valid,input wire [575:0] mul_products,
    input wire [31:0] mul_epoch,input wire [1:0] mul_mode,
    output reg out_valid,input wire out_ready,
    output reg [13:0] roi_x,roi_y,roi_w,roi_h,
    output reg out_empty,out_error,output reg [31:0] out_epoch,
    output wire busy,output wire [3:0] debug_state,output wire [3:0] debug_bit,
    output wire [63:0] debug_remainder0
);
    localparam IDLE=0,ENDS=1,SUBPAD=2,CLIP=3,ISSUE=4,WAIT_MUL=5,
               ADD1=6,ADD2=7,DIVIDE=8,ROUND=9,HOLD=10,ROUND_PREP=11,PRECHECK=12;
    reg [3:0] state,bit_count;
    reg input_illegal;
    reg signed [63:0] sx,sy,sw,sh;
    reg [13:0] source[0:3];
    reg [8:0] resize[0:3],padding[0:3];
    reg signed [63:0] endpoint[0:3],delta[0:3];
    reg [48:0] clipped[0:3];
    reg [47:0] part[0:11];
    reg [63:0] sum01[0:3],remainder[0:3],trial[0:3];
    reg [13:0] quotient[0:3];
    reg [31:0] saved_epoch;
    reg [13:0] begin_x,begin_y,end_x,end_y;
    wire illegal=source_w==0 || source_w>8192 || source_h==0 || source_h>8192 ||
                 resized_w==0 || resized_w>320 || resized_h==0 || resized_h>320 ||
                 pad_left>319 || pad_top>319 ||
                 x < -64'sh0004000000000000 || x > 64'sh0004000000000000 ||
                 y < -64'sh0004000000000000 || y > 64'sh0004000000000000 ||
                 w<=0 || w>64'sh0004000000000000 || h<=0 || h>64'sh0004000000000000;
    assign in_ready=run_ce && !clear && (state==IDLE || (state==HOLD && out_ready));
    assign mul_req_valid=state==ISSUE && !clear;
    assign mul_req_epoch=saved_epoch;
    assign busy=state!=IDLE;
    assign debug_state=state;assign debug_bit=bit_count;
    assign debug_remainder0=remainder[0];
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin:operand
        assign mul_x[25*(3*lane)+:25]={1'b0,clipped[lane][23:0]};
        assign mul_x[25*(3*lane+1)+:25]={1'b0,clipped[lane][47:24]};
        assign mul_x[25*(3*lane+2)+:25]={24'b0,clipped[lane][48]};
        assign mul_y[18*(3*lane)+:18]={4'b0,source[lane]};
        assign mul_y[18*(3*lane+1)+:18]={4'b0,source[lane]};
        assign mul_y[18*(3*lane+2)+:18]={4'b0,source[lane]};
    end endgenerate
    integer i;
    reg bad_products;
    reg [63:0] numerator;
    always @(posedge clk)begin
        if(clear)begin
            state<=IDLE;bit_count<=0;input_illegal<=0;out_valid<=0;out_empty<=0;out_error<=0;
            roi_x<=0;roi_y<=0;roi_w<=0;roi_h<=0;out_epoch<=0;saved_epoch<=0;
            begin_x<=0;begin_y<=0;end_x<=0;end_y<=0;
            sx<=0;sy<=0;sw<=0;sh<=0;
            for(i=0;i<4;i=i+1)begin source[i]<=0;resize[i]<=0;padding[i]<=0;
                endpoint[i]<=0;delta[i]<=0;clipped[i]<=0;sum01[i]<=0;
                remainder[i]<=0;trial[i]<=0;quotient[i]<=0;end
            for(i=0;i<12;i=i+1)part[i]<=0;
        end else if(run_ce)begin
            if(out_valid && out_ready)out_valid<=0;
            case(state)
            IDLE,HOLD:begin
                if(state==HOLD && out_valid && out_ready)state<=IDLE;
                if(in_valid && in_ready)begin
                    // Payload capture never depends on the wide domain predicate.
                    // PRECHECK consumes only the captured one-bit decision.
                    saved_epoch<=epoch;out_epoch<=epoch;out_error<=0;out_empty<=0;
                    roi_x<=0;roi_y<=0;roi_w<=0;roi_h<=0;input_illegal<=illegal;
                    sx<=x;sy<=y;sw<=w;sh<=h;
                    source[0]<=source_w;source[1]<=source_w;source[2]<=source_h;source[3]<=source_h;
                    resize[0]<=resized_w;resize[1]<=resized_w;resize[2]<=resized_h;resize[3]<=resized_h;
                    padding[0]<=pad_left;padding[1]<=pad_left;padding[2]<=pad_top;padding[3]<=pad_top;
                    state<=PRECHECK;
                end
            end
            PRECHECK:begin
                if(input_illegal)begin out_error<=1;out_valid<=1;state<=HOLD;end
                else state<=ENDS;
            end
            ENDS:begin endpoint[0]<=sx;endpoint[1]<=sx+sw;endpoint[2]<=sy;endpoint[3]<=sy+sh;state<=SUBPAD;end
            SUBPAD:begin
                for(i=0;i<4;i=i+1)delta[i]<=endpoint[i]-$signed({15'b0,padding[i],40'b0});
                state<=CLIP;
            end
            CLIP:begin
                for(i=0;i<4;i=i+1)begin
                    if(delta[i]<0)clipped[i]<=0;
                    else if(delta[i]>$signed({15'b0,resize[i],40'b0}))clipped[i]<={resize[i],40'b0};
                    else clipped[i]<=delta[i][48:0];
                end
                state<=ISSUE;
            end
            ISSUE:if(mul_ready)state<=WAIT_MUL;
            WAIT_MUL:if(mul_rsp_valid)begin
                bad_products=mul_epoch!=saved_epoch || mul_mode!=3;
                for(i=0;i<12;i=i+1)begin
                    part[i]<=mul_products[48*i+:48];
                    if(|mul_products[48*i+38+:10])bad_products=1;
                end
                if(bad_products)begin out_error<=1;out_valid<=1;state<=HOLD;end
                else state<=ADD1;
            end
            ADD1:begin
                for(i=0;i<4;i=i+1)sum01[i]<={16'b0,part[3*i]}+({16'b0,part[3*i+1]}<<24);
                state<=ADD2;
            end
            ADD2:begin
                for(i=0;i<4;i=i+1)begin
                    numerator=sum01[i]+({16'b0,part[3*i+2]}<<48);
                    remainder[i]<=numerator;trial[i]<={2'b0,resize[i],53'b0};quotient[i]<=0;
                end
                bit_count<=13;state<=DIVIDE;
            end
            DIVIDE:begin
                for(i=0;i<4;i=i+1)begin
                    if(remainder[i]>=trial[i])begin
                        remainder[i]<=remainder[i]-trial[i];quotient[i]<={quotient[i][12:0],1'b1};
                    end else quotient[i]<={quotient[i][12:0],1'b0};
                    trial[i]<=trial[i]>>1;
                end
                if(bit_count==0)state<=ROUND_PREP;
                else bit_count<=bit_count-1'b1;
            end
            ROUND_PREP:begin
                begin_x<=quotient[0];begin_y<=quotient[2];
                end_x<=quotient[1]+(remainder[1]!=0);
                end_y<=quotient[3]+(remainder[3]!=0);
                state<=ROUND;
            end
            ROUND:begin
                out_valid<=1;out_error<=0;out_epoch<=saved_epoch;
                out_empty<=(end_x<=begin_x || end_y<=begin_y);
                if(end_x<=begin_x || end_y<=begin_y)begin roi_x<=0;roi_y<=0;roi_w<=0;roi_h<=0;end
                else begin roi_x<=begin_x;roi_y<=begin_y;roi_w<=end_x-begin_x;roi_h<=end_y-begin_y;end
                state<=HOLD;
            end
            default:state<=IDLE;
            endcase
        end
    end
endmodule
