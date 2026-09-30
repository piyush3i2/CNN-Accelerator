// Dual-clock RAM: write port on wr_clk, registered read port on rd_clk.
//                                                          YOU WRITE THIS - DAY 2
//
// This memory is a CLOCK-DOMAIN CROSSING with no synchroniser. That is safe
// only because of a protocol the rest of the design enforces: the host writes
// it while the accelerator is idle, and the accelerator reads it only after
// START has crossed. No address is ever written in one domain while being read
// in the other. Write that argument in the header comment of your version -
// it is the answer to "where is the synchroniser on your image RAM?".
//
// Contract (tested by tb/unit/test_ram_dc.py): as ram_1r1w, except the write
// is clocked by wr_clk and the read register by rd_clk.
module ram_dc_1r1w #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 64,
    parameter int AW    = $clog2(DEPTH)
) (
    input  logic             wr_clk,
    input  logic             wr_en,
    input  logic [AW-1:0]    wr_addr,
    input  logic [WIDTH-1:0] wr_data,

    input  logic             rd_clk,
    input  logic [AW-1:0]    rd_addr,
    output logic [WIDTH-1:0] rd_data
);

    // TODO(Day 2)

    logic [WIDTH-1:0]mem[DEPTH];


    //write data
    always_ff @( posedge wr_clk ) begin 
        if (wr_en) begin
            mem[wr_addr]<=wr_data;
        end
    end

    //read data
    always_ff @( posedge rd_clk ) begin
        rd_data <= mem[rd_addr];
    end
endmodule
