//
// DISCLAIMER OF WARRANTY:
//   This software code and all associated documentation, comments or other 
//   information (collectively "Software") is provided "AS IS" without 
//   warranty of any kind. MICRON TECHNOLOGY, INC. ("MTI") EXPRESSLY 
//   DISCLAIMS ALL WARRANTIES EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
//   TO, NONINFRINGEMENT OF THIRD PARTY RIGHTS, AND ANY IMPLIED WARRANTIES 
//   OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE. MTI DOES NOT 
//   WARRANT THAT THE SOFTWARE WILL MEET YOUR REQUIREMENTS, OR THAT THE 
//   OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE. 
//   FURTHERMORE, MTI DOES NOT MAKE ANY REPRESENTATIONS REGARDING THE USE OR 
//   THE RESULTS OF THE USE OF THE SOFTWARE IN TERMS OF ITS CORRECTNESS, 
//   ACCURACY, RELIABILITY, OR OTHERWISE. THE ENTIRE RISK ARISING OUT OF USE 
//   OR PERFORMANCE OF THE SOFTWARE REMAINS WITH YOU. IN NO EVENT SHALL MTI, 
//   ITS AFFILIATED COMPANIES OR THEIR SUPPLIERS BE LIABLE FOR ANY DIRECT, 
//   INDIRECT, CONSEQUENTIAL, INCIDENTAL, OR SPECIAL DAMAGES (INCLUDING, 
//   WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, BUSINESS INTERRUPTION, 
//   OR LOSS OF INFORMATION) ARISING OUT OF YOUR USE OF OR INABILITY TO USE 
//   THE SOFTWARE, EVEN IF MTI HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH 
//   DAMAGES. Because some jurisdictions prohibit the exclusion or 
//   limitation of liability for consequential or incidental damages, the 
//   above limitation may not apply to you.
// 
//   Copyright 2003 Micron Technology, Inc. All rights reserved.

`timescale 1ps/1ps
// HMC SerDes
// Generates TX and RX UI and FLIT clocks from REFCLK
// Deserializes LxRXP onto rx_fi, and drives associated HEAD, VALID and TAIL signals
// Serializes tx_fi onto LxTXP
// *features*
//  -training
//  -scrambling/descrambling
//  -half rate
//  -lane reversal and polarity inversion


interface hmc_serdes(
// modports ?
    input logic         P_RST_N,
    input logic         REFCLKP,
    input logic         REFCLKN,
`ifdef HMC_FLIT
    input logic  [127:0] LxRXFLIT,
    output logic [127:0] LxTXFLIT,
    // In Flit Interface mode, these are to be supplied by the host driving
    // the interface
    input logic        LxTXCLK, // same signal as tx_fi.fi.CLK
    input logic        LxRXCLK, // same signal as rx_fi.fi.CLK
`else // HMC_SERDES
    input logic [15:0]  LxRXP, 
    input logic [15:0]  LxRXN, 
    output logic [15:0] LxTXP, 
    output logic [15:0] LxTXN, 
    // In Serial Interface mode, these are outputs from the block that are
    // connected to flit_bfm modules
    output logic        LxTXCLK, // gets sent into tx_fi.fi.CLK
    output logic        LxRXCLK, // gets sent into rx_fi.fi.CLK
`endif
    input logic         LxRXPS,
    output logic        LxTXPS,
    input logic         LxRXPSOR

`ifdef TWO_IN_ONE
    , output logic        LINK_ACTIVE_2_IN_1
`endif //TWO_IN_ONE
);

    import hmc_bfm_pkg::*;
    cls_link_cfg            link_cfg;   
    cls_fi                  tx_fi;
    cls_fi                  rx_fi;
    
    // define link training states and tx data
    typedef enum {IDLE, RXALIGNDATACLK, DESCRAMSYNC, NZWAIT, TS1SYNC, ZEROWAIT, LINKACTIVE32NULL, LINKACTIVE, SLEEP} LinkStates_e;
    typedef enum {SEND_Z, SEND_ALT01, SEND_ZEROS, SEND_TS1, SEND_FLITS} TxSend_e;

`ifndef HMC_FLIT // HMC_SERDES
    // clocks
    bit                 clk_txui;
    bit                 clk_rxui;
    bit                 refclk;
    time                tm_refclk;
    time                tm_refclk_period;
    time                tm_rx_clk_negedge;
    time                tm_rx_clk_posedge;
    time                tm_rx_data_spot;
    time                tm_rx_ln_dly[16];
    time                tm_rx_ln_edge[16];
    time                tm_rx_ui;
    time                tm_tx_unit_lane_delay;
    assign              refclk = REFCLKP & ~REFCLKN;
    bit           [2:0] cnt_txui;
    bit           [2:0] cnt_rxui;
`endif

    // Group Configuration
    bit                 cfg_info_msg      = 0;
    int                 cfg_tx_clk_ratio  = 60; //125MHz REFCLK * 60 = 750MHz UICLK = 1.5Gbps UI
    int                 cfg_rx_clk_ratio  = 60;

    bit [2:0]           cfg_link_id            = 3'h0;          // slid bit 2:0
    bit [1:0]           cfg_host_mode          = 2'h1;          // linkctl bit 1:0
    bit                 cfg_pkt_rx_enb         = 1'b1;          // linkctl bit 6
    bit                 cfg_pkt_tx_enb         = 1'b1;          // linkctl bit 7
    bit                 cfg_descram_enb        = 1'b1;          // linkctl bit 9
    bit                 cfg_scram_enb          = 1'b1;          // linkctl bit 10
    bit                 cfg_lane_auto_correct  = 1'b1;          // lictrl2 bit 16
    bit                 cfg_lane_reverse       = 1'b0;          // lictrl2 bit 17
    bit                 cfg_half_link_mode_tx  = 1'b0;          // lictrl2 bit 18
    bit                 cfg_half_link_mode_rx  = 1'b0;          // lictrl2 bit 19
    bit [15:0]          cfg_hsstxoe            = 16'hffff;      // lictrl3 bit 15:0
    bit [7:0]           cfg_tx_rl_lim          = 8'h00;         // linkifsts2 bit 23:16
    bit                 cfg_send_null          = 1;
    int                 num_lanes_tx           = 16;            // PR: since half_link defaults to 0
    int                 num_lanes_rx           = 16;
    int                 num_flit_bits_per_lane_tx = 128/num_lanes_tx; // PR: make this 5 bits to make it easier to expand for gen3 quarter link 
    int                 num_flit_bits_per_lane_rx = 128/num_lanes_rx; 
    
    // bit              cfg_link_down_inhib    = 1'b0;          // linkctl bit 8 - Set to inhibit link power down resulting from normal power state mgmt.

    bit [15:0]          cfg_hsstx_inv          = 16'h0000;  // emulates hss functionality to invert lanes
    bit [15:0]          cfg_hssrx_inv          = 16'h0000;
    bit                 cfg_tx_lane_reverse    = 1'b0;      // for test purposes only, not implemented in HMC
    bit [15:0]          cfg_tx_lane_delay[16];
    bit [15:0]          cfg_tx_lane_delay_divisor = 100;

    // internal signals
`ifndef HMC_FLIT // HMC_SERDES
    logic       [127:0] LxTXFLIT, LxRXFLIT;
    logic        [15:0] LxTX, LxRX;
    logic        [15:0] LxRXdly;
    logic        [15:0] LxTXdly;
`endif
    bit           [3:0] rx_lng;
