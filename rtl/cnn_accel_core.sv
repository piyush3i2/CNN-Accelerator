// Tiny-LeNet compute core. One clock domain (the accelerator clock); every
// clock crossing happens above this module.        YOU WRITE THIS - DAY 3 and DAY 4
//
// One inference per `start` pulse:
//   conv 3x3 x CONV_OUT_CH -> +bias -> ReLU -> requantise -> fmap RAM
//   -> maxpool 2x2 -> fmap RAM (above the conv region) -> FC -> result stream
//
// ONE shared MAC serves convolution and FC: both are a dot product; only the
// address generators differ. Pooling does not use the MAC - it keeps a running
// maximum, initialised from the FIRST value of each window, never from 0.
//
// FSM - state codes are exported on state_code and must use these values,
// because STATUS[7:4] reports them and the testbench expects IDLE = 0:
//    0 S_IDLE        1 S_CONV_ISSUE  2 S_CONV_DRAIN  3 S_CONV_WRITE
//    4 S_POOL_ISSUE  5 S_POOL_DRAIN  6 S_POOL_WRITE
//    7 S_FC_ISSUE    8 S_FC_DRAIN    9 S_FC_WRITE   10 S_DONE
// Day 3 builds IDLE -> CONV_* -> DONE. Day 4 inserts POOL_* and FC_*.
//
// Pipeline, three registers deep - so the sum completes in the 3rd cycle after
// the last address, and WRITE may fall in that cycle (DRAIN_CYCLES >= 2):
//   cycle 0  FSM drives a RAM read address
//   cycle 1  RAM read data valid                     (ram read register)
//   cycle 2  operands in the MAC                     (act_q, wt_q)
//   cycle 3  accumulator holds the new sum           (acc)
//
// Outputs:
//   busy                high from the cycle after start is seen until the last WRITE
//                       state; LOW in S_IDLE and S_DONE, so BUSY and DONE never
//                       appear together in STATUS
//   done_pulse          exactly one cycle, in S_DONE
//   res_wr_en / res_wr_data   one pulse per FC neuron, carrying the raw int32
//                       logit (bias added, NOT requantised)
//   mac_total / mac_skipped   from the MAC; tie to 0 until Day 7
//
// Observability contract - the testbench and measurement scripts read these
// INTERNAL names, so use them:
//   fmap_wr_en, fmap_wr_addr, fmap_wr_data   the feature-map RAM write port
//   u_mac                                    the MAC instance name
// Feature-map layout: conv maps at 0 .. FMAP_CONV_N-1, channel-major;
// pooled maps at FMAP_POOL_BASE .., channel-major. Each address written once.
//
// Contract: tb/unit/test_core.py via tb/common/core_harness.sv (no AXI).
module cnn_accel_core
    import cnn_accel_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    start,          // one-cycle pulse, this domain
    input  logic                    zero_gate_en,   // quasi-static during a run
    input  logic [4:0]              conv_shift,     // quasi-static during a run

    output logic [IMG_AW-1:0]       img_rd_addr,
    input  logic signed [ACT_W-1:0] img_rd_data,
    output logic [WT_AW-1:0]        wt_rd_addr,
    input  logic signed [ACT_W-1:0] wt_rd_data,
    output logic [BIAS_AW-1:0]      bias_rd_addr,
    input  logic signed [ACC_W-1:0] bias_rd_data,

    output logic                    res_wr_en,
    output logic signed [ACC_W-1:0] res_wr_data,

    output logic                    busy,
    output logic                    done_pulse,
    output logic [3:0]              state_code,
    output logic [31:0]             mac_total,
    output logic [31:0]             mac_skipped
);

    // TODO(Day 3): FSM, conv address generation, fmap RAM (ram_1r1w),
    //              mac_unit_baseline as u_mac, requantize

    typedef enum logic [3:0] {
        S_IDLE       = 4'd0,
        S_CONV_ISSUE = 4'd1,
        S_CONV_DRAIN = 4'd2,
        S_CONV_WRITE = 4'd3,
        S_POOL_ISSUE = 4'd4,
        S_POOL_DRAIN = 4'd5,
        S_POOL_WRITE = 4'd6,
        S_FC_ISSUE   = 4'd7,
        S_FC_DRAIN   = 4'd8,
        S_FC_WRITE   = 4'd9,
        S_DONE       = 4'd10
    } state_t;

    state_t state, next_state;

    //-------------------------counters-------------------------------------------------//
    logic [$clog2(KN):0]            tap_cnt;      // 0..8
    logic [OCH_W-1:0]               ochan;
    logic [$clog2(CONV_H):0]        orow;
    logic [$clog2(CONV_W):0]        ocol;

    logic [$clog2(K):0]             kr;
    logic [$clog2(K):0]             kc;

    logic                           fmap_wr_en;
    logic [FMAP_AW-1:0]             fmap_wr_addr;
    logic signed [ACT_W-1:0]        fmap_wr_data;

    logic                           drain_done;

    logic [1:0]                     drain_cnt;
    
    logic signed [ACC_W-1:0]        conv_acc;

    logic                           last_pixel;
    assign last_pixel = (ochan == CONV_OUT_CH-1) && (orow == CONV_H-1) && (ocol == CONV_W-1);

    logic                           pool_finished;
    assign pool_finished = (ochan == CONV_OUT_CH-1) && (prow == POOL_H-1) && (pcol == POOL_W -1);
    logic                           fc_finished;
        
    assign fc_finished = (fc_out == FC_OUT - 1);


    assign kr = tap_cnt / K;
    assign kc = tap_cnt % K;

    logic  clear_acc;

    assign clear_acc = ((state == S_CONV_WRITE)||(state == S_FC_WRITE));




    logic [$clog2(POOL_H):0] prow;
    logic [$clog2(POOL_W):0] pcol;

    logic [$clog2(POOL_STRIDE):0] pk;
    logic [$clog2(POOL_STRIDE):0] pk_q;

    logic [$clog2(FC_IN):0]fc_tap_cnt;
    logic [$clog2(FC_OUT)-1:0]fc_out;

    //-------------------------------------------------------------------------------------------//
    assign state_code = state;

    assign busy =
        (state != S_IDLE) &&
        (state != S_DONE);

    assign done_pulse =
        (state == S_DONE);

    assign mac_total   = 32'd0;
    assign mac_skipped = 32'd0;

    assign res_wr_en   = 1'b0;
    assign res_wr_data = '0;


    assign res_wr_en =(state == S_FC_WRITE);

    assign res_wr_data =  conv_acc + bias_rd_data;

    //---------------------------------------------------------------------------------------------//

    logic [9:0]             img_addr_calc;
    logic [9:0]             wt_addr_calc;
    logic [9:0]             bias_addr_calc;
    logic [9:0]             fmap_addr_calc;
    logic [9:0]             pool_addr_calc;

    logic [FMAP_AW-1:0]      fmap_rd_addr;
    logic signed [ACT_W-1:0] fmap_rd_data;

    logic [FMAP_AW-1:0]     fc_rd_address_calc;
    logic [WT_AW-1:0]       fc_wt_addr_calc;
    logic [BIAS_AW-1:0]     fc_bias_addr_calc;

    always_comb begin
        // Image address
        img_addr_calc = ((orow + kr) * IMG_W) + (ocol + kc);

        // Weight address
        wt_addr_calc = WT_CONV_BASE + (ochan * KN) + (kr * K) + kc;

        // Bias address
        bias_addr_calc = BIAS_CONV_BASE + ochan;

        // Feature-map write address
        fmap_addr_calc = FMAP_CONV_BASE + (ochan * CONV_N) + (orow * CONV_W) + ocol;

        // feature map address read
        fmap_rd_addr = FMAP_CONV_BASE + ochan*CONV_N + (2*prow + pk[1])*CONV_W  + (2*pcol + pk[0]);

        //poolmap write data
        pool_addr_calc = FMAP_POOL_BASE + ochan * POOL_N + prow  * POOL_W + pcol;

        //fc rd address
        fc_rd_address_calc = FMAP_POOL_BASE + fc_tap_cnt ;

        //fc wt data
        fc_wt_addr_calc = WT_FC_BASE + fc_out * FC_IN + fc_tap_cnt;

        //fc bias data
        fc_bias_addr_calc = BIAS_FC_BASE + fc_out;


        img_rd_addr  = img_addr_calc[IMG_AW-1:0];
        

        bias_rd_addr = bias_addr_calc[BIAS_AW-1:0];
    end

    always_comb begin 
        if (state == S_FC_ISSUE)
            wt_rd_addr = fc_wt_addr_calc[WT_AW-1:0];
        else
            wt_rd_addr = wt_addr_calc[WT_AW-1:0];    
    end

    always_comb begin 
        if (state == S_FC_ISSUE) 
                fmap_rd_addr = fc_rd_address_calc;
        else if (state == S_POOL_ISSUE)
                fmap_rd_addr = FMAP_CONV_BASE + ochan * CONV_N + (2*prow + pk[1]) * CONV_W + (2*pcol + pk[0]);
        else
        fmap_rd_addr = '0;
        
    end

    always_comb begin
            if (state == S_CONV_WRITE)
                fmap_wr_addr = fmap_addr_calc[FMAP_AW-1:0];
            else if (state == S_POOL_WRITE)
                fmap_wr_addr = pool_addr_calc[FMAP_AW-1:0];
            else if (state == S_FC_WRITE)
                fmap_wr_addr = pool_addr_calc[FMAP_AW-1:0];
            else
                fmap_wr_addr = '0;
    end

    always_comb begin 
    if ((state == S_FC_ISSUE) ||
    (state == S_FC_DRAIN) ||
    (state == S_FC_WRITE))
    bias_rd_addr = fc_bias_addr_calc;
