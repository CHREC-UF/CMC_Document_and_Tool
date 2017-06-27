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

// HMC Retry
// -implements retry state machine
// -Enters Error Abort Mode on CRC, LEN/DLN mismatch or SEQ error
// -stores outgoing packets into retry buffer
// -extracts FRP and RRP from incoming packets
// -generates FRP and embeds FRP and RRP into outgoing packets
// -generates PRET packets when idle
// -filters out NULL and PRET packets from downstream devices

`timescale 1ns/1ps

interface hmc_retry;
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    // modports
    mailbox#(cls_pkt)       mb_tx_pkt_in;  // no flow control
    mailbox#(cls_pkt)       mb_tx_pkt_out; // with flow control
    mailbox#(cls_pkt)       mb_tx_pkt_err;  // ADG:: for error packet 
    mailbox#(cls_pkt)       mb_rx_pkt_in;  // with flow control
    mailbox#(cls_pkt)       mb_rx_pkt_out; // no flow control

`ifdef TWO_IN_ONE
    mailbox#(cls_pkt)       mb_rx_bad_pkt_out; // report packets that have errors to systemC wrapper
`endif

    int unsigned num_entries_used;
    // internal signals
    bit             [ 2: 0] retry_attempts;
    bit             [ 2: 0] tx_retry_attempts;
    bit             [10: 0] retry_timeout_setting;
    bit             [10: 0] retry_timer;
    bit                     retry_timer_expired;
    bit                     retry_timeout;
    bit                     tx_retry_timeout;
    bit                     retry_limit_reached; //ADG::
    bit                     send_err_rsp_rtry_to;
    bit                     send_err_rsp_rtry_cmplt;
    int unsigned            start_retry_mode;
    bit             [ 7: 0] error_abort;
    bit             [ 7: 0] start_retry_rxcnt;
    bit             [ 7: 0] start_retry_txcnt;
    bit             [ 7: 0] error_abort_rxcnt;
    bit             [ 7: 0] error_abort_txcnt;
    bit               [2:0] tx_seq;             // sequence number to send on TX
    bit               [2:0] rx_seq;             // sequence number to expect on RX
    bit               [7:0] frp;                // tail.frp extracted from the recieved packet
    bit               [7:0] rrp;                // tail.rrp extracted from the recieved packet
    bit               [7:0] tx_frp;             // last frp sent on TX
    bit               [7:0] tx_rrp;             // last rrp sent on TX
    bit               [7:0] tx_rp;              // retry pointer used during LinkRetry_FLIT state
    bit               [7:0] rx_rp;              // starting retry pointer during ErrorAbort mode
    bit               [7:0] delayed_rrp;        // delayed version to embed in tx direction
    bit               [7:0] abort_rrp;          // rrp to embed for err_abort mode
    bit               [7:0] next_pkt_lng;       // after we get a packet from the tx input mbox, save its length
    bit                     reset_done;

    bit               [7:0] tx_rp_prev;
    bit                     send_pret_inhibit = 0; // prevent explicit PRET from being sent?
    //cls_pkt                 tx_pkts[256];
    cls_pkt                tx_pkts[];
    int unsigned             retry_buf_size;
    bit                  irtry_delay = 0;       //  delay irtry packet. 
    int unsigned           irtry_delay_time = 0;  //  latency delay time for irtry packet in ns. 

    cls_pkt                tx_pkt_q[$:0]; // to get from mailbox
    bit                     check_timer;
    bit                     err_abort_clr;
    int debug_fd;    
    // Group: Configuration
    cls_link_cfg            link_cfg;   
    bit                     cfg_info_msg  = 0;
    bit                     cfg_stall_info_msg = 0; // show when PRET stall conditions happen? 
`ifdef HMC_PRET_THROTTLE
    realtime                cfg_send_pret_timeout = `HMC_PRET_THROTTLE; // larger values make sending explicit PRET less likely
`else
    realtime                cfg_send_pret_timeout = 6.4ns; // larger values make sending explicit PRET less likely
