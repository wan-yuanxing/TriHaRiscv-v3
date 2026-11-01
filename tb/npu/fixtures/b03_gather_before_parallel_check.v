// Production baseline SHA256 5f84707097d6506c143d30e830c4249a721c73289c8bb9c0a53a0b728606401d.
// Test-only module rename; production source list excludes this fixture.
// Compact gather: explicit K geometry counters, bounded address arithmetic.
// One shared byte-alignment network serves all sixteen output pixels.
// Two 288-bit return contexts, one ordered 128-bit A write per final token.
// Parent owns the actual ROI/A RAM and waits its final write pipeline empty.
module b03_gather_old(
    input wire clk,rst_n,clear,run_ce,
    input wire start_valid,output wire start_ready,
    input wire [7:0] cfg_k_count,input wire [6:0] cfg_cin,input wire [8:0] cfg_win,cfg_x,
    input wire [4:0] cfg_m,input wire cfg_kernel3,cfg_stride2,input wire [7:0] cfg_pad_left,
    input wire [191:0] cfg_row_present,input wire [32:0] cfg_row_offsets,input wire [10:0] cfg_group_stride,
    input wire [31:0] cfg_tag,
    output reg done_valid,input wire done_ready,output reg [31:0] done_status,done_tag,
    output reg [15:0] roi_req_a,roi_req_b,output reg [175:0] roi_addr_a,roi_addr_b,
    input wire [511:0] roi_q_a,roi_q_b,input wire [15:0] roi_valid_a,roi_valid_b,
    output wire a_write_valid,output wire [7:0] a_write_index,output reg [127:0] a_write_data,
    output wire busy,output reg [31:0] groups,vectors
);
    reg active;reg [7:0] count,current_k;reg [6:0] cin;reg [8:0] win,x;
    reg [4:0] m;reg kernel3,stride2;reg [7:0] pad_left;reg [191:0] present;
    reg [32:0] offsets;reg [10:0] group_stride;reg [31:0] tag;
    reg [3:0] word_index;
    reg [1:0] vp,firstp,lastp,dummyp,twop;
    reg [7:0] kp[0:1];reg [3:0] bankp[0:1],wp[0:1];reg [8:0] firstwordp[0:1];reg signed [11:0] ixp[0:1];
    reg [255:0] context_data;
    reg [6:0] k_ci;
    reg [1:0] k_ky,k_kx;
    reg [6:0] ci;
    reg [1:0] ky,kx;
    reg signed [11:0] first_x,last_x,clipped_first,clipped_last;
    reg [4:0] word_count;
    reg [8:0] first_word;
    reg [13:0] physical;
    reg [3:0] bank;
    integer n,addr_bank;
    reg dummy,twowords,address_bad;
    wire step=rst_n&&!clear&&run_ce;
    wire issue=active&&current_k<count;
    wire last_group=dummy||word_index+2>=word_count;
    assign start_ready=rst_n&&!clear&&!active&&!done_valid;
    assign busy=active||done_valid;
    always @*begin
        ci=k_ci;ky=k_ky;kx=k_kx;
        first_x=($signed({3'd0,x})<<<stride2)-$signed({4'd0,pad_left})+$signed({10'd0,kx});
        last_x=first_x+($signed({7'd0,(m-5'd1)})<<<stride2);
        clipped_first=first_x<0?12'sd0:first_x;
        clipped_last=last_x>=$signed({3'd0,win})?$signed({3'd0,win})-12'sd1:last_x;
        dummy=ci>=cin||!present[ci*3+ky]||last_x<0||first_x>=$signed({3'd0,win});
        first_word=dummy?0:clipped_first>>2;word_count=dummy?0:(clipped_last>>2)-first_word+1;
        twowords=!dummy&&word_index+1<word_count;
        physical=(ci[4]?{3'd0,group_stride}:14'd0)+(ci[5]?{2'd0,group_stride,1'b0}:14'd0)+
            {3'd0,offsets[11*ky+:11]}+{5'd0,first_word}+{10'd0,word_index};
        bank=ci[3:0];address_bad=!dummy&&(physical>1023||(twowords&&physical+14'd1>1023));
        roi_req_a=0;roi_req_b=0;roi_addr_a=0;roi_addr_b=0;
        for(addr_bank=0;addr_bank<16;addr_bank=addr_bank+1)begin
            roi_addr_a[11*addr_bank+:11]=physical;roi_addr_b[11*addr_bank+:11]=physical+1;
        end
        if(step&&issue&&!dummy&&!address_bad)begin
            roi_req_a[bank]=1;
            if(twowords)roi_req_b[bank]=1;
        end
    end
    reg [287:0] assembled;
    integer pixel,word;reg signed [12:0] source_x,byte_index;
    reg signed [12:0] first_byte;
    reg [5:0] align_bytes;
    reg [127:0] aligned_pixels;
    reg [151:0] sampled_pixels;reg signed [12:0] sample_start;integer sample;
    reg [31:0] return_word_a,return_word_b;
    wire return_good=dummyp[1]||(roi_valid_a[bankp[1]]&&(!twop[1]||roi_valid_b[bankp[1]]));
    assign a_write_valid=step&&active&&vp[1]&&lastp[1]&&return_good;
    assign a_write_index=kp[1];
    always @*begin
        assembled=firstp[1]?288'd0:{32'd0,context_data};
        return_word_a=roi_q_a[32*bankp[1]+:32];return_word_b=roi_q_b[32*bankp[1]+:32];
        for(word=0;word<9;word=word+1)begin
            if(!dummyp[1] && wp[1]==word)assembled[32*word+:32]=return_word_a;
            if(!dummyp[1] && twop[1] && wp[1]+1==word)assembled[32*word+:32]=return_word_b;
        end
        first_byte=$signed({ixp[1][11],ixp[1]})-$signed({2'd0,firstwordp[1],2'b00});
        // Every return is ordered. One context holds words 0..7; a possible
        // ninth word is only used by this final response and needs no register.
        // Decimate stride2 first, so the common alignment shifter is 16 pixels.
        sampled_pixels=0;
        for(sample=0;sample<19;sample=sample+1)begin
            if(!stride2)sampled_pixels[8*sample+:8]=assembled[8*sample+:8];
            else if(sample<18)sampled_pixels[8*sample+:8]=first_byte[0]?assembled[16*sample+8+:8]:assembled[16*sample+:8];
        end
        sample_start=stride2?(first_byte>>>1):first_byte;
        align_bytes=sample_start+13'sd16;
        aligned_pixels={sampled_pixels,128'd0}>>{align_bytes[4:0],3'b000};
        a_write_data=0;
        for(pixel=0;pixel<16;pixel=pixel+1)begin
            source_x=$signed({ixp[1][11],ixp[1]})+($signed({8'd0,pixel[4:0]})<<<stride2);
            byte_index=source_x-$signed({2'd0,firstwordp[1],2'b00});
            if(pixel<m&&!dummyp[1]&&source_x>=0&&source_x<$signed({4'd0,win})&&byte_index>=0&&byte_index<36)
                a_write_data[8*pixel+:8]=aligned_pixels[8*pixel+:8];
        end
    end
    task fail;input[31:0] s;begin done_valid<=1;done_status<=s;done_tag<=tag;active<=0;vp<=0;end endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active<=0;count<=0;current_k<=0;cin<=0;win<=0;x<=0;m<=0;kernel3<=0;stride2<=0;pad_left<=0;present<=0;offsets<=0;group_stride<=0;tag<=0;
            k_ci<=0;k_ky<=0;k_kx<=0;
            word_index<=0;vp<=0;firstp<=0;lastp<=0;dummyp<=0;twop<=0;context_data<=0;
            done_valid<=0;done_status<=0;done_tag<=0;groups<=0;vectors<=0;
            for(n=0;n<2;n=n+1)begin kp[n]<=0;bankp[n]<=0;wp[n]<=0;firstwordp[n]<=0;ixp[n]<=0;end
        end else if(clear)begin active<=0;vp<=0;done_valid<=0;done_status<=0;word_index<=0;end
        else begin
            if(done_valid&&done_ready)done_valid<=0;
            if(start_valid&&start_ready)begin
                count<=cfg_k_count;current_k<=0;k_ci<=0;k_ky<=0;k_kx<=0;cin<=cfg_cin;win<=cfg_win;x<=cfg_x;m<=cfg_m;kernel3<=cfg_kernel3;stride2<=cfg_stride2;pad_left<=cfg_pad_left;
                present<=cfg_row_present;offsets<=cfg_row_offsets;group_stride<=cfg_group_stride;tag<=cfg_tag;
                active<=1;word_index<=0;vp<=0;groups<=0;vectors<=0;done_status<=0;
                if(cfg_k_count==0||cfg_k_count>128||cfg_cin==0||cfg_cin>64||cfg_win==0||cfg_win>320||cfg_m==0||cfg_m>16||cfg_x>=320)begin
                    active<=0;done_valid<=1;done_status<=11;done_tag<=cfg_tag;
                end
            end else if(step)begin
                vp<={vp[0],issue};firstp<={firstp[0],word_index==0};lastp<={lastp[0],last_group};dummyp<={dummyp[0],dummy};twop<={twop[0],twowords};
                kp[0]<=current_k;kp[1]<=kp[0];bankp[0]<=bank;bankp[1]<=bankp[0];wp[0]<=word_index;wp[1]<=wp[0];
                firstwordp[0]<=first_word;firstwordp[1]<=firstwordp[0];ixp[0]<=first_x;ixp[1]<=ixp[0];
                if(issue)begin
                    groups<=groups+1;
                    if(last_group)begin
                        current_k<=current_k+1;word_index<=0;
                        if(!kernel3)k_ci<=k_ci+1;
                        else if(k_kx<2)k_kx<=k_kx+1;
                        else begin
                            k_kx<=0;
                            if(k_ky<2)k_ky<=k_ky+1;
                            else begin k_ky<=0;k_ci<=k_ci+1;end
                        end
                    end else word_index<=word_index+2;
                    if(address_bad)fail(32'h610);
                end
                if(active&&vp[1])begin
                    if(!return_good)fail(32'h611);
                    else begin
                        context_data<=assembled[255:0];
                        if(lastp[1])begin
                            vectors<=vectors+1;
                            if(kp[1]+1==count)begin active<=0;done_valid<=1;done_status<=0;done_tag<=tag;end
                        end
                    end
                end
            end
        end
    end
endmodule
