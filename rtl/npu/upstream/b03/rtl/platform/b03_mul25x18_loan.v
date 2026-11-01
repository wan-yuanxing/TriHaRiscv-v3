// Normal signed multiply mode shared by MODEL and zero-extended POST operands.
// Valid/data/tags advance together. Output may hold valid during run_ce=0.
module b03_mul25x18_loan(
    input wire clk,clear,run_ce,in_valid,
    input wire signed [24:0] x,input wire signed [17:0] y,
    input wire [1:0] mode,input wire [31:0] epoch,
    output wire signed [47:0] product,output wire out_valid,
    output reg [1:0] out_mode,output reg [31:0] out_epoch,output wire busy
);
    reg [1:0] valid_pipe;
    reg [1:0] mode0;
    reg [31:0] epoch0;
    GTP_APM_E2 #(
        .GRS_EN("FALSE"),.USE_SIMD(0),.USE_MULT(1),.USE_PREADD(0),.USE_POSTADD(0),
        .X_REG(1),.Y_REG(1),.MULT_REG(1),.P_REG(0),.ASYNC_RST(0)
    ) apm(
        .P(product),.CPO(),.COUT(),.CXO(),.CXBO(),
        .X({{5{x[24]}},x}),.Y(y),.XB(25'b0),.Z(48'b0),
        .CXI(30'b0),.CXBI(25'b0),.CPI(48'b0),.CIN(1'b0),
        .MODEY(3'b0),.MODEZ(4'b0),.MODEIN(5'b00010),.CLK(clk),
        .CEX1(run_ce),.CEX2(run_ce),.CEX3(run_ce),.CEXB(run_ce),
        .CEY1(run_ce),.CEY2(run_ce),.CEZ(run_ce),.CEPRE(run_ce),.CEM(run_ce),
        .CEP(run_ce),.CEMODEY(run_ce),.CEMODEZ(run_ce),.CEMODEIN(run_ce),
        .RSTX(clear),.RSTXB(clear),.RSTY(clear),.RSTZ(clear),.RSTPRE(clear),
        .RSTM(clear),.RSTP(clear),.RSTMODEY(clear),.RSTMODEZ(clear),.RSTMODEIN(clear));
    assign out_valid=valid_pipe[1];
    assign busy=|valid_pipe;
    always @(posedge clk)begin
        if(clear)begin valid_pipe<=0;mode0<=0;out_mode<=0;epoch0<=0;out_epoch<=0;end
        else if(run_ce)begin
            valid_pipe<={valid_pipe[0],in_valid};
            mode0<=mode;out_mode<=mode0;epoch0<=epoch;out_epoch<=epoch0;
        end
    end
endmodule
