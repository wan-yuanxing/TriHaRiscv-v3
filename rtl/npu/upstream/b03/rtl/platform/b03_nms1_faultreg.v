// Serial, exact NMS candidate. Same A reqreg and shared two-stage APM contracts.
// Unrequested address/data bank slices are broadcasts; only req/we commit RAM.
module b03_nms1_faultreg(
    input wire clk,clear,run_ce,frame_start,in_valid,output wire in_ready,
    input wire [63:0] rectangle,input wire [20:0] current_area,
    input wire [31:0] candidate_id,epoch,
    output wire busy,out_valid,input wire out_ready,
    output reg out_keep,out_error,output reg [31:0] out_id,out_epoch,
    output reg [11:0] kept_count,output reg [31:0] cycles,groups_issued,
    output reg [15:0] req_a,we_a,req_b,we_b,
    output reg [175:0] addr_a,addr_b,output reg [511:0] data_a,data_b,
    input wire [511:0] q_a,q_b,input wire [15:0] valid_a,valid_b,
    output wire [31:0] mul_valid,output wire [799:0] mul_x,output wire [575:0] mul_y,
    output wire [31:0] mul_epoch,
    input wire [1535:0] products,input wire [31:0] product_valid,
    input wire [63:0] product_modes,input wire [1023:0] product_epochs,
    output wire [2:0] debug_state,output wire [15:0] debug_mask,output wire [15:0] debug_hits
);
    localparam IDLE=0,SCAN=1,APPEND=2,HOLD=3,APPEND_EXEC=4,APPEND_RETIRE=5,APPEND_COMMIT=6;
    reg [2:0] state;
    reg [63:0] current;
    reg [20:0] area;
    reg [11:0] issued,total_groups;
    reg seen_hit,fault;
    reg issue_pending,issue_last;reg [15:0] issue_mask;
    reg [3:0] issue_bank,bank0;
    reg expected_m0,expected_m1;
    reg v0,v1,last0,last1,last_m0,last_m1,last_union,last_hits;
    reg [15:0] mask0,mask1,mask_m0,mask_m1,mask_union,mask_hits,hits;
    reg union_valid,hits_valid;
    reg [10:0] iw,ih,ow,oh;
    reg [21:0] unions;reg [20:0] intersections;
    wire issue=state==SCAN&&issued<total_groups;
    wire signed [15:0] cx=current[15:0],cy=current[31:16];
    wire signed [15:0] ix=rectangle[15:0],iy=rectangle[31:16];
    wire invalid=ix < -16'sd1024 || ix > 16'sd1024 || iy < -16'sd1024 || iy > 16'sd1024 ||
                 rectangle[47:32]>1024 || rectangle[63:48]>1024 || current_area>21'd1048576;
    wire [31:0] selected_a=q_a[32*bank0+:32],selected_b=q_b[32*bank0+:32];
    wire [21:0] pair_sum={1'b0,area}+{1'b0,products[48+:21]};
    assign busy=state!=IDLE;assign in_ready=state==IDLE&&!frame_start;
    assign out_valid=state==HOLD;assign debug_state=state;assign debug_mask=mask0;assign debug_hits=hits;
    assign mul_epoch=out_epoch;
    assign mul_valid={30'b0,v1,v1};
    assign mul_x={750'b0,14'b0,ow,14'b0,iw};
    assign mul_y={540'b0,7'b0,oh,7'b0,ih};
    integer b;
    always @* begin
        req_a=0;req_b=0;we_a=0;we_b=0;
        for(b=0;b<16;b=b+1)begin
            addr_a[11*b+:11]={2'b0,issued[11:4],1'b0};
            addr_b[11*b+:11]={2'b0,issued[11:4],1'b1};
            data_a[32*b+:32]=current[31:0];data_b[32*b+:32]=current[63:32];
        end
        if(issue)begin req_a=16'b1<<issued[3:0];req_b=req_a;end
        else if(state==APPEND)begin
            req_a=16'b1<<kept_count[3:0];req_b=req_a;we_a=req_a;we_b=req_b;
            for(b=0;b<16;b=b+1)begin
                addr_a[11*b+:11]={2'b0,kept_count[11:4],1'b0};
                addr_b[11*b+:11]={2'b0,kept_count[11:4],1'b1};
            end
        end
    end
    reg signed [12:0] px,py,pxe,pye,cxe,cye,xlo,ylo,xhi,yhi;
    reg [23:0] three_union,ten_intersection;
    reg [31:0] lane_bad_reg;
    reg pair_bad_reg,ram_bad_reg;
    genvar f;
    generate for(f=0;f<32;f=f+1)begin:lane_fault
        wire expected=f<2 ? expected_m1:1'b0;
        always @(posedge clk)begin
            if(clear)lane_bad_reg[f]<=0;
            else if(run_ce)lane_bad_reg[f]<=(product_valid[f]!=expected)||
                (product_valid[f]&&(product_modes[2*f+:2]!=1||product_epochs[32*f+:32]!=out_epoch));
        end
    end endgenerate
    always @(posedge clk)begin
        if(clear)begin pair_bad_reg<=0;ram_bad_reg<=0;end
        else if(run_ce)begin
            ram_bad_reg<=v0&&(!valid_a[bank0]||!valid_b[bank0]);
            pair_bad_reg<=expected_m1&&
                (products[21+:27]!=0||products[69+:27]!=0||{1'b0,products[0+:21]}>pair_sum);
        end
    end
    always @(posedge clk)begin
        if(clear)begin
            state<=IDLE;current<=0;area<=0;issued<=0;total_groups<=0;seen_hit<=0;fault<=0;
            out_keep<=0;out_error<=0;out_id<=0;out_epoch<=0;kept_count<=0;cycles<=0;groups_issued<=0;
            issue_pending<=0;issue_last<=0;issue_mask<=0;issue_bank<=0;bank0<=0;expected_m0<=0;expected_m1<=0;
            v0<=0;v1<=0;last0<=0;last1<=0;last_m0<=0;last_m1<=0;last_union<=0;last_hits<=0;
            mask0<=0;mask1<=0;mask_m0<=0;mask_m1<=0;mask_union<=0;mask_hits<=0;hits<=0;union_valid<=0;hits_valid<=0;
            iw<=0;ih<=0;ow<=0;oh<=0;unions<=0;intersections<=0;
        end else if(run_ce)begin
            issue_pending<=issue;issue_last<=issue&&issued+1==total_groups;issue_mask<=issue?req_a:16'b0;
            issue_bank<=issued[3:0];bank0<=issue_bank;
            v0<=issue_pending;last0<=issue_last;mask0<=issue_mask;
            v1<=v0;last1<=last0;mask1<=mask0;
            last_m0<=last1;last_m1<=last_m0;mask_m0<=mask1;mask_m1<=mask_m0;
            expected_m0<=v1;expected_m1<=expected_m0;
            union_valid<=expected_m1;last_union<=last_m1;mask_union<=mask_m1;
            hits_valid<=union_valid;last_hits<=last_union;mask_hits<=mask_union;
            if(state!=IDLE&&state!=HOLD)cycles<=cycles+1'b1;
            if((|lane_bad_reg)||pair_bad_reg||ram_bad_reg)fault<=1;
            if(v0)begin
                px=$signed(selected_a[15:0]);py=$signed(selected_a[31:16]);
                pxe=px+$signed({2'b0,selected_b[10:0]});pye=py+$signed({2'b0,selected_b[26:16]});
                cxe=$signed(cx)+$signed({2'b0,current[42:32]});cye=$signed(cy)+$signed({2'b0,current[58:48]});
                xlo=$signed(cx)>px?$signed(cx):px;ylo=$signed(cy)>py?$signed(cy):py;
                xhi=cxe<pxe?cxe:pxe;yhi=cye<pye?cye:pye;
                iw<=xhi>xlo?xhi-xlo:11'b0;ih<=yhi>ylo?yhi-ylo:11'b0;
                ow<=selected_b[10:0];oh<=selected_b[26:16];
            end
            if(expected_m1)begin
                unions<=pair_sum-{1'b0,products[0+:21]};intersections<=products[0+:21];
            end
            if(union_valid)begin
                three_union=({2'b0,unions}<<1)+{2'b0,unions};
                ten_intersection=({3'b0,intersections}<<3)+({3'b0,intersections}<<1);
                hits<=mask_union&{16{unions==0||ten_intersection>three_union}};
            end
            case(state)
                IDLE:begin
                    if(frame_start)kept_count<=0;
                    else if(in_valid)begin
                        current<=rectangle;area<=current_area;out_id<=candidate_id;out_epoch<=epoch;
                        seen_hit<=0;fault<=0;issued<=0;groups_issued<=0;cycles<=0;out_keep<=0;out_error<=0;
                        total_groups<=kept_count;
                        if(invalid||kept_count>=2100)begin out_error<=1;state<=HOLD;end
                        else state<=kept_count==0?APPEND:SCAN;
                    end
                end
                SCAN:begin
                    if(issue)begin issued<=issued+1'b1;groups_issued<=groups_issued+1'b1;end
                    if(hits_valid)begin
                        seen_hit<=seen_hit|| |hits;
                        if(last_hits)begin
                            if(fault)begin out_error<=1;state<=HOLD;end
                            else if(seen_hit|| |hits)begin out_keep<=0;state<=HOLD;end
                            else state<=APPEND;
                        end
                    end
                end
                APPEND:state<=APPEND_EXEC;
                APPEND_EXEC:state<=APPEND_RETIRE;
                APPEND_RETIRE:state<=APPEND_COMMIT;
                APPEND_COMMIT:begin
                    if(fault)begin out_error<=1;out_keep<=0;end
                    else begin kept_count<=kept_count+1'b1;out_keep<=1;end
                    state<=HOLD;
                end
                HOLD:if(out_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
