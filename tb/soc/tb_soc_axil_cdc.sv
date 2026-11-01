`timescale 1ns/1ps
`default_nettype none

// Real 100/125 MHz CDC and video decoder, with independent byte-register slaves.
// Reset only starts a new epoch after every request and response has drained.
module tb_soc_axil_cdc;
    parameter integer PHASE_NS = 0;
    localparam integer NW = 27, NR = 19;
    reg s_clk = 0, m_clk = 0, rst_n = 0;
    always #5 s_clk = !s_clk;
    initial begin #(PHASE_NS); forever #4 m_clk = !m_clk; end

    reg [31:0] s_awaddr = 0, s_wdata = 0, s_araddr = 0;
    reg [2:0] s_awprot = 0, s_arprot = 0;
    reg [3:0] s_wstrb = 0;
    reg s_awvalid = 0, s_wvalid = 0, s_bready = 0, s_arvalid = 0, s_rready = 0;
    wire s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [1:0] s_bresp, s_rresp;
    wire [31:0] s_rdata;
    wire [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    wire [2:0] m_awprot, m_arprot;
    wire [3:0] m_wstrb;
    wire m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    wire m_arvalid, m_arready, m_rvalid, m_rready;
    wire [1:0] m_bresp, m_rresp;
    wire [63:0] d_awaddr, d_wdata, d_araddr, d_rdata;
    wire [5:0] d_awprot, d_arprot;
    wire [7:0] d_wstrb;
    wire [1:0] d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
    wire [1:0] d_arvalid, d_arready, d_rvalid, d_rready;
    wire [3:0] d_bresp, d_rresp;
    wire [31:0] slave_writes [0:1], slave_reads [0:1];

    soc_axil_cdc u_cdc (
        .s_clk_i(s_clk), .m_clk_i(m_clk), .rst_ni(rst_n),
        .s_axi_awaddr_i(s_awaddr), .s_axi_awprot_i(s_awprot), .s_axi_awvalid_i(s_awvalid), .s_axi_awready_o(s_awready),
        .s_axi_wdata_i(s_wdata), .s_axi_wstrb_i(s_wstrb), .s_axi_wvalid_i(s_wvalid), .s_axi_wready_o(s_wready),
        .s_axi_bresp_o(s_bresp), .s_axi_bvalid_o(s_bvalid), .s_axi_bready_i(s_bready),
        .s_axi_araddr_i(s_araddr), .s_axi_arprot_i(s_arprot), .s_axi_arvalid_i(s_arvalid), .s_axi_arready_o(s_arready),
        .s_axi_rdata_o(s_rdata), .s_axi_rresp_o(s_rresp), .s_axi_rvalid_o(s_rvalid), .s_axi_rready_i(s_rready),
        .m_axi_awaddr_o(m_awaddr), .m_axi_awprot_o(m_awprot), .m_axi_awvalid_o(m_awvalid), .m_axi_awready_i(m_awready),
        .m_axi_wdata_o(m_wdata), .m_axi_wstrb_o(m_wstrb), .m_axi_wvalid_o(m_wvalid), .m_axi_wready_i(m_wready),
        .m_axi_bresp_i(m_bresp), .m_axi_bvalid_i(m_bvalid), .m_axi_bready_o(m_bready),
        .m_axi_araddr_o(m_araddr), .m_axi_arprot_o(m_arprot), .m_axi_arvalid_o(m_arvalid), .m_axi_arready_i(m_arready),
        .m_axi_rdata_i(m_rdata), .m_axi_rresp_i(m_rresp), .m_axi_rvalid_i(m_rvalid), .m_axi_rready_o(m_rready)
    );
    video_axil_decode u_decode (
        .clk_i(m_clk), .rst_ni(rst_n),
        .s_axi_awaddr_i(m_awaddr), .s_axi_awprot_i(m_awprot), .s_axi_awvalid_i(m_awvalid), .s_axi_awready_o(m_awready),
        .s_axi_wdata_i(m_wdata), .s_axi_wstrb_i(m_wstrb), .s_axi_wvalid_i(m_wvalid), .s_axi_wready_o(m_wready),
        .s_axi_bresp_o(m_bresp), .s_axi_bvalid_o(m_bvalid), .s_axi_bready_i(m_bready),
        .s_axi_araddr_i(m_araddr), .s_axi_arprot_i(m_arprot), .s_axi_arvalid_i(m_arvalid), .s_axi_arready_o(m_arready),
        .s_axi_rdata_o(m_rdata), .s_axi_rresp_o(m_rresp), .s_axi_rvalid_o(m_rvalid), .s_axi_rready_i(m_rready),
        .m_axi_awaddr_o(d_awaddr), .m_axi_awprot_o(d_awprot), .m_axi_awvalid_o(d_awvalid), .m_axi_awready_i(d_awready),
        .m_axi_wdata_o(d_wdata), .m_axi_wstrb_o(d_wstrb), .m_axi_wvalid_o(d_wvalid), .m_axi_wready_i(d_wready),
        .m_axi_bresp_i(d_bresp), .m_axi_bvalid_i(d_bvalid), .m_axi_bready_o(d_bready),
        .m_axi_araddr_o(d_araddr), .m_axi_arprot_o(d_arprot), .m_axi_arvalid_o(d_arvalid), .m_axi_arready_i(d_arready),
        .m_axi_rdata_i(d_rdata), .m_axi_rresp_i(d_rresp), .m_axi_rvalid_i(d_rvalid), .m_axi_rready_o(d_rready)
    );
    genvar g;
    generate for (g=0; g<2; g=g+1) begin: slaves
        axil_cdc_register_slave #(.LANE(g)) u_registers (
            .clk(m_clk), .rst_n(rst_n),
            .awaddr(d_awaddr[g*32+:32]), .awvalid(d_awvalid[g]), .awready(d_awready[g]),
            .wdata(d_wdata[g*32+:32]), .wstrb(d_wstrb[g*4+:4]), .wvalid(d_wvalid[g]), .wready(d_wready[g]),
            .bresp(d_bresp[g*2+:2]), .bvalid(d_bvalid[g]), .bready(d_bready[g]),
            .araddr(d_araddr[g*32+:32]), .arvalid(d_arvalid[g]), .arready(d_arready[g]),
            .rdata(d_rdata[g*32+:32]), .rresp(d_rresp[g*2+:2]), .rvalid(d_rvalid[g]), .rready(d_rready[g]),
            .write_count(slave_writes[g]), .read_count(slave_reads[g])
        );
    end endgenerate

    axil_cdc_hold_check #(35) c_saw(s_clk,rst_n,s_awvalid,s_awready,{s_awaddr,s_awprot});
    axil_cdc_hold_check #(36) c_sw(s_clk,rst_n,s_wvalid,s_wready,{s_wdata,s_wstrb});
    axil_cdc_hold_check #(2) c_sb(s_clk,rst_n,s_bvalid,s_bready,s_bresp);
    axil_cdc_hold_check #(35) c_sar(s_clk,rst_n,s_arvalid,s_arready,{s_araddr,s_arprot});
    axil_cdc_hold_check #(34) c_sr(s_clk,rst_n,s_rvalid,s_rready,{s_rdata,s_rresp});
    axil_cdc_hold_check #(35) c_maw(m_clk,rst_n,m_awvalid,m_awready,{m_awaddr,m_awprot});
    axil_cdc_hold_check #(36) c_mw(m_clk,rst_n,m_wvalid,m_wready,{m_wdata,m_wstrb});
    axil_cdc_hold_check #(2) c_mb(m_clk,rst_n,m_bvalid,m_bready,m_bresp);
    axil_cdc_hold_check #(35) c_mar(m_clk,rst_n,m_arvalid,m_arready,{m_araddr,m_arprot});
    axil_cdc_hold_check #(34) c_mr(m_clk,rst_n,m_rvalid,m_rready,{m_rdata,m_rresp});

    reg [31:0] write_addr[0:NW-1], write_data[0:NW-1], read_addr[0:NR-1], read_data[0:NR-1];
    reg [3:0] write_mask[0:NW-1];
    reg [2:0] write_prot[0:NW-1], read_prot[0:NR-1];
    reg [1:0] write_resp[0:NW-1], read_resp[0:NR-1];
    reg [7:0] expected_bytes[0:1][0:31];
    integer saw_count=0, sw_count=0, sb_count=0, sar_count=0, sr_count=0;
    integer maw_count=0, mw_count=0, mb_count=0, mar_count=0, mr_count=0;
    integer aw_stalls=0, w_stalls=0, ar_stalls=0, b_stalls=0, r_stalls=0;
    integer s_first_aw=-1, s_first_w=-1, s_cycle=0;
    integer m_first_aw=-1, m_first_w=-1, m_cycle=0;
    integer total_b_stalls=0, total_r_stalls=0;

    always @(posedge s_clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_count<=0; sw_count<=0; sb_count<=0; sar_count<=0; sr_count<=0;
            s_first_aw<=-1; s_first_w<=-1; s_cycle<=0;
            aw_stalls<=0; w_stalls<=0; ar_stalls<=0;
        end else begin
            s_cycle<=s_cycle+1;
            if (s_awvalid && !s_awready) aw_stalls<=aw_stalls+1;
            if (s_wvalid && !s_wready) w_stalls<=w_stalls+1;
            if (s_arvalid && !s_arready) ar_stalls<=ar_stalls+1;
            if (s_awvalid && s_awready) begin
                saw_count<=saw_count+1;
                if (saw_count==0) s_first_aw<=s_cycle;
            end
            if (s_wvalid && s_wready) begin
                sw_count<=sw_count+1;
                if (sw_count==0) s_first_w<=s_cycle;
            end
            if (s_bvalid && s_bready) begin
                if (sb_count>=NW || s_bresp!==write_resp[sb_count])
                    $fatal(1,"B scoreboard index=%0d got=%b",sb_count,s_bresp);
                sb_count<=sb_count+1;
            end
            if (s_arvalid && s_arready) sar_count<=sar_count+1;
            if (s_rvalid && s_rready) begin
                if (sr_count>=NR || s_rresp!==read_resp[sr_count] || s_rdata!==read_data[sr_count])
                    $fatal(1,"R scoreboard index=%0d data=%h expected=%h resp=%b",sr_count,s_rdata,read_data[sr_count],s_rresp);
                sr_count<=sr_count+1;
            end
        end
    end
    always @(posedge m_clk or negedge rst_n) begin
        if (!rst_n) begin
            maw_count<=0; mw_count<=0; mb_count<=0; mar_count<=0; mr_count<=0;
            b_stalls<=0; r_stalls<=0;
            m_first_aw<=-1; m_first_w<=-1; m_cycle<=0;
        end else begin
            m_cycle<=m_cycle+1;
            if (m_awvalid && m_awready) begin
                if (maw_count>=NW || {m_awaddr,m_awprot}!=={write_addr[maw_count],write_prot[maw_count]})
                    $fatal(1,"AW CDC order/address/protection index=%0d",maw_count);
                maw_count<=maw_count+1;
                if(maw_count==0) m_first_aw<=m_cycle;
            end
            if (m_wvalid && m_wready) begin
                if (mw_count>=NW || {m_wdata,m_wstrb}!=={write_data[mw_count],write_mask[mw_count]})
                    $fatal(1,"W CDC order/data/strobe index=%0d",mw_count);
                mw_count<=mw_count+1;
                if(mw_count==0) m_first_w<=m_cycle;
            end
            if (m_bvalid && m_bready) mb_count<=mb_count+1;
            if (m_arvalid && m_arready) begin
                if (mar_count>=NR || {m_araddr,m_arprot}!=={read_addr[mar_count],read_prot[mar_count]})
                    $fatal(1,"AR CDC order/address/protection index=%0d",mar_count);
                mar_count<=mar_count+1;
            end
            if (m_rvalid && m_rready) mr_count<=mr_count+1;
            if (m_bvalid && !m_bready) b_stalls<=b_stalls+1;
            if (m_rvalid && !m_rready) r_stalls<=r_stalls+1;
        end
    end

    task prepare_epoch(input integer epoch);
        integer i,l,j,k;
        reg [31:0] initial_word;
        begin
            for (l=0;l<2;l=l+1) for (j=0;j<8;j=j+1) begin
                initial_word=32'ha0000000 ^ (l<<16) ^ (j*32'h01010101);
                for(k=0;k<4;k=k+1) expected_bytes[l][j*4+k]=initial_word[k*8+:8];
            end
            for (i=0;i<NW;i=i+1) begin
                l=i%2; j=(i/2)%4;
                write_addr[i]=(l==0 ? 32'h20012000 : 32'h20011000)+j*4;
                write_data[i]=32'h11223344 ^ (epoch*32'hb937c7e1) ^ (i*32'h08040201);
                write_prot[i]=(i+epoch)%8; write_resp[i]=0;
                case(i%8)
                    0:write_mask[i]=15; 1:write_mask[i]=1; 2:write_mask[i]=2; 3:write_mask[i]=4;
                    4:write_mask[i]=8; 5:write_mask[i]=0; 6:write_mask[i]=5; 7:write_mask[i]=10;
                endcase
                if(i<24) for(k=0;k<4;k=k+1)
                    if(write_mask[i][k]) expected_bytes[l][j*4+k]=write_data[i][k*8+:8];
            end
            write_addr[24]=32'h20014000; write_resp[24]=3;
            write_addr[25]=32'h20012002; write_resp[25]=3;
            write_addr[26]=32'h200123fc; write_resp[26]=2;
            for(i=0;i<NR;i=i+1) begin
                l=i%2; j=i/2;
                read_addr[i]=(l==0 ? 32'h20012000 : 32'h20011000)+j*4;
                read_prot[i]=(i+3+epoch)%8; read_resp[i]=0; read_data[i]=0;
                if(i<16) for(k=0;k<4;k=k+1) read_data[i][k*8+:8]=expected_bytes[l][j*4+k];
            end
            read_addr[16]=32'h20014000; read_resp[16]=3;
            read_addr[17]=32'h20011001; read_resp[17]=3;
            read_addr[18]=32'h200113fc; read_resp[18]=2; read_data[18]=32'hebad0001;
        end
    endtask
    task send_aw(input integer epoch);
        integer i;
        begin
            if(epoch==0) repeat(25) @(negedge s_clk);
            for(i=0;i<NW;i=i+1) begin
                @(negedge s_clk); s_awvalid=1; s_awaddr=write_addr[i]; s_awprot=write_prot[i];
                @(posedge s_clk); while(!s_awready) @(posedge s_clk);
                @(negedge s_clk); s_awvalid=0;
                repeat(i%3) @(negedge s_clk);
            end
        end
    endtask
    task send_w(input integer epoch);
        integer i;
        begin
            if(epoch==1) repeat(25) @(negedge s_clk);
            for(i=0;i<NW;i=i+1) begin
                @(negedge s_clk); s_wvalid=1; s_wdata=write_data[i]; s_wstrb=write_mask[i];
                @(posedge s_clk); while(!s_wready) @(posedge s_clk);
                @(negedge s_clk); s_wvalid=0;
                repeat((i+1)%3) @(negedge s_clk);
            end
        end
    endtask
    task receive_b;
        integer tick;
        begin
            s_bready=0;
            repeat(220) @(negedge s_clk);
            if(b_stalls==0) $fatal(1,"B FIFO was not filled to destination backpressure");
            tick=0;
            while(sb_count<NW) begin
                @(negedge s_clk); s_bready=(tick%5!=1 && tick%7!=2); tick=tick+1;
            end
            @(negedge s_clk); s_bready=0;
        end
    endtask
    task send_ar;
        integer i;
        begin
            for(i=0;i<NR;i=i+1) begin
                @(negedge s_clk); s_arvalid=1; s_araddr=read_addr[i]; s_arprot=read_prot[i];
                @(posedge s_clk); while(!s_arready) @(posedge s_clk);
                @(negedge s_clk); s_arvalid=0;
            end
        end
    endtask
    task receive_r;
        integer tick;
        begin
            s_rready=0;
            repeat(140) @(negedge s_clk);
            if(r_stalls==0) $fatal(1,"R FIFO was not filled to destination backpressure");
            tick=0;
            while(sr_count<NR) begin
                @(negedge s_clk); s_rready=(tick%4!=1 && tick%9!=3); tick=tick+1;
            end
            @(negedge s_clk); s_rready=0;
        end
    endtask
    integer epoch;
    initial begin
        for(epoch=0;epoch<2;epoch=epoch+1) begin
            rst_n=0; prepare_epoch(epoch);
            repeat(8) @(negedge s_clk);
            rst_n=1;
            repeat(8) @(negedge s_clk);
            fork send_aw(epoch); send_w(epoch); receive_b(); join
            fork send_ar(); receive_r(); join
            repeat(12) @(negedge s_clk);
            if(saw_count!=NW || sw_count!=NW || sb_count!=NW || maw_count!=NW || mw_count!=NW || mb_count!=NW ||
               sar_count!=NR || sr_count!=NR || mar_count!=NR || mr_count!=NR)
                $fatal(1,"Missing or duplicate transaction in epoch %0d",epoch);
            if(slave_writes[0]!=13 || slave_writes[1]!=12 || slave_reads[0]!=8 || slave_reads[1]!=9)
                $fatal(1,"Decoder routed a missing, duplicate, or invalid transaction");
            if((epoch==0 && s_first_w>=s_first_aw) || (epoch==1 && s_first_aw>=s_first_w))
                $fatal(1,"Required AW/W ordering was not exercised");
            if((epoch==0 && m_first_w>=m_first_aw) || (epoch==1 && m_first_aw>=m_first_w))
                $fatal(1,"Required AW/W ordering did not reach video domain");
            if(aw_stalls==0 || w_stalls==0 || ar_stalls==0 || b_stalls==0 || r_stalls==0)
                $fatal(1,"Not all five channel FIFOs experienced backpressure");
            if({s_bvalid,s_rvalid,m_awvalid,m_wvalid,m_arvalid,m_bvalid,m_rvalid,d_bvalid,d_rvalid}!==11'b0)
                $fatal(1,"Coordinated reset requires drained endpoints");
            total_b_stalls=total_b_stalls+b_stalls; total_r_stalls=total_r_stalls+r_stalls;
        end
        $display("PASS SOC_AXIL_CDC phase=%0d epochs=2 writes=54 reads=38 b_stalls=%0d r_stalls=%0d",PHASE_NS,total_b_stalls,total_r_stalls);
        $finish;
    end
    initial begin #1000000; $fatal(1,"AXI-Lite CDC timeout"); end
endmodule

module axil_cdc_hold_check #(parameter integer WIDTH=1)(
    input wire clk,rst_n,valid,ready,
    input wire [WIDTH-1:0] payload
);
    reg stalled=0;
    reg [WIDTH-1:0] held;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) stalled<=0;
        else begin
            if(stalled && (valid!==1'b1 || payload!==held))
                $fatal(1,"VALID/payload changed under backpressure: %m");
            stalled<=valid && !ready;
            held<=payload;
        end
    end
endmodule

// Slave implementation deliberately differs from the driver's byte oracle.
module axil_cdc_register_slave #(parameter integer LANE=0)(
    input wire clk,rst_n,
    input wire [31:0] awaddr,wdata,araddr,
    input wire [3:0] wstrb,
    input wire awvalid,wvalid,bready,arvalid,rready,
    output wire awready,wready,arready,
    output reg [1:0] bresp,rresp,
    output reg bvalid,rvalid,
    output reg [31:0] rdata,write_count,read_count
);
    reg [31:0] words[0:7];
    reg aw_full=0,w_full=0;
    reg [31:0] saved_addr=0,saved_data=0;
    reg [3:0] saved_mask=0;
    integer cycle=0, i, k;
    assign awready=rst_n && !aw_full && !bvalid && (cycle%5!=2);
    assign wready=rst_n && !w_full && !bvalid && (cycle%7!=1 && cycle%7!=2);
    assign arready=rst_n && !rvalid && (cycle%4!=1);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cycle<=0; aw_full<=0; w_full<=0; bvalid<=0; rvalid<=0;
            bresp<=0; rresp<=0; rdata<=0; write_count<=0; read_count<=0;
            for(i=0;i<8;i=i+1) words[i]<=32'ha0000000 ^ (LANE<<16) ^ (i*32'h01010101);
        end else begin
            cycle<=cycle+1;
            if(awvalid && awready) begin aw_full<=1; saved_addr<=awaddr; end
            if(wvalid && wready) begin w_full<=1; saved_data<=wdata; saved_mask<=wstrb; end
            if(aw_full && w_full && !bvalid) begin
                if(saved_addr[11:0]==12'h3fc) bresp<=2;
                else begin
                    bresp<=0;
                    for(k=0;k<4;k=k+1) if(saved_mask[k]) words[saved_addr[4:2]][k*8+:8]<=saved_data[k*8+:8];
                end
                aw_full<=0; w_full<=0; bvalid<=1; write_count<=write_count+1;
            end
            if(bvalid && bready) bvalid<=0;
            if(arvalid && arready) begin
                rvalid<=1; read_count<=read_count+1;
                if(araddr[11:0]==12'h3fc) begin rresp<=2; rdata<=32'hebad0000+LANE; end
                else begin rresp<=0; rdata<=words[araddr[4:2]]; end
            end
            if(rvalid && rready) rvalid<=0;
        end
    end
endmodule
`default_nettype wire
