// Isolated single-clock TDP probe. Accepted operations advance on ce && !conflict.
module tdp32_probe #(parameter OUTPUT_REG=0)(
    input wire clk,input wire rst_n,
    input wire ce_a,input wire we_a,input wire [3:0] mask_a,
    input wire [9:0] addr_a,input wire [31:0] data_a,
    input wire ce_b,input wire we_b,input wire [3:0] mask_b,
    input wire [9:0] addr_b,input wire [31:0] data_b,
    output wire [31:0] q_a,output wire [31:0] q_b,
    output wire valid_a,output wire valid_b,output wire conflict
);
    assign conflict=rst_n && ce_a && ce_b && (addr_a==addr_b) && (we_a || we_b);
    wire advance_a=rst_n && ce_a && !conflict;
    wire advance_b=rst_n && ce_b && !conflict;
    reg pending_a,pending_b,registered_a,registered_b;
    always @(posedge clk) begin
        if(!rst_n)begin pending_a<=0;pending_b<=0;registered_a<=0;registered_b<=0;end
        else begin
            if(advance_a)begin pending_a<=!we_a;registered_a<=pending_a;end
            if(advance_b)begin pending_b<=!we_b;registered_b<=pending_b;end
        end
    end
    assign valid_a=OUTPUT_REG ? registered_a : pending_a;
    assign valid_b=OUTPUT_REG ? registered_b : pending_b;
    genvar half;
    generate for(half=0;half<2;half=half+1)begin:lane
        wire [17:0] qa,qb;
        GTP_DRM18K_E1 #(
            .GRS_EN("FALSE"),.DATA_WIDTH_A(18),.DATA_WIDTH_B(18),
            .DOA_REG(OUTPUT_REG),.DOB_REG(OUTPUT_REG),.RST_TYPE("SYNC"),
            .RAM_MODE("TRUE_DUAL_PORT"),.WRITE_MODE_A("NORMAL_WRITE"),
            .WRITE_MODE_B("NORMAL_WRITE"),.RAM_DATA_WIDTH(18),.RAM_ADDR_WIDTH(10)
        ) ram(
            .DOA(qa),.DOB(qb),
            .DIA({1'b0,data_a[16*half+8+:8],1'b0,data_a[16*half+:8]}),
            .DIB({1'b0,data_b[16*half+8+:8],1'b0,data_b[16*half+:8]}),
            .ADDRA({addr_a,4'b0}),.ADDRB({addr_b,4'b0}),
            .ADDRA_HOLD(1'b0),.ADDRB_HOLD(1'b0),
            .BWEA({2'b0,mask_a[2*half+:2]}),.BWEB(mask_b[2*half+:2]),
            .CLKA(clk),.CLKB(clk),.CEA(advance_a),.CEB(advance_b),
            .WEA(we_a),.WEB(we_b),.ORCEA(advance_a),.ORCEB(advance_b),
            .RSTA(~rst_n),.RSTB(~rst_n)
        );
        assign q_a[16*half+:16]={qa[16:9],qa[7:0]};
        assign q_b[16*half+:16]={qb[16:9],qb[7:0]};
    end endgenerate
endmodule
