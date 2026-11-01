// Optional backup only. Two exact Q40 values share one RNE/reconstruction lane.
module b03_q40_round2_stage(
    input wire clk,clear,run_ce,in_valid,output wire in_ready,input wire [127:0] values,
    input wire [31:0] epoch,input wire phase,
    output wire out_valid,input wire out_ready,output reg [63:0] encoded,
    output reg [127:0] rounded_values,output reg out_error,output reg [31:0] out_epoch,output reg out_phase,
    output wire busy
);
    reg [2:0] state;
    reg lane;
    reg [63:0] second,magnitude;
    reg sign_value;
    reg [5:0] msb;
    reg [23:0] normalized;
    reg signed [6:0] rounded_shift;
    reg [7:0] rounded_exponent;
    reg [63:0] a,m,residue,half,reconstructed;
    reg [24:0] mantissa;
    integer bit_index,shift,exponent;
    reg carry;
    function [2:0] high8;input [7:0] bits;
    begin casez(bits)
        8'b1???????:high8=7;8'b01??????:high8=6;8'b001?????:high8=5;8'b0001????:high8=4;
        8'b00001???:high8=3;8'b000001??:high8=2;8'b0000001?:high8=1;default:high8=0;
    endcase end endfunction
    function [5:0] high63;input [63:0] bits;
        reg [63:0] admitted;reg [7:0] nonzero;reg [2:0] lo[0:7];reg [2:0] hi;integer n;
    begin
        admitted={1'b0,bits[62:0]};
        for(n=0;n<8;n=n+1)begin nonzero[n]=|admitted[8*n+:8];lo[n]=high8(admitted[8*n+:8]);end
        hi=high8(nonzero);high63={hi,lo[hi]};
    end endfunction
    assign in_ready=state==0;assign out_valid=state==3;assign busy=state!=0;
    always @(posedge clk)begin
        if(clear)begin
            state<=0;lane<=0;second<=0;magnitude<=0;sign_value<=0;msb<=0;
            normalized<=0;rounded_shift<=0;rounded_exponent<=0;
            encoded<=0;rounded_values<=0;out_error<=0;out_epoch<=0;out_phase<=0;
        end else if(run_ce)case(state)
            0:if(in_valid)begin
                out_error<=0;out_epoch<=epoch;out_phase<=phase;second<=values[127:64];lane<=0;
                a=values[63:0];m=a[63] ? -a:a;
                magnitude<=m;sign_value<=a[63];msb<=0;

                if(m>=64'h4000000000000000)out_error<=1;
                state<=4;
            end
            4:begin msb<=high63(magnitude);state<=1;end
            1:begin
                m=magnitude;shift=$signed({1'b0,msb})-23;
                if(m==0)begin normalized<=0;rounded_shift<=0;rounded_exponent<=0;end
                else begin
                    if(shift>0)begin
                        mantissa=m>>shift;residue=m&((64'd1<<shift)-1);half=64'd1<<(shift-1);
                        if(residue>half||(residue==half&&mantissa[0]))mantissa=mantissa+1'b1;
                    end else mantissa=m<<(-shift);
                    carry=mantissa[24];
                    if(carry)mantissa=mantissa>>1;
                    exponent=$signed({1'b0,msb})-40+127+carry;
                    shift=shift+carry;
                    normalized<=mantissa[23:0];rounded_shift<=shift;rounded_exponent<=exponent[7:0];
                end
                state<=2;
            end
            2:begin
                shift=$signed(rounded_shift);
                reconstructed=shift>=0 ? ({40'b0,normalized}<<shift):({40'b0,normalized}>>(-shift));
                if(!lane)begin
                    encoded[31:0]<=normalized==0 ? 32'b0:{sign_value,rounded_exponent,normalized[22:0]};
                    rounded_values[63:0]<=sign_value ? -reconstructed:reconstructed;
                    a=second;m=a[63] ? -a:a;
                    magnitude<=m;sign_value<=a[63];msb<=0;
    
                    if(m>=64'h4000000000000000)out_error<=1;
                    lane<=1;state<=4;
                end else begin
                    encoded[63:32]<=normalized==0 ? 32'b0:{sign_value,rounded_exponent,normalized[22:0]};
                    rounded_values[127:64]<=sign_value ? -reconstructed:reconstructed;
                    state<=3;
                end
            end
            3:if(out_ready)state<=0;
        endcase
    end
endmodule
