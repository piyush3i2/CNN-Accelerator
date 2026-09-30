// Shared constants for the Tiny-LeNet accelerator.       YOU WRITE THIS - DAY 2
//
// Every size in the design is derived here from a handful of primary numbers,
// so changing CONV_OUT_CH from 1 to 2 resizes every port, counter and memory
// with no hand-edited constant anywhere else.
//
// The channel count is set by a define rather than a module parameter because
// packages cannot take parameters, and -P only reaches module parameters:
//     iverilog -g2012 -DCNN_CONV_OUT_CH=2 ...        (run_sim.py --channels 2)
// The define is deliberately NOT named CONV_OUT_CH: a macro with the same name
// as the localparam would be substituted into the localparam's own declaration.
`ifndef CNN_CONV_OUT_CH
  `define CNN_CONV_OUT_CH 1
`endif

package cnn_accel_pkg;

    localparam int CONV_OUT_CH = `CNN_CONV_OUT_CH;

    localparam int ACT_W = 8;
    localparam int ACC_W = 32;

    localparam int IMG_H = 8;
    localparam int IMG_W = 8;
    localparam int IMG_N = IMG_H * IMG_W;

    // Kernel
    localparam int K  = 3;
    localparam int KN = K * K;

    // Convolution output
    localparam int CONV_H = IMG_H - K + 1;
    localparam int CONV_W = IMG_W - K + 1;
    localparam int CONV_N = CONV_H * CONV_W;

    // Pooling output
    localparam int POOL_STRIDE = 2 ;
    localparam int POOL_H = CONV_H / POOL_STRIDE ;
    localparam int POOL_W = CONV_W / POOL_STRIDE ;
    localparam int POOL_N = POOL_H * POOL_W ;

    // Fully connected layer
    localparam int FC_IN  = CONV_OUT_CH * POOL_N;
    localparam int FC_OUT = 4;

    // Weight RAM
    localparam int WT_CONV_BASE = 0;
    localparam int WT_CONV_N    = CONV_OUT_CH * KN;
    localparam int WT_FC_BASE   = WT_CONV_N;
    localparam int WT_N         = WT_CONV_N + FC_OUT * FC_IN;

    // Bias RAM
    localparam int BIAS_CONV_BASE = 0;
    localparam int BIAS_FC_BASE  = CONV_OUT_CH;
    localparam int BIAS_N        = CONV_OUT_CH + FC_OUT;

    // Feature-map RAM
    localparam int FMAP_CONV_BASE = 0;
    localparam int FMAP_CONV_N    = CONV_OUT_CH * CONV_N;
    localparam int FMAP_POOL_BASE = FMAP_CONV_N;
    localparam int FMAP_N         = FMAP_CONV_N + FC_IN;

    // Address / counter widths
    localparam int IMG_AW  = $clog2(IMG_N);
    localparam int WT_AW   = $clog2(WT_N);
    localparam int BIAS_AW = $clog2(BIAS_N);
    localparam int FMAP_AW = $clog2(FMAP_N);
    localparam int TAP_W   = $clog2(KN);

    // Avoid zero-width signal when CONV_OUT_CH = 1
    localparam int OCH_W =
        (CONV_OUT_CH > 1) ? $clog2(CONV_OUT_CH) : 1;

    // Total MAC operations per inference
    localparam int MAC_PER_RUN =
        CONV_OUT_CH * CONV_N * KN
        + FC_OUT * FC_IN;

    // Conservative Day-2/Day-3 setting
    localparam int DRAIN_CYCLES = 3;

    // Result FIFO
    localparam int RESULT_FIFO_AW = 3;


    // TODO(Day 2): declare every constant below as `localparam int`, deriving
    // each from the ones above it wherever possible. The value in brackets is
    // what it must come out as at CONV_OUT_CH = 1 (and 2, where different).
    //
    // Widths
    //   ACT_W          activation and weight width                        [8]
    //   ACC_W          accumulator and logit width                        [32]
    //
    // Network shape
    //   IMG_H, IMG_W, IMG_N                                                [8, 8, 64]
    //   K              kernel size;  KN = K*K taps                         [3; 9]
    //   CONV_H, CONV_W = IMG - K + 1;  CONV_N per channel                  [6, 6; 36]
    //   POOL_H, POOL_W = CONV / 2;     POOL_N per channel                  [3, 3; 9]
    //   FC_IN  = CONV_OUT_CH * POOL_N                                      [9 | 18]
    //   FC_OUT                                                             [4]
    //
    // Weight RAM: every channel's kernel, then the FC weights neuron-major
    //   WT_CONV_BASE [0],  WT_CONV_N = CONV_OUT_CH*KN                      [9 | 18]
    //   WT_FC_BASE = WT_CONV_N,  WT_N = WT_CONV_N + FC_OUT*FC_IN           [45 | 90]
    //
    // Bias RAM: one per conv channel, then one per FC neuron
    //   BIAS_CONV_BASE [0],  BIAS_FC_BASE = CONV_OUT_CH,  BIAS_N           [5 | 6]
    //
    // Feature-map RAM: conv maps, then pooled maps directly above them
    //   FMAP_CONV_BASE [0],  FMAP_CONV_N = CONV_OUT_CH*CONV_N              [36 | 72]
    //   FMAP_POOL_BASE = FMAP_CONV_N,  FMAP_N = FMAP_CONV_N + FC_IN         [45 | 90]
    //
    // Address and counter widths - derive with $clog2
    //   IMG_AW, WT_AW, BIAS_AW, FMAP_AW, TAP_W = $clog2(FC_IN)             [6, 6, 3, 6, 4]
    //   OCH_W          $clog2(CONV_OUT_CH), but floored at 1 - $clog2(1)
    //                  is 0, and a zero-width signal is illegal            [1]
    //
    // Behaviour
    //   MAC_PER_RUN    CONV_OUT_CH*CONV_N*KN + FC_OUT*FC_IN                 [360 | 720]
    //   DRAIN_CYCLES   DRAIN states between the last ISSUE and the WRITE.
    //                  Three registers (RAM read, operands, accumulator)
    //                  mean the sum completes in the 3rd cycle after the last
    //                  address, and WRITE is that 3rd cycle when this is 2.
    //                  Use 3 for now - one cycle of margin - and say so in a
    //                  comment; Day 8 proves 2 and measures the saving.   [3]
    //   RESULT_FIFO_AW result FIFO depth is 2**AW; must hold FC_OUT         [3]

endpackage
