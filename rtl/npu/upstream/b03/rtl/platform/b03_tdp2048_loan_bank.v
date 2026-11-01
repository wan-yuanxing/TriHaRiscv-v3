// One original 2048x32 logical A bank, using two unchanged 1024x32 TDPs.
module b03_tdp2048_loan_bank(
    input wire clk,rst_n,run_ce,
    input wire req_a,we_a,input wire [10:0] addr_a,input wire [31:0] data_a,input wire [3:0] mask_a,
    input wire req_b,we_b,input wire [10:0] addr_b,input wire [31:0] data_b,input wire [3:0] mask_b,
    output wire [31:0] q_a,q_b,output reg valid_a,valid_b,output wire conflict,
    output wire busy
);
    assign conflict=rst_n && run_ce && req_a && req_b && addr_a==addr_b && (we_a || we_b);
    wire take_a=rst_n && run_ce && req_a && !conflict;
    wire take_b=rst_n && run_ce && req_b && !conflict;
    reg select_a,select_b;
    wire [31:0] qa0,qa1,qb0,qb1;
    genvar depth;
    generate for(depth=0;depth<2;depth=depth+1)begin:level
        wire [31:0] qa,qb;
        tdp32_probe #(.OUTPUT_REG(0)) ram(
            .clk(clk),.rst_n(rst_n),
            .ce_a(take_a && addr_a[10]==depth),.we_a(we_a),.mask_a(mask_a),
            .addr_a(addr_a[9:0]),.data_a(data_a),
            .ce_b(take_b && addr_b[10]==depth),.we_b(we_b),.mask_b(mask_b),
            .addr_b(addr_b[9:0]),.data_b(data_b),
            .q_a(qa),.q_b(qb),.valid_a(),.valid_b(),.conflict());
        if(depth==0)begin assign qa0=qa;assign qb0=qb;end
        else begin assign qa1=qa;assign qb1=qb;end
    end endgenerate
    assign q_a=select_a ? qa1 : qa0;
    assign q_b=select_b ? qb1 : qb0;
    assign busy=valid_a || valid_b;
    always @(posedge clk)begin
        if(!rst_n)begin valid_a<=0;valid_b<=0;select_a<=0;select_b<=0;end
        else if(run_ce)begin
            valid_a<=take_a && !we_a;valid_b<=take_b && !we_b;
            if(take_a && !we_a)select_a<=addr_a[10];
            if(take_b && !we_b)select_b<=addr_b[10];
        end
    end
endmodule
