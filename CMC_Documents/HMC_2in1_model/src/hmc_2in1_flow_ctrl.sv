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

// HMC Flow Control for 2in1
// -stores a queue of outgoing commands 
// -extracts RTC from request packets
// -embeds RTC into response packets
// -generates TRET packets when queue is empty
// -filters out TRET packets from downstream devices: PR: no longer true on cube side for 2-in-1 -- it passes TRETs forward to systemC which also returns TRETs back
// -blocks TX stream when tokens == 0
// -configurable random delay of RTC time

/**
* PR: this module must be hooked on the cube side of a link (do host_mode == 1)
**/

`timescale 1ns/1ps

interface hmc_2in1_flow_ctrl;
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    // modports
    mailbox#(cls_pkt)       mb_tx_pkt_in; // no flow control
    mailbox#(cls_pkt)       mb_tx_pkt_out; // with flow control
    mailbox#(cls_pkt)       mb_rx_pkt_in; // with flow control
    mailbox#(cls_pkt)       mb_rx_pkt_out; // no flow control

    mailbox#(int unsigned)      mb_return_tokens; 


    // internal signals
    cls_pkt                 rx_pkt_q[$]; // link input buffer
    cls_pkt                 tx_pkt_q[$]; // link output buffer
    bit               [8:0] rx_pkt_q_flits; // number of FLITs in the link input buffer
    // input buffer tokens
    //   initial value =  link_cfg.cfg_tokens
    //   increment when packets are received += header.lng
    //   decrement when rtc is transmitted -= tail.rtc
    //   configure delay using link_cfg.cfg_rtc_min/mean/std_dev
    bit               [9:0] tokens;
    bit                     send_tret_inhibit=0; // prevent explicit TRET from being sent?
`ifdef HMC_TRET_THROTTLE
    realtime                cfg_send_tret_timeout = `HMC_TRET_THROTTLE; // larger values make sending explicit TRET less likely
`else 
    realtime                cfg_send_tret_timeout = 1.6ns; // larger values make sending explicit TRET less likely
