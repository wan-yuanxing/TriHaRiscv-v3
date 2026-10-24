`timescale 1ns/1ps
module tb_csr_metadata_property #(parameter BROKEN=0);
    reg valid_bit,base_csr,illegal_bit,fault_bit;
    wire old_invalid=valid_bit && illegal_bit;
    wire old_decoded_csr=base_csr | old_invalid | fault_bit;
    wire old_csr=valid_bit ? old_decoded_csr : (base_csr | fault_bit);
    wire legal_bit=~illegal_bit;
    wire new_invalid=valid_bit && ~legal_bit;
    wire new_csr=base_csr | new_invalid | fault_bit;
    wire tested_csr=BROKEN ? (new_csr^1'b1) : new_csr;
    integer n,checks=0;
    function state_bit;
        input [1:0] code;
        begin
            case(code)
                0:state_bit=0;1:state_bit=1;2:state_bit=1'bx;3:state_bit=1'bz;
            endcase
        end
    endfunction
    initial begin
        for(n=0;n<256;n=n+1)begin
            valid_bit=state_bit(n[1:0]);base_csr=state_bit(n[3:2]);
            illegal_bit=state_bit(n[5:4]);fault_bit=state_bit(n[7:6]);
            #1;checks=checks+1;
            if({new_invalid,tested_csr}!=={old_invalid,old_csr})
                $fatal(1,"CSR_METADATA_PROPERTY_FAIL check=%0d v=%b b=%b i=%b f=%b",checks,valid_bit,base_csr,illegal_bit,fault_bit);
        end
        $display("CSR_METADATA_PROPERTY_PASS checks=%0d all4state_scalar_combinations",checks);$finish;
    end
endmodule
