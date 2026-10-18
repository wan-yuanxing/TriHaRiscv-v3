`timescale 1ns/1ps
`default_nettype none
// The affine byte map below is TEST DATA ONLY, deliberately not a calibrated
// model quantizer. It maps raw zero to 13 so zero-point assumptions are visible.
module tb_detect_input_dma #(parameter integer FW=15,FH=10,PH=4);
    localparam integer W=FW/5,AH=FH/5,ROW_BYTES=W*8,STRIDE=((ROW_BYTES+15)/16+1)*16;
    localparam integer GUARD=16,MEM_SIZE=GUARD+STRIDE*PH+32,BYTES=ROW_BYTES*PH;
    localparam [31:0] BASE=32'h87300ff0;
    reg clk=0,reset_n=0,control=0,inject_error=0,hold_b=0;
    always #4 clk=~clk;
    reg pack_sent=0,dma_sent=0;
    integer sent=0,cycle=0;
    wire src_valid=reset_n&&pack_sent&&dma_sent&&sent<FW*FH;
    wire src_ready;
    wire [23:0] scale_rgb,pad_bgr;
    wire scale_valid,scale_ready,scale_last,scale_fault;
    wire pad_valid,pad_ready,pad_last,pad_end,pad_padding,pad_fault;
    wire pack_valid,pack_ready,pack_last,pack_end,pack_done,pack_fault,pack_req_ready;
    wire [127:0] pack_data;
    wire [15:0] pack_keep;
    wire dma_req_ready,result_valid,result_success,dma_fault;
    wire [7:0] result_code;
    wire [31:0] result_tag,written_bytes;
    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awvalid,awready,wvalid,wready,wlast,bready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    reg bvalid=0;
    reg [1:0] bresp=0;
    function automatic [7:0] source_byte(input integer x,y,c);
        case(c)
            0:source_byte=8'((37*x+19*y+147)%256);
            1:source_byte=8'((11*x+53*y+101)%256);
            default:source_byte=8'((71*x+7*y+183)%256);
        endcase
    endfunction
    function automatic [7:0] test_q(input [7:0] raw);
        test_q=8'(int'(raw)*37+13);
    endfunction
    function automatic [7:0] expected_byte(input integer row,byte_x);
        integer x,c,dx,dy,total;
        begin
            x=byte_x/8;c=byte_x%8;total=0;
            if(row>=AH||c>=3)expected_byte=13;
            else begin
                for(dy=0;dy<5;dy=dy+1)for(dx=0;dx<5;dx=dx+1)
                    total=total+int'(source_byte(x*5+dx,row*5+dy,2-c));
                expected_byte=test_q(8'((total+12)/25));
            end
        end
    endfunction
    wire [23:0] source_rgb={source_byte(sent%FW,sent/FW,0),source_byte(sent%FW,sent/FW,1),source_byte(sent%FW,sent/FW,2)};
    detect_downscale #(.FRAME_WIDTH(FW),.FRAME_HEIGHT(FH)) scaler(
        .clk(clk),.reset_n(reset_n),.clear(1'b0),.s_valid(src_valid),.s_ready(src_ready),
        .s_rgb(source_rgb),.s_row_last(sent%FW==FW-1),.m_valid(scale_valid),.m_ready(scale_ready),
        .m_rgb(scale_rgb),.m_row_last(scale_last),.fault(scale_fault));
    detect_input_pad #(.WIDTH(W),.ACTIVE_HEIGHT(AH),.STORAGE_HEIGHT(PH)) pad(
        .clk(clk),.reset_n(reset_n),.clear(1'b0),.s_valid(scale_valid),.s_ready(scale_ready),
        .s_rgb(scale_rgb),.s_row_last(scale_last),.m_valid(pad_valid),.m_ready(pad_ready),
        .m_bgr(pad_bgr),.m_row_last(pad_last),.m_frame_last(pad_end),.m_padding(pad_padding),.fault(pad_fault));
    detect_c8_pack #(.WIDTH(W),.ACTIVE_HEIGHT(AH),.STORAGE_HEIGHT(PH)) packer(
        .clk(clk),.reset_n(reset_n),.clear(1'b0),.req_valid(control&&!pack_sent),.req_ready(pack_req_ready),.req_zero(8'd13),
        .s_valid(pad_valid),.s_ready(pad_ready),.s_q_bgr({test_q(pad_bgr[23:16]),test_q(pad_bgr[15:8]),test_q(pad_bgr[7:0])}),
        .s_row_last(pad_last),.s_frame_last(pad_end),.s_padding(pad_padding),
        .m_valid(pack_valid),.m_ready(pack_ready),.m_data(pack_data),.m_keep(pack_keep),
        .m_row_last(pack_last),.m_frame_last(pack_end),.done(pack_done),.fault(pack_fault));
    video_write_dma #(.AXI_ID(4'd3)) dma(
        .clk(clk),.reset_n(reset_n),.online(1'b1),.abort(scale_fault||pad_fault||pack_fault),
        .req_valid(control&&!dma_sent),.req_ready(dma_req_ready),.req_base(BASE),.req_row_bytes(ROW_BYTES),
        .req_stride(STRIDE),.req_rows(16'(PH)),.req_tag(32'hda7a),
        .s_valid(pack_valid),.s_ready(pack_ready),.s_data(pack_data),.s_keep(pack_keep),.s_row_last(pack_last),
        .result_valid(result_valid),.result_ready(1'b0),.result_success(result_success),.result_code(result_code),
        .result_tag(result_tag),.written_bytes(written_bytes),.busy(),.fault(dma_fault),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(4'd3),.bresp(bresp),.bvalid(bvalid),.bready(bready));

    reg [7:0] memory[0:MEM_SIZE-1];
    reg active=0,pending_b=0,held_last=0;
    reg [31:0] address;
    integer beats=0,index=0,bdelay=0,bytes_written=0,bursts=0,responses=0;
    integer b,i,offset,row,byte_x,new_bytes;
    assign awready=reset_n&&!active&&!pending_b&&!bvalid&&cycle%5!=1;
    assign wready=reset_n&&active&&cycle%7>=3;
    always @(posedge clk)begin
        if(!reset_n)begin
            sent<=0;pack_sent<=0;dma_sent<=0;cycle<=0;active<=0;pending_b<=0;bvalid<=0;
            held_last<=0;hold_b<=0;bytes_written<=0;bursts<=0;responses<=0;bdelay<=0;
        end else begin
            cycle<=cycle+1;
            if(control&&!pack_sent&&pack_req_ready)pack_sent<=1;
            if(control&&!dma_sent&&dma_req_ready)dma_sent<=1;
            if(src_valid&&src_ready)sent<=sent+1;
            if(scale_fault||pad_fault||pack_fault)$fatal(1,"input format chain fault");
            if(!inject_error&&dma_fault)$fatal(1,"unexpected DMA port fault");
            if(awvalid&&awready)begin
                if(active||pending_b||awid!==3||awsize!==4||awburst!==1||awlen>15||
                   int'(awaddr[11:0])+(int'(awlen)+1)*16>4096)$fatal(1,"DMA burst protocol mismatch");
                address<=awaddr;beats<=int'(awlen)+1;index<=0;active<=1;bursts<=bursts+1;
            end
            if(wvalid&&wready)begin
                if(wlast!==(index==beats-1))$fatal(1,"DMA WLAST mismatch");
                new_bytes=0;
                for(b=0;b<16;b=b+1)if(wstrb[b])begin
                    offset=int'(address-BASE)+index*16+b;row=offset/STRIDE;byte_x=offset%STRIDE;
                    if(offset<0||row>=PH||byte_x>=ROW_BYTES)$fatal(1,"DMA wrote guard/stride padding");
                    if(wdata[b*8+:8]!==expected_byte(row,byte_x))$fatal(1,"DMA C8 byte mismatch row=%0d byte=%0d got=%h expected=%h",row,byte_x,wdata[b*8+:8],expected_byte(row,byte_x));
                    memory[GUARD+offset]<=wdata[b*8+:8];new_bytes=new_bytes+1;
                end
                bytes_written<=bytes_written+new_bytes;
                if(wlast)begin
                    active<=0;pending_b<=1;bdelay<=0;
                    if(!inject_error&&bytes_written+new_bytes==BYTES)begin held_last<=1;hold_b<=1;end
                end else index<=index+1;
            end
            if(pending_b&&!bvalid)begin
                if(bdelay<7)bdelay<=bdelay+1;
                else if(!hold_b)begin bvalid<=1;bresp<=inject_error?2'b10:2'b00;end
            end
            if(bvalid&&bready)begin bvalid<=0;pending_b<=0;responses<=responses+1;end
            if(result_valid&&(!inject_error)&&(active||pending_b||bvalid||responses!=bursts))$fatal(1,"DMA success before B retirement");
        end
    end
    task automatic restart(input bit error_response);
        begin
            @(negedge clk);reset_n=0;control=0;inject_error=error_response;
            for(i=0;i<MEM_SIZE;i=i+1)memory[i]=8'ha5;
            repeat(4)@(negedge clk);reset_n=1;control=1;
        end
    endtask
    task automatic check_memory;
        integer n,r,x;
        reg [7:0] wanted;
        begin
            for(n=0;n<MEM_SIZE;n=n+1)begin
                wanted=8'ha5;
                if(n>=GUARD&&n<GUARD+STRIDE*PH)begin
                    r=(n-GUARD)/STRIDE;x=(n-GUARD)%STRIDE;
                    if(x<ROW_BYTES)wanted=expected_byte(r,x);
                end
                if(memory[n]!==wanted)$fatal(1,"memory/guard mismatch offset=%0d",n);
            end
        end
    endtask
    initial begin
        restart(0);
        wait(held_last);repeat(40)@(negedge clk);
        if(result_valid||!pack_done)$fatal(1,"local pack done confused with DMA completion");
        hold_b=0;wait(result_valid);@(negedge clk);
        if(!result_success||result_code!=0||result_tag!==32'hda7a||written_bytes!=BYTES||sent!=FW*FH||!pack_done)
            $fatal(1,"DMA full tensor result mismatch");
        check_memory();repeat(10)@(negedge clk);
        if(FW<800)begin
            restart(1);wait(result_valid);@(negedge clk);
            if(result_success||result_code!=6||written_bytes!=0)$fatal(1,"DMA B error accepted as success");
        end
        $display("DETECT_INPUT_DMA_PASS FW=%0d FH=%0d W=%0d AH=%0d PH=%0d bytes=%0d stride=%0d",FW,FH,W,AH,PH,BYTES,STRIDE);$finish;
    end
    initial begin #200000000;$fatal(1,"input DMA global timeout");end
endmodule
`default_nettype wire
