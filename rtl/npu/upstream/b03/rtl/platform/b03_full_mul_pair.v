// Two independent U8/S8 * S8 products in one actual SIMD APM.
// E0 registers X/Y and the first token slot; E1 registers both products.
// The enclosing array consumes that result on E2. No accumulators live here.
module b03_full_mul_pair (
    input wire clk, rst_n, clear, run_ce, in_valid,
    input wire [7:0] in_a0,in_a1,
    input wire input_signed,
    input wire signed [7:0] in_w0, in_w1,
    input wire [7:0] in_k,
    input wire [31:0] in_epoch,
    output wire signed [23:0] product0, product1,
    output wire out_valid,
    output reg [7:0] out_k,
    output reg [31:0] out_epoch,
    output wire busy
);
    reg [1:0] valid_pipe;
    reg [7:0] k0;
    reg [31:0] epoch0;
    wire leaf_clear = !rst_n || clear;
    wire [47:0] packed_product;
    // SIMD uses signed 12x9 lanes. Zero/sign extension follows the locked input type.
    GTP_APM_E2 #(
        .GRS_EN("FALSE"), .USE_SIMD(1), .USE_MULT(1),
        .USE_PREADD(0), .USE_POSTADD(0), .X_REG(1), .Y_REG(1),
        .MULT_REG(1), .P_REG(0), .ASYNC_RST(0)
    ) apm (
        .P(packed_product), .CPO(), .COUT(), .CXO(), .CXBO(),
        .X({6'b0,{4{input_signed && in_a1[7]}},in_a1,{4{input_signed && in_a0[7]}},in_a0}),
        .Y({in_w1[7],in_w1,in_w0[7],in_w0}),
        .XB(25'b0), .Z(48'b0), .CXI(30'b0), .CXBI(25'b0),
        .CPI(48'b0), .CIN(1'b0), .MODEY(3'b0), .MODEZ(4'b0),
        .MODEIN(5'b00010), .CLK(clk),
        .CEX1(run_ce), .CEX2(run_ce), .CEX3(run_ce), .CEXB(run_ce),
        .CEY1(run_ce), .CEY2(run_ce), .CEZ(run_ce), .CEPRE(run_ce),
        .CEM(run_ce), .CEP(run_ce), .CEMODEY(run_ce),
        .CEMODEZ(run_ce), .CEMODEIN(run_ce),
        .RSTX(leaf_clear), .RSTXB(leaf_clear), .RSTY(leaf_clear),
        .RSTZ(leaf_clear), .RSTPRE(leaf_clear), .RSTM(leaf_clear),
        .RSTP(leaf_clear), .RSTMODEY(leaf_clear),
        .RSTMODEZ(leaf_clear), .RSTMODEIN(leaf_clear)
    );
    assign product0 = packed_product[23:0];
    assign product1 = packed_product[47:24];
    assign out_valid = valid_pipe[1];
    assign busy = |valid_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe<=0; k0<=0; epoch0<=0; out_k<=0; out_epoch<=0;
        end else if (clear) begin
            valid_pipe<=0; k0<=0; epoch0<=0; out_k<=0; out_epoch<=0;
        end else if (run_ce) begin
            valid_pipe <= {valid_pipe[0],in_valid};
            k0 <= in_k; epoch0 <= in_epoch;
            out_k <= k0; out_epoch <= epoch0;
        end
    end
endmodule
