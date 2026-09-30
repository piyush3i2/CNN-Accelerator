// Multiply-accumulate, no zero-gating - the "before" of the Day 7 comparison.
//                                                          YOU WRITE THIS - DAY 3
//
// Two pipeline stages:
//   stage 1  operand registers act_q, wt_q and valid_q, loaded EVERY cycle
//   stage 2  if valid_q: acc <= acc + act_q * wt_q
//
// So a tap presented with in_valid is in acc two edges later. With the RAM's
// registered read in front, the core sees three - the basis of DRAIN_CYCLES.
//
// `clear` zeroes acc (synchronously) between dot products. Forgetting it makes
// every result include the previous one.
//
// Observability contract - the register names act_q, wt_q, valid_q and acc are
// read by the Day 7 switching-activity measurement. Keep them.
//
// Contract: tb/unit/test_mac.py (suite mac_baseline).
module mac_unit_baseline #(
    parameter int ACT_W = 8,
    parameter int ACC_W = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     clear,
    input  logic                     in_valid,
    input  logic signed [ACT_W-1:0]  act,
    input  logic signed [ACT_W-1:0]  wt,
    output logic signed [ACC_W-1:0]  acc
);
    
    // TODO(Day 3)

    logic signed [ACT_W-1:0]act_q;
    logic signed [ACT_W-1:0]wt_q;
    logic valid_q;

    always_ff @( posedge clk ) begin
        if (!rst_n) begin
            act_q <= 0;
            wt_q <= 0;
            valid_q <= 0;
        end
        else begin
            act_q <= act;
            wt_q <= wt;
            valid_q <= in_valid;
        end
    end

    always_ff @( posedge clk ) begin 
        if (!rst_n) begin
            acc <= 0;
        end
        else begin
            if (clear) begin
                acc <= 0;
            end
            else begin
               if (valid_q) begin
                    acc <= acc + act_q*wt_q;
                end 
            end   
        end
    end


endmodule
