`timescale 1ns/1ps
`default_nettype none
module tb_video_memory_scheduler #(parameter integer LEGACY_POLICY=0,MAX_READ_BURSTS=4);
    reg clk=0,reset_n=0,online=0,memory_fault=0,display_urgent=0;
    always #4 clk=~clk;
    reg [3:0] c_awid=1,d_arid=0;
    reg [31:0] c_awaddr=32'h82000000,d_araddr=32'h82000000;
    reg [7:0] c_awlen=0,d_arlen=0;
    reg [2:0] c_awsize=4,d_arsize=4;
    reg [1:0] c_awburst=1,d_arburst=1;
    reg c_awvalid=0,c_wvalid=1,c_wlast=1,c_bready=1,d_arvalid=0,d_rready=1;
    reg [127:0] c_wdata=128'h112233445566778899aabbccddeeff00;
    reg [15:0] c_wstrb=16'hffff;
    wire c_awready,c_wready,c_bvalid,d_arready,d_rvalid,d_rlast;
    wire [3:0] c_bid,d_rid;
    wire [1:0] c_bresp,d_rresp;
    wire [127:0] d_rdata;
    wire [3:0] m_awid,m_arid,m_bid,m_rid;
    wire [31:0] m_awaddr,m_araddr;
    wire [7:0] m_awlen,m_arlen;
    wire [2:0] m_awsize,m_arsize;
    wire [1:0] m_awburst,m_arburst,m_bresp,m_rresp;
    wire m_awvalid,m_awready,m_wvalid,m_wready,m_wlast,m_bvalid,m_bready;
    wire m_arvalid,m_arready,m_rvalid,m_rready,m_rlast;
    wire [127:0] m_wdata,m_rdata;wire [15:0] m_wstrb;
    wire fault,busy,port_drained;wire [7:0] fault_code;wire [31:0] read_grants,write_grants;
    reg hold_down_aw=0,hold_down_ar=0;
    wire bridge_awready,bridge_arready,bridge_fault;
    wire [7:0] bridge_code;
    wire [27:0] h_awaddr,h_araddr;
    wire [3:0] h_awlen,h_arlen,h_awid,h_arid,h_wid,h_rid;
    wire h_awvalid,h_arvalid,h_awready,h_arready,h_wready,h_rvalid,h_wlast,h_rlast;
    wire [255:0] h_wdata,h_rdata;wire [31:0] h_wstrb;
    reg hold_aw=0,hold_ar=0,hold_w=0,hold_r=0;
    reg [3:0] bad_rid=0;
    integer aw_commands,ar_commands,write_beats,read_beats,first_w,first_r;
    assign m_awready=bridge_awready&&!hold_down_aw;
    assign m_arready=bridge_arready&&!hold_down_ar;
    generate if(LEGACY_POLICY)begin
        assign m_awid=c_awid;assign m_awaddr=c_awaddr;assign m_awlen=c_awlen;assign m_awsize=c_awsize;assign m_awburst=c_awburst;assign m_awvalid=c_awvalid;
        assign c_awready=m_awready;assign m_wdata=c_wdata;assign m_wstrb=c_wstrb;assign m_wlast=c_wlast;assign m_wvalid=c_wvalid;
        assign c_wready=m_wready;assign c_bid=m_bid;assign c_bresp=m_bresp;assign c_bvalid=m_bvalid;assign m_bready=c_bready;
        assign m_arid=d_arid;assign m_araddr=d_araddr;assign m_arlen=d_arlen;assign m_arsize=d_arsize;assign m_arburst=d_arburst;assign m_arvalid=d_arvalid;
        assign d_arready=m_arready;assign d_rid=m_rid;assign d_rdata=m_rdata;assign d_rresp=m_rresp;assign d_rlast=m_rlast;assign d_rvalid=m_rvalid;assign m_rready=d_rready;
        assign fault=bridge_fault;assign fault_code=bridge_code;assign busy=0;assign port_drained=1;assign read_grants=0;assign write_grants=0;
    end else begin
        video_memory_scheduler #(.MAX_READ_BURSTS(MAX_READ_BURSTS)) dut(.*);
    end endgenerate
    axi128_hmic256 #(.NATIVE_TIMEOUT_CYCLES(20000)) bridge(
        .clk(clk),.rst_n(reset_n),.init_done(online),
        .awid(m_awid),.awaddr(m_awaddr),.awlen(m_awlen),.awsize(m_awsize),.awburst(m_awburst),
        .awvalid(m_awvalid&&!hold_down_aw),.awready(bridge_awready),.wdata(m_wdata),.wstrb(m_wstrb),.wlast(m_wlast),.wvalid(m_wvalid),.wready(m_wready),
        .bid(m_bid),.bresp(m_bresp),.bvalid(m_bvalid),.bready(m_bready),
        .arid(m_arid),.araddr(m_araddr),.arlen(m_arlen),.arsize(m_arsize),.arburst(m_arburst),.arvalid(m_arvalid&&!hold_down_ar),.arready(bridge_arready),
        .rid(m_rid),.rdata(m_rdata),.rresp(m_rresp),.rlast(m_rlast),.rvalid(m_rvalid),.rready(m_rready),.fault(bridge_fault),.fault_code(bridge_code),
        .h_awaddr(h_awaddr),.h_awlen(h_awlen),.h_awid(h_awid),.h_awvalid(h_awvalid),.h_awready(h_awready),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_wready(h_wready),.h_wid(h_wid),.h_wlast(h_wlast),
        .h_araddr(h_araddr),.h_arlen(h_arlen),.h_arid(h_arid),.h_arvalid(h_arvalid),.h_arready(h_arready),
        .h_rdata(h_rdata),.h_rid(h_rid),.h_rlast(h_rlast),.h_rvalid(h_rvalid));
    axi_bridge_native_model native_mem(.clk(clk),.rst_n(reset_n),.gaps(1'b1),.hold_aw(hold_aw),.hold_ar(hold_ar),.hold_w(hold_w),.hold_r(hold_r),
        .idle_wready(1'b0),.bad_wid(4'd0),.bad_rid(bad_rid),.bad_wlast(1'b0),.bad_rlast(1'b0),.x_read(1'b0),.inject_r(1'b0),.read_xor(256'd0),
        .h_awaddr(h_awaddr),.h_araddr(h_araddr),.h_awlen(h_awlen),.h_arlen(h_arlen),.h_awid(h_awid),.h_arid(h_arid),
        .h_awvalid(h_awvalid),.h_arvalid(h_arvalid),.h_awready(h_awready),.h_arready(h_arready),.h_wready(h_wready),.h_rvalid(h_rvalid),
        .h_wdata(h_wdata),.h_wstrb(h_wstrb),.h_rdata(h_rdata),.h_wid(h_wid),.h_rid(h_rid),.h_wlast(h_wlast),.h_rlast(h_rlast),
        .aw_commands(aw_commands),.ar_commands(ar_commands),.write_beats(write_beats),.read_beats(read_beats),.first_w(first_w),.first_r(first_r));
    integer case_id=0,writes=0,reads=0,write_wait=0,read_wait=0,max_write_wait=0,max_read_wait=0;
    reg aw_held=0,ar_held=0,b_held=0,r_held=0;
    reg [48:0] aw_saved,ar_saved;reg [5:0] b_saved;reg [134:0] r_saved;
    always @(posedge clk)if(reset_n)begin
        memory_fault<=bridge_fault;
        if(aw_held&&(!m_awvalid||{m_awid,m_awaddr,m_awlen,m_awsize,m_awburst}!==aw_saved))$fatal(1,"SHARED_AW_UNSTABLE");
        if(ar_held&&(!m_arvalid||{m_arid,m_araddr,m_arlen,m_arsize,m_arburst}!==ar_saved))$fatal(1,"SHARED_AR_UNSTABLE");
        if(b_held&&(!c_bvalid||{c_bid,c_bresp}!==b_saved))$fatal(1,"SHARED_B_UNSTABLE");
        if(r_held&&(!d_rvalid||{d_rid,d_rdata,d_rresp,d_rlast}!==r_saved))$fatal(1,"SHARED_R_UNSTABLE");
        aw_held<=m_awvalid&&!m_awready;aw_saved<={m_awid,m_awaddr,m_awlen,m_awsize,m_awburst};
        ar_held<=m_arvalid&&!m_arready;ar_saved<={m_arid,m_araddr,m_arlen,m_arsize,m_arburst};
        b_held<=c_bvalid&&!c_bready;b_saved<={c_bid,c_bresp};
        r_held<=d_rvalid&&!d_rready;r_saved<={d_rid,d_rdata,d_rresp,d_rlast};
        if(c_awready&&d_arready)$fatal(1,"SHARED_DUAL_GRANT");
        if(!LEGACY_POLICY&&((c_bvalid&&d_rvalid)||(port_drained&&(m_awvalid||m_arvalid||c_bvalid||d_rvalid))))$fatal(1,"SHARED_OWNER_EARLY_RELEASE");
        if(c_bvalid&&c_bready)begin
            writes=writes+1;
            if(case_id==0||case_id==1)begin
                if(c_bresp!=0||c_bid!=1)$fatal(1,"SHARED_WRITE_RESPONSE");
                if(d_arvalid)read_wait=read_wait+1;
                if(read_wait>max_read_wait)max_read_wait=read_wait;
                if(read_wait>1)$fatal(1,"SHARED_READ_STARVED");
            end
            write_wait=0;
        end
        if(d_arvalid&&d_arready)read_wait=0;
        if(d_rvalid&&d_rready)begin
            reads=reads+1;
            if(case_id==0||case_id==1)begin
                if(d_rresp!=0||d_rid!=0||!d_rlast||d_rdata!==(writes?c_wdata:128'd0))$fatal(1,"SHARED_READ_AFTER_B");
                if(c_awvalid)write_wait=write_wait+1;
                if(write_wait>max_write_wait)max_write_wait=write_wait;
                if(write_wait>(case_id==1?MAX_READ_BURSTS:1))$fatal(1,"SHARED_WRITE_STARVED");
            end
        end
        if(c_awvalid&&c_awready)write_wait=0;
    end
    initial begin
        if($value$plusargs("CASE=%d",case_id))begin end
        repeat(6)@(negedge clk);reset_n=1;online=1;
        if(case_id==10||case_id==11)begin
            if(case_id==10)force m_bvalid=1;else force m_rvalid=1;
            @(posedge clk);@(negedge clk);release m_bvalid;release m_rvalid;
            c_awvalid=1;d_arvalid=1;
            repeat(8)@(negedge clk);
            if(!fault||c_awready||d_arready)$fatal(1,"SHARED_STRAY_NOT_STICKY");
        end else if(case_id==13||case_id==14)begin
            c_awvalid=1;
            wait(c_awready);@(posedge clk);@(negedge clk);c_awvalid=0;
            wait(m_awvalid&&m_awready);@(posedge clk);@(negedge clk);
            if(case_id==13)c_wvalid=1'bx;else force m_wready=1'bx;
            @(posedge clk);@(negedge clk);c_wvalid=1;release m_wready;
            wait(writes==1);@(negedge clk);c_awvalid=1;d_arvalid=1;repeat(12)@(negedge clk);
            if(!fault||fault_code!=10||busy||!port_drained||c_awready||d_arready)$fatal(1,"SHARED_UNKNOWN_W_NOT_DRAINED");
        end else if(case_id==12)begin
            d_arlen=255;d_arvalid=1;wait(d_arready);@(posedge clk);@(negedge clk);d_arvalid=0;
            wait(reads==256);repeat(8)@(negedge clk);
            if(busy||!port_drained||fault)$fatal(1,"SHARED_ADVERTISED_READ_COUNT");
        end else if(case_id>=4&&case_id<=9)begin
            c_awvalid=case_id==4||case_id==6;d_arvalid=!c_awvalid;
            if(case_id==6)c_wlast=0;
            if(case_id==7)bad_rid=1;
            if(case_id==9)d_arlen=3;
            wait((c_awvalid&&c_awready)||(d_arvalid&&d_arready));@(posedge clk);@(negedge clk);c_awvalid=0;d_arvalid=0;
            if(case_id==4)begin hold_w=1;wait(h_awvalid);online=0;repeat(30)@(negedge clk);hold_w=0;end
            if(case_id==5)begin wait(m_arvalid);force memory_fault=1;repeat(5)@(negedge clk);release memory_fault;end
            if(case_id==8)begin wait(m_rvalid);force m_rid=3;end
            if(case_id==9)begin wait(m_rvalid);force m_rlast=1;end
            wait(writes+reads>=(case_id==9?4:1));@(negedge clk);release m_rid;release m_rlast;
            c_awvalid=1;d_arvalid=1;
            repeat(12)@(negedge clk);
            if(!fault||c_awready||d_arready||busy||!port_drained)$fatal(1,"SHARED_FAULT_DRAIN code=%h",fault_code);
        end else begin
            display_urgent=case_id==1;c_awvalid=1;d_arvalid=1;
            if(case_id==2)begin
                hold_down_ar=1;wait(m_arvalid);repeat(33)@(negedge clk);display_urgent=1;hold_down_ar=0;
                wait(writes>0);hold_down_aw=1;wait(m_awvalid);repeat(33)@(negedge clk);hold_down_aw=0;
            end
            if(case_id==3)begin
                d_rready=0;wait(d_rvalid);repeat(45)begin @(negedge clk);if(port_drained)$fatal(1,"SHARED_R_HOLD_RETIRED");end
                d_rready=1;c_bready=0;wait(c_bvalid);repeat(45)begin @(negedge clk);if(port_drained)$fatal(1,"SHARED_B_HOLD_RETIRED");end
                c_bready=1;
            end
            wait(writes>=12&&reads>=12);
            if(fault)$fatal(1,"SHARED_UNEXPECTED_FAULT %h",fault_code);
        end
        $display("VIDEO_MEMORY_SCHEDULER_PASS case=%0d reads=%0d writes=%0d maxRwait=%0d maxWwait=%0d quota=%0d",case_id,reads,writes,max_read_wait,max_write_wait,MAX_READ_BURSTS);$finish;
    end
    initial begin #20000000;$fatal(1,"SHARED_SCHEDULER_WATCHDOG case=%0d r=%0d w=%0d",case_id,reads,writes);end
endmodule
`default_nettype wire
