// Complete fixed-width TDP array. rst_n clears responses, never RAM contents.
module b03_bank_array #(
    parameter BANKS=16, WIDTH=32, DEPTH=1024
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
    wire [BANKS-1:0] collisions,range_faults;
    genvar b;
    generate for(b=0;b<BANKS;b=b+1)begin:bank
        wire [10:0] aa=addr_a[11*b+:11],ab=addr_b[11*b+:11];
        wire bad=rst_n&&run_ce&&((req_a[b]&&aa>=DEPTH)||(req_b[b]&&ab>=DEPTH));
        assign range_faults[b]=bad;
        if(WIDTH==32 && DEPTH==2048)begin:deep
            b03_tdp2048_loan_bank ram(.clk(clk),.rst_n(rst_n),.run_ce(run_ce),
                .req_a(req_a[b]),.we_a(we_a[b]),.addr_a(aa),.data_a(data_a[32*b+:32]),.mask_a(mask_a[4*b+:4]),
                .req_b(req_b[b]),.we_b(we_b[b]),.addr_b(ab),.data_b(data_b[32*b+:32]),.mask_b(mask_b[4*b+:4]),
                .q_a(q_a[32*b+:32]),.q_b(q_b[32*b+:32]),.valid_a(valid_a[b]),.valid_b(valid_b[b]),
                .conflict(collisions[b]),.busy());
        end else begin:shallow
            wire col=rst_n&&run_ce&&req_a[b]&&req_b[b]&&aa==ab&&(we_a[b]||we_b[b]);
            wire ca=rst_n&&run_ce&&req_a[b]&&!bad&&!col;
            wire cb=rst_n&&run_ce&&req_b[b]&&!bad&&!col;
            reg va,vb;
            assign valid_a[b]=va;assign valid_b[b]=vb;
            assign collisions[b]=col;
            always @(posedge clk)begin
                if(!rst_n)begin va<=0;vb<=0;end
                else if(run_ce)begin va<=ca&&!we_a[b];vb<=cb&&!we_b[b];end
            end
            if(WIDTH==32)begin:word32
                tdp32_probe #(.OUTPUT_REG(0)) ram(.clk(clk),.rst_n(rst_n),
                    .ce_a(ca),.we_a(we_a[b]),.addr_a(aa[9:0]),.data_a(data_a[32*b+:32]),.mask_a(mask_a[4*b+:4]),
                    .ce_b(cb),.we_b(we_b[b]),.addr_b(ab[9:0]),.data_b(data_b[32*b+:32]),.mask_b(mask_b[4*b+:4]),
                    .q_a(q_a[32*b+:32]),.q_b(q_b[32*b+:32]),.valid_a(),.valid_b(),.conflict());
            end else begin:word16
                wire [17:0] qa,qb;
                GTP_DRM18K_E1 #(.GRS_EN("FALSE"),.DATA_WIDTH_A(18),.DATA_WIDTH_B(18),
                    .DOA_REG(0),.DOB_REG(0),.RST_TYPE("SYNC"),.RAM_MODE("TRUE_DUAL_PORT"),
                    .WRITE_MODE_A("NORMAL_WRITE"),.WRITE_MODE_B("NORMAL_WRITE"),.RAM_DATA_WIDTH(18),.RAM_ADDR_WIDTH(10)) ram(
                    .DOA(qa),.DOB(qb),.DIA({1'b0,data_a[16*b+8+:8],1'b0,data_a[16*b+:8]}),
                    .DIB({1'b0,data_b[16*b+8+:8],1'b0,data_b[16*b+:8]}),
                    .ADDRA({aa[9:0],4'b0}),.ADDRB({ab[9:0],4'b0}),.ADDRA_HOLD(1'b0),.ADDRB_HOLD(1'b0),
                    .BWEA({2'b0,mask_a[2*b+:2]}),.BWEB(mask_b[2*b+:2]),
                    .CLKA(clk),.CLKB(clk),.CEA(ca),.CEB(cb),.WEA(we_a[b]),.WEB(we_b[b]),
                    .ORCEA(ca),.ORCEB(cb),.RSTA(~rst_n),.RSTB(~rst_n));
                assign q_a[16*b+:16]={qa[16:9],qa[7:0]};
                assign q_b[16*b+:16]={qb[16:9],qb[7:0]};
            end
        end
    end endgenerate
    assign busy=|valid_a|| |valid_b;
    assign conflict=|collisions;assign range_error=|range_faults;
endmodule
