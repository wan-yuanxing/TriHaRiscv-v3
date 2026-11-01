`timescale 1ns/1ps
// Complete real MODEL/POST, blockDMA, phase owner, CDC FIFOs and supervised
// bridge. Only the native HMIC/UI memory is an address-exact byte proxy.
module tb_b03_full_frame_payload;
    reg compute_clk=0,free_clk=0,board_reset_n=0,grs_n=0;
    reg ui_clk=0;always #5 compute_clk=~compute_clk;
    always #4 ui_clk=~ui_clk;always #18.518518519 free_clk=~free_clk;
    wire hmic_reset_n,session_reset_n;
    GTP_GRS GRS_INST(.GRS_N(grs_n));
    wire pll_lock,init_done;wire init_fail=0,align_error=0;
    reg [4:0] calibration=0;
    always @(posedge ui_clk or negedge hmic_reset_n)
        if(!hmic_reset_n)calibration<=0;else if(calibration<16)calibration<=calibration+1;
    assign pll_lock=calibration>=8;assign init_done=calibration>=16;
    wire [27:0] awaddr,araddr;wire [3:0] awlen,arlen;
    wire [3:0] wid=0,rid=0;wire awvalid,arvalid,awready,arready,wready,wlast;
    wire [255:0] wdata;wire [31:0] wstrb;
    reg rvalid=0,rlast=0;reg [255:0] rdata=0;
    reg [7:0] memory[0:16777215];
    reg writing=0,reading=0;reg [31:0] write_base,read_base;integer wi=0,ri=0,wn=0,rn=0,ui_ticks=0,native_lane;
    wire [31:0] awbyte={2'd0,awaddr,2'd0},arbyte={2'd0,araddr,2'd0};
    wire awf=awvalid&&awready,arf=arvalid&&arready;
    assign awready=hmic_reset_n&&init_done&&!writing&&!reading&&!rvalid&&ui_ticks%7!=2;
    assign arready=hmic_reset_n&&init_done&&!writing&&!reading&&!rvalid&&!awvalid&&ui_ticks%5!=1;
    assign wready=hmic_reset_n&&(writing||awf)&&ui_ticks%6!=3;
    assign wlast=writing?wi+1==wn:awlen==0;
    wire [31:0] wbyte=writing?write_base+(wi<<5):awbyte;
    always @(posedge ui_clk)begin
        ui_ticks=ui_ticks+1;
        if(!hmic_reset_n)begin writing<=0;reading<=0;rvalid<=0;rlast<=0;wi<=0;ri<=0;end
        else begin
            rvalid<=0;
            if(awf)begin
                if(awbyte<32'h01000000||{1'b0,awbyte}+((awlen+1)<<5)>33'h02000000)$fatal(1,"native WRITE range");
                writing<=1;write_base<=awbyte;wn<=awlen+1;wi<=0;
            end
            if(wready)begin
                for(native_lane=0;native_lane<32;native_lane=native_lane+1)if(wstrb[native_lane])memory[wbyte-32'h01000000+native_lane]<=wdata[8*native_lane+:8];
                wi<=(writing?wi:0)+1;if(wlast)writing<=0;
            end
            if(arf)begin
                if(arbyte<32'h01000000||{1'b0,arbyte}+((arlen+1)<<5)>33'h02000000)$fatal(1,"native READ range");
                reading<=1;read_base<=arbyte;rn<=arlen+1;ri<=0;
            end
            if(reading&&ui_ticks%4!=1)begin
                rvalid<=1;rlast<=ri+1==rn;
                for(native_lane=0;native_lane<32;native_lane=native_lane+1)rdata[8*native_lane+:8]<=memory[read_base-32'h01000000+(ri<<5)+native_lane];
                ri<=ri+1;if(ri+1==rn)reading<=0;
            end
        end
    end
    `include "b03_full_frame_payload_driver.svh"

    reg task_lease=0;reg [1023:0] leased_task;
    integer task_starts=0,task_ends=0,task_checks=0,task_ce0_checks=0;
    always @(posedge compute_clk)begin
        if(!frame.leaf_reset_n)task_lease<=0;
        else begin
            if(task_lease)begin
                if(frame.task_saved!==leased_task)$fatal(1,"shared graph task changed during graph lease");
                task_checks=task_checks+1;if(!run_ce)task_ce0_checks=task_ce0_checks+1;
            end
            if(frame.state==frame.GSTART&&frame.active&&!frame.cancel_all&&frame.g_start_ready)begin
                leased_task<=frame.task_saved;task_lease<=1;task_starts=task_starts+1;
            end
            if(frame.g_done_valid&&frame.state==frame.GWAIT)begin task_lease<=0;task_ends=task_ends+1;end
        end
    end
    reg layer_lease=0;reg [1023:0] leased_op;reg [31:0] leased_epoch;
    integer op_starts=0,op_ends=0,op_checks=0,op_ce0=0;
    always @(posedge compute_clk)begin
        if(!frame.leaf_reset_n)layer_lease<=0;
        else begin
            if(layer_lease)begin
                if(frame.layer.saved_epoch!==leased_epoch||frame.layer.input_path.saved_epoch!==leased_epoch)$fatal(1,"shared epoch full layer changed");
                if(frame.layer.op!==leased_op||frame.layer.input_path.op!==leased_op)$fatal(1,"shared layer op changed");
                op_checks=op_checks+1;if(!run_ce)op_ce0=op_ce0+1;
            end
            if(frame.l_start&&frame.l_start_ready)begin leased_op<=frame.l_op;leased_epoch<=frame.layer.epoch;layer_lease<=1;op_starts=op_starts+1;end
            if(frame.l_done&&frame.l_done_ready)begin layer_lease<=0;op_ends=op_ends+1;end
        end
    end
    final begin
        if(op_starts!=316||op_ends!=316||op_checks==0||op_ce0==0)$fatal(1,"shared op full-frame coverage");
        $display("PASS B03_SHARED_OP_STABLE starts=%0d ends=%0d checks=%0d ce0=%0d",op_starts,op_ends,op_checks,op_ce0);
        $display("PASS B03_SHARED_EPOCH_STABLE starts=%0d ends=%0d checks=%0d ce0=%0d",op_starts,op_ends,op_checks,op_ce0);
        if(task_starts!=2||task_ends!=2||task_checks==0||task_ce0_checks==0)$fatal(1,"shared task monitor coverage");
        $display("PASS B03_SHARED_TASK_STABLE starts=%0d ends=%0d checks=%0d ce0=%0d",task_starts,task_ends,task_checks,task_ce0_checks);
    end
endmodule
