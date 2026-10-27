`timescale 1ns/1ps

// Compare actual head-D selection with a frozen parent over the entire count
// representation, including illegal/underflow and four-state control values.
module tb_fifo_remaining_predicate;
    parameter ADDR_W = 1;
    localparam COUNT_W = ADDR_W + 2;
    reg [COUNT_W-1:0] test_count;
    reg pop_a, pop_b, push, two;
    integer c, p, s, bit_index;
    integer checks = 0;

    triha_fetch_fifo #(.DEPTH(3), .ADDR_W(ADDR_W), .OPC_INFO_W(19)) u_candidate ();
    triha_fetch_fifo_parent #(.DEPTH(3), .ADDR_W(ADDR_W), .OPC_INFO_W(19)) u_parent ();

    function four;
        input integer value;
        begin
            case (value & 3)
                0: four = 0;
                1: four = 1;
                2: four = 1'bx;
                3: four = 1'bz;
            endcase
        end
    endfunction

    initial begin
        force u_candidate.count_q = test_count;
        force u_parent.count_q = test_count;
        force u_candidate.pop_a_w = pop_a;
        force u_parent.pop_a_w = pop_a;
        force u_candidate.pop_b_w = pop_b;
        force u_parent.pop_b_w = pop_b;
        force u_candidate.push_w = push;
        force u_parent.push_w = push;
        force u_candidate.push_two_w = two;
        force u_parent.push_two_w = two;
        force u_candidate.head0_q = 116'h1;
        force u_parent.head0_q = 116'h1;
        force u_candidate.head1_q = 116'h2;
        force u_parent.head1_q = 116'h2;
        force u_candidate.third_w = 116'h3;
        force u_parent.third_w = 116'h3;
        force u_candidate.fourth_w = 116'h4;
        force u_parent.fourth_w = 116'h4;
        force u_candidate.first_in_w = 116'ha;
        force u_parent.first_in_w = 116'ha;
        force u_candidate.second_in_w = 116'hb;
        force u_parent.second_in_w = 116'hb;
        if ($test$plusargs("POISON_REMAINING"))
            force u_candidate.remaining_r = {COUNT_W{1'b1}};
        if ($test$plusargs("FAULT_NEXT")) force u_candidate.next1_r = 116'b0;
        for (c = 0; c < (1 << (2*COUNT_W)); c = c + 1) begin
            for (bit_index = 0; bit_index < COUNT_W; bit_index = bit_index + 1)
                test_count[bit_index] = four(c >> (2*bit_index));
            for (p = 0; p < 16; p = p + 1) begin
                pop_a = four(p); pop_b = four(p >> 2);
                for (s = 0; s < 16; s = s + 1) begin
                    push = four(s); two = four(s >> 2);
                    #1;
                    if ({u_candidate.next0_r, u_candidate.next1_r} !==
                        {u_parent.next0_r, u_parent.next1_r}) begin
                        $display("FIFO_PREDICATE_FAIL count=%b pop=%b%b push=%b two=%b candidate=%h/%h parent=%h/%h",
                            test_count, pop_a, pop_b, push, two,
                            u_candidate.next0_r, u_candidate.next1_r,
                            u_parent.next0_r, u_parent.next1_r);
                        $finish;
                    end
                    if (!$test$plusargs("POISON_REMAINING") &&
                        u_candidate.remaining_r !== u_parent.remaining_r) begin
                        $display("FIFO_PREDICATE_FAIL count update changed");
                        $finish;
                    end
                    checks = checks + 1;
                end
            end
        end
        $display("FIFO_PREDICATE_PASS count_width=%0d checks=%0d", COUNT_W, checks);
        $finish;
    end
endmodule
