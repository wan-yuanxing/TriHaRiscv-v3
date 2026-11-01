module b03_mul_pool32_probe(
    input wire clk,clear,run_ce,
    input wire [31:0] in_valid,
    input wire [799:0] x,input wire [575:0] y,
    input wire [1:0] mode,input wire [31:0] epoch,
    output wire [1535:0] products,output wire [31:0] out_valid,
    output wire [63:0] out_modes,output wire [1023:0] out_epochs,output wire busy
);
    wire [31:0] occupied;
    genvar lane;
    generate for(lane=0;lane<32;lane=lane+1)begin:unit
        b03_mul25x18_loan mul(
            .clk(clk),.clear(clear),.run_ce(run_ce),.in_valid(in_valid[lane]),
            .x(x[25*lane+:25]),.y(y[18*lane+:18]),.mode(mode),.epoch(epoch),
            .product(products[48*lane+:48]),.out_valid(out_valid[lane]),
            .out_mode(out_modes[2*lane+:2]),.out_epoch(out_epochs[32*lane+:32]),.busy(occupied[lane]));
    end endgenerate
    assign busy=|occupied;
endmodule