//    int                 tx_credits;
    
    logic              retrain = '0;  // temp

    LinkStates_e       link_train_sm_q;
    logic [1:0]        link_idle_q;
    logic [15:0]       rx_auto_lane_invert_q;
    logic              rx_auto_lane_reversal_q;
    logic [5:0]        rx_cycle_cnt_q;
    logic [7:0][127:0] rx_dscrm_flit_q;
    logic [15:0][3:0]  rx_lfsr_cmp_eq_cnt_q;
    logic [15:0][3:0]  rx_lfsr_cmp_err_cnt_q;
    logic [15:0][15:0] rx_lfsr_q;
    logic [15:0][15:0] rx_lfsr_s1_q;
    logic [15:0]       rx_lfsr_sync_q;
    logic [15:0]       rx_signal_detected_q;
    logic [127:0]      rxflit_q;
    logic [127:0]      txflit_q;
    logic [5:0]        tx_32null_cnt_q;
    logic [15:0]       tx_lane_out_q;
    logic [15:0][15:0] tx_lfsr_q;
    logic [15:0][7:0]  tx_run_limit_cnt_q;
    logic [15:0]       rx_clk_align = '0;
    logic [15:0]       rx_ts1_sync  = '0;

    LinkStates_e       link_train_sm_d;
    logic [15:0]       rx_auto_lane_invert_d;
    logic              rx_auto_lane_reversal_d;
    logic [5:0]        rx_cycle_cnt_d;
    logic [15:0][3:0]  rx_lfsr_cmp_eq_cnt_d;
    logic [15:0][3:0]  rx_lfsr_cmp_err_cnt_d;
    logic [15:0][15:0] rx_lfsr_d;
    logic [15:0]       rx_lfsr_sync_d;
    logic [15:0]       rx_signal_detected_d;
    logic [5:0]        tx_32null_cnt_d;
    logic [15:0]       tx_lane_out_d;
    logic [15:0][7:0]  tx_run_limit_cnt_d;

    logic              hsstxoe;
    logic              link_idle;
    logic              link_idle_reset_n;
    logic              link_rxclkalign;
    logic [15:0][63:0] rx_dscrm_lane;
    logic [127:0]      rx_flit_out;
    logic [15:0]       rx_lane_invert;
    logic [15:0][15:0] rx_lane_capture;
    logic [15:0][15:0] rx_lane_expected;
    logic              rx_lane_reversal;
    logic              rx_link_active;
    int                rx_ln_align_f0_ptr_d[16], rx_ln_align_f0_ptr_q[16];
    int                rx_ln_align_ptr[16];
    logic [15:0][6:0]  rx_ln_bit_sum;
    logic [15:0][3:0]  rx_ln_id;
    logic [15:0][3:0]  rx_ln_seq;
    logic [15:0][3:0]  rx_ln_seq_diff_d, rx_ln_seq_diff_q;
    logic [3:0]        rx_ln_seq_min;
    logic              ts1ptr;
    logic [3:0]        ts1seq_q;
    logic [63:0]       ts1_lane0_seq;
    logic [63:0]       ts1_lanen_seq;
    logic [63:0]       ts1_lanef_seq;
    logic [127:0]      tx_flit_out;
    logic              tx_link_active;
    logic [127:0]      tx_rll_out;
    logic              tx_run_limit_en;
    logic [127:0]      tx_run_limit_mask;
    logic [127:0]      tx_scram_out;

    bit                in_sleep_mode;
    bit                in_down_mode;
    int                in_sleep_mode_trans = 0;
    int                in_down_mode_trans = 0;   
    
    TxSend_e           tx_send;

    int                   cfg_trsp1 = 1us;
    int                   cfg_trsp2 = 1us;
    realtime              cfg_tpst  = 80ns;  // max tpst
    realtime              cfg_tsme  = 500ns; // max tsme
    realtime              cfg_trxd  = 0ns;
    realtime              cfg_ttxd  = 200ns; // max
    realtime              cfg_tsd   = 200ns; // max
    realtime              cfg_tis   = 10ns;  // min
    realtime              cfg_tss   = 500ns; // max
    realtime              cfg_top   = 1ms;   // min
    realtime              cfg_tsref = 1ms;   // max
    realtime              cfg_tpsc  = 200ns; // max


    realtime           LxRXPS_fall = 0;
    realtime           LxRXPS_rise = 0;
    realtime           LxTXPS_fall = 0;
    realtime           LxTXPS_rise = 0;         
    time               tm_descram_sync;
    time               tm_ts1_sync;
//
    string flit_rx_adg, flit_tx_adg, fnend, fname; //ADG:: for debug
    integer flits_in, flits_out; //ADG:: for debug
//
`ifdef HMC_COV //ADG:: for user not doing verification coverage.

    covergroup hmc_serdes_down_mode_cg;

        in_down_mode: coverpoint in_down_mode;
        in_down_mode_trans: coverpoint in_down_mode_trans {
            bins reset_to_down = {1};
            bins all_sleep_to_down = {2};
            bins exit_down_from_LxRXPS = {3};
        }
        
    endgroup

    covergroup hmc_serdes_sleep_mode_cg;

        in_sleep_mode: coverpoint in_sleep_mode;
        in_sleep_mode_trans_responder: coverpoint in_sleep_mode_trans {
            bins to_reset = {1};
            bins enter_sleep_mode = {2};
            // done in the coverpoint below to allow cleaner reporting
            // ignore_bins exit_sleep_mode_requester = {3};
            bins exit_sleep_mode_responder = {4};
        }

        in_sleep_mode_trans_requester: coverpoint in_sleep_mode_trans {
            bins to_reset = {1};
            bins enter_sleep_mode = {2};
            bins exit_sleep_mode_requester = {3};          
        }

        
    endgroup

    
    hmc_serdes_down_mode_cg hmc_serdes_down_cov = new();
    hmc_serdes_sleep_mode_cg hmc_serdes_sleep_cov = new();    
`endif
    
    initial begin
        wait (
              link_cfg           != null &&
              tx_fi              != null &&
              rx_fi              != null
        );
         `ifdef ADG_DEBUG
                cfg_info_msg = 1;
         `endif
         `ifdef HMC_FLIT
            $display("%m FLIT INTERFACE ENABLED");
         `else // HMC_SERDES
            for (int i=0; i<16; i++) begin
                cfg_tx_lane_delay[i] = 0;
                tm_rx_ln_dly[i]      = 0;
            end
         `endif

// Some 2in1 safeguards 
`ifdef TWO_IN_ONE
    `ifdef HMC_GEN2
        assert(0) else $fatal("2in1 model does not support HMC Gen2 hardware");
    `endif

    `ifdef HMC_PROTOCOL_1
        assert(0) else $fatal("2in1 model does not currently support HMC Protocol Rev. 1");
    `endif
