// int32 accumulator -> int8 activation. Purely combinational. YOU WRITE THIS - DAY 2
//
// The four steps, in this order and no other (the golden model does the same):
//     biased    = acc_in + bias                       at ACC_W bits
//     activated = (relu_en && biased < 0) ? 0 : biased
//     shifted   = activated >>> shift                 ARITHMETIC shift
//     out       = clamp(shifted, -2**(OUT_W-1), 2**(OUT_W-1)-1)   saturate
//
// Signedness is the whole difficulty here. `>>>` is arithmetic only if its left
// operand is DECLARED signed, and one unsigned operand anywhere in an
// expression makes the whole expression unsigned. Re-read Day 0 Exercise 2.
//
// Icarus note: a constant part-select inside an always_* block does not
// compile; do the final narrowing (shifted[OUT_W-1:0]) in a continuous assign.
//
// Contract: tb/unit/test_requantize.py - 12 directed cases plus 3000 random
// ones checked against your golden model.
module requantize #(
    parameter int ACC_W   = 32,
    parameter int OUT_W   = 8,
    parameter int SHIFT_W = 5
) (
    input  logic signed [ACC_W-1:0]   acc_in,
    input  logic signed [ACC_W-1:0]   bias,
    input  logic        [SHIFT_W-1:0] shift,
    input  logic                      relu_en,
    output logic signed [OUT_W-1:0]   out
);

    // TODO(Day 2)
    logic signed [ACC_W-1:0] biased;
    logic signed [ACC_W-1:0] activated;
    logic signed [ACC_W-1:0] shifted;
    logic signed [ACC_W-1:0] clamped;

    localparam int signed MAX_OUT = (1 << (OUT_W - 1)) - 1;
    localparam int signed MIN_OUT = -(1 << (OUT_W - 1));

    
    always_comb begin 

        biased = acc_in + bias;

        activated = (relu_en && biased < 0) ? 0 : biased;

        shifted = activated >>> shift;

        if (shifted > MAX_OUT)
            clamped = MAX_OUT;
        else if (shifted < MIN_OUT)
            clamped = MIN_OUT;
        else
            clamped = shifted;
    end

    assign out = clamped[OUT_W-1:0] ;

endmodule
