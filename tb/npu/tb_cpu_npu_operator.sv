`timescale 1ns/1ps
`default_nettype none
// Digital diagnostic: frozen CPU and actual operator RTL. The local CPU DDR
// read port shares this byte model; it is not a production coherent fabric.
module tb_cpu_npu_operator #(
    parameter integer IRQ_MODE=0, BAD_DATA=0, NO_CONTROL=0
);
    reg clk_i=0, rst_ni=0;
    always #5 clk_i=~clk_i;
    integer cycles=0;
    logic [31:0] s_axi_awaddr_i;
    logic s_axi_awvalid_i;
    logic s_axi_awready_o;
    logic [31:0] s_axi_wdata_i;
    logic [3:0] s_axi_wstrb_i;
    logic s_axi_wvalid_i;
    logic s_axi_wready_o;
    logic [1:0] s_axi_bresp_o;
    logic s_axi_bvalid_o;
    logic s_axi_bready_i;
    logic [31:0] s_axi_araddr_i;
    logic s_axi_arvalid_i;
    logic s_axi_arready_o;
    logic [31:0] s_axi_rdata_o;
    logic [1:0] s_axi_rresp_o;
    logic s_axi_rvalid_o;
    logic s_axi_rready_i;
    logic irq_o;
    logic fault_o;
    logic [3:0] m_axi_arid_o;
    logic [31:0] m_axi_araddr_o;
    logic [7:0] m_axi_arlen_o;
    logic [2:0] m_axi_arsize_o;
    logic [1:0] m_axi_arburst_o;
    logic m_axi_arvalid_o;
    logic m_axi_arready_i;
    logic [3:0] m_axi_rid_i;
    logic [127:0] m_axi_rdata_i;
    logic [1:0] m_axi_rresp_i;
    logic m_axi_rlast_i;
    logic m_axi_rvalid_i;
    logic m_axi_rready_o;
    logic [3:0] m_axi_awid_o;
    logic [31:0] m_axi_awaddr_o;
    logic [7:0] m_axi_awlen_o;
    logic [2:0] m_axi_awsize_o;
    logic [1:0] m_axi_awburst_o;
    logic m_axi_awvalid_o;
    logic m_axi_awready_i;
    logic [127:0] m_axi_wdata_o;
    logic [15:0] m_axi_wstrb_o;
    logic m_axi_wlast_o;
    logic m_axi_wvalid_o;
    logic m_axi_wready_i;
    logic [3:0] m_axi_bid_i;
    logic [1:0] m_axi_bresp_i;
    logic m_axi_bvalid_i;
    logic m_axi_bready_o;
    npu_operator_top u_npu (.*);
    reg [7:0] memory[0:32767], expected[0:32767];
    reg [31:0] config_words[0:31];
    function automatic integer memory_index(input [31:0] addr);
        if(addr>=32'h82800000&&addr<32'h82802000)memory_index=int'(addr-32'h82800000);
        else if(addr>=32'h82b00000&&addr<32'h82b03000)memory_index=8192+int'(addr-32'h82b00000);
        else if(addr>=32'h83300000&&addr<32'h83302000)memory_index=24576+int'(addr-32'h83300000);
        else memory_index=-1;
    endfunction
    reg [31:0] random_q=32'h4e505531;
    reg read_pending=0, aw_pending=0, w_pending=0, write_pending=0;
    reg [31:0] saved_awaddr;
    reg [127:0] saved_wdata, saved_rdata;
    reg [15:0] saved_wstrb;
    integer read_delay=0,write_delay=0, read_transactions=0,write_transactions=0;
    integer write_bytes=0,b_responses=0,starts=0,completions=0,final_b_guard=0;
    integer aw_first=0,w_first=0;
    integer lane, index, idx, amount;
    assign m_axi_arready_i=rst_ni&&!read_pending&&!m_axi_rvalid_i&&random_q[0];
    // Guarantee both independent channel orders even for five-element ties;
    // the remaining transactions retain deterministic pseudorandom stalls.
    assign m_axi_awready_i=rst_ni&&!aw_pending&&!write_pending&&!m_axi_bvalid_i&&random_q[2]&&
        (write_transactions!=1||w_pending);
    assign m_axi_wready_i=rst_ni&&!w_pending&&!write_pending&&!m_axi_bvalid_i&&random_q[4]&&
        (write_transactions!=0||aw_pending);
    assign m_axi_rid_i=4'd0;
    assign m_axi_rresp_i=2'd0;
    assign m_axi_rlast_i=1'b1;
    assign m_axi_bid_i=4'd0;
    assign m_axi_bresp_i=2'd0;
    reg held_ar=0,held_aw=0,held_w=0;
    reg [48:0] ar_saved,aw_saved;
    reg [144:0] w_saved;
    always @(posedge clk_i)begin
        if(!rst_ni)begin m_axi_rvalid_i<=0;m_axi_bvalid_i<=0;end
        else begin
            random_q<={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
            if(held_ar&&(!m_axi_arvalid_o||{m_axi_arid_o,m_axi_araddr_o,m_axi_arlen_o,m_axi_arsize_o,m_axi_arburst_o}!==ar_saved))
                $fatal(1,"CPU_NPU_FAIL AR stability");
            if(held_aw&&(!m_axi_awvalid_o||{m_axi_awid_o,m_axi_awaddr_o,m_axi_awlen_o,m_axi_awsize_o,m_axi_awburst_o}!==aw_saved))
                $fatal(1,"CPU_NPU_FAIL AW stability");
            if(held_w&&(!m_axi_wvalid_o||{m_axi_wdata_o,m_axi_wstrb_o,m_axi_wlast_o}!==w_saved))
                $fatal(1,"CPU_NPU_FAIL W stability");
            held_ar<=m_axi_arvalid_o&&!m_axi_arready_i;
            held_aw<=m_axi_awvalid_o&&!m_axi_awready_i;
            held_w<=m_axi_wvalid_o&&!m_axi_wready_i;
            ar_saved<={m_axi_arid_o,m_axi_araddr_o,m_axi_arlen_o,m_axi_arsize_o,m_axi_arburst_o};
            aw_saved<={m_axi_awid_o,m_axi_awaddr_o,m_axi_awlen_o,m_axi_awsize_o,m_axi_awburst_o};
            w_saved<={m_axi_wdata_o,m_axi_wstrb_o,m_axi_wlast_o};
            if(m_axi_arvalid_o&&m_axi_arready_i)begin
                index=memory_index(m_axi_araddr_o);
                if(index<0||index+15>=32768||m_axi_araddr_o[3:0]!=0||m_axi_arid_o!=0||
                    m_axi_arlen_o!=0||m_axi_arsize_o!=4||m_axi_arburst_o!=1)
                    $fatal(1,"CPU_NPU_FAIL AXI read address %h",m_axi_araddr_o);
                for(lane=0;lane<16;lane=lane+1)saved_rdata[lane*8+:8]<=memory[index+lane];
                read_pending<=1;read_delay<=2+int'(random_q[8:6]);read_transactions<=read_transactions+1;
            end
            if(read_pending)begin
                if(read_delay>0)read_delay<=read_delay-1;
                else begin read_pending<=0;m_axi_rvalid_i<=1;m_axi_rdata_i<=saved_rdata;end
            end
            if(m_axi_rvalid_i&&m_axi_rready_o)m_axi_rvalid_i<=0;
            if(m_axi_awvalid_o&&m_axi_awready_i)begin
                if(m_axi_awaddr_o[3:0]!=0||m_axi_awid_o!=0||m_axi_awlen_o!=0||m_axi_awsize_o!=4||m_axi_awburst_o!=1)
                    $fatal(1,"CPU_NPU_FAIL AXI write geometry");
                saved_awaddr<=m_axi_awaddr_o;aw_pending<=1;
                if(!w_pending&&!(m_axi_wvalid_o&&m_axi_wready_i))aw_first<=aw_first+1;
            end
            if(m_axi_wvalid_o&&m_axi_wready_i)begin
                if(!m_axi_wlast_o||m_axi_wstrb_o==0)$fatal(1,"CPU_NPU_FAIL AXI write data");
                saved_wdata<=m_axi_wdata_o;saved_wstrb<=m_axi_wstrb_o;w_pending<=1;
                if(!aw_pending&&!(m_axi_awvalid_o&&m_axi_awready_i))w_first<=w_first+1;
            end
            if(aw_pending&&w_pending)begin
                index=memory_index(saved_awaddr);amount=0;
                if(index<24576||index+15>=32768)$fatal(1,"CPU_NPU_FAIL non-output write");
                for(lane=0;lane<16;lane=lane+1)if(saved_wstrb[lane])begin
                    idx=index+lane;
                    if(idx>=24576+int'(config_words[19])*(config_words[16]==3?2:1))
                        $fatal(1,"CPU_NPU_FAIL output guard");
                    memory[idx]<=saved_wdata[lane*8+:8]^((BAD_DATA!=0&&idx==24576)?8'h01:8'h00);
                    amount=amount+1;
                end
                write_bytes<=write_bytes+amount;write_transactions<=write_transactions+1;
                aw_pending<=0;w_pending<=0;write_pending<=1;
                // In particular, hold every final B well after the output write.
                write_delay<=((write_transactions+1)%int'(config_words[19])==0)?31:3+int'(random_q[11:9]);
            end
            if(write_pending)begin
                if(write_delay>0)begin
                    write_delay<=write_delay-1;
                    if(write_transactions%int'(config_words[19])==0)final_b_guard<=final_b_guard+1;
                end else begin write_pending<=0;m_axi_bvalid_i<=1;end
            end
            if(m_axi_bvalid_i&&m_axi_bready_o)begin m_axi_bvalid_i<=0;b_responses<=b_responses+1;end
            if(u_npu.start)starts<=starts+1;
            if(u_npu.engine_done)begin
                if(write_pending||m_axi_bvalid_i||aw_pending||w_pending||b_responses!=write_transactions)
                    $fatal(1,"CPU_NPU_FAIL completion before B");
                if(u_npu.engine_error||fault_o)$fatal(1,"CPU_NPU_FAIL operator error %0d",u_npu.engine_error_code);
                completions<=completions+1;
            end
        end
    end
    reg [7:0] rom[0:8191],sram[0:32767];
    string image_path,signature_path,memory_path,expected_path,config_path,output_path;
    integer fd,image_size,local_lane,native_requests=0,native_responses=0;
    integer output_reads=0,ifetch_stalls=0,data_stalls=0;
    reg bus_pending=0,local_pending=0,local_ack=0;
    reg [31:0] local_data=0,saved_local_data=0;
    reg [10:0] local_tag=0,saved_local_tag=0,expected_native_tag=0;
    integer local_delay=0,fetch_delay=0;
    reg fetch_pending=0,fetch_valid=0;
    reg [63:0] fetch_data=0,saved_fetch_data=0;
    wire [31:0] d_addr,d_wdata,i_pc;
    wire [10:0] request_tag;
    wire d_rd,i_rd,d_cacheable,d_invalidate,d_writeback,d_flush;
    wire [3:0] d_wr;
    wire rom_select=d_addr<8192;
    wire sram_select=d_addr>=32'h10000&&d_addr<32'h18000;
    wire ddr_select=d_addr>=32'h83300000&&d_addr<32'h83302000;
    wire memory_select=rom_select||sram_select||ddr_select;
    wire native_request_enable=!bus_pending&&!memory_select&&(NO_CONTROL==0);
    wire native_accept,native_ack,native_error;
    wire [31:0] native_rdata;
    wire [10:0] native_tag;
    wire d_accept=rst_ni&&!bus_pending&&(memory_select?(cycles%4!=0):(NO_CONTROL==0&&native_accept));
    wire d_ack=local_ack||native_ack;
    wire [31:0] d_data=local_ack?local_data:native_rdata;
    wire [10:0] d_tag=local_ack?local_tag:native_tag;
    wire i_accept=rst_ni&&!fetch_pending&&(cycles%3!=0);
    wire [2:0] ignored_awprot,ignored_arprot;
    cpu_native_axil #(.MMIO_PREFIX(16'h2000)) u_adapter(
        .clk_i(clk_i),.rst_ni(rst_ni),.cpu_addr_i(d_addr),.cpu_wdata_i(d_wdata),
        .cpu_re_i(d_rd&&native_request_enable),.cpu_wstrb_i(d_wr&{4{native_request_enable}}),
        .cpu_cacheable_i(d_cacheable),.cpu_req_tag_i(request_tag),
        .cpu_invalidate_i(d_invalidate&&native_request_enable),
        .cpu_writeback_i(d_writeback&&native_request_enable),.cpu_flush_i(d_flush&&native_request_enable),
        .cpu_rdata_o(native_rdata),.cpu_accept_o(native_accept),.cpu_ack_o(native_ack),
        .cpu_error_o(native_error),.cpu_resp_tag_o(native_tag),
        .m_axi_awaddr_o(s_axi_awaddr_i),.m_axi_awprot_o(ignored_awprot),
        .m_axi_awvalid_o(s_axi_awvalid_i),.m_axi_awready_i(s_axi_awready_o),
        .m_axi_wdata_o(s_axi_wdata_i),.m_axi_wstrb_o(s_axi_wstrb_i),
        .m_axi_wvalid_o(s_axi_wvalid_i),.m_axi_wready_i(s_axi_wready_o),
        .m_axi_bresp_i(s_axi_bresp_o),.m_axi_bvalid_i(s_axi_bvalid_o),.m_axi_bready_o(s_axi_bready_i),
        .m_axi_araddr_o(s_axi_araddr_i),.m_axi_arprot_o(ignored_arprot),
        .m_axi_arvalid_o(s_axi_arvalid_i),.m_axi_arready_i(s_axi_arready_o),
        .m_axi_rdata_i(s_axi_rdata_o),.m_axi_rresp_i(s_axi_rresp_o),
        .m_axi_rvalid_i(s_axi_rvalid_o),.m_axi_rready_o(s_axi_rready_i));
    triha_cpu #(.SUPPORT_DUAL_ISSUE(0),.SUPPORT_BRANCH_PREDICTION(1),
        .SUPPORT_MULDIV(0),.SUPPORT_SUPER(0),.SUPPORT_MMU(0),
        .SUPPORT_REGFILE_XILINX(0),.SUPPORT_LOAD_BYPASS(1),.SUPPORT_MUL_BYPASS(1)) u_cpu(
        .clk_i(clk_i),.rst_i(!rst_ni),.intr_i(irq_o),.reset_vector_i(32'd0),.cpu_id_i(32'd0),
        .mem_i_accept_i(i_accept),.mem_i_valid_i(fetch_valid),.mem_i_error_i(1'b0),.mem_i_inst_i(fetch_data),
        .mem_i_rd_o(i_rd),.mem_i_pc_o(i_pc),.mem_i_flush_o(),.mem_i_invalidate_o(),
        .mem_d_accept_i(d_accept),.mem_d_ack_i(d_ack),.mem_d_error_i(native_error&&!local_ack),
        .mem_d_data_rd_i(d_data),.mem_d_resp_tag_i(d_tag),.mem_d_addr_o(d_addr),
        .mem_d_data_wr_o(d_wdata),.mem_d_rd_o(d_rd),.mem_d_wr_o(d_wr),
        .mem_d_req_tag_o(request_tag),.mem_d_cacheable_o(d_cacheable),
        .mem_d_invalidate_o(d_invalidate),.mem_d_writeback_o(d_writeback),.mem_d_flush_o(d_flush));
    integer irq_rises=0,irq_falls=0;
    reg previous_irq=0,w1c_seen=0;
    always @(posedge clk_i) if(rst_ni)begin
        cycles<=cycles+1;local_ack<=0;fetch_valid<=0;
        if(i_rd&&!i_accept)ifetch_stalls<=ifetch_stalls+1;
        if((d_rd||(|d_wr))&&!d_accept)data_stalls<=data_stalls+1;
        if(i_rd&&i_accept)begin
            if(i_pc>=8192||i_pc[2:0]!=0)$fatal(1,"CPU_NPU_FAIL fetch address %h",i_pc);
            fetch_pending<=1;fetch_delay<=cycles%3;
            for(local_lane=0;local_lane<8;local_lane=local_lane+1)saved_fetch_data[local_lane*8+:8]<=rom[i_pc+local_lane];
        end else if(fetch_pending)begin
            if(fetch_delay==0)begin fetch_pending<=0;fetch_valid<=1;fetch_data<=saved_fetch_data;end
            else fetch_delay<=fetch_delay-1;
        end
        if((d_rd||(|d_wr))&&d_accept)begin
            bus_pending<=1;
            // Native LSU marks its DDR window cacheable. This fixture has no
            // data cache: its documented local DDR port reads the byte model.
            if(d_addr[1:0]!=0||d_cacheable!==ddr_select||d_invalidate||d_writeback||d_flush)
                $fatal(1,"CPU_NPU_FAIL native controls");
            if(memory_select)begin
                local_pending<=1;local_delay<=cycles%4;saved_local_tag<=request_tag;
                if(ddr_select)begin
                    if(|d_wr||completions<1)$fatal(1,"CPU_NPU_FAIL CPU DDR write/read before completion");
                    output_reads<=output_reads+1;
                end
                for(local_lane=0;local_lane<4;local_lane=local_lane+1)begin
                    if(rom_select)saved_local_data[local_lane*8+:8]<=rom[d_addr+local_lane];
                    else if(sram_select)saved_local_data[local_lane*8+:8]<=sram[d_addr-32'h10000+local_lane];
                    else saved_local_data[local_lane*8+:8]<=memory[memory_index(d_addr)+local_lane];
                    if(d_wr[local_lane])begin
                        if(!sram_select)$fatal(1,"CPU_NPU_FAIL CPU write outside SRAM");
                        sram[d_addr-32'h10000+local_lane]<=d_wdata[local_lane*8+:8];
                    end
                end
            end else begin native_requests<=native_requests+1;expected_native_tag<=request_tag;end
        end else if(local_pending)begin
            if(local_delay==0)begin local_pending<=0;local_ack<=1;local_data<=saved_local_data;local_tag<=saved_local_tag;end
            else local_delay<=local_delay-1;
        end
        if(d_ack)begin
            if(!bus_pending)$fatal(1,"CPU_NPU_FAIL unsolicited ACK");
            bus_pending<=0;
        end
        if(native_ack)begin
            if(native_tag!==expected_native_tag||native_error)$fatal(1,"CPU_NPU_FAIL native response");
            native_responses<=native_responses+1;
        end
        if(s_axi_wvalid_i&&s_axi_wready_o&&s_axi_awaddr_i==32'h20000010&&s_axi_wdata_i!=0)w1c_seen<=1;
        if(irq_o&&!previous_irq)begin irq_rises<=irq_rises+1;w1c_seen<=0;end
        if(!irq_o&&previous_irq)begin
            if(!w1c_seen)$fatal(1,"CPU_NPU_FAIL IRQ without W1C");
            irq_falls<=irq_falls+1;
        end
        previous_irq<=irq_o;
    end
    function automatic [31:0] signature_word(input integer word_index);
        signature_word={sram[word_index*4+3],sram[word_index*4+2],sram[word_index*4+1],sram[word_index*4]};
    endfunction
    integer outfd,word_index,mem_index,output_bytes;
    reg [31:0] outcome;
    initial begin
        if(!$value$plusargs("ROM_IMAGE=%s",image_path)||!$value$plusargs("SIGNATURE=%s",signature_path)||
            !$value$plusargs("MEMORY=%s",memory_path)||!$value$plusargs("EXPECTED=%s",expected_path)||
            !$value$plusargs("CONFIG=%s",config_path)||!$value$plusargs("OUTPUT=%s",output_path))
            $fatal(1,"CPU_NPU_FAIL input arguments");
        for(mem_index=0;mem_index<8192;mem_index=mem_index+1)rom[mem_index]=0;
        for(mem_index=0;mem_index<32768;mem_index=mem_index+1)sram[mem_index]=0;
        $readmemh(memory_path,memory);$readmemh(expected_path,expected);$readmemh(config_path,config_words);
        output_bytes=int'(config_words[19])*(config_words[16]==3?2:1);
        if(output_bytes<1||output_bytes>8192)$fatal(1,"CPU_NPU_FAIL vector size");
        fd=$fopen(image_path,"rb");if(!fd)$fatal(1,"CPU_NPU_FAIL ROM open");
        image_size=$fread(rom,fd);$fclose(fd);
        if(image_size!=8192)$fatal(1,"CPU_NPU_FAIL ROM size");
        repeat(8)@(negedge clk_i);rst_ni=1;
    end
    always @(negedge clk_i) if(rst_ni)begin
        outcome=signature_word(0);
        if(outcome[31:20]==12'hbad)$fatal(1,"CPU_NPU_FAIL firmware signature %h stage%0d index%0d actual%h expected%h cause%h",outcome,signature_word(1),signature_word(13),signature_word(14),signature_word(15),signature_word(10));
        if(cycles>(NO_CONTROL!=0?20000:2000000))$fatal(1,"CPU_NPU_FAIL timeout pc%h stage%0d",i_pc,signature_word(1));
        if(outcome==32'h4350554e&&!bus_pending&&!d_ack)begin
            if(signature_word(1)!=4||signature_word(2)!=2||signature_word(4)!=2*output_bytes||
                output_reads!=2*output_bytes||native_requests!=native_responses||native_requests<40||
                ifetch_stalls==0||data_stalls==0||starts!=2||completions!=2||
                b_responses!=write_transactions||write_transactions!=2*int'(config_words[19])||
                write_bytes!=2*output_bytes||read_transactions==0||aw_first==0||w_first==0||final_b_guard<62)
                $fatal(1,"CPU_NPU_FAIL coverage req%0d rsp%0d output_reads%0d starts%0d done%0d AWfirst%0d Wfirst%0d",native_requests,native_responses,output_reads,starts,completions,aw_first,w_first);
            if(irq_o||irq_rises!=(IRQ_MODE!=0?2:0)||irq_falls!=(IRQ_MODE!=0?2:0)||
                signature_word(3)!=(IRQ_MODE!=0?2:0)||(IRQ_MODE!=0&&u_cpu.u_csr.u_csrfile.csr_mip_q[11]))
                $fatal(1,"CPU_NPU_FAIL real CPU IRQ coverage");
            for(mem_index=0;mem_index<32768;mem_index=mem_index+1)
                if(memory[mem_index]!==expected[mem_index])$fatal(1,"CPU_NPU_FAIL oracle memory %0d",mem_index);
            outfd=$fopen(output_path,"w");if(!outfd)$fatal(1,"CPU_NPU_FAIL output open");
            for(mem_index=0;mem_index<output_bytes;mem_index=mem_index+1)$fdisplay(outfd,"%02h",memory[24576+mem_index]);
            $fclose(outfd);
            outfd=$fopen(signature_path,"w");if(!outfd)$fatal(1,"CPU_NPU_FAIL signature open");
            for(word_index=0;word_index<16;word_index=word_index+1)$fdisplay(outfd,"%08h",signature_word(word_index));
            $fclose(outfd);
            $display("CPU_NPU_OPERATOR_PASS irq=%0d tasks=%0d cycles=%0d native=%0d output_reads=%0d dma_reads=%0d dma_writes=%0d AWfirst=%0d Wfirst=%0d final_b_guard=%0d",IRQ_MODE,completions,cycles,native_responses,output_reads,read_transactions,write_transactions,aw_first,w_first,final_b_guard);
            $finish;
        end
    end
endmodule
`default_nettype wire