`endif

    // TODO: sts_err_abort_mode to config?
    bit                     sts_err_abort_mode;           // LINKRETRY 
    int unsigned            num_err_abort_mode;
    
    // TODO: below var not used
    bit             [ 3: 0] sts_init_retry_state;         // LINKRETRY

    bit                  retry_cleared_tx_pkt_out; 
`ifdef HMC_COV //ADG:: for not doing verification coverage.

    covergroup hmc_retry_cg() @(start_retry_mode, error_abort[0], error_abort_rxcnt, error_abort_txcnt, retry_attempts, retry_timer_expired, send_err_rsp_rtry_to, send_err_rsp_rtry_cmplt);
        
        startretry_flag: coverpoint start_retry_mode {
            bins no_retry = {0};
            bins retry = {[1:$]}; // if >= 1 in retry
        } 

        error_abort: coverpoint sts_err_abort_mode {
            bins _0 = {0};
            bins _1 = {1};
        }
        
        // not in testplan but could be useful
        errorabort_flag_rx: coverpoint error_abort_rxcnt;
        errorabort_flag_tx: coverpoint error_abort_txcnt;

        retry_attempts: coverpoint retry_attempts;
                
        retry_timer_expired: coverpoint retry_timer_expired {
            bins _0 = {0};
            bins _1 = {1};
        }

        // TODO could do on the monitor which be better
        retry_failed_errstat: coverpoint send_err_rsp_rtry_to {
            bins _0 = {0};
            bins _1 = {1};
        }

        // TODO could do on the monitor which be better        
        retry_success_errstat: coverpoint send_err_rsp_rtry_cmplt {
            bins _0 = {0};
            bins _1 = {1};
        }
        
    endgroup

    hmc_retry_cg hmc_retry_cov = new();
