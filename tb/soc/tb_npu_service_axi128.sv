`timescale 1ns/1ps
// Independent byte memories check packing, masked writes and transaction retirement.
module tb_npu_service_axi128;
    reg clk_i=0; always #5 clk_i=~clk_i;
    reg rst_ni=0,healthy_i=1;
    reg p_cmd_valid=0,p_cmd_write=0;
    wire p_cmd_ready;
    reg [31:0] p_cmd_offset=0,p_cmd_id=0,p_cmd_epoch=0;
    reg [4:0] p_cmd_beats=0;
    reg [2:0] p_cmd_client=0;
    reg p_write_valid=0,p_write_last=0,p_read_ready=0,p_done_ready=0,p_abort_req=0;
    reg [255:0] p_write_data=0;
    reg [31:0] p_write_strb=0;
    wire p_write_ready,p_read_valid,p_read_last,p_done_valid,idle_o,fault_o;
    wire [255:0] p_read_data;
    wire [3:0] p_done_status,fault_code_o;
    wire [31:0] p_done_id,p_done_epoch;
    wire [2:0] p_done_client;
    wire m_awvalid_o,m_wvalid_o,m_wlast_o,m_bready_o,m_arvalid_o,m_rready_o;
    wire [31:0] m_awaddr_o,m_araddr_o;
    wire [3:0] m_awid_o,m_arid_o;
    wire [7:0] m_awlen_o,m_arlen_o;
    wire [2:0] m_awsize_o,m_arsize_o;
    wire [1:0] m_awburst_o,m_arburst_o;
    wire [127:0] m_wdata_o;
    wire [15:0] m_wstrb_o;
    wire m_awready_i,m_wready_i,m_arready_i;
    reg m_bvalid_i=0,m_rvalid_i=0,m_rlast_i=0;
    reg [3:0] m_bid_i=0,m_rid_i=0;
    reg [1:0] m_bresp_i=0,m_rresp_i=0;
    reg [127:0] m_rdata_i=0;
    npu_service_axi128 dut(.*);

    reg [7:0] memory[0:8191],expected[0:8191];
    reg [127:0] slave_wdata[0:15];
    reg [15:0] slave_wstrb[0:15];
    reg slave_wlast[0:15];
    reg aw_have=0,write_committed=0,reading=0;
    reg [31:0] aw_address=0,ar_address=0;
    integer aw_beats=0,w_count=0,b_delay=0,r_index=0,r_beats=0;
    integer ticks=0,mode=0,error_mode=0,aw_count=0,b_count=0,ar_count=0;
    integer before_aw=0,before_w=0,split_count=0,checks=0,i,j,k;
    reg [31:0] random_q=32'hda713b29;
    assign m_awready_i=rst_ni&&!aw_have&&!m_bvalid_i&&b_delay==0&&random_q[0]&&(mode!=1||w_count>=2);
    assign m_wready_i=rst_ni&&!m_bvalid_i&&b_delay==0&&w_count<16&&random_q[2]&&(mode!=2||aw_have);
    assign m_arready_i=rst_ni&&!reading&&!m_rvalid_i&&random_q[4];
    always @(posedge clk_i) begin
        ticks<=ticks+1;
        random_q<={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
        if(!rst_ni) begin
            aw_have<=0;write_committed<=0;w_count<=0;b_delay<=0;m_bvalid_i<=0;
            reading<=0;m_rvalid_i<=0;r_index<=0;
        end else begin
            if(m_awvalid_o&&m_awready_i) begin
                if(m_awid_o!=0||m_awaddr_o<32'h82000000||m_awaddr_o>=32'h88000000||
                   m_awsize_o!=4||m_awburst_o!=1||m_awlen_o>15||m_awaddr_o[4:0]!=0||
                   m_awaddr_o[11:0]+16*(m_awlen_o+1)>4096) $fatal(1,"AXI AW contract");
                aw_have<=1;aw_address<=m_awaddr_o;aw_beats<=m_awlen_o+1;aw_count<=aw_count+1;
                if(w_count==0) before_w<=before_w+1;
                if(m_awaddr_o[11:0]==0)split_count<=split_count+1;
            end
            if(m_wvalid_o&&m_wready_i) begin
                slave_wdata[w_count]<=m_wdata_o;slave_wstrb[w_count]<=m_wstrb_o;slave_wlast[w_count]<=m_wlast_o;
                w_count<=w_count+1;if(!aw_have)before_aw<=before_aw+1;
            end
            if(aw_have&&w_count==aw_beats&&!write_committed) begin
                for(j=0;j<aw_beats;j=j+1)begin
                    if(slave_wlast[j]!=(j==aw_beats-1))$fatal(1,"AXI WLAST");
                    for(k=0;k<16;k=k+1)if(slave_wstrb[j][k])
                        memory[(aw_address-32'h82000000+j*16+k)%8192]<=slave_wdata[j][k*8+:8];
                end
                write_committed<=1;b_delay<=13;
            end
            if(b_delay>1)b_delay<=b_delay-1;
            if(b_delay==1)begin
                b_delay<=0;m_bvalid_i<=1;m_bid_i<=error_mode==1?4'd3:4'd0;m_bresp_i<=error_mode==2?2'd2:2'd0;
            end
            if(m_bvalid_i&&m_bready_o)begin
                m_bvalid_i<=0;aw_have<=0;write_committed<=0;w_count<=0;b_count<=b_count+1;
            end
            if(m_arvalid_o&&m_arready_i)begin
                if(m_arid_o!=0||m_araddr_o<32'h82000000||m_araddr_o>=32'h88000000||
                   m_arsize_o!=4||m_arburst_o!=1||m_arlen_o>15||m_araddr_o[4:0]!=0||
                   m_araddr_o[11:0]+16*(m_arlen_o+1)>4096)$fatal(1,"AXI AR contract");
                reading<=1;ar_address<=m_araddr_o;r_beats<=m_arlen_o+1;r_index<=0;ar_count<=ar_count+1;
            end
            if(m_rvalid_i&&m_rready_o)m_rvalid_i<=0;
            if(reading&&(!m_rvalid_i||m_rready_o)&&random_q[6])begin
                for(k=0;k<16;k=k+1)m_rdata_i[k*8+:8]<=memory[(ar_address-32'h82000000+r_index*16+k)%8192];
                m_rvalid_i<=1;m_rlast_i<=(r_index==r_beats-1)^(error_mode==5);
                m_rid_i<=error_mode==3?4'd1:4'd0;m_rresp_i<=error_mode==4?2'd2:2'd0;
                r_index<=r_index+1;if(r_index==r_beats-1)reading<=0;
            end
            if(p_done_valid&&p_done_status==0&&(aw_have||m_bvalid_i||b_delay!=0||reading||m_rvalid_i))
                $fatal(1,"local DONE before all AXI responses retire");
        end
    end
    reg aw_stall=0,w_stall=0,ar_stall=0,r_stall=0,done_stall=0;
    reg [48:0] aw_hold,ar_hold;reg [144:0] w_hold;reg [256:0] r_hold;reg [70:0] done_hold;
    always @(posedge clk_i)if(rst_ni)begin
        if(aw_stall&&(!m_awvalid_o||{m_awaddr_o,m_awid_o,m_awlen_o,m_awsize_o,m_awburst_o}!==aw_hold))$fatal(1,"stalled AW changed");
        if(ar_stall&&(!m_arvalid_o||{m_araddr_o,m_arid_o,m_arlen_o,m_arsize_o,m_arburst_o}!==ar_hold))$fatal(1,"stalled AR changed");
        if(w_stall&&(!m_wvalid_o||{m_wdata_o,m_wstrb_o,m_wlast_o}!==w_hold))$fatal(1,"stalled W changed");
        if(r_stall&&(!p_read_valid||{p_read_data,p_read_last}!==r_hold))$fatal(1,"stalled local R changed");
        if(done_stall&&(!p_done_valid||{p_done_status,p_done_id,p_done_epoch,p_done_client}!==done_hold))$fatal(1,"stalled DONE changed");
        aw_stall<=m_awvalid_o&&!m_awready_i;aw_hold<={m_awaddr_o,m_awid_o,m_awlen_o,m_awsize_o,m_awburst_o};
        ar_stall<=m_arvalid_o&&!m_arready_i;ar_hold<={m_araddr_o,m_arid_o,m_arlen_o,m_arsize_o,m_arburst_o};
        w_stall<=m_wvalid_o&&!m_wready_i;w_hold<={m_wdata_o,m_wstrb_o,m_wlast_o};
        r_stall<=p_read_valid&&!p_read_ready;r_hold<={p_read_data,p_read_last};
        done_stall<=p_done_valid&&!p_done_ready;done_hold<={p_done_status,p_done_id,p_done_epoch,p_done_client};
    end else begin aw_stall<=0;ar_stall<=0;w_stall<=0;r_stall<=0;done_stall<=0;end

    task reset;begin
        @(negedge clk_i);rst_ni=0;healthy_i=1;p_abort_req=0;p_cmd_valid=0;p_write_valid=0;p_read_ready=0;p_done_ready=0;
        repeat(4)@(negedge clk_i);rst_ni=1;repeat(3)@(negedge clk_i);
        if(!idle_o||fault_o)$fatal(1,"reset state");
    end endtask
    task command(input bit wr,input[31:0]offset,input integer beats,input integer id);begin
        @(negedge clk_i);p_cmd_write=wr;p_cmd_offset=offset;p_cmd_beats=beats;p_cmd_id=id;p_cmd_epoch=77;p_cmd_client=5;p_cmd_valid=1;
        do @(posedge clk_i);while(!p_cmd_ready);
        @(negedge clk_i);p_cmd_valid=0;p_cmd_offset=32'hdeadbeef;p_cmd_id=0;
    end endtask
    task done(input integer id,input integer status);begin
        while(!p_done_valid)@(negedge clk_i);
        if(p_done_status!==status||p_done_id!==id||p_done_epoch!=77||p_done_client!=5)$fatal(1,"DONE identity/status want=%0d actual=%0d",status,p_done_status);
        repeat(5)@(negedge clk_i);p_done_ready=1;@(negedge clk_i);p_done_ready=0;
        if(p_done_valid)$fatal(1,"DONE not acknowledged");
        checks=checks+1;
    end endtask
    task write_case(input[31:0]address,input integer beats,input integer id,input integer masks,input bit badlast);integer b,c;begin
        command(1,address,beats,id);
        for(b=0;b<beats;b=b+1)begin
            @(negedge clk_i);for(c=0;c<32;c=c+1)p_write_data[c*8+:8]=(id+b*32+c*7)&255;
            p_write_strb=masks==2?32'd0:masks==1?32'h9137a50f^(32'h1030101*b):32'hffffffff;
            p_write_last=(b==beats-1)^badlast;p_write_valid=1;
            do @(posedge clk_i);while(!p_write_ready);
            for(c=0;c<32;c=c+1)if(p_write_strb[c]&&!badlast)expected[(address-32'h02000000+b*32+c)%8192]=p_write_data[c*8+:8];
            @(negedge clk_i);p_write_valid=0;
        end
    end endtask
    task read_case(input[31:0]address,input integer beats,input integer id,input bit compare);integer b,c;begin
        command(0,address,beats,id);b=0;
        while(b<beats&&!p_done_valid)begin
            @(negedge clk_i);p_read_ready=random_q[8];
            @(posedge clk_i);if(p_read_valid&&p_read_ready)begin
                if(compare)begin
                    if(p_read_last!==(b==beats-1))$fatal(1,"local LAST");
                    for(c=0;c<32;c=c+1)if(p_read_data[c*8+:8]!==expected[(address-32'h02000000+b*32+c)%8192])
                        $fatal(1,"byte scoreboard address=%h beat=%0d byte=%0d",address,b,c);
                end
                b=b+1;
            end
        end
        @(negedge clk_i);p_read_ready=1;
    end endtask
    initial begin
        for(i=0;i<8192;i=i+1)begin memory[i]=(i*7+3)&255;expected[i]=(i*7+3)&255;end
        reset;
        mode=1;write_case(32'h02000020,1,10,0,0);done(10,0);read_case(32'h02000020,1,11,1);done(11,0);
        mode=2;write_case(32'h02000100,8,12,1,0);done(12,0);read_case(32'h02000100,8,13,1);done(13,0);
        mode=0;write_case(32'h02000fe0,16,14,1,0);healthy_i=0;done(14,0);
        if(p_cmd_ready||fault_o)$fatal(1,"healthy must only gate new admission");healthy_i=1;
        read_case(32'h02000fe0,16,15,1);done(15,0);
        if(before_aw==0||before_w==0||split_count==0||aw_count!=b_count)$fatal(1,"AW/W order or split coverage");
        write_case(32'h02000300,8,16,2,0);done(16,0);read_case(32'h02000300,8,17,1);done(17,0);
        for(i=0;i<6;i=i+1)begin
            write_case(32'h02000f40,1+(i*7)%16,100+i*2,1,0);done(100+i*2,0);
            read_case(32'h02000f40,1+(i*7)%16,101+i*2,1);done(101+i*2,0);
        end
        for(i=1;i<=2;i=i+1)begin
            reset;error_mode=i;write_case(32'h02000200,1,20+i,0,0);done(20+i,i==1?3:2);
            if(!fault_o||p_cmd_ready)$fatal(1,"B fault not quarantined");
        end
        for(i=3;i<=5;i=i+1)begin
            reset;error_mode=i;read_case(32'h02000200,1,30+i,0);done(30+i,i==3?3:i==4?2:4);
            if(!fault_o||p_cmd_ready)$fatal(1,"R fault not quarantined");
        end
        reset;error_mode=0;write_case(32'h02000200,1,40,0,1);done(40,4);if(!fault_o)$fatal(1,"local LAST not faulted");
        reset;command(0,32'h01ffffe0,1,41);done(41,1);if(!fault_o)$fatal(1,"range not quarantined");
        reset;command(0,32'h07ffffe0,2,42);done(42,1);
        reset;command(0,32'h02000010,1,43);done(43,1);
        reset;command(0,32'h02000000,0,44);done(44,1);
        reset;command(0,32'h02000000,17,45);done(45,1);
        reset;mode=1;write_case(32'h02000400,1,46,0,0);p_abort_req=1;
        done(46,7);if(!fault_o||p_cmd_ready)$fatal(1,"abort did not quarantine after retirement");
        reset;mode=0;write_case(32'h02000420,1,47,0,0);
        while(!p_done_valid)@(negedge clk_i);
        p_abort_req=1;repeat(3)@(negedge clk_i);done(47,0);
        if(!fault_o||p_cmd_ready)$fatal(1,"held result abort did not quarantine");
        if(checks!=33)$fatal(1,"complete service case count");
        $display("PASS NPU_SERVICE_AXI128 checks=%0d AW=%0d B=%0d AR=%0d WbeforeAW=%0d AWbeforeW=%0d splits=%0d",checks,aw_count,b_count,ar_count,before_aw,before_w,split_count);$finish;
    end
    initial begin #1000000;$fatal(1,"service watchdog checks=%0d",checks);end
endmodule
