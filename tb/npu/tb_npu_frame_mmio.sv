`timescale 1ns/1ps
`include "frame_config.vh"
module tb_npu_frame_mmio #(parameter integer CPU_POST=0);
    reg clk=0; always #5 clk=~clk;
    reg rst=0;
    reg [31:0] awaddr=0,wdata=0,araddr=0;
    reg [3:0] wstrb=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    reg healthy=1, engine_ready=0,done_valid=0,done_live=1,done_publish=0;
    reg [31:0] epoch=7,done_cmd=9,done_epoch=7,done_status=0;
    reg [63:0] done_frame=11;
    reg [11:0] done_faces=CPU_POST?0:2;
    reg [31:0] done_offset=CPU_POST?32'h00900000:32'h00908000;
    reg [31:0] done_bytes=CPU_POST?26368:192,done_crc=CPU_POST?0:32'h12345678;
    wire start_valid,done_ready,irq,fault;
    wire [1023:0] task_words;
    integer checks=0,starts=0,i,bad_case;
    reg [31:0] words[0:31];
    npu_frame_mmio #(.ENABLE_HARDWARE_POST(!CPU_POST)) dut(
        .clk_i(clk),.rst_ni(rst),.s_axi_awaddr_i(awaddr),.s_axi_awvalid_i(awvalid),.s_axi_awready_o(awready),
        .s_axi_wdata_i(wdata),.s_axi_wstrb_i(wstrb),.s_axi_wvalid_i(wvalid),.s_axi_wready_o(wready),
        .s_axi_bresp_o(bresp),.s_axi_bvalid_o(bvalid),.s_axi_bready_i(bready),
        .s_axi_araddr_i(araddr),.s_axi_arvalid_i(arvalid),.s_axi_arready_o(arready),
        .s_axi_rdata_o(rdata),.s_axi_rresp_o(rresp),.s_axi_rvalid_o(rvalid),.s_axi_rready_i(rready),
        .platform_healthy_i(healthy),.session_epoch_i(epoch),.addr_version_i(32'd1),
        .start_valid_o(start_valid),.start_ready_i(engine_ready),.task_words_o(task_words),
        .done_valid_i(done_valid),.done_ready_o(done_ready),.done_status_i(done_status),.done_detail_i(32'd0),
        .done_cmd_i(done_cmd),.done_epoch_i(done_epoch),.done_frame_i(done_frame),.done_faces_i(done_faces),
        .done_result_offset_i(done_offset),.done_result_bytes_i(done_bytes),.done_crc_i(done_crc),
        .done_total_cycles_i(64'h100000005),.done_model_cycles_i(64'd4),.done_post_cycles_i(64'd1),
        .done_live_i(done_live),.done_publish_i(done_publish),.irq_o(irq),.fault_o(fault));
    always @(posedge clk) if(start_valid&&engine_ready) starts<=starts+1;
    task check(input bit condition,input [255:0] label_text);
        begin checks=checks+1; if(!condition) $fatal(1,"CHECK %s",label_text); end
    endtask
    task write_reg(input [31:0] offset,input [31:0] data,input [3:0] strobe,input integer order,input [1:0] response);
        reg [1:0] saved; integer n;
        begin
            @(negedge clk); awaddr=`NF_BASE+offset;wdata=data;wstrb=strobe;
            if(order==1) begin wvalid=1;do @(posedge clk);while(!wready);@(negedge clk);wvalid=0;repeat(2)@(negedge clk);end
            awvalid=1;do @(posedge clk);while(!awready);@(negedge clk);awvalid=0;
            if(order!=1) begin repeat(2)@(negedge clk);wvalid=1;do @(posedge clk);while(!wready);@(negedge clk);wvalid=0;end
            wait(bvalid); #1;saved=bresp;check(saved===response,"B response");
            for(n=0;n<3;n=n+1)begin @(posedge clk);#1;check(bvalid&&bresp===saved,"B stable under backpressure");end
            @(negedge clk);bready=1;@(negedge clk);bready=0;
        end
    endtask
    task read_reg(input [31:0] offset,input [31:0] expected,input [1:0] response);
        integer n;reg [31:0] saved;
        begin
            @(negedge clk);araddr=`NF_BASE+offset;arvalid=1;do @(posedge clk);while(!arready);
            @(negedge clk);arvalid=0;wait(rvalid);#1;saved=rdata;
            if(rresp!==response||rdata!==expected)$display("READ offset=%x actual=%x expected=%x resp=%x",offset,rdata,expected,rresp);
            check(rresp===response&&rdata===expected,"R data/response");
            for(n=0;n<3;n=n+1)begin @(posedge clk);#1;check(rvalid&&rdata===saved,"R stable under backpressure");end
            @(negedge clk);rready=1;@(negedge clk);rready=0;
        end
    endtask
    initial begin
        #200000; $fatal(1,"TIMEOUT frame MMIO");
    end
    initial begin
        repeat(3)@(negedge clk);rst=1;
        for(i=0;i<32;i=i+1)words[i]=0;
        words[0]=32'h33444d42;words[1]=1;words[2]=128;words[3]=1;
        words[4]=32'h00b00000;words[5]=10240;words[6]=32'h01300000;words[7]=4876544;
        words[8]=32'h00800000;words[9]=307200;words[10]=32'h00908000;words[11]=67328;
        words[12]=32'h00b10000;words[13]=1572864;words[14]=9;words[15]=11;words[17]=7;words[18]=1;
        words[19]=800;words[20]=600;words[21]=320;words[22]=240;words[24]=40;words[25]=2100;
        words[26]=32'h1e48284c;words[27]=32'h45016037;words[28]=32'h00900000;words[29]=1;words[30]=100000000;
        read_reg(`NF_REG_ID_VERSION,`NF_ID_VERSION,0);
        write_reg(`NF_REG_CONTROL,1,15,0,2); // incomplete task
        for(i=0;i<32;i=i+1)write_reg(`NF_TASK_BASE+4*i,words[i],15,i%2,0);
        // WSTRB merge, then restore; zero strobe is a no-op.
        write_reg(`NF_TASK_BASE+56,32'h00001200,2,0,0);
        read_reg(`NF_TASK_BASE+56,32'h00001209,0);
        write_reg(`NF_TASK_BASE+56,9,15,0,0);
        write_reg(`NF_TASK_BASE+56,123,0,1,0);
        write_reg(`NF_REG_IRQ_ENABLE,3,15,1,0);
        write_reg(`NF_REG_CONTROL,1,1,0,2);
        write_reg(`NF_REG_CONTROL,1,15,0,0);
        check(start_valid&&starts==0,"START held until core ready");
        write_reg(`NF_TASK_BASE+56,22,15,1,2);
        check(task_words[14*32+:32]==9,"snapshot immutable");
        write_reg(`NF_REG_CONTROL,1,15,0,2);
        @(negedge clk);engine_ready=1;@(negedge clk);engine_ready=0;
        check(starts==1&&!start_valid,"one accepted START");
        @(negedge clk);done_valid=1;wait(done_ready);@(negedge clk);done_valid=0;
        read_reg(`NF_REG_STATUS,`NF_STATUS_HELD,0);
        read_reg(`NF_COMPLETION_BASE+4*`NF_DONE_FRAME_ID_LO,11,0);
        read_reg(`NF_COMPLETION_BASE+4*`NF_DONE_TOTAL_HI,1,0);
        read_reg(`NF_COMPLETION_BASE+4*`NF_DONE_PUBLISHED,0,0);
        check(irq,"done sticky interrupt");
        write_reg(`NF_REG_IRQ_STATUS,3,15,0,0);
        check(!irq,"W1C clears IRQ only");
        write_reg(`NF_REG_CONTROL,1,15,1,2);
        write_reg(`NF_REG_ACK_CMD,9,15,0,0);write_reg(`NF_REG_ACK_FRAME,10,15,0,0);write_reg(`NF_REG_ACK_EPOCH,7,15,0,0);
        write_reg(`NF_REG_ACK,1,15,1,2);
        write_reg(`NF_REG_ACK_FRAME,11,15,0,0);write_reg(`NF_REG_ACK,1,15,1,0);
        read_reg(`NF_REG_STATUS,`NF_STATUS_IDLE,0);
        // Exhausted identity and another frame's output range fail before core starts.
        write_reg(`NF_TASK_BASE+60,32'hffffffff,15,0,0);write_reg(`NF_REG_CONTROL,1,15,0,2);
        write_reg(`NF_TASK_BASE+60,11,15,0,0);
        write_reg(`NF_TASK_BASE+40,32'h00948000,15,0,0);write_reg(`NF_REG_CONTROL,1,15,0,2);
        write_reg(`NF_TASK_BASE+40,32'h00908000,15,0,0);
        write_reg(3,0,15,0,3); read_reg(4096,0,3);
        // A simultaneous W1C cannot discard a newly completed frame.
        write_reg(`NF_REG_CONTROL,1,15,0,0);
        @(negedge clk);engine_ready=1;@(negedge clk);engine_ready=0;done_publish=1;
        fork
            write_reg(`NF_REG_IRQ_STATUS,3,15,0,0);
            begin
                wait(dut.write_execute);done_valid=1;
                @(posedge clk);@(negedge clk);done_valid=0;
            end
        join
        read_reg(`NF_REG_IRQ_STATUS,1,0);
        read_reg(`NF_COMPLETION_BASE+4*`NF_DONE_PUBLISHED,1,0);
        // Session loss invalidates an unacknowledged result and cannot release its slot.
        @(negedge clk);healthy=0;@(negedge clk);healthy=1;
        check(fault,"held completion invalidated");
        read_reg(`NF_COMPLETION_BASE+4*`NF_DONE_PUBLISHED,0,0);
        write_reg(`NF_REG_ACK,1,15,0,0);
        write_reg(`NF_REG_CONTROL,1,15,0,2);
        @(negedge clk);rst=0;@(negedge clk);rst=1;
        for(i=0;i<32;i=i+1)write_reg(`NF_TASK_BASE+4*i,words[i],15,i%2,0);
        // A stale completion cannot publish and locks the endpoint for coordinated recovery.
        write_reg(`NF_REG_CONTROL,1,15,0,0);
        @(negedge clk);engine_ready=1;@(negedge clk);engine_ready=0;done_epoch=6;done_publish=1;done_valid=1;
        wait(done_ready);@(negedge clk);done_valid=0;
        check(fault,"stale completion faults");
        read_reg(`NF_COMPLETION_BASE+4*`NF_DONE_PUBLISHED,0,0);
        read_reg(`NF_REG_STATUS,`NF_STATUS_HELD|`NF_STATUS_FAULT,0);
        // Wrong slot, length, face count and opposite-profile result formats
        // must never become a published completion in either configuration.
        for(bad_case=0;bad_case<4;bad_case=bad_case+1)begin
            @(negedge clk);rst=0;done_epoch=7;
            done_faces=CPU_POST?0:2;done_offset=CPU_POST?32'h00900000:32'h00908000;
            done_bytes=CPU_POST?26368:192;done_crc=CPU_POST?0:32'h12345678;
            @(negedge clk);rst=1;
            for(i=0;i<32;i=i+1)write_reg(`NF_TASK_BASE+4*i,words[i],15,i%2,0);
            write_reg(`NF_REG_CONTROL,1,15,0,0);
            @(negedge clk);engine_ready=1;@(negedge clk);engine_ready=0;
            case(bad_case)
              0:done_offset=done_offset+32'h40000;
              1:done_bytes=done_bytes-32;
              2:done_faces=done_faces+1;
              3:begin done_faces=CPU_POST?2:0;done_offset=CPU_POST?32'h00908000:32'h00900000;
                      done_bytes=CPU_POST?192:26368;done_crc=CPU_POST?32'h12345678:0;end
            endcase
            done_valid=1;wait(done_ready);@(negedge clk);done_valid=0;
            check(fault,"malformed completion faults");
            read_reg(`NF_COMPLETION_BASE+4*`NF_DONE_PUBLISHED,0,0);
        end
        $display("PASS NPU_FRAME_MMIO checks=%0d starts=%0d",checks,starts);$finish;
    end
endmodule