`endif 
    bit                     sent_return_tokens =0; // will be toggled every time return tokens are sent back to host

    // LMSTAT [9:0] Indicates current number of tokens available for transmitting FLITs.
    //   initial value = 0
    //   increment when rtc is received += tail.rtc
    //   decrement when packets are transmitted -= header.lng
    //   configure delay using link_cfg.cfg_retry_delay 
    bit              [10:0] sts_tx_tokens;
    bit                     systemc_token_return_started = 0;
    int                     rtc_proccess_count;
    bit                     reset_done;
    int                     cfg_tx_pkt_q_size = 20;
    int                     seed = adg_seed;
    typ_req_header          incoming_pkt_header = 0;


    // Group: Configuration
    cls_link_cfg            link_cfg;   
    bit                     cfg_info_msg  = 0;
    bit                     cfg_stall_info_msg = 0; // show when token stall conditions happen? 
    // bit                  cfg_tx_taga_en = 1; // enable use of the taga field on responses
    
    initial begin
       `ifdef ADG_DEBUG
            cfg_info_msg  = 1;
       `endif
        wait (
            link_cfg           != null &&
            mb_tx_pkt_in       != null &&
            mb_tx_pkt_out      != null &&
            mb_rx_pkt_in       != null &&
            mb_rx_pkt_out      != null &&
            reset_done
        );
            assert (link_cfg.cfg_host_mode == 1) else $fatal("Hooked 2in1 flow control block on wrong side of link (cfg_host_mode=%0d)", link_cfg.cfg_host_mode);
            wait(mb_return_tokens);
            $display("%m 2in1 host mode=%0d", link_cfg.cfg_host_mode);

        fork
            run_tx_pkt_in();
            run_tx();
            run_rx();
            run_rx_pkt_out();
            run_token_return();


        join_none
    end

    task automatic run_token_return();
        int unsigned num_tokens_returned;
        forever begin
            mb_return_tokens.get(num_tokens_returned);
            // previous statement will block until something is returned
            systemc_token_return_started = 1;
            tokens += num_tokens_returned;
            if (cfg_info_msg)
                $display("%0t PR::FLOW [LINK %0d] %m systemC returned %0d; now %0d tokens available to forward to host",$realtime, link_cfg.cfg_link_id, num_tokens_returned, tokens);
        end
    endtask : run_token_return

    function automatic void run_reset();
        if (cfg_info_msg)
            $display("%t %m: Warm Reset", $realtime);
        assert_empty_buffers: assert (!rx_pkt_q.size() && !tx_pkt_q.size()) else begin
            $warning("%1d in flight transactions haven been lost due to Warm Reset", rx_pkt_q.size() + tx_pkt_q.size());
            //foreach (rx_pkt_q[i])
            //    $warning("\tLink Input Buffer[%0d]: %s", i, rx_pkt_q[i].convert2string());
            //foreach (tx_pkt_q[i])
            //    $warning("\tLink Output Buffer[%0d]: %s", i, tx_pkt_q[i].convert2string());
        end
        assert_tokens_returned: assert (!tokens) else
            $warning("All tokens must be returned prior to Warm Reset");
        rx_pkt_q.delete();
        tx_pkt_q.delete();
        rx_pkt_q_flits                  = 0;
        // PR: the systemC model will tell us when tokens can be returned so
        // we start with zero initially 
        tokens             = 0;
        sts_tx_tokens      = 0;
        rtc_proccess_count = 0;
        reset_done         = 1;
    endfunction : run_reset

    // Function: run_tx_pkt_in
    //
    // get from mb_pkt_in, put into tx_pkt_q
    task automatic run_tx_pkt_in();
        var       cls_pkt pkt;

        forever begin
            wait(tx_pkt_q.size() < cfg_tx_pkt_q_size);
            mb_tx_pkt_in.get(pkt);
            tx_pkt_q.push_back(pkt);
        end
    endtask : run_tx_pkt_in

    task automatic tx_token_watchdog();
`ifdef HMC_TRET_THROTTLE
        $display("%t %m: Waiting for cfg_send_tret_to = %t", $realtime, `HMC_TRET_THROTTLE);
`endif 
        #(cfg_send_tret_timeout);
        send_tret_inhibit =  0;
    endtask

    always @(sent_return_tokens) begin
        disable tx_token_watchdog;
        send_tret_inhibit = 1;
        fork
            tx_token_watchdog;
        join_none
    end

    // Function: run_tx
    //
    // get from put into tx_pkt_q, put into mb_pkt_out
    task automatic run_tx();
        var        cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var typ_req_header header;
        var   typ_req_tail tail;

        forever begin

            wait(tx_pkt_q.size() || (tokens && !send_tret_inhibit) );

            if (tx_pkt_q.size()) begin
                incoming_pkt_header = tx_pkt_q[0].get_header();
            end else begin
                incoming_pkt_header = 0;
            end

            // The link master is allowed to send a flow command even if there are no tokens available.
            // TODO: re-add
//            if (cfg_stall_info_msg && !(incoming_pkt_header != 0 && (sts_tx_tokens >= incoming_pkt_header.lng || link_cfg.cfg_rsp_open_loop || incoming_pkt_header.cmd == PRET || incoming_pkt_header.cmd == IRTRY || incoming_pkt_header.cmd == TRET))) 
//                $display("%t %m: INFO: token stall condition; pkt=%s, sts_tx_tokens=%0d; tokens=%0d", $realtime, tx_pkt_q[0].convert2string(), sts_tx_tokens, tokens);
            wait((incoming_pkt_header != 0 && (sts_tx_tokens >= incoming_pkt_header.lng || link_cfg.cfg_rsp_open_loop || incoming_pkt_header.cmd == PRET || incoming_pkt_header.cmd == IRTRY || incoming_pkt_header.cmd == TRET)) || (tokens && !send_tret_inhibit) );
            if  (incoming_pkt_header != 0 && (sts_tx_tokens >= incoming_pkt_header.lng || link_cfg.cfg_rsp_open_loop || incoming_pkt_header.cmd == PRET || incoming_pkt_header.cmd == IRTRY || incoming_pkt_header.cmd == TRET)) begin
                pkt = tx_pkt_q[0];
                header = pkt.get_header();

                if (cfg_stall_info_msg) begin
                    $display("%t %m: INFO: token stall clear; pkt=%s, sts_tx_tokens=%0d", $realtime, pkt.convert2string(), sts_tx_tokens);
                end

                if (!link_cfg.cfg_rsp_open_loop) begin
                    if ((header.cmd != PRET) & (header.cmd != TRET) & (header.cmd != IRTRY)) begin // flow control packets from the test don't need a credit to send
                        assert (sts_tx_tokens >= header.lng) else $fatal(0, "%t %m(2in1) Flow control got packet that violates token protocol: lng=%0d; sts_tx_tokens=%0d", $realtime, header.lng, sts_tx_tokens);
                        sts_tx_tokens -= header.lng;
                    end
                end

                tx_pkt_q.delete(0); // free the location in tx_pkt_q
            end else if (tokens && !send_tret_inhibit) begin // Generate new TRET packet
                header     = 0;
                header.cmd = TRET;
                header.lng = 1;
                header.dln = 1;
                req_pkt = new();
                pkt = req_pkt;
            end else begin
                assert_unreachable: assert (0) else
                    $error("unreachable branch");
            end
            pkt.set_header(header);
            // embed the rtc on anything but PRET or IRTRY
            if(header.cmd != PRET && header.cmd !=IRTRY) begin
                tail     = pkt.get_tail();
                tail.rtc = get_rtc();
                pkt.set_tail(tail);

                // toggle this signal so it re-triggers the TRET watchdog
                if (tail.rtc > 0) 
                    sent_return_tokens = ~sent_return_tokens;
            end
            
            //done in hmc_err_inj: tail.crc = pkt.gen_crc();
            //done in hmc_err_inj: pkt.set_tail(tail);

            if (cfg_info_msg)
                $display("%t %m: FLOW TX: %s (now returnTokens=%0d, sts_tx_tokens=%0d)", $realtime, pkt.convert2string_short(), tokens, sts_tx_tokens);
            mb_tx_pkt_out.put(pkt);
        end
    endtask

    // Function: get_rtc
    //
    // returns a number of tokens to embed into the rtc field
    // decrements tokens
    function automatic bit[4:0] get_rtc();
        if (tokens > 31)
            get_rtc = 31;
        else
            get_rtc = tokens;
        tokens -= get_rtc;
    endfunction

    // Function: run_rx
    //
    // get from mb_rx_pkt_in, put to mb_rx_pkt_out
    task automatic run_rx();
        var        cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var    cls_rsp_pkt rsp_pkt;
        var   typ_req_tail tail;
        var typ_req_header header;

        forever begin : run_loop

            // PR: this mbox has size equivalent to link_cfg[i].cfg_tokens
            mb_rx_pkt_in.get(pkt);

            header = pkt.get_header();
            tail   = pkt.get_tail();

            if (!link_cfg.cfg_rsp_open_loop) begin
                fork
                    delay_rtc_in(tail.rtc); // extract the rtc, delayed increment
                join_none
                #0; // start the forked task
            end

            if (cfg_info_msg)
                $display("%t %m FLOW RX: %s (pkt.rtc=%0d, sts_tx_tokens=%0d now)", $realtime, pkt.convert2string_short(), tail.rtc, sts_tx_tokens);

            assert_rsp_open_loop: assert (!link_cfg.cfg_rsp_open_loop || !tail.rtc) else begin
                $warning("%t %m RTC field ignored during Response Open Loop mode. cfg_rsp_open_loop = %0d; Expected RTC = 0, Actual RTC = %1d",$realtime,link_cfg.cfg_rsp_open_loop, tail.rtc);
                $assertoff(1, run_rx.run_loop.assert_rsp_open_loop); // only issue this warning one time
            end

            assert_dln_match: assert(header.lng == header.dln) else begin
                $display("%t %m LNG/DLN RX: %s", $realtime, pkt.convert2string());
                $error("lng dln mismatch must be resolved in hmc_retry: %s", pkt.convert2string());
            end
            

            assert_null_pret_itry: assert (pkt.poison || (header.cmd && header.cmd != IRTRY && header.cmd != PRET)) else
                $error("IRTRY, PRET, and NULL commands are not allowed in the input stream");

            if (header.cmd != TRET) begin
                rx_pkt_q.push_back(pkt);
                rx_pkt_q_flits += header.lng;
                

                // PR: TODO: Currently the SystemC model just aborts when it
                // sees this condition -- in theory it should signal an error
                // back. At the very least this would require some extra error
                // signals or maybe some extra transaction types to be added
                // to systemc. 
                if (rx_pkt_q_flits > link_cfg.cfg_tokens) begin
                    $display ("%t %m: Input Buffer Overrun.  Expected Input Buffer Size <= %0d, Actual Input Buffer Size = %0d", $realtime, link_cfg.cfg_tokens, rx_pkt_q_flits);
                    rsp_pkt = new();
                    rsp_pkt.header.cmd = ERROR;
                    rsp_pkt.header.lng = 1;
                    rsp_pkt.header.dln = 1;
                    rsp_pkt.header.tag = link_cfg.cfg_cid;
                    rsp_pkt.tail.errstat = typ_err_stat'(ERR_BUF_LINK0 | link_cfg.cfg_link_id);
                    mb_tx_pkt_out.put(rsp_pkt);
                end
            end else begin 
                // PR: immediately send out the TRET packet without a delay or flow control accounting 
                mb_rx_pkt_out.put(pkt);
            end
        end        
    endtask

    // Function: run_rx_pkt_out
    //
    // get from rx_pkt_q, put into mb_pkt_out
    task automatic run_rx_pkt_out();
        var        cls_pkt pkt;
        var typ_req_header header;

        forever begin
            wait(rx_pkt_q.size());
            pkt = rx_pkt_q[0];
            header = pkt.get_header();
            rx_pkt_q_flits -= header.lng;

            if (link_cfg.cfg_tail_rtc_dsbl) // force RTC = 0 to turn off TRET generation
                tokens = 0;
            // discard poison packet after extracting frp, rrp, seq, and rtc
            if (pkt.poison) begin
                if (cfg_info_msg)
                    $display("%t %m FLOW RX: Discarding Poisoned packet: %s", $realtime, pkt.convert2string());
            end else begin
                mb_rx_pkt_out.put(pkt);
            end
            rx_pkt_q.delete(0);
        end
    endtask : run_rx_pkt_out



    // wait for cfg_retry_delay before incrementing received token count
    // TODO: PR: this function name is no longer representative of reality
    task automatic delay_rtc_in(input bit[4:0]rtc);
        rtc_proccess_count++;
        sts_tx_tokens += rtc;
        rtc_proccess_count--;
    endtask

    // Task: wait_for_idle
    //
    // wait until there is nothing to do
    task automatic wait_for_idle();
        //$display ("%t %m FLOW: wait_for_idle begin", $realtime);
        forever begin
            if ((mb_tx_pkt_in != null && mb_tx_pkt_in.num())  || tx_pkt_q.size() || 
                (mb_tx_pkt_out != null && mb_tx_pkt_out.num()) ||
                (mb_rx_pkt_in  != null && mb_rx_pkt_in.num())  || rx_pkt_q.size() ||
                (mb_rx_pkt_out != null && mb_rx_pkt_out.num()) ||
                rtc_proccess_count  ||
                // PR: wait for systemC to have started returning tokens 
                systemc_token_return_started == 0 || 
                tokens
            ) begin
                $display ("%t %m FLOW: waiting for idle", $realtime);
                #200ns;
            end else
                break;
        end
        //$display ("%t %m FLOW: wait_for_idle end", $realtime);
    endtask
    
/*
`ifndef VCS
    // vcs: Error-[SE] Syntax error
    assert_tx_token_overflow: assert #0 (tokens <= link_cfg.cfg_tokens) else
        $error("Token overflow. Token count must be <= %1d.  Actual token count = %1d", link_cfg.cfg_tokens, tokens);

    assert_rx_token_overflow: assert #0 (sts_tx_tokens < 1024) else // 10 bit token count register overflow
        $error("Token overflow. Token count must be < %1d.  Actual token count = %1d", 1024, sts_tx_tokens);

    assert_min_tokens: assert #0 (link_cfg.cfg_tokens >= 9) else
        $error("Number of tokens must be >= 9 to allow the largest packet size to be transferred contiguously");
`endif
*/

    always @(tokens or link_cfg or sts_tx_tokens) begin
        if (link_cfg != null) begin
            assert_tx_token_overflow: assert (tokens <= link_cfg.cfg_tokens) else
                $error("%t %m Token overflow. Token count must be <= %1d.  Actual token count = %1d", $realtime, link_cfg.cfg_tokens, tokens);

            assert_min_tokens: assert (link_cfg.cfg_tokens >= 9) else
                $error("%t %m Number of tokens must be >= 9 to allow the largest packet size to be transferred contiguously", $realtime);
        end

        if (link_cfg && !link_cfg.cfg_rsp_open_loop) begin // don't worry about sts_tx_token value on the cube side in response open loop mode
            assert_rx_token_overflow: assert (sts_tx_tokens < 1024) else // 10 bit token count register overflow
                $fatal("%t %m Token overflow. Token count must be < %1d.  Actual token count = %1d", $realtime, 1024, sts_tx_tokens);
        end
    end

    final begin
        assert_all_tokens: assert (!tokens) else
            $error("Test ended before all tokens were returned.  Expected: 0, Actual: %1d", tokens);
    end

endinterface : hmc_2in1_flow_ctrl