else
    bias_rd_addr = bias_addr_calc;
    
    end

    //-------------------------------------------------------------------------------------------//
    
    
    assign fmap_wr_en = (state == S_CONV_WRITE | state == S_POOL_WRITE);

    ram_1r1w #(.WIDTH(ACT_W), .DEPTH(FMAP_N), .AW(FMAP_AW)) fmap (
        .clk      (clk),
        .wr_en    (fmap_wr_en),
        .wr_addr  (fmap_wr_addr),
        .wr_data  (fmap_wr_data),
        .rd_addr  (fmap_rd_addr),
        .rd_data  (fmap_rd_data)
    );

    //---------------------------------------------------------------------------------------------//

    logic signed [ACT_W-1:0] conv_out_quan;
    
    requantize #(.ACC_W(ACC_W), .OUT_W(ACT_W), .SHIFT_W(5)) u_requant (
        .acc_in   (conv_acc),
        .bias     (bias_rd_data),
        .shift    (conv_shift),
        .relu_en  (1'b1),
        .out      (conv_out_quan)
    );

    


    //--------------------------------------------------------------------------------------------------//
    logic conv_mac_valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            conv_mac_valid_q <= 1'b0;
        else
            conv_mac_valid_q <= (state == S_CONV_ISSUE | state == S_FC_ISSUE);
    end
    //--------------------------------------------using mac for conv and fc -----------------------------//
    always_comb begin 
        if(state == S_CONV_ISSUE  || state == S_CONV_DRAIN)
            mac_act_rd_data = img_rd_data;
        else if(state == S_FC_ISSUE || state == S_FC_DRAIN)
            mac_act_rd_data = fmap_rd_data;
        else
            mac_act_rd_data = '0;

    end

    always_comb begin 
        if(state == S_CONV_ISSUE || state == S_CONV_DRAIN )
            mac_wt_rd_data = wt_rd_data;
        else if (state == S_FC_ISSUE|| state == S_FC_DRAIN)
            mac_wt_rd_data = wt_rd_data;
        else
        mac_act_rd_data = '0;
    end



    //--------------------------------------------------------------------------------//

    logic signed [ACT_W-1:0] mac_act_rd_data,
    logic signed [ACT_W-1:0] mac_wt_rd_data,

    mac_unit_baseline #(.ACT_W(ACT_W), .ACC_W(ACC_W)) u_mac (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear_acc),
        .in_valid (conv_mac_valid_q),
        .act      (mac_act_rd_data),
        .wt       (mac_wt_rd_data),
        .acc      (conv_acc)
    );

    //---------------------------------------------------------------------------------------------//
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    //----------------------------------------------------------assign-----------------------------//
    assign drain_done = (drain_cnt == DRAIN_CYCLES-1);

    //---------------------------------------------------------------------------------------------//
    always_comb begin
        next_state = state;

        casez (state)

            S_IDLE: begin
                if (start)
                    next_state = S_CONV_ISSUE;
            end

            // -------------------------
            // CONVOLUTION
            // -------------------------
            S_CONV_ISSUE: begin
                if (tap_cnt == KN-1)
                    next_state = S_CONV_DRAIN;
            end

            S_CONV_DRAIN: begin
                if (drain_done)
                    next_state = S_CONV_WRITE;
            end

            S_CONV_WRITE: begin
                if (last_pixel)
                    next_state = S_POOL_ISSUE;
                else
                    next_state = S_CONV_ISSUE;
            end

            // -------------------------
            // POOLING
            // -------------------------
            S_POOL_ISSUE: begin
                if (pool_read_cnt == 3 )
                    next_state = S_POOL_DRAIN;
            end

            S_POOL_DRAIN: begin
                if (drain_done)
                    next_state = S_POOL_WRITE;
            end

            S_POOL_WRITE: begin
                if (pool_finished)
                    next_state = S_FC_ISSUE;
                else
                    next_state = S_POOL_ISSUE;
            end

            // -------------------------
            // FULLY CONNECTED
            // -------------------------
            S_FC_ISSUE: begin
                if (fc_tap_cnt == FC_IN-1)
                    next_state = S_FC_DRAIN;
            end

            S_FC_DRAIN: begin
                if (drain_done)
                    next_state = S_FC_WRITE;
            end

            S_FC_WRITE: begin
                if (fc_finished)
                    next_state = S_DONE;
                else
                    next_state = S_FC_ISSUE;
            end

            // -------------------------
            // DONE
            // -------------------------
            S_DONE: begin
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end

        endcase
    end

    //----------------------------------------------------------------------------------------------//
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tap_cnt <= 0;
        else if (state == S_CONV_ISSUE) begin
            if (tap_cnt == KN-1)
                tap_cnt <= 0;
            else
                tap_cnt <= tap_cnt + 1;
        end
        else
            tap_cnt <= 0;
    end

    //----------------------------------------------------------------------------------------------//
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            drain_cnt <= 0;
        else if ((state == S_CONV_DRAIN  | state == S_POOL_DRAIN | S_FC_DRAIN ) & !drain_done)
            drain_cnt <= drain_cnt + 1'b1;
        else
            drain_cnt <= 0;
    end

    //----------------------------------------------------------------------------------------------//

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            orow  <= '0;
            ocol  <= '0;
        end
        else if (state == S_IDLE && start) begin
            // Start a fresh convolution
            orow  <= '0;
            ocol  <= '0;
        end
        else if (state == S_CONV_WRITE) begin
            // Move to next output column
            if (ocol < CONV_W-1) begin
                ocol <= ocol + 1'b1;
            end
            // End of row
            else begin
                ocol <= '0;

                // Move to next output row
                if (orow < CONV_H-1) begin
                    orow <= orow + 1'b1;
                end
                // End of feature map
                else begin
                    orow <= '0;
                end
            end
        end
    end

