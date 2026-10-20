`timescale 1ns/1ps
`default_nettype none
// Literal ABI addresses and independently supplied capture events are the oracle.
module tb_video_capture_driver;
    localparam integer LEGACY=0;
    localparam [31:0] BASE=LEGACY?32'h2001_0000:32'h20012000;
    wire [31:0] capture_req_generation_o;
    reg clk_i=0,rst_ni=0;
    always #4 clk_i=~clk_i;
    reg [31:0] s_axi_awaddr_i=0,s_axi_wdata_i=0,s_axi_araddr_i=0;
    reg [2:0] s_axi_awprot_i=0,s_axi_arprot_i=0;
    reg [3:0] s_axi_wstrb_i=0;
    reg s_axi_awvalid_i=0,s_axi_wvalid_i=0,s_axi_bready_i=0,s_axi_arvalid_i=0,s_axi_rready_i=0;
    wire s_axi_awready_o,s_axi_wready_o,s_axi_bvalid_o,s_axi_arready_o,s_axi_rvalid_o;
    wire [1:0] s_axi_bresp_o,s_axi_rresp_o;
    wire [31:0] s_axi_rdata_o;
    wire capture_req_valid_o;
    reg capture_req_ready_i=0;
    wire [1:0] capture_req_slot_o;
    wire [31:0] capture_req_frame_id_o,capture_req_version_o;
    reg accepted_valid_i=0,completion_valid_i=0,completion_success_i=1;
    wire accepted_ready_o,completion_ready_o;
    reg [7:0] completion_code_i=0,capture_live_code_i=0;
    reg [1:0] capture_slot_i=0;
    reg [31:0] capture_frame_id_i=0,capture_version_i=1;
    reg [31:0] capture_raw_base_i=32'h82000000,capture_preview_base_i=32'h82160000,capture_input_base_i=32'h82800000;
    reg [31:0] capture_raw_pixels_i=480000,capture_preview_pixels_i=120000,capture_input_pixels_i=76800;
    reg [31:0] capture_raw_bytes_i=1440000,capture_preview_bytes_i=360000,capture_input_bytes_i=307200;
    reg [31:0] capture_raw_crc_i=32'h12345678,capture_preview_crc_i=32'h89abcdef,capture_fifo_peak_i=37;
    reg capture_live_fault_i=0,capture_port_drained_i=1;
    wire capture_abort_o,irq_o;
    generate if(LEGACY)begin video_capture_mmio dut(.*);end
    else begin video_capture_mmio_v2 dut(.*);end endgenerate
    integer checks=0,i,j;
    reg [31:0] rd,saved,merged;
    reg [1:0] resp;
    task automatic expect_read(input [31:0] addr,value,input [1:0] response);
        begin
            @(negedge clk_i);s_axi_araddr_i=addr;s_axi_arvalid_i=1;
            do @(posedge clk_i);while(!s_axi_arready_o);
            @(negedge clk_i);s_axi_arvalid_i=0;
            while(!s_axi_rvalid_o)@(negedge clk_i);
            if(s_axi_rresp_o!==response||s_axi_rdata_o!==value)
                $fatal(1,"read %h got %h/%h wanted %h/%h",addr,s_axi_rdata_o,s_axi_rresp_o,value,response);
            repeat(4)begin @(negedge clk_i);if(!s_axi_rvalid_o||s_axi_rdata_o!==value||s_axi_rresp_o!==response||s_axi_arready_o)$fatal(1,"R changed or extra read accepted under stall");end
            s_axi_rready_i=1;@(negedge clk_i);s_axi_rready_i=0;checks=checks+1;
        end
    endtask
    task automatic write_word(input [31:0] addr,value,input [3:0] mask,input [1:0] response,input integer skew);
        begin
            fork
                begin
                    repeat(skew<0?-skew:0)@(negedge clk_i);
                    @(negedge clk_i);s_axi_awaddr_i=addr;s_axi_awvalid_i=1;
                    do @(posedge clk_i);while(!s_axi_awready_o);
                    @(negedge clk_i);s_axi_awvalid_i=0;
                end
                begin
                    repeat(skew>0?skew:0)@(negedge clk_i);
                    @(negedge clk_i);s_axi_wdata_i=value;s_axi_wstrb_i=mask;s_axi_wvalid_i=1;
                    do @(posedge clk_i);while(!s_axi_wready_o);
                    @(negedge clk_i);s_axi_wvalid_i=0;
                end
            join
            while(!s_axi_bvalid_o)@(negedge clk_i);
            if(addr==BASE+32'h030&&s_axi_bresp_o!==response)$fatal(1,"V2_REARM_REJECTED");
            if(s_axi_bresp_o!==response)$fatal(1,"write %h/%h/%h response %h expected %h",addr,value,mask,s_axi_bresp_o,response);
            repeat(5)begin @(negedge clk_i);if(!s_axi_bvalid_o||s_axi_bresp_o!==response||s_axi_awready_o||s_axi_wready_o)$fatal(1,"B changed or extra write accepted");end
            s_axi_bready_i=1;@(negedge clk_i);s_axi_bready_i=0;checks=checks+1;
        end
    endtask
    task automatic reset_all;
        begin
            @(negedge clk_i);rst_ni=0;s_axi_awvalid_i=0;s_axi_wvalid_i=0;s_axi_arvalid_i=0;
            s_axi_bready_i=0;s_axi_rready_i=0;capture_req_ready_i=0;accepted_valid_i=0;completion_valid_i=0;
            capture_live_fault_i=0;capture_live_code_i=0;capture_port_drained_i=1;
            capture_slot_i=0;capture_frame_id_i=0;capture_version_i=1;completion_success_i=1;completion_code_i=0;
            capture_raw_base_i=32'h82000000;capture_preview_base_i=32'h82160000;capture_input_base_i=32'h82800000;
            capture_raw_pixels_i=480000;capture_preview_pixels_i=120000;capture_input_pixels_i=76800;
            repeat(4)@(negedge clk_i);
            if(s_axi_bvalid_o||s_axi_rvalid_o||capture_req_valid_o||capture_abort_o||irq_o)$fatal(1,"reset valids/fault");
            rst_ni=1;
        end
    endtask
    task automatic prepare_shot(input [1:0] which,input [31:0] frame);
        begin
            if(!LEGACY)write_word(BASE+32'h134,frame^32'h56abcd12,15,0,0);
            write_word((BASE+32'h008),1,15,0,0);
            write_word((BASE+32'h100),{30'd0,which},15,0,3);
            write_word((BASE+32'h104),frame,15,0,-3);
            write_word((BASE+32'h108),1,15,0,0);
            write_word((BASE+32'h020),1,15,0,2);
            if(!capture_req_valid_o||capture_req_slot_o!==which||capture_req_frame_id_o!==frame||capture_req_version_o!==1)$fatal(1,"request identity");
            repeat(8)begin @(negedge clk_i);if(!capture_req_valid_o||capture_req_slot_o!==which||capture_req_frame_id_o!==frame)$fatal(1,"request not held");end
            capture_slot_i=which;capture_frame_id_i=frame;
            case(which)
                0:begin capture_raw_base_i=32'h82000000;capture_input_base_i=32'h82800000;end
                1:begin capture_raw_base_i=32'h82200000;capture_input_base_i=32'h82850000;end
                2:begin capture_raw_base_i=32'h82400000;capture_input_base_i=32'h828a0000;end
            endcase
            capture_preview_base_i=capture_raw_base_i+32'h160000;
        end
    endtask
    task automatic dispatch;
        begin @(negedge clk_i);capture_req_ready_i=1;@(negedge clk_i);capture_req_ready_i=0;if(capture_req_valid_o)$fatal(1,"request replay");end
    endtask
    task automatic accept_event;
        begin @(negedge clk_i);accepted_valid_i=1;do @(posedge clk_i);while(!accepted_ready_o);@(negedge clk_i);accepted_valid_i=0;end
    endtask
    task automatic complete_event;
        begin @(negedge clk_i);completion_valid_i=1;do @(posedge clk_i);while(!completion_ready_o);@(negedge clk_i);completion_valid_i=0;end
    endtask
    reg [127:0] kind;
    reg [31:0] arg0,arg1,arg2;
    integer fd,rc,reads=0,writes=0,events=0,fences=0;
    string trace_file;
    initial begin
        if(!$value$plusargs("TRACE=%s",trace_file))$fatal(1,"missing native trace");
        fd=$fopen(trace_file,"r");if(!fd)$fatal(1,"cannot open native trace");
        reset_all;capture_req_ready_i=1;
        while(!$feof(fd))begin
            rc=$fscanf(fd,"%s",kind);
            if(rc==1)case(kind)
                "R":begin
                    rc=$fscanf(fd,"%h %h",arg0,arg1);if(rc!=2)$fatal(1,"trace R parse");
                    expect_read(BASE+arg0,arg1,0);reads=reads+1;
                end
                "W":begin
                    rc=$fscanf(fd,"%h %h",arg0,arg1);if(rc!=2)$fatal(1,"trace W parse");
                    write_word(BASE+arg0,arg1,15,0,writes%3-1);writes=writes+1;
                end
                "E":begin
                    rc=$fscanf(fd,"%d %d %d",arg0,arg1,arg2);if(rc!=3)$fatal(1,"trace E parse");
                    if(capture_req_slot_o!==arg0[1:0]||capture_req_frame_id_o!==arg1||capture_req_generation_o!==arg2||capture_req_valid_o)
                        $fatal(1,"native request identity/dispatch");
                    capture_slot_i=arg0[1:0];capture_frame_id_i=arg1;
                    capture_raw_base_i=32'h82000000+arg0*32'h200000;
                    capture_preview_base_i=capture_raw_base_i+32'h160000;
                    capture_input_base_i=32'h82800000+arg0*32'h50000;
                    accept_event;complete_event;events=events+1;
                end
                "F":begin fences=fences+1;@(negedge clk_i);end
                "END":begin
                    if(reads==0||writes==0||events!=4||fences==0||capture_abort_o||irq_o)$fatal(1,"trace coverage/fault");
                    $display("VIDEO_CAPTURE_DRIVER_RTL_PASS reads=%0d writes=%0d events=%0d fences=%0d",reads,writes,events,fences);$finish;
                end
                default:$fatal(1,"unknown native trace token");
            endcase
        end
        $fatal(1,"native trace missing END");
    end
    initial begin #10000000;$fatal(1,"native trace timeout");end
endmodule
`default_nettype wire
