// 32 logical beats including prefetched/in-flight words. 8 E1 half-blocks.
// Explicitly coordinated destructive reset; native transactions must be quiesced.
module async_fifo256_probe(
    input wire wclk,input wire rclk,input wire wrst_n,input wire rrst_n,
    input wire wvalid,output wire wready,input wire [255:0] wdata,
    input wire [31:0] wstrb,input wire wlast,
    output wire rvalid,input wire rready,output wire [255:0] rdata,
    output wire [31:0] rstrb,output wire rlast,
    output wire [5:0] wfree,output wire [5:0] ravailable,
    output wire wactive,output wire ractive
);
    wire link_arst_n=wrst_n && rrst_n;
    reg [2:0] wrelease,rrelease /* synthesis syn_preserve=1 */;
    always @(posedge wclk or negedge link_arst_n)
        if(!link_arst_n)wrelease<=0;else wrelease<={wrelease[1:0],1'b1};
    always @(posedge rclk or negedge link_arst_n)
        if(!link_arst_n)rrelease<=0;else rrelease<={rrelease[1:0],1'b1};
    wire wlocal_n=wrelease[2],rlocal_n=rrelease[2];
    reg w_peer_meta,w_peer_sync,r_peer_meta,r_peer_sync /* synthesis syn_preserve=1 */;
    always @(posedge wclk or negedge wlocal_n)
        if(!wlocal_n)begin w_peer_meta<=0;w_peer_sync<=0;end
        else begin w_peer_meta<=rlocal_n;w_peer_sync<=w_peer_meta;end
    always @(posedge rclk or negedge rlocal_n)
        if(!rlocal_n)begin r_peer_meta<=0;r_peer_sync<=0;end
        else begin r_peer_meta<=wlocal_n;r_peer_sync<=r_peer_meta;end
    assign wactive=link_arst_n && wlocal_n && w_peer_sync;
    assign ractive=link_arst_n && rlocal_n && r_peer_sync;
    reg [5:0] wbin,rbin,fetch_bin;
    reg [5:0] wgray,rgray /* synthesis syn_preserve=1 */;
    reg [5:0] w_rgray_meta,w_rgray_sync,r_wgray_meta,r_wgray_sync /* synthesis syn_preserve=1 */;
    always @(posedge wclk or negedge wlocal_n)
        if(!wlocal_n)begin w_rgray_meta<=0;w_rgray_sync<=0;end
        else begin w_rgray_meta<=rgray;w_rgray_sync<=w_rgray_meta;end
    always @(posedge rclk or negedge rlocal_n)
        if(!rlocal_n)begin r_wgray_meta<=0;r_wgray_sync<=0;end
        else begin r_wgray_meta<=wgray;r_wgray_sync<=r_wgray_meta;end
    function [5:0] binary;
        input [5:0] gray;
        integer i;
        begin binary[5]=gray[5];for(i=4;i>=0;i=i-1)binary[i]=binary[i+1]^gray[i];end
    endfunction
    wire [5:0] used=wbin-binary(w_rgray_sync);
    assign wfree=wactive ? (6'd32-used) : 0;
    assign wready=wactive && used<32;
    wire push=wvalid && wready;
    wire [5:0] next_wbin=wbin+push;
    always @(posedge wclk or negedge wlocal_n)begin
        if(!wlocal_n)begin wbin<=0;wgray<=0;end
        else begin wbin<=next_wbin;wgray<=(next_wbin>>1)^next_wbin;end
    end
    assign ravailable=ractive ? binary(r_wgray_sync)-rbin : 0;
    reg [288:0] slot0,slot1;
    reg head,tail;
    reg [1:0] queued;
    reg pending;
    wire pop=rvalid && rready;
    wire [2:0] held={1'b0,queued}+pending;
    wire fetch=ractive && (fetch_bin!=binary(r_wgray_sync)) && ((held-pop)<2);
    wire [287:0] raw;
    wire [288:0] selected=head ? slot1 : slot0;
    assign {rlast,rstrb,rdata}=selected;
    assign rvalid=ractive && queued!=0;
    wire [5:0] next_rbin=rbin+pop;
    reg last_q;
    wire [31:0] last_bits;
    genvar bit_index;
    generate for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:last_store
        reg value /* synthesis syn_preserve=1 */;
        always @(posedge wclk)if(push && wbin[4:0]==bit_index)value<=wlast;
        assign last_bits[bit_index]=value;
    end endgenerate
    always @(posedge rclk or negedge rlocal_n)begin
        if(!rlocal_n)begin
            rbin<=0;rgray<=0;fetch_bin<=0;head<=0;tail<=0;queued<=0;pending<=0;last_q<=0;
        end else begin
            rbin<=next_rbin;rgray<=(next_rbin>>1)^next_rbin;
            pending<=fetch;
            if(fetch)begin fetch_bin<=fetch_bin+1'b1;last_q<=last_bits[fetch_bin[4:0]];end
            if(pop)head<=~head;
            if(pending)begin
                if(tail)slot1<={last_q,raw};else slot0<={last_q,raw};
                tail<=~tail;
            end
            queued<=queued+pending-pop;
        end
    end
    wire [287:0] packed_input={wstrb,wdata};
    genvar bank;
    generate for(bank=0;bank<8;bank=bank+1)begin:ram_bank
        wire [17:0] qa,qb;
        GTP_DRM18K_E1 #(
            .GRS_EN("FALSE"),.DATA_WIDTH_A(36),.DATA_WIDTH_B(36),
            .DOA_REG(0),.DOB_REG(0),.RST_TYPE("SYNC"),.RAM_MODE("SIMPLE_DUAL_PORT"),
            .RAM_DATA_WIDTH(36),.RAM_ADDR_WIDTH(9)
        ) ram(
            .DOA(qa),.DOB(qb),.DIA(packed_input[36*bank+:18]),.DIB(packed_input[36*bank+18+:18]),
            .ADDRA({4'b0,wbin[4:0],5'b0}),.ADDRB({4'b0,fetch_bin[4:0],5'b0}),
            .ADDRA_HOLD(1'b0),.ADDRB_HOLD(1'b0),.BWEA(4'b1111),.BWEB(2'b0),
            .CLKA(wclk),.CLKB(rclk),.CEA(push),.CEB(fetch),.WEA(1'b1),.WEB(1'b0),
            .ORCEA(1'b1),.ORCEB(1'b1),.RSTA(~wlocal_n),.RSTB(~rlocal_n)
        );
        assign raw[36*bank+:36]={qb,qa};
    end endgenerate
endmodule