`endif    //ADG:: ifdef HMC_COV
        
    initial begin
        `ifdef ADG_DEBUG
               cfg_info_msg = 1;
        `endif
        wait (
              link_cfg           != null &&           
              mb_tx_pkt_in       != null &&
              mb_tx_pkt_out      != null &&
              mb_rx_pkt_in       != null &&
              mb_rx_pkt_out      != null &&
              reset_done                 
        );
    `ifdef DELAY_IRTRY
          $display("%t %m: DELAY_IRTRY difined. irtry_delay_time = %0d; ",$realtime,link_cfg.cfg_irtry_delay_max);
          irtry_delay = 1; 
          irtry_delay_time = link_cfg.cfg_irtry_delay_max;
    `endif

        fork
            run_tx_pkt_in();
            run_tx();
            run_rx();
        join_none
	#0;
    end

    // decode the configuration value
    always @(link_cfg) begin
        if (link_cfg != null) begin
            case(link_cfg.cfg_retry_timeout)
                3'h0: retry_timeout_setting = 10'h060;
                3'h1: retry_timeout_setting = 10'h080;
                3'h2: retry_timeout_setting = 10'h0C0;
                3'h3: retry_timeout_setting = 10'h100;
                3'h4: retry_timeout_setting = 10'h180;
                3'h5: retry_timeout_setting = 10'h200;
                3'h6: retry_timeout_setting = 10'h300;
                3'h7: retry_timeout_setting = 10'h3FF;
            endcase
            
            // PR: TODO: pass through link config object so customers can
            // override this? 
            if( link_cfg.cfg_tx_clk_ratio <= 40 ) begin
                retry_buf_size = 160;                    
               `ifdef RTL_V21
                      retry_buf_size = 192;                    
               `endif
            end
            else begin
                  retry_buf_size = 256;
            end
            if (cfg_info_msg)
               $display("%t %m: tx_clk_ratio = %0d; rx_clk_ratio = %0d; retry_buf_size = %0d;",$realtime,link_cfg.cfg_tx_clk_ratio,link_cfg.cfg_rx_clk_ratio,retry_buf_size);

            tx_pkts = new[retry_buf_size] ;
         end
    end

    function automatic void run_reset();
        if (cfg_info_msg)
            $display("%t %m: Warm Reset", $realtime);

        assert_empty_buffers: assert (!tx_pkt_q.size()) else begin
            $warning("%1d in flight transactions haven been lost due to Warm Reset", tx_pkt_q.size());
        end
        assert_all_pointers_returned: assert (tx_frp == rrp) else begin
            $warning("All retry pointers must be returned prior to Warm Reset");
        end

        reset_done                      = 0;
        retry_attempts                  = 0;
        tx_retry_attempts               = 0;
        retry_timer                     = 0;
        retry_timer_expired             = 0;
        retry_timeout                   = 0;
        tx_retry_timeout                = 0;
        send_err_rsp_rtry_to            = 0;
        send_err_rsp_rtry_cmplt         = 0;
        start_retry_mode                = 0;
        error_abort                     = 0;
        start_retry_rxcnt               = 0;
        start_retry_txcnt               = 0;
        error_abort_rxcnt               = 0;
        error_abort_txcnt               = 0;
        tx_seq                          = 1;
        rx_seq                          = 1;
        frp                             = 0;
        rrp                             = 0;
        tx_frp                          = 0;
        tx_rrp                          = 0;
        tx_rp                           = 0;
        tx_rp_prev                      = 0;
        delayed_rrp                     = 0;
        tx_pkt_q.delete();
        check_timer                     = 0;
        err_abort_clr                   = 0;
        sts_err_abort_mode              = 0;
        num_err_abort_mode              = 0;
        reset_done                      = 1;
    endfunction : run_reset

    // Function: run_tx_pkt_in
    //
    // get from mb_pkt_in, put into tx_pkt_q
    task automatic run_tx_pkt_in();
        var       cls_pkt pkt;
        var typ_req_header header;

        forever begin
            wait(!tx_pkt_q.size());
            mb_tx_pkt_in.get(pkt);
            retry_cleared_tx_pkt_out = ~retry_cleared_tx_pkt_out;
            #0;

            header = pkt.get_header();
            next_pkt_lng = header.lng;
                        
            tx_pkt_q.push_back(pkt);
        end
    endtask : run_tx_pkt_in

    task automatic set_tail(cls_pkt pkt);
        var    typ_req_tail tail;      
        tail     = pkt.get_tail();
        tail.rrp = delayed_rrp; // embed the frp into the rrp field
        tx_rrp   = delayed_rrp; // store the last rrp
        pkt.set_tail(tail);
    endtask : set_tail
    
    // LinkRetry "state machine"
    task automatic link_retry();
        var    cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var    cls_rsp_pkt rsp_pkt;
        var    typ_req_header header;
        var    typ_req_tail tail;

        // LinkRetry_Init State
        // Transmit 4 * link_cfg.cfg_init_retry_txcnt IRTRY packets (per spec Table 34)
        if (cfg_info_msg) begin
           $display("%t %m ADG:: starts %0d IRTRY packets ", $realtime, link_cfg.cfg_init_retry_txcnt*4);
        end
        for(start_retry_txcnt=0; start_retry_txcnt<(link_cfg.cfg_init_retry_txcnt*4);start_retry_txcnt++) begin
            header     = 0;
            header.cmd = IRTRY;
            header.lng = 1;
            header.dln = 1;
            req_pkt = new();
            req_pkt.header = header;
            req_pkt.tail.frp[0] = 0; // clear the StartRetry flag
            req_pkt.tail.frp[1] = 1; // set the ClearErrorAbort flag during LinkRetry_Init state
            pkt = req_pkt;
            set_tail(pkt);
            if(irtry_delay == 1 && start_retry_txcnt == 2 && (^link_cfg.cfg_host_mode)) begin
                #( irtry_delay_time );
                irtry_delay = 0;
            end
            put_tx_pkt(pkt, "LinkRetry_Init", $sformatf("num_entries=%0d, next_lng=%0d, rrp=%0d, tx_frp=%0d", num_entries_used, next_pkt_lng, rrp, tx_frp));
        end // for (int i=0;i<link_cfg.cfg_init_retry_txcnt;i++)


        // detect multiple retry requests with same retry pointer
        tx_rp = rrp; // capture the starting retry pointer from the last rrp recieved
        if (tx_rp == tx_frp || tx_rp != tx_rp_prev) begin // retry buffer is empty or new retry pointer
            tx_retry_attempts = 0;
            tx_retry_timeout = 0;
        end else if (tx_retry_attempts < link_cfg.cfg_retry_limit) begin
            tx_retry_attempts += 1;
        end else begin
            if (!tx_retry_timeout) begin
                $display("%t %m RETRY TX: Link Failure after %d Retry attempts.\n\tCheck for malformed packet: %s", $realtime, tx_retry_attempts, tx_pkts[tx_rp].convert2string());
                retry_limit_reached = 1;
                send_error();
                $finish;
                // todo: send error response broadcast to all links?
                //tx_retry_timeout     = 1;
            end     
        end
        tx_rp_prev = tx_rp;

        // LinkRetry_FLIT State
        // per 10.2.7.2.1, HMC will complete LinkRetry_FLIT state before initiating stream of IRTRY
        while(tx_rp != tx_frp) begin
            if (tx_rp == rrp)
                $display("%t %m LinkRetry_FLIT TX: Entering LinkRetry_FLIT state. Sending Retry packets starting from RRP: %0h; tx_rp=%0h; tx_rp=%0h;", $realtime, rrp, tx_rp,tx_frp);
            pkt = tx_pkts[tx_rp];
            if (cfg_info_msg)
               $display("%t %m LinkRetry_FLIT TX: packet: %s", $realtime, tx_pkts[tx_rp].convert2string());            
            header = pkt.get_header();
            set_tail(pkt);
            put_tx_pkt(pkt, "LinkRetry_FLIT", $sformatf("num_entries=%0d, next_lng=%0d, rrp=%0d, tx_frp=%0d", num_entries_used, next_pkt_lng, rrp, tx_frp));
            // update pointer and handle wraparound case
            tx_rp = (tx_rp + header.lng)%retry_buf_size;
            if (cfg_info_msg)
               $display("%t %m  LinkRetry_FLIT TX: inside link retry loop. after: tx_rp = %0h ; tx_frp = %0h", $realtime,tx_rp,tx_frp);            
        end

        if (cfg_info_msg) begin
           $display("%t %m  LinkRetry_FLIT TX: Finished link retry. send_err_rsp_rtry_to = %0d ; send_err_rsp_rtry_cmplt = %0d ; retry_limit_reached = %0d",$realtime,send_err_rsp_rtry_to,send_err_rsp_rtry_cmplt,retry_limit_reached);            
        end
        if (link_cfg.cfg_retry_enb && (^link_cfg.cfg_host_mode) && (send_err_rsp_rtry_to || send_err_rsp_rtry_cmplt || retry_limit_reached)) begin
           if (cfg_info_msg)
              $display("%t %m  LinkRetry_FLIT TX: Finished link retry start send_error", $realtime);            
           send_error();
        end

        // LinkRetry Exit
        start_retry_mode--;
    endtask : link_retry
                
        
    // LinkRetry "state machine"
    task automatic start_retry();
        var    cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var    cls_rsp_pkt rsp_pkt;
        var    typ_req_header header;
        var    typ_req_tail tail;
        
        // StartRetry_Init State
        err_abort_clr = 0;

        header      = 0;
        header.cmd  = IRTRY;
        header.lng  = 1;
        header.dln  = 1;
        tail        = 0;
        tail.frp[0] = 1; // set the StartRetry flag during StartRetry_Init state
        tail.frp[1] = 0; // clear the ClearErrorAbort flag during LinkRetry_Init state
        tail.rrp    = rx_rp;
        tx_rrp      = rx_rp; // store the last rrp

        if (cfg_info_msg) begin
        $display("%t %m TX: Entering StartRetry_Init state. Requesting Retry packets starting from RRP: %h; rx_rp: %h; ", $realtime, frp,rx_rp);
        end

        // Transmit 4 * link_cfg.cfg_init_retry_txcnt IRTRY packets (per spec Table 34)
        if (cfg_info_msg) begin
           $display("%t %m ADG:: starts %0d IRTRY packets", $realtime, link_cfg.cfg_init_retry_txcnt*4);
        end
        for(error_abort_txcnt=0; error_abort_txcnt<(link_cfg.cfg_init_retry_txcnt*4); error_abort_txcnt++) begin
            req_pkt        = new();
            req_pkt.header = header;
            req_pkt.tail   = tail;
            put_tx_pkt(req_pkt, "StartRetry_Init", $sformatf("num_entries=%0d, next_lng=%0d, rrp=%0d, tx_frp=%0d", num_entries_used, next_pkt_lng, rrp, tx_frp));
        end // for (int i=0;i<link_cfg.cfg_init_retry_txcnt;i++)

        // StarRetry Exit
        error_abort--;
        fork
            retry_counter();
        join_none
        #0; // start the forked task

    endtask : start_retry

    // Send Error pkt upon retry
    task automatic send_error();
        var    cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var    cls_rsp_pkt rsp_pkt;
        var    typ_req_header header;
        var    typ_req_tail tail;
        var string str_lnk_id;

        pkt = tx_pkts[tx_rp];
        rsp_pkt = new();
        rsp_pkt.header.cmd = ERROR;
        rsp_pkt.header.lng = 1;
        rsp_pkt.header.dln = 1;
        rsp_pkt.header.tag = link_cfg.cfg_cid;
        if (send_err_rsp_rtry_to) begin
            rsp_pkt.tail.errstat = typ_err_stat'(ERR_RETRY_LINK0 | (link_cfg.cfg_link_id+4'h1));
            send_err_rsp_rtry_to = 0;
        end 
        else if(retry_limit_reached) begin
               rsp_pkt.tail.errstat = typ_err_stat'(ERR_RETRY_LINK0 | link_cfg.cfg_link_id);
               retry_limit_reached = 0;             
        end
        else if (send_err_rsp_rtry_cmplt) begin
               rsp_pkt.tail.errstat = typ_err_stat'(ERR_LINK0 | link_cfg.cfg_link_id);
               send_err_rsp_rtry_cmplt = 0;
        end

        pkt = rsp_pkt;
        tx_pkts[tx_frp] = pkt; // save packet into retry buffer
        // TG: even though error packet only has length of 1, still need to be sure tx_frp will not be to out of boundary
        tx_frp = (tx_frp + 1) % retry_buf_size;
        tail     = pkt.get_tail();
        tail.frp = tx_frp; // generate the frp
        tail.seq = tx_seq; // embed the sequence number
        pkt.set_tail(tail);
        set_tail(pkt);
        if (cfg_info_msg)
            $display("%t %m  send_error TX: %s", $realtime, pkt.convert2string());
        put_tx_pkt(pkt, "send_error", $sformatf("num_entries=%0d, next_lng=%0d, rrp=%0d, tx_frp=%0d", num_entries_used, next_pkt_lng, rrp, tx_frp));
        //mb_tx_pkt_err.put(pkt);
        tx_seq++;

    endtask : send_error

    task automatic send_pkt();

        var    cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var    cls_rsp_pkt rsp_pkt;
        var    typ_req_header header;
        var    typ_req_tail tail;
        var    int previous_tx_frp; // for debug only

        pkt = tx_pkt_q[0];

//        if ($cast(rsp_pkt, pkt)) 
//            $display("%t %m got pkt %s with lat=%0d", $realtime, rsp_pkt.convert2string_short(), rsp_pkt.lat);
//
        header = pkt.get_header();
        if (header.cmd && header.cmd != PRET && header.cmd != IRTRY) begin
            previous_tx_frp = tx_frp; // save for debug below

            tx_pkts[tx_frp] = pkt; // save packet into retry buffer
            // update retry pointer and handle wraparound case
            tx_frp = (tx_frp + header.lng) % retry_buf_size;

            if (cfg_info_msg && tx_frp < previous_tx_frp ) begin
                $display("%t %m tx_frp wraparound condition: before tx_frp=%0d, added lng=%0d; now tx_frp=%0d", $realtime, previous_tx_frp, header.lng, tx_frp);
            end
            tail     = pkt.get_tail();
            tail.frp = tx_frp; // generate the frp
            tail.seq = tx_seq; // embed the sequence number
            
            pkt.set_tail(tail);
            tx_seq++;
        end // if (header.cmd && header.cmd != PRET && header.cmd != IRTRY)
        
        set_tail(pkt);
        if (cfg_info_msg)
            $display("%t %m send_pkt TX: %s", $realtime, pkt.convert2string());
        put_tx_pkt(pkt, "send_pkt", $sformatf("num_entries=%0d, next_lng=%0d, header.lng=%0d, rrp=%0d, tx_frp=%0d", num_entries_used, next_pkt_lng, header.lng, rrp, tx_frp));
        void'(tx_pkt_q.pop_front());

    endtask : send_pkt
    
    task automatic send_pret();

        var    cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var    cls_rsp_pkt rsp_pkt;
        var    typ_req_header header;
        var    typ_req_tail tail;

        req_pkt = new();
        req_pkt.header.cmd = PRET;
        req_pkt.header.lng = 1;
        req_pkt.header.dln = 1;

        pkt = req_pkt;
        set_tail(pkt);
        put_tx_pkt(pkt, "send_pret", $sformatf("num_entries=%0d, next_lng=%0d, rrp=%0d, tx_frp=%0d", num_entries_used, next_pkt_lng, rrp, tx_frp));

    endtask : send_pret
    

    // Function: put_tx_pkt
    //
    // Prints a packet to the screen if cfg_info_msg == 1
    // then puts it into mb_tx_pkt_out
    task automatic put_tx_pkt(cls_pkt pkt, string which, string extra="");
        var    typ_req_header header;

        if (cfg_info_msg) begin
            header = pkt.get_header();
            if (header) begin
                $display("%t %m : put packet TX %s", $realtime, pkt.convert2string());
            end
        end
        pkt.pkt_trace(debug_fd, link_cfg.cfg_link_id, which, extra);
        mb_tx_pkt_out.put(pkt);
    endtask : put_tx_pkt
          
    task automatic tx_rrp_watchdog();
        #(cfg_send_pret_timeout);
        send_pret_inhibit =  0;
    endtask

    always @(tx_rrp) begin
        disable tx_rrp_watchdog;
        send_pret_inhibit = 1;
        fork 
            tx_rrp_watchdog;
        join_none
    end

    // Task: run_tx
    //
    // get from mb_pkt_in, put into tx_pkt_q
    // I.E Link Master
    task automatic run_tx();
        forever begin

            // rx will increment start_retry_mode each time LinkRetry Sequence needs to be initiated
            // per 10.2.7.2.1, HMC will complete LinkRetry_FLIT state before initiating stream of IRTRY            
            if (cfg_stall_info_msg && tx_pkt_q.size() > 0 && (retry_buf_size - num_entries_used) <= next_pkt_lng) begin
                $display("%t %m INFO: retry buffer pointer stall condition: tx_frp=%0d, rrp=%0d, next_lng=%0d",$realtime, tx_frp, rrp, next_pkt_lng);
/*
            end else if (cfg_info_msg && tx_pkt_q.size()) begin
                $display("%t %m packet %s waiting to go from retry block", $realtime, tx_pkt_q[0].convert2string());
*/
            end
            // PR: NOTE: make sure the if conditions below match the
            // conditions in this wait statement *exactly* or else we may mess
            // up the buffer
            wait ( 
                (tx_pkt_q.size() && ((retry_buf_size - num_entries_used) > next_pkt_lng)) // we can accept next packet from tx_pkt_q
                || (link_cfg.cfg_retry_enb && start_retry_mode>0)         // we need to start LinkRetry_FLIT
                || (link_cfg.cfg_retry_enb && error_abort)                // we need to start StartRetry
                || (tx_rrp != delayed_rrp && !send_pret_inhibit)            // we can send a PRET
                ) 

            begin

                if (start_retry_mode == 0)
                    start_retry_txcnt = 0;
                
                // LinkRetry
                if (link_cfg.cfg_retry_enb && (start_retry_mode > 0)) begin
                   if (cfg_info_msg) begin
                      $display("%t %m ADG:: link_retry : cfg_retry_enb=%0d;start_retry_mode=%0d;", $realtime, link_cfg.cfg_retry_enb,start_retry_mode);
                   end
                   link_retry();
                end                  
                // StartRetry
                else if (link_cfg.cfg_retry_enb && error_abort) begin
                   if (cfg_info_msg) begin
                      $display("%t %m ADG:: start_retry : cfg_retry_enb=%0d;start_retry_mode=%0d;", $realtime, link_cfg.cfg_retry_enb,start_retry_mode);
                   end
                    start_retry();
                end  
               else if (tx_pkt_q.size() && ((retry_buf_size - num_entries_used) > next_pkt_lng)) begin
                   if (cfg_info_msg) begin
                       $display("%t %m ADG:: Send_pkt on : link %0d;", $realtime, link_cfg.cfg_link_id);
                   end
                    send_pkt();
                end
                else if (tx_rrp != delayed_rrp && !send_pret_inhibit) begin
                       if (cfg_info_msg) begin
                           $display("%t %m ADG:: Send_pret : on link %0d;", $realtime, link_cfg.cfg_link_id);
                       end
                    send_pret();
                end
                else begin
                    assert_unreachable: assert (0) else
                        $error("%t %m : unreachable branch",$realtime);
                end
                    
            end // wait ((link_cfg.cfg_retry_enb && (start_retry_mode>0)) ||...

        end
    endtask

    // Function: run_rx
    //
    // get from mb_rx_pkt_in, put to mb_rx_pkt_out
    task automatic run_rx();
        var       cls_pkt pkt;
        var   cls_req_pkt req_pkt;
        var   cls_rsp_pkt rsp_pkt;
        var  typ_req_tail tail;
        var typ_req_header header;
        var   logic [31:0] crc;

        forever begin
            mb_rx_pkt_in.get(pkt);
            header = pkt.get_header();
            tail   = pkt.get_tail();
            crc    = pkt.gen_crc();

            // if valid packet
            if ((crc == tail.crc || crc == ~tail.crc) && header.lng == header.dln
                && (!header.cmd || header.cmd == PRET || header.cmd == IRTRY || tail.seq == rx_seq) // sequence number must match except for NULL, PRET, IRTRY
                // Sometimes the error injector "fixes" a dln and CRC so
                // packet looks OK; in this case we have to sanity check the
                // command with the lng

					 // CMD match LNG check is now handled in hmc_rsp_gen and hmc_mem
                // && (header.cmd == 0 || pkt.check_cmd_lng())
            ) begin
                // increment retry counters
                if (header.cmd == IRTRY) begin
                    //if (start_retry_rxcnt < link_cfg.cfg_init_retry_rxcnt)
                        start_retry_rxcnt += tail.frp[0]; // StartRetry flag
                    //if (error_abort_rxcnt < link_cfg.cfg_init_retry_rxcnt)
                        error_abort_rxcnt += tail.frp[1]; // ClearErrorAbort flag
                    if (cfg_info_msg)
                        $display("%t %m IRTRY RX: start_retry_rxcnt = %0d; error_abort_rxcnt = %0d;", $realtime,start_retry_rxcnt,error_abort_rxcnt);
                    if (!tail.frp[0]) begin 
                        assert_start_retry_stream1: assert (!start_retry_rxcnt || (start_retry_rxcnt >= link_cfg.cfg_init_retry_rxcnt)) else
                            $warning("The stream of %1d IRTRY packets was less than the number required to Enter StartRetry Mode. Expected %1d contiguous IRTRY packets.", start_retry_rxcnt, link_cfg.cfg_init_retry_rxcnt);
                        start_retry_rxcnt = 0;
                    end
                    if (!tail.frp[1]) begin 
                        assert_clear_error_abort_stream1: assert (!error_abort_rxcnt || (error_abort_rxcnt >= link_cfg.cfg_init_retry_rxcnt)) else
                            $warning("The stream of %1d IRTRY packets was less than the number required to Clear Err Abort Mode. Expected %1d contiguous IRTRY packets.", error_abort_rxcnt, link_cfg.cfg_init_retry_rxcnt);
                        error_abort_rxcnt = 0;
                    end
                end 
                else begin
                    assert_start_retry_stream2: assert (!start_retry_rxcnt || (start_retry_rxcnt >= link_cfg.cfg_init_retry_rxcnt)) else
                        $warning("The stream of %1d IRTRY packets was less than the number required to Enter StartRetry Mode. Expected %1d contiguous IRTRY packets.", start_retry_rxcnt, link_cfg.cfg_init_retry_rxcnt);
                    assert_clear_error_abort_stream2: assert (!error_abort_rxcnt || (error_abort_rxcnt >= link_cfg.cfg_init_retry_rxcnt)) else
                        $warning("The stream of %1d IRTRY packets was less than the number required to Clear Err Abort Mode. Expected %1d contiguous IRTRY packets.", error_abort_rxcnt, link_cfg.cfg_init_retry_rxcnt);
                    start_retry_rxcnt = 0;
                    error_abort_rxcnt = 0;
                end

                // clear error abort mode
                if (sts_err_abort_mode != 0 && error_abort_rxcnt == link_cfg.cfg_init_retry_rxcnt) begin
                    $display("%t %m RETRY RX: Clearing Abort Mode. Detected %1d IRTRY packets with ClearErrorAbort flag == 1", $realtime, link_cfg.cfg_init_retry_rxcnt);
                    sts_err_abort_mode = 0;
                    err_abort_clr = 1;
                    
                    send_err_rsp_rtry_cmplt = 1; // todo: needs more definition, error response broadcast to all links?
                    //rrp = tail.rrp; // extract the rrp
                    rrp <= #( link_cfg.cfg_retry_delay ) tail.rrp; // ADG:: extract the rrp with delay
                end

                // enter start retry mode
                if (start_retry_rxcnt == link_cfg.cfg_init_retry_rxcnt) begin
                    if (start_retry_mode == 0) begin
                        $display("%t %m RETRY RX: Entering StartRetry Mode. Detected %1d IRTRY packets with StartRetry flag == 1", $realtime, link_cfg.cfg_init_retry_rxcnt);
                        fork
                            begin        
                                #( link_cfg.cfg_retry_delay ); 
                                start_retry_mode++;
                            end
                        join_none
                        #0; // start the fork
                    end
                    rrp <= #( link_cfg.cfg_retry_delay ) tail.rrp; // ADG:: extract the rrp with delay
                end

                if (header.cmd && (sts_err_abort_mode == 0)) begin
                    
                    if (header.cmd != PRET && header.cmd != IRTRY) begin // these commands do not have a valid FRP field

                        frp = tail.frp; // extract the frp
                        fork
                            begin        
                                //#( link_cfg.cfg_retry_delay ); 
                                delayed_rrp <= #( link_cfg.cfg_retry_delay ) frp; //ADG::  extract the rrp with delay     
                            end
                        join_none
                        #0; // start the forked task
                            
                        rx_seq++; // update the expected sequence number
                        
                    end
                    if(crc == ~tail.crc) begin
                        assert (pkt.poison) else
                          $error ("expected pkt.poison == 1 from hmc_err_inj, Actual: %s", pkt.convert2string());
                        start_retry_rxcnt = 0;
                        error_abort_rxcnt = 0;                
`ifdef TWO_IN_ONE
                        // ceusebio: sysc should drop this packet, mark it as bad
                        if (mb_rx_bad_pkt_out) begin
                            assert(link_cfg.cfg_host_mode == 1) else $fatal("%t %m: Shouldn't have 2in1 mode enabled for host components", $realtime);
                            if (header.cmd != PRET && header.cmd != IRTRY) begin
                                assert(mb_rx_bad_pkt_out.try_put(pkt) == 1) else $fatal(0, "%t %m Failed to put bad pkt", $realtime);
                            end
                        end
