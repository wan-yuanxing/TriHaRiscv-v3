`timescale 1ns/1ps
`include "frame_config.vh"
module tb_npu_frame_layout_admission;
    localparam integer CPU_POST=1;
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
    integer slot,field,bit_index,cases=0;
    reg [31:0] field_id;
    reg [1023:0] accepted;
    initial begin #10000000;$fatal(1,"LAYOUT_ADMISSION timeout");end
    initial begin
      for(slot=0;slot<3;slot=slot+1)begin
        @(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
        for(i=0;i<32;i=i+1)words[i]=0;
        words[0]=32'h33444d42;words[1]=1;words[2]=128;words[3]=1;
        words[4]=`B03_PROGRAM_BASE-(`SOC_DDR_BASE+`SOC_WINDOW_BASE);words[5]=`B03_PROGRAM_BYTES;
        words[6]=`B03_WORKSPACE_BASE-(`SOC_DDR_BASE+`SOC_WINDOW_BASE);words[7]=`B03_WORKSPACE_BYTES;
        words[8]=(`B03_INPUT_BASES_0+slot*`B03_INPUT_SLOT_BYTES)-(`SOC_DDR_BASE+`SOC_WINDOW_BASE);words[9]=`B03_INPUT_BYTES;
        words[10]=(`B03_OUTPUT_BASES_0+slot*`B03_OUTPUT_SLOT_BYTES+`B03_RESULT_OFFSET)-(`SOC_DDR_BASE+`SOC_WINDOW_BASE);words[11]=`B03_RESULT_BYTES;
        words[12]=`B03_POST_TABLE_BASE-(`SOC_DDR_BASE+`SOC_WINDOW_BASE);words[13]=`B03_POST_TABLE_BYTES;
        words[14]=9;words[15]=11;words[17]=7;words[18]=1;
        words[19]=`B03_SOURCE_WIDTH;words[20]=`B03_SOURCE_HEIGHT;words[21]=`B03_RESIZED_WIDTH;words[22]=`B03_RESIZED_HEIGHT;
        words[23]=`B03_PAD_LEFT;words[24]=`B03_PAD_TOP;words[25]=`B03_CAPACITY;
        words[28]=(`B03_OUTPUT_BASES_0+slot*`B03_OUTPUT_SLOT_BYTES+`B03_HEADS_OFFSET)-(`SOC_DDR_BASE+`SOC_WINDOW_BASE);
        words[29]=1;words[30]=`B03_WATCHDOG_CYCLES;
        for(i=0;i<32;i=i+1)write_reg(`NF_TASK_BASE+4*i,words[i],15,i%2,0);
        for(field=0;field<11;field=field+1)begin
          field_id=field<10?field+4:28;
          for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin
            write_reg(`NF_TASK_BASE+4*field_id,words[field_id]^(32'd1<<bit_index),15,bit_index%2,0);
            write_reg(`NF_REG_CONTROL,1,15,0,2);
            check(!start_valid,"mutated layout rejected before engine");
            write_reg(`NF_TASK_BASE+4*field_id,words[field_id],15,0,0);cases=cases+1;
          end
        end
        write_reg(`NF_REG_CONTROL,1,15,0,0);check(start_valid,"valid slot accepted");accepted=task_words;
        for(i=0;i<32;i=i+1)begin
          check(task_words[32*i+:32]===words[i],"exact admitted task snapshot");
          write_reg(`NF_TASK_BASE+4*i,~words[i],15,i%2,2);
          check(task_words===accepted&&start_valid,"held task immutable");
        end
      end
      $display("LAYOUT_ADMISSION_PASS cases=%0d slots=3",cases);$finish;
    end
endmodule
