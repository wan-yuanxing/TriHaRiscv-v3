// Independent exact fault-code/lowest-lane decomposition; spec137.
// Streaming depthwise multiplier-one: 16 channels / tap, eight SIMD APMs.
// K=1 or 9. The last accepted tap of each position snapshots 16 I32 sums.
// All private events use advance; output backpressure freezes products too.
module b03_full_dw16_parallelfault #(
    // CPU-post mode keeps the depthwise arithmetic but drops the wide
    // return/overflow reduction tree used only for runtime diagnostics.
    parameter integer ENABLE_DIAGNOSTICS = 1
)(
    input wire clk,rst_n,clear,run_ce,
    input wire in_valid,output wire in_ready,
    input wire input_signed,input wire [15:0] in_mask,
    input wire [127:0] in_a,in_w,
    input wire [3:0] in_k,in_k_count,
    input wire [127:0] in_tag,
    output reg out_valid,input wire out_ready,
    output reg [511:0] out_psum,output reg [15:0] out_mask,
    output reg [127:0] out_tag,
    output wire advance,busy,
    output reg [3:0] fault,output reg [3:0] fault_lane
);
    reg [1:0] vp,gp,firstp,lastp;
    reg [3:0] kp[0:1];reg [15:0] mp[0:1];reg [127:0] tp[0:1];
    reg [3:0] expected_k,saved_count;
    reg [15:0] saved_mask;reg saved_signed;reg [127:0] saved_tag;
    reg signed [31:0] acc[0:15];
    assign advance=rst_n&&!clear&&run_ce&&(!out_valid||out_ready);
    assign in_ready=advance&&fault==0;
    assign busy=(|vp)||out_valid;
    wire take=in_valid&&in_ready;
    reg [3:0] front_error,front_lane;
    integer i,j_front,j_return;
    reg [15:0] bad_weight_flags;
    always @* begin
        bad_weight_flags=0;
        for(j_front=0;j_front<16;j_front=j_front+1)
            bad_weight_flags[j_front]=in_mask[j_front]&&(in_w[8*j_front+:8]==8'h80);
        front_error=0;front_lane=0;
        if(in_k!=expected_k || !(in_k_count==1 || in_k_count==9) || in_k>=in_k_count)
            front_error=2;
        else if(in_k!=0 && (in_k_count!=saved_count || in_mask!=saved_mask ||
                             input_signed!=saved_signed || in_tag!=saved_tag))front_error=2;
        else if(|bad_weight_flags)begin
            front_error=1;
            for(j_front=15;j_front>=0;j_front=j_front-1)
                if(bad_weight_flags[j_front])front_lane=j_front;
        end
    end
    wire [7:0] bad_leaf;
    wire [15:0] overflows;
    wire [511:0] sums;
    genvar p;
    generate for(p=0;p<8;p=p+1)begin: pair
        wire signed [23:0] p0,p1;wire lv,lb;wire [7:0] lk;wire [31:0] le;
        wire enabled=in_mask[2*p]||in_mask[2*p+1];
        b03_full_mul_pair leaf(.clk(clk),.rst_n(rst_n),.clear(clear),.run_ce(advance),
            .in_valid(take&&front_error==0&&enabled),.input_signed(input_signed),
            .in_a0(take&&in_mask[2*p]?in_a[16*p+:8]:8'd0),
            .in_a1(take&&in_mask[2*p+1]?in_a[16*p+8+:8]:8'd0),
            .in_w0(take&&in_mask[2*p]?in_w[16*p+:8]:8'd0),
            .in_w1(take&&in_mask[2*p+1]?in_w[16*p+8+:8]:8'd0),
            .in_k({4'd0,in_k}),.in_epoch(in_tag[31:0]),
            .product0(p0),.product1(p1),.out_valid(lv),.out_k(lk),.out_epoch(le),.busy(lb));
        if (ENABLE_DIAGNOSTICS) begin : g_diag_leaf
            assign bad_leaf[p]=(mp[1][2*p]||mp[1][2*p+1])&&
                (!lv||lk!={4'd0,kp[1]}||le!=tp[1][31:0]);
        end else begin : g_no_diag_leaf
            assign bad_leaf[p]=1'b0;
        end
        wire signed [32:0] a0=firstp[1]?33'sd0:$signed({acc[2*p][31],acc[2*p]});
        wire signed [32:0] a1=firstp[1]?33'sd0:$signed({acc[2*p+1][31],acc[2*p+1]});
        wire signed [32:0] s0=a0+$signed({{9{p0[23]}},p0});
        wire signed [32:0] s1=a1+$signed({{9{p1[23]}},p1});
        assign sums[64*p+:32]=s0[31:0];assign sums[64*p+32+:32]=s1[31:0];
        if (ENABLE_DIAGNOSTICS) begin : g_diag_overflow
            assign overflows[2*p]=mp[1][2*p]&&(s0[32]!=s0[31]);
            assign overflows[2*p+1]=mp[1][2*p+1]&&(s1[32]!=s1[31]);
        end else begin : g_no_diag_overflow
            assign overflows[2*p]=1'b0;
            assign overflows[2*p+1]=1'b0;
        end
    end endgenerate
    reg [3:0] return_error,return_lane;
    reg [15:0] return_bad_flags;
    always @* begin
        return_bad_flags=0;
        return_error=0;return_lane=0;
        if (ENABLE_DIAGNOSTICS) begin
            for(j_return=0;j_return<16;j_return=j_return+1)
                return_bad_flags[j_return]=mp[1][j_return]&&bad_leaf[j_return/2];
            if(vp[1]&&gp[1])begin
                if(|return_bad_flags)begin
                    return_error=3;
                    for(j_return=15;j_return>=0;j_return=j_return-1)
                        if(return_bad_flags[j_return])return_lane=j_return;
                end else if(|overflows)begin
                    return_error=4;
                    for(j_return=15;j_return>=0;j_return=j_return-1)
                        if(overflows[j_return])return_lane=j_return;
                end
            end
        end
    end
    wire fault_now=return_error!=0 || (take&&front_error!=0);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            vp<=0;gp<=0;firstp<=0;lastp<=0;expected_k<=0;saved_count<=0;
            saved_mask<=0;saved_signed<=0;saved_tag<=0;
            out_valid<=0;out_psum<=0;out_mask<=0;out_tag<=0;fault<=0;fault_lane<=0;
            for(i=0;i<16;i=i+1)acc[i]<=0;
            for(i=0;i<2;i=i+1)begin kp[i]<=0;mp[i]<=0;tp[i]<=0;end
        end else if(clear)begin
            vp<=0;gp<=0;firstp<=0;lastp<=0;expected_k<=0;saved_count<=0;
            saved_mask<=0;saved_signed<=0;saved_tag<=0;
            out_valid<=0;out_psum<=0;out_mask<=0;out_tag<=0;fault<=0;fault_lane<=0;
            for(i=0;i<16;i=i+1)acc[i]<=0;
            for(i=0;i<2;i=i+1)begin kp[i]<=0;mp[i]<=0;tp[i]<=0;end
        end else if(advance)begin
            vp<={vp[0],take};gp<={gp[0],take&&front_error==0};
            firstp<={firstp[0],in_k==0};lastp<={lastp[0],in_k+1==in_k_count};
            kp[0]<=in_k;kp[1]<=kp[0];mp[0]<=in_mask;mp[1]<=mp[0];tp[0]<=in_tag;tp[1]<=tp[0];
            if(out_valid)out_valid<=0;
            if(take&&front_error==0)begin
                expected_k<=in_k+1==in_k_count?0:in_k+1;
                if(in_k==0)begin saved_count<=in_k_count;saved_mask<=in_mask;saved_signed<=input_signed;saved_tag<=in_tag;end
            end
            if(fault==0&&fault_now)begin
                fault<=return_error!=0?return_error:front_error;
                fault_lane<=return_error!=0?return_lane:front_lane;
                out_valid<=0;
            end
            if(vp[1]&&gp[1]&&fault==0&&!fault_now)begin
                for(i=0;i<16;i=i+1)acc[i]<=mp[1][i]?$signed(sums[32*i+:32]):32'sd0;
                if(lastp[1])begin
                    out_valid<=1;out_mask<=mp[1];out_tag<=tp[1];
                    for(i=0;i<16;i=i+1)out_psum[32*i+:32]<=mp[1][i]?sums[32*i+:32]:32'd0;
                end
            end
        end
    end
endmodule
