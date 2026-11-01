// Exact CRC-32/ISO-HDLC. Capture first, then at most 16 bit rounds per stage.
module b03_crc32_word_pipe(
    input wire clk,clear,run_ce,in_valid,output wire in_ready,
    input wire [31:0] data,input wire [2:0] byte_count,input wire first,last,
    input wire [31:0] stream_id,epoch,
    output reg out_valid,input wire out_ready,output reg out_error,
    output reg [31:0] crc,out_id,out_epoch,output wire busy
);
    localparam IDLE=2'd0,LOW=2'd1,HIGH=2'd2;
    reg [1:0] phase;
    reg active;
    reg [31:0] active_id,active_epoch;
    reg [31:0] state,mid,saved_data,saved_id,saved_epoch;
    reg [1:0] saved_low_count,saved_high_count;
    reg saved_first,saved_last,saved_error;
    wire needs_result=saved_last||saved_error;
    wire can_commit=!needs_result||!out_valid||out_ready;
    assign in_ready=phase==IDLE||(phase==HIGH&&can_commit);
    assign busy=active||phase!=IDLE||out_valid;
    wire accept=in_valid&&in_ready;
    wire input_error=byte_count>4||(byte_count==0&&!(first&&last))||
        (first&&active)||(!first&&!active)||
        (!first&&(stream_id!=active_id||epoch!=active_epoch));

    function [31:0] update16;
        input [31:0] seed;
        input [15:0] bytes;
        input [1:0] count;
        reg [31:0] work;
        integer b,k;
        begin
            work=seed;
            for(b=0;b<2;b=b+1)if(b<count)begin
                work=work^{24'b0,bytes[8*b+:8]};
                for(k=0;k<8;k=k+1)
                    work=work[0] ? (work>>1)^32'hedb88320:(work>>1);
            end
            update16=work;
        end
    endfunction
    wire [31:0] low_value=update16(saved_first ? 32'hffffffff:state,saved_data[15:0],saved_low_count);
    wire [31:0] high_value=update16(mid,saved_data[31:16],saved_high_count);

    always @(posedge clk)begin
        if(clear)begin
            phase<=IDLE;active<=0;active_id<=0;active_epoch<=0;
            state<=32'hffffffff;mid<=0;saved_data<=0;saved_id<=0;saved_epoch<=0;
            saved_low_count<=0;saved_high_count<=0;saved_first<=0;saved_last<=0;saved_error<=0;
            out_valid<=0;out_error<=0;crc<=0;out_id<=0;out_epoch<=0;
        end else if(run_ce)begin
            if(out_valid&&out_ready)out_valid<=0;
            case(phase)
                IDLE:begin end
                LOW:begin
                    mid<=saved_error ? 32'b0:low_value;
                    phase<=HIGH;
                end
                HIGH:if(can_commit)begin
                    if(saved_error)begin
                        out_valid<=1;out_error<=1;crc<=0;out_id<=saved_id;out_epoch<=saved_epoch;
                    end else begin
                        state<=high_value;
                        if(saved_last)begin
                            out_valid<=1;out_error<=0;crc<=~high_value;out_id<=saved_id;out_epoch<=saved_epoch;
                        end
                    end
                    phase<=IDLE;
                end
                default:phase<=IDLE;
            endcase
            // Logical stream identity follows accepted words; result identity
            // remains untouched until a completed last/error can use its slot.
            if(accept)begin
                saved_data<=data;saved_id<=stream_id;saved_epoch<=epoch;
                saved_low_count<=byte_count>=2 ? 2'd2:byte_count[1:0];
                saved_high_count<=byte_count>=4 ? 2'd2:byte_count==3 ? 2'd1:2'd0;
                saved_first<=first;saved_last<=last;saved_error<=input_error;
                if(input_error)active<=0;
                else begin
                    active<=!last;
                    if(first)begin active_id<=stream_id;active_epoch<=epoch;end
                end
                phase<=LOW;
            end
        end
    end
endmodule
