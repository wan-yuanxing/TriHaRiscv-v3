`timescale 1ns/1ps
`include "video_display.vh"
module tb_display_shadow_bytes;
    reg clk_i=0,rst_ni=0;
    always #4 clk_i=~clk_i;
    reg [31:0] awaddr=0,wdata=0,araddr=0;
    reg [3:0] wstrb=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    integer writes=0,reads=0,i,j,b;
    reg [31:0] expected[0:159];reg [31:0] pattern;
    video_display_mmio #(.EXTERNAL_HEALTH(1)) u_dut(
        .clk_i(clk_i),.rst_ni(rst_ni),
        .s_axi_awaddr_i(awaddr),.s_axi_awprot_i(3'd0),.s_axi_awvalid_i(awvalid),.s_axi_awready_o(awready),
        .s_axi_wdata_i(wdata),.s_axi_wstrb_i(wstrb),.s_axi_wvalid_i(wvalid),.s_axi_wready_o(wready),
        .s_axi_bresp_o(bresp),.s_axi_bvalid_o(bvalid),.s_axi_bready_i(bready),
        .s_axi_araddr_i(araddr),.s_axi_arprot_i(3'd0),.s_axi_arvalid_i(arvalid),.s_axi_arready_o(arready),
        .s_axi_rdata_o(rdata),.s_axi_rresp_o(rresp),.s_axi_rvalid_o(rvalid),.s_axi_rready_i(rready),
        .modes_i(3'b111),.asset_ready_i(1'b0),.asset_id_i(32'd0),.asset_generation_i(32'd0),
        .cmd_ready_i(1'b0),.feedback_valid_i(1'b0),.feedback_slot_i(2'd0),.feedback_mode_i(2'd0),
        .feedback_frame_i(32'd0),.feedback_generation_i(32'd0),.feedback_seq_i(32'd0),
        .retire_valid_i(1'b0),.retire_slot_i(2'd0),.retire_frame_i(32'd0),.retire_generation_i(32'd0),
        .submit_enable_i(1'b1),.external_fault_i(1'b0));
    task automatic read_word(input [31:0] address,value);
        begin
            @(negedge clk_i);araddr=address;arvalid=1;
            @(posedge clk_i);while(!arready)@(posedge clk_i);
            @(negedge clk_i);arvalid=0;
            while(!rvalid)@(negedge clk_i);
            repeat(2) begin
                if(rdata!==value||rresp!==0||!rvalid)$fatal(1,"shadow read mismatch %h expected %h got %h",address,value,rdata);
                @(negedge clk_i);
            end
            rready=1;@(negedge clk_i);rready=0;reads=reads+1;
        end
    endtask
    task automatic send_aw(input [31:0] address,input integer delay_cycles);
        begin
            repeat(delay_cycles)@(negedge clk_i);
            @(negedge clk_i);awaddr=address;awvalid=1;
            @(posedge clk_i);while(!awready)@(posedge clk_i);
            @(negedge clk_i);awvalid=0;
        end
    endtask
    task automatic send_w(input [31:0] value,input [3:0] strobes,input integer delay_cycles);
        begin
            repeat(delay_cycles)@(negedge clk_i);
            @(negedge clk_i);wdata=value;wstrb=strobes;wvalid=1;
            @(posedge clk_i);while(!wready)@(posedge clk_i);
            @(negedge clk_i);wvalid=0;
        end
    endtask
    task automatic write_word(input [31:0] address,value,input [3:0] strobes,
                               input integer order,input [1:0] response,input [31:0] check_address,check_value);
        begin
            fork send_aw(address,order==2?2:0);send_w(value,strobes,order==1?2:0);join
            while(!bvalid)@(negedge clk_i);
            repeat(3) begin
                if(!bvalid||bresp!==response)$fatal(1,"shadow B response mismatch");
                @(negedge clk_i);
            end
            // The write is already visible while B is backpressured.
            read_word(check_address,check_value);
            if(!bvalid||bresp!==response)$fatal(1,"shadow B response not held during read");
            bready=1;@(negedge clk_i);bready=0;writes=writes+1;
        end
    endtask
    initial begin
        #101;rst_ni=1;
        for(i=0;i<160;i=i+1) begin
            expected[i]=32'ha5963c69^(i*32'h01030507);
            write_word(`VDISP_BASE+`VDISP_SHADOW_OFFSET+4*i,expected[i],15,i%3,0,
                       `VDISP_BASE+`VDISP_SHADOW_OFFSET+4*i,expected[i]);
            for(j=0;j<16;j=j+1) begin
                pattern=32'hf05aa50f^(i*32'h0307010b)^(j*32'h10204081);
                for(b=0;b<4;b=b+1)if((j>>b)&1)expected[i][8*b+:8]=pattern[8*b+:8];
                write_word(`VDISP_BASE+`VDISP_SHADOW_OFFSET+4*i,pattern,j,(i+j)%3,0,
                           `VDISP_BASE+`VDISP_SHADOW_OFFSET+4*i,expected[i]);
            end
        end
        write_word(`VDISP_BASE+`VDISP_SHADOW_OFFSET+1,32'hffffffff,15,0,3,
                   `VDISP_BASE+`VDISP_SHADOW_OFFSET,expected[0]);
        write_word(`VDISP_BASE+`VDISP_SHADOW_OFFSET+`VDISP_RECORD_BYTES,32'hffffffff,15,1,3,
                   `VDISP_BASE+`VDISP_SHADOW_OFFSET,expected[0]);
        write_word(`VDISP_BASE+`VDISP_SHADOW_OFFSET,32'hxxxxxxxx,0,2,2,
                   `VDISP_BASE+`VDISP_SHADOW_OFFSET,expected[0]);
        @(negedge clk_i);rst_ni=0;#101;rst_ni=1;
        for(i=0;i<160;i=i+1)read_word(`VDISP_BASE+`VDISP_SHADOW_OFFSET+4*i,32'd0);
        $display("DISPLAY_SHADOW_BYTES_PASS writes=%0d reads=%0d",writes,reads);$finish;
    end
    initial begin #2000000;$fatal(1,"shadow byte test timeout");end
endmodule
