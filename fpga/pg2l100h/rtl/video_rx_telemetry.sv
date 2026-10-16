`timescale 1ns/1ps
`default_nettype none
// Independent10MHz reference counts Gray-coded RX pixel edges over one gate.
// Stable-bus request/ack snapshot: source freezes data until next request;
// destination sees ack through2flops, waits another edge, then captures bus.
module video_rx_telemetry #(
    parameter integer STATUS_WIDTH=216,
    parameter integer GATE_CYCLES=100_000
)(input wire cfg_clk,pixel_clk,reset_n,input wire[STATUS_WIDTH-1:0]pixel_status,
    output reg[STATUS_WIDTH-1:0] snapshot,output wire snapshot_valid,
    output reg[31:0]pixel_hz,output wire clock_alive,frequency_good);
    localparam integer CW=GATE_CYCLES>1?$clog2(GATE_CYCLES):1;
    localparam integer HZ_SCALE=10_000_000/GATE_CYCLES;
    generate if(GATE_CYCLES<1 || 10_000_000%GATE_CYCLES!=0 || STATUS_WIDTH<1)begin:invalid_parameters
        initial $fatal(1,"Telemetry gate must be a positive exact divisor of10MHz");
    end endgenerate
    (* syn_preserve=1 *) reg[1:0] pixel_release;
    always @(posedge pixel_clk or negedge reset_n)
        if(!reset_n)pixel_release<=0;else pixel_release<={pixel_release[0],1'b1};
    wire pixel_reset_n=reset_n&&pixel_release[1];
    reg[31:0] counter,gray;
    reg request,ack;
    (* syn_preserve=1 *) reg[1:0] req_sync,ack_sync;
    reg[STATUS_WIDTH-1:0] stable_status;
    wire[31:0] next_counter=counter+1'b1;
    always @(posedge pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin counter<=0;gray<=0;req_sync<=0;ack<=0;stable_status<=0;end
        else begin
            counter<=next_counter;gray<=next_counter^(next_counter>>1);
            req_sync<={req_sync[0],request};
            if(req_sync[1]!=ack)begin stable_status<=pixel_status;ack<=req_sync[1];end
        end
    end
    (* syn_preserve=1 *) reg[31:0] gray_meta,gray_sync;
    reg[CW-1:0] gate_count;
    reg[31:0] previous;
    reg pending,capture_pending,have_snapshot;
    function automatic[31:0] decode_gray(input[31:0] value);
        integer n;
        begin decode_gray[31]=value[31];for(n=30;n>=0;n=n-1)decode_gray[n]=decode_gray[n+1]^value[n];end
    endfunction
    wire[31:0] count_now=decode_gray(gray_sync);
    wire[31:0] count_delta=count_now-previous;
    //10ms default; gate must divide reference Hz exactly. Count quantization is
    // at most a few pixel edges, well inside the VESA +/-0.5percent tolerance.
    wire[63:0] measured_hz={32'd0,count_delta}*HZ_SCALE;
    assign clock_alive=pixel_hz!=0;
    assign frequency_good=pixel_hz>=39_800_000&&pixel_hz<=40_200_000;
    assign snapshot_valid=have_snapshot&&clock_alive;
    always @(posedge cfg_clk or negedge reset_n)begin
        if(!reset_n)begin
            gray_meta<=0;gray_sync<=0;ack_sync<=0;gate_count<=0;previous<=0;
            request<=0;pending<=0;capture_pending<=0;have_snapshot<=0;snapshot<=0;pixel_hz<=0;
        end else begin
            gray_meta<=gray;gray_sync<=gray_meta;ack_sync<={ack_sync[0],ack};
            if(gate_count==GATE_CYCLES-1)begin
                gate_count<=0;previous<=count_now;pixel_hz<=measured_hz[31:0];
                if(!pending&&!capture_pending)begin request<=~request;pending<=1;end
            end else gate_count<=gate_count+1'b1;
            if(pending&&ack_sync[1]==request)begin pending<=0;capture_pending<=1;end
            if(capture_pending)begin snapshot<=stable_status;have_snapshot<=1;capture_pending<=0;end
        end
    end
endmodule
`default_nettype wire
