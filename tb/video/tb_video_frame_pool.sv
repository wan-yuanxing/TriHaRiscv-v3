`timescale 1ns/1ps
`default_nettype none
// Replay actual native C I/O against the production display endpoint. Literal
// offsets and recorded read values are independent of the DUT register decode.
module tb_video_frame_pool;
    reg clk_i=0,rst_ni=0;
    always #4 clk_i=~clk_i;
    reg [31:0] s_axi_awaddr_i=0,s_axi_wdata_i=0,s_axi_araddr_i=0;
    reg [2:0] s_axi_awprot_i=0,s_axi_arprot_i=0;
    reg [3:0] s_axi_wstrb_i=15;
    reg s_axi_awvalid_i=0,s_axi_wvalid_i=0,s_axi_bready_i=0;
    reg s_axi_arvalid_i=0,s_axi_rready_i=0;
    wire s_axi_awready_o,s_axi_wready_o,s_axi_bvalid_o,s_axi_arready_o,s_axi_rvalid_o;
    wire [1:0] s_axi_bresp_o,s_axi_rresp_o;
    wire [31:0] s_axi_rdata_o;
    reg [2:0] modes_i=7;
    reg asset_ready_i=1;
    reg [31:0] asset_id_i=1,asset_generation_i=7;
    wire cmd_valid_o,cmd_mode_only_o;
    reg cmd_ready_i=0;
    wire [1:0] cmd_slot_o,cmd_mode_o;
    wire [31:0] cmd_frame_o,cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o;
    wire [5119:0] cmd_data_o;
    reg feedback_valid_i=0;
    wire feedback_ready_o;
    reg [1:0] feedback_slot_i=0,feedback_mode_i=0;
    reg [31:0] feedback_frame_i=0,feedback_generation_i=0,feedback_seq_i=0;
    reg retire_valid_i=0;
    wire retire_ready_o;
    reg [1:0] retire_slot_i=0;
    reg [31:0] retire_frame_i=0,retire_generation_i=0;
    wire irq_o;
    video_display_mmio dut(.*);
    reg [5119:0] shadow=0;
    reg held=0;
    reg [5284:0] held_payload;
    integer checks=0,reads=0,writes=0,commands=0,retirements=0,rejections=0,fences=0;
    task automatic check(input bit ok,input string label);
        begin
            checks=checks+1;
            if(ok!==1'b1)$fatal(1,"FRAME_POOL_RTL_ASSERT %s",label);
        end
    endtask
    task automatic cycle;
        begin @(posedge clk_i);#1;end
    endtask
    always @(posedge clk_i)begin
        if(!rst_ni)held<=0;
        else begin
            if(held)check(cmd_valid_o&&{cmd_mode_only_o,cmd_slot_o,cmd_mode_o,cmd_frame_o,
                cmd_generation_o,cmd_base_o,cmd_stride_o,cmd_seq_o,cmd_data_o}===held_payload,"HELD_FULL_COMMAND");
            held<=cmd_valid_o&&!cmd_ready_i;
            held_payload<={cmd_mode_only_o,cmd_slot_o,cmd_mode_o,cmd_frame_o,cmd_generation_o,
                cmd_base_o,cmd_stride_o,cmd_seq_o,cmd_data_o};
        end
    end
    task automatic bus_read(input [31:0] offset,output [31:0] value);
        reg [31:0] saved;
        begin
            @(negedge clk_i);s_axi_araddr_i=32'h20011000+offset;s_axi_arvalid_i=1;
            do @(posedge clk_i);while(!s_axi_arready_o);
            @(negedge clk_i);s_axi_arvalid_i=0;
            while(!s_axi_rvalid_o)@(negedge clk_i);
            check(s_axi_rresp_o===0,"READ_RESPONSE");saved=s_axi_rdata_o;
            repeat(2)begin
                @(negedge clk_i);
                check(s_axi_rvalid_o&&s_axi_rresp_o===0&&s_axi_rdata_o===saved,"HELD_R_RESPONSE");
            end
            value=saved;s_axi_rready_i=1;
            @(negedge clk_i);s_axi_rready_i=0;
        end
    endtask
    task automatic bus_write(input [31:0] offset,value,input integer skew);
        begin
            fork
                begin
                    repeat(skew<0?-skew:0)@(negedge clk_i);
                    @(negedge clk_i);s_axi_awaddr_i=32'h20011000+offset;s_axi_awvalid_i=1;
                    do @(posedge clk_i);while(!s_axi_awready_o);
                    @(negedge clk_i);s_axi_awvalid_i=0;
                end
                begin
                    repeat(skew>0?skew:0)@(negedge clk_i);
                    @(negedge clk_i);s_axi_wdata_i=value;s_axi_wvalid_i=1;
                    do @(posedge clk_i);while(!s_axi_wready_o);
                    @(negedge clk_i);s_axi_wvalid_i=0;
                end
            join
            while(!s_axi_bvalid_o)@(negedge clk_i);
            check(s_axi_bresp_o===0,$sformatf("WRITE_RESPONSE offset=%h response=%h",offset,s_axi_bresp_o));
            repeat(2)begin
                @(negedge clk_i);
                check(s_axi_bvalid_o&&s_axi_bresp_o===0&&!s_axi_awready_o&&!s_axi_wready_o,"HELD_B_RESPONSE");
            end
            s_axi_bready_i=1;@(negedge clk_i);s_axi_bready_i=0;
            if(offset>='h100&&offset<'h380)shadow[(offset-'h100)*8+:32]=value;
        end
    endtask
    task automatic accept_commit(input [31:0] slot,frame,gen,mode,seq,only);
        integer waited;
        begin
            waited=0;
            while(!cmd_valid_o)begin cycle;waited=waited+1;check(waited<100,"COMMAND_EVENTUALLY_AVAILABLE");end
            check(cmd_slot_o===slot[1:0]&&cmd_frame_o===frame&&cmd_generation_o===gen&&
                cmd_mode_o===mode[1:0]&&cmd_seq_o===seq&&cmd_mode_only_o===only[0],"COMMAND_IDENTITY");
            check(cmd_data_o===shadow&&cmd_base_o===shadow[160+:32]&&cmd_stride_o===2400,"FULL_RECORD_DECODE");
            repeat(3)cycle;
            @(negedge clk_i);cmd_ready_i=1;cycle;
            @(negedge clk_i);cmd_ready_i=0;
            feedback_slot_i=slot[1:0];feedback_frame_i=frame;feedback_generation_i=gen;
            feedback_mode_i=mode[1:0];feedback_seq_i=seq;feedback_valid_i=1;
            #1;check(feedback_ready_o,"ACTUAL_FEEDBACK_READY");cycle;
            @(negedge clk_i);feedback_valid_i=0;
        end
    endtask
    task automatic retire(input [31:0] slot,frame,gen);
        begin
            @(negedge clk_i);retire_slot_i=slot[1:0];retire_frame_i=frame;retire_generation_i=gen;retire_valid_i=1;
            #1;check(retire_ready_o,"RETIRE_PROOF_READY");cycle;
            @(negedge clk_i);retire_valid_i=0;
        end
    endtask
    task automatic await_rejection(input [31:0] seq,code);
        reg [31:0] events,value;
        integer waited;
        begin
            events=0;waited=0;
            while(!events[2])begin
                bus_read('h14,events);waited=waited+1;check(waited<30,"REJECTION_EVENTUALLY_AVAILABLE");
            end
            check(!cmd_valid_o,"REJECTED_RECORD_HAS_NO_COMMAND");
            bus_read('h68,value);check(value===seq,"REJECT_SEQUENCE");
            bus_read('h6c,value);check(value===code,"REJECT_CODE");
        end
    endtask
    string path;
    // This installed Icarus crashes on case(string), even in a one-line probe.
    // A packed ASCII operation word preserves the trace format and comparison.
    reg [127:0] kind;
    integer file,scanned,ended=0;
    reg [31:0] a,b,c,d,e,f,value;
    initial begin
        check($value$plusargs("TRACE=%s",path),"TRACE_REQUIRED");
        file=$fopen(path,"r");check(file!=0,"OPEN_ACTUAL_NATIVE_TRACE");
        repeat(3)cycle;
        @(negedge clk_i);rst_ni=1;cycle;
        while(!ended&&!$feof(file))begin
            scanned=$fscanf(file,"%s",kind);
            if(scanned==1)case(kind)
                "R":begin
                    scanned=$fscanf(file,"%h %h",a,b);check(scanned==2,"READ_TRACE_FORMAT");
                    bus_read(a,value);check(value===b,$sformatf("ACTUAL_C_READ offset=%h expected=%h actual=%h",a,b,value));reads=reads+1;
                end
                "W":begin
                    scanned=$fscanf(file,"%h %h",a,b);check(scanned==2,"WRITE_TRACE_FORMAT");
                    bus_write(a,b,(writes%3)-1);writes=writes+1;
                end
                "F":begin cycle;fences=fences+1;end
                "Q":begin
                    scanned=$fscanf(file,"%d %d %d %d %d %d",a,b,c,d,e,f);check(scanned==6,"COMMIT_TRACE_FORMAT");
                    accept_commit(a,b,c,d,e,f);commands=commands+1;
                end
                "T":begin
                    scanned=$fscanf(file,"%d %d %d",a,b,c);check(scanned==3,"RETIRE_TRACE_FORMAT");
                    retire(a,b,c);retirements=retirements+1;
                end
                "J":begin
                    scanned=$fscanf(file,"%d %d",a,b);check(scanned==2,"REJECT_TRACE_FORMAT");
                    await_rejection(a,b);rejections=rejections+1;
                end
                "END":ended=1;
                default:$fatal(1,"FRAME_POOL_RTL_ASSERT UNKNOWN_TRACE_OPERATION %s",kind);
            endcase
        end
        check(ended&&reads==81&&writes==1149&&commands==6&&retirements==2&&rejections==1&&fences==15,"COMPLETE_ACTUAL_TRACE_COUNTS");
        $fclose(file);
        $display("FRAME_POOL_RTL_PASS reads=%0d writes=%0d commands=%0d retirements=%0d rejections=%0d checks=%0d",
            reads,writes,commands,retirements,rejections,checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"FRAME_POOL_RTL_ASSERT TIMEOUT");end
endmodule
`default_nettype wire
