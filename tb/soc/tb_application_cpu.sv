`timescale 1ns/1ps
`default_nettype none
// Only the CPU/router/memories/cache/adapters are production RTL. The two
// AXI-Lite endpoints and AXI memory below are control-path test models.
module tb_application_cpu #(parameter integer CPU_MODE=0, BROKEN=0);
    reg clk=0, rst_n=0, ddr_ready=0, ddr_fault=0, ddr_hold=0;
    always #5 clk=~clk;
    wire fault, protocol_fault;
    wire [1:0] irqs;
    wire [31:0] finish[0:1];
    wire [31:0] mmio_reads[0:1], mmio_writes[0:1];
    wire [31:0] ddr_reads, ddr_writes;
    reg i_req=0, i_flush=0, i_invalidate=0;
    reg [31:0] i_addr=0;
    wire i_accept,i_valid,i_error;
    wire [63:0] i_data;
    reg [31:0] d_addr=0,d_wdata=0;
    reg d_re=0,d_cacheable=0,d_invalidate=0,d_writeback=0,d_flush=0;
    reg [3:0] d_wstrb=0;
    reg [10:0] d_tag=0;
    wire d_accept,d_ack,d_error;
    wire [31:0] d_data;
    wire [10:0] d_resp_tag;
    integer cycles=0,checks=0,waits=0,irq_seen=0,irq_cleared=0;
    wire [31:0] npu_axi_awaddr_o;
    wire [2:0] npu_axi_awprot_o;
    wire npu_axi_awvalid_o;
    wire npu_axi_awready_i;
    wire [31:0] npu_axi_wdata_o;
    wire [3:0] npu_axi_wstrb_o;
    wire npu_axi_wvalid_o;
    wire npu_axi_wready_i;
    wire [1:0] npu_axi_bresp_i;
    wire npu_axi_bvalid_i;
    wire npu_axi_bready_o;
    wire [31:0] npu_axi_araddr_o;
    wire [2:0] npu_axi_arprot_o;
    wire npu_axi_arvalid_o;
    wire npu_axi_arready_i;
    wire [31:0] npu_axi_rdata_i;
    wire [1:0] npu_axi_rresp_i;
    wire npu_axi_rvalid_i;
    wire npu_axi_rready_o;
    wire [31:0] video_axi_awaddr_o;
    wire [2:0] video_axi_awprot_o;
    wire video_axi_awvalid_o;
    wire video_axi_awready_i;
    wire [31:0] video_axi_wdata_o;
    wire [3:0] video_axi_wstrb_o;
    wire video_axi_wvalid_o;
    wire video_axi_wready_i;
    wire [1:0] video_axi_bresp_i;
    wire video_axi_bvalid_i;
    wire video_axi_bready_o;
    wire [31:0] video_axi_araddr_o;
    wire [2:0] video_axi_arprot_o;
    wire video_axi_arvalid_o;
    wire video_axi_arready_i;
    wire [31:0] video_axi_rdata_i;
    wire [1:0] video_axi_rresp_i;
    wire video_axi_rvalid_i;
    wire video_axi_rready_o;
    wire axi_awvalid_o;
    wire [31:0] axi_awaddr_o;
    wire [3:0] axi_awid_o;
    wire [7:0] axi_awlen_o;
    wire [2:0] axi_awsize_o;
    wire [1:0] axi_awburst_o;
    wire axi_awready_i;
    wire axi_wvalid_o;
    wire [127:0] axi_wdata_o;
    wire [15:0] axi_wstrb_o;
    wire axi_wlast_o;
    wire axi_wready_i;
    wire axi_bvalid_i;
    wire [1:0] axi_bresp_i;
    wire [3:0] axi_bid_i;
    wire axi_bready_o;
    wire axi_arvalid_o;
    wire [31:0] axi_araddr_o;
    wire [3:0] axi_arid_o;
    wire [7:0] axi_arlen_o;
    wire [2:0] axi_arsize_o;
    wire [1:0] axi_arburst_o;
    wire axi_arready_i;
    wire axi_rvalid_i;
    wire [127:0] axi_rdata_i;
    wire [1:0] axi_rresp_i;
    wire [3:0] axi_rid_i;
    wire axi_rlast_i;
    wire axi_rready_o;
    generate if(CPU_MODE) begin:g_cpu
        integer trace_count=0;
        always @(posedge clk) if(rst_n && u_dut.u_core.u_cpu.u_csr.csr_writeback_exception_i!=0 && trace_count<12)begin
            trace_count<=trace_count+1;
            $display("APPLICATION_TRAP exception=%h pc=%h mepc=%h cause=%h",u_dut.u_core.u_cpu.u_csr.csr_writeback_exception_i,
                u_dut.u_core.u_cpu.u_csr.csr_writeback_exception_pc_i,
                u_dut.u_core.u_cpu.u_csr.u_csrfile.csr_mepc_q,u_dut.u_core.u_cpu.u_csr.u_csrfile.csr_mcause_q);
        end
        always @(posedge clk) if(cycles==99999) begin
            $display("APPLICATION_STATE pc=%h ireq=%b iaccept=%b ivalid=%b daddr=%h dre=%b dwr=%h daccept=%b dack=%b irq=%b npu_writes=%0d video_writes=%0d ddr_reads=%0d ddr_writes=%0d",
                u_dut.inst_addr,u_dut.inst_req,u_dut.inst_accept,u_dut.inst_valid,
                u_dut.data_addr,u_dut.data_re,u_dut.data_wstrb,u_dut.data_accept,u_dut.data_ack,
                irqs,mmio_writes[0],mmio_writes[1],ddr_reads,ddr_writes);
        end
        triha_application_cpu u_dut (.clk_i(clk),.rst_ni(rst_n),.external_irq_i(|irqs),
            .ddr_ready_i(ddr_ready),.ddr_fault_i(ddr_fault),.ddr_fault_o(fault),.protocol_fault_o(protocol_fault),
            .npu_axi_awaddr_o(npu_axi_awaddr_o),
            .npu_axi_awprot_o(npu_axi_awprot_o),
            .npu_axi_awvalid_o(npu_axi_awvalid_o),
            .npu_axi_awready_i(npu_axi_awready_i),
            .npu_axi_wdata_o(npu_axi_wdata_o),
            .npu_axi_wstrb_o(npu_axi_wstrb_o),
            .npu_axi_wvalid_o(npu_axi_wvalid_o),
            .npu_axi_wready_i(npu_axi_wready_i),
            .npu_axi_bresp_i(npu_axi_bresp_i),
            .npu_axi_bvalid_i(npu_axi_bvalid_i),
            .npu_axi_bready_o(npu_axi_bready_o),
            .npu_axi_araddr_o(npu_axi_araddr_o),
            .npu_axi_arprot_o(npu_axi_arprot_o),
            .npu_axi_arvalid_o(npu_axi_arvalid_o),
            .npu_axi_arready_i(npu_axi_arready_i),
            .npu_axi_rdata_i(npu_axi_rdata_i),
            .npu_axi_rresp_i(npu_axi_rresp_i),
            .npu_axi_rvalid_i(npu_axi_rvalid_i),
            .npu_axi_rready_o(npu_axi_rready_o),
            .video_axi_awaddr_o(video_axi_awaddr_o),
            .video_axi_awprot_o(video_axi_awprot_o),
            .video_axi_awvalid_o(video_axi_awvalid_o),
            .video_axi_awready_i(video_axi_awready_i),
            .video_axi_wdata_o(video_axi_wdata_o),
            .video_axi_wstrb_o(video_axi_wstrb_o),
            .video_axi_wvalid_o(video_axi_wvalid_o),
            .video_axi_wready_i(video_axi_wready_i),
            .video_axi_bresp_i(video_axi_bresp_i),
            .video_axi_bvalid_i(video_axi_bvalid_i),
            .video_axi_bready_o(video_axi_bready_o),
            .video_axi_araddr_o(video_axi_araddr_o),
            .video_axi_arprot_o(video_axi_arprot_o),
            .video_axi_arvalid_o(video_axi_arvalid_o),
            .video_axi_arready_i(video_axi_arready_i),
            .video_axi_rdata_i(video_axi_rdata_i),
            .video_axi_rresp_i(video_axi_rresp_i),
            .video_axi_rvalid_i(video_axi_rvalid_i),
            .video_axi_rready_o(video_axi_rready_o),
            .axi_awvalid_o(axi_awvalid_o),
            .axi_awaddr_o(axi_awaddr_o),
            .axi_awid_o(axi_awid_o),
            .axi_awlen_o(axi_awlen_o),
            .axi_awsize_o(axi_awsize_o),
            .axi_awburst_o(axi_awburst_o),
            .axi_awready_i(axi_awready_i),
            .axi_wvalid_o(axi_wvalid_o),
            .axi_wdata_o(axi_wdata_o),
            .axi_wstrb_o(axi_wstrb_o),
            .axi_wlast_o(axi_wlast_o),
            .axi_wready_i(axi_wready_i),
            .axi_bvalid_i(axi_bvalid_i),
            .axi_bresp_i(axi_bresp_i),
            .axi_bid_i(axi_bid_i),
            .axi_bready_o(axi_bready_o),
            .axi_arvalid_o(axi_arvalid_o),
            .axi_araddr_o(axi_araddr_o),
            .axi_arid_o(axi_arid_o),
            .axi_arlen_o(axi_arlen_o),
            .axi_arsize_o(axi_arsize_o),
            .axi_arburst_o(axi_arburst_o),
            .axi_arready_i(axi_arready_i),
            .axi_rvalid_i(axi_rvalid_i),
            .axi_rdata_i(axi_rdata_i),
            .axi_rresp_i(axi_rresp_i),
            .axi_rid_i(axi_rid_i),
            .axi_rlast_i(axi_rlast_i),
            .axi_rready_o(axi_rready_o)
        );
    end else begin:g_router
        triha_application_router u_dut (.clk_i(clk),.rst_ni(rst_n),
            .ddr_ready_i(ddr_ready),.ddr_fault_i(ddr_fault),.ddr_fault_o(fault),.protocol_fault_o(protocol_fault),
            .inst_req_i(i_req),.inst_flush_i(i_flush),.inst_invalidate_i(i_invalidate),.inst_addr_i(i_addr),
            .inst_accept_o(i_accept),.inst_valid_o(i_valid),.inst_error_o(i_error),.inst_rdata_o(i_data),
            .data_addr_i(d_addr),.data_wdata_i(d_wdata),.data_re_i(d_re),.data_wstrb_i(d_wstrb),
            .data_cacheable_i(d_cacheable),.data_req_tag_i(d_tag),.data_invalidate_i(d_invalidate),
            .data_writeback_i(d_writeback),.data_flush_i(d_flush),.data_rdata_o(d_data),
            .data_accept_o(d_accept),.data_ack_o(d_ack),.data_error_o(d_error),.data_resp_tag_o(d_resp_tag),
            .npu_axi_awaddr_o(npu_axi_awaddr_o),
            .npu_axi_awprot_o(npu_axi_awprot_o),
            .npu_axi_awvalid_o(npu_axi_awvalid_o),
            .npu_axi_awready_i(npu_axi_awready_i),
            .npu_axi_wdata_o(npu_axi_wdata_o),
            .npu_axi_wstrb_o(npu_axi_wstrb_o),
            .npu_axi_wvalid_o(npu_axi_wvalid_o),
            .npu_axi_wready_i(npu_axi_wready_i),
            .npu_axi_bresp_i(npu_axi_bresp_i),
            .npu_axi_bvalid_i(npu_axi_bvalid_i),
            .npu_axi_bready_o(npu_axi_bready_o),
            .npu_axi_araddr_o(npu_axi_araddr_o),
            .npu_axi_arprot_o(npu_axi_arprot_o),
            .npu_axi_arvalid_o(npu_axi_arvalid_o),
            .npu_axi_arready_i(npu_axi_arready_i),
            .npu_axi_rdata_i(npu_axi_rdata_i),
            .npu_axi_rresp_i(npu_axi_rresp_i),
            .npu_axi_rvalid_i(npu_axi_rvalid_i),
            .npu_axi_rready_o(npu_axi_rready_o),
            .video_axi_awaddr_o(video_axi_awaddr_o),
            .video_axi_awprot_o(video_axi_awprot_o),
            .video_axi_awvalid_o(video_axi_awvalid_o),
            .video_axi_awready_i(video_axi_awready_i),
            .video_axi_wdata_o(video_axi_wdata_o),
            .video_axi_wstrb_o(video_axi_wstrb_o),
            .video_axi_wvalid_o(video_axi_wvalid_o),
            .video_axi_wready_i(video_axi_wready_i),
            .video_axi_bresp_i(video_axi_bresp_i),
            .video_axi_bvalid_i(video_axi_bvalid_i),
            .video_axi_bready_o(video_axi_bready_o),
            .video_axi_araddr_o(video_axi_araddr_o),
            .video_axi_arprot_o(video_axi_arprot_o),
            .video_axi_arvalid_o(video_axi_arvalid_o),
            .video_axi_arready_i(video_axi_arready_i),
            .video_axi_rdata_i(video_axi_rdata_i),
            .video_axi_rresp_i(video_axi_rresp_i),
            .video_axi_rvalid_i(video_axi_rvalid_i),
            .video_axi_rready_o(video_axi_rready_o),
            .axi_awvalid_o(axi_awvalid_o),
            .axi_awaddr_o(axi_awaddr_o),
            .axi_awid_o(axi_awid_o),
            .axi_awlen_o(axi_awlen_o),
            .axi_awsize_o(axi_awsize_o),
            .axi_awburst_o(axi_awburst_o),
            .axi_awready_i(axi_awready_i),
            .axi_wvalid_o(axi_wvalid_o),
            .axi_wdata_o(axi_wdata_o),
            .axi_wstrb_o(axi_wstrb_o),
            .axi_wlast_o(axi_wlast_o),
            .axi_wready_i(axi_wready_i),
            .axi_bvalid_i(axi_bvalid_i),
            .axi_bresp_i(axi_bresp_i),
            .axi_bid_i(axi_bid_i),
            .axi_bready_o(axi_bready_o),
            .axi_arvalid_o(axi_arvalid_o),
            .axi_araddr_o(axi_araddr_o),
            .axi_arid_o(axi_arid_o),
            .axi_arlen_o(axi_arlen_o),
            .axi_arsize_o(axi_arsize_o),
            .axi_arburst_o(axi_arburst_o),
            .axi_arready_i(axi_arready_i),
            .axi_rvalid_i(axi_rvalid_i),
            .axi_rdata_i(axi_rdata_i),
            .axi_rresp_i(axi_rresp_i),
            .axi_rid_i(axi_rid_i),
            .axi_rlast_i(axi_rlast_i),
            .axi_rready_o(axi_rready_o)
        );
    end endgenerate
    application_fake_axil #(.IDENTITY(0)) u_npu_endpoint (
        .clk_i(clk), .rst_ni(rst_n), .irq_o(irqs[0]), .finish_o(finish[0]),
        .reads_o(mmio_reads[0]), .writes_o(mmio_writes[0]), .corrupt_i(BROKEN && 0==1),
        .awaddr(npu_axi_awaddr_o),
        .awprot(npu_axi_awprot_o),
        .awvalid(npu_axi_awvalid_o),
        .awready(npu_axi_awready_i),
        .wdata(npu_axi_wdata_o),
        .wstrb(npu_axi_wstrb_o),
        .wvalid(npu_axi_wvalid_o),
        .wready(npu_axi_wready_i),
        .bresp(npu_axi_bresp_i),
        .bvalid(npu_axi_bvalid_i),
        .bready(npu_axi_bready_o),
        .araddr(npu_axi_araddr_o),
        .arprot(npu_axi_arprot_o),
        .arvalid(npu_axi_arvalid_o),
        .arready(npu_axi_arready_i),
        .rdata(npu_axi_rdata_i),
        .rresp(npu_axi_rresp_i),
        .rvalid(npu_axi_rvalid_i),
        .rready(npu_axi_rready_o)
    );
    application_fake_axil #(.IDENTITY(1)) u_video_endpoint (
        .clk_i(clk), .rst_ni(rst_n), .irq_o(irqs[1]), .finish_o(finish[1]),
        .reads_o(mmio_reads[1]), .writes_o(mmio_writes[1]), .corrupt_i(BROKEN && 1==1),
        .awaddr(video_axi_awaddr_o),
        .awprot(video_axi_awprot_o),
        .awvalid(video_axi_awvalid_o),
        .awready(video_axi_awready_i),
        .wdata(video_axi_wdata_o),
        .wstrb(video_axi_wstrb_o),
        .wvalid(video_axi_wvalid_o),
        .wready(video_axi_wready_i),
        .bresp(video_axi_bresp_i),
        .bvalid(video_axi_bvalid_i),
        .bready(video_axi_bready_o),
        .araddr(video_axi_araddr_o),
        .arprot(video_axi_arprot_o),
        .arvalid(video_axi_arvalid_o),
        .arready(video_axi_arready_i),
        .rdata(video_axi_rdata_i),
        .rresp(video_axi_rresp_i),
        .rvalid(video_axi_rvalid_i),
        .rready(video_axi_rready_o)
    );
    application_fake_ddr u_ddr (.clk_i(clk),.rst_ni(rst_n),.hold_i(ddr_hold),.reads_o(ddr_reads),.writes_o(ddr_writes),
        .awvalid(axi_awvalid_o),
        .awaddr(axi_awaddr_o),
        .awid(axi_awid_o),
        .awlen(axi_awlen_o),
        .awsize(axi_awsize_o),
        .awburst(axi_awburst_o),
        .awready(axi_awready_i),
        .wvalid(axi_wvalid_o),
        .wdata(axi_wdata_o),
        .wstrb(axi_wstrb_o),
        .wlast(axi_wlast_o),
        .wready(axi_wready_i),
        .bvalid(axi_bvalid_i),
        .bresp(axi_bresp_i),
        .bid(axi_bid_i),
        .bready(axi_bready_o),
        .arvalid(axi_arvalid_o),
        .araddr(axi_araddr_o),
        .arid(axi_arid_o),
        .arlen(axi_arlen_o),
        .arsize(axi_arsize_o),
        .arburst(axi_arburst_o),
        .arready(axi_arready_i),
        .rvalid(axi_rvalid_i),
        .rdata(axi_rdata_i),
        .rresp(axi_rresp_i),
        .rid(axi_rid_i),
        .rlast(axi_rlast_i),
        .rready(axi_rready_o)
    );

    task check(input condition,input [511:0] reason);
        begin checks=checks+1; if(condition!==1'b1)$fatal(1,"APPLICATION_FAIL %0s cycle=%0d",reason,cycles); end
    endtask
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(cycles>100000)$fatal(1,"APPLICATION_FAIL watchdog");
        if(rst_n && protocol_fault)$fatal(1,"APPLICATION_FAIL protocol fault");
        if(irqs[0])irq_seen<=1;
        if(irq_seen && !irqs[0])irq_cleared<=1;
        if(CPU_MODE && finish[1]!=0)begin
            check(finish[1]==32'h600d600d,"firmware completion");
        end
        // The completion register changes before the endpoint's B handshake.
        if(CPU_MODE && finish[1]!=0 && mmio_writes[1]>=2)begin
            check(mmio_reads[0]>=1 && mmio_reads[1]>=1,"both endpoint reads");
            check(mmio_writes[0]==3 && mmio_writes[1]==2,"both endpoint writes");
            check(ddr_reads>=2 && ddr_writes>=2,"shared DDR transactions");
            check(irq_seen && irq_cleared,"external IRQ handler acknowledged source");
            $display("APPLICATION_CPU_PASS cycles=%0d checks=%0d npu_reads=%0d video_reads=%0d ddr_reads=%0d ddr_writes=%0d irq=1",cycles,checks,mmio_reads[0],mmio_reads[1],ddr_reads,ddr_writes);
            $finish;
        end
    end
    task access(input [31:0] address,input [3:0] mask,input [31:0] value,
                input cacheable,input [2:0] maintenance,input error_expected,input [31:0] expected);
        integer guard; reg [10:0] saved_tag;
        begin
            @(negedge clk);d_addr=address;d_wdata=value;d_wstrb=mask;d_re=(mask==0 && maintenance==0);
            d_cacheable=cacheable;{d_flush,d_writeback,d_invalidate}=maintenance;d_tag=d_tag+1;saved_tag=d_tag;
            guard=0;
            begin:accept_loop forever begin @(posedge clk);guard=guard+1;if(d_accept)disable accept_loop;
                if(guard>20000)$fatal(1,"APPLICATION_FAIL data accept timeout"); end end
            @(negedge clk);d_re=0;d_wstrb=0;{d_flush,d_writeback,d_invalidate}=0;
            d_addr=32'h20010000;d_tag=11'h7fe;
            while(!d_ack)begin check(!d_accept,"owner locked until response");waits=waits+1;@(negedge clk);guard=guard+1;
                if(guard>25000)$fatal(1,"APPLICATION_FAIL data response timeout");end
            check(d_resp_tag==saved_tag,"accepted tag survives changing inputs");
            check(d_error===error_expected,"data error completion");
            if(mask==0 && maintenance==0 && !error_expected)check(d_data===expected,"data readback");
            @(negedge clk);
        end
    endtask
    task fetch(input [31:0] address,input error_expected,input [63:0] expected);
        integer guard;
        begin
            @(negedge clk);i_req=1;i_addr=address;guard=0;
            begin:accept_loop forever begin @(posedge clk);guard=guard+1;if(i_accept)disable accept_loop;
                if(guard>20000)$fatal(1,"APPLICATION_FAIL fetch accept timeout");end end
            @(negedge clk);i_req=0;i_addr=32'h20000000;
            while(!i_valid)begin @(negedge clk);guard=guard+1;if(guard>22000)$fatal(1,"APPLICATION_FAIL fetch response timeout");end
            check(i_error===error_expected,"fetch error");if(!error_expected)check(i_data===expected,"fetch data");
            @(negedge clk);
        end
    endtask
    integer before_reads,before_writes,guard;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;ddr_ready=1;
        if(!CPU_MODE)begin
            fetch(0,0,64'h00028067000102b7);
            fetch(32'h1ff8,0,64'h0010007300100073);
            fetch(32'h1ffc,1,0);fetch(32'h2000,1,0);fetch(32'h18000,1,0);fetch(32'h88000000,1,0);
            access(32'h10001,0,0,0,0,1,0);access(0,15,1,0,0,1,0);access(32'h4000,0,0,0,0,1,0);
            access(32'h10000,15,32'h1234abcd,0,0,0,0);
            access(32'h10000,0,0,0,0,0,32'h1234abcd);
            // A simultaneous same-64-bit-word store takes precedence over I.
            @(negedge clk);d_addr=32'h10000;d_wdata=32'h76543210;d_wstrb=15;d_tag=11'h31;i_addr=32'h10000;i_req=1;
            @(posedge clk);check(d_accept && !i_accept,"SRAM I/write collision stalls fetch");
            @(negedge clk);d_wstrb=0;
            begin:collision_accept forever begin @(posedge clk);if(i_accept)disable collision_accept;end end
            @(negedge clk);i_req=0;check(i_valid && i_data[31:0]==32'h76543210,"fetch sees committed SRAM store");
            @(negedge clk);
            access(32'h20000000,15,32'h10203040,0,0,0,0);
            access(32'h20010000,15,32'h50607080,0,0,0,0);
            access(32'h20000000,0,0,0,0,0,32'h10203040);
            access(32'h20010000,0,0,0,0,0,32'h50607080);
            access(32'h20000000,0,0,1,0,1,0);
            access(32'h20010001,0,0,0,0,1,0);
            before_writes=mmio_writes[0];access(32'h20000000,0,0,0,3'b100,0,0);
            check(mmio_writes[0]==before_writes,"global maintenance never writes MMIO");
            access(32'h82001000,15,32'haabbccdd,1,0,0,0);
            access(32'h82001000,2,32'h00001100,1,0,0,0);
            access(32'h82001000,0,0,1,0,0,32'haabb11dd);
            before_reads=ddr_reads;access(32'h82001000,0,0,1,0,0,32'haabb11dd);
            check(ddr_reads==before_reads+1,"shared DDR always bypasses");
            access(32'h80001000,0,0,1,0,0,0);
            before_reads=ddr_reads;access(32'h80001000,0,0,1,0,0,0);
            check(ddr_reads==before_reads,"private DDR resident load hits cache");
            before_writes=ddr_writes;access(32'h80001000,15,32'h11223344,1,0,0,0);
            check(ddr_writes==before_writes,"private dirty store is not posted to DDR");
            access(32'h80001000,0,0,1,3'b010,0,0);
            check(ddr_writes>=before_writes+8,"private line writeback completes");
            // Not-ready gates only new work. Then lock an accepted response,
            // change target/tag, drop ready and assert fault before returning it.
            @(negedge clk);ddr_ready=0;ddr_hold=1;d_addr=32'h82001000;d_re=1;d_cacheable=0;d_tag=11'h57;
            repeat(8)begin @(posedge clk);check(!d_accept,"DDR not-ready stalls new request");end
            @(negedge clk);ddr_ready=1;
            begin:late_accept forever begin @(posedge clk);if(d_accept)disable late_accept;end end
            @(negedge clk);d_addr=32'h20000000;d_tag=11'h58; // next target held while old response drains
            begin:ar_accept forever begin @(posedge clk);if(axi_arvalid_o&&axi_arready_i)disable ar_accept;end end
            @(negedge clk);ddr_ready=0;ddr_fault=1;
            repeat(8)begin @(posedge clk);check(!d_accept && !d_ack,"target switch blocked during inflight DDR");end
            @(negedge clk);ddr_hold=0;
            guard=0;while(!d_ack)begin @(negedge clk);guard=guard+1;if(guard>1000)$fatal(1,"APPLICATION_FAIL lost inflight response");end
            check(!d_error && d_data==32'haabb11dd && d_resp_tag==11'h57,"response survives loss of DDR ready/fault");
            d_re=0;@(negedge clk);ddr_fault=0;
            access(32'h82001000,0,0,0,0,1,0);
            access(32'h10000,0,0,0,0,0,32'h76543210);
            access(32'h20000000,0,0,0,0,0,32'h10203040);
            check(fault,"DDR fault sticky until coordinated reset");check(waits>20,"response backpressure exercised");
            $display("APPLICATION_ROUTER_PASS cycles=%0d checks=%0d waits=%0d ddr_reads=%0d ddr_writes=%0d",cycles,checks,waits,ddr_reads,ddr_writes);
            $finish;
        end
    end
endmodule

module application_fake_axil #(parameter integer IDENTITY=0)(
    input wire clk_i,rst_ni,corrupt_i,
    output wire irq_o, output wire [31:0] finish_o,
    output reg [31:0] reads_o=0,writes_o=0,
    input wire [31:0] awaddr,
    input wire [2:0] awprot,
    input wire awvalid,
    output reg awready,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire wvalid,
    output reg wready,
    output reg [1:0] bresp,
    output reg bvalid,
    input wire bready,
    input wire [31:0] araddr,
    input wire [2:0] arprot,
    input wire arvalid,
    output reg arready,
    output reg [31:0] rdata,
    output reg [1:0] rresp,
    output reg rvalid,
    input wire rready
);
    reg [31:0] words[0:63];reg [31:0] saved_aw,saved_w,saved_ar;reg [3:0] saved_strb;
    reg have_aw=0,have_w=0,have_ar=0;integer ticks=0,bdelay=0,rdelay=0,i;
    assign irq_o=IDENTITY==0 && words[8][0];assign finish_o=words[60];
    always @* begin awready=rst_ni&&!have_aw&&(ticks%5==0);wready=rst_ni&&!have_w&&(ticks%7==0);arready=rst_ni&&!have_ar&&(ticks%3==0);end
    always @(posedge clk_i)begin
        ticks<=ticks+1;
        if(!rst_ni)begin
            have_aw<=0;have_w<=0;have_ar<=0;bvalid<=0;rvalid<=0;bresp<=0;rresp<=0;rdata<=0;
            bdelay<=0;rdelay<=0;reads_o<=0;writes_o<=0;
            for(i=0;i<64;i=i+1)words[i]<=0;
        end else begin
            if(awvalid&&awready)begin have_aw<=1;saved_aw<=awaddr;end
            if(wvalid&&wready)begin have_w<=1;saved_w<=wdata;saved_strb<=wstrb;end
            if(have_aw&&have_w&&!bvalid)begin
                if(bdelay==11)begin
                    bvalid<=1;bresp<=0;
                    for(i=0;i<4;i=i+1)if(saved_strb[i])words[saved_aw[7:2]][i*8+:8]<=saved_w[i*8+:8];
                end else bdelay<=bdelay+1;
            end
            if(bvalid&&bready)begin bvalid<=0;have_aw<=0;have_w<=0;bdelay<=0;writes_o<=writes_o+1;end
            if(arvalid&&arready)begin have_ar<=1;saved_ar<=araddr;rdelay<=9;end
            if(have_ar&&!rvalid)begin
                if(rdelay==0)begin rvalid<=1;rresp<=0;rdata<=words[saved_ar[7:2]] ^ (corrupt_i?32'h1:0);end
                else rdelay<=rdelay-1;
            end
            if(rvalid&&rready)begin rvalid<=0;have_ar<=0;reads_o<=reads_o+1;end
        end
    end
endmodule

module application_fake_ddr(input wire clk_i,rst_ni,hold_i,
    output reg [31:0] reads_o=0,writes_o=0,
    input wire awvalid,
    input wire [31:0] awaddr,
    input wire [3:0] awid,
    input wire [7:0] awlen,
    input wire [2:0] awsize,
    input wire [1:0] awburst,
    output reg awready,
    input wire wvalid,
    input wire [127:0] wdata,
    input wire [15:0] wstrb,
    input wire wlast,
    output reg wready,
    output reg bvalid,
    output reg [1:0] bresp,
    output reg [3:0] bid,
    input wire bready,
    input wire arvalid,
    input wire [31:0] araddr,
    input wire [3:0] arid,
    input wire [7:0] arlen,
    input wire [2:0] arsize,
    input wire [1:0] arburst,
    output reg arready,
    output reg rvalid,
    output reg [127:0] rdata,
    output reg [1:0] rresp,
    output reg [3:0] rid,
    output reg rlast,
    input wire rready
);
    reg [31:0] words[0:4095];reg [31:0] saved_aw,saved_ar;reg [127:0] saved_w;reg [15:0] saved_strb;
    reg [3:0] saved_awid;reg have_aw=0,have_w=0,have_ar=0;
    integer ticks=0,bdelay=0,rdelay=0,beats=0,beat=0,i;
    function integer index_of(input [31:0] address);index_of=address[12:2]+(address[25]?2048:0);endfunction
    initial for(i=0;i<4096;i=i+1)words[i]=0;
    always @* begin awready=rst_ni&&!have_aw&&(ticks%5==0);wready=rst_ni&&!have_w&&(ticks%4==0);arready=rst_ni&&!have_ar&&(ticks%3==0);end
    always @(posedge clk_i)begin
        ticks<=ticks+1;
        if(!rst_ni)begin
            have_aw<=0;have_w<=0;have_ar<=0;bvalid<=0;rvalid<=0;bresp<=0;rresp<=0;rdata<=0;rlast<=0;bid<=0;rid<=0;
            bdelay<=0;rdelay<=0;reads_o<=0;writes_o<=0;
        end else begin
            if(awvalid&&awready)begin have_aw<=1;saved_aw<=awaddr;saved_awid<=awid;
                if(awlen!=0||awsize!=4||awburst!=1||awaddr[3:0]!=0)$fatal(1,"APPLICATION_FAIL AW geometry");end
            if(wvalid&&wready)begin have_w<=1;saved_w<=wdata;saved_strb<=wstrb;if(!wlast)$fatal(1,"APPLICATION_FAIL WLAST");end
            if(have_aw&&have_w&&!bvalid&&!hold_i)begin
                if(bdelay==13)begin bvalid<=1;bid<=saved_awid;bresp<=0;
                    for(i=0;i<16;i=i+1)if(saved_strb[i])words[index_of(saved_aw)+i/4][(i%4)*8+:8]<=saved_w[i*8+:8];end
                else bdelay<=bdelay+1;
            end
            if(bvalid&&bready)begin bvalid<=0;have_aw<=0;have_w<=0;bdelay<=0;writes_o<=writes_o+1;end
            if(arvalid&&arready)begin
                if(arlen>1||arsize!=4||arburst!=1||araddr[3:0]!=0)$fatal(1,"APPLICATION_FAIL AR geometry");
                have_ar<=1;saved_ar<=araddr;beats<=arlen+1;beat<=0;rid<=arid;rdelay<=7;reads_o<=reads_o+1;
            end
            if(have_ar&&!rvalid&&!hold_i)begin
                if(rdelay==0)begin rvalid<=1;rlast<=beat==beats-1;rresp<=0;
                    for(i=0;i<4;i=i+1)rdata[i*32+:32]<=words[index_of(saved_ar)+beat*4+i];end
                else rdelay<=rdelay-1;
            end
            if(rvalid&&rready)begin rvalid<=0;rdelay<=5;if(rlast)have_ar<=0;else beat<=beat+1;end
        end
    end
endmodule
`default_nettype wire
