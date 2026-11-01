// RAW diagnostic responses only. All arrays are already returned bank buses;
// this module creates no RAM/APM and never changes native request semantics.
module b03_raw_bank_response_pipe(
    input wire clk,clear,run_ce,
    input wire [1:0] read_pending,
    input wire [63:0] selected_a,selected_b,
    input wire [511:0] aq_a,aq_b,pq_a,pq_b,oq_a,oq_b,
    input wire [15:0] av_a,av_b,pv_a,pv_b,
    input wire [31:0] ov_a,ov_b,
    input wire [1:0] saved_mem,
    input wire [4:0] saved_bank_a,saved_bank_b,
    input wire [31:0] saved_epoch,
    output reg [31:0] q_a,q_b,
    output reg [1:0] out_valid,
    output reg [1:0] out_mem,
    output reg [4:0] out_bank_a,out_bank_b,
    output reg [31:0] out_epoch,
    output wire busy
);
    wire [63:0] native_a={ov_a,pv_a,av_a},native_b={ov_b,pv_b,av_b};
    wire [63:0] take_a=selected_a&native_a&{64{read_pending[0]}};
    wire [63:0] take_b=selected_b&native_b&{64{read_pending[1]}};
    reg [63:0] bank_valid_a,bank_valid_b;
    reg [1:0] group_valid;
    reg [1:0] bank_mem,group_mem;
    reg [4:0] bank_id_a,bank_id_b,group_id_a,group_id_b;
    reg [31:0] bank_epoch,group_epoch;
    wire [2047:0] bank_words_a,bank_words_b;
    wire [255:0] group_words_a,group_words_b;
    // Current qualified return protects the gap before first-level capture.
    assign busy=!clear&&((|take_a)||(|take_b)||(|bank_valid_a)||(|bank_valid_b)||
                (|group_valid)||(|out_valid));

    genvar b,g;
    generate for(b=0;b<64;b=b+1)begin:bank
        wire [31:0] input_a,input_b;
        reg [31:0] data_a,data_b;
        if(b<16)begin:from_a
            assign input_a=aq_a[32*b+:32];assign input_b=aq_b[32*b+:32];
        end else if(b<32)begin:from_p
            assign input_a=pq_a[32*(b-16)+:32];assign input_b=pq_b[32*(b-16)+:32];
        end else begin:from_o
            assign input_a={16'b0,oq_a[16*(b-32)+:16]};
            assign input_b={16'b0,oq_b[16*(b-32)+:16]};
        end
        // A single bank-local qualification drives this bank's data CE.
        // Data need no reset: bank_valid is cleared and masks every stale bit.
        always @(posedge clk)begin
            if(!clear&&run_ce)begin
                if(take_a[b])data_a<=input_a;
                if(take_b[b])data_b<=input_b;
            end
        end
        assign bank_words_a[32*b+:32]=data_a;
        assign bank_words_b[32*b+:32]=data_b;
    end endgenerate

    generate for(g=0;g<8;g=g+1)begin:group
        wire [31:0] reduce_a,reduce_b;
        reg [31:0] data_a,data_b;
        assign reduce_a=
            (bank_words_a[32*(8*g+0)+:32]&{32{bank_valid_a[8*g+0]}})|
            (bank_words_a[32*(8*g+1)+:32]&{32{bank_valid_a[8*g+1]}})|
            (bank_words_a[32*(8*g+2)+:32]&{32{bank_valid_a[8*g+2]}})|
            (bank_words_a[32*(8*g+3)+:32]&{32{bank_valid_a[8*g+3]}})|
            (bank_words_a[32*(8*g+4)+:32]&{32{bank_valid_a[8*g+4]}})|
            (bank_words_a[32*(8*g+5)+:32]&{32{bank_valid_a[8*g+5]}})|
            (bank_words_a[32*(8*g+6)+:32]&{32{bank_valid_a[8*g+6]}})|
            (bank_words_a[32*(8*g+7)+:32]&{32{bank_valid_a[8*g+7]}});
        assign reduce_b=
            (bank_words_b[32*(8*g+0)+:32]&{32{bank_valid_b[8*g+0]}})|
            (bank_words_b[32*(8*g+1)+:32]&{32{bank_valid_b[8*g+1]}})|
            (bank_words_b[32*(8*g+2)+:32]&{32{bank_valid_b[8*g+2]}})|
            (bank_words_b[32*(8*g+3)+:32]&{32{bank_valid_b[8*g+3]}})|
            (bank_words_b[32*(8*g+4)+:32]&{32{bank_valid_b[8*g+4]}})|
            (bank_words_b[32*(8*g+5)+:32]&{32{bank_valid_b[8*g+5]}})|
            (bank_words_b[32*(8*g+6)+:32]&{32{bank_valid_b[8*g+6]}})|
            (bank_words_b[32*(8*g+7)+:32]&{32{bank_valid_b[8*g+7]}});
        always @(posedge clk)begin
            if(!clear&&run_ce)begin data_a<=reduce_a;data_b<=reduce_b;end
        end
        assign group_words_a[32*g+:32]=data_a;
        assign group_words_b[32*g+:32]=data_b;
    end endgenerate

    wire [31:0] final_a=group_words_a[0+:32]|group_words_a[32+:32]|group_words_a[64+:32]|group_words_a[96+:32]|
                         group_words_a[128+:32]|group_words_a[160+:32]|group_words_a[192+:32]|group_words_a[224+:32];
    wire [31:0] final_b=group_words_b[0+:32]|group_words_b[32+:32]|group_words_b[64+:32]|group_words_b[96+:32]|
                         group_words_b[128+:32]|group_words_b[160+:32]|group_words_b[192+:32]|group_words_b[224+:32];
    always @(posedge clk)begin
        if(clear)begin
            bank_valid_a<=0;bank_valid_b<=0;group_valid<=0;out_valid<=0;
            bank_mem<=0;group_mem<=0;out_mem<=0;bank_epoch<=0;group_epoch<=0;out_epoch<=0;
            bank_id_a<=0;bank_id_b<=0;group_id_a<=0;group_id_b<=0;out_bank_a<=0;out_bank_b<=0;
            q_a<=0;q_b<=0;
        end else if(run_ce)begin
            bank_valid_a<=take_a;bank_valid_b<=take_b;
            group_valid<={|bank_valid_b,|bank_valid_a};out_valid<=group_valid;
            if((|take_a)||(|take_b))begin
                bank_mem<=saved_mem;bank_id_a<=saved_bank_a;bank_id_b<=saved_bank_b;bank_epoch<=saved_epoch;
            end
            if((|bank_valid_a)||(|bank_valid_b))begin
                group_mem<=bank_mem;group_id_a<=bank_id_a;group_id_b<=bank_id_b;group_epoch<=bank_epoch;
            end
            if(group_valid[0])q_a<=final_a;
            if(group_valid[1])q_b<=final_b;
            if(|group_valid)begin
                out_mem<=group_mem;out_bank_a<=group_id_a;out_bank_b<=group_id_b;out_epoch<=group_epoch;
            end
        end
    end
endmodule
