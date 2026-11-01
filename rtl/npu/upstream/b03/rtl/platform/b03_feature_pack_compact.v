// Ordinary 32-byte reception; arithmetic consumption is gated by run_ce.
// Tail bank is always zero because each input appends exactly 32 bytes.
module b03_feature_pack_compact(
 input wire clk,rst_n,clear,run_ce,
 input wire in_valid,output wire in_ready,input wire [255:0] in_data,
 input wire [3:0] out_take,output wire out_valid,output wire [63:0] out_data,
 input wire out_ready,output reg [6:0] count
);
 reg [39:0] bank[0:7];
 reg [2:0] used[0:7];
 reg [2:0] head;
 wire incoming=in_valid&&in_ready;
 wire consume=run_ce&&out_valid&&out_ready;
 assign in_ready=rst_n&&!clear&&count<=8;
 assign out_valid=rst_n&&!clear&&out_take>=1&&out_take<=8&&count>=out_take;
 wire [63:0] heads;
 wire [127:0] repeated_heads={heads,heads};
 assign out_data=repeated_heads[{head,3'b000}+:64];
 genvar b;
 generate for(b=0;b<8;b=b+1)begin:BANKS
   wire [2:0] distance=b-head;
   wire pop=consume&&{1'b0,distance}<out_take;
   wire carry=(used[b]!=0)&&!pop;
   wire [31:0] append_data={in_data[8*(b+24)+:8],in_data[8*(b+16)+:8],
                          in_data[8*(b+8)+:8],in_data[8*b+:8]};
   assign heads[8*b+:8]=bank[b][7:0];
   always @(posedge clk or negedge rst_n)begin
     if(!rst_n)begin bank[b]<=0;used[b]<=0;end
     else if(clear)begin bank[b]<=0;used[b]<=0;end
     else if(incoming)begin
       // incoming implies at most one old byte per bank, before any pop.
       bank[b]<=carry?{append_data,bank[b][7:0]}:{8'd0,append_data};
       used[b]<=carry?3'd5:3'd4;
     end else if(pop)begin bank[b]<=bank[b]>>8;used[b]<=used[b]-1'b1;end
   end
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin count<=0;head<=0;end
   else if(clear)begin count<=0;head<=0;end
   else begin
     if(incoming||consume)count<=count+(incoming?7'd32:7'd0)-(consume?{3'd0,out_take}:7'd0);
     if(consume)head<=head+out_take[2:0];
   end
 end
endmodule
