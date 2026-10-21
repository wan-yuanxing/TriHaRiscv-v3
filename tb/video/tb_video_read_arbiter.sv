`timescale 1ns/1ps
module tb_video_read_arbiter #(parameter integer CASE_ID=0);
    reg clk=0,reset_n=0,online=1,memory_fault=0,display_urgent=1;
    always #4 clk=~clk;
    reg [3:0] d_arid=0,a_arid=9;reg [31:0] d_araddr=0,a_araddr=0;
    reg [7:0] d_arlen=3,a_arlen=3;reg [2:0] d_arsize=4,a_arsize=4;
    reg [1:0] d_arburst=1,a_arburst=1;reg d_arvalid=0,a_arvalid=0;
    wire d_arready,a_arready,d_rvalid,a_rvalid,d_rlast,a_rlast;reg d_rready=0,a_rready=0;
    wire [3:0] d_rid,a_rid;wire [127:0] d_rdata,a_rdata;wire [1:0] d_rresp,a_rresp;
    wire [3:0] m_arid;wire [31:0] m_araddr;wire [7:0] m_arlen;wire [2:0] m_arsize;wire [1:0] m_arburst;
    wire m_arvalid,m_rready;reg m_arready=0,m_rvalid=0,m_rlast=0;
    reg [3:0] m_rid=0;reg [127:0] m_rdata=0;reg [1:0] m_rresp=0;
    wire fault,port_drained;wire [7:0] fault_code;wire [31:0] raw_grants,asset_grants;
    video_read_arbiter dut(.*);
    integer ticks=0,ds=0,as_=0,dc=0,ac=0,di=0,ai=0,mi=0,left=0,masters=0,accepted=0,streak=0;
    reg dp=0,ap=0,active=0,last_owner=1,held=0,early=0;
    reg [31:0] address=0;reg [3:0] identity=0;reg [48:0] saved_ar;
    function automatic [127:0] pattern(input [31:0] addr);
        pattern={addr^32'hb578940e,addr+32'h12457c99,~addr,addr*32'h91d73b55};
    endfunction
    wire failing=CASE_ID>=3&&CASE_ID!=12&&CASE_ID!=15;
    wire [31:0] d_expected=32'h82000000+dc*64+di*16,a_expected=32'h82600000+ac*64+ai*16;
    always @(negedge clk)begin
        if(reset_n)begin
            m_arready=(ticks%5!=0)&&(!((CASE_ID==3||CASE_ID==7||CASE_ID==13)&&ticks<40));
            d_rready=ticks%7!=0;a_rready=ticks%3!=0;
            if(!dp&&!d_arvalid&&ds<(failing?1:12)&&!fault)begin d_arvalid=1;d_araddr=32'h82000000+ds*64;end
            if(!ap&&!a_arvalid&&as_<(failing?1:12)&&!fault)begin a_arvalid=1;a_araddr=32'h82600000+as_*64;end
            if(CASE_ID==8&&d_arvalid)d_araddr='x;
            if(CASE_ID==9&&d_arvalid)d_arsize=3;
            if(!m_rvalid&&active&&ticks%4!=0)begin
                m_rvalid=1;m_rdata=pattern(address+mi*16);m_rid=identity;m_rresp=0;m_rlast=left==1;
                if(CASE_ID==4&&mi==1)m_rid=identity^1;
                if((CASE_ID==6||CASE_ID==11)&&mi==1)m_rresp=2;
                if(CASE_ID==5&&mi==0)m_rlast=1;
                if(CASE_ID==10&&mi==1)m_rdata[75]=1'bx;
            end
            if(CASE_ID==7&&m_arvalid&&!m_arready&&!early)begin
                early=1;m_rvalid=1;m_rdata=pattern(m_araddr);m_rid=m_arid;m_rresp=0;m_rlast=0;
            end
            if(CASE_ID==14&&m_arvalid)begin m_rvalid=1'bx;end
            if((CASE_ID==3||CASE_ID==13)&&m_arvalid&&ticks>15)begin
                if(CASE_ID==3)online=0;else memory_fault=1;
            end
        end
    end
    always @(posedge clk)if(reset_n)begin
        ticks<=ticks+1;
        if(held&&{m_arvalid,m_arid,m_araddr,m_arlen,m_arsize,m_arburst}!=={1'b1,saved_ar})$fatal(1,"READ_ARB_POSTED_AR");
        held<=m_arvalid&&!m_arready;saved_ar<={m_arid,m_araddr,m_arlen,m_arsize,m_arburst};
        if(d_rvalid&&a_rvalid)$fatal(1,"READ_ARB_LEAK_BOTH");
        if(d_arready&&a_arready)$fatal(1,"READ_ARB_DOUBLE_GRANT");
        if(d_arvalid&&d_arready)begin
            if(d_arvalid&&a_arvalid)begin
                if(display_urgent&&streak>=4)$fatal(1,"READ_ARB_QUOTA");
                if(!display_urgent&&!last_owner)$fatal(1,"READ_ARB_ROUND_ROBIN");
            end
            if(streak<4)streak<=streak+1;last_owner<=0;ds<=ds+1;dp<=1;d_arvalid<=0;accepted<=accepted+1;
        end
        if(a_arvalid&&a_arready)begin
            if(d_arvalid&&a_arvalid&&!display_urgent&&last_owner)$fatal(1,"READ_ARB_ROUND_ROBIN");
            streak<=0;last_owner<=1;as_<=as_+1;ap<=1;a_arvalid<=0;accepted<=accepted+1;
        end
        if(m_arvalid&&m_arready)begin
            if(active||m_arlen!=3||m_arsize!=4||m_arburst!=1)$fatal(1,"READ_ARB_MASTER_DESCRIPTOR");
            active<=1;left<=4;mi<=0;address<=m_araddr;identity<=m_arid;masters<=masters+1;
        end
        if(m_rvalid&&m_rready)begin
            if(!active)$fatal(1,"READ_ARB_MASTER_NO_OWNER");
            mi<=mi+1;left<=left-1;m_rvalid<=0;if(left==1)active<=0;
        end
        if(d_rvalid&&d_rready)begin
            if(!dp||(CASE_ID!=10&&d_rdata!==pattern(d_expected)))$fatal(1,"READ_ARB_RAW_ROUTING");
            if(d_rid!==((CASE_ID==4&&di==1)?d_arid^1:d_arid)||d_rresp!==2'((CASE_ID==6||CASE_ID==11)&&di==1?2:0)||d_rlast!==((CASE_ID==5&&di==0)||di==3))$fatal(1,"READ_ARB_RAW_RESPONSE");
            if(di==3)begin di<=0;dc<=dc+1;dp<=0;end else di<=di+1;
        end
        if(a_rvalid&&a_rready)begin
            if(!ap||a_rdata!==pattern(a_expected)||a_rid!==a_arid||a_rresp!==0||a_rlast!==(ai==3))$fatal(1,"READ_ARB_ASSET_ROUTING");
            if(ai==3)begin ai<=0;ac<=ac+1;ap<=0;end else ai<=ai+1;
        end
    end
    initial begin
        if(CASE_ID==1)display_urgent=0;if(CASE_ID==2)begin d_arid=3;a_arid=3;end
        repeat(4)@(negedge clk);reset_n=1;
        if(!failing)begin
            wait(dc==12&&ac==12);repeat(5)@(negedge clk);
            if(fault||!port_drained||raw_grants!=12||asset_grants!=12||masters!=24)$fatal(1,"READ_ARB_NORMAL");
        end else begin
            wait(fault);
            if(CASE_ID==8||CASE_ID==9||CASE_ID==14)begin repeat(20)@(negedge clk);if((CASE_ID!=14&&masters!=0)||(CASE_ID==14&&port_drained))$fatal(1,"READ_ARB_INVALID");end
            else begin
                wait(dc+ac==1);repeat(5)@(negedge clk);
                if(masters!=1||accepted!=1)$fatal(1,"READ_ARB_NEW_AFTER_FAULT");
                if((CASE_ID==4||CASE_ID==5||CASE_ID==7||CASE_ID==10)&&port_drained)$fatal(1,"READ_ARB_FALSE_DRAIN");
                if(CASE_ID==11)begin
                    if(!port_drained)$fatal(1,"READ_ARB_DRAIN_BASELINE");
                    @(negedge clk);m_rvalid=1;m_rid=0;m_rlast=1;m_rresp=0;m_rdata=0;
                    repeat(3)@(negedge clk);if(port_drained)$fatal(1,"READ_ARB_LATE_STRAY");
                end
            end
        end
        $display("READ_ARBITER_PASS case=%0d raw=%0d asset=%0d masters=%0d code=%0d",CASE_ID,raw_grants,asset_grants,masters,fault_code);$finish;
    end
    initial begin #1000000;$fatal(1,"READ_ARB_TIMEOUT case=%0d",CASE_ID);end
endmodule
