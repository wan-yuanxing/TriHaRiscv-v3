// Frame-chain decoder math: grid was prepared concurrently with table gathering.
// Conversion is still registered before domain validation (100MHz path split).
module b03_decode_math_roundstage(
    input wire clk,clear,run_ce,in_valid,output wire in_ready,
    input wire [1:0] stride_index,input wire [10:0] index,input wire [127:0] table_words,
    input wire [5:0] grid_row_in,grid_col_in,
    input wire [31:0] candidate_id,epoch,
    output wire out_valid,input wire out_ready,output reg out_error,
    output reg [127:0] box_bits,output reg [255:0] box_q40,output reg [63:0] rectangle,
    output reg [20:0] current_area,output reg [31:0] out_id,out_epoch,cycles,
    output wire mul_valid,output wire [24:0] mul_x,output wire [17:0] mul_y,output wire [31:0] mul_epoch,
    input wire [47:0] mul_product,input wire mul_rsp_valid,input wire [1:0] mul_mode,input wire [31:0] mul_rsp_epoch,
    output wire busy,output wire [4:0] debug_state
);
    localparam IDLE=0,CONVERT=1,VALIDATE=2,CENTER=3,ROUND1=4,WAIT1=5,STRIDE=6,SUBTRACT=7,
               ROUND2=8,WAIT2=9,TRUNCATE=10,AREA=11,WAIT_AREA=12,HOLD=13;
    reg [4:0] state;reg [1:0] scale;reg [10:0] position;reg [5:0] grid_row,grid_col;
    reg [127:0] words;
    reg [1:0] convert_index;
    wire signed [63:0] converted_one;wire convert_error_one;
    b03_fp32_q40 cvt(.encoded(words[32*convert_index+:32]),.q(converted_one),.error(convert_error_one));
    reg signed [63:0] dx,dy,width_q,height_q,cx,cy,x,y;
    reg converted_bad;
    reg [127:0] round_inputs;wire [127:0] rounded;wire [63:0] rounded_bits;
    wire round_ready,round_valid,round_error,round_phase,round_busy;wire [31:0] round_epoch;
    b03_q40_round2_stage rounding(.clk(clk),.clear(clear),.run_ce(run_ce),.in_valid(state==ROUND1||state==ROUND2),
        .in_ready(round_ready),.values(round_inputs),.epoch(out_epoch),.phase(state==ROUND2),
        .out_valid(round_valid),.out_ready(state==WAIT1||state==WAIT2),.encoded(rounded_bits),
        .rounded_values(rounded),.out_error(round_error),.out_epoch(round_epoch),.out_phase(round_phase),.busy(round_busy));
    wire [5:0] grid_width=scale==0 ? 6'd40:scale==1 ? 6'd20:6'd10;
    wire [11:0] row_base=scale==0 ? ({6'b0,grid_row}<<5)+({6'b0,grid_row}<<3):
                         scale==1 ? ({6'b0,grid_row}<<4)+({6'b0,grid_row}<<2):
                                    ({6'b0,grid_row}<<3)+({6'b0,grid_row}<<1);
    assign in_ready=state==IDLE&&!round_busy;assign out_valid=state==HOLD;assign busy=state!=IDLE||round_busy;assign debug_state=state;
    assign mul_valid=state==AREA;assign mul_x={14'b0,rectangle[42:32]};assign mul_y={7'b0,rectangle[58:48]};assign mul_epoch=out_epoch;
    reg signed [63:0] tx,ty;reg [63:0] tw,th;
    always @(posedge clk)begin
        if(clear)begin
            state<=IDLE;scale<=0;position<=0;grid_row<=0;grid_col<=0;words<=0;
            dx<=0;dy<=0;width_q<=0;height_q<=0;cx<=0;cy<=0;x<=0;y<=0;round_inputs<=0;converted_bad<=0;convert_index<=0;
            out_error<=0;box_bits<=0;box_q40<=0;rectangle<=0;current_area<=0;out_id<=0;out_epoch<=0;cycles<=0;
        end else if(run_ce)begin
            if(state!=IDLE&&state!=HOLD)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(in_valid)begin
                    scale<=stride_index;position<=index;grid_row<=grid_row_in;grid_col<=grid_col_in;words<=table_words;
                    out_id<=candidate_id;out_epoch<=epoch;cycles<=0;out_error<=0;convert_index<=0;converted_bad<=0;box_bits<=0;box_q40<=0;rectangle<=0;current_area<=0;
                    if(stride_index>2||(stride_index==0&&index>=1600)||(stride_index==1&&index>=400)||(stride_index==2&&index>=100))begin
                        out_error<=1;state<=HOLD;
                    end else state<=CONVERT;
                end
                CONVERT:begin
                    converted_bad<=converted_bad||convert_error_one;
                    case(convert_index)
                        0:dx<=converted_one;
                        1:dy<=converted_one;
                        2:width_q<=converted_one;
                        3:height_q<=converted_one;
                    endcase
                    box_bits[127:64]<=words[127:64];
                    if(convert_index==3)state<=VALIDATE;
                    else convert_index<=convert_index+2'd1;
                end
                VALIDATE:begin
                    if(converted_bad||dx < -(64'sd1024<<40)||dx > (64'sd1024<<40)||dy < -(64'sd1024<<40)||dy > (64'sd1024<<40)||
                       width_q<=0||width_q>(64'sd1024<<40)||height_q<=0||height_q>(64'sd1024<<40)||width_q[0]||height_q[0]||
                       grid_row>=grid_width||grid_col>=grid_width||row_base+{6'b0,grid_col}!={1'b0,position})begin
                        out_error<=1;state<=HOLD;
                    end else state<=CENTER;
                end
                CENTER:begin
                    round_inputs<={$signed({18'b0,grid_row,40'b0})+dy,$signed({18'b0,grid_col,40'b0})+dx};state<=ROUND1;
                end
                ROUND1:if(round_ready)state<=WAIT1;
                WAIT1:if(round_valid)begin
                    if(round_error||round_phase||round_epoch!=out_epoch)begin out_error<=1;state<=HOLD;end
                    else begin cx<=rounded[63:0];cy<=rounded[127:64];state<=STRIDE;end
                end
                STRIDE:begin cx<=cx<<<(3+scale);cy<=cy<<<(3+scale);state<=SUBTRACT;end
                SUBTRACT:begin round_inputs<={cy-(height_q>>>1),cx-(width_q>>>1)};state<=ROUND2;end
                ROUND2:if(round_ready)state<=WAIT2;
                WAIT2:if(round_valid)begin
                    if(round_error||!round_phase||round_epoch!=out_epoch)begin out_error<=1;state<=HOLD;end
                    else begin x<=rounded[63:0];y<=rounded[127:64];box_bits[63:0]<=rounded_bits;state<=TRUNCATE;end
                end
                TRUNCATE:begin
                    tx=x<0 ? -((-x)>>>40):(x>>>40);ty=y<0 ? -((-y)>>>40):(y>>>40);tw=width_q>>40;th=height_q>>40;
                    if(x < -(64'sd1024<<40)||x > (64'sd1024<<40)||y < -(64'sd1024<<40)||y > (64'sd1024<<40)||tw>1024||th>1024)begin out_error<=1;state<=HOLD;end
                    else begin rectangle<={th[15:0],tw[15:0],ty[15:0],tx[15:0]};box_q40<={height_q,width_q,y,x};state<=AREA;end
                end
                AREA:state<=WAIT_AREA;
                WAIT_AREA:if(mul_rsp_valid)begin
                    if(mul_mode!=1||mul_rsp_epoch!=out_epoch||mul_product>48'd1048576)begin out_error<=1;state<=HOLD;end
                    else begin current_area<=mul_product[20:0];state<=HOLD;end
                end
                HOLD:if(out_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
