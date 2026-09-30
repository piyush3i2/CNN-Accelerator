// Single-clock RAM: one write port, one registered read port.   YOU WRITE THIS - DAY 2
//
// Contract (tested by tb/unit/test_ram.py):
//   - write:  on posedge clk, if wr_en, mem[wr_addr] <= wr_data
//   - read:   REGISTERED. rd_addr applied in cycle t appears on rd_data after
//             the edge that ends cycle t. This one cycle is one of the three
//             pipeline registers behind DRAIN_CYCLES.
//   - read-during-write to the same address returns the OLD contents
//   - no vendor primitive: a plain `logic [WIDTH-1:0] mem [DEPTH]` plus a
//     registered read is what every tool infers as a block RAM
module ram_1r1w #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 64,
    parameter int AW    = $clog2(DEPTH)
) (
    input  logic             clk,
    input  logic             wr_en,
    input  logic [AW-1:0]    wr_addr,
    input  logic [WIDTH-1:0] wr_data,
    input  logic [AW-1:0]    rd_addr,
    output logic [WIDTH-1:0] rd_data
);
    logic [WIDTH-1:0]mem[DEPTH];
    // TODO(Day 2)
    always_ff @( posedge clk ) begin 
        if (wr_en) mem[wr_addr] <= wr_data;
    end

    always_ff @( posedge clk ) begin
        rd_data <= mem[rd_addr] ;
    end

endmodule