//------------------------------------------------------------------------------------------------//
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pool_read_cnt <= 0;
        else if (state == S_POOL_ISSUE) begin
            if (pool_read_cnt == 3)
                pool_read_cnt <= 0;
            else
                pool_read_cnt <= pool_read_cnt + 1'b1;
        end
        else
            pool_read_cnt <= 0;
    end 
//----------------------------------------pooling------------------------------------------------------//

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prow <= '0;
            pcol  <= '0;
            pk  <= '0;
        end
        
        else if (state == S_POOL_WRITE) begin
            // Move to next output column
            if (pcol < POOL_W-1) begin
                pcol <= pcol + 1'b1;
            end
            // End of row
            else begin
                pcol <= '0;

                // Move to next output row
                if (prow < POOL_H-1) begin
                    prow <= prow + 1'b1;
                end
                // End of feature map
                else begin
                    prow <= '0;
                end
            end
        end
    end


//-------------------------------------pk & pk_q-----------------------------------------//
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pk <= 2'b00;

        else if (state == S_POOL_ISSUE) begin
            if (pk == 2'b11)
                pk <= 2'b00;
            else
                pk <= pk + 1'b1;
        end
        else
            pk <= 2'b00;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pk_q <= 2'b00;
        else if (state == S_POOL_ISSUE)
            pk_q <= pk;
    end
//---------------------------------------------------ochan-----------------------------//
    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            ochan <= '0;

        // Reset channel counter when entering pooling
        else if ((state == S_CONV_WRITE) && last_pixel)
            ochan <= '0;

        // -----------------------
        // CONVOLUTION CHANNELS
        // -----------------------
        else if (state == S_CONV_WRITE) begin

            if ((ocol == CONV_W-1) &&
                (orow == CONV_H-1)) begin

                if (ochan != CONV_OUT_CH-1)
                    ochan <= ochan + 1'b1;
            end

        end

        // -----------------------
        // POOLING CHANNELS
        // -----------------------
        else if (state == S_POOL_WRITE) begin

            if ((pcol == POOL_W-1) &&
                (prow == POOL_H-1)) begin

                if (ochan != CONV_OUT_CH-1)
                    ochan <= ochan + 1'b1;
            end

        end

    end
//------------------------------pool calculation-------------------------------//

    logic fram_pool_first;
    logic signed [ACT_W-1:0] pool_max;

    assign fram_pool_first = (pk_q == 2'b00);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pool_max <= '0;

        else if ((state == S_POOL_ISSUE) ||
         (state == S_POOL_DRAIN)) begin

            if (fram_pool_first)
                pool_max <= fmap_rd_data;
            else if (fmap_rd_data > pool_max)
                pool_max <= fmap_rd_data;
            else
                pool_max <= pool_max;
        end
    end

//---------------------------------------write pool in fmap ------------------------//

    always_comb begin
        if (state == S_CONV_WRITE)
            fmap_wr_data = conv_out_quan;
        else if (state == S_POOL_WRITE)
            fmap_wr_data = pool_max;
        else
            fmap_wr_data = '0;
    end

//-----------------------------------fc tap cnt--------------------------------------------//

    always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        fc_tap_cnt <= 0;

    else if (state == S_FC_ISSUE) begin
        if (fc_tap_cnt == FC_IN-1)
            fc_tap_cnt <= 0;
        else
            fc_tap_cnt <= fc_tap_cnt + 1'b1;
    end

    else
        fc_tap_cnt <= 0;
end


//-------------------------------------fc out logic --------------------------------------//
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fc_out <= '0;

        else if (state == S_POOL_WRITE && pool_finished)
            fc_out <= '0;              // start FC from neuron 0

        else if (state == S_FC_WRITE) begin
            if (fc_out < FC_OUT-1)
                fc_out <= fc_out + 1'b1;
            else
                fc_out <= '0;
        end
    end
    // TODO(Day 4): pooling and FC states, result stream
    // TODO(Day 7): swap u_mac to the zero-gated mac_unit, connect the counters

endmodule