`endif
        fork
            run_tx();
            run_rx();
        join_none
    end

`ifndef HMC_FLIT //HMC_SERDES
    // serial link interface
    always @* begin
        if(hsstxoe) begin
            LxTXP[7:0] = LxTXdly[7:0];
            LxTXN[7:0] = ~LxTXdly[7:0];
        end else begin
            LxTXP[7:0] = 'z;
            LxTXN[7:0] = 'z;
        end
        if(hsstxoe & (cfg_hsstxoe[15:8]==8'hff)) begin
            LxTXP[15:8] = LxTXdly[15:8];
            LxTXN[15:8] = ~LxTXdly[15:8];
        end else begin
            LxTXP[15:8] = 'z;
            LxTXN[15:8] = 'z;
        end
    end

    assign LxRX = LxRXP & ~LxRXN;
`endif

`ifdef TWO_IN_ONE
    assign LINK_ACTIVE_2_IN_1 = link_train_sm_q == LINKACTIVE;
`endif //TWO_IN_ONE

//
`ifdef ADG_DEBUG
    // logging input flits. ADG:: 
    always @(clk_rxui or LxRXP) begin
       if (cfg_host_mode != 3) begin 
          $sformat(flit_rx_adg, "%h", LxRXP);
          $fdisplay(flits_in, "%t %m %s ",$realtime,flit_rx_adg); 
       end
    end  
    // logging output flits. ADG:: 
    always @(clk_txui or LxTX) begin
       if (cfg_host_mode != 3) begin 
          $sformat(flit_tx_adg, "%h", LxTX);
          $fdisplay(flits_out, "%t %m %s ",$realtime,flit_tx_adg); 
       end
    end
`endif
//        
    // power state management:
    always @(P_RST_N or LxRXPS) begin
        if (!P_RST_N) begin
            assign in_sleep_mode = 1;
            in_sleep_mode_trans = 1; // to reset
        end else begin
            deassign in_sleep_mode;

            if (!LxRXPS && !in_sleep_mode) begin
                $display("%t %m SERDES Entering Sleep Mode", $realtime);
                in_sleep_mode <= #(cfg_tpst + cfg_link_id*cfg_tss + cfg_tsme) 1;
                in_sleep_mode_trans = 2; // enter sleep mode                
            end else if (LxRXPS && in_sleep_mode) begin // posedge LxRXPS
                if (cfg_host_mode == 3) begin
                    $display("%t %m SERDES: Exiting Sleep Mode REQUESTER", $realtime);
                    in_sleep_mode <= #(cfg_trxd + cfg_tpsc*in_down_mode) 0;
                    in_sleep_mode_trans = 3; // exit sleep mode requester
                end else begin
                    $display("%t %m SERDES: Exiting Sleep Mode RESPONDER", $realtime);
                    in_sleep_mode <= #(cfg_tpst + cfg_link_id*cfg_tss + cfg_ttxd + cfg_tpsc*in_down_mode) 0;
                    in_sleep_mode_trans = 4; // exit sleep mode responder
                end
            end
        end
     `ifdef HMC_COV
        hmc_serdes_sleep_cov.sample();
     `endif        
    end

    // down mode is enterted at the deassertion of reset    (posedge P_RST_N)
    // or after the last link goes into sleep mode          (negedge LxRXPSOR)
    // down mode is exited when LxRXPS goes high            (posedge LxRXPS)
    always @(posedge P_RST_N or negedge LxRXPSOR or posedge LxRXPS) begin
        if (!P_RST_N) begin
            in_down_mode_trans = 1; // reset to down
        end else if (LxRXPSOR == 0) begin
            in_down_mode_trans = 2; // all sleep to down mode
        end else if (LxRXPS == 1) begin
            in_down_mode_trans = 3; // exit down mode from LxRXPS
        end
        in_down_mode <= !LxRXPS;
     `ifdef HMC_COV
        hmc_serdes_down_cov.sample();
     `endif        
    end

    always @(negedge P_RST_N) begin
        in_down_mode_trans = 1; // reset to down
    end
    
    always @(P_RST_N or LxRXPS) begin
        if (!P_RST_N) begin
            assign LxTXPS = 0;
        end else begin
            deassign LxTXPS;
            LxTXPS <= #(cfg_tpst + cfg_link_id*cfg_tss) LxRXPS;
        end
    end

`ifndef HMC_FLIT //HMC_SERDES
    // pll model
    always @(posedge refclk) begin
        tm_refclk_period = $time - tm_refclk;

        if (tm_refclk_period <= 16ns) begin
            for (real i=0; i<cfg_tx_clk_ratio; i++) begin
                clk_txui <= #(i*tm_refclk_period/cfg_tx_clk_ratio) refclk;
                clk_txui <= #((i+0.5)*tm_refclk_period/cfg_tx_clk_ratio) !refclk;
            end
            for (real i=0; i<cfg_rx_clk_ratio; i++) begin
                clk_rxui <= #(i*tm_refclk_period/cfg_rx_clk_ratio) refclk;
                clk_rxui <= #((i+0.5)*tm_refclk_period/cfg_rx_clk_ratio) !refclk;
            end
        end
        tm_refclk = $time;

        // calculate tx unit lane delay increment = 32ui/cfg_tx_lane_delay_divisor
        tm_tx_unit_lane_delay = (32*(tm_refclk_period/(2*cfg_tx_clk_ratio)))/cfg_tx_lane_delay_divisor;
        // calculate rx ui
        tm_rx_ui = tm_refclk_period/(2*cfg_rx_clk_ratio);
    end

    // flit clock divider
    always @(posedge clk_txui) begin
        cnt_txui--;
    end
    assign LxTXCLK = cnt_txui[1 + cfg_half_link_mode_tx];

    always @(posedge clk_rxui) begin
        cnt_rxui--;
    end
    assign LxRXCLK = cnt_rxui[1 + cfg_half_link_mode_rx];

    // determine times to calculate rx lane skew to center data between clock edges.  Both clock edges used.
    always @(posedge clk_rxui) begin
        tm_rx_clk_posedge <= $time;
    end

    always @(negedge clk_rxui) begin
        tm_rx_clk_negedge <= $time;
    end

    assign tm_rx_data_spot = ((tm_rx_clk_posedge + tm_rx_clk_negedge)/2) + tm_rx_ui;

`endif // HMC_SERDES

    // gather times for LxRXPS rise and fall
    always @(negedge LxRXPS) LxRXPS_fall <= $time;  // enter down mode when the last link goes into sleep mode
    always @(posedge LxRXPS) LxRXPS_rise <= $time;

    // gather times for LxTXPS rise and fall
    always @(negedge LxTXPS) LxTXPS_fall <= $time;
    always @(posedge LxTXPS) LxTXPS_rise <= $time;

    always @(posedge LxRXPS) begin
        assert_tsref: assert (($time - LxRXPS_fall >= cfg_tsref) || (LxRXPS_fall == 0)) else begin
            $warning("tSREF violation.  Time between LxRXPS fall (%t) and LxRXPS rise (%t) must be >= %t", LxRXPS_fall, $realtime, cfg_tsref);
        end
    end

    always @(negedge LxTXPS) begin
        assert_top: assert (($time - LxTXPS_rise >= cfg_top) || ($time == 0)) else begin
            $warning("tOP violation.  Time between LxTXPS rise (%t) and LxTXPS fall (%t) must be >= %t", LxTXPS_rise, $realtime, cfg_top);
        end
    end
    
`ifndef HMC_FLIT //HMC_SERDES
    generate
        for(genvar i=0; i<16; i=i+1) begin: gen_rx_clk_align
            // calculate rx lane skew by comparing data edge to center of clk transistions
            always @(posedge LxRX[i] or negedge LxRX[i]) begin
                if(~rx_clk_align[i] & link_rxclkalign) begin
                    tm_rx_ln_edge[i] = $time;
                    if(tm_rx_ln_edge[i] <= tm_rx_data_spot) begin
                        tm_rx_ln_dly[i] = tm_rx_data_spot - tm_rx_ln_edge[i];
                    end else begin
                        tm_rx_ln_dly[i] = tm_rx_data_spot + tm_rx_ui - tm_rx_ln_edge[i];
                    end
                    rx_clk_align[i] = '1;
                end
            end
        end
    endgenerate
`endif


    always @(negedge P_RST_N or posedge LxTXCLK) begin
        if(!P_RST_N | ~hsstxoe) begin
            ts1ptr             <= '0;
            ts1seq_q           <= '0;
            tx_32null_cnt_q    <= '0;
            tx_lfsr_q[0]       <= 16'hcd56;
            tx_lfsr_q[1]       <= 16'h47ff;
            tx_lfsr_q[2]       <= 16'h75b8;
            tx_lfsr_q[3]       <= 16'h1e18;
            tx_lfsr_q[4]       <= 16'h2e10;
            tx_lfsr_q[5]       <= 16'hbeb2;
            tx_lfsr_q[6]       <= 16'hc302;
            tx_lfsr_q[7]       <= 16'h1380;
            tx_lfsr_q[8]       <= 16'h3eb3;
            tx_lfsr_q[9]       <= 16'ha769;
            tx_lfsr_q[10]      <= 16'h4580;
            tx_lfsr_q[11]      <= 16'hd665;
            tx_lfsr_q[12]      <= 16'h6318;
            tx_lfsr_q[13]      <= 16'h6014;
            tx_lfsr_q[14]      <= 16'h077b;
            tx_lfsr_q[15]      <= 16'h261f;
            txflit_q           <= '0;
            tx_lane_out_q      <= '0;
            tx_run_limit_cnt_q <= '0;

        end else begin
    
            // update tx lfsr
            for (int i=0; i<16; i++) begin
                tx_lfsr_q[i] <= lfsr_rotate(tx_lfsr_q[i], cfg_half_link_mode_tx);
            end

            // determine tx flit
            case({tx_send})
                SEND_ALT01: begin
                    if (cfg_half_link_mode_tx) begin
                        txflit_q <= {8{16'hff00}};
                    end else begin
                        txflit_q <= {4{32'hffff0000}};
                    end
                end
                SEND_ZEROS: begin
                    txflit_q <= 'b0;
                end
                SEND_TS1: begin
                    ts1_lane0_seq = {12'hf03,ts1seq_q};
                    ts1_lanen_seq = {12'hf05,ts1seq_q};
                    ts1_lanef_seq = {12'hf0c,ts1seq_q};
                    if (cfg_half_link_mode_tx) begin

                        txflit_q <= {ts1_lanef_seq[15], {6{ts1_lanen_seq[15]}}, ts1_lane0_seq[15],
                                     ts1_lanef_seq[14], {6{ts1_lanen_seq[14]}}, ts1_lane0_seq[14],
                                     ts1_lanef_seq[13], {6{ts1_lanen_seq[13]}}, ts1_lane0_seq[13],
                                     ts1_lanef_seq[12], {6{ts1_lanen_seq[12]}}, ts1_lane0_seq[12],
                                     ts1_lanef_seq[11], {6{ts1_lanen_seq[11]}}, ts1_lane0_seq[11],
                                     ts1_lanef_seq[10], {6{ts1_lanen_seq[10]}}, ts1_lane0_seq[10],
                                     ts1_lanef_seq[9] , {6{ts1_lanen_seq[9] }}, ts1_lane0_seq[9] ,
                                     ts1_lanef_seq[8] , {6{ts1_lanen_seq[8] }}, ts1_lane0_seq[8] ,
                                     ts1_lanef_seq[7] , {6{ts1_lanen_seq[7] }}, ts1_lane0_seq[7] ,
                                     ts1_lanef_seq[6] , {6{ts1_lanen_seq[6] }}, ts1_lane0_seq[6] ,
                                     ts1_lanef_seq[5] , {6{ts1_lanen_seq[5] }}, ts1_lane0_seq[5] ,
                                     ts1_lanef_seq[4] , {6{ts1_lanen_seq[4] }}, ts1_lane0_seq[4] ,
                                     ts1_lanef_seq[3] , {6{ts1_lanen_seq[3] }}, ts1_lane0_seq[3] ,
                                     ts1_lanef_seq[2] , {6{ts1_lanen_seq[2] }}, ts1_lane0_seq[2] ,
                                     ts1_lanef_seq[1] , {6{ts1_lanen_seq[1] }}, ts1_lane0_seq[1] ,
                                     ts1_lanef_seq[0] , {6{ts1_lanen_seq[0] }}, ts1_lane0_seq[0] 
                                    };
                        if(ts1seq_q == 4'hf)
                            ts1seq_q <= 4'h0;
                        else
                            ts1seq_q <= ts1seq_q+1'b1;
                    end else begin
                        txflit_q <= {ts1_lanef_seq[(8*ts1ptr)+7], {14{ts1_lanen_seq[(8*ts1ptr)+7]}}, ts1_lane0_seq[(8*ts1ptr)+7],
                                     ts1_lanef_seq[(8*ts1ptr)+6], {14{ts1_lanen_seq[(8*ts1ptr)+6]}}, ts1_lane0_seq[(8*ts1ptr)+6],
                                     ts1_lanef_seq[(8*ts1ptr)+5], {14{ts1_lanen_seq[(8*ts1ptr)+5]}}, ts1_lane0_seq[(8*ts1ptr)+5],
                                     ts1_lanef_seq[(8*ts1ptr)+4], {14{ts1_lanen_seq[(8*ts1ptr)+4]}}, ts1_lane0_seq[(8*ts1ptr)+4],
                                     ts1_lanef_seq[(8*ts1ptr)+3], {14{ts1_lanen_seq[(8*ts1ptr)+3]}}, ts1_lane0_seq[(8*ts1ptr)+3],
                                     ts1_lanef_seq[(8*ts1ptr)+2], {14{ts1_lanen_seq[(8*ts1ptr)+2]}}, ts1_lane0_seq[(8*ts1ptr)+2],
                                     ts1_lanef_seq[(8*ts1ptr)+1], {14{ts1_lanen_seq[(8*ts1ptr)+1]}}, ts1_lane0_seq[(8*ts1ptr)+1],
                                     ts1_lanef_seq[(8*ts1ptr)]  , {14{ts1_lanen_seq[(8*ts1ptr)]  }}, ts1_lane0_seq[(8*ts1ptr)]
                                    };
                        if(ts1ptr == 1) begin
                            ts1ptr <= 0;
                            if(ts1seq_q == 4'hf)
                                ts1seq_q <= 4'h0;
                            else
                                ts1seq_q <= ts1seq_q+1'b1;
                        end else begin
                            ts1ptr <= 1;
                        end
                    end
                end
                SEND_FLITS: begin
                    txflit_q <= tx_fi.fi.FLIT;
                end
                SEND_Z: begin
                    txflit_q <= 'bz;
                end
                default: begin
                    txflit_q <= 'bz;
                end
            endcase
        
            if(~link_idle_reset_n)
                tx_32null_cnt_q <= '0;
            else
                tx_32null_cnt_q <= tx_32null_cnt_d;

            tx_lane_out_q      <= tx_lane_out_d;
            tx_run_limit_cnt_q <= tx_run_limit_cnt_d;
        end

`ifdef HMC_FLIT

        // serialize tx_fi.FLIT onto LxTXP
        if (!P_RST_N) begin
            LxTXFLIT <= 'bz;
        end else if (tx_send == SEND_Z) begin
            LxTXFLIT <= 'bz;
        end else begin
            LxTXFLIT <= tx_flit_out;
        end 
`else // HMC_SERDES
        // serialize tx_fi.FLIT onto LxTXP
        if (!P_RST_N) begin
            LxTX <= 'bz;
        end else if (tx_send == SEND_Z) begin
            LxTX <= 'bz;
        end else begin
            LxTXFLIT = tx_flit_out;
            for (int i=0; i<(8<<cfg_half_link_mode_tx); i++) begin
                if (cfg_half_link_mode_tx)
                    LxTX <= LxTXFLIT[i*8+:8];
                else
                    LxTX <= LxTXFLIT[i*16+:16];
                @(clk_txui);
            end
        end
`endif // HMC_SERDES
    end // negedge P_RST_N or posedge LxTXCLK

    // drive credits on the tx flit interface
    task run_tx();
        tx_fi.fi.cfg_rx_en <= 1; // turn on flit interface driver
        
/*
        forever @(negedge tx_fi.fi.RESET_N or posedge tx_fi.fi.CLK) begin
            if (!tx_fi.fi.RESET_N) begin
                tx_fi.fi.CREDIT <= 0;
                tx_fi.fi.rx_credits <= tx_fi.fi.cfg_rx_credits;
            end else begin
                // track credits, return credit immediately
                tx_fi.fi.rx_credits += tx_fi.fi.VALID;
                if (tx_fi.fi.rx_credits) begin
                    tx_fi.fi.CREDIT <= 1;
                    tx_fi.fi.rx_credits--;
                end else begin
                    tx_fi.fi.CREDIT <= 0;
                end

                //assert_tx_valid_low_while_in_sleep_mode : assert (!in_sleep_mode || ((tx_fi.fi.VALID == 0) && (in_sleep_mode == 1))) else
                //    $error("tx_fi.fi.VALID must be 0 while in_sleep_mode", tx_fi.fi.VALID);
            end

        end
*/
    endtask : run_tx

`ifndef HMC_FLIT //HMC_SERDES
    // test feature, add delay to TX serial outputs, cfg * unit lane delay
    always @* begin
        for(int i=0; i<16; i++) begin
            LxTXdly[i] <= #(cfg_tx_lane_delay[i]*tm_tx_unit_lane_delay) LxTX[i];
        end
    end

    //add skew to RX serial inputs, to center data within clk_rxui
    always @* begin
        for(int i=0; i<16; i++) begin
            LxRXdly[i] <= #(tm_rx_ln_dly[i]) LxRX[i];
        end
    end
`endif

    // deserialize LxRXP onto rx_fi.FLIT
    task run_rx();
        forever @(negedge rx_fi.fi.RESET_N or posedge rx_fi.fi.CLK) begin
            if (cfg_info_msg && link_train_sm_d != link_train_sm_q)
                $display("%t %m SERDES: Training State: %s", $realtime, link_train_sm_d.name());

            if(~rx_fi.fi.RESET_N | ~link_idle_reset_n | (tx_send == SEND_Z)) begin
                rx_auto_lane_invert_q   <= '0;
                rx_auto_lane_reversal_q <= '0;
                rx_cycle_cnt_q          <= '0;
                rx_dscrm_flit_q         <= '0;
                rx_lfsr_cmp_eq_cnt_q    <= '0;
                rx_lfsr_cmp_err_cnt_q   <= '0;
                rx_lfsr_q               <= '0;
                rx_lfsr_s1_q            <= '0;
                rx_lfsr_sync_q          <= '0;
                rx_signal_detected_q    <= '0;
                rxflit_q                <= '0;
                for (int i=0; i<16; ++i) begin
                   // rx_ln_align_f0_ptr_q[i]  <= '0;
                    rx_ln_align_f0_ptr_q[i]  <= 8; //.
                    rx_ln_seq_diff_q[i] <= '0;
                end

           end else begin
                rxflit_q           <= LxRXFLIT;
                rx_dscrm_flit_q[0] <= lfsr_scramble(LxRXFLIT, rx_lfsr_q, cfg_half_link_mode_rx, cfg_descram_enb, rx_lane_invert);

                for(int i=0; i<7; ++i) 
                    rx_dscrm_flit_q[i+1] <= rx_dscrm_flit_q[i];

                rx_auto_lane_invert_q   <= rx_auto_lane_invert_d;
                rx_auto_lane_reversal_q <= rx_auto_lane_reversal_d;
                rx_cycle_cnt_q          <= rx_cycle_cnt_d;
                rx_lfsr_cmp_eq_cnt_q    <= rx_lfsr_cmp_eq_cnt_d;
                rx_lfsr_cmp_err_cnt_q   <= rx_lfsr_cmp_err_cnt_d;
                rx_lfsr_q               <= rx_lfsr_d;
                rx_lfsr_s1_q            <= rx_lfsr_q;
                rx_lfsr_sync_q          <= rx_lfsr_sync_d;
                rx_signal_detected_q    <= rx_signal_detected_d;
                rx_ln_align_f0_ptr_q    <= rx_ln_align_f0_ptr_d;
                rx_ln_seq_diff_q        <= rx_ln_seq_diff_d;
            end

            if (!rx_fi.fi.RESET_N) begin
                link_idle_q <= '0;
                link_train_sm_q <= SLEEP;

                rx_fi.fi.cfg_tx_en <= 0; // turn off flit interface driver
                rx_fi.fi.FLIT  <= '0;
                rx_fi.fi.HEAD  <= '0;                
                rx_fi.fi.VALID <= '0;
                rx_fi.fi.TAIL  <= '0;
                rx_lng = '0;
            end else begin
                link_idle_q <= {link_idle_q[0], link_idle};
                link_train_sm_q <= link_train_sm_d;


                // todo: track rx_credits, cannot drive onto rx_fi unless rx_credits != 0
                // drive HEAD, VALID and TAIL bits onto rx_fi
                if (rx_fi.fi.CREDIT[0])
                    rx_fi.fi.tx_credits++;

                if (rx_link_active &&
                    rx_fi.fi.tx_credits &&
                    (
                     // if cube link mode / tb drive : ignore data coming back after LxRXPS
                     // if host link mode : keep reading flits until powerdown
                     (LxRXPS && (cfg_host_mode == 3)) || 
                     (LxTXPS && (cfg_host_mode == 1 || cfg_host_mode == 2))
                    )
                    ) begin
                    rx_fi.fi.FLIT <= rx_flit_out;
                    rx_fi.fi.HEAD <= bit'(!rx_lng && (rx_flit_out[10:7] || cfg_send_null)); // cast 'x' to 0
                    if (!rx_lng)
                        rx_lng = (rx_flit_out[10:7] | (cfg_send_null && !rx_flit_out[10:7]));
                    rx_fi.fi.VALID <= (rx_lng != 0);
                    rx_fi.fi.TAIL  <= (rx_lng == 1);
                    if (rx_lng)
                        rx_lng--;
                    rx_fi.fi.tx_credits--;
                end else begin
                    rx_fi.fi.FLIT  <= '0;
                    rx_fi.fi.HEAD  <= '0;                
                    rx_fi.fi.VALID <= '0;
                    rx_fi.fi.TAIL  <= '0;
                    //rx_lng = '0;
                end

`ifndef HMC_FLIT //HMC_SERDES
                for (int i=0; i<(8<<cfg_half_link_mode_rx); i++) begin
                    if (cfg_half_link_mode_rx)
                        LxRXFLIT[i*8+:8] <= LxRXdly;
                    else
                        LxRXFLIT[i*16+:16] <= LxRXdly;
                    @(clk_rxui);
                end
`endif
            end

            // TEMP DISABLE
            // assert_rx_valid_low_while_in_sleep_mode : assert (!(in_sleep_mode) || ((rx_fi.fi.VALID == 0) && (in_sleep_mode == 1))) else begin
            //    $error("rx_fi.fi.VALID : %h is not zero while in_sleep_mode : %h", rx_fi.fi.VALID, in_sleep_mode);
            // end

        end
    endtask : run_rx

    // check signal to see if all output lanes are enabled
    assign hsstxoe =   (cfg_half_link_mode_tx) ? (cfg_hsstxoe[7:0] == 8'hff)
                     :                           (cfg_hsstxoe      == 16'hffff);
    
    initial begin
        tx_send = SEND_Z;
    end
    
    always @* begin
        link_train_sm_d         = link_train_sm_q;
        rx_auto_lane_invert_d   = rx_auto_lane_invert_q;
        rx_auto_lane_reversal_d = rx_auto_lane_reversal_q;
        rx_cycle_cnt_d          = rx_cycle_cnt_q;
        rx_lfsr_cmp_eq_cnt_d    = rx_lfsr_cmp_eq_cnt_q;
        rx_lfsr_cmp_err_cnt_d   = rx_lfsr_cmp_err_cnt_q;
        rx_lfsr_sync_d          = rx_lfsr_sync_q;
        rx_signal_detected_d    = rx_signal_detected_q;
        tx_32null_cnt_d         = tx_32null_cnt_q;

        // 2 cycle minimum, need to reset counter in tx clk domain if idles state reentered
        link_idle_reset_n     = ~((link_idle | link_idle_q[0]) & ~link_idle_q[1]);

        for(int i=0; i<16; ++i)
            rx_lfsr_d[i] <= lfsr_rotate(rx_lfsr_q[i], cfg_half_link_mode_rx);

        // tx_send          = SEND_Z;
        link_idle        = '0;
        link_rxclkalign  = '0;
        rx_lane_expected = '0;
        rx_ln_bit_sum    = '0;
        rx_link_active   = '0;
        tx_link_active   = '0;
        
        for(int i=0; i<16; ++i) begin
            if(cfg_half_link_mode_rx) begin
                rx_ln_align_ptr[i] = rx_ln_align_f0_ptr_q[i] - 8 - (16*rx_ln_seq_diff_q[i]);
            end else begin
                rx_ln_align_ptr[i] = rx_ln_align_f0_ptr_q[i] - (16*rx_ln_seq_diff_q[i]);
            end
        end

        if (~hsstxoe | (cfg_host_mode == 2'h0) | retrain ) begin

            link_train_sm_d = IDLE;
            
            link_idle    = 1'b1;
            rx_clk_align = '0;
            rx_ts1_sync  = '0;           
            
        end else begin
            if (in_sleep_mode) begin
                link_train_sm_d = SLEEP;
            end
            
            case(link_train_sm_q)
                SLEEP: begin
                    tx_send = SEND_Z;
                    link_idle    = 1'b1;
                    rx_clk_align = '0;
                    rx_ts1_sync  = '0;

                    if (!in_sleep_mode) begin
                        link_train_sm_d = IDLE;
                    end           
                end

                IDLE: begin
                    link_idle    = 1'b1;
                    tx_send      = SEND_ALT01;
                    // bypass DESCRAMSYNC state in flit interface 
`ifdef HMC_FLIT
                    rx_clk_align = '1;
`else // HMC_SERDES
                    rx_clk_align = '0;
`endif
                    rx_ts1_sync  = '0;

                    // cnt # of bits in lane capture
                    if(cfg_descram_enb) begin
                        // add bits to insure some bits are not z,x when testing for all 1's, or 0's
                        for(int lane=0; lane<num_lanes_rx; ++lane) begin
                            for(int j=0; j<num_flit_bits_per_lane_rx; ++j) begin
                                rx_ln_bit_sum[lane] = rx_ln_bit_sum[lane] + rx_lane_capture[lane][j];
                            end
                        end
                        // detect that lane is not all 0's or all 1's
                        for(int i=0; i<16; ++i) begin
                            // line with problem
                           rx_signal_detected_d[i] = (rx_ln_bit_sum[i] > 16'h0) && (rx_ln_bit_sum[i] < 6'h10);
                        end
                    end else begin
                        rx_signal_detected_d = {{8{~cfg_half_link_mode_rx}},8'hff};
                    end 

                    // advance to next state if all lanes detect signal
                    if(rx_signal_detected_q == {{8{~cfg_half_link_mode_rx}},8'hff}) begin
                        if(cfg_descram_enb) begin
                            link_train_sm_d = RXALIGNDATACLK;
                        end else begin
                            link_train_sm_d = DESCRAMSYNC;
                            tm_descram_sync = $time;
                        end
                    end
                end

                // In hardware this occurs before link training state machine is started.
                RXALIGNDATACLK: begin
                    link_rxclkalign = 1'b1;
                    if (cfg_host_mode == 2'h3) begin
                        if(cfg_descram_enb)
                            tx_send = SEND_ZEROS;
                        else
                            tx_send = SEND_TS1;
                    end else begin
                        if(cfg_descram_enb)
                            tx_send = SEND_ALT01;
                        else
                            tx_send = SEND_ZEROS;
                    end

                    // center rx lane data between edges of clk_rxui
                    if(rx_clk_align == {{8{~cfg_half_link_mode_rx}},8'hff}) begin
                        if(cfg_descram_enb) begin
                            link_train_sm_d = DESCRAMSYNC;
                            tm_descram_sync = $time;
                        end else begin
                            link_train_sm_d = TS1SYNC;
                            tm_ts1_sync     = $time;
                        end
                    end
                end

                DESCRAMSYNC: begin
                    if (cfg_host_mode == 2'h3) begin
                        tx_send = SEND_ZEROS;
                    end else begin
                        tx_send = SEND_ALT01;
                    end

                    // compare lane data to rx lfsr, if they do not match reseed rx lfsr
                    if(rx_cycle_cnt_q==(6'h1 << ~cfg_half_link_mode_rx)) begin
                        rx_cycle_cnt_d <= 6'h1;
                        for(int i=0; i<(16>>cfg_half_link_mode_rx); ++i) begin
                            if(~rx_lfsr_sync_q[i]) begin
                                if(cfg_half_link_mode_rx) begin
                                    rx_lane_expected[i] = rx_lfsr_q[i];
                                end else begin
                                    rx_lane_expected[i] = rx_lfsr_s1_q[i];
                                end

                                // if match 4 consecutive times, lfsr synced
                                if(rx_lane_capture[i] == rx_lane_expected[i]) begin
                                    rx_lfsr_cmp_eq_cnt_d[i]  = rx_lfsr_cmp_eq_cnt_q[i] + 1'b1;
                                    rx_lfsr_cmp_err_cnt_d[i] = '0;
                                    rx_lfsr_sync_d[i]        = (rx_lfsr_cmp_eq_cnt_q[i] == 4'h3) | rx_lfsr_sync_q[i];
                                // if match fails for 4 consecutive times invert lane
                                end else begin
                                    rx_lfsr_cmp_eq_cnt_d[i]  = '0;
                                    rx_lfsr_d[i] <= lfsr_calc(rx_lane_capture[i], cfg_half_link_mode_rx);

                                    if ((rx_lfsr_cmp_err_cnt_q[i] == 4'h3) && cfg_lane_auto_correct) begin
                                        rx_auto_lane_invert_d[i] = ~rx_auto_lane_invert_q[i];
                                        rx_lfsr_cmp_err_cnt_d[i] = '0;
                                    end else begin
                                        rx_lfsr_cmp_err_cnt_d[i] = rx_lfsr_cmp_err_cnt_q[i] + 1'b1;
                                    end
                                end
                            end
                        end
                    end else begin
                        rx_cycle_cnt_d = rx_cycle_cnt_q + 6'h1;
                    end

                    // advance to next state if all lanes lfsr synced
                    if (rx_lfsr_sync_q == {{8{~cfg_half_link_mode_rx}},8'hff}) begin
                        link_train_sm_d = NZWAIT;
                        rx_cycle_cnt_d  = 0;
                    end
                end

                NZWAIT: begin
                    // wait for TS1's
                    if (cfg_host_mode == 2'h3) begin
                        tx_send = SEND_TS1;
                    end else begin
                        tx_send = SEND_ZEROS;
                    end
                    if(rx_dscrm_flit_q[0] != 128'h0) begin
                        if(cfg_descram_enb) begin
                            link_train_sm_d = TS1SYNC;
                            tm_ts1_sync     = $time;
                        end else begin
                            link_train_sm_d = RXALIGNDATACLK;
                        end
                    end
                end

                TS1SYNC: begin
                    if (cfg_host_mode == 2'h3) begin
                        tx_send = SEND_TS1;
                    end else begin
                        tx_send = SEND_ZEROS;
                    end


                    // look for f0 portion of TS1, use pointer to track position in descrambled lane data
                    if(rx_cycle_cnt_q == 6'h8) begin
                        for(int i=0; i<16; ++i) begin
                            for(int j=0; j<16; ++j) begin
                                if(rx_dscrm_lane[i][(56-j)+:8]==8'hf0) begin
                                    rx_ts1_sync[i]        = 1'b1;
                                    rx_ln_align_f0_ptr_d[i] = 56-j;
                                    rx_ln_id[i]           = rx_dscrm_lane[i][(52-j)+:4];
                                    rx_ln_seq[i]          = rx_dscrm_lane[i][(48-j)+:4];
                                end
                            end
                            
                        end

                        // this code is LANEDESKEW functionality but for convenience is located here.
                        // the max number of TS1s held in rx_dscrm_lane is 4, test for rollover
                        if(rx_ts1_sync == {{8{~cfg_half_link_mode_rx}},8'hff}) begin
                            rx_ln_seq_min =  rx_ln_seq[0];

                            // compare lane seq number to find lowest seq number, check for rollover
                            for(int i=1; i<16; ++i) begin
                                //test for rollover
                                if(~((rx_ln_seq_min >= 12) && (rx_ln_seq[i] <= 3))) begin
                                    if(rx_ln_seq[i] < rx_ln_seq_min) begin
                                        rx_ln_seq_min = rx_ln_seq[i];
                                    end
                                end
                            end

                            // adjust pointer based on seq number
                            for(int i=0; i<16; ++i) begin
                                if((rx_ln_seq_min >= 12) && (rx_ln_seq[i] <= 3)) begin
                                    rx_ln_seq_diff_d[i]  = {1'b1,rx_ln_seq[i]} - {1'b0,rx_ln_seq_min};
                                end else begin
                                    rx_ln_seq_diff_d[i]  = rx_ln_seq[i] - rx_ln_seq_min;
                                end
                            end

                            // test lane id to determine if lanes should be reversed
                            if(cfg_half_link_mode_rx) begin
                                rx_auto_lane_reversal_d = (rx_ln_id[0] == 4'hc) & (rx_ln_id[7] == 4'h3);
                            end else begin
                                rx_auto_lane_reversal_d = (rx_ln_id[0] == 4'hc) & (rx_ln_id[15] == 4'h3);
                            end
                                
                            link_train_sm_d = ZEROWAIT;
                            rx_cycle_cnt_d  = 0;
                        end
                    end else begin
                        rx_cycle_cnt_d = rx_cycle_cnt_q + 6'h1;
                    end 
                end

                ZEROWAIT: begin
                    // wait for 0's after TS1
                    if (cfg_host_mode == 2'h3) begin
                        tx_send = SEND_ZEROS;
                    end else begin
                        tx_send = SEND_TS1;
                    end
                    if(rx_flit_out == 128'h0)
                        link_train_sm_d = LINKACTIVE32NULL;
                end

                LINKACTIVE32NULL: begin
                    // insure 32 Null flits are sent before transaction layer packets
                    // count nulls in tx clk domain
                    rx_link_active  = cfg_pkt_rx_enb;
                    tx_send = SEND_ZEROS;
                    if(tx_32null_cnt_q == 6'h1f) begin
                        link_train_sm_d = LINKACTIVE;
                    end else begin
                        tx_32null_cnt_d = tx_32null_cnt_q + 6'h1;
                    end
                end

                LINKACTIVE: begin
                    rx_link_active = cfg_pkt_rx_enb;
                    tx_link_active = cfg_pkt_tx_enb;
                    tx_send = SEND_FLITS;
                end
            endcase
        end
    end


    // invert and/or reverese rx lanes due to link training discovery process or cfg
    assign rx_lane_invert =   (cfg_descram_enb & cfg_lane_auto_correct) ? rx_auto_lane_invert_q
                            :                                             cfg_hssrx_inv;

    assign rx_lane_reversal = (cfg_lane_auto_correct & rx_auto_lane_reversal_q) | cfg_lane_reverse;


    // tx logic
    always @* begin

        // apply lfsr to tx data
        tx_scram_out = lfsr_scramble(txflit_q, tx_lfsr_q, cfg_half_link_mode_tx, cfg_scram_enb, cfg_hsstx_inv);

        // check run limit on lane basis, if limit reached flip output bit
        tx_run_limit_en = (cfg_tx_rl_lim != 8'h00);
        
        tx_run_limit_mask  = '0;
        tx_lane_out_d      = tx_lane_out_q;
        tx_run_limit_cnt_d = tx_run_limit_cnt_q;

        // count unchanging tx lanes, create mask to flip bits if run limit reached.  crc error created
        for (int lane=0; lane<num_lanes_tx; lane++) begin
            for (int j=0; j<num_flit_bits_per_lane_tx; j++) begin
                if(tx_scram_out[(num_lanes_tx*j)+lane] == tx_lane_out_d[lane]) begin
                    tx_run_limit_cnt_d[lane] = tx_run_limit_cnt_d[lane] + 8'h1;
                end else begin
                    tx_run_limit_cnt_d[lane] = 8'h0;
                end
                if((tx_run_limit_cnt_d[lane] == cfg_tx_rl_lim) & tx_run_limit_en) begin
                    tx_run_limit_mask[(num_lanes_tx*j)+lane] = 1'b1;
                    tx_run_limit_cnt_d[lane] = 8'h0;
                end
                tx_lane_out_d[lane] = tx_scram_out[(num_lanes_tx*j)+lane];
            end   
        end

        // apply rll mask
        tx_rll_out = tx_scram_out ^ tx_run_limit_mask;

        // test feature, reverse lane outputs, controlled by cfg 
        if(cfg_tx_lane_reverse) begin
            for (int i=0; i<num_flit_bits_per_lane_tx; i++) begin
                for (int lane=0; lane<num_lanes_tx; lane++) begin
                    tx_flit_out[(num_lanes_tx*i)+(num_lanes_tx-1-lane)] = tx_rll_out[(num_lanes_tx*i)+lane];
                end
            end

        end else begin
            tx_flit_out = tx_rll_out;
        end
    end
    
    always_comb begin

        // rx_lane_capture bit 0 oldest, bit 15 youngest, captures rx lane before descrambling
        // rx_dscrm_lane   bit 0 oldest, bit 63 youngest, captures rx lane after descrambling, 
        if (cfg_half_link_mode_rx) begin
            rx_lane_capture[15:8] = '0;

            for (int i=0; i<8; i++) begin
                rx_lane_capture[i] = {LxRXFLIT[120+i], LxRXFLIT[112+i], LxRXFLIT[104+i], LxRXFLIT[96+i],
                                      LxRXFLIT[88+i],  LxRXFLIT[80+i],  LxRXFLIT[72+i],  LxRXFLIT[64+i],
                                      LxRXFLIT[56+i],  LxRXFLIT[48+i],  LxRXFLIT[40+i],  LxRXFLIT[32+i],
                                      LxRXFLIT[24+i],  LxRXFLIT[16+i],  LxRXFLIT[8+i],   LxRXFLIT[i]
                                     } ^ {16{rx_lane_invert[i]}};

            end
        end else begin
            for (int i=0; i<16; i++) begin
                rx_lane_capture[i] = {LxRXFLIT[112+i], LxRXFLIT[96+i],  LxRXFLIT[80+i],  LxRXFLIT[64+i],
                                      LxRXFLIT[48+i],  LxRXFLIT[32+i],  LxRXFLIT[16+i],  LxRXFLIT[i],
                                      rxflit_q[112+i], rxflit_q[96+i],  rxflit_q[80+i],  rxflit_q[64+i],
                                      rxflit_q[48+i],  rxflit_q[32+i],  rxflit_q[16+i],  rxflit_q[i]
                                     } ^ {16{rx_lane_invert[i]}};

            end

        end
    end

    always_comb begin

        // rx_dscrm_lane   bit 0 oldest, bit 63 youngest, captures rx lane after descrambling, 
        if (cfg_half_link_mode_rx) begin
            rx_dscrm_lane[15:8]   = '0;

            for (int i=0; i<8; i++) begin
                rx_dscrm_lane[i] = {rx_dscrm_flit_q[0][120+i], rx_dscrm_flit_q[0][112+i], rx_dscrm_flit_q[0][104+i], rx_dscrm_flit_q[0][96+i],
                                    rx_dscrm_flit_q[0][88+i],  rx_dscrm_flit_q[0][80+i],  rx_dscrm_flit_q[0][72+i],  rx_dscrm_flit_q[0][64+i],
                                    rx_dscrm_flit_q[0][56+i],  rx_dscrm_flit_q[0][48+i],  rx_dscrm_flit_q[0][40+i],  rx_dscrm_flit_q[0][32+i],
                                    rx_dscrm_flit_q[0][24+i],  rx_dscrm_flit_q[0][16+i],  rx_dscrm_flit_q[0][8+i],   rx_dscrm_flit_q[0][i],
                                    rx_dscrm_flit_q[1][120+i], rx_dscrm_flit_q[1][112+i], rx_dscrm_flit_q[1][104+i], rx_dscrm_flit_q[1][96+i],
                                    rx_dscrm_flit_q[1][88+i],  rx_dscrm_flit_q[1][80+i],  rx_dscrm_flit_q[1][72+i],  rx_dscrm_flit_q[1][64+i],
                                    rx_dscrm_flit_q[1][56+i],  rx_dscrm_flit_q[1][48+i],  rx_dscrm_flit_q[1][40+i],  rx_dscrm_flit_q[1][32+i],
                                    rx_dscrm_flit_q[1][24+i],  rx_dscrm_flit_q[1][16+i],  rx_dscrm_flit_q[1][8+i],   rx_dscrm_flit_q[1][i],
                                    rx_dscrm_flit_q[2][120+i], rx_dscrm_flit_q[2][112+i], rx_dscrm_flit_q[2][104+i], rx_dscrm_flit_q[2][96+i],
                                    rx_dscrm_flit_q[2][88+i],  rx_dscrm_flit_q[2][80+i],  rx_dscrm_flit_q[2][72+i],  rx_dscrm_flit_q[2][64+i],
                                    rx_dscrm_flit_q[2][56+i],  rx_dscrm_flit_q[2][48+i],  rx_dscrm_flit_q[2][40+i],  rx_dscrm_flit_q[2][32+i],
                                    rx_dscrm_flit_q[2][24+i],  rx_dscrm_flit_q[2][16+i],  rx_dscrm_flit_q[2][8+i],   rx_dscrm_flit_q[2][i],
                                    rx_dscrm_flit_q[3][120+i], rx_dscrm_flit_q[3][112+i], rx_dscrm_flit_q[3][104+i], rx_dscrm_flit_q[3][96+i],
                                    rx_dscrm_flit_q[3][88+i],  rx_dscrm_flit_q[3][80+i],  rx_dscrm_flit_q[3][72+i],  rx_dscrm_flit_q[3][64+i],
                                    rx_dscrm_flit_q[3][56+i],  rx_dscrm_flit_q[3][48+i],  rx_dscrm_flit_q[3][40+i],  rx_dscrm_flit_q[3][32+i],
                                    rx_dscrm_flit_q[3][24+i],  rx_dscrm_flit_q[3][16+i],  rx_dscrm_flit_q[3][8+i],   rx_dscrm_flit_q[3][i]
                                   };
            end


        end else begin
            for (int i=0; i<16; i++) begin
                rx_dscrm_lane[i] = {rx_dscrm_flit_q[0][112+i], rx_dscrm_flit_q[0][96+i],  rx_dscrm_flit_q[0][80+i],  rx_dscrm_flit_q[0][64+i],
                                    rx_dscrm_flit_q[0][48+i],  rx_dscrm_flit_q[0][32+i],  rx_dscrm_flit_q[0][16+i],  rx_dscrm_flit_q[0][i],
                                    rx_dscrm_flit_q[1][112+i], rx_dscrm_flit_q[1][96+i],  rx_dscrm_flit_q[1][80+i],  rx_dscrm_flit_q[1][64+i],
                                    rx_dscrm_flit_q[1][48+i],  rx_dscrm_flit_q[1][32+i],  rx_dscrm_flit_q[1][16+i],  rx_dscrm_flit_q[1][i],
                                    rx_dscrm_flit_q[2][112+i], rx_dscrm_flit_q[2][96+i],  rx_dscrm_flit_q[2][80+i],  rx_dscrm_flit_q[2][64+i],
                                    rx_dscrm_flit_q[2][48+i],  rx_dscrm_flit_q[2][32+i],  rx_dscrm_flit_q[2][16+i],  rx_dscrm_flit_q[2][i],
                                    rx_dscrm_flit_q[3][112+i], rx_dscrm_flit_q[3][96+i],  rx_dscrm_flit_q[3][80+i],  rx_dscrm_flit_q[3][64+i],
                                    rx_dscrm_flit_q[3][48+i],  rx_dscrm_flit_q[3][32+i],  rx_dscrm_flit_q[3][16+i],  rx_dscrm_flit_q[3][i],
                                    rx_dscrm_flit_q[4][112+i], rx_dscrm_flit_q[4][96+i],  rx_dscrm_flit_q[4][80+i],  rx_dscrm_flit_q[4][64+i],
                                    rx_dscrm_flit_q[4][48+i],  rx_dscrm_flit_q[4][32+i],  rx_dscrm_flit_q[4][16+i],  rx_dscrm_flit_q[4][i],
                                    rx_dscrm_flit_q[5][112+i], rx_dscrm_flit_q[5][96+i],  rx_dscrm_flit_q[5][80+i],  rx_dscrm_flit_q[5][64+i],
                                    rx_dscrm_flit_q[5][48+i],  rx_dscrm_flit_q[5][32+i],  rx_dscrm_flit_q[5][16+i],  rx_dscrm_flit_q[5][i],
                                    rx_dscrm_flit_q[6][112+i], rx_dscrm_flit_q[6][96+i],  rx_dscrm_flit_q[6][80+i],  rx_dscrm_flit_q[6][64+i],
                                    rx_dscrm_flit_q[6][48+i],  rx_dscrm_flit_q[6][32+i],  rx_dscrm_flit_q[6][16+i],  rx_dscrm_flit_q[6][i],
                                    rx_dscrm_flit_q[7][112+i], rx_dscrm_flit_q[7][96+i],  rx_dscrm_flit_q[7][80+i],  rx_dscrm_flit_q[7][64+i],
                                    rx_dscrm_flit_q[7][48+i],  rx_dscrm_flit_q[7][32+i],  rx_dscrm_flit_q[7][16+i],  rx_dscrm_flit_q[7][i]
                                   };
            end
        end
    end

    always_comb begin
        for (int lane=0; lane<num_lanes_rx; lane++) begin
            for (int j=0; j<num_flit_bits_per_lane_rx; j++) begin
                if(rx_lane_reversal) begin
                    rx_flit_out[(num_lanes_rx*j)+(num_lanes_rx-1-lane)] = rx_dscrm_lane[lane][rx_ln_align_ptr[lane]+j];
                end else begin
                    rx_flit_out[(num_lanes_rx*j)+lane] = rx_dscrm_lane[lane][rx_ln_align_ptr[lane]+j];
                end
            end
        end
    end

    // lfsr functions
    // apply lfsr and lane inversion to data
    function logic [127:0] lfsr_scramble (input [127:0] d, input [15:0][15:0] lfsr_i, input half_width, input scram_en, input [15:0] lane_inv);
        logic [127:0] lfsr;
        logic [127:0] flit_inv;
        int   num_lanes; 
        // PR: num_ui is the number of bits from each lane that will make up the portion of the flit;
        // specifically in this context, how far back in the LFSR history do we need to look 
        int   num_ui; 

        begin
            if (half_width) begin
                flit_inv = {16{lane_inv[7:0]}};
            end else begin
                flit_inv = {8{lane_inv[15:0]}};
            end

            if (half_width) begin
                num_lanes = 8;
            end else begin
                num_lanes = 16;
            end

            // PR: guarantee that the loop below will always generate a flit's worth of bits 
            num_ui = 128/num_lanes;
            
            if (scram_en) begin
                lfsr = '0;
                for(int ui=0; ui<num_ui; ++ui) begin
                    for(int lane=0; lane<num_lanes; ++lane) begin
                        lfsr = (lfsr_i[lane][ui] << ((num_lanes*ui)+lane)) | lfsr;
                    end
                end

                lfsr_scramble = d ^ flit_inv ^ lfsr;
            end else begin // not scrambling
                lfsr_scramble = d ^ flit_inv;
            end
        end
    endfunction 

    // advance lfsr per flit clk
    function logic [15:0] lfsr_rotate (input [15:0] lfsr_i, input half_width);
        if (half_width) begin // advanced LFSR 17 time steps 
            lfsr_rotate = {(lfsr_i[3:2]^lfsr_i[1:0]),(lfsr_i[14]^lfsr_i[1]^lfsr_i[0]), (lfsr_i[14:2]^lfsr_i[13:1])};
        end else begin // advance LFSR 8 time steps 
            lfsr_rotate = {(lfsr_i[9:2]^lfsr_i[8:1]), lfsr_i[15:8]};
        end
    endfunction 

    // calculate lfsr based on captured lane data, lfsr advanced to match next lane data 
    function logic [15:0] lfsr_calc (input [15:0] lfsr_i, input half_width);
        if (half_width) begin
//            lfsr_calc = {^lfsr_i[5:2], ^lfsr_i[4:1], ^lfsr_i[3:0], (lfsr_i[14]^lfsr_i[2]^lfsr_i[1]), (lfsr_i[13]^lfsr_i[1]^lfsr_i[0]), (lfsr_i[14:4]^lfsr_i[12:2])};
            lfsr_calc = {(lfsr_i[3:2]^lfsr_i[1:0]),(lfsr_i[14]^lfsr_i[1]^lfsr_i[0]), (lfsr_i[14:2]^lfsr_i[13:1])};
        end else begin
            lfsr_calc = {(lfsr_i[3:2]^lfsr_i[1:0]),(lfsr_i[14]^lfsr_i[1]^lfsr_i[0]), (lfsr_i[14:2]^lfsr_i[13:1])};
        end
    endfunction 


    always @(LxRXPS) begin
        assert_sleep_entry_exit: assert ($time == 0 || !P_RST_N || LxRXPS == in_sleep_mode) else begin
            if (LxRXPS)
                $error("Sleep Mode entry must be complete prior to Sleep Mode exit.");
            else
                $error("Sleep Mode exit must be complete prior to Sleep Mode entry.");
        end
    end

//    assert_head_valid_tail: assert property (@(posedge tx_fi.CLK) tx_fi.HEAD |-> tx_fi.VALID throughout ##[0:8] tx_fi.TAIL) else
//        $error("HEAD must be followed by TAIL within [0:8] consecutive clocks.  VALID must remain asserted throughout this time.");

    // insure lfsr sync acheived in 1 us from start of training
    // the assert assumes that when simulating, link training has started when activity is detected on the rx serial lanes
    // in hardware, link training is controlled by the APG after receiving HMC init continue which is set by the host
    assert_trsp1: assert property
        (@(posedge LxRXCLK) disable iff (cfg_host_mode == 3 || link_train_sm_q != DESCRAMSYNC) ($time - tm_descram_sync < cfg_trsp1) || &(rx_lfsr_sync_q | {{8{cfg_half_link_mode_rx}},8'h0}))
    else begin
        $error("tRSP1 violation.  Descrambler failed to sync within %t.  Requester must send NULL stream to achieve Descrambler Sync", cfg_trsp1);
        $assertoff(1, assert_trsp1); // only issue this warning one time
    end


    // insure ts1 sync acheived in 1 us from start of receiving TS1s
    assert_trsp2: assert property
        (@(posedge LxRXCLK) disable iff (cfg_host_mode == 3 || link_train_sm_q != TS1SYNC)  ($time - tm_ts1_sync < cfg_trsp2) || &(rx_ts1_sync | {{8{cfg_half_link_mode_rx}},8'h0}))
    else begin
        $error("tRSP2 violation.  TS1 sync did not occur within %t.  Requester must send TS1 stream to achieve sync", cfg_trsp2);
        $assertoff(1, assert_trsp2); // only issue this warning one time
    end

    // insure that when link goes active, 32 null flits are received before any transaction layer packets
    assert_link_active_32_null: assert property
        (@(posedge LxRXCLK) ((link_train_sm_q == ZEROWAIT) & (rx_flit_out == 128'b0)) |-> (rx_flit_out == 128'b0)[*32])
    else
        $error("When link goes active, 32 NULL flits must be received before any transaction layer packets");

    // insure run limit not violated
    generate 
        for(genvar i=0; i<16; i=i+1) begin: gen_rll_assert
            always @(rx_ln_align_f0_ptr_q[i]) 
                assert_rx_ln_align_f0_ptr: assert (rx_ln_align_f0_ptr_q[i] >= 0) else
                    $error("unexpected negative pointer rx_ln_align_f0_ptr_q[%0d] = %0d.  RX lane skew must be less than 32UI.", i, rx_ln_align_f0_ptr_q[i]);

            always @(rx_ln_align_ptr[i]) 
                assert_rx_ln_align_ptr: assert (rx_ln_align_ptr[i] >= 0) else
                    $error("unexpected negative pointer rx_ln_align_ptr[%0d] = %0d.  RX lane skew must be less than 32UI.", i, rx_ln_align_ptr[i]);

/********** assertions ***************
            property rl_limit_0(rll);
                disable iff ( ((i>=8) && (cfg_half_link_mode_rx)) || !cfg_descram_enb ) @(posedge clk_rxui or negedge clk_rxui) !LxRX[i] |-> ##[1:rll] LxRX[i];
            endproperty

            property rl_limit_1(rll);
                disable iff ( ((i>=8) && (cfg_half_link_mode_rx)) || !cfg_descram_enb ) @(posedge clk_rxui or negedge clk_rxui) LxRX[i] |-> ##[1:rll] !LxRX[i];
            endproperty

            assert_rl_limit_0:
                assert property (rl_limit_0(85))
            else
                $error("Lane %d must change from 0 to 1 within 85 UI", i);

            assert_rl_limit_1:
                assert property (rl_limit_1(85))
            else
                $error("Lane %d must change from 1 to 0 within 85 UI", i);

            final begin
                 $assertkill(1, assert_rl_limit_0);
                 $assertkill(1, assert_rl_limit_1);
            end
*/
        end
    endgenerate

    function void set_config(cls_link_cfg cfg);
        link_cfg = cfg;
        cfg_link_id = cfg.cfg_link_id;
`ifdef ADG_DEBUG
        // ADG::   debug
        $sformat(fnend, "%d", cfg_link_id);
        fname = {"adg_flits_in",fnend,".txt"};
       if (cfg_host_mode != 3) begin 
        flits_in = $fopen(fname); 
       end
        fname = {"adg_flits_out",fnend,".txt"};
       if (cfg_host_mode != 3) begin 
        flits_out = $fopen(fname); 
       end
`endif
        cfg_tx_clk_ratio = cfg.cfg_tx_clk_ratio;
        cfg_rx_clk_ratio = cfg.cfg_rx_clk_ratio;
        cfg_host_mode = cfg.cfg_host_mode;
        cfg_pkt_rx_enb = cfg.cfg_pkt_rx_enb;
        cfg_pkt_tx_enb = cfg.cfg_pkt_tx_enb;
        cfg_descram_enb = cfg.cfg_descram_enb;
        cfg_scram_enb = cfg.cfg_scram_enb;
        cfg_lane_auto_correct = cfg.cfg_lane_auto_correct;
        cfg_lane_reverse = cfg.cfg_lane_reverse;
        cfg_half_link_mode_tx = cfg.cfg_half_link_mode_tx;
        cfg_half_link_mode_rx = cfg.cfg_half_link_mode_rx;
        cfg_hsstxoe = cfg.cfg_hsstxoe;
        cfg_tx_rl_lim = cfg.cfg_tx_rl_lim;
        cfg_send_null = cfg.cfg_send_null;
        cfg_hsstx_inv = cfg.cfg_hsstx_inv;
        cfg_hssrx_inv = cfg.cfg_hssrx_inv;
        cfg_tx_lane_reverse = cfg.cfg_tx_lane_reverse;
        cfg_tx_lane_delay = cfg.cfg_tx_lane_delay;
        cfg_tx_lane_delay_divisor = cfg.cfg_tx_lane_delay_divisor;
        // PR: since these don't come from the cls_link_cfg, I will leave off the cfg_ prefix 
        num_lanes_tx              = cfg_half_link_mode_tx == 0 ? 16 : 8;
        num_lanes_rx              = cfg_half_link_mode_rx == 0 ? 16 : 8;
        num_flit_bits_per_lane_tx = 128/num_lanes_tx;
        num_flit_bits_per_lane_rx = 128/num_lanes_rx;

        // convert 1ns timescale to 1ps
        cfg_trsp1 = 1000*cfg.cfg_trsp1;
        cfg_trsp2 = 1000*cfg.cfg_trsp2;
        cfg_tpst  = 1000*cfg.cfg_tpst;
        cfg_tsme  = 1000*cfg.cfg_tsme;
        cfg_trxd  = 1000*cfg.cfg_trxd;
        cfg_ttxd  = 1000*cfg.cfg_ttxd;
        cfg_tsd   = 1000*cfg.cfg_tsd;
        cfg_tis   = 1000*cfg.cfg_tis;
        cfg_tss   = 1000*cfg.cfg_tss;
        cfg_top   = 1000*cfg.cfg_top;
        cfg_tsref = 1000*cfg.cfg_tsref;
        cfg_tpsc  = 1000*cfg.cfg_tpsc;
                
    endfunction : set_config

endinterface : hmc_serdes
