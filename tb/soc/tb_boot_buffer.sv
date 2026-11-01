`timescale 1ns/1ps
module tb_boot_buffer;
    reg clk=0;always #4 clk=~clk;
    reg rst=0,write=0,start=0,ready=0;
    reg [7:0] address=0,byte_data=0;
    wire valid,last,busy;wire [127:0] data;
    integer checks=0,packet,byte_index,beat,delay_cycles,j;
    reg [127:0] held;
    triha_boot_buffer dut(.clk_i(clk),.rst_ni(rst),.write_i(write),.write_address_i(address),
        .write_data_i(byte_data),.start_i(start),.busy_o(busy),.valid_o(valid),.ready_i(ready),.data_o(data),.last_o(last));
    task check(input bit value,input string why);begin checks=checks+1;if(!value)$fatal(1,"BOOT_BUFFER_FAIL %s",why);end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        for(packet=0;packet<4;packet=packet+1)begin
            for(byte_index=0;byte_index<256;byte_index=byte_index+1)begin
                @(negedge clk);write=1;address=byte_index;byte_data=(byte_index*13+packet*71)%256;
            end
            @(negedge clk);write=0;start=1;@(negedge clk);start=0;
            for(beat=0;beat<16;beat=beat+1)begin
                wait(valid);@(negedge clk);held=data;
                check(last==(beat==15),"advertised last beat");
                for(j=0;j<16;j=j+1)check(data[j*8+:8]==((beat*16+j)*13+packet*71)%256,"byte order");
                for(delay_cycles=0;delay_cycles<beat%5;delay_cycles=delay_cycles+1)begin
                    @(negedge clk);check(valid&&data===held&&last==(beat==15),"stalled beat stable");
                end
                ready=1;@(negedge clk);ready=0;
            end
            check(!valid&&!busy,"all bytes retired");
        end
        start=1;@(negedge clk);start=0;repeat(9)@(negedge clk);
        rst=0;repeat(3)@(negedge clk);rst=1;repeat(40)@(negedge clk);
        check(!busy&&!valid,"reset aborts partially packed beat");
        $display("PASS BOOT_BUFFER checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"BOOT_BUFFER_TIMEOUT");end
endmodule
