// Exact conversion only. Error for non-normal/nonzero, lost low bits or overflow.
module b03_fp32_q40(input wire [31:0] encoded,output reg signed [63:0] q,output reg error);
    integer shift;reg [63:0] mantissa,magnitude;
    always @* begin
        q=0;error=0;shift=0;mantissa={40'b0,1'b1,encoded[22:0]};magnitude=0;
        if(encoded[30:0]==0)begin q=0;end
        else if(encoded[30:23]==0||encoded[30:23]==255)error=1;
        else begin
            shift=$signed({1'b0,encoded[30:23]})-110;
            if(shift>=0)begin
                if(shift>39)error=1;
                else magnitude=mantissa<<shift;
            end else begin
                if(shift < -23)error=1;
                else begin
                    magnitude=mantissa>>(-shift);
                    if((magnitude<<(-shift))!=mantissa)error=1;
                end
            end
            if(!error)q=encoded[31] ? -$signed(magnitude):$signed(magnitude);
        end
    end
endmodule
