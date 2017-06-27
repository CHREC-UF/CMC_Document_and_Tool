/*
 Class: cls_link_cfg
 A class that allows for storing and updating configuration
 information for the link.
 
 You can reference the values of this class from any of the interfaces
 that are passed a handle to the class.  The passing of the handle is
 done in the testbench and also in hmc_flit_top.sv.

 There is one class instantiation per link.  Each link shares the
 class values between all of the components across the link - each
 member can update or read the values in the class.
 */

class cls_link_cfg;

         bit              [2:0] cfg_link_id                = 0;            // SLID bit [2:0] todo: randomize
   randc bit              [2:0] cfg_cid                    = 0;            // SLID bit [5:3]

    rand bit                    cfg_check_pkt              = 1;            // check for valid packet

    // hmc_rsp_chk
    rand bit                    cfg_seq_tags               = 0;            // 0 = tags must be reused in order.  1 = tags may be reused out of order.  
    rand bit              [9:0] cfg_max_tags               = 512;          // maximum tags that host will send before stalling  
    
    // hmc_flow_ctrl
    rand bit              [9:0] cfg_tokens                 = 200;          // Number of tokens sent during initialization
         bit              [9:0] cfg_tokens_expected        = 0;            // Number of tokens expected during initialization. h0 - disabled  
    rand bit                    cfg_rsp_open_loop          = 0;            // LINKCTL bit 2
         bit              [1:0] cfg_host_mode              = 2'h1;         // LINKCTL bit 1:0 h0 - Link powered off; 
                                                                          //                  h1 - Link is a Host Link and a Source Link
                                                                          //                  h2 - Link is a Host Link but not a Source Link
                                                                          //                  h3 - Link is a Cube Link

         bit                    cfg_tail_rtc_dsbl          = 0;            // LMCTRL bit 28

    // hmc_retry    
    rand bit                    cfg_retry_enb              = 1;            // LINKRETRY
    rand bit            [ 3: 0] cfg_retry_limit            = 3;            // LINKRETRY - infinite retry when cfg_retry_limit[3] == 1
    rand bit            [ 2: 0] cfg_retry_timeout          = 5;            // LINKRETRY
    rand bit            [ 7: 0] cfg_init_retry_txcnt       = 6;            // LINKRETRY - number of IRTRY is this value * 4
    rand bit            [ 7: 0] cfg_init_retry_rxcnt       = 16;           // LINKRETRY
         bit            [ 3: 0] sts_init_retry_state;                      // LINKRETRY

    // hmc_serdes
    rand int unsigned           cfg_tx_clk_ratio           = 60;           // 60 : 15Gbps lane rate
	 																								// 50 : 12.5Gbps lane rate
																									// 40 : 10Gbps lane rate
																									// Calculation for 15Gbps lane rate: 
																									// 60 * 125MHz REFCLK = 7500MHz UICLK = 7.5GHz UI
																									// 7.5GHz UI * 2 bits per UI (DDR) = 15Gbps
    rand int                    cfg_rx_clk_ratio           = 60;

         bit                    cfg_pkt_rx_enb             = 1'b1;         // linkctl bit 6
         bit                    cfg_pkt_tx_enb             = 1'b1;         // linkctl bit 7
    rand bit                    cfg_descram_enb            = 1'b1;         // linkctl bit 9
    rand bit                    cfg_scram_enb              = 1'b1;         // linkctl bit 10
    rand bit                    cfg_lane_auto_correct      = 1'b1;         // lictrl2 bit 16
    rand bit                    cfg_lane_reverse           = 1'b0;         // lictrl2 bit 17
    rand bit                    cfg_half_link_mode_tx      = 1'b0;         // lictrl2 bit 18
    rand bit                    cfg_half_link_mode_rx      = 1'b0;         // lictrl2 bit 19
         bit             [15:0] cfg_hsstxoe                = 16'hffff;     // lictrl3 bit 15:0 remove
    rand bit              [7:0] cfg_tx_rl_lim              = 8'h00;        // linkifsts2 bit 23:16
         bit                    cfg_send_null              = 1;
    
         bit             [15:0] cfg_hsstx_inv              = 16'h0000;     // emulates hss functionality to invert lanes
         bit             [15:0] cfg_hssrx_inv              = 16'h0000;
         bit                    cfg_tx_lane_reverse        = 1'b0;
    rand bit [15:0]             cfg_tx_lane_delay[16]      = '{16{4'h0}};  // 
         bit [15:0]             cfg_tx_lane_delay_divisor  = 100;          // delay granularity over 32UI

    // return token and retry pointer delay
         int                    cfg_rtc_min              = 15;          // idle latency in ns, 
    rand int unsigned           cfg_rtc_mean               = 30;          // rtc avg response time in ns, added to cfg_rsp_min
    rand int unsigned           cfg_rtc_std_dev            = 5;           // rtc standard deviation of response times in ns
    rand int unsigned           cfg_retry_delay            = 14;          // latency in turnaround for frp and rtc extraction in ns.
         int unsigned           cfg_irtry_delay_min        = 0;          //  min. latency delay for irtry packet in ns.
         int unsigned           cfg_irtry_delay_max        = 1000;       //  max. latency delay for irtry packet in ns. 

    realtime                    cfg_trsp1 = 1us;
    realtime                    cfg_trsp2 = 1us;
    realtime                    cfg_tpst  = 80ns;  // max tpst
