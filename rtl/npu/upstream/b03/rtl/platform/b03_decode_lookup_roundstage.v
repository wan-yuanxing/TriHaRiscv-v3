// Same external contract as b03_decode_lookup; six grid steps overlap gathering.
module b03_decode_lookup_roundstage(
    input wire clk,clear,run_ce,in_valid,output wire in_ready,
    input wire [1:0] stride_index,input wire [10:0] index,input wire [63:0] raw_codes,
    input wire [31:0] candidate_id,epoch,
    output wire req_valid,input wire req_ready,output reg [31:0] req_offset,output wire [31:0] req_epoch,
    input wire rsp_valid,output wire rsp_ready,input wire [255:0] rsp_data,
    input wire [31:0] rsp_offset,rsp_epoch,input wire rsp_error,
    output wire out_valid,input wire out_ready,output reg out_error,
    output reg [127:0] box_bits,output reg [255:0] box_q40,output reg [63:0] rectangle,
    output reg [20:0] current_area,output reg [31:0] out_id,out_epoch,local_cycles,wait_cycles,
    output reg [2:0] lookup_beats,output wire [31:0] arithmetic_cycles,
    output wire mul_valid,output wire [24:0] mul_x,output wire [17:0] mul_y,output wire [31:0] mul_epoch,
    input wire [47:0] mul_product,input wire mul_rsp_valid,input wire [1:0] mul_mode,input wire [31:0] mul_rsp_epoch,
    output wire busy,output wire [3:0] debug_state,output wire [4:0] math_state
);
    localparam IDLE=0,CHECK=1,REQUEST=2,WAIT=3,LAUNCH=4,COMPUTE=5,HOLD=6;
    reg [3:0] state;reg [1:0] scale,axis;reg [10:0] position;reg [63:0] codes;
    reg [255:0] cache[0:3],entries;reg [31:0] cache_offset[0:3];reg [3:0] cache_valid;reg [2:0] loaded;
    reg [10:0] grid_remainder;reg [5:0] grid_row;reg [2:0] grid_bit;reg grid_done;
    wire [5:0] grid_width=scale==0 ? 6'd40:scale==1 ? 6'd20:6'd10;
    wire [12:0] grid_trial={7'b0,grid_width}<<grid_bit;
    wire [15:0] code=codes[16*axis+:16];
    wire [31:0] wanted=({30'b0,scale}<<19)+(({16'b0,code}>>2)<<5);
    reg hit;reg [1:0] hit_index;integer i;
    always @* begin hit=0;hit_index=0;for(i=0;i<4;i=i+1)if(cache_valid[i]&&cache_offset[i]==wanted)begin hit=1;hit_index=i;end end
    assign req_valid=!clear&&state==REQUEST;assign req_epoch=out_epoch;
    assign rsp_ready=!clear&&run_ce&&state==WAIT;
    wire core_ready,core_valid,core_error,core_busy;wire [127:0] core_bits;wire [255:0] core_q;
    wire [63:0] core_rect;wire [20:0] core_area;wire [31:0] core_id,core_epoch;
    b03_decode_math_roundstage math(.clk(clk),.clear(clear||(state==HOLD&&out_error)),.run_ce(run_ce),.in_valid(state==LAUNCH&&grid_done),.in_ready(core_ready),
        .stride_index(scale),.index(position),.grid_row_in(grid_row),.grid_col_in(grid_remainder[5:0]),
        .table_words({entries[255:224],entries[191:160],entries[95:64],entries[31:0]}),
        .candidate_id(out_id),.epoch(out_epoch),.out_valid(core_valid),.out_ready(state==COMPUTE),.out_error(core_error),
        .box_bits(core_bits),.box_q40(core_q),.rectangle(core_rect),.current_area(core_area),.out_id(core_id),.out_epoch(core_epoch),.cycles(arithmetic_cycles),
        .mul_valid(mul_valid),.mul_x(mul_x),.mul_y(mul_y),.mul_epoch(mul_epoch),.mul_product(mul_product),.mul_rsp_valid(mul_rsp_valid),
        .mul_mode(mul_mode),.mul_rsp_epoch(mul_rsp_epoch),.busy(core_busy),.debug_state(math_state));
    assign in_ready=state==IDLE&&!core_busy;assign out_valid=state==HOLD;assign busy=state!=IDLE||core_busy;assign debug_state=state;
    wire invalid=stride_index>2||(stride_index==0&&index>=1600)||(stride_index==1&&index>=400)||(stride_index==2&&index>=100)||
        raw_codes[15:0]==16'h8000||raw_codes[31:16]==16'h8000||raw_codes[47:32]==16'h8000||raw_codes[63:48]==16'h8000||
        candidate_id!=(stride_index==0 ? 32'd0:stride_index==1 ? 32'd1600:32'd2000)+index;
    integer c;
    always @(posedge clk)begin
        if(clear)begin
            state<=IDLE;scale<=0;axis<=0;position<=0;codes<=0;cache_valid<=0;loaded<=0;entries<=0;req_offset<=0;
            grid_remainder<=0;grid_row<=0;grid_bit<=0;grid_done<=0;
            out_error<=0;box_bits<=0;box_q40<=0;rectangle<=0;current_area<=0;out_id<=0;out_epoch<=0;local_cycles<=0;wait_cycles<=0;lookup_beats<=0;
            for(c=0;c<4;c=c+1)begin cache[c]<=0;cache_offset[c]<=0;end
        end else if(run_ce)begin
            if(state!=IDLE&&state!=HOLD&&!grid_done)begin
                if({2'b0,grid_remainder}>=grid_trial)begin grid_remainder<=grid_remainder-grid_trial;grid_row[grid_bit]<=1;end
                if(grid_bit==0)grid_done<=1;else grid_bit<=grid_bit-1'b1;
            end
            if(state!=IDLE&&state!=HOLD)begin
                if((state==REQUEST&&!req_ready)||(state==WAIT&&!rsp_valid))wait_cycles<=wait_cycles+1'b1;
                else local_cycles<=local_cycles+1'b1;
            end
            if(rsp_valid&&state!=IDLE&&state!=WAIT&&state!=HOLD)begin out_error<=1;state<=HOLD;end
            else case(state)
                IDLE:if(in_valid&&in_ready)begin
                    scale<=stride_index;position<=index;codes<=raw_codes;axis<=0;loaded<=0;cache_valid<=0;entries<=0;
                    grid_remainder<=index;grid_row<=0;grid_bit<=5;grid_done<=0;
                    out_id<=candidate_id;out_epoch<=epoch;out_error<=invalid;box_bits<=0;box_q40<=0;rectangle<=0;current_area<=0;
                    lookup_beats<=0;local_cycles<=0;wait_cycles<=0;state<=invalid ? HOLD:CHECK;
                end
                CHECK:begin
                    if(hit)begin
                        entries[64*axis+:64]<=cache[hit_index][64*code[1:0]+:64];
                        if(axis==3)state<=LAUNCH;else axis<=axis+1'b1;
                    end else if(loaded>=4)begin out_error<=1;state<=HOLD;end
                    else begin req_offset<=wanted;state<=REQUEST;end
                end
                REQUEST:if(req_ready)begin lookup_beats<=lookup_beats+1'b1;state<=WAIT;end
                WAIT:if(rsp_valid)begin
                    if(rsp_error||rsp_epoch!=out_epoch||rsp_offset!=req_offset)begin out_error<=1;state<=HOLD;end
                    else begin
                        cache[loaded]<=rsp_data;cache_offset[loaded]<=req_offset;cache_valid[loaded]<=1;loaded<=loaded+1'b1;
                        entries[64*axis+:64]<=rsp_data[64*code[1:0]+:64];
                        if(axis==3)state<=LAUNCH;else begin axis<=axis+1'b1;state<=CHECK;end
                    end
                end
                LAUNCH:if(core_ready&&grid_done)state<=COMPUTE;
                COMPUTE:if(core_valid)begin
                    out_error<=core_error||core_id!=out_id||core_epoch!=out_epoch;
                    box_bits<=core_bits;box_q40<=core_q;rectangle<=core_rect;current_area<=core_area;state<=HOLD;
                end
                HOLD:if(out_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
