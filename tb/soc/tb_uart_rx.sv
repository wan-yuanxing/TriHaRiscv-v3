`timescale 1ns/1ps
module tb_uart_rx;
    reg clk=0; always #4 clk=~clk;
    reg rst=0,rx=1,ready=1;
    wire valid,error;
    wire [7:0] data;
    integer received=0,errors=0,checks=0,i;
    reg [7:0] last;
    triha_uart_rx #(.DIVISOR(16)) dut(.clk_i(clk),.rst_ni(rst),.rx_i(rx),
        .ready_i(ready),.valid_o(valid),.data_o(data),.error_o(error));
    always @(posedge clk) if(rst) begin
        if(valid&&ready)begin received=received+1;last=data;end
        if(error)errors=errors+1;
    end
    task check(input bit ok,input string why);begin
        checks=checks+1;if(!ok)$fatal(1,"UART_RX_FAIL %s received=%0d errors=%0d",why,received,errors);
    end endtask
    task bit_in(input bit value,input integer ticks);begin
        rx=value;repeat(ticks)@(negedge clk);
    end endtask
    task byte_in(input [7:0] value,input integer ticks,input bit stop);integer n;begin
        bit_in(0,ticks);for(n=0;n<8;n=n+1)bit_in(value[n],ticks);bit_in(stop,ticks);
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;repeat(5)@(negedge clk);
        check(!valid&&errors==0,"reset idle");
        bit_in(0,3);bit_in(1,32);check(received==0&&errors==0,"short start rejected");
        for(i=0;i<256;i=i+1)begin
            byte_in(i,16,1);check(received==i+1&&last==i,"all bytes back to back");
        end
        byte_in(8'ha5,16,0);bit_in(1,32);
        check(received==256&&errors==1,"bad stop never delivers byte");
        ready=0;byte_in(8'h3c,16,1);repeat(20)@(negedge clk);
        check(valid&&data==8'h3c,"backpressure holds byte");
        byte_in(8'hc3,16,1);repeat(10)@(negedge clk);
        check(valid&&data==8'h3c&&errors==2,"overrun reports loss and keeps oldest");
        ready=1;repeat(3)@(negedge clk);check(received==257&&last==8'h3c,"held byte delivered once");
        byte_in(8'h96,16,1);check(received==258&&last==8'h96,"recovery after overrun");
        bit_in(0,24);rst=0;repeat(4)@(negedge clk);rx=1;rst=1;repeat(32)@(negedge clk);
        check(!valid&&received==258,"reset aborts partial byte");
        byte_in(8'h5a,16,1);check(received==259&&last==8'h5a,"receive after reset");
        $display("PASS UART_RX checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"UART_RX_TIMEOUT");end
endmodule
