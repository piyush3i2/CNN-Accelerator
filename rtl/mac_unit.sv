// Zero-gated multiply-accumulate - the "after" of the Day 7 comparison, and
// the MAC the finished core instantiates.                  YOU WRITE THIS - DAY 7
//
// Identical to mac_unit_baseline, plus:
//   skip = zero_gate_en && (act == 0)
//   on a skipped tap: act_q and wt_q HOLD (the multiplier's inputs do not
//   toggle - this is where the saving is) and valid_q is cleared (the
//   accumulator does not update).
//
// Gate on the ACTIVATION, not the weight. ReLU makes activation sparsity
// dynamic, so only hardware can exploit it; weight zeros are static and are
// better removed by pruning the weight memory at compile time.
//
// Muxing the multiplier OUTPUT to zero saves nothing - its inputs would still
// toggle. tb/unit/test_mac.py::test_gate_holds_operand_registers exists to
// catch exactly that, because the results alone cannot.
//
// Counters, cleared by count_clear (the core drives it with start):
//   mac_total    +1 for every tap presented with in_valid
//   mac_skipped  +1 for every tap the gate suppressed
//
// Observability contract: keep the names act_q, wt_q, valid_q, acc.
module mac_unit #(
    parameter int ACT_W = 8,
    parameter int ACC_W = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     clear,
    input  logic                     in_valid,
    input  logic signed [ACT_W-1:0]  act,
    input  logic signed [ACT_W-1:0]  wt,
    input  logic                     zero_gate_en,
    input  logic                     count_clear,
    output logic signed [ACC_W-1:0]  acc,
    output logic [31:0]              mac_total,
    output logic [31:0]              mac_skipped
);

    // TODO(Day 7)

endmodule
