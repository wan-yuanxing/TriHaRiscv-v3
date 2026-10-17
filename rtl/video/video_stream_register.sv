`timescale 1ns/1ps
`default_nettype none
// One owned word, no combinational data bypass; replace on the retirement edge.
// Only coordinated reset drops ownership. Payload storage itself has no reset.
module video_stream_register #(
    parameter integer DATA_WIDTH=48
)(
    input wire clk,reset_n,
    input wire s_valid,
    output wire s_ready,
    input wire [DATA_WIDTH-1:0] s_data,
    output wire m_valid,
    input wire m_ready,
    output wire [DATA_WIDTH-1:0] m_data
);
    reg run,valid;
    reg [DATA_WIDTH-1:0] data;
    generate if(DATA_WIDTH<1)begin:invalid_parameters
        initial $fatal(1,"Stream register requires positive DATA_WIDTH");
    end endgenerate
    assign s_ready=run && (!valid || m_ready);
    assign m_valid=valid;
    assign m_data=data;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin run<=0;valid<=0;end
        else begin
            run<=1;
            if(s_ready)valid<=s_valid;
        end
    end
    always @(posedge clk)
        if(s_valid && s_ready)data<=s_data;
endmodule
`default_nettype wire
