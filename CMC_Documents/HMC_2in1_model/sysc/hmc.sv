`ifdef TWO_IN_ONE

`timescale 1ps/1ps

`define HMC_RTC_BITS 5

import hmc_bfm_pkg::*; 
import pkt_pkg::*;
import pkg_cad::*;

/**
* TODO: Cleanups to be done eventually
* - rename things (monitor_bad_whatever, run_rx_pkt)
* - make sure all associative arrays are getting cleared out at some point
* - Fix up stats and actually print them
* - remove all the per-link dimensions on structures indexed on transaction_id
*   since txn_ids are unique, it doesn't matter what link they came from
* - make a lot of the variables local so we get rid of a bunch of the
*   [link_id] indexing 
* - The txn_id handling in flit_bfm::forward_to_sysc is atrociously bad
* - all branches: for cases where link_cfg.cfg_tokens_expected is non-zero,
*   make sure that the two sides of the link match up in hmc_bfm_tb
*/

typedef struct packed {
    logic [0:0]  toggle; // toggle bit 
    logic [31:0] transaction_id; 
    logic [7:0]  flits_sent;
} typ_sysc_flits_used;

module hmc_2in1 #(
	/* All pin-level signals that feed into the wrapper must be hardcoded to
	 * 4 instances, all functional signals that feed back to the BFM via
	 * mailboxes are controlled by num_links_c
	 */
   num_links_c=4
) (
    input [3:0] link_power_states, 
    input inhibit_flit_rx[4]
); 
    typedef int unsigned txn_id_queue[$];

    mailbox#(cls_flit) mb_flits_from_serdes[num_links_c];
    // requests from flow control module
    mailbox#(cls_pkt) mb_rx_pkt_in[num_links_c];
    // responses to flow control module
    mailbox#(cls_pkt) mb_rsp_out[num_links_c]; 

    // requests forwarded to rsp_gen
    mailbox#(cls_pkt) mb_rx_pkt_out[num_links_c];
    // responses coming back from rsp_gen 
    mailbox#(cls_pkt) mb_rsp_in[num_links_c];

    mailbox#(int unsigned) mb_return_tokens[num_links_c];


    // packets that have returned from rsp_gen -- per link; keyed on the tag
    cls_rsp_pkt rsp_gen_packets[num_links_c][int];

    mailbox#(cls_pkt) mb_bad_req_in[num_links_c];
    cls_req_pkt bad_requests_map[num_links_c][int];

    // ceusebio: for keeping track of poison packets
    cls_req_pkt poison_requests_map[num_links_c][int];

    int unsigned wrongly_returned_tokens[num_links_c];
    semaphore wrongly_returned_tokens_sem = new(1);

    // keep track of all the currently used tags -- systemC requires this
    bit outstanding_tags[num_links_c][int];
    // if we bypassed the SC model, store a map of transaction_id->delay_time
    // in this map so that we can delay the response packet after it comes
    // back from rsp_gen
    realtime bypass_delay_map[int];

    int unsigned bypassed_tokens[num_links_c];
    semaphore bypassed_tokens_sem = new(1);

    // ceusebio: add a toggle bit to flits to SC, just like tokens
    logic [162:0] flit_out[4];
    logic         flit_out_toggle_bit[4] = '{0, 0, 0, 0};
    wire  [63:0]  flit_in[4];
    logic [32:0]  token_adjustments[4];

    // PR: systemC will tell us how many flits were sent in for each transaction ID
    wire  [40:0]  expected_sysc_token_return[4];

    // config options to pass to SC model
    logic [9:0] cfg_link_speed;
    logic [2:0] cfg_link_width;
    logic [9:0] cfg_host_num_tokens, cfg_cube_num_tokens;
    logic [10:0] cfg_block_bits;
    logic [2:0] cfg_cube_size;
    logic cfg_response_open_loop;
    logic [31:0] cfg_tj;

    // ceusebio: new SC parameters
	logic cfg_dram_tracing_en;
	logic cfg_refresh_en;

    // for run_tx
    cls_pkt pkt[num_links_c]; 
    cls_rsp_pkt rsp_pkt[num_links_c]; 
    int done_tag[num_links_c]; 

    /**
    * The 'return_tokens' signal is driven by the SystemC model to indicate
    * how many tokens are being returned. However, due to some issues with the
    * SC+SV bindings, the most significant bit is a "toggle bit" that flips
    * every time a "new" value is returned. That is, the low bits might be the
    * same between two token return packets, but the highest order bit will be
    * different on consecutive transactions. Therefore, the sensitivity of the
    * always block will take into account all of the bits, but the lower order
    * bits representing the actual return token count are spliced out into the
    * 'return_token_count' variable below. 
    **/
    wire    [`HMC_RTC_BITS:0]   return_tokens[4];
    logic   [`HMC_RTC_BITS-1:0] return_token_count[4];

    logic             simulation_finished;
    bit               cfg_info_msg = 0;
    // stats below
    // packets forwaded to rsp_gen that needed a response
    int total_forwarded_rsp=0; 
    // packets forwarded to rsp_gen that did not need a response
    int total_forwarded_no_rsp=0; 
    // total responses we got back from rsp_gen
    int total_received=0;
    // total responses we sent back to flow_ctrl
    int total_completed=0;
    // total dropped transactions (due to poisoning)
    int total_dropped=0;
    // total requests retried after being posioned
    int total_retried=0;


    hmc_2_in_1_wrapper hmcsim(.bfm_bits_in0  (flit_out[0])
                            , .bfm_bits_out0(flit_in[0])
                            , .bfm_return_tokens0(return_tokens[0])
                            , .link_power0(link_power_states[0])
                            , .expected_sysc_token_return0(expected_sysc_token_return[0])
                            , .token_adjust0(token_adjustments[0])
                            , .token_adjust1(token_adjustments[1])
                            , .token_adjust2(token_adjustments[2])
                            , .token_adjust3(token_adjustments[3])
                            , .bfm_bits_in1 (flit_out[1])
                            , .bfm_bits_out1(flit_in[1])
                            , .bfm_return_tokens1(return_tokens[1])
                            , .link_power1(link_power_states[1])
                            , .expected_sysc_token_return1(expected_sysc_token_return[1])
                            , .bfm_bits_in2 (flit_out[2])
                            , .bfm_bits_out2(flit_in[2])
                            , .bfm_return_tokens2(return_tokens[2])
                            , .link_power2(link_power_states[2])
                            , .expected_sysc_token_return2(expected_sysc_token_return[2])
                            , .bfm_bits_in3 (flit_out[3])
                            , .bfm_bits_out3(flit_in[3])
                            , .link_power3(link_power_states[3])
                            , .bfm_return_tokens3(return_tokens[3])
                            , .expected_sysc_token_return3(expected_sysc_token_return[3])
                            , .simulationFinishedSignal(simulation_finished)
                            , .cfg_link_speed(cfg_link_speed)
                            , .cfg_link_width(cfg_link_width)
                            , .cfg_cube_num_tokens(cfg_cube_num_tokens)
                            , .cfg_host_num_tokens(cfg_host_num_tokens)
                            , .cfg_block_bits(cfg_block_bits)
                            , .cfg_cube_size(cfg_cube_size)
                            , .cfg_response_open_loop(cfg_response_open_loop)
                            , .cfg_tj(cfg_tj)
                            , .cfg_dram_tracing_en(cfg_dram_tracing_en)
							, .cfg_refresh_en(cfg_refresh_en)
                            );

    initial begin
		fork 
			for (int i=0; i < num_links_c; ++i) begin
				wait(mb_rx_pkt_in[i] != null 
                     && mb_rsp_in[i] != null 
                     && mb_rx_pkt_out[i] != null 
                     && mb_flits_from_serdes[i] != null); 
			end
		join 

        $display("%t %m: MAILBOXES FOR %0d LINKS HOOKED, STARTING UP 2-in-1", $realtime, num_links_c);
        
		for (int i=0; i<num_links_c; ++i) begin 
			fork 
				run_rx_flit(i); 
				collect_rsp_gen_responses(i);
			join_none
			#0;
		end
    end

    for (genvar link_id=0; link_id<num_links_c; link_id++) begin : track_sysc_return_tokens
        typ_sysc_flits_used sc_flits_used;
        always @(expected_sysc_token_return[link_id]) begin
           sc_flits_used = typ_sysc_flits_used'(expected_sysc_token_return[link_id]);
           if (cfg_info_msg)
               $display("%t %m Sent %0d flits to SystemC for transaction %0d (bits=%0x)", $realtime, sc_flits_used.flits_sent, sc_flits_used.transaction_id, expected_sysc_token_return[link_id]);
            #1;

            if (cfg_info_msg)
                $display("%t %m Checking bad requests map for tid=%0d", $realtime, sc_flits_used.transaction_id);

            if (bad_requests_map[link_id].exists(sc_flits_used.transaction_id)) begin
                if (sc_flits_used.flits_sent == 0) begin
                    if (cfg_info_msg)
                        $display("%t %m: bad request won't generate response; removing from bad map: %s", $realtime, bad_requests_map[link_id][sc_flits_used.transaction_id].convert2string());
                    bad_requests_map[link_id].delete(sc_flits_used.transaction_id);
                // ceusebio: check poison packet map
                end else if (poison_requests_map[link_id].exists(sc_flits_used.transaction_id)) begin
                    // remove from poison pkt map, but don't add to wrongly_returned_tokens
                    if (cfg_info_msg)
                        $display("%t %m: poison pkt; removing from poison pkt map: %s", $realtime, poison_requests_map[link_id][sc_flits_used.transaction_id].convert2string());
                    poison_requests_map[link_id].delete(sc_flits_used.transaction_id);
                end else begin
                    wrongly_returned_tokens_sem.get(); // lock
                    wrongly_returned_tokens[link_id] += unsigned'(sc_flits_used.flits_sent);
                    wrongly_returned_tokens_sem.put(); // unlock
                    if (cfg_info_msg)
                        $display("%t %m %0d flits wrongly sent to SystemC (latest transaction=%0d, flits=%0d)", $realtime, wrongly_returned_tokens[link_id], sc_flits_used.transaction_id, sc_flits_used.flits_sent);
                end
            end

        end // always
    end : track_sysc_return_tokens

    // take any token returns that come from the SystemC model and forward
    // them to flow_ctrl
    for (genvar link_id=0; link_id<num_links_c; link_id++) begin : forward_return_tokens 
        int unsigned returned_tokens;
        int unsigned wrongly_returned_tokens_tmp;
        always @(return_tokens[link_id]) begin 
            // remove the "toggle bit" to just get the actual count 
            returned_tokens = unsigned'(return_tokens[link_id][`HMC_RTC_BITS-1:0]);
            if (cfg_info_msg)
                $display("%0t PR::BFM [LINK %0d] %m returning %b tokens (raw value %b) to flow_ctrl",$realtime, link_id, returned_tokens, return_tokens[link_id]);

            wrongly_returned_tokens_sem.get(); // lock
            wrongly_returned_tokens_tmp = wrongly_returned_tokens[link_id];
            symmetric_difference(returned_tokens, wrongly_returned_tokens_tmp);
            wrongly_returned_tokens[link_id] = wrongly_returned_tokens_tmp;
            wrongly_returned_tokens_sem.put(); // unlock

            if (returned_tokens > 0) begin
                if (cfg_info_msg)
                    $display("%t %m PR::BFM: [LINK %0d] returning %0d tokens to flow_ctrl",$realtime, link_id, returned_tokens);

                assert(mb_return_tokens[link_id] != null) else $fatal("%t %m: mb_return_tokens not hooked up", $realtime);
                mb_return_tokens[link_id].put(returned_tokens);
            end 
        end
    end: forward_return_tokens

    // collect responses from rsp_gen, and store them in a map keyed on the
    // tag (one map per link)
    task automatic collect_rsp_gen_responses(int link_id);
        cls_pkt pkt; 
        cls_rsp_pkt rsp_pkt; 
        typ_rsp_header rsp_header;
        forever begin
			assert(link_id < num_links_c) else $fatal("Getting response from unconnected link %d", link_id);
            mb_rsp_in[link_id].get(pkt);
            assert($cast(rsp_pkt, pkt)) else $fatal("Didn't get a response packet: %s", pkt.convert2string());
            if (rsp_pkt.poison) begin 
                // rsp_gen will send another non-poisoned packet that will
                // follow this packet, so drop the poisoned packet and just
                // wait for the non-poisoned one instead
                if (cfg_info_msg)
                    $display("%t %m PR::BFM [LINK %0d]: ignoring poisoned response packet from rsp_gen: %s",$realtime, link_id, rsp_pkt.convert2string());
            end else begin // regular (non-poisoned) response packet
                if (cfg_info_msg)
                    $display("%t %m PR::BFM [LINK %0d]: got response packet from rsp_gen: %s",$realtime, link_id, rsp_pkt.convert2string());

                // check for bypassed packet
                if(bypass_delay_map.exists(rsp_pkt.transaction_id)) begin
                    rsp_header = rsp_pkt.get_header();
                    $display("%t %m [LINK %0d]: sending back bypassed packet after %0t; marking %0d tokens bypassed", $realtime, link_id, bypass_delay_map[rsp_pkt.transaction_id], rsp_header.lng);
                    fork 
                        send_response_pkt(rsp_pkt, link_id, bypass_delay_map[rsp_pkt.transaction_id]);
                    join_none
                    #0; // start the fork 

                    bypassed_tokens_sem.get(); // lock 
                    // The host will return tokens to SystemC that it won't be expecting (since pkt got bypassed) -- so debit those tokens
                    bypassed_tokens[link_id] += unsigned'(rsp_header.lng);
                    bypassed_tokens_sem.put(); // unlock


                    bypass_delay_map.delete(rsp_pkt.transaction_id);
                    continue;
                end

                if(!outstanding_tags[link_id].exists(rsp_pkt.transaction_id))
                    outstanding_tags[link_id][rsp_pkt.transaction_id] = 1; 
                else begin
                    // since we no longer use tags, tids are by definition
                    // unique and so this should never be able to happen
                    // anymore
                    assert(0) else $fatal("Duplicate tag going to SystemC model are not allowed");
                end
                // store the response packet while we wait for the SC model to
                // return the tag
                rsp_gen_packets[link_id][rsp_pkt.transaction_id] = rsp_pkt;


                total_received++; 
            end // regular rsp pkt
        end
    endtask : collect_rsp_gen_responses

    task automatic add_pkt_2_bad_req_map(int link_id, cls_pkt pkt);
        cls_req_pkt req_pkt;
        assert($cast(req_pkt, pkt)) else $fatal("couldn't cast request packet");
        bad_requests_map[link_id][pkt.transaction_id] = req_pkt;
        // ceusebio: check for poisoned pkts
        if (pkt.poison) begin
            if (cfg_info_msg)
                $display("%t %m adding packet to poison packet map: %s", $realtime, req_pkt.convert2string());
            poison_requests_map[link_id][pkt.transaction_id] = req_pkt;
        end
    endtask

    // forward inbound transactions from serdes to rsp_gen (via output mailbox)
    task automatic run_rx_pkt(int link_id, cls_req_pkt req_pkt);
        // Forward to rsp_gen; Filter TRETs 
        if (req_pkt.header.cmd != TRET)  begin 
            if (cfg_info_msg)
                $display("%t %m sending packet to rsp_gen: %s", $realtime, link_id, req_pkt.convert2string());
            mb_rx_pkt_out[link_id].put(req_pkt);
        end

        // stats
        if (req_pkt.must_respond()) 
            total_forwarded_rsp++;
        else
        total_forwarded_no_rsp++;
    endtask : run_rx_pkt

    // take flits coming off the flit_bfm and forward them to SystemC;
    task automatic run_rx_flit(int unsigned link_id); 
        cls_flit flit_in; 
        typ_req_header header;
        typ_req_tail tail;
        cls_pkt good_pkt;
        cls_pkt bad_pkt;
        cls_req_pkt good_req_pkt;
        bit pkt_is_bad;
        bit pkt_is_good;
        bit token_adjust_toggle;
        int unsigned bypass_transaction_id=0;
        int unsigned header_lng;
        int unsigned tail_rtc;
        int unsigned bypassed_tokens_tmp; //needed to pass as ref to symmetric_difference() for Cadence tools
        cls_req_pkt  null_pkt; // ceusebio: SysC needs to see NULLs
        forever begin
			assert(link_id < num_links_c) else $fatal("Sending packet to unconnected link %d", link_id);
            mb_flits_from_serdes[link_id].get(flit_in);
            assert(flit_in.transaction_id > 0) else $fatal(0, "%t %m all flits should have transaction_id>0 coming into this module: %s", $realtime, flit_in.convert2string());


            if (!inhibit_flit_rx[link_id]) begin
                // SystemC doesn't understand certain command types so we just
                // forward them to the response generator and fix up the host
                // tokens manually
                if (flit_in.is_head) begin
                    header = flit_in.head;
                    if (should_bypass_systemc(header.cmd)) begin
                        bypass_transaction_id = flit_in.transaction_id;
                    end
                end

                // PR: TODO: figure out why this appears to be necessary 
                #1;

                if (bypass_transaction_id == flit_in.transaction_id) begin 
                    if (flit_in.is_tail) begin // forward all completed packets to rsp_gen and return the return tokens that SC won't
                        pkt_is_good = (mb_rx_pkt_in[link_id].try_get(good_pkt) == 1);
                        // need to call this just to empty the mailbox slot; bad pkt is ignored
                        pkt_is_bad  = (mb_bad_req_in[link_id].try_get(bad_pkt) == 1); 
                        assert(pkt_is_bad ^ pkt_is_good) else $fatal(0, "%t %m not good or bad bypass (good=%0d, bad=%0d); flit=%s", $realtime, pkt_is_good, pkt_is_bad, flit_in.convert2string());
                        if (pkt_is_good) begin
                            assert($cast(good_req_pkt, good_pkt)) else $fatal(0, "%t %m cast failed", $realtime);
                            header = good_req_pkt.get_header();
                            tail = good_req_pkt.get_tail();
                            header_lng = unsigned'(header.lng);

                            // if our bypass packet had host tokens, SC still needs
                            // to know about them; but clear out some tokens
                            // out of the bypassed token pool if there are any
                            // in there (this helps prevent a warning from the
                            // SC token adjustment function in certain cases)
                            tail_rtc = unsigned'(tail.rtc);
                            bypassed_tokens_sem.get(); // lock 
                            bypassed_tokens_tmp = bypassed_tokens[link_id];
                            symmetric_difference(tail_rtc, bypassed_tokens_tmp);
                            bypassed_tokens[link_id] = bypassed_tokens_tmp;
                            good_req_pkt.tail.rtc = tail_rtc;
                            bypassed_tokens_sem.put(); // unlock 

                            if (!cfg_response_open_loop && tail_rtc > 0) begin
                                token_adjust_toggle = !token_adjust_toggle;
                                token_adjustments[link_id] = {token_adjust_toggle, tail_rtc};
                            end
                            good_req_pkt.transaction_id = flit_in.transaction_id;
                            run_rx_pkt(link_id, good_req_pkt);
                            $display("%t %m giving back %0d return tokens to flow_ctrl after bypassing good pkt %s", $realtime, header_lng, good_req_pkt.convert2string());
                            mb_return_tokens[link_id].put(header_lng);
                            bypass_delay_map[flit_in.transaction_id] = 50ns;
                        end
                        bypass_transaction_id = 0;
                    end // if tail
                    // don't let the transaction go into SC
                    continue;
                end // if bypass transaction

                // If this flit is a tail, one of two things must have happened in
                // this same timestep:
                //   1. We got a cls_pkt in the mb_rx_pkt_in mailbox which means
                //   this tail belongs to an error-free packet
                //   2. We got a cls_pkt in the mb_bad_req_in mailbox which means
                //   this tail belongs to an error packet
                //
                // If we got a packet in neither or both of these mailboxes,
                // something went horribly wrong
                //
                // ceusebio: SysC now needs to see NULL flits
                // Flit BFM will now forward NULLs and we'll see them here
                if (flit_in.is_tail) begin
                    pkt_is_good = (mb_rx_pkt_in[link_id].try_get(good_pkt) == 1);
                    pkt_is_bad  = (mb_bad_req_in[link_id].try_get(bad_pkt) == 1); 

                    if (pkt_is_good && pkt_is_bad) begin
                        assert(0) else $fatal(0, "%t %m: Got a tail flit for a packet that was both good and bad: \n\tgood=%s\n\tbad=%s", $realtime, good_pkt.convert2string(), bad_pkt.convert2string());
                    end

                    if (pkt_is_good) begin
                        assert($cast(good_req_pkt, good_pkt)) else $fatal(0, "%t %m cast failed", $realtime);
                        good_req_pkt.transaction_id = flit_in.transaction_id;
                        if (cfg_info_msg)
                            $display("%t %m Got good pkt: %s", $realtime, good_req_pkt.convert2string());
                        run_rx_pkt(link_id, good_req_pkt);

                        tail_rtc = unsigned'(flit_in.tail.rtc);
                        good_pkt_matches_flit_in : assert(tail_rtc == good_req_pkt.tail.rtc) else $error("%t %m: RTC mismatch between flit_in and pkt: flit_in.tail.rtc=%0d, good_req_pkt.tail.rtc=%0d", $realtime,  flit_in.tail.rtc, good_req_pkt.tail.rtc);
                        bypassed_tokens_sem.get(); // lock 
                        bypassed_tokens_tmp = bypassed_tokens[link_id];
                        symmetric_difference(tail_rtc, bypassed_tokens_tmp); // updates both arguments
                        bypassed_tokens[link_id] = bypassed_tokens_tmp;
                        flit_in.tail.rtc = tail_rtc;
                        good_req_pkt.tail.rtc = tail_rtc;
                        bypassed_tokens_sem.put(); // unlock 

                        pkt_is_bad = 0;
                    end else if (pkt_is_bad) begin
                        bad_pkt.transaction_id = flit_in.transaction_id;
                        if (cfg_info_msg)
                            $display("%t %m Got bad pkt: %s", $realtime, bad_pkt.convert2string());
                        add_pkt_2_bad_req_map(link_id, bad_pkt);
                    end else if (flit_in.head.cmd == NULL) begin
                        pkt_is_good = 1;
                        null_pkt = new();
                        assert_null_pkt_cast: assert ($cast(good_req_pkt, null_pkt)) else
                             $error("%t %m casting good_req_pkt to null_pkt failed. %s", $realtime,good_req_pkt.convert2string());
                        good_req_pkt.transaction_id = flit_in.transaction_id;
                        good_req_pkt.set_header(flit_in.head);
                        good_req_pkt.set_tail(flit_in.tail);
                        // Clear tail_rtc
                        tail_rtc = 0;
                        // Check for data
                        if (!flit_in.is_head) begin
                            assert(0) else $fatal(0, "%t %m: Got a NULL flit with data, transaction_id=%0d", $realtime, flit_in.transaction_id);
                        end
                        if (cfg_info_msg)
                            $display("%t %m Got NULL pkt: %s", $realtime, good_req_pkt.convert2string());
                    end else begin
                        assert(0) else $fatal(0, "%t %m: Got a tail flit for a packet that was neither good nor bad, tag=%0d, transaction_id=%0d", $realtime, flit_in.tag, flit_in.transaction_id);
                    end
                end // flit is tail 

                // There is an obscure case that needs to be considered here
                // where the cube rx error injector happens to "fix" a packet
                // that was originally incorrectly transmitted on the wire.
                // For a single-flit packet (where flit_in and good_pkt arrive
                // at the same time), we have the possibility where the
                // original bad packet comes in on flit_in and the "fixed"
                // good packet comes in through good_pkt and they are not the
                // same. In this case, we must prefer the version coming from
                // the error injector since that is what the other BFM
                // components use. 
                if (pkt_is_good && flit_in.is_head && flit_in.is_tail) begin
                    // ceusebio: flip toggle bit and add to flit
                    flit_out_toggle_bit[link_id] = !flit_out_toggle_bit[link_id];
                    if (cfg_info_msg)
                        $display("%t %m [link%0d] flipping toggle bit: now %d", $realtime, link_id, flit_out_toggle_bit[link_id]);
                    if (cfg_info_msg)
                        $display("%t %m [link%0d] sending single-flit pkt to sysc: %s", $realtime, link_id, good_req_pkt.convert2string());
                    flit_out[link_id] = {flit_out_toggle_bit[link_id], flit_in.is_tail, pkt_is_bad, flit_in.transaction_id, good_req_pkt.get_header(), good_req_pkt.get_tail()};
                end else begin // normal case, just send flit_in
                    // ceusebio: flip toggle bit and add to flit
                    flit_out_toggle_bit[link_id] = !flit_out_toggle_bit[link_id];
                    if (cfg_info_msg)
                        $display("%t %m [link%0d] flipping toggle bit: now %d", $realtime, link_id, flit_out_toggle_bit[link_id]);
                    if (cfg_info_msg)
                        $display("%t %m [link%0d] sending flit to sysc: %s", $realtime, link_id, flit_in.convert2string());
                    flit_out[link_id] = {flit_out_toggle_bit[link_id], flit_in.is_tail, pkt_is_bad, flit_in.transaction_id, flit_in.head, flit_in.tail};
                end

            end else begin // we are inhibited
                if (cfg_info_msg)
                    $display("%t %m: [link%0d] Dropping inhibited flit: %s", $realtime, link_id, flit_in.convert2string());
            end

        end // forever

    endtask : run_rx_flit

    // given two numbers a and b, subtract the absolute difference from both
    // values; kind of like computing the balance where neither value can go
    // negative
    function automatic void symmetric_difference(ref int unsigned a, ref int unsigned b);
        if (a > b) begin
            a -= b;
            b = 0;
        end else begin
            b -= a;
            a = 0;
        end

    endfunction

    // collect responses from 2-in-1, lookup the corresponding response packet
    // by tag and then send back the pkt
    for (genvar link_id=0; link_id<num_links_c; link_id++) begin : run_tx
        bit token_adjust_toggle;
        int systemc_return_tokens;
        cls_req_pkt bad_req_pkt;
        always @(flit_in[link_id]) begin
            // We chop off the top bit which is the tag toggle bit
            // FIXME: remove excess bits; only the transaction_id is being sent here
            done_tag[link_id] = unsigned'(flit_in[link_id][62:0]);
            if (cfg_info_msg)
                $display("%t %m PR::BFM: [LINK %0d] receiving flit with tag: %0h (actual tag=%0h)", $realtime, link_id, flit_in[link_id], done_tag[link_id]);

            if (!rsp_gen_packets[link_id].exists(done_tag[link_id])) begin
                bad_req_pkt = bad_requests_map[link_id][done_tag[link_id]];

                // don't do token adjustments for open loop mode; the SC model
                // gets angry
                systemc_return_tokens = cfg_response_open_loop ? 0 : response_data_size_for_request(bad_req_pkt);
                if (cfg_info_msg)
                    $display("%t %m PR::BFM [LINK %0d] dropping response to bogus request %s (will return %0d tokens to SC)", $realtime, link_id, bad_req_pkt.convert2string(), systemc_return_tokens);

                bad_requests_map[link_id].delete(done_tag[link_id]);
                if (!cfg_response_open_loop) begin
                    token_adjust_toggle = !token_adjust_toggle;
                    token_adjustments[link_id] = {token_adjust_toggle, systemc_return_tokens};
                end
            end else begin // valid transaction
                pkt[link_id] = rsp_gen_packets[link_id][done_tag[link_id]];
                pkt[link_id].transaction_id = done_tag[link_id];

                assert($cast(rsp_pkt[link_id], pkt[link_id])) else $fatal("Didn't get a response packet");
                rsp_pkt[link_id].lat = $realtime/1ns;
                if (cfg_info_msg)
                    $display("%t %m PR::BFM: [LINK %0d] found matching tag=%d: response packet %s; setting lat=%0d", $realtime, link_id, done_tag[link_id], rsp_pkt[link_id].convert2string(), rsp_pkt[link_id].lat);

                if (!rsp_pkt[link_id].poison) begin
                    // send back the response packet, make sure it succeeded
                    send_response_pkt(rsp_pkt[link_id], link_id);
                end else if (cfg_info_msg) begin 
                    $display("%t %m PR::BFM [LINK %0d] dropping poisoned packet %s", $realtime, link_id, rsp_pkt[link_id].convert2string());
                    total_dropped++;
                end

                rsp_gen_packets[link_id].delete(done_tag[link_id]);

                systemc_unexpected_response_tag: assert(outstanding_tags[link_id].exists(done_tag[link_id])) else $fatal("Got back unexpected tag");
                outstanding_tags[link_id].delete(done_tag[link_id]);
            end

        end
    end : run_tx

    task automatic send_response_pkt(cls_pkt pkt, int unsigned link_id, realtime delay=0);
        if (delay > 0) 
            #(delay)
        // This mailbox is now unbounded
        assert(mb_rsp_out[link_id] != null) else $fatal(0, "%t %m unconnected mailbox", $realtime);
        mb_rsp_out[link_id].put(pkt);
        total_completed++;
        if (cfg_info_msg)
            $display("%t %m [LINK %0d] sent pkt (now %0d in mbox): %s", $realtime, link_id, mb_rsp_out[link_id].num(), pkt.convert2string());
    endtask

    task automatic wait_for_idle();
        simulation_finished = 0; 
        #1ps;
        forever begin
            int num_waiting = 0; 
            int last_pkt_index;
            for (int i=0; i<num_links_c; ++i) begin
                num_waiting += rsp_gen_packets[i].num();
            end
            if (num_waiting > 0) begin
                $display("%t PR::BFM %m: Still waiting for %d responses from SystemC (sent %d rsp/ %d norsp, received %d, completed %d)", $realtime, num_waiting, total_forwarded_rsp, total_forwarded_no_rsp, total_received, total_completed); 
                if (num_waiting == 1) begin
                    for (int i=0; i<num_links_c; ++i) begin
                        if(rsp_gen_packets[i].first(last_pkt_index))
                            $display("\t Last packet from link %d is: %s", i, rsp_gen_packets[i][last_pkt_index].convert2string());
                    end
                end
                #10ns; 
            end else begin
                simulation_finished = 1; 
                // PR: give systemC a moment to print out stats before
                // $finish()
                #10ps;
                break;
            end
        end

    endtask : wait_for_idle

    function automatic bit should_bypass_systemc(typ_req_cmd cmd);
        case(cmd)
            MD_WR,
            MD_RD: should_bypass_systemc = 1;

            default: should_bypass_systemc = 0;
        endcase
    endfunction
    // PR: TODO: figure out if this already exists somewhere in the BFM
    function automatic int response_data_size_for_request(cls_req_pkt req_pkt);
        typ_req_header header;
        cls_cad cad; 

        header = req_pkt.get_header();
        cad = new();
        void'(req_pkt.get_cad(cad));
        case (header.cmd)
                WR16,
                WR32,
                WR48,
                WR64,
                WR80,
                WR96,
                WR112,
                WR128: response_data_size_for_request = 1;

               
                RD16 ,
                RD32 ,
                RD48 ,
                RD64 ,
                RD80 ,
                RD96 ,
                RD112, 
                RD128: response_data_size_for_request = int'(cad.dbytes)+2;
            default: begin
                assert(0) else $fatal(0, "%t %m: This pkt type needs a response? %s", $realtime, req_pkt.convert2string());
            end
        endcase

    endfunction

    function automatic void set_config(cls_link_cfg link_cfg);
        // PR: TODO: rename variables -- confusing because these are really
        // cfg_cube_num_tokens = "host many tokens do we send to the cube to
        // tell it about our buffer space"
        cfg_cube_num_tokens    = link_cfg.cfg_tokens;
        cfg_host_num_tokens    = link_cfg.cfg_tokens_expected;

        cfg_response_open_loop = link_cfg.cfg_rsp_open_loop;
        assert(link_cfg.cfg_tx_clk_ratio == link_cfg.cfg_rx_clk_ratio && link_cfg.cfg_half_link_mode_rx == link_cfg.cfg_half_link_mode_tx) 
            else $fatal(0, "SC model doesn't support asymmetric links");

        cfg_link_speed = link_cfg.cfg_rx_clk_ratio;
        cfg_link_width = link_cfg.cfg_half_link_mode_rx;

        cfg_dram_tracing_en = link_cfg.cfg_dram_tracing_en;
		cfg_refresh_en		= link_cfg.cfg_refresh_en;
    endfunction

    function automatic void set_cube_config(cls_cube_cfg cube_cfg);
        assert(cube_cfg.cfg_tj <= 105) else $error("%t %m The selected operating temperature (%0d'C) is outside the HMC spec boundaries", $realtime, cube_cfg.cfg_tj);
        cfg_tj         = cube_cfg.cfg_tj;
        assert(cube_cfg.cfg_cube_size == 0) else $fatal("%t %m The selected cube size (%0d) is not supported", $realtime, cube_cfg.cfg_cube_size);
        cfg_cube_size  = cube_cfg.cfg_cube_size;
        cfg_block_bits = cube_cfg.cfg_block_bits;
    endfunction

endmodule
`endif //TWO_IN_ONE
