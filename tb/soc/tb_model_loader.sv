`timescale 1ns/1ps
module tb_model_loader #(parameter integer SERIAL=0);
 reg clk=0; always #4 clk=~clk;
 reg rst=0,healthy=1,rx_valid=0,tx_ready=1; reg[7:0] rx_data=0;
 wire rx_ready,tx_valid,sealed,fault; wire[7:0] tx_data;
 wire awvalid,wvalid,wlast,bready; wire[31:0] awaddr; wire[127:0] wdata;
 reg awready=0,wready=0,bvalid=0; reg[1:0] bresp=0;
 integer checks=0,cycles=0,writes=0,beats=0,ack_count=0,ack_status=0,ack_segment=0;
 reg[31:0] ack_offset=0; reg[7:0] reply[0:11]; reg[31:0] saved_addr=0;
 reg[7:0] mem[0:1535]; reg[7:0] payload[0:255];
 reg hold_b=0,hold_aw=0,hold_w=0,injected_rx_error=0; integer delay_b=0,i,j;
 reg serial_rx=1;
 wire wire_rx_valid,wire_rx_error,wire_tx_ready,serial_tx,reply_valid,reply_error;
 wire [7:0] wire_rx_data,reply_data;
 triha_uart_rx #(.DIVISOR(16)) receive(.clk_i(clk),.rst_ni(rst),.rx_i(serial_rx),
   .ready_i(rx_ready),.valid_o(wire_rx_valid),.data_o(wire_rx_data),.error_o(wire_rx_error));
 triha_uart_tx #(.DIVISOR(16)) transmit(.clk_i(clk),.rst_ni(rst),
   .valid_i(tx_valid&&SERIAL),.data_i(tx_data),.ready_o(wire_tx_ready),.tx_o(serial_tx));
 triha_uart_rx #(.DIVISOR(16)) host_receive(.clk_i(clk),.rst_ni(rst),.rx_i(serial_tx),
   .ready_i(1'b1),.valid_o(reply_valid),.data_o(reply_data),.error_o(reply_error));
 triha_model_loader #(.PROGRAM_BYTES(256),.PARAMETER_BYTES(256),.TABLE_BYTES(256),.HEADS_BYTES(256),
   .PROGRAM_CRC(32'h29058c73),.PARAMETER_CRC(32'h29058c73),.TABLE_CRC(32'h29058c73),
   .HEADS_CRC(32'h29058c73),.RX_TIMEOUT_CYCLES(2000)) dut(
   .clk_i(clk),.rst_ni(rst),.healthy_i(healthy),.rx_valid_i(SERIAL?wire_rx_valid:rx_valid),.rx_ready_o(rx_ready),.rx_data_i(SERIAL?wire_rx_data:rx_data),
   .rx_error_i(injected_rx_error||(SERIAL&&wire_rx_error)),.tx_valid_o(tx_valid),.tx_ready_i(SERIAL?wire_tx_ready:tx_ready),.tx_data_o(tx_data),
   .model_sealed_o(sealed),.fault_o(fault),.m_awvalid_o(awvalid),.m_awready_i(awready),.m_awaddr_o(awaddr),
   .m_wvalid_o(wvalid),.m_wready_i(wready),.m_wdata_o(wdata),.m_wlast_o(wlast),
   .m_bvalid_i(bvalid),.m_bready_o(bready),.m_bresp_i(bresp));
 task check(input bit cond,input string why);begin checks=checks+1;if(!cond)$fatal(1,"MODEL_LOADER_FAIL %s",why);end endtask
 function[31:0] crc_byte(input[31:0] c,input[7:0] b);integer n;reg[31:0] v;begin
   v=c^b;for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end endfunction
 task byte_in(input[7:0] value);integer b;begin
   if(SERIAL)begin
     @(negedge clk);serial_rx=0;repeat(16)@(negedge clk);
     for(b=0;b<8;b=b+1)begin serial_rx=value[b];repeat(16)@(negedge clk);end
     serial_rx=1;repeat(16)@(negedge clk);
   end else begin
     @(negedge clk);rx_valid=1;rx_data=value;
     @(posedge clk);while(!rx_ready)@(posedge clk);
     @(negedge clk);rx_valid=0;
   end
 end endtask
 task word_in(input[31:0] v);integer n;begin for(n=0;n<4;n=n+1)byte_in(v[8*n+:8]);end endtask
 task packet(input[31:0] seg,input[31:0] offset,input bit corrupt);integer n;reg[31:0] c;begin
   c=32'hffffffff;for(n=0;n<256;n=n+1)c=crc_byte(c,payload[n]);
   word_in(32'h31424854);word_in(seg);word_in(offset);word_in((~c)^{31'd0,corrupt});
   for(n=0;n<256;n=n+1)byte_in(payload[n]);
 end endtask
 task ack(input integer expected);begin
   wait(ack_count==12);@(negedge clk);
   check({reply[3],reply[2],reply[1],reply[0]}==32'h31414854,"reply magic");
   ack_status=reply[4];ack_segment=reply[5];ack_offset={reply[11],reply[10],reply[9],reply[8]};
   check(ack_status==expected,"reply status");check(reply[6]==0&&reply[7]==0,"reserved");ack_count=0;
   if(SERIAL)repeat(20)@(negedge clk);
 end endtask
 task reset_all;begin @(negedge clk);rst=0;repeat(4)@(negedge clk);rst=1;repeat(3)@(negedge clk);end endtask
 always @(posedge clk)begin
   cycles<=cycles+1;
   if(!rst)begin awready<=0;wready<=0;bvalid<=0;beats<=0;delay_b<=0;end
   else begin
     awready<=!hold_aw&&cycles%5==0&&!bvalid&&beats==0;
     wready<=!hold_w&&cycles%3==0&&beats>0;
     if(awvalid&&awready)begin check(beats==0,"one transaction");saved_addr<=awaddr;beats<=16;writes<=writes+1;end
     if(wvalid&&wready)begin
       check(wlast==(beats==1),"WLAST exact");
       for(j=0;j<16;j=j+1)mem[(writes-1)*256+(16-beats)*16+j]<=wdata[j*8+:8];
       beats<=beats-1;if(beats==1)delay_b<=12;
     end
     if(delay_b!=0&&!hold_b)begin delay_b<=delay_b-1;if(delay_b==1)bvalid<=1;end
     if(bvalid&&bready)bvalid<=0;
     if(SERIAL&&reply_error)$fatal(1,"ACK UART framing/overrun");
     if(SERIAL?reply_valid:(tx_valid&&tx_ready))begin
       check(ack_count<12,"reply overflow");reply[ack_count]<=SERIAL?reply_data:tx_data;ack_count<=ack_count+1;
     end
   end
 end
 initial begin
   for(i=0;i<256;i=i+1)payload[i]=i;
   reset_all();check(!sealed,"reset unsealed");
   packet(0,0,1);ack(1);check(writes==0&&!sealed,"bad CRC no DDR writes");
   packet(1,0,0);ack(2);check(writes==0,"wrong segment no DDR writes");
   packet(0,256,0);ack(2);check(writes==0,"wrong offset no DDR writes");
   for(i=0;i<6;i=i+1)begin
     hold_b=1;packet(i,0,0);wait(delay_b!=0);repeat(20)@(negedge clk);
     check(!sealed&&ack_count==0,"B debt prevents seal and ACK");hold_b=0;ack(0);
     check(ack_segment==i+1&&ack_offset==0,"next segment identity");
     check(writes==i+1,"one packet one burst");
     case(i)
       0:check(saved_addr==32'h82b00000,"program address");
       1:check(saved_addr==32'h8378c200,"parameter address");
       2:check(saved_addr==32'h82b10000,"table address");
       3:check(saved_addr==32'h82900000,"HEAD A");
       4:check(saved_addr==32'h82940000,"HEAD B");
       5:check(saved_addr==32'h82980000,"HEAD C");
     endcase
     packet(i,0,0);ack(0);check(writes==i+1,"lost ACK retry is idempotent");
   end
   check(sealed&&!fault,"all segments sealed after B");
   for(i=0;i<1536;i=i+1)check(mem[i]==(i%256),"DDR bytes exact");
   packet(0,0,0);ack(5);check(writes==6&&sealed,"sealed image immutable");
   healthy=0;repeat(3)@(negedge clk);check(fault&&!sealed,"health loss revokes seal");
   healthy=1;repeat(3)@(negedge clk);check(fault&&!sealed,"fault sticky until shared reset");
   reset_all();check(!fault&&!sealed,"coordinated reset clears state");
   payload[0]=8'hff;packet(0,0,0);ack(3);check(writes==6&&!sealed,"whole image CRC enforced");payload[0]=0;
   bresp=2;packet(0,0,0);ack(4);check(fault&&!sealed,"B error never seals");
   bresp=0;reset_all();
   word_in(32'h31424854);word_in(0);ack(6);
   check(!fault&&!sealed,"partial header timeout remains retryable");
   word_in(32'h31424854);@(negedge clk);injected_rx_error=1;
   @(negedge clk);injected_rx_error=0;ack(6);
   check(!fault&&!sealed,"parsing framing error remains retryable");
   hold_aw=1;packet(0,0,0);wait(awvalid);
   @(negedge clk);injected_rx_error=1;@(negedge clk);injected_rx_error=0;
   repeat(8)@(negedge clk);
   check(awvalid&&fault&&!sealed,"error preserves outstanding AW");
   hold_aw=0;ack(4);check(beats==0&&!bvalid,"faulted AW drains all W and B");
   reset_all();hold_w=1;packet(0,0,0);wait(wvalid);
   @(negedge clk);injected_rx_error=1;@(negedge clk);injected_rx_error=0;
   repeat(8)@(negedge clk);
   check(wvalid&&fault&&!sealed,"error preserves held W");
   hold_w=0;ack(4);check(beats==0&&!bvalid,"faulted W drains all W and B");
   $display("PASS MODEL_LOADER serial=%0d checks=%0d writes=%0d",SERIAL,checks,writes);$finish;
 end
 initial begin #20000000;$fatal(1,"MODEL_LOADER_TIMEOUT");end
endmodule
