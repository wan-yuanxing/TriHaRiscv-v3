// Unsigned stable merge over the two-edge registered P request interface.
// Last WRITE is executed by RAM on DRAIN; source flips only at that edge.
module b03_key_sort_mem2(
    input wire clk,clear,run_ce,start,input wire [11:0] count,
    input wire [31:0] epoch,
    output wire busy,output wire done,input wire done_ready,
    output reg error,result_buffer,output reg [31:0] result_epoch,cycles,
    output reg [15:0] req_a,we_a,req_b,we_b,
    output reg [175:0] addr_a,addr_b,output reg [511:0] data_a,data_b,
    input wire [511:0] q_a,q_b,input wire [15:0] valid_a,valid_b,
    output wire [3:0] debug_state
);
    localparam IDLE=0,SETUP=1,READ=2,WRITE=3,DRAIN=4,HOLD=5,CAPTURE=6,SELECT=7,WAIT_RAM=8;
    reg [3:0] state;
    reg [12:0] n,width,begin_run,left,right,left_end,right_end,out_index;
    reg source;
    wire left_live=left<left_end,right_live=right<right_end;
    wire [13:0] left_word=(source?14'd4224:14'd0)+{left[11:0],1'b0};
    wire [13:0] right_word=(source?14'd4224:14'd0)+{right[11:0],1'b0};
    wire [13:0] dest_word=(source?14'd0:14'd4224)+{out_index[11:0],1'b0};
    wire [3:0] lb=left_word[3:0],rb=right_word[3:0],db=dest_word[3:0];
    wire [63:0] lv={q_a[32*(lb+1)+:32],q_a[32*lb+:32]};
    wire [63:0] rv={q_b[32*(rb+1)+:32],q_b[32*rb+:32]};
    reg captured_ok,captured_left_live,captured_right_live;
    reg [63:0] captured_left,captured_right,chosen;
    reg choose_left;
    wire select_left=!captured_right_live||(captured_left_live&&captured_left<=captured_right);
    wire [3:0] lb_second=lb+4'd1,rb_second=rb+4'd1,db_second=db+4'd1;
    wire read_ok=(!left_live||(valid_a[lb]&&valid_a[lb+1]))&&
                 (!right_live||(valid_b[rb]&&valid_b[rb+1]));
    assign busy=state!=IDLE;assign done=state==HOLD;assign debug_state=state;
    integer b;
    // Constant bank slices avoid a 512-bit variable-position write network.
    always @* begin
        req_a=0;req_b=0;we_a=0;we_b=0;addr_a=0;addr_b=0;data_a=0;data_b=0;
        for(b=0;b<16;b=b+1)begin
            if(state==READ)begin
                if(left_live&&(lb==b||lb_second==b))begin req_a[b]=1;addr_a[11*b+:11]={1'b0,left_word[13:4]};end
                if(right_live&&(rb==b||rb_second==b))begin req_b[b]=1;addr_b[11*b+:11]={1'b0,right_word[13:4]};end
            end else if(state==WRITE)begin
                if(db==b)begin req_a[b]=1;we_a[b]=1;addr_a[11*b+:11]={1'b0,dest_word[13:4]};data_a[32*b+:32]=chosen[31:0];end
                if(db_second==b)begin req_a[b]=1;we_a[b]=1;addr_a[11*b+:11]={1'b0,dest_word[13:4]};data_a[32*b+:32]=chosen[63:32];end
            end
        end
    end
    always @(posedge clk)begin
        if(clear)begin
            state<=IDLE;n<=0;width<=1;source<=0;cycles<=0;error<=0;result_buffer<=0;result_epoch<=0;
            begin_run<=0;left<=0;right<=0;left_end<=0;right_end<=0;out_index<=0;
            captured_ok<=0;captured_left_live<=0;captured_right_live<=0;captured_left<=0;captured_right<=0;chosen<=0;choose_left<=0;
        end else if(run_ce)begin
            if(state!=IDLE&&state!=HOLD)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(start)begin
                    n<=count;source<=0;width<=1;begin_run<=0;cycles<=0;
                    result_buffer<=0;result_epoch<=epoch;error<=count>2100;
                    state<=count>1&&count<=2100?SETUP:HOLD;
                end
                SETUP:begin
                    left<=0;right<=width;left_end<=width<n?width:n;
                    right_end<=(width<<1)<n?(width<<1):n;out_index<=0;begin_run<=0;state<=READ;
                end
                READ:state<=WAIT_RAM;
                WAIT_RAM:state<=CAPTURE;
                CAPTURE:begin
                    captured_ok<=read_ok;captured_left<=lv;captured_right<=rv;
                    captured_left_live<=left_live;captured_right_live<=right_live;state<=SELECT;
                end
                SELECT:begin
                    if(!captured_ok)begin error<=1;state<=HOLD;end
                    else begin chosen<=select_left?captured_left:captured_right;choose_left<=select_left;state<=WRITE;end
                end
                WRITE:begin
                    if(choose_left)left<=left+1'b1;else right<=right+1'b1;
                    out_index<=out_index+1'b1;
                    if(out_index+1==n)state<=DRAIN;
                    else begin
                        if(out_index+1==right_end)begin
                            begin_run<=right_end;left<=right_end;right<=right_end+width;
                            left_end<=right_end+width<n?right_end+width:n;
                            right_end<=right_end+(width<<1)<n?right_end+(width<<1):n;
                        end
                        state<=READ;
                    end
                end
                DRAIN:begin
                    source<=!source;width<=width<<1;
                    if((width<<1)>=n)begin result_buffer<=!source;state<=HOLD;end
                    else state<=SETUP;
                end
                HOLD:if(done_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
