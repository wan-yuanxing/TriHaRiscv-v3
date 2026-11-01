// Complete common A request boundary. RAM contents and collision rules stay in
// the unchanged bank array; clear discards pending commands and read responses.
module b03_bank_array_payload #(
    parameter BANKS=16, WIDTH=32, DEPTH=2048
)(
    input wire clk,rst_n,run_ce,
    input wire [BANKS-1:0] req_a,we_a,req_b,we_b,
    input wire [11*BANKS-1:0] addr_a,addr_b,
    input wire [WIDTH*BANKS-1:0] data_a,data_b,
    input wire [(WIDTH/8)*BANKS-1:0] mask_a,mask_b,
    output wire [WIDTH*BANKS-1:0] q_a,q_b,
    output wire [BANKS-1:0] valid_a,valid_b,
    output wire busy,conflict,range_error
);
    reg [BANKS-1:0] req_a_reg,we_a_reg,req_b_reg,we_b_reg;
    reg [11*BANKS-1:0] addr_a_reg,addr_b_reg;
    reg [WIDTH*BANKS-1:0] data_a_reg,data_b_reg;
    reg [(WIDTH/8)*BANKS-1:0] mask_a_reg,mask_b_reg;
    wire array_busy;
    // spec156: no request can observe these private payloads until captured
    // on the same run_ce edge as its request. RAM reset/valid remain unchanged.
    always @(posedge clk)if(run_ce)begin
        addr_a_reg<=addr_a;addr_b_reg<=addr_b;data_a_reg<=data_a;data_b_reg<=data_b;
        mask_a_reg<=mask_a;mask_b_reg<=mask_b;
    end

    always @(posedge clk)begin
        if(!rst_n)begin
            req_a_reg<=0;we_a_reg<=0;req_b_reg<=0;we_b_reg<=0;
        end else if(run_ce)begin
            req_a_reg<=req_a;we_a_reg<=we_a;req_b_reg<=req_b;we_b_reg<=we_b;
        end
    end
    b03_bank_array #(.BANKS(BANKS),.WIDTH(WIDTH),.DEPTH(DEPTH)) array(
        .clk(clk),.rst_n(rst_n),.run_ce(run_ce),
        .req_a(req_a_reg),.we_a(we_a_reg),.req_b(req_b_reg),.we_b(we_b_reg),
        .addr_a(addr_a_reg),.addr_b(addr_b_reg),.data_a(data_a_reg),.data_b(data_b_reg),
        .mask_a(mask_a_reg),.mask_b(mask_b_reg),.q_a(q_a),.q_b(q_b),
        .valid_a(valid_a),.valid_b(valid_b),.busy(array_busy),.conflict(conflict),.range_error(range_error));
    assign busy=(|req_a_reg)||(|req_b_reg)||array_busy;
endmodule
