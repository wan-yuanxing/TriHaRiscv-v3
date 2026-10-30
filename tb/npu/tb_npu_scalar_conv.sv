`timescale 1ns/1ps
module tb_npu_scalar_conv;
    reg clk_i=0, rst_ni=0, start_i=0;
    always #5 clk_i=~clk_i;
    reg [31:0] cfg[0:31];
    reg [7:0] memory[0:32767], expected[0:32767];
    wire busy_o,done_o,error_o;
    wire [7:0] error_code_o;
    wire [31:0] total_cycles_o,compute_cycles_o,dma_wait_cycles_o;
    wire req_valid,req_write;
    wire [31:0] req_addr;
    wire [127:0] req_wdata;
    wire [15:0] req_wstrb;
    reg req_ready=0,rsp_valid=0,rsp_error=0;
    reg [127:0] rsp_data=0;
    npu_scalar_conv u_dut(
        .clk_i(clk_i),.rst_ni(rst_ni),.start_i(start_i),
        .cfg_input_base_i(cfg[0]),.cfg_weight_base_i(cfg[1]),.cfg_bias_base_i(cfg[2]),
        .cfg_requant_base_i(cfg[3]),.cfg_output_base_i(cfg[4]),
        .cfg_input_width_i(cfg[5][15:0]),.cfg_input_height_i(cfg[6][15:0]),
        .cfg_input_channels_i(cfg[7][15:0]),.cfg_output_channels_i(cfg[8][15:0]),
        .cfg_output_width_i(cfg[9][15:0]),.cfg_output_height_i(cfg[10][15:0]),
        .cfg_kernel_i(cfg[11][1:0]),.cfg_stride_i(cfg[12][1:0]),.cfg_padding_i(cfg[13][1:0]),
        .cfg_depthwise_i(cfg[14][0]),.cfg_input_signed_i(cfg[15][0]),.cfg_output_format_i(cfg[16][1:0]),
        .busy_o(busy_o),.done_o(done_o),.error_o(error_o),.error_code_o(error_code_o),
        .total_cycles_o(total_cycles_o),.compute_cycles_o(compute_cycles_o),.dma_wait_cycles_o(dma_wait_cycles_o),
        .mem_req_valid_o(req_valid),.mem_req_write_o(req_write),.mem_req_addr_o(req_addr),
        .mem_req_wdata_o(req_wdata),.mem_req_wstrb_o(req_wstrb),.mem_req_ready_i(req_ready),
        .mem_rsp_valid_i(rsp_valid),.mem_rsp_rdata_i(rsp_data),.mem_rsp_error_i(rsp_error));
    function automatic integer location(input [31:0] address);
        if(address>=32'h82800000&&address<32'h82802000)location=address-32'h82800000;
        else if(address>=32'h82B00000&&address<32'h82B03000)location=address-32'h82B00000+16'h2000;
        else if(address>=32'h83300000&&address<32'h83302000)location=address-32'h83300000+16'h6000;
        else location=-1;
    endfunction
    integer count=0,writes=0,delay_q=0,base_q=0,task_base=0;
    reg pending=0,write_q=0;
    reg [127:0] data_q;
    reg [15:0] strb_q;
    reg [31:0] rng=32'h12345678;
    integer lane;
    always @(posedge clk_i) begin
        if(!rst_ni)begin pending<=0;req_ready<=0;rsp_valid<=0;rsp_error<=0;count<=0;writes<=0;end
        else begin
            rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            req_ready<=!pending&&rng[2:0]!=0;
            rsp_valid<=0;
            if(req_valid&&req_ready)begin
                if(pending)$fatal(1,"multiple requests");
                if(req_addr[3:0]!=0||location(req_addr)<0)$fatal(1,"bad DMA address %h",req_addr);
                pending<=1;req_ready<=0;count<=count+1;delay_q<=1+rng[5:3];
                base_q<=location(req_addr);write_q<=req_write;data_q<=req_wdata;strb_q<=req_wstrb;
            end
            if(pending)begin
                if(delay_q!=0)delay_q<=delay_q-1;
                else begin
                    pending<=0;rsp_valid<=1;rsp_error<=(cfg[18]!=0&&count-task_base==cfg[18]);
                    if(!(cfg[18]!=0&&count-task_base==cfg[18]))begin
                        if(write_q)begin
                            writes<=writes+1;
                            for(lane=0;lane<16;lane=lane+1)if(strb_q[lane])memory[base_q+lane]<=data_q[lane*8+:8];
                        end else for(lane=0;lane<16;lane=lane+1)rsp_data[lane*8+:8]<=memory[base_q+lane];
                    end
                end
            end
        end
    end
    string folder,suffix;
    integer version,i,limit,previous_count;
    initial begin
        if(!$value$plusargs("CASE_DIR=%s",folder))$fatal(1,"CASE_DIR missing");
        repeat(4)@(negedge clk_i);rst_ni=1;
        for(version=0;version<2;version=version+1)begin
            suffix=version==0?"":"_next";
            $readmemh({folder,"/config",suffix,".hex"},cfg);
            $readmemh({folder,"/memory",suffix,".hex"},memory);
            $readmemh({folder,"/expected",suffix,".hex"},expected);
            previous_count=count;task_base=count;
            @(negedge clk_i);start_i=1;@(negedge clk_i);start_i=0;
            cfg[0]=0; // Active input pointer must already be latched.
            limit=0;
            while(!done_o&&limit<2000000)begin @(negedge clk_i);limit=limit+1;end
            if(!done_o)$fatal(1,"scalar timeout");
            if(error_o!==(cfg[17]!=0)||error_code_o!==cfg[17][7:0])$fatal(1,"wrong error got=%0d expected=%0d",error_code_o,cfg[17]);
            if(busy_o||pending)$fatal(1,"early completion");
            if(cfg[20]&&count!=previous_count)$fatal(1,"invalid config issued DMA");
            for(i=0;i<32768;i=i+1)if(memory[i]!==expected[i])$fatal(1,"byte mismatch %h got%h expected%h",i,memory[i],expected[i]);
            if(cfg[17]==0&&(compute_cycles_o==0||total_cycles_o==0||dma_wait_cycles_o==0))$fatal(1,"missing counters");
            repeat(3)@(negedge clk_i);
        end
        $display("NPU_SCALAR_PASS requests=%0d writes=%0d",count,writes);$finish;
    end
endmodule
