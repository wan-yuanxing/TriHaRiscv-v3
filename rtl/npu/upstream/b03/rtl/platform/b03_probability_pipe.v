// One lane of the fixed shared pool; all pipeline stages freeze on advance=0.
module b03_probability_pipe(
    input wire clk,clear,run_ce,in_valid,output wire in_ready,
    input wire [15:0] cls,obj,input wire [31:0] candidate_id,epoch,
    output wire advance,mul_valid,output wire [24:0] mul_x,output wire [17:0] mul_y,
    input wire [47:0] mul_product,input wire mul_rsp_valid,
    input wire [1:0] mul_mode,input wire [31:0] mul_epoch,
    output reg out_valid,input wire out_ready,output reg out_error,
    output reg [31:0] product,out_id,out_epoch,output wire busy
);
    reg v0,v1;reg [31:0] id0,id1,e0,e1;
    assign in_ready=!out_valid||out_ready;assign advance=run_ce&&in_ready;
    assign mul_valid=in_valid&&in_ready;assign mul_x={9'b0,cls};assign mul_y={2'b0,obj};
    assign busy=v0||v1||out_valid;
    always @(posedge clk)begin
        if(clear)begin v0<=0;v1<=0;id0<=0;id1<=0;e0<=0;e1<=0;out_valid<=0;out_error<=0;product<=0;out_id<=0;out_epoch<=0;end
        else if(advance)begin
            v0<=in_valid;v1<=v0;id0<=candidate_id;id1<=id0;e0<=epoch;e1<=e0;
            out_valid<=v1||mul_rsp_valid;
            if(v1||mul_rsp_valid)begin
                product<=mul_product[31:0];out_id<=id1;out_epoch<=e1;
                out_error<=!v1||!mul_rsp_valid||mul_mode!=2||mul_epoch!=e1||mul_product[47:32]!=0;
            end
        end
    end
endmodule
