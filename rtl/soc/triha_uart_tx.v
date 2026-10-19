/* TriHa same-clock UART transmitter: 8 data bits, no parity, one stop bit. */
module triha_uart_tx #(
    parameter integer DIVISOR = 868
) (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire       valid_i,
    input  wire [7:0] data_i,
    output wire       ready_o,
    output wire       tx_o
);
    reg [9:0] shift_q;
    reg [3:0] bits_q;
    reg [15:0] ticks_q;
    assign ready_o = bits_q == 0;
    // The stop bit and fill bits leave shift_q[0] at one when idle.
    // Drive the registered bit directly, removing the busy decode at the pad.
    assign tx_o = shift_q[0];
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            shift_q <= 10'h3ff;
            bits_q <= 0;
            ticks_q <= 0;
        end else if (ready_o) begin
            if (valid_i) begin
                shift_q <= {1'b1, data_i, 1'b0};
                bits_q <= 10;
                ticks_q <= DIVISOR - 1;
            end
        end else if (ticks_q == 0) begin
            shift_q <= {1'b1, shift_q[9:1]};
            bits_q <= bits_q - 1'b1;
            ticks_q <= DIVISOR - 1;
        end else begin
            ticks_q <= ticks_q - 1'b1;
        end
    end
endmodule
