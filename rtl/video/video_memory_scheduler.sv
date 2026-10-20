`timescale 1ns/1ps
`default_nettype none
// Video-local, one total outstanding transaction. A source descriptor is
// accepted into registers before it is advertised to the exclusive DDR bridge.
// Never preempt published AW/AR/W/B/R. Faults stop new grants, not retirement.
module video_memory_scheduler #(parameter integer MAX_READ_BURSTS=4)(
    input wire clk,reset_n,online,memory_fault,display_urgent,
    input wire [3:0] c_awid,d_arid,
    input wire [31:0] c_awaddr,d_araddr,
    input wire [7:0] c_awlen,d_arlen,
    input wire [2:0] c_awsize,d_arsize,
    input wire [1:0] c_awburst,d_arburst,
    input wire c_awvalid,output wire c_awready,
    input wire [127:0] c_wdata,input wire [15:0] c_wstrb,input wire c_wlast,c_wvalid,
    output wire c_wready,output wire [3:0] c_bid,output wire [1:0] c_bresp,
    output wire c_bvalid,input wire c_bready,
    input wire d_arvalid,output wire d_arready,
    output wire [3:0] d_rid,output wire [127:0] d_rdata,output wire [1:0] d_rresp,
    output wire d_rlast,d_rvalid,input wire d_rready,
    output reg [3:0] m_awid,m_arid,output reg [31:0] m_awaddr,m_araddr,
    output reg [7:0] m_awlen,m_arlen,output reg [2:0] m_awsize,m_arsize,
    output reg [1:0] m_awburst,m_arburst,
    output wire m_awvalid,input wire m_awready,
    output wire [127:0] m_wdata,output wire [15:0] m_wstrb,output wire m_wlast,m_wvalid,
    input wire m_wready,input wire [3:0] m_bid,input wire [1:0] m_bresp,
    input wire m_bvalid,output wire m_bready,
    output wire m_arvalid,input wire m_arready,
    input wire [3:0] m_rid,input wire [127:0] m_rdata,input wire [1:0] m_rresp,
    input wire m_rlast,m_rvalid,output wire m_rready,
    output reg fault,output reg [7:0] fault_code,output wire busy,port_drained,
    output reg [31:0] read_grants,write_grants
);
    localparam [2:0] IDLE=0,WADDR=1,WDATA=2,BRESP=3,RADDR=4,RDATA=5;
    localparam integer QUOTA=MAX_READ_BURSTS>=1&&MAX_READ_BURSTS<=16?MAX_READ_BURSTS:1;
    reg [2:0] state;
    reg seen_online,last_read;
    reg [4:0] read_streak;
    reg [8:0] remaining;
    wire wants_read=d_arvalid===1'b1,wants_write=c_awvalid===1'b1;
    wire choose_read=wants_read&&(!wants_write||
        ((display_urgent===1'b1) ? read_streak<QUOTA : !last_read));
    wire can_accept=reset_n&&state==IDLE&&!fault&&online===1'b1&&memory_fault===1'b0&&
        m_bvalid===1'b0&&m_rvalid===1'b0;
    assign c_awready=can_accept&&wants_write&&!choose_read;
    assign d_arready=can_accept&&choose_read;
    wire take_write=c_awvalid&&c_awready,take_read=d_arvalid&&d_arready;
    assign m_awvalid=reset_n&&state==WADDR;
    assign m_arvalid=reset_n&&state==RADDR;
    assign m_wvalid=reset_n&&state==WDATA&&c_wvalid;
    assign m_wdata=c_wdata;assign m_wstrb=c_wstrb;assign m_wlast=c_wlast;
    assign c_wready=reset_n&&state==WDATA&&m_wready;
    assign c_bid=m_bid;assign c_bresp=m_bresp;
    assign c_bvalid=reset_n&&state==BRESP&&m_bvalid;
    assign m_bready=reset_n&&(state==BRESP?c_bready:state==IDLE);
    assign d_rid=m_rid;assign d_rdata=m_rdata;assign d_rresp=m_rresp;assign d_rlast=m_rlast;
    assign d_rvalid=reset_n&&state==RDATA&&m_rvalid;
    assign m_rready=reset_n&&(state==RDATA?d_rready:state==IDLE);
    assign busy=state!=IDLE;
    assign port_drained=reset_n&&state==IDLE&&m_bvalid===1'b0&&m_rvalid===1'b0;
    wire w_take=m_wvalid&&m_wready,r_take=d_rvalid&&d_rready;
    // A legal peer may raise its response on the final request handshake;
    // it is backpressured here until the registered response phase starts.
    wire b_phase=state==BRESP||(state==WDATA&&w_take&&remaining==1);
    wire r_phase=state==RDATA||(state==RADDR&&m_arvalid&&m_arready);
    reg [7:0] fault_now;
    always @* begin
        fault_now=0;
        if(seen_online&&online!==1'b1)fault_now=1;
        else if(memory_fault!==1'b0)fault_now=2;
        else if(m_bvalid===1'b1&&!b_phase)fault_now=3;
        else if(m_rvalid===1'b1&&!r_phase)fault_now=4;
        else if(m_bvalid===1'b1&&m_bid!==m_awid)fault_now=5;
        else if(m_rvalid===1'b1&&m_rid!==m_arid)fault_now=6;
        else if(w_take&&c_wlast!==(remaining==1))fault_now=7;
        else if(state==RDATA&&m_rvalid===1'b1&&m_rlast!==(remaining==1))fault_now=8;
        else if((take_write&&(^({c_awid,c_awaddr,c_awlen,c_awsize,c_awburst}))===1'bx)||
                (take_read&&(^({d_arid,d_araddr,d_arlen,d_arsize,d_arburst}))===1'bx))fault_now=9;
        else if((m_bvalid!==1'b0&&m_bvalid!==1'b1)||(m_rvalid!==1'b0&&m_rvalid!==1'b1)||
                (m_awvalid&&m_awready!==1'b0&&m_awready!==1'b1)||
                (m_arvalid&&m_arready!==1'b0&&m_arready!==1'b1)||
                (state==WDATA&&c_wvalid!==1'b0&&c_wvalid!==1'b1)||
                (state==WDATA&&c_wvalid===1'b1&&m_wready!==1'b0&&m_wready!==1'b1))fault_now=10;
        else if((m_bvalid===1'b1&&(^m_bresp)===1'bx)||
                (m_rvalid===1'b1&&(^({m_rdata,m_rresp,m_rlast}))===1'bx)||
                (w_take&&(^({c_wdata,c_wstrb}))===1'bx))fault_now=11;
    end
    initial if(MAX_READ_BURSTS<1||MAX_READ_BURSTS>16)$fatal(1,"scheduler quota requires 1..16");
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=IDLE;seen_online<=0;last_read<=0;read_streak<=0;remaining<=0;
            m_awid<=0;m_arid<=0;m_awaddr<=0;m_araddr<=0;m_awlen<=0;m_arlen<=0;
            m_awsize<=0;m_arsize<=0;m_awburst<=0;m_arburst<=0;
            fault<=0;fault_code<=0;read_grants<=0;write_grants<=0;
        end else begin
            if(online===1'b1)seen_online<=1;
            if(!fault&&fault_now!=0)begin fault<=1;fault_code<=fault_now;end
            case(state)
                IDLE:if(take_write)begin
                    m_awid<=c_awid;m_awaddr<=c_awaddr;m_awlen<=c_awlen;m_awsize<=c_awsize;m_awburst<=c_awburst;
                    remaining<={1'b0,c_awlen}+9'd1;last_read<=0;read_streak<=0;
                    write_grants<=write_grants+1'b1;state<=WADDR;
                end else if(take_read)begin
                    m_arid<=d_arid;m_araddr<=d_araddr;m_arlen<=d_arlen;m_arsize<=d_arsize;m_arburst<=d_arburst;
                    remaining<={1'b0,d_arlen}+9'd1;last_read<=1;
                    if(read_streak<QUOTA)read_streak<=read_streak+1'b1;
                    read_grants<=read_grants+1'b1;state<=RADDR;
                end
                WADDR:if(m_awready)state<=WDATA;
                WDATA:if(w_take)begin remaining<=remaining-1'b1;if(remaining==1)state<=BRESP;end
                BRESP:if(c_bvalid&&c_bready)state<=IDLE;
                RADDR:if(m_arready)state<=RDATA;
                RDATA:if(r_take)begin remaining<=remaining-1'b1;if(remaining==1)state<=IDLE;end
                default:begin end
            endcase
        end
    end
endmodule
`default_nettype wire
