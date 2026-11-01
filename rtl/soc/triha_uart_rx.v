/* TriHa asynchronous 8N1 UART receiver, one-byte ready/valid buffer.
 * Sender uses packet/ACK flow control. Framing errors and buffer overflow
 * pulse error_o; neither may silently replace an unconsumed byte.
 */
module triha_uart_rx #(
    parameter integer DIVISOR=1085
)(
    input wire clk_i,rst_ni,rx_i,ready_i,
    output reg valid_o,error_o,
    output reg [7:0] data_o
);
    localparam integer CW=DIVISOR>1?$clog2(DIVISOR):1;
    localparam IDLE=0,START=1,DATA=2,STOP=3,WAIT_HIGH=4;
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [1:0] rx_sync;
    reg [2:0] state,bit_index;
    reg [CW-1:0] ticks;
    reg [7:0] shift;
    always @(posedge clk_i or negedge rst_ni)
        if(!rst_ni)rx_sync<=2'b11;else rx_sync<={rx_sync[0],rx_i};
    always @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            state<=IDLE;ticks<=0;bit_index<=0;shift<=0;
            valid_o<=0;error_o<=0;data_o<=0;
        end else begin
            error_o<=0;
            if(valid_o&&ready_i)valid_o<=0;
            case(state)
                IDLE:if(!rx_sync[1])begin ticks<=DIVISOR/2-1;state<=START;end
                START:if(ticks!=0)ticks<=ticks-1'b1;
                    else if(rx_sync[1])state<=IDLE;
                    else begin ticks<=DIVISOR-1;bit_index<=0;state<=DATA;end
                DATA:if(ticks!=0)ticks<=ticks-1'b1;
                    else begin
                        shift[bit_index]<=rx_sync[1];ticks<=DIVISOR-1;
                        if(bit_index==7)state<=STOP;else bit_index<=bit_index+1'b1;
                    end
                STOP:if(ticks!=0)ticks<=ticks-1'b1;
                    else if(!rx_sync[1])begin error_o<=1;state<=WAIT_HIGH;end
                    else begin
                        if(valid_o&&!ready_i)error_o<=1;
                        else begin data_o<=shift;valid_o<=1;end
                        state<=IDLE;
                    end
                WAIT_HIGH:if(rx_sync[1])state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
