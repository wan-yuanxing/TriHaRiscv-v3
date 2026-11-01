// sqrt(RNE_F32(p*2^-32)), bounded p=qcls*qobj. No floating point IP.
module b03_score_root(
    input wire clk,clear,run_ce,in_valid,output wire in_ready,
    input wire [31:0] product,candidate_id,epoch,
    output wire out_valid,input wire out_ready,output reg out_error,
    output reg [31:0] score,out_id,out_epoch,cycles,output wire [63:0] sort_key,
    output wire busy,output wire [2:0] debug_state,output wire [4:0] debug_digit
);
    localparam IDLE=0,NORMALIZE=1,SETUP=2,ROOT=3,PACK=4,HOLD=5;
    reg [2:0] state;reg [31:0] p;
    reg [5:0] leading;reg [47:0] radicand;
    reg [23:0] root;reg [49:0] remainder;reg [4:0] digit;
    reg signed [8:0] target_exponent;
    integer i,shift;reg [24:0] mantissa,rounded;
    reg [31:0] residue,half;reg signed [8:0] exponent;
    reg [49:0] trial,next_remainder;reg [23:0] next_root;
    assign in_ready=state==IDLE||(state==HOLD&&out_ready);assign out_valid=state==HOLD;assign busy=state!=IDLE;
    assign sort_key={~score,out_id};assign debug_state=state;assign debug_digit=digit;
    always @(posedge clk)begin
        if(clear)begin
            state<=IDLE;p<=0;leading<=0;radicand<=0;root<=0;remainder<=0;digit<=0;target_exponent<=0;
            score<=0;out_id<=0;out_epoch<=0;cycles<=0;out_error<=0;
        end else if(run_ce)begin
            if(state!=IDLE&&state!=HOLD)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(in_valid)begin
                    p<=product;out_id<=candidate_id;out_epoch<=epoch;score<=0;cycles<=0;out_error<=product>32'hfffe0001;
                    state<=product==0||product>32'hfffe0001 ? HOLD:NORMALIZE;
                end
                NORMALIZE:begin
                    leading<=0;
                    for(i=0;i<32;i=i+1)if(p[i])leading<=i;
                    state<=SETUP;
                end
                SETUP:begin
                    shift=$signed({1'b0,leading})-23;
                    if(shift>0)begin
                        mantissa=p>>shift;residue=p&((32'd1<<shift)-1);half=32'd1<<(shift-1);
                        if(residue>half||(residue==half&&mantissa[0]))mantissa=mantissa+1'b1;
                    end else mantissa={1'b0,p[23:0]}<<(-shift);
                    exponent=$signed({1'b0,leading})-32;
                    if(mantissa[24])begin mantissa=mantissa>>1;exponent=exponent+1'b1;end
                    target_exponent<=exponent>>>1;
                    radicand<={24'b0,mantissa[23:0]}<<(23+exponent[0]);
                    root<=0;remainder<=0;digit<=23;state<=ROOT;
                end
                ROOT:begin
                    next_remainder=(remainder<<2)|((radicand>>(2*digit))&48'd3);
                    trial=({26'b0,root}<<2)|50'd1;
                    if(next_remainder>=trial)begin next_remainder=next_remainder-trial;next_root=(root<<1)|24'd1;end
                    else next_root=root<<1;
                    remainder<=next_remainder;root<=next_root;
                    if(digit==0)state<=PACK;else digit<=digit-1'b1;
                end
                PACK:begin
                    rounded={1'b0,root}+(remainder>{26'b0,root});
                    exponent=target_exponent+127;
                    if(rounded[24])begin rounded=rounded>>1;exponent=exponent+1'b1;end
                    score<={1'b0,exponent[7:0],rounded[22:0]};state<=HOLD;
                end
                HOLD:if(out_ready)begin
                    if(in_valid)begin
                        p<=product;out_id<=candidate_id;out_epoch<=epoch;score<=0;cycles<=0;out_error<=product>32'hfffe0001;
                        state<=product==0||product>32'hfffe0001 ? HOLD:NORMALIZE;
                    end else state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
