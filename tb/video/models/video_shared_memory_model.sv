`timescale 1ns/1ps
// Test-only byte memory for the three public frame/input slots. Literal window
// decoding is independent of AXI/native lane logic in the production bridge.
module video_shared_memory_model #(
    parameter integer W=30,H=20,PT=2,PB=1,GAPS=1
)(
    input wire clk,reset_n,
    input wire [27:0] h_awaddr,h_araddr,input wire [3:0] h_awlen,h_arlen,h_awid,h_arid,
    input wire h_awvalid,h_arvalid,output wire h_awready,h_arready,h_wready,h_rvalid,
    input wire [255:0] h_wdata,input wire [31:0] h_wstrb,output wire [255:0] h_rdata,
    output wire [3:0] h_wid,h_rid,output wire h_wlast,h_rlast,
    output integer aw_commands,ar_commands,write_bytes,read_beats
);
    localparam integer RS=(W*3+15)/16*16,PS=(W/2*3+15)/16*16,IS=(W*2/5+15)/16*16;
    localparam integer RB=RS*H,VB=PS*(H/2),IB=3*IS*(H*2/5+PT+PB),SPAN=RB+VB+IB;
    reg [7:0] memory[0:3*SPAN-1];
    integer ticks=0,wi=0,ri=0,wn=0,rn=0;
    reg writing=0,reading=0;reg [27:0] wa=0,ra=0;reg [3:0] wid=0,rid=0;
    wire aw=h_awvalid&&h_awready,ar=h_arvalid&&h_arready;
    assign h_awready=reset_n&&!writing&&!reading&&(!GAPS||ticks%5==1);
    assign h_arready=reset_n&&!writing&&!reading&&(!GAPS||ticks%7==2);
    assign h_wready=reset_n&&(writing||aw)&&(!GAPS||ticks%4!=0);
    assign h_rvalid=reset_n&&(reading||ar)&&(!GAPS||ticks%3!=0);
    assign h_wid=writing?wid:h_awid;assign h_rid=reading?rid:h_arid;
    assign h_wlast=writing?wi==wn-1:h_awlen==0;assign h_rlast=reading?ri==rn-1:h_arlen==0;
    function automatic integer index_of(input [31:0] address);
        integer slot;reg [31:0] raw,input_base;
        begin
            index_of=-1;
            for(slot=0;slot<3;slot=slot+1)begin
                raw=32'h82000000+slot*32'h200000;input_base=32'h82800000+slot*32'h50000;
                if(address>=raw&&address<raw+RB)index_of=slot*SPAN+int'(address-raw);
                else if(address>=raw+32'h160000&&address<raw+32'h160000+VB)
                    index_of=slot*SPAN+RB+int'(address-raw-32'h160000);
                else if(address>=input_base&&address<input_base+IB)index_of=slot*SPAN+RB+VB+int'(address-input_base);
            end
        end
    endfunction
    function automatic [7:0] peek(input [31:0] address);
        integer idx;
        begin idx=index_of(address);peek=idx<0?8'ha5:memory[idx];end
    endfunction
    function automatic [255:0] fetch(input [27:0] address,input integer revision);
        integer lane;
        begin for(lane=0;lane<32;lane=lane+1)fetch[lane*8+:8]=peek(32'h80000000+({4'd0,address}<<2)+lane);end
    endfunction
    assign h_rdata=fetch(reading?ra:h_araddr,ticks);
    integer lane,idx,i;
    reg [31:0] byte_address;
    always @(posedge clk)begin
        if(!reset_n)begin
            ticks<=0;writing<=0;reading<=0;wi<=0;ri<=0;wn<=0;rn<=0;wa<=0;ra<=0;wid<=0;rid<=0;
            aw_commands<=0;ar_commands<=0;write_bytes=0;read_beats<=0;
            for(i=0;i<3*SPAN;i=i+1)memory[i]=8'ha5;
        end else begin
            ticks<=ticks+1;
            if(aw)begin writing<=1;wa<=h_awaddr;wid<=h_awid;wn<=int'(h_awlen)+1;wi<=0;aw_commands<=aw_commands+1;end
            if((writing||aw)&&h_wready)begin
                for(lane=0;lane<32;lane=lane+1)if(h_wstrb[lane])begin
                    byte_address=32'h80000000+({4'd0,(writing?wa:h_awaddr)}<<2)+lane;idx=index_of(byte_address);
                    if(idx<0)$fatal(1,"SHARED_NATIVE_GUARD_WRITE %h",byte_address);
                    memory[idx]=h_wdata[lane*8+:8];write_bytes=write_bytes+1;
                end
                wa<=(writing?wa:h_awaddr)+8;wi<=(writing?wi:0)+1;
                if(writing?wi==wn-1:h_awlen==0)writing<=0;
            end
            if(ar)begin reading<=1;ra<=h_araddr;rid<=h_arid;rn<=int'(h_arlen)+1;ri<=0;ar_commands<=ar_commands+1;end
            if((reading||ar)&&h_rvalid)begin
                read_beats<=read_beats+1;ra<=(reading?ra:h_araddr)+8;ri<=(reading?ri:0)+1;
                if(reading?ri==rn-1:h_arlen==0)reading<=0;
            end
        end
    end
endmodule