//    realtime                    cfg_tsme  = 600ns; // max tsme
    realtime                    cfg_tsme  = 500ns; // 
    realtime                    cfg_trxd  = 0ns;
    realtime                    cfg_ttxd  = 200ns; // max
    realtime                    cfg_tsd   = 200ns; // max
    realtime                    cfg_tis   = 10ns;  // min
    realtime                    cfg_tss   = 500ns; // max
    realtime                    cfg_top   = 1ms;   // min. for shorter simulation to aviod seeing the warning, it can be reduced to a min. 1 us.
    realtime                    cfg_tsref = 1ms;   // max
    realtime                    cfg_tpsc  = 200ns; // max

`ifdef TWO_IN_ONE
    // ceusebio: hooks for parameters in Sysc
    int unsigned			    cfg_dram_tracing_en = 1;
	int unsigned			    cfg_refresh_en      = 0;
`endif
    
    // error injection is defined in 0.1% granularity
    rand int unsigned           cfg_rsp_dln, cfg_rsp_lng, cfg_rsp_crc, cfg_rsp_seq, cfg_rsp_dinv, cfg_rsp_errstat, cfg_rsp_err, cfg_rsp_poison;
    rand int unsigned           cfg_req_dln, cfg_req_lng, cfg_req_crc, cfg_req_seq;

    constraint con_link_cfg {
        cfg_tokens            inside{[9:1023]};

    // randomize systemC model's token count
`ifdef TWO_IN_ONE
        cfg_tokens_expected   inside{0, [9:1023]};
`endif
        cfg_max_tags          inside{[50:512]};
        cfg_rsp_open_loop     inside{0,1};
        cfg_retry_enb         dist{0 := 0, 1 := 1};
        cfg_retry_limit[2:0]  inside{[3:7]};
        cfg_retry_timeout     inside{[3:7]};
        cfg_init_retry_txcnt  inside{[4:12]};
        cfg_init_retry_rxcnt  inside{[16:32]};
        cfg_init_retry_rxcnt < (cfg_init_retry_txcnt*4);

        // serdes constraints
        cfg_tx_clk_ratio      inside{40,50,60};
        cfg_rx_clk_ratio      inside{40,50,60};
        cfg_descram_enb       inside{0,1};
        cfg_scram_enb         inside{0,1};
        cfg_lane_auto_correct inside{0,1};
        cfg_lane_reverse      inside{0,1};
        cfg_half_link_mode_tx inside{0,1};
        cfg_half_link_mode_rx inside{0,1};
        cfg_tx_rl_lim         inside{0,1};
        foreach (cfg_tx_lane_delay[i])
            cfg_tx_lane_delay[i] < cfg_tx_lane_delay_divisor;

        // delay constraints
        cfg_rtc_mean         <= 250;
        cfg_rtc_std_dev      <= cfg_rtc_mean;

        // rrp delay
        cfg_retry_delay        == 14;
        
        // error injection constraints
        cfg_rsp_dln          <= 5; // 0.5%
        cfg_rsp_lng          <= 5; // 0.5%
        cfg_rsp_crc          <= 5; // 0.5%
        cfg_rsp_seq          <= 5; // 0.5%
        cfg_rsp_dinv         <= 5; // 0.5%
        cfg_rsp_errstat      <= 5; // 0.5%
        cfg_rsp_err          <= 5; // 0.5%
        cfg_rsp_poison       <= 5; // 0.5%

        cfg_req_dln          <= 5; // 0.5%
        cfg_req_lng          <= 5; // 0.5%
        cfg_req_crc          <= 5; // 0.5%
        cfg_req_seq          <= 5; // 0.5%

        // when error injection is nonzero
        (
        cfg_rsp_dln          ||
        cfg_rsp_lng          ||
        cfg_rsp_crc          ||
        cfg_rsp_seq          ||
        cfg_rsp_dinv         ||
        cfg_rsp_errstat      ||
        cfg_rsp_err          ||
        cfg_rsp_poison       ||

        cfg_req_dln          ||
        cfg_req_lng          ||
        cfg_req_crc          ||
        cfg_req_seq
        ) -> {
            cfg_check_pkt      == 0; // disable packet checking
            cfg_retry_limit[3] == 1; // enable infinite retry
        }


    }

    function void display(int link_num=-1);
        var string str;
        var string tmp=""; 
        if (link_num >= 0) begin
            tmp = $sformatf("%t %m link %0d configuration\n",$realtime, link_num);
        end

        str = {tmp,
        $sformatf("  cfg_cid                    = %0d\n", cfg_cid                  ),
        $sformatf("  cfg_link_id                = %0d\n", cfg_link_id              ),
        $sformatf("  cfg_check_pkt              = %0d\n", cfg_check_pkt            ),
        $sformatf("  cfg_seq_tags               = %0d\n", cfg_seq_tags             ),
        $sformatf("  cfg_max_tags               = %0d\n", cfg_max_tags             ),
        $sformatf("  cfg_tokens                 = %0d\n", cfg_tokens               ),
        $sformatf("  cfg_tokens_expected        = %0d\n", cfg_tokens_expected      ),
        $sformatf("  cfg_rsp_open_loop          = %0d\n", cfg_rsp_open_loop        ),
        $sformatf("  cfg_host_mode              = %0d\n", cfg_host_mode            ),
        $sformatf("  cfg_tail_rtc_dsbl          = %0d\n", cfg_tail_rtc_dsbl        ),
        $sformatf("  cfg_retry_enb              = %0d\n", cfg_retry_enb            ),
        $sformatf("  cfg_retry_limit            = %0d\n", cfg_retry_limit          ),
        $sformatf("  cfg_retry_timeout          = %0d\n", cfg_retry_timeout        ),
        $sformatf("  cfg_init_retry_txcnt       = %0d\n", cfg_init_retry_txcnt     ),
        $sformatf("  cfg_init_retry_rxcnt       = %0d\n", cfg_init_retry_rxcnt     ),
        $sformatf("  sts_init_retry_state       = %0d\n", sts_init_retry_state     ),
        $sformatf("  cfg_tx_clk_ratio           = %0d\n", cfg_tx_clk_ratio         ),
        $sformatf("  cfg_rx_clk_ratio           = %0d\n", cfg_rx_clk_ratio         ),
        $sformatf("  cfg_pkt_rx_enb             = %0d\n", cfg_pkt_rx_enb           ),
        $sformatf("  cfg_pkt_tx_enb             = %0d\n", cfg_pkt_tx_enb           ),
        $sformatf("  cfg_descram_enb            = %0d\n", cfg_descram_enb          ),
        $sformatf("  cfg_scram_enb              = %0d\n", cfg_scram_enb            ),
        $sformatf("  cfg_lane_auto_correct      = %0d\n", cfg_lane_auto_correct    ),
        $sformatf("  cfg_lane_reverse           = %0d\n", cfg_lane_reverse         ),
        $sformatf("  cfg_half_link_mode_tx      = %0d\n", cfg_half_link_mode_tx    ),
        $sformatf("  cfg_half_link_mode_rx      = %0d\n", cfg_half_link_mode_rx    ),
        $sformatf("  cfg_hsstxoe                = %0d\n", cfg_hsstxoe              ),
        $sformatf("  cfg_tx_rl_lim              = %0d\n", cfg_tx_rl_lim            ),
        $sformatf("  cfg_send_null              = %0d\n", cfg_send_null            ),
        $sformatf("  cfg_hsstx_inv              = %0d\n", cfg_hsstx_inv            ),
        $sformatf("  cfg_hssrx_inv              = %0d\n", cfg_hssrx_inv            ),
        $sformatf("  cfg_tx_lane_reverse        = %0d\n", cfg_tx_lane_reverse      ),
        $sformatf("  cfg_tx_lane_delay          = %0p\n", cfg_tx_lane_delay        ),
        $sformatf("  cfg_tx_lane_delay_divisor  = %0d\n", cfg_tx_lane_delay_divisor),

        $sformatf("  cfg_rtc_min                =  %t\n", cfg_rtc_min              ),
        $sformatf("  cfg_rtc_mean               =  %t\n", cfg_rtc_mean             ),
        $sformatf("  cfg_rtc_std_dev            =  %t\n", cfg_rtc_std_dev          ),
        $sformatf("  cfg_retry_delay            =  %t\n", cfg_retry_delay          ),

        $sformatf("  cfg_trsp1                  =  %t\n", cfg_trsp1                ),
        $sformatf("  cfg_trsp2                  =  %t\n", cfg_trsp2                ),
        $sformatf("  cfg_tpst                   =  %t\n", cfg_tpst                 ),
        $sformatf("  cfg_tsme                   =  %t\n", cfg_tsme                 ),
        $sformatf("  cfg_trxd                   =  %t\n", cfg_trxd                 ),
        $sformatf("  cfg_ttxd                   =  %t\n", cfg_ttxd                 ),
        $sformatf("  cfg_tsd                    =  %t\n", cfg_tsd                  ),
        $sformatf("  cfg_tis                    =  %t\n", cfg_tis                  ),
        $sformatf("  cfg_tss                    =  %t\n", cfg_tss                  ),
        $sformatf("  cfg_top                    =  %t\n", cfg_top                  ),
        $sformatf("  cfg_tsref                  =  %t\n", cfg_tsref                ),
        $sformatf("  cfg_tpsc                   =  %t\n", cfg_tpsc                 ),

    `ifdef TWO_IN_ONE
        $sformatf("  cfg_dram_tracing_en        = %0d\n", cfg_dram_tracing_en	   ),
        $sformatf("  cfg_refresh_en             = %0d\n", cfg_refresh_en		   ),
    `endif

        $sformatf("  cfg_rsp_dln                = %1.1f%%\n", cfg_rsp_dln     /10.0), // format as 1/10th percent
        $sformatf("  cfg_rsp_lng                = %1.1f%%\n", cfg_rsp_lng     /10.0), // format as 1/10th percent
        $sformatf("  cfg_rsp_crc                = %1.1f%%\n", cfg_rsp_crc     /10.0), // format as 1/10th percent
        $sformatf("  cfg_rsp_seq                = %1.1f%%\n", cfg_rsp_seq     /10.0), // format as 1/10th percent
        $sformatf("  cfg_rsp_dinv               = %1.1f%%\n", cfg_rsp_dinv    /10.0), // format as 1/10th percent
        $sformatf("  cfg_rsp_errstat            = %1.1f%%\n", cfg_rsp_errstat /10.0), // format as 1/10th percent
        $sformatf("  cfg_rsp_err                = %1.1f%%\n", cfg_rsp_err     /10.0), // format as 1/10th percent
        $sformatf("  cfg_rsp_poison             = %1.1f%%\n", cfg_rsp_poison  /10.0), // format as 1/10th percent
        $sformatf("  cfg_req_crc                = %1.1f%%\n", cfg_req_crc     /10.0), // format as 1/10th percent
        $sformatf("  cfg_req_dln                = %1.1f%%\n", cfg_req_dln     /10.0), // format as 1/10th percent
        $sformatf("  cfg_req_lng                = %1.1f%%\n", cfg_req_lng     /10.0), // format as 1/10th percent
        $sformatf("  cfg_req_seq                = %1.1f%%\n", cfg_req_seq     /10.0)  // format as 1/10th percent
        };

        $display("%s", str);        
    endfunction : display        
        
endclass : cls_link_cfg
