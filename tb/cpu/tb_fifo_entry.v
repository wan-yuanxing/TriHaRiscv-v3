/* Whole-state comparison against the frozen compact FIFO before the
 * fixed-entry rewrite, including inactive payload and four-state controls.
 */
`timescale 1ns/1ps
module tb_fifo_entry #(parameter BROKEN=0,parameter DEPTH=2);
    reg clk=0,rst=1,flush=0,push=0,pop0=0,pop1=0;
    reg [31:0] pc=32'h80001000,rng=32'h124578ab;
    reg [63:0] data=64'h12345678feed5678;
    reg [1:0] pred=0;
    reg [9:0] info0=10'h321,info1=10'h123;
    reg hint0=0,hint1=1;
    integer n,k,checks=0;
    always #5 clk=~clk;
    triha_fetch_fifo #(.OPC_INFO_W(10),.DEPTH(DEPTH)) u_dut (
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),.pc_in_i(pc),
        .pred_in_i(pred),.data_in_i(data),.info0_in_i(info0),.info1_in_i(info1),.accept_o(),
        .valid0_o(),.pc0_out_o(),.data0_out_o(),.info0_out_o(),.pop0_i(pop0),
        .valid1_o(),.pc1_out_o(),.data1_out_o(),.info1_out_o(),.pop1_i(pop1),
        .csr0_in_i(hint0),.csr1_in_i(hint1),.csr0_out_o(),.csr1_out_o());
    triha_fifo_reference #(.OPC_INFO_W(10),.DEPTH(DEPTH)) u_ref (
        .clk_i(clk),.rst_i(rst),.flush_i(flush),.push_i(push),.pc_in_i(pc),
        .pred_in_i(pred),.data_in_i(data),.info0_in_i(info0),.info1_in_i(info1),.accept_o(),
        .valid0_o(),.pc0_out_o(),.data0_out_o(),.info0_out_o(),.pop0_i(pop0),
        .valid1_o(),.pc1_out_o(),.data1_out_o(),.info1_out_o(),.pop1_i(pop1),
        .csr0_in_i(hint0),.csr1_in_i(hint1),.csr0_out_o(),.csr1_out_o());
    task check;
        begin
            #1;checks=checks+1;
            if({u_dut.valid0_o,u_dut.valid1_o,u_dut.accept_o,u_dut.pc0_out_o}!==
               {u_ref.valid0_o,u_ref.valid1_o,u_ref.accept_o,u_ref.pc0_out_o})
                $fatal(1,"FIFO_ENTRY_FAIL control_or_head");
            if(u_dut.count_q!==u_ref.count_q) $fatal(1,"FIFO_ENTRY_FAIL count");
            for(k=0;k<2*DEPTH;k=k+1)
                if({u_dut.pc_q[k],u_dut.data_q[k],u_dut.info_q[k],u_dut.csr_q[k]}!==
                   {u_ref.pc_q[k],u_ref.data_q[k],u_ref.info_q[k],u_ref.csr_q[k]})
                    $fatal(1,"FIFO_ENTRY_FAIL state index=%0d count=%0d pop=%b%b pred=%b",k,u_ref.count_q,pop1,pop0,pred);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;push=1;
        @(negedge clk);check;pc=pc+8;
        @(negedge clk);check;push=0;pop0=1'bx;pop1=0;
        @(negedge clk);check;pop0=0;pop1=1'bx;
        @(negedge clk);check;pop0=1'bx;pop1=1'bx;
        @(negedge clk);check;pop0=0;pop1=0;push=1;pred=2'b0x;
        @(negedge clk);check;pred=0;
        if(BROKEN) force u_dut.pc0_out_o=0;
        for(n=0;n<4000;n=n+1)begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            push=rng[0];pop0=rng[1];pop1=rng[2];flush=rng[7:3]==0;
            pred=rng[9:8];pc=(rng[10] && u_ref.count_q>0) ?
                ((u_ref.pc_q[u_ref.count_q-1]&32'hfffffff8)+8) : {4'h8,rng[27:3],3'b0};
            data={rng,~rng};info0=rng[9:0];info1=rng[19:10];hint0=rng[11];hint1=rng[12];
            if(n%53==0)pop0=1'bx;
            if(n%57==0)pop1=1'bx;
            if(n%61==0)pred[0]=1'bx;
            if(n%67==0)push=1'bx;
            if(n%71==0)flush=1'bx;
            if(n%73==0)begin data=64'hx;info0=10'hx;hint1=1'bx;end
            @(negedge clk);check;
        end
        $display("FIFO_ENTRY_PASS checks=%0d full_state_and_unknown_controls",checks);$finish;
    end
endmodule

// Frozen pre-entry-rewrite compact FIFO oracle (diagnostic only).
module triha_fifo_reference
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
    parameter WIDTH   = 64,
    parameter DEPTH   = 2,
    parameter ADDR_W  = 1,
    parameter OPC_INFO_W = 10
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
     input                  clk_i
    ,input                  rst_i

    ,input                  flush_i

    // Input side
    ,input                  push_i
    ,input  [31:0]          pc_in_i
    ,input  [1:0]           pred_in_i
    ,input  [WIDTH-1:0]     data_in_i
    ,input [OPC_INFO_W-1:0] info0_in_i
    ,input [OPC_INFO_W-1:0] info1_in_i
    ,output                 accept_o

    // Outputs
    ,output                 valid0_o
    ,output  [31:0]         pc0_out_o
    ,output [(WIDTH/2)-1:0] data0_out_o
    ,output[OPC_INFO_W-1:0] info0_out_o
    ,input                  pop0_i

    ,output                 valid1_o
    ,output  [31:0]         pc1_out_o
    ,output [(WIDTH/2)-1:0] data1_out_o
    ,output[OPC_INFO_W-1:0] info1_out_o
    ,input                  pop1_i
    ,input                  csr0_in_i
    ,input                  csr1_in_i
    ,output                 csr0_out_o
    ,output                 csr1_out_o
);

// Compact a four-word instruction queue, keeping PC and all sideband fields
// with each word. Two outputs may cross an original 64-bit fetch boundary.
// No combinational push-through and no change to memory response latency.
localparam WORDS = 2*DEPTH;
reg [31:0] pc_q[0:WORDS-1];
reg [WIDTH/2-1:0] data_q[0:WORDS-1];
reg [OPC_INFO_W-1:0] info_q[0:WORDS-1];
reg csr_q[0:WORDS-1];
reg [ADDR_W+1:0] count_q;
wire pop_a_w = pop0_i && valid0_o;
wire pop_b_w = pop1_i && valid1_o;
wire push_w = push_i && accept_o;
integer i, j, next_count;
assign accept_o = count_q <= WORDS-2;
assign valid0_o = count_q != 0;
assign valid1_o = count_q > 1 && pc_q[1] == pc_q[0] + 32'd4;
assign pc0_out_o=pc_q[0]; assign pc1_out_o=pc_q[1];
assign data0_out_o=data_q[0]; assign data1_out_o=data_q[1];
assign info0_out_o=info_q[0]; assign info1_out_o=info_q[1];
assign csr0_out_o=csr_q[0]; assign csr1_out_o=csr_q[1];
always @(posedge clk_i or posedge rst_i)
if(rst_i) begin
    count_q<=0;
    for(i=0;i<WORDS;i=i+1) begin
        pc_q[i]<=0;data_q[i]<=0;info_q[i]<=0;csr_q[i]<=0;
    end
end else if(flush_i) begin
    count_q<=0;
end else begin
    // Remove only acknowledged words. Parallel B-only consumption is retained
    // for interface completeness; the issue unit consumes B with A in practice.
    j=0;
    for(i=0;i<WORDS;i=i+1) begin
        if(i<count_q && !(i==0 && pop_a_w) && !(i==1 && pop_b_w)) begin
            pc_q[j]<=pc_q[i];data_q[j]<=data_q[i];
            info_q[j]<=info_q[i];csr_q[j]<=csr_q[i];j=j+1;
        end
    end
    next_count=j;
    if(push_w) begin
        pc_q[next_count]<={pc_in_i[31:3],3'b000};data_q[next_count]<=data_in_i[WIDTH/2-1:0];
        info_q[next_count]<=info0_in_i;csr_q[next_count]<=csr0_in_i;next_count=next_count+1;
        if(!pred_in_i[0]) begin
            pc_q[next_count]<={pc_in_i[31:3],3'b100};data_q[next_count]<=data_in_i[WIDTH-1:WIDTH/2];
            info_q[next_count]<=info1_in_i;csr_q[next_count]<=csr1_in_i;next_count=next_count+1;
        end
    end
    count_q<=next_count;
end
endmodule
