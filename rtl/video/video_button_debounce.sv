`timescale 1ns/1ps
`default_nettype none
// Single qualified press, followed by a fully qualified release before rearm.
// CLOCK_HZ is the actual receiving clock; no board pin is assumed here.
module video_button_debounce #(
    parameter integer CLOCK_HZ=125000000,STABLE_MS=20,ACTIVE_LOW=1
)(
    input wire clk,reset_n,button_async,
    output reg pressed,press_pulse
);
    localparam [63:0] STABLE_CYCLES=(64'd1*CLOCK_HZ*STABLE_MS+999)/1000;
    localparam integer CW=STABLE_CYCLES>1?$clog2(STABLE_CYCLES):1;
    (* ASYNC_REG="TRUE" *) reg button_meta,button_sync;
    reg [CW-1:0] count;
    wire synchronized_pressed=ACTIVE_LOW?!button_sync:button_sync;
    generate if(CLOCK_HZ<1||STABLE_MS<1||(ACTIVE_LOW!=0&&ACTIVE_LOW!=1))begin:invalid_parameters
        initial $fatal(1,"Button requires positive clock/time and boolean polarity");
    end endgenerate
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            button_meta<=ACTIVE_LOW?1'b1:1'b0;
            button_sync<=ACTIVE_LOW?1'b1:1'b0;
        end else begin button_meta<=button_async;button_sync<=button_meta;end
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin pressed<=0;press_pulse<=0;count<=0;end
        else begin
            press_pulse<=0;
            case(synchronized_pressed)
            1'b0,1'b1:begin
                if(synchronized_pressed==pressed)count<=0;
                else if(count==STABLE_CYCLES-1)begin
                    count<=0;pressed<=synchronized_pressed;
                    press_pulse<=synchronized_pressed;
                end else count<=count+1'b1;
            end
            default:count<=0;
            endcase
        end
    end
endmodule
`default_nettype wire
