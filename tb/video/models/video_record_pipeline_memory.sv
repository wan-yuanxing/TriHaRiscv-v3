`timescale 1ns/1ps
// Test-only packed byte store. Native read data is prepared once per valid
// beat, not recomputed from a multi-MiB memory on every core clock.
module video_record_pipeline_memory #(parameter integer H=600,GAPS=1,CORRUPT=0)(
    input wire clk,reset_n,input wire [95:0] slot_tags,
    input wire [27:0] h_awaddr,h_araddr,input wire [3:0] h_awlen,h_arlen,h_awid,h_arid,
    input wire h_awvalid,h_arvalid,output wire h_awready,h_arready,h_wready,
    output reg h_rvalid,output reg [255:0] h_rdata,output wire [3:0] h_wid,
    output reg [3:0] h_rid,output wire h_wlast,output reg h_rlast,
    input wire [255:0] h_wdata,input wire [31:0] h_wstrb,
    output integer write_bytes,read_beats,aw_commands,ar_commands
);
    localparam integer RB=2400*H,VB=1200*(H/2),IH=H*2/5+80,IB=960*IH;
    localparam integer SPAN=(RB+VB+IB+31)/32*32,WORDS=3*SPAN/32;
    reg [255:0] memory[0:WORDS-1];
    reg [7:0] asset[0:262143];string directory;integer asset_commands=0;
    initial begin if(!$value$plusargs("DIR=%s",directory))$fatal(1,"RECORD_MEMORY_DIR");$readmemh({directory,"/asset_bytes.hex"},asset);end
    // A word lazily starts a new coverage epoch when its frame tag changes.
    // Exact per-branch totals + no duplicate address + legal address bounds
    // prove every branch byte was written, including all-zero padding.
    reg [31:0] covered[0:WORDS-1],coverage_tag[0:WORDS-1];
    integer bytes_by_frame[0:7],raw_by_frame[0:7],preview_by_frame[0:7],input_by_frame[0:7];
    integer ticks=0,wi=0,wn=0,ri=0,rn=0;
    reg writing=0,reading=0,corrupted=0;reg [27:0] wa=0,ra=0;reg [3:0] wid=0,rid=0;
    assign h_awready=reset_n&&!writing&&!reading&&!h_rvalid&&(!GAPS||ticks%5==1);
    assign h_arready=reset_n&&!writing&&!reading&&!h_rvalid&&(!GAPS||ticks%7==2);
    assign h_wready=reset_n&&writing&&(!GAPS||ticks%4!=0);
    assign h_wid=wid;assign h_wlast=wi==wn-1;
    function automatic integer locate(input [31:0] address);
        integer s;reg [31:0] raw,inp;
        begin
            locate=-1;
            for(s=0;s<3;s=s+1)begin
                raw=32'h82000000+32'(s)*32'h200000;inp=32'h82800000+32'(s)*32'h50000;
                if(address>=raw&&address<raw+RB)locate=s*SPAN+int'(address-raw);
                if(address>=raw+32'h160000&&address<raw+32'h160000+VB)locate=s*SPAN+RB+int'(address-raw-32'h160000);
                if(address>=inp&&address<inp+IB)locate=s*SPAN+RB+VB+int'(address-inp);
            end
        end
    endfunction
    function automatic [7:0] peek(input [31:0] address);
        integer n;begin if(address>=32'h82600ff0&&address<32'h82640ff0)peek=asset[address-32'h82600ff0];else begin n=locate(address);peek=n<0?8'ha5:memory[n/32][(n%32)*8+:8];end end
    endfunction
    function automatic [7:0] channel(input integer x,y,c,tag);
        channel=8'(43*tag+(37+tag)*x+19*y+83*c+(x*y)/8);
    endfunction
    function automatic [7:0] expected(input integer local_index,tag);
        integer k,row,x,c,total,sx,sy,wx,wy,h0,h1;
        begin
            if(local_index<RB)begin row=local_index/2400;k=local_index%2400;x=k/3;c=k%3;expected=channel(x,row,c,tag);end
            else if(local_index<RB+VB)begin
                k=local_index-RB;row=k/1200;x=(k%1200)/3;c=k%3;
                total=int'(channel(2*x,2*row,c,tag))+int'(channel(2*x+1,2*row,c,tag))+
                    int'(channel(2*x,2*row+1,c,tag))+int'(channel(2*x+1,2*row+1,c,tag));expected=8'((total+2)/4);
            end else begin
                k=local_index-RB-VB;c=2-k/(320*IH);row=(k%(320*IH))/320;x=k%320;
                if(row<40||row>=40+H*2/5)expected=0;
                else begin
                    row=row-40;sx=(10*x+3)/4;sy=(10*row+3)/4;wx=x%2==0?3:1;wy=row%2==0?3:1;
                    h0=(4-wx)*int'(channel(sx,sy,c,tag))+wx*int'(channel(sx+1,sy,c,tag));
                    h1=(4-wx)*int'(channel(sx,sy+1,c,tag))+wx*int'(channel(sx+1,sy+1,c,tag));
                    expected=8'(((4-wy)*h0/4+wy*h1/4+2)/4);
                end
            end
        end
    endfunction
    integer i,lane,n,s,tag,local_index;reg [31:0] address;
    initial begin
        for(i=0;i<WORDS;i=i+1)begin memory[i]={32{8'ha5}};covered[i]=0;coverage_tag[i]=0;end
        for(i=0;i<8;i=i+1)begin bytes_by_frame[i]=0;raw_by_frame[i]=0;preview_by_frame[i]=0;input_by_frame[i]=0;end
    end
    always @(posedge clk)begin
        if(!reset_n)begin
            ticks<=0;writing<=0;reading<=0;wi<=0;wn<=0;ri<=0;rn<=0;wa<=0;ra<=0;wid<=0;rid<=0;
            h_rvalid<=0;h_rdata<=0;h_rid<=0;h_rlast<=0;corrupted<=0;
            write_bytes=0;read_beats=0;aw_commands=0;ar_commands=0;asset_commands=0;
        end else begin
            ticks<=ticks+1;h_rvalid<=0;
            if(h_awvalid&&h_awready)begin writing<=1;wa<=h_awaddr;wid<=h_awid;wi<=0;wn<=int'(h_awlen)+1;aw_commands=aw_commands+1;end
            if(writing&&h_wready)begin
                for(lane=0;lane<32;lane=lane+1)if(h_wstrb[lane])begin
                    address=32'h80000000+({4'd0,wa}<<2)+32'(lane);n=locate(address);
                    if(n<0)$fatal(1,"PIPELINE_GUARD_WRITE %h",address);
                    s=n/SPAN;local_index=n%SPAN;tag=int'(slot_tags[s*32+:32]);
                    if(tag<1||tag>7||h_wdata[lane*8+:8]!==expected(local_index,tag))
                        $fatal(1,"PIPELINE_WRITE_ORACLE address=%h tag=%0d got=%h expected=%h",address,tag,h_wdata[lane*8+:8],expected(local_index,tag));
                    if(coverage_tag[n/32]!=32'(tag))begin coverage_tag[n/32]=32'(tag);covered[n/32]=0;end
                    if(covered[n/32][n%32])$fatal(1,"PIPELINE_DUPLICATE_WRITE address=%h tag=%0d",address,tag);
                    covered[n/32][n%32]=1;
                    memory[n/32][(n%32)*8+:8]=h_wdata[lane*8+:8];
                    if(CORRUPT&&!corrupted)begin memory[n/32][(n%32)*8]=~memory[n/32][(n%32)*8];corrupted=1;end
                    write_bytes=write_bytes+1;bytes_by_frame[tag]=bytes_by_frame[tag]+1;
                    if(local_index<RB)raw_by_frame[tag]=raw_by_frame[tag]+1;
                    else if(local_index<RB+VB)preview_by_frame[tag]=preview_by_frame[tag]+1;
                    else input_by_frame[tag]=input_by_frame[tag]+1;
                end
                wa<=wa+8;wi<=wi+1;if(wi==wn-1)writing<=0;
            end
            if(h_arvalid&&h_arready)begin reading<=1;ra<=h_araddr;rid<=h_arid;ri<=0;rn<=int'(h_arlen)+1;ar_commands=ar_commands+1;if(h_araddr>=28'h980000&&h_araddr<28'ha00000)asset_commands=asset_commands+1;end
            if(reading&&(!GAPS||ticks%3!=0))begin
                for(lane=0;lane<32;lane=lane+1)h_rdata[lane*8+:8]<=peek(32'h80000000+({4'd0,ra}<<2)+32'(lane));
                h_rid<=rid;h_rlast<=ri==rn-1;h_rvalid<=1;read_beats=read_beats+1;
                ra<=ra+8;ri<=ri+1;if(ri==rn-1)reading<=0;
            end
        end
    end
endmodule
