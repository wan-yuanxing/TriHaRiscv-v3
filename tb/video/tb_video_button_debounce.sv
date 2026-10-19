`timescale 1ns/1ps
module tb_video_button_debounce #(
    parameter integer TEST_HZ=1001, TEST_MS=20, ACTIVE_LOW=1, FULL_THRESHOLD=0
);
    localparam integer N=(64'd1*TEST_HZ*TEST_MS+999)/1000;
    reg clk=0,reset_n=0,button_async=ACTIVE_LOW?1'b1:1'b0;
    wire pressed,press_pulse;
    integer checks=0,pulses=0,n;
    always #4 clk=~clk;
    video_button_debounce #(.CLOCK_HZ(TEST_HZ),.STABLE_MS(TEST_MS),.ACTIVE_LOW(ACTIVE_LOW)) dut(.*);
    task automatic check(input bit ok,input string message);
        begin checks++;if(ok!==1'b1)$fatal(1,"BUTTON: %s",message);end
    endtask
    task automatic cycle;
        begin @(posedge clk);#1;if(press_pulse)pulses++;end
    endtask
    task automatic drive(input reg logical_pressed);
        begin @(negedge clk);button_async=ACTIVE_LOW?!logical_pressed:logical_pressed;end
    endtask
    task automatic exact_transition(input bit down);
        integer j,before_pulses;
        begin
            before_pulses=pulses;drive(down);
            for(j=1;j<=N+2;j++)begin
                cycle;
                check(pressed==(j==N+2?down:!down),"exact N samples after two synchronizer stages");
                check(press_pulse==(down&&j==N+2),"one press event only at threshold");
            end
            repeat(7)begin cycle;check(!press_pulse,"held level cannot repeat");end
            check(pulses==before_pulses+(down?1:0),"one event per qualified press");
        end
    endtask
    task automatic reset_released;
        begin
            @(negedge clk);reset_n=0;button_async=ACTIVE_LOW?1'b1:1'b0;
            cycle;check(!pressed&&!press_pulse,"reset releases state");
            @(negedge clk);reset_n=1;
            repeat(3)cycle;
        end
    endtask
    initial begin
        reset_released;
        exact_transition(1);exact_transition(0);
        if(!FULL_THRESHOLD)begin
            if(N>1)begin
                // Every pulse is shorter than qualification, even after CDC delay.
                for(n=0;n<8;n++)begin drive(1);repeat(N-1)cycle;drive(0);repeat(N+3)cycle;end
                check(!pressed&&pulses==1,"press bounce is rejected");
            end
            exact_transition(1);
            if(N>1)begin
                drive(0);repeat(N-1)cycle;drive(1);repeat(N+4)cycle;
                check(pressed&&pulses==2,"short release cannot rearm");
            end
            exact_transition(0);
            // X cannot qualify a new press or erase an already qualified state.
            drive(1'bx);repeat(N+4)begin cycle;check(!pressed&&!press_pulse,"unknown input fails closed");end
            exact_transition(1);
            drive(1'bx);repeat(N+4)begin cycle;check(pressed&&!press_pulse,"unknown held input cannot repeat");end
            drive(1);repeat(N+3)cycle;
            @(negedge clk);reset_n=0;cycle;check(!pressed&&!press_pulse,"reset while held");
            @(negedge clk);reset_n=1;
            for(n=1;n<=N+2;n++)begin cycle;check(press_pulse==(n==N+2),"held key after reset qualifies once");end
            repeat(N+4)begin cycle;check(!press_pulse,"held after reset does not repeat");end
        end
        $display("VIDEO_BUTTON_DEBOUNCE_PASS hz=%0d ms=%0d cycles=%0d checks=%0d",TEST_HZ,TEST_MS,N,checks);
        $finish;
    end
    initial begin #200000000;$fatal(1,"button watchdog");end
endmodule
