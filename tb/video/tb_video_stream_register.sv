`timescale 1ns/1ps
module tb_video_stream_register #(
    parameter integer TEST_WIDTH=48
);
    reg clk=0,reset_n=1;
    reg s_valid=0,m_ready=0;
    reg [TEST_WIDTH-1:0] s_data=0;
    wire s_ready,m_valid;
    wire [TEST_WIDTH-1:0] m_data;
    reg [TEST_WIDTH-1:0] expected[0:8191],held;
    reg previous_stall=0,last_take=0;
    reg [31:0] random_state=32'h8765a321;
    integer head=0,tail=0,sent_words=0,mode=0,cycles=0,epoch=0;
    integer full_cycles=0,stall_samples=0,replacements=0,n;
    always #5 clk=~clk;
`ifdef VIDEO_STREAM_REGISTER_MISSING
    // The old unregistered connection is the timing-path reproduction.
    assign s_ready=reset_n&&m_ready;
    assign m_valid=reset_n&&s_valid;
    assign m_data=s_data;
`else
    video_stream_register #(.DATA_WIDTH(TEST_WIDTH)) dut(.*);
`endif
    task automatic check(input bit ok,input string message);
        if(ok!==1'b1)$fatal(1,"STREAM REGISTER: %s",message);
    endtask
    function automatic [TEST_WIDTH-1:0] pattern(input integer index);
        pattern={index[15:0],~index[15:0],(index[15:0]^16'hb67d)}^{48{epoch[0]}};
    endfunction
    // Independent accepted-word queue. It is not derived from DUT occupancy.
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin head=0;tail=0;sent_words=0;cycles=0;previous_stall=0;last_take=0;full_cycles=0;end
        else begin
            cycles=cycles+1;
            if(previous_stall)begin
                check(m_valid && m_data===held,"held output must survive backpressure");
                stall_samples=stall_samples+1;
            end
            if(m_valid)check(head<tail,"output cannot bypass a registered acceptance");
            if(m_valid&&m_ready)begin
                check(m_data===expected[head],"no loss, duplication, corruption or reordering");
                head=head+1;
            end
            last_take=s_valid&&s_ready;
            if(last_take)begin
                check(tail<8192,"scoreboard bound");
                expected[tail]=s_data;tail=tail+1;sent_words=sent_words+1;
            end
            if(last_take&&m_valid&&m_ready)replacements=replacements+1;
            if(mode==1)begin
                full_cycles=full_cycles+1;
                if(full_cycles>4)check(m_valid&&s_ready,"full throughput must have no bubbles");
            end else full_cycles=0;
            previous_stall=m_valid&&!m_ready;held=m_data;
        end
    end
    always @(negedge clk)begin
        if(!reset_n)begin s_valid=0;m_ready=0;end
        else begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            case(mode)
                1,3:m_ready=1;
                2:m_ready=(cycles%97>=23)&&random_state[0];
                default:m_ready=0;
            endcase
            if(last_take||!s_valid)begin
                s_valid=(mode==1||mode==4||(mode==2&&random_state[2:1]!=0));
                s_data=pattern(sent_words);
            end
        end
    end
    task automatic reset_stream;
        begin
            @(negedge clk);#1;reset_n=0;mode=0;
            #1;check(!m_valid&&!s_ready,"reset revokes ownership and input acceptance");
            repeat(3)@(negedge clk);
            #1;reset_n=1;
        end
    endtask
    task automatic drain;
        begin
            @(negedge clk);#1;mode=3;
            repeat(10)@(negedge clk);
            #1;check(head==tail&&!m_valid,"all accepted words must retire");
        end
    endtask
    initial begin
        reset_stream;
        @(negedge clk);#1;mode=1;s_valid=1;s_data=pattern(sent_words);m_ready=1;
        #1;check(!m_valid,"must register source instead of combinational bypass");
        repeat(260)@(negedge clk);
        drain;
        mode=2;
        repeat(5000)@(negedge clk);
        drain;
        check(stall_samples>100&&replacements>200,"random stalls and simultaneous replacement covered");
        mode=4;
        repeat(10)@(negedge clk);
        #1;check(m_valid&&!s_ready,"full stalled ownership before coordinated reset");
        epoch=1;reset_stream;
        mode=1;
        repeat(40)@(negedge clk);
        drain;
        $display("VIDEO_STREAM_REGISTER_PASS width=%0d stalls=%0d replacements=%0d",TEST_WIDTH,stall_samples,replacements);
        $finish;
    end
    initial begin #1000000;$fatal(1,"stream register watchdog");end
endmodule
