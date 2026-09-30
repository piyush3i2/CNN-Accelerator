// Zero-gated multiply-accumulate - the "after" of the Day 7 comparison, and
// the MAC the finished core instantiates.
//
// Identical to mac_unit_baseline, plus:
//   skip = zero_gate_en && (act == 0)
//   on a skipped tap: act_q and wt_q HOLD (the multiplier's inputs do not
//   toggle - this is where the saving is) and valid_q is cleared (the
//   accumulator does not update).
//
// Counters:
//   mac_total    +1 for every tap presented with in_valid
//   mac_skipped  +1 for every tap the gate suppressed
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

    // Required observability signals
    logic signed [ACT_W-1:0] act_q;
    logic signed [ACT_W-1:0] wt_q;
    logic                    valid_q;

    logic skip;

    assign skip = zero_gate_en && (act == 0);

    // ------------------------------------------------------------------------
    // Stage 1 : Operand registers
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            act_q   <= '0;
            wt_q    <= '0;
            valid_q <= 1'b0;
        end
        else begin
            if (skip) begin
                // Hold multiplier inputs to reduce switching activity
                act_q   <= act_q;
                wt_q    <= wt_q;
                valid_q <= 1'b0;
            end
            else begin
                act_q   <= act;
                wt_q    <= wt;
                valid_q <= in_valid;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Stage 2 : Accumulator
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            acc <= '0;
        end
        else if (clear) begin
            acc <= '0;
        end
        else if (valid_q) begin
            acc <= acc + (act_q * wt_q);
        end
    end

    // ------------------------------------------------------------------------
    // Counters
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mac_total   <= 32'd0;
            mac_skipped <= 32'd0;
        end
        else if (count_clear) begin
            mac_total   <= 32'd0;
            mac_skipped <= 32'd0;
        end
        else begin
            if (in_valid)
                mac_total <= mac_total + 32'd1;

            if (in_valid && skip)
                mac_skipped <= mac_skipped + 32'd1;
        end
    end

endmodule