`endif
                    end
                    
                    rrp <= #( link_cfg.cfg_retry_delay ) tail.rrp; //ADG:: extract the rrp with delay 
                end
            end else if (sts_err_abort_mode == 0) begin // if (crc == tail.crc && header.lng == header.dln...
`ifdef TWO_IN_ONE
                if (mb_rx_bad_pkt_out) begin
                    assert(link_cfg.cfg_host_mode == 1) else $fatal("%t %m: Shouldn't have 2in1 mode enabled for host components", $realtime);
                    if (header.cmd != PRET && header.cmd != IRTRY) begin
                        assert(mb_rx_bad_pkt_out.try_put(pkt) == 1) else $fatal(0, "%t %m Failed to put bad pkt", $realtime);
                    end
                end
`endif
                $display("%t %m RETRY RX: Invalid packet detected.  Entering Err Abort Mode: %s", $realtime, pkt.convert2string());
                $display("\tExpected dln = %0x, Actual dln = %0x", header.lng, header.dln);
                $display("\tExpected seq = %0x, Actual seq = %0x", (!header.cmd || header.cmd == PRET || header.cmd == IRTRY)? 0 : rx_seq, tail.seq);
                $display("\tExpected crc = %0x, Actual crc = %0x", crc, tail.crc);
                
                sts_err_abort_mode = 1;
                num_err_abort_mode++;
                
                fork
                    begin
                        #( link_cfg.cfg_retry_delay ); 
                        error_abort++;
                    end
                join_none
                #0; // start the fork
                        
                error_abort_rxcnt  = 0;
                start_retry_rxcnt  = 0;

                rx_rp = frp; // capture last valid frp
                // not necessary: poison the incoming packet tail.crc = ~pkt.gen_crc();
                // todo: if invalid command, generate WR_RS packet with tail.errstat == 'h30
                // todo: if cmd/len mismatch, generate RD_RS packet with tail.errstat == 'h31
            end // else invalid packet in error abort mode
            else begin // in error abort mode but detected bad packet
                if (cfg_info_msg)
                    $display("%t %m RETRY RX: in Err Abort Mode but detected bad packet: %s", $realtime, pkt.convert2string());
                start_retry_rxcnt = 0;
                error_abort_rxcnt = 0;
            end // else: !if (sts_err_abort_mode==0)
            

            if (sts_err_abort_mode != 0) begin
                if (cfg_info_msg && header)
                    $display("%t %m RETRY RX: Discarding packet in Err Abort Mode: %s", $realtime, pkt.convert2string());
            end else begin
                if (cfg_info_msg && header)
                    $display("%t %m RETRY RX: %s", $realtime, pkt.convert2string());

                if (pkt.poison || ((header.cmd) && header.cmd != PRET && header.cmd != IRTRY)) begin
                    mb_rx_pkt_out.put(pkt);
                end
            end


            // Retry Timer Algorithm
            if (sts_err_abort_mode == 0) begin
                retry_attempts        = 0;
                retry_timer           = 0;
                retry_timer_expired   = 0;
                retry_timeout         = 0;
                send_err_rsp_rtry_to  = 0;
            end else if (retry_timer >= retry_timeout_setting && retry_attempts < link_cfg.cfg_retry_limit) begin
               // Send unsolicited ERR_LINKx error packet when starting retry
                if (retry_attempts == 0) begin
                   $display("%t %m RETRY RX: Retry started on link %d", $realtime, link_cfg.cfg_link_id);
                   send_error();
                end
                retry_attempts     += 1;
                retry_timer         = 0;
                retry_timer_expired = 1;
                if (retry_attempts < link_cfg.cfg_retry_limit)
                    start_retry_txcnt   = 0;
            end else if (retry_attempts == (link_cfg.cfg_retry_limit)) begin
                // link retry failed
                if (!retry_timeout) begin
                    $display("%t %m RETRY RX: Link Failure after %d Retry attempts.", $realtime, retry_attempts);
                    retry_limit_reached = 1;
                    send_error();
                    $finish;
                end
                else begin     
                    send_err_rsp_rtry_to = 1; // todo: needs more definition, error response broadcast to all links?
                                  
                    retry_timeout        = 1;
                    $display("%t %m RETRY RX: Link Retry Time out Failure.", $realtime);
                    send_error();
                    $finish;
                end     
            end else begin
                retry_timer += 1;
                retry_timer_expired = 0;
            end


        end
    endtask // run_rx

    task automatic retry_counter();
        int cur_err_abort_mode;
        
        cur_err_abort_mode = num_err_abort_mode;
        
        #500ns;

        if (cur_err_abort_mode == num_err_abort_mode && !err_abort_clr) begin
            
            retry_attempts     += 1;
            error_abort        += 1;
            error_abort_rxcnt  = 0;
            start_retry_rxcnt  = 0;
        end
            
    endtask : retry_counter

    // compute how many entries are used in the retry buffer

    always @(*) begin
        if (tx_frp == rrp) // empty condition
            num_entries_used = 0;

        if (tx_frp > rrp) // normal case, no wraparound
            num_entries_used = tx_frp - rrp;

        if (tx_frp < rrp) // wraparound case
            num_entries_used = retry_buf_size + tx_frp - rrp;

    end

    // Task: wait_for_idle
    //
    // wait until there is nothing to do
    task automatic wait_for_idle();
        
        forever begin
            if (mb_tx_pkt_in.num() || tx_pkt_q.size() || 
                mb_rx_pkt_in.num() ||
                sts_err_abort_mode || start_retry_mode ||
                tx_frp != rrp
            ) begin
                $display ("%t %m RETRY: waiting for idle", $realtime);
                #200ns;
            end else
                break;
        end
        
    endtask

    final begin
        assert_retry_inactive: assert (!sts_err_abort_mode && !start_retry_mode) else 
            $error("Test ended before Link Retry completion");

        if(link_cfg.cfg_retry_enb) begin
            assert_all_pointers_returned: assert (tx_frp == rrp) else 
                $error("Test ended before all Retry Pointers were returned, tx_frp = %0d, rrp = %0d", tx_frp, rrp);
        end
    end


endinterface : hmc_retry
