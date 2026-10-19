`timescale 1ns/1ps
`default_nettype none
// Literal ABI addresses and independently supplied capture events are the oracle.
module tb_video_capture_mmio;
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
    video_capture_mmio dut(.*);
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
            write_word(32'h20010008,1,15,0,0);
            write_word(32'h20010100,{30'd0,which},15,0,3);
            write_word(32'h20010104,frame,15,0,-3);
            write_word(32'h20010108,1,15,0,0);
            write_word(32'h20010020,1,15,0,2);
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
    reg [31:0] ro_offsets[0:38];
    initial begin
        ro_offsets[0]='h000;ro_offsets[1]='h004;ro_offsets[2]='h00c;ro_offsets[3]='h018;
        ro_offsets[4]='h024;ro_offsets[5]='h028;ro_offsets[6]='h02c;
        ro_offsets[7]='h10c;ro_offsets[8]='h110;ro_offsets[9]='h114;ro_offsets[10]='h118;
        ro_offsets[11]='h11c;ro_offsets[12]='h120;ro_offsets[13]='h124;ro_offsets[14]='h128;
        ro_offsets[15]='h12c;ro_offsets[16]='h130;ro_offsets[17]='h140;ro_offsets[18]='h144;
        ro_offsets[19]='h148;ro_offsets[20]='h14c;ro_offsets[21]='h150;ro_offsets[22]='h154;
        ro_offsets[23]='h180;ro_offsets[24]='h184;ro_offsets[25]='h188;ro_offsets[26]='h18c;
        ro_offsets[27]='h190;ro_offsets[28]='h194;ro_offsets[29]='h198;ro_offsets[30]='h19c;
        ro_offsets[31]='h1a0;ro_offsets[32]='h1a4;ro_offsets[33]='h1a8;ro_offsets[34]='h1ac;
        ro_offsets[35]='h1b0;ro_offsets[36]='h1b4;ro_offsets[37]='h1b8;ro_offsets[38]='h1bc;
        reset_all;
        // PROT is transported but grants no alternate register access.
        s_axi_awprot_i=7;s_axi_arprot_i=7;
        expect_read(32'h20010000,32'h10000,0);expect_read(32'h20010004,7,0);
        expect_read(32'h2001000c,128,0);expect_read(32'h20010118,2400,0);
        expect_read(32'h2001011c,1200,0);expect_read(32'h20010120,320,0);
        expect_read(32'h20010124,800,0);expect_read(32'h20010128,600,0);
        expect_read(32'h2001012c,320,0);expect_read(32'h20010130,320,0);
        expect_read(32'h20000000,0,3);expect_read(32'h30010000,0,3);expect_read(32'h20020000,0,3);
        expect_read(32'h20010001,0,3);expect_read(32'h2001001c,0,3);expect_read(32'h20010200,0,3);
        expect_read(32'h20010020,0,2);expect_read(32'hxxxxxxxx,0,3);
        write_word(32'h20010000,1,0,2,0);write_word(32'h2001001c,0,0,3,0);
        write_word(32'h20000008,1,15,3,0);write_word(32'h20010009,1,15,3,0);
        write_word(32'hxxxxxxxx,1,15,3,0);write_word(32'h20010104,32'hx,15,2,0);
        write_word(32'h20010104,1,4'bx001,2,0);
        write_word(32'h20010104,32'hx,0,2,0);
        for(i=0;i<39;i=i+1)write_word(32'h20010000+ro_offsets[i],0,15,2,i%3-1);
        write_word(32'h20010020,1,15,2,0); // disabled
        write_word(32'h20010008,2,15,2,0);write_word(32'h20010010,8,15,2,0);
        write_word(32'h20010100,4,15,2,0);write_word(32'h20010014,8,15,2,0);
        // All byte masks, independently merge the four literal byte lanes.
        merged=0;
        for(i=0;i<16;i=i+1)begin
            write_word(32'h20010104,32'h9a7b5c3d^i,4'(i),0,i%3-1);
            for(j=0;j<4;j=j+1)if(i&(1<<j))merged[j*8+:8]=(32'h9a7b5c3d^i)>>(j*8);
            expect_read(32'h20010104,merged,0);
        end
        write_word(32'h20010008,1,1,0,0);write_word(32'h20010008,32'hffffffff,0,0,0);
        write_word(32'h20010100,3,15,0,0);expect_read(32'h2001010c,0,0);
        write_word(32'h20010020,1,15,2,0);write_word(32'h20010100,0,15,0,0);
        write_word(32'h20010108,2,15,0,0);write_word(32'h20010020,1,15,2,0);
        write_word(32'h20010108,1,15,0,0);write_word(32'h20010020,1,1,2,0);
        write_word(32'h20010020,2,15,2,0);write_word(32'h20010020,32'hffffffff,0,0,0);
        write_word(32'h20010020,0,15,0,0);
        // High-byte merges and W1C discard disabled lanes, while a reserved
        // enabled bit rejects the complete write atomically.
        write_word(32'h20010010,7,1,0,0);
        write_word(32'h20010010,32'hffffff00,1,0,0);expect_read(32'h20010010,0,0);
        write_word(32'h20010010,32'hff000007,8,2,0);expect_read(32'h20010010,0,0);
        write_word(32'h20010008,32'h00010000,1,0,0);expect_read(32'h20010008,0,0);
        write_word(32'h20010014,32'hffff0007,1,0,0);
        for(i=0;i<3;i=i+1)begin
            reset_all;prepare_shot(2'(i),i==2?32'hffffffff:32'(i));
            expect_read(32'h2001000c,135,0);
            write_word(32'h20010008,0,15,2,0);write_word(32'h20010104,42,15,2,0);
            write_word(32'h20010020,1,15,2,0);
            dispatch;accept_event;
            expect_read(32'h20010140,32'(i),0);expect_read(32'h20010028,i==2?32'hffffffff:32'(i),0);
            expect_read(32'h2001014c,capture_raw_base_i,0);expect_read(32'h20010150,capture_preview_base_i,0);
            expect_read(32'h20010154,capture_input_base_i,0);
            complete_event;
            expect_read(32'h20010014,3,0);if(irq_o)$fatal(1,"masked IRQ");
            write_word(32'h20010010,7,1,0,0);if(!irq_o)$fatal(1,"mask discarded events");
            expect_read(32'h2001018c,1,0);expect_read(32'h2001019c,480000,0);
            expect_read(32'h200101a0,120000,0);expect_read(32'h200101a4,76800,0);
            expect_read(32'h200101a8,1440000,0);expect_read(32'h200101ac,360000,0);
            expect_read(32'h200101b0,307200,0);expect_read(32'h200101b4,32'h12345678,0);
            expect_read(32'h200101b8,32'h89abcdef,0);expect_read(32'h200101bc,37,0);
            if(accepted_ready_o||completion_ready_o)$fatal(1,"mailbox not backpressured");
            write_word(32'h20010014,3,1,0,0);if(irq_o)$fatal(1,"ACK IRQ");
            expect_read(32'h2001018c,1,0);expect_read(32'h2001000c,139,0);
            capture_live_code_i=8'h06;capture_live_fault_i=1;@(negedge clk_i);@(negedge clk_i);
            expect_read(32'h20010018,6,0);expect_read(32'h2001018c,1,0);if(!capture_abort_o||!irq_o)$fatal(1,"late fault");
            write_word(32'h20010014,4,1,0,0);repeat(5)@(negedge clk_i);if(irq_o)$fatal(1,"sticky fault re-raised IRQ");
        end
        reset_all;prepare_shot(0,0);dispatch;
        // Accepted and completion may enter empty mailboxes on the same edge.
        @(negedge clk_i);accepted_valid_i=1;completion_valid_i=1;
        @(negedge clk_i);accepted_valid_i=0;completion_valid_i=0;
        expect_read(32'h2001018c,1,0);expect_read(32'h20010018,0,0);
        // Clear a previously pending accepted event; a simultaneous fresh
        // completion must win its own W1C bit on the execution edge.
        reset_all;prepare_shot(0,0);dispatch;accept_event;
        @(negedge clk_i);s_axi_awaddr_i=32'h20010014;s_axi_awvalid_i=1;s_axi_wdata_i=3;s_axi_wstrb_i=1;s_axi_wvalid_i=1;
        @(negedge clk_i);s_axi_awvalid_i=0;s_axi_wvalid_i=0;completion_valid_i=1;
        @(negedge clk_i);completion_valid_i=0;
        if(!s_axi_bvalid_o||s_axi_bresp_o!=0)$fatal(1,"ACK race B");
        s_axi_bready_i=1;@(negedge clk_i);s_axi_bready_i=0;
        expect_read(32'h20010014,2,0);expect_read(32'h2001000c,171,0);
        // Duplicate accepted is drained only after the mailbox ACK and does
        // not replace the immutable first record.
        write_word(32'h20010014,1,1,0,0);capture_frame_id_i=99;accept_event;
        expect_read(32'h20010018,225,0);expect_read(32'h20010144,0,0);
        // Success without a first PIX acceptance is invalid, whereas a known
        // failed dispatched shot legitimately has no accepted event.
        reset_all;prepare_shot(0,4);dispatch;complete_event;
        expect_read(32'h20010018,225,0);expect_read(32'h2001018c,0,0);
        reset_all;prepare_shot(0,5);dispatch;completion_success_i=0;completion_code_i=3;complete_event;
        expect_read(32'h20010018,3,0);expect_read(32'h2001018c,32'h300,0);expect_read(32'h20010014,6,0);
        expect_read(32'h20010028,0,0);expect_read(32'h2001002c,5,0);
        accept_event;expect_read(32'h20010028,0,0);expect_read(32'h20010014,6,0);
        expect_read(32'h2001018c,32'h300,0);expect_read(32'h20010018,3,0);
        for(i=0;i<8;i=i+1)begin
            reset_all;
            if(i!=0)begin prepare_shot(0,123);if(i!=1)dispatch;end
            if(i>=3)accept_event;
            case(i)
                0:accept_event; // unsolicited
                1:accept_event; // not dispatched
                2:begin capture_raw_base_i=32'h82000001;accept_event;end
                3:begin completion_success_i=1;completion_code_i=6;complete_event;end
                4:begin completion_success_i=0;completion_code_i=0;complete_event;end
                5:begin capture_raw_pixels_i=32'hx;complete_event;end
                6:begin completion_success_i=1'bx;complete_event;end
                7:begin capture_version_i=2;complete_event;end
            endcase
            expect_read(32'h20010018,225,0);if(!capture_abort_o)$fatal(1,"protocol must abort");
            expect_read(32'h2001018c,0,0);
        end
        reset_all;prepare_shot(0,3);dispatch;accept_event;
        @(negedge clk_i);completion_success_i=0;completion_code_i=6;capture_live_fault_i=1;capture_live_code_i=7;completion_valid_i=1;
        @(negedge clk_i);completion_valid_i=0;
        expect_read(32'h20010018,6,0);expect_read(32'h2001018c,32'h600,0);
        write_word(32'h20010014,2,1,0,0);completion_success_i=1;completion_code_i=0;complete_event;
        expect_read(32'h2001018c,32'h600,0);expect_read(32'h20010018,6,0);
        reset_all;prepare_shot(0,3);dispatch;accept_event;
        @(negedge clk_i);capture_version_i=2;completion_success_i=0;completion_code_i=6;
        capture_live_fault_i=1;capture_live_code_i=7;completion_valid_i=1;
        @(negedge clk_i);completion_valid_i=0;
        expect_read(32'h20010018,225,0);
        // Duplicate accepted + legitimate failed completion + live fault all
        // coincide. Protocol has priority, and the valid failed record survives.
        reset_all;prepare_shot(0,6);dispatch;accept_event;write_word(32'h20010014,1,1,0,0);
        @(negedge clk_i);accepted_valid_i=1;completion_valid_i=1;completion_success_i=0;completion_code_i=6;
        capture_live_fault_i=1;capture_live_code_i=7;
        @(negedge clk_i);accepted_valid_i=0;completion_valid_i=0;
        expect_read(32'h20010018,225,0);expect_read(32'h2001018c,32'h600,0);
        // First fault wins same-edge W1C, and is raised only once.
        reset_all;write_word(32'h20010010,4,1,0,0);
        @(negedge clk_i);s_axi_awaddr_i=32'h20010014;s_axi_awvalid_i=1;s_axi_wdata_i=4;s_axi_wstrb_i=1;s_axi_wvalid_i=1;
        @(negedge clk_i);s_axi_awvalid_i=0;s_axi_wvalid_i=0;capture_live_fault_i=1;capture_live_code_i=3;
        @(negedge clk_i);s_axi_bready_i=1;@(negedge clk_i);s_axi_bready_i=0;
        expect_read(32'h20010014,4,0);if(!irq_o)$fatal(1,"first fault lost to W1C");
        // Complete whole-address decoding: low offset aliases are forbidden.
        expect_read(32'h00010100,0,3);expect_read(32'h2001fffc,0,3);
        write_word(32'h2001fffc,1,15,3,0);
        reset_all;capture_live_fault_i=1;capture_live_code_i=0;repeat(2)@(negedge clk_i);expect_read(32'h20010018,225,0);
        reset_all;capture_live_fault_i=1;capture_live_code_i=8'hxx;repeat(2)@(negedge clk_i);expect_read(32'h20010018,225,0);
        reset_all;prepare_shot(0,0);capture_live_fault_i=1;capture_live_code_i=6;
        repeat(3)@(negedge clk_i);if(!capture_req_valid_o)$fatal(1,"fault withdrew request");dispatch;
        // A held AR samples before a concurrent CONTROL write executes.
        reset_all;
        @(negedge clk_i);s_axi_awaddr_i=32'h20010008;s_axi_awvalid_i=1;s_axi_wdata_i=1;s_axi_wstrb_i=15;s_axi_wvalid_i=1;
        @(negedge clk_i);s_axi_awvalid_i=0;s_axi_wvalid_i=0;s_axi_araddr_i=32'h20010008;s_axi_arvalid_i=1;
        @(negedge clk_i);s_axi_arvalid_i=0;if(!s_axi_rvalid_o||s_axi_rdata_o!==0)$fatal(1,"concurrent read not pre-write");
        // Coordinated reset drops all AXI and capture VALID and unlocks frame0.
        reset_all;prepare_shot(2,0);reset_all;expect_read(32'h2001000c,128,0);
        // Half a write in either order is discarded only by coordinated reset.
        @(negedge clk_i);s_axi_awaddr_i=32'h20010008;s_axi_awvalid_i=1;
        @(negedge clk_i);s_axi_awvalid_i=0;repeat(4)@(negedge clk_i);
        if(s_axi_bvalid_o)$fatal(1,"AW alone executed");reset_all;
        @(negedge clk_i);s_axi_wdata_i=1;s_axi_wvalid_i=1;
        @(negedge clk_i);s_axi_wvalid_i=0;repeat(4)@(negedge clk_i);
        if(s_axi_bvalid_o)$fatal(1,"W alone executed");reset_all;
        expect_read(32'h20010008,0,0);
        $display("VIDEO_CAPTURE_MMIO_PASS checks=%0d",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"MMIO test timeout");end
endmodule
`default_nettype wire
