`timescale 1ns/1ps
`default_nettype none
// Actual CPU + B03 MODEL/POST, compute arbitration, CDC and shared native owner.
// Only the final byte-addressed DDR storage and test-finish MMIO are models.
module tb_cpu_b03;
    reg cpu_clk=0,ddr_clk=0,rst_n=0,grs_n=0,init_done=0,model_sealed=0;
    always #5 cpu_clk=~cpu_clk;
    always #4 ddr_clk=~ddr_clk;
    GTP_GRS GRS_INST(.GRS_N(grs_n));
    wire cpu_rst,ddr_rst,cpu_ready,cpu_memory_fault,system_fault,fabric_fault;
    wire npu_irq,npu_idle,compute_idle,fabric_idle;wire [7:0] stage,op,fabric_code;
    wire c_awvalid;
    wire c_awready;
    wire [31:0] c_awaddr;
    wire [3:0] c_awid;
    wire [7:0] c_awlen;
    wire [2:0] c_awsize;
    wire [1:0] c_awburst;
    wire c_wvalid;
    wire c_wready;
    wire [127:0] c_wdata;
    wire [15:0] c_wstrb;
    wire c_wlast;
    wire c_bvalid;
    wire c_bready;
    wire [3:0] c_bid;
    wire [1:0] c_bresp;
    wire c_arvalid;
    wire c_arready;
    wire [31:0] c_araddr;
    wire [3:0] c_arid;
    wire [7:0] c_arlen;
    wire [2:0] c_arsize;
    wire [1:0] c_arburst;
    wire c_rvalid;
    wire c_rready;
    wire [127:0] c_rdata;
    wire [3:0] c_rid;
    wire [1:0] c_rresp;
    wire c_rlast;
    wire d_awvalid;
    wire d_awready;
    wire [31:0] d_awaddr;
    wire [3:0] d_awid;
    wire [7:0] d_awlen;
    wire [2:0] d_awsize;
    wire [1:0] d_awburst;
    wire d_wvalid;
    wire d_wready;
    wire [127:0] d_wdata;
    wire [15:0] d_wstrb;
    wire d_wlast;
    wire d_bvalid;
    wire d_bready;
    wire [3:0] d_bid;
    wire [1:0] d_bresp;
    wire d_arvalid;
    wire d_arready;
    wire [31:0] d_araddr;
    wire [3:0] d_arid;
    wire [7:0] d_arlen;
    wire [2:0] d_arsize;
    wire [1:0] d_arburst;
    wire d_rvalid;
    wire d_rready;
    wire [127:0] d_rdata;
    wire [3:0] d_rid;
    wire [1:0] d_rresp;
    wire d_rlast;
    wire [31:0] v_awaddr;
    wire [2:0] v_awprot;
    wire v_awvalid;
    wire v_awready;
    wire [31:0] v_wdata;
    wire [3:0] v_wstrb;
    wire v_wvalid;
    wire v_wready;
    wire [1:0] v_bresp;
    wire v_bvalid;
    wire v_bready;
    wire [31:0] v_araddr;
    wire [2:0] v_arprot;
    wire v_arvalid;
    wire v_arready;
    wire [31:0] v_rdata;
    wire [1:0] v_rresp;
    wire v_rvalid;
    wire v_rready;
    triha_compute_system u_system (
        .clk_i(cpu_clk),
        .rst_ni(cpu_rst),
        .healthy_i(cpu_ready),
        .memory_fault_i(cpu_memory_fault),
        .model_sealed_i(model_sealed),
        .video_irq_i(1'b0),
        .epoch_i(32'd7),
        .addr_version_i(32'd1),
        .video_axi_awaddr_o(v_awaddr),
        .video_axi_awprot_o(v_awprot),
        .video_axi_awvalid_o(v_awvalid),
        .video_axi_awready_i(v_awready),
        .video_axi_wdata_o(v_wdata),
        .video_axi_wstrb_o(v_wstrb),
        .video_axi_wvalid_o(v_wvalid),
        .video_axi_wready_i(v_wready),
        .video_axi_bresp_i(v_bresp),
        .video_axi_bvalid_i(v_bvalid),
        .video_axi_bready_o(v_bready),
        .video_axi_araddr_o(v_araddr),
        .video_axi_arprot_o(v_arprot),
        .video_axi_arvalid_o(v_arvalid),
        .video_axi_arready_i(v_arready),
        .video_axi_rdata_i(v_rdata),
        .video_axi_rresp_i(v_rresp),
        .video_axi_rvalid_i(v_rvalid),
        .video_axi_rready_o(v_rready),
        .m_awvalid_o(c_awvalid),
        .m_awready_i(c_awready),
        .m_awaddr_o(c_awaddr),
        .m_awid_o(c_awid),
        .m_awlen_o(c_awlen),
        .m_awsize_o(c_awsize),
        .m_awburst_o(c_awburst),
        .m_wvalid_o(c_wvalid),
        .m_wready_i(c_wready),
        .m_wdata_o(c_wdata),
        .m_wstrb_o(c_wstrb),
        .m_wlast_o(c_wlast),
        .m_bvalid_i(c_bvalid),
        .m_bready_o(c_bready),
        .m_bid_i(c_bid),
        .m_bresp_i(c_bresp),
        .m_arvalid_o(c_arvalid),
        .m_arready_i(c_arready),
        .m_araddr_o(c_araddr),
        .m_arid_o(c_arid),
        .m_arlen_o(c_arlen),
        .m_arsize_o(c_arsize),
        .m_arburst_o(c_arburst),
        .m_rvalid_i(c_rvalid),
        .m_rready_o(c_rready),
        .m_rdata_i(c_rdata),
        .m_rid_i(c_rid),
        .m_rresp_i(c_rresp),
        .m_rlast_i(c_rlast),
        .fault_o(system_fault),
        .npu_irq_o(npu_irq),
        .npu_idle_o(npu_idle),
        .compute_idle_o(compute_idle),
        .npu_stage_o(stage),
        .npu_op_o(op)
    );
    triha_axi128_cdc u_cdc (
        .cpu_clk_i(cpu_clk),
        .ddr_clk_i(ddr_clk),
        .rst_ni(rst_n),
        .cpu_rst_no(cpu_rst),
        .ddr_rst_no(ddr_rst),
        .ddr_ready_i(init_done),
        .ddr_fault_i(fabric_fault),
        .cpu_ddr_ready_o(cpu_ready),
        .cpu_ddr_fault_o(cpu_memory_fault),
        .s_awvalid_i(c_awvalid),
        .m_awvalid_o(d_awvalid),
        .s_awready_o(c_awready),
        .m_awready_i(d_awready),
        .s_awaddr_i(c_awaddr),
        .m_awaddr_o(d_awaddr),
        .s_awid_i(c_awid),
        .m_awid_o(d_awid),
        .s_awlen_i(c_awlen),
        .m_awlen_o(d_awlen),
        .s_awsize_i(c_awsize),
        .m_awsize_o(d_awsize),
        .s_awburst_i(c_awburst),
        .m_awburst_o(d_awburst),
        .s_wvalid_i(c_wvalid),
        .m_wvalid_o(d_wvalid),
        .s_wready_o(c_wready),
        .m_wready_i(d_wready),
        .s_wdata_i(c_wdata),
        .m_wdata_o(d_wdata),
        .s_wstrb_i(c_wstrb),
        .m_wstrb_o(d_wstrb),
        .s_wlast_i(c_wlast),
        .m_wlast_o(d_wlast),
        .s_bvalid_o(c_bvalid),
        .m_bvalid_i(d_bvalid),
        .s_bready_i(c_bready),
        .m_bready_o(d_bready),
        .s_bid_o(c_bid),
        .m_bid_i(d_bid),
        .s_bresp_o(c_bresp),
        .m_bresp_i(d_bresp),
        .s_arvalid_i(c_arvalid),
        .m_arvalid_o(d_arvalid),
        .s_arready_o(c_arready),
        .m_arready_i(d_arready),
        .s_araddr_i(c_araddr),
        .m_araddr_o(d_araddr),
        .s_arid_i(c_arid),
        .m_arid_o(d_arid),
        .s_arlen_i(c_arlen),
        .m_arlen_o(d_arlen),
        .s_arsize_i(c_arsize),
        .m_arsize_o(d_arsize),
        .s_arburst_i(c_arburst),
        .m_arburst_o(d_arburst),
        .s_rvalid_o(c_rvalid),
        .m_rvalid_i(d_rvalid),
        .s_rready_i(c_rready),
        .m_rready_o(d_rready),
        .s_rdata_o(c_rdata),
        .m_rdata_i(d_rdata),
        .s_rid_o(c_rid),
        .m_rid_i(d_rid),
        .s_rresp_o(c_rresp),
        .m_rresp_i(d_rresp),
        .s_rlast_o(c_rlast),
        .m_rlast_i(d_rlast)
    );
    wire [27:0] h_awaddr,h_araddr;wire [3:0] h_awlen,h_arlen,h_awid,h_arid,h_wid;
    wire h_awvalid,h_arvalid,h_awready,h_arready,h_wready,h_wlast;
    wire [255:0] h_wdata;wire [31:0] h_wstrb;
    reg h_rvalid=0,h_rlast=0;reg [3:0] h_rid=0;reg [255:0] h_rdata=0;
    wire [2:0] p_awready;
    assign d_awready=p_awready[0];
    wire [2:0] p_wready;
    assign d_wready=p_wready[0];
    wire [2:0] p_bvalid;
    assign d_bvalid=p_bvalid[0];
    wire [11:0] p_bid;
    assign d_bid=p_bid[3:0];
    wire [5:0] p_bresp;
    assign d_bresp=p_bresp[1:0];
    wire [2:0] p_arready;
    assign d_arready=p_arready[0];
    wire [2:0] p_rvalid;
    assign d_rvalid=p_rvalid[0];
    wire [383:0] p_rdata;
    assign d_rdata=p_rdata[127:0];
    wire [11:0] p_rid;
    assign d_rid=p_rid[3:0];
    wire [5:0] p_rresp;
    assign d_rresp=p_rresp[1:0];
    wire [2:0] p_rlast;
    assign d_rlast=p_rlast[0];
    soc_ddr_fabric u_fabric (
        .clk_i(ddr_clk),
        .rst_ni(ddr_rst),
        .healthy_i(init_done&&!fabric_fault),
        .init_done_i(init_done),
        .s_awvalid_i({2'b0,d_awvalid}),
        .s_awready_o(p_awready),
        .s_awaddr_i({64'b0,d_awaddr}),
        .s_awid_i({8'b0,d_awid}),
        .s_awlen_i({16'b0,d_awlen}),
        .s_awsize_i({6'b0,d_awsize}),
        .s_awburst_i({4'b0,d_awburst}),
        .s_wvalid_i({2'b0,d_wvalid}),
        .s_wready_o(p_wready),
        .s_wdata_i({256'b0,d_wdata}),
        .s_wstrb_i({32'b0,d_wstrb}),
        .s_wlast_i({2'b0,d_wlast}),
        .s_bvalid_o(p_bvalid),
        .s_bready_i({2'b0,d_bready}),
        .s_bid_o(p_bid),
        .s_bresp_o(p_bresp),
        .s_arvalid_i({2'b0,d_arvalid}),
        .s_arready_o(p_arready),
        .s_araddr_i({64'b0,d_araddr}),
        .s_arid_i({8'b0,d_arid}),
        .s_arlen_i({16'b0,d_arlen}),
        .s_arsize_i({6'b0,d_arsize}),
        .s_arburst_i({4'b0,d_arburst}),
        .s_rvalid_o(p_rvalid),
        .s_rready_i({2'b0,d_rready}),
        .s_rdata_o(p_rdata),
        .s_rid_o(p_rid),
        .s_rresp_o(p_rresp),
        .s_rlast_o(p_rlast),
        .idle_o(fabric_idle),
        .fault_o(fabric_fault),
        .fault_code_o(fabric_code),
        .h_awaddr(h_awaddr),
        .h_araddr(h_araddr),
        .h_awlen(h_awlen),
        .h_arlen(h_arlen),
        .h_awid(h_awid),
        .h_arid(h_arid),
        .h_awvalid(h_awvalid),
        .h_arvalid(h_arvalid),
        .h_awready(h_awready),
        .h_arready(h_arready),
        .h_wready(h_wready),
        .h_rvalid(h_rvalid),
        .h_wdata(h_wdata),
        .h_wstrb(h_wstrb),
        .h_rdata(h_rdata),
        .h_wid(h_wid),
        .h_rid(h_rid),
        .h_wlast(h_wlast),
        .h_rlast(h_rlast)
    );

    // Address geometry and registered read timing follow the existing Video
    // video_record_pipeline_memory proxy; no upstream NPU native bridge is used.
    localparam [31:0] MEMORY_BASE=32'h82800000,MEMORY_END=32'h83800000;
    reg [255:0] memory[0:524287];reg [7:0] golden_heads[0:52735];
    reg writing=0,reading=0;reg [31:0] wa=0,ra=0;reg [3:0] wid=0,rid=0;
    integer ticks=0,wi=0,wn=0,ri=0,rn=0,lane,aw_count=0,ar_count=0,w_count=0,r_count=0;
    wire [31:0] aw_byte=32'h80000000+{2'b0,h_awaddr,2'b0};
    wire [31:0] ar_byte=32'h80000000+{2'b0,h_araddr,2'b0};
    assign h_awready=ddr_rst&&init_done&&!writing&&!reading&&!h_rvalid&&(ticks%5!=1);
    assign h_arready=ddr_rst&&init_done&&!writing&&!reading&&!h_rvalid&&!h_awvalid&&(ticks%7!=2);
    assign h_wready=ddr_rst&&writing&&(ticks%4!=0);
    assign h_wid=wid;assign h_wlast=wi==wn-1;
    always @(posedge ddr_clk)begin
        if(!ddr_rst)begin writing<=0;reading<=0;h_rvalid<=0;wi<=0;ri<=0;ticks<=0;end
        else begin
            ticks<=ticks+1;h_rvalid<=0;
            if(h_awvalid&&h_awready)begin
                if(aw_byte<MEMORY_BASE||{1'b0,aw_byte}+((h_awlen+1)<<5)>{1'b0,MEMORY_END})$fatal(1,"CPU_B03 native write range %h",aw_byte);
                writing<=1;wa<=aw_byte;wid<=h_awid;wi<=0;wn<=h_awlen+1;aw_count<=aw_count+1;
            end
            if(writing&&h_wready)begin
                for(lane=0;lane<32;lane=lane+1)if(h_wstrb[lane])memory[(wa-MEMORY_BASE)/32][lane*8+:8]<=h_wdata[lane*8+:8];
                wa<=wa+32;wi<=wi+1;w_count<=w_count+1;if(wi==wn-1)writing<=0;
            end
            if(h_arvalid&&h_arready)begin
                if(ar_byte<MEMORY_BASE||{1'b0,ar_byte}+((h_arlen+1)<<5)>{1'b0,MEMORY_END})$fatal(1,"CPU_B03 native read range %h",ar_byte);
                reading<=1;ra<=ar_byte;rid<=h_arid;ri<=0;rn<=h_arlen+1;ar_count<=ar_count+1;
            end
            if(reading&&ticks%3!=0)begin
                h_rdata<=memory[(ra-MEMORY_BASE)/32];h_rid<=rid;h_rvalid<=1;h_rlast<=ri==rn-1;
                ra<=ra+32;ri<=ri+1;r_count<=r_count+1;if(ri==rn-1)reading<=0;
            end
        end
    end
    function automatic [7:0] byte_at(input [31:0] address);
        byte_at=memory[(address-MEMORY_BASE)/32][(address%32)*8+:8];
    endfunction
    function automatic [31:0] word_at(input [31:0] address);
        word_at={byte_at(address+3),byte_at(address+2),byte_at(address+1),byte_at(address)};
    endfunction
    integer fd,uploads,index,count,preload_words;reg [31:0] load_address,seal_magic;
    string leaf;reg [31:0] seal[0:0];
    initial begin
        for(index=0;index<524288;index=index+1)memory[index]=0;
        fd=$fopen("uploads.txt","r");if(!fd)$fatal(1,"CPU_B03 missing uploads");
        count=$fscanf(fd,"%d\n",uploads);if(count!=1||uploads!=7)$fatal(1,"CPU_B03 uploads count");
        for(index=0;index<uploads;index=index+1)begin
            count=$fscanf(fd,"%h %d %s\n",load_address,preload_words,leaf);
            if(count!=3||load_address<MEMORY_BASE||load_address+preload_words>MEMORY_END||load_address%32||preload_words%32)$fatal(1,"CPU_B03 bad preload");
            $readmemh(leaf,memory,(load_address-MEMORY_BASE)/32,(load_address-MEMORY_BASE+preload_words)/32-1);
        end
        $fclose(fd);
        $readmemh("heads_golden_0.hex",golden_heads,0,26367);
        $readmemh("heads_golden_1.hex",golden_heads,26368,52735);
        $readmemh("preload_verified.txt",seal);
        if(seal[0]!==32'h54524948)$fatal(1,"CPU_B03 asset SHA check receipt missing");
        model_sealed=1;grs_n=1;
        repeat(12)@(negedge ddr_clk);rst_n=1;
        repeat(12)@(negedge ddr_clk);init_done=1;
    end
    // Test-finish sink only. No NPU register or completion behavior is modeled.
    reg have_aw=0,have_w=0,bvalid=0;reg [31:0] saved_aw,saved_w;reg [3:0] saved_strb;
    assign v_awready=cpu_rst&&!have_aw;assign v_wready=cpu_rst&&!have_w;
    assign v_bvalid=bvalid;assign v_bresp=0;assign v_arready=0;assign v_rvalid=0;assign v_rdata=0;assign v_rresp=0;
    integer cycles=0,frames=0,model_ops=0,preflights=0,starts=0,commands=0,dones=0,cpu_result_reads=0;
    integer file_head,file_result,b,result_bytes;reg [31:0] base;
    task automatic verify_frame(input integer number);
        begin
            if(number!=frames||model_ops!=(number+1)*79||preflights!=(number+1)*79||starts!=number+1)$fatal(1,"CPU_B03 incomplete real frame coverage");
            base=32'h82900000+number*32'h40000;
            file_head=$fopen($sformatf("heads_actual_%0d.hex",number),"w");
            for(b=0;b<26368;b=b+1)begin
                if(byte_at(base+b)!==golden_heads[number*26368+b])$fatal(1,"CPU_B03 HEAD mismatch frame=%0d byte=%0d actual=%h expected=%h",number,b,byte_at(base+b),golden_heads[number*26368+b]);
                $fdisplay(file_head,"%02x",byte_at(base+b));
            end
            $fclose(file_head);result_bytes=128+word_at(base+32'h8000+44);
            if(result_bytes!=128||word_at(base+32'h8000+24)!=101+number||word_at(base+32'h8000+32)!=1001+number)$fatal(1,"CPU_B03 empty result identity");
            file_result=$fopen($sformatf("result_actual_%0d.hex",number),"w");
            for(b=0;b<result_bytes;b=b+1)$fdisplay(file_result,"%02x",byte_at(base+32'h8000+b));
            $fclose(file_result);frames=frames+1;
            $display("CPU_B03_FRAME_PASS frame=%0d slot=%0d ops=79 preflights=79 cpu_reads=%0d cycles=%0d commands=%0d dones=%0d",number,number,cpu_result_reads,cycles,commands,dones);
        end
    endtask
    `define FRAME u_system.u_npu.u_service.u_frame
    always @(posedge cpu_clk)begin
        cycles<=cycles+1;
        if(cycles>200000000)$fatal(1,"CPU_B03 watchdog stage=%0d op=%0d",stage,op);
        if(cpu_rst&&(system_fault||fabric_fault))$fatal(1,"CPU_B03 fault system=%b fabric=%b code=%h stage=%0d op=%0d cpu=%b adapter=%b/%h arb=%b npu=%b",system_fault,fabric_fault,fabric_code,stage,op,u_system.cpu_fault,u_system.adapter_fault,u_system.adapter_fault_code,u_system.arb_fault,u_system.npu_fault);
        if(cpu_rst)begin
            if(u_system.u_npu.start_valid&&u_system.u_npu.start_ready)begin starts=starts+1;$display("CPU_B03_START frame=%0d cycle=%0d",starts,cycles);end
            if(`FRAME.l_start&&`FRAME.l_start_ready&&`FRAME.l_preflight)preflights=preflights+1;
            if(`FRAME.l_done&&`FRAME.l_done_ready&&!`FRAME.l_preflight)begin
                if(`FRAME.l_status!=0)$fatal(1,"CPU_B03 MODEL status %d",`FRAME.l_status);
                model_ops=model_ops+1;$display("CPU_B03_OP frame=%0d op=%0d cycles=%0d",starts,`FRAME.l_done_opid,cycles);
            end
            if(u_system.svc_cmd_valid&&u_system.svc_cmd_ready)commands=commands+1;
            if(u_system.svc_done_valid&&u_system.svc_done_ready)dones=dones+1;
            if(u_system.cpu_arvalid&&u_system.cpu_arready)cpu_result_reads=cpu_result_reads+1;
            if(v_awvalid&&v_awready)begin have_aw<=1;saved_aw<=v_awaddr;end
            if(v_wvalid&&v_wready)begin have_w<=1;saved_w<=v_wdata;saved_strb<=v_wstrb;end
            if(have_aw&&have_w&&!bvalid)bvalid<=1;
            if(bvalid&&v_bready)begin
                bvalid<=0;have_aw<=0;have_w<=0;
                if(saved_aw!=32'h2001fff0||saved_strb!=15)$fatal(1,"CPU_B03 invalid testfinish write");
                if(saved_w==32'h600d0001||saved_w==32'h600d0002)verify_frame(saved_w-32'h600d0001);
                else if(saved_w==32'h600d600d)begin
                    if(frames!=2||commands!=dones||cpu_result_reads<64||!npu_idle)$fatal(1,"CPU_B03 final retirement");
                    $display("CPU_B03_PASS frames=2 ops=%0d preflights=%0d reads=%0d commands=%0d dones=%0d nativeAW=%0d nativeAR=%0d nativeW=%0d nativeR=%0d cycles=%0d",model_ops,preflights,cpu_result_reads,commands,dones,aw_count,ar_count,w_count,r_count,cycles);
                    $finish;
                end else $fatal(1,"CPU_B03 firmware reported %h pc=%h",saved_w,u_system.u_cpu.inst_addr);
            end
        end
    end
    `undef FRAME
endmodule
`default_nettype wire
