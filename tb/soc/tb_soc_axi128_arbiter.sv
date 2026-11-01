`timescale 1ns/1ps
// Arithmetic equivalence against the full-width exclusive-end definition.
// All 8-bit lengths and all 256 aligned offsets in every high address window.
module tb_axi128_address_legal;
    soc_axi128_arbiter dut();
    integer hi,word_index,len,low,size,burst,cases=0;
    reg [31:0] address;
    reg [32:0] finish_address;
    reg [12:0] finish_page;
    reg expected;
    task compare(input [31:0] a,input [7:0] l,input [2:0] s,input [1:0] b);begin
        finish_address={1'b0,a}+33'd16*({25'd0,l}+33'd1);
        finish_page={1'b0,a[11:0]}+13'd16*({5'd0,l}+13'd1);
        expected=a>=32'h80000000&&finish_address<=33'h088000000&&l<=15&&a[3:0]==0&&s==4&&b==1&&finish_page<=4096;
        if((dut.legal(a,l,s,b)===1'b1)!==(expected===1'b1))$fatal(1,"LEGAL_MISMATCH a=%h len=%d size=%d burst=%d",a,l,s,b);
        cases=cases+1;
    end endtask
    initial begin
        for(hi=0;hi<32;hi=hi+1)
            for(word_index=0;word_index<256;word_index=word_index+1)
                for(len=0;len<256;len=len+1)
                    compare((hi<<27)|32'h07fff000|(word_index<<4),len,4,1);
        for(low=0;low<16;low=low+1)
            for(size=0;size<8;size=size+1)
                for(burst=0;burst<4;burst=burst+1)
                    for(len=0;len<256;len=len+1)begin
                        compare(32'h80000000+low,len,size,burst);
                        compare(32'h87fffff0+low,len,size,burst);
                    end
        compare(32'h80xxx000,0,4,1);compare(32'h8x000000,0,4,1);
        compare(32'h80000000,8'h0x,4,1);compare(32'h80000000,0,3'bx00,1);compare(32'h80000000,0,4,2'bx1);
        $display("PASS AXI128_ADDRESS_LEGAL cases=%0d",cases);$finish;
    end
endmodule

// Three concurrent masters and a separate byte-memory AXI slave/oracle.
module tb_soc_axi128_arbiter #(parameter integer M=3);
    reg clk_i=0;always #5 clk_i=~clk_i;
    reg rst_ni=0,healthy_i=1;
    reg [M-1:0] s_awvalid_i=0,s_wvalid_i=0,s_wlast_i=0,s_bready_i=0,s_arvalid_i=0,s_rready_i=0;
    reg [M*32-1:0] s_awaddr_i=0,s_araddr_i=0;
    reg [M*4-1:0] s_awid_i=0,s_arid_i=0;
    reg [M*8-1:0] s_awlen_i=0,s_arlen_i=0;
    reg [M*3-1:0] s_awsize_i=0,s_arsize_i=0;
    reg [M*2-1:0] s_awburst_i=0,s_arburst_i=0;
    reg [M*128-1:0] s_wdata_i=0;
    reg [M*16-1:0] s_wstrb_i=0;
    wire [M-1:0] s_awready_o,s_wready_o,s_bvalid_o,s_arready_o,s_rvalid_o,s_rlast_o;
    wire [M*4-1:0] s_bid_o,s_rid_o;
    wire [M*2-1:0] s_bresp_o,s_rresp_o;
    wire [M*128-1:0] s_rdata_o;
    wire m_awvalid_o,m_wvalid_o,m_wlast_o,m_bready_o,m_arvalid_o,m_rready_o,idle_o,fault_o;
    wire [7:0] fault_code_o;
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
    soc_axi128_arbiter #(.MASTERS(M)) dut(.*);
    reg [7:0] memory[0:8191],expected[0:8191];
    reg [127:0] wbuf[0:15];reg [15:0] wmask[0:15];reg wlast[0:15];
    reg aw_owned=0,committed=0,reading=0;
    reg [31:0] aw_address,ar_address;
    reg [3:0] aw_id,ar_id;
    integer aw_beats=0,w_count=0,b_delay=0,r_index=0,r_beats=0,error_mode=0,slave_mode=0;
    integer ticks=0,aw_count=0,b_count=0,ar_count=0,checks=0,w_before_aw=0;
    integer grants[0:M-1],waiting_grants[0:M-1];integer i,j,k,n,grant;
    reg [31:0] random_q=32'hf3a90d27;
    assign m_awready_i=rst_ni&&!aw_owned&&!m_bvalid_i&&b_delay==0&&random_q[1]&&(slave_mode!=1||w_count>=1);
    assign m_wready_i=rst_ni&&!committed&&!m_bvalid_i&&w_count<16&&random_q[3];
    assign m_arready_i=rst_ni&&!reading&&!m_rvalid_i&&random_q[5];
    always @(posedge clk_i)begin
        ticks<=ticks+1;random_q<={random_q[30:0],random_q[31]^random_q[21]^random_q[1]^random_q[0]};
        if(!rst_ni)begin
            aw_owned<=0;committed<=0;w_count<=0;b_delay<=0;m_bvalid_i<=0;reading<=0;m_rvalid_i<=0;
            for(n=0;n<M;n=n+1)waiting_grants[n]=0;
        end else begin
            grant=-1;
            for(n=0;n<M;n=n+1)if((s_awvalid_i[n]&&s_awready_o[n])||(s_arvalid_i[n]&&s_arready_o[n]))begin
                if(grant!=-1)$fatal(1,"multiple owner grants");grant=n;grants[n]=grants[n]+1;
            end
            if(grant!=-1)for(n=0;n<M;n=n+1)begin
                if(n==grant||!(s_awvalid_i[n]||s_arvalid_i[n]))waiting_grants[n]=0;
                else begin waiting_grants[n]=waiting_grants[n]+1;if(waiting_grants[n]>=M)$fatal(1,"round robin starvation");end
            end
            if(m_awvalid_o&&m_awready_i)begin
                if(m_awaddr_o<32'h80000000||m_awaddr_o>=32'h88000000||m_awlen_o>15||m_awsize_o!=4||m_awburst_o!=1||
                   m_awaddr_o[3:0]!=0||m_awaddr_o[11:0]+16*(m_awlen_o+1)>4096)$fatal(1,"illegal AXI AW escaped");
                aw_owned<=1;aw_address<=m_awaddr_o;aw_id<=m_awid_o;aw_beats<=m_awlen_o+1;aw_count<=aw_count+1;
            end
            if(m_wvalid_o&&m_wready_i)begin
                wbuf[w_count]<=m_wdata_o;wmask[w_count]<=m_wstrb_o;wlast[w_count]<=m_wlast_o;w_count<=w_count+1;
                if(!aw_owned)w_before_aw<=w_before_aw+1;
            end
            if(aw_owned&&w_count==aw_beats&&!committed)begin
                for(j=0;j<aw_beats;j=j+1)begin
                    if(wlast[j]!=(j==aw_beats-1))$fatal(1,"downstream WLAST not advertised count");
                    for(k=0;k<16;k=k+1)if(wmask[j][k])memory[(aw_address-32'h80000000+j*16+k)%8192]<=wbuf[j][k*8+:8];
                end
                committed<=1;b_delay<=9;
            end
            if(b_delay>1)b_delay<=b_delay-1;
            if(b_delay==1)begin b_delay<=0;m_bvalid_i<=1;m_bid_i<=error_mode==1?aw_id^4'h8:aw_id;m_bresp_i<=error_mode==2?2'd2:2'd0;end
            if(m_bvalid_i&&m_bready_o)begin m_bvalid_i<=0;aw_owned<=0;committed<=0;w_count<=0;b_count<=b_count+1;end
            if(m_arvalid_o&&m_arready_i)begin
                if(m_araddr_o<32'h80000000||m_araddr_o>=32'h88000000||m_arlen_o>15||m_arsize_o!=4||m_arburst_o!=1||
                   m_araddr_o[3:0]!=0||m_araddr_o[11:0]+16*(m_arlen_o+1)>4096)$fatal(1,"illegal AXI AR escaped");
                reading<=1;ar_address<=m_araddr_o;ar_id<=m_arid_o;r_beats<=m_arlen_o+1;r_index<=0;ar_count<=ar_count+1;
            end
            if(m_rvalid_i&&m_rready_o)m_rvalid_i<=0;
            if(reading&&(!m_rvalid_i||m_rready_o)&&random_q[7])begin
                for(k=0;k<16;k=k+1)m_rdata_i[k*8+:8]<=memory[(ar_address-32'h80000000+r_index*16+k)%8192];
                m_rvalid_i<=1;m_rid_i<=error_mode==3?ar_id^4'h8:ar_id;m_rresp_i<=error_mode==4?2'd2:2'd0;
                m_rlast_i<=(r_index==r_beats-1)^(error_mode==5);r_index<=r_index+1;if(r_index==r_beats-1)reading<=0;
            end
        end
    end
    reg aw_stall=0,ar_stall=0,w_stall=0;reg[48:0]aw_hold,ar_hold;reg[144:0]w_hold;
    reg [M-1:0] rb_stall=0,bb_stall=0;reg[134:0]rh[0:M-1];reg[5:0]bh[0:M-1];
    always @(posedge clk_i)if(rst_ni)begin
        if(aw_stall&&(!m_awvalid_o||{m_awaddr_o,m_awid_o,m_awlen_o,m_awsize_o,m_awburst_o}!==aw_hold))$fatal(1,"AW offer changed");
        if(ar_stall&&(!m_arvalid_o||{m_araddr_o,m_arid_o,m_arlen_o,m_arsize_o,m_arburst_o}!==ar_hold))$fatal(1,"AR offer changed");
        if(w_stall&&(!m_wvalid_o||{m_wdata_o,m_wstrb_o,m_wlast_o}!==w_hold))$fatal(1,"W offer changed");
        aw_stall<=m_awvalid_o&&!m_awready_i;aw_hold<={m_awaddr_o,m_awid_o,m_awlen_o,m_awsize_o,m_awburst_o};
        ar_stall<=m_arvalid_o&&!m_arready_i;ar_hold<={m_araddr_o,m_arid_o,m_arlen_o,m_arsize_o,m_arburst_o};
        w_stall<=m_wvalid_o&&!m_wready_i;w_hold<={m_wdata_o,m_wstrb_o,m_wlast_o};
        for(integer q=0;q<M;q=q+1)begin
            if(rb_stall[q]&&(!s_rvalid_o[q]||{s_rdata_o[q*128+:128],s_rid_o[q*4+:4],s_rresp_o[q*2+:2],s_rlast_o[q]}!==rh[q]))$fatal(1,"R response changed owner=%0d",q);
            if(bb_stall[q]&&(!s_bvalid_o[q]||{s_bid_o[q*4+:4],s_bresp_o[q*2+:2]}!==bh[q]))$fatal(1,"B response changed owner=%0d",q);
            rb_stall[q]<=s_rvalid_o[q]&&!s_rready_i[q];rh[q]<={s_rdata_o[q*128+:128],s_rid_o[q*4+:4],s_rresp_o[q*2+:2],s_rlast_o[q]};
            bb_stall[q]<=s_bvalid_o[q]&&!s_bready_i[q];bh[q]<={s_bid_o[q*4+:4],s_bresp_o[q*2+:2]};
        end
    end else begin aw_stall<=0;ar_stall<=0;w_stall<=0;rb_stall<=0;bb_stall<=0;end
    task reset;begin
        @(negedge clk_i);rst_ni=0;healthy_i=1;s_awvalid_i=0;s_arvalid_i=0;s_wvalid_i=0;s_bready_i=0;s_rready_i=0;
        repeat(4)@(negedge clk_i);rst_ni=1;repeat(3)@(negedge clk_i);if(!idle_o||fault_o)$fatal(1,"reset");
    end endtask
    task automatic write_tx(input integer master,input[31:0]addr,input integer beats,input integer seed,input integer response,input bit broken_last);
        integer b,c;
        begin
            fork
                begin
                    repeat(3)@(negedge clk_i);s_awaddr_i[master*32+:32]=addr;s_awid_i[master*4+:4]=master+1;
                    s_awlen_i[master*8+:8]=beats-1;s_awsize_i[master*3+:3]=4;s_awburst_i[master*2+:2]=1;s_awvalid_i[master]=1;
                    do @(posedge clk_i);while(!s_awready_o[master]);@(negedge clk_i);s_awvalid_i[master]=0;
                end
                begin
                    for(b=0;b<beats;b=b+1)begin
                        @(negedge clk_i);for(c=0;c<16;c=c+1)s_wdata_i[master*128+c*8+:8]=(seed+b*16+c*3)&255;
                        s_wstrb_i[master*16+:16]=16'h5ad7^(b*37);s_wlast_i[master]=(b==beats-1)^broken_last;s_wvalid_i[master]=1;
                        do @(posedge clk_i);while(!s_wready_o[master]);
                        for(c=0;c<16;c=c+1)if(response==0&&s_wstrb_i[master*16+c])expected[(addr-32'h80000000+b*16+c)%8192]=s_wdata_i[master*128+c*8+:8];
                        @(negedge clk_i);s_wvalid_i[master]=0;
                    end
                end
            join
            while(!s_bvalid_o[master])@(negedge clk_i);
            if(s_bid_o[master*4+:4]!==master+1||s_bresp_o[master*2+:2]!==response)$fatal(1,"B owner/response master=%0d got=%0d",master,s_bresp_o[master*2+:2]);
            repeat(7)@(negedge clk_i);s_bready_i[master]=1;@(negedge clk_i);s_bready_i[master]=0;checks=checks+1;
        end
    endtask
    task automatic read_tx(input integer master,input[31:0]addr,input integer beats,input integer response);
        integer b,c;
        begin
            @(negedge clk_i);s_araddr_i[master*32+:32]=addr;s_arid_i[master*4+:4]=master+1;
            s_arlen_i[master*8+:8]=beats-1;s_arsize_i[master*3+:3]=4;s_arburst_i[master*2+:2]=1;s_arvalid_i[master]=1;
            do @(posedge clk_i);while(!s_arready_o[master]);@(negedge clk_i);s_arvalid_i[master]=0;b=0;
            while(b<beats)begin
                @(negedge clk_i);s_rready_i[master]=random_q[master+9];
                @(posedge clk_i);if(s_rvalid_o[master]&&s_rready_i[master])begin
                    if(s_rid_o[master*4+:4]!==master+1||s_rresp_o[master*2+:2]!==response||s_rlast_o[master]!==(b==beats-1))$fatal(1,"R owner/response/LAST master=%0d beat=%0d",master,b);
                    for(c=0;c<16;c=c+1)if(response==0&&s_rdata_o[master*128+c*8+:8]!==expected[(addr-32'h80000000+b*16+c)%8192])$fatal(1,"byte memory master=%0d beat=%0d byte=%0d",master,b,c);
                    b=b+1;
                end
            end
            @(negedge clk_i);s_rready_i[master]=0;checks=checks+1;
        end
    endtask
    task automatic traffic(input integer master);integer round,beats;reg[31:0]addr;begin
        for(round=0;round<6;round=round+1)begin
            addr=32'h80000000+master*2048+round*256;beats=round==0?1:round==1?16:1+(round*3)%16;
            write_tx(master,addr,beats,master*71+round,0,0);read_tx(master,addr,beats,0);
        end
    end endtask
    initial begin
        for(i=0;i<8192;i=i+1)begin memory[i]=(i*5)&255;expected[i]=(i*5)&255;end
        for(i=0;i<M;i=i+1)begin grants[i]=0;waiting_grants[i]=0;end
        reset;slave_mode=1;
        fork traffic(0);traffic(1);begin if(M==3)traffic(2);end
            begin wait(m_awvalid_o);@(negedge clk_i);healthy_i=0;repeat(17)@(negedge clk_i);healthy_i=1;end
        join
        if(fault_o||!idle_o||w_before_aw==0||aw_count!=b_count)$fatal(1,"mixed traffic retirement");
        for(i=0;i<M;i=i+1)if(grants[i]!=12)$fatal(1,"grant fairness coverage");
        for(i=1;i<=2;i=i+1)begin reset;error_mode=i;write_tx(1,32'h80000000,2,60+i,2,0);if(!fault_o)$fatal(1,"B error not latched");end
        for(i=3;i<=5;i=i+1)begin reset;error_mode=i;read_tx(M-1,32'h80000000,2,2);if(!fault_o)$fatal(1,"R error not latched");end
        reset;error_mode=0;write_tx(0,32'h80000000,2,70,2,1);if(!fault_o)$fatal(1,"source WLAST not latched");
        reset;read_tx(0,32'h7ffffff0,1,3);if(!fault_o)$fatal(1,"bad range accepted");
        reset;read_tx(1,32'h87fffff0,2,3);
        reset;read_tx(M-1,32'h80000ff0,2,3);
        reset;write_tx(0,32'h80000000,17,90,3,0);
        if(checks!=12*M+10)$fatal(1,"arbiter case count %0d",checks);
        $display("PASS SOC_AXI128_ARBITER masters=%0d checks=%0d AW=%0d B=%0d AR=%0d WbeforeAW=%0d",M,checks,aw_count,b_count,ar_count,w_before_aw);$finish;
    end
    initial begin #2000000;$fatal(1,"arbiter watchdog checks=%0d",checks);end
endmodule

// The production three-lane fabric, with its one real AXI128/HMIC256 bridge.
module tb_soc_ddr_fabric;
    reg clk_i=0;always #4 clk_i=~clk_i;
    reg rst_ni=0,healthy_i=1,init_done_i=1;
    reg [2:0]s_awvalid_i=0,s_wvalid_i=0,s_wlast_i=0,s_bready_i=0,s_arvalid_i=0,s_rready_i=0;
    reg [95:0]s_awaddr_i=0,s_araddr_i=0;reg[11:0]s_awid_i=0,s_arid_i=0;
    reg [23:0]s_awlen_i=0,s_arlen_i=0;reg[8:0]s_awsize_i=0,s_arsize_i=0;
    reg [5:0]s_awburst_i=0,s_arburst_i=0;reg[383:0]s_wdata_i=0;reg[47:0]s_wstrb_i=0;
    wire [2:0]s_awready_o,s_wready_o,s_bvalid_o,s_arready_o,s_rvalid_o,s_rlast_o;
    wire [11:0]s_bid_o,s_rid_o;wire[5:0]s_bresp_o,s_rresp_o;wire[383:0]s_rdata_o;
    wire idle_o,fault_o;wire[7:0]fault_code_o;
    wire [27:0]h_awaddr,h_araddr;wire[3:0]h_awlen,h_arlen,h_awid,h_arid;
    wire h_awvalid,h_arvalid;wire h_awready,h_arready,h_wready,h_wlast;wire[3:0]h_wid;
    wire[255:0]h_wdata;wire[31:0]h_wstrb;
    reg[255:0]h_rdata=0;reg[3:0]h_rid=0;reg h_rvalid=0,h_rlast=0;
    soc_ddr_fabric #(.NATIVE_TIMEOUT_CYCLES(1000)) dut(.*);
    reg[7:0]memory[0:1023];reg writing=0,reading=0;reg[31:0]wa,ra;reg[3:0]wid;
    integer wn=0,rn=0,wi=0,ri=0,cycles=0,aw_count=0,ar_count=0,k;
    wire awf=h_awvalid&&h_awready,arf=h_arvalid&&h_arready;
    assign h_awready=rst_ni&&!writing&&!reading&&!h_rvalid&&cycles%3!=0;
    assign h_arready=rst_ni&&!writing&&!reading&&!h_rvalid&&!h_awvalid&&cycles%4!=0;
    assign h_wready=rst_ni&&(writing||awf)&&cycles%5!=0;
    assign h_wlast=writing?wi+1==wn:h_awlen==0;
    assign h_wid=writing?wid:h_awid;
    wire[31:0]write_address=writing?wa+32*wi:{2'd0,h_awaddr,2'd0};
    always @(posedge clk_i)begin
        cycles<=cycles+1;
        if(!rst_ni)begin writing<=0;reading<=0;h_rvalid<=0;end
        else begin
            h_rvalid<=0;
            if(awf)begin writing<=1;wa<={2'd0,h_awaddr,2'd0};wn<=h_awlen+1;wi<=0;wid<=h_awid;aw_count<=aw_count+1;end
            if(h_wready)begin
                for(k=0;k<32;k=k+1)if(h_wstrb[k])memory[write_address+k]<=h_wdata[k*8+:8];
                wi<=(writing?wi:0)+1;if(h_wlast)writing<=0;
            end
            if(arf)begin reading<=1;ra<={2'd0,h_araddr,2'd0};rn<=h_arlen+1;ri<=0;h_rid<=h_arid;ar_count<=ar_count+1;end
            if(reading&&cycles%3!=1)begin
                h_rvalid<=1;h_rlast<=ri+1==rn;
                for(k=0;k<32;k=k+1)h_rdata[k*8+:8]<=memory[ra+32*ri+k];
                ri<=ri+1;if(ri+1==rn)reading<=0;
            end
            if(fault_o)$fatal(1,"fabric fault=%h",fault_code_o);
        end
    end
    task automatic write_lane(input integer lane,input[31:0]addr,input integer seed);integer b;begin
        @(negedge clk_i);s_awaddr_i[lane*32+:32]=addr;s_awid_i[lane*4+:4]=lane+1;s_awlen_i[lane*8+:8]=0;
        s_awsize_i[lane*3+:3]=4;s_awburst_i[lane*2+:2]=1;s_awvalid_i[lane]=1;
        do @(posedge clk_i);while(!s_awready_o[lane]);@(negedge clk_i);s_awvalid_i[lane]=0;
        if(lane==0)healthy_i=0;
        for(b=0;b<16;b=b+1)s_wdata_i[lane*128+b*8+:8]=seed+b;
        s_wvalid_i[lane]=1;s_wlast_i[lane]=1;s_wstrb_i[lane*16+:16]=16'hffff;
        do @(posedge clk_i);while(!s_wready_o[lane]);@(negedge clk_i);s_wvalid_i[lane]=0;
        while(!s_bvalid_o[lane])@(negedge clk_i);
        if(s_bresp_o[lane*2+:2]!=0||s_bid_o[lane*4+:4]!=lane+1)$fatal(1,"fabric B");
        repeat(4)@(negedge clk_i);s_bready_i[lane]=1;@(negedge clk_i);s_bready_i[lane]=0;healthy_i=1;
    end endtask
    integer i,b,c;
    initial begin
        for(i=0;i<1024;i=i+1)memory[i]=8'ha5;
        repeat(5)@(negedge clk_i);rst_ni=1;repeat(3)@(negedge clk_i);
        write_lane(0,32'h80000000,16);write_lane(1,32'h80000010,112);
        @(negedge clk_i);s_araddr_i[64+:32]=32'h80000000;s_arid_i[8+:4]=3;s_arlen_i[16+:8]=1;s_arsize_i[6+:3]=4;s_arburst_i[4+:2]=1;s_arvalid_i[2]=1;
        do @(posedge clk_i);while(!s_arready_o[2]);@(negedge clk_i);s_arvalid_i[2]=0;b=0;
        while(b<2)begin
            @(negedge clk_i);s_rready_i[2]=cycles%4!=1;
            @(posedge clk_i);if(s_rvalid_o[2]&&s_rready_i[2])begin
                if(s_rid_o[8+:4]!=3||s_rresp_o[4+:2]!=0||s_rlast_o[2]!=(b==1))$fatal(1,"fabric R");
                for(c=0;c<16;c=c+1)if(s_rdata_o[256+c*8+:8]!==((b==0?16:112)+c))$fatal(1,"native fabric byte");
                b=b+1;
            end
        end
        @(negedge clk_i);s_rready_i[2]=0;repeat(4)@(negedge clk_i);
        if(!idle_o||aw_count!=2||ar_count!=3)$fatal(1,"native bridge retirement/readback count");
        $display("PASS SOC_DDR_FABRIC lanes=3 nativeAW=%0d nativeAR=%0d",aw_count,ar_count);$finish;
    end
    initial begin #100000;$fatal(1,"fabric watchdog");end
endmodule
