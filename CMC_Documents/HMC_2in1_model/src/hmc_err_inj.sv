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

// HMC Error Injection
// -Provides manual or randomized error injection
// -Can inject errors into the Request or Response streams
// -Detects inverted crc and sets the poison bit on incoming commands
// -Generates crc on outgoing commands and uses poison bit to invert crc

`timescale 1ns/1ps 

interface hmc_err_inj;
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    cls_link_cfg            link_cfg;   
    
    // modports
    mailbox#(cls_pkt)       mb_tx_pkt_in; // no flow control
    mailbox#(cls_pkt)       mb_tx_pkt_out; // with flow control
    mailbox#(cls_pkt)       mb_rx_pkt_in; // with flow control
    mailbox#(cls_pkt)       mb_rx_pkt_out; // no flow control

    pkt_analysis_port#()    mb_req_pkt_err_cov; // coverage
    pkt_analysis_port#()    mb_rsp_pkt_err_cov; // coverage
    
    // internal signals

    // Group: Configuration
    bit                     cfg_info_msg  = 0;

    // TODO: NOT USED
    bit                     cfg_host_link = 1;

    bit [31:0]              tag_tmp;
    bit [8:0]               tag;
    cls_rsp_pkt_err         rsp_tag_q[$];

    cls_req_pkt_err         req_tag_q[$];
    int debug_fd;

    initial begin

        wait (
            link_cfg           != null &&
            mb_tx_pkt_in       != null &&
            mb_rx_pkt_in       != null &&
            mb_rsp_pkt_err_cov != null &&
            mb_req_pkt_err_cov != null
        );
        `ifdef ADG_DEBUG
               cfg_info_msg = 1;
        `endif
                
        fork
            run_tx_pkt_in();
            run_rx_pkt_in();
        join_none
    end // initial begin

    // Function: gen_err_pkt
    //
    function automatic cls_pkt gen_err_pkt(input cls_pkt pkt);

        var   cls_rsp_pkt_err rsp_pkt_err;
        var   cls_req_pkt_err req_pkt_err;
        var       typ_rsp_cmd rsp_cmd;
        var      logic [63:0] header;


        header = pkt.get_header();

        if ($cast(rsp_cmd, header[5:0])) begin
            rsp_pkt_err = new ();
            rsp_pkt_err.header = header;
            rsp_pkt_err.data   = pkt.data;
            rsp_pkt_err.tail   = pkt.get_tail();
            rsp_pkt_err.poison = pkt.poison;
            rsp_pkt_err.lat    = pkt.lat;

            if ((header[5:0] != 0) && (
                link_cfg.cfg_rsp_crc || 
                link_cfg.cfg_rsp_errstat || 
                link_cfg.cfg_rsp_dln || 
                link_cfg.cfg_rsp_seq || 
                link_cfg.cfg_rsp_dinv || 
                link_cfg.cfg_rsp_errstat
            )) begin // performance optimization 
                assert_rsp_randomize: assert(rsp_pkt_err.randomize() with {
                    crc_c     == link_cfg.cfg_rsp_crc;
                    errstat_c == link_cfg.cfg_rsp_errstat;
                    dln_c     == link_cfg.cfg_rsp_dln;
                    lng_c     == link_cfg.cfg_rsp_lng;
                    seq_c     == link_cfg.cfg_rsp_seq;
                    dinv_c    == link_cfg.cfg_rsp_dinv;
                    err_c     == 0;
                    cid       == 0;  // unused
                }) else
                    $error("randomize failed");
            end

            // Search q for tags to inject error on
            foreach(rsp_tag_q[i]) begin

                if (rsp_tag_q[i].header.tag == rsp_pkt_err.header.tag) begin
                    assert_rsp_randomize: assert(rsp_pkt_err.randomize() with {
                        err == rsp_tag_q[i].err;
                    }) else
                        $error("randomize failed");

                    rsp_pkt_err.post_randomize();
                
                    $display("%t %m RSP ERR: Found tag match injecting error, tag = %0x", $realtime, rsp_pkt_err.header.tag);
                    rsp_tag_q.delete(i);
                    break;
                end
            end

            // also corrupt data when dinv was injected
            if (rsp_pkt_err.err[rsp_pkt_err.dinv_p]) begin
                $display ("%t %m Corrupting data for pkt: %s",$realtime, rsp_pkt_err.convert2string());
                rsp_pkt_err.corrupt_pkt("data");
                rsp_pkt_err.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CresTX_d_a");
            end

            // regen crc if an error was injected (except for crc and lng injection)
            if (rsp_pkt_err.err && !rsp_pkt_err.err[rsp_pkt_err.crc_p] && !rsp_pkt_err.err[rsp_pkt_err.lng_p]) begin
                rsp_pkt_err.tail.crc = rsp_pkt_err.gen_crc(); 
                if (rsp_pkt_err.poison) begin
                    rsp_pkt_err.tail.crc = ~rsp_pkt_err.tail.crc;
                end
            end

            gen_err_pkt = rsp_pkt_err;
        end else begin
            req_pkt_err = new ();
            req_pkt_err.header = header;
            req_pkt_err.data   = pkt.data;
            req_pkt_err.tail   = pkt.get_tail();
            req_pkt_err.poison = pkt.poison;
            
            if ((req_pkt_err.header.cmd != IRTRY) && (header[5:0] != 0) && (
                link_cfg.cfg_req_crc || 
                link_cfg.cfg_req_dln || 
                link_cfg.cfg_req_seq
            )) begin // performance optimization
                if(req_pkt_err.header.cmd == IRTRY) begin
                    assert_irtry_randomize: assert(req_pkt_err.randomize() with {
                        crc_c == 1; // 0.1%
                        dln_c == 1; // 0.1%
                        lng_c == 1; // 0.1%
                        seq_c == 1; // 0.1%
                    })
                      else
                        $error("irtry randomize failed");

                    
                end else begin
                    assert_req_randomize: assert(req_pkt_err.randomize() with {
                        crc_c == link_cfg.cfg_req_crc;
                        dln_c == link_cfg.cfg_req_dln;
                        lng_c == link_cfg.cfg_req_lng;
                        seq_c == link_cfg.cfg_req_seq;
                    })
                      else
                        $error("randomize failed");
                    
                end
            end

            foreach(req_tag_q[i]) begin

                if (req_tag_q[i].header.tag == req_pkt_err.header.tag) begin
                    req_pkt_err.err = req_tag_q[i].err;
                    req_pkt_err.post_randomize();

                    $display("%t %m REQ ERR: Found tag match injecting error, tag = %0x", $realtime, req_pkt_err.header.tag);
                    req_tag_q.delete(i);

                    break;

                end
            end

            // todo: this also disables IRETRY, PRET, and TRET packes from being poisoned in the response direction
            // IRETRY and PRET packets cannot be poisoned at this time because the SEQ, RRP, FRP, RTC fields must be populated

            // regen crc if an error was injected (except for crc and lng injection)
            if (req_pkt_err.err && !req_pkt_err.err[req_pkt_err.crc_p] && !req_pkt_err.err[req_pkt_err.lng_p]) begin
                req_pkt_err.tail.crc = req_pkt_err.gen_crc(); 
                if (req_pkt_err.poison) begin
                    req_pkt_err.tail.crc = ~req_pkt_err.tail.crc;
                end
            end

            gen_err_pkt = req_pkt_err;
        end

    endfunction : gen_err_pkt

    // Function: run_tx_pkt_in
    //
    task automatic run_tx_pkt_in();

        var       cls_pkt pkt, err_pkt;
        var   cls_rsp_pkt_err rsp_pkt_err;
        var   cls_req_pkt_err req_pkt_err;
        //var   cls_rsp_pkt_err errrsp_pkt;
        var      typ_rsp_tail tail;
        var      logic [31:0] crc;


        forever begin
            mb_tx_pkt_in.peek(pkt);
            tail = pkt.get_tail();

            // use poison bit to set crc
            tail.crc = pkt.gen_crc();
            if (pkt.poison) begin
                tail.crc = ~tail.crc;
            end

            pkt.set_tail(tail);
            err_pkt = gen_err_pkt(pkt);
            mb_tx_pkt_out.put(err_pkt);
                        
            if ($cast(rsp_pkt_err,err_pkt)) begin
                mb_rsp_pkt_err_cov.write(err_pkt);

                if (rsp_pkt_err.err) begin
                    $display("%t %m  ERR INJ TX RSP: Corrupted a response packet:\n\tbefore: %s\n\tafter : %s, err = %15b", $realtime, pkt.convert2string(), rsp_pkt_err.convert2string(), rsp_pkt_err.err);
                    pkt.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CresTX_b");
                    rsp_pkt_err.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CresTX_a");
                end
            end else if ($cast(req_pkt_err,err_pkt)) begin
                mb_req_pkt_err_cov.write(err_pkt);
                                
                if (req_pkt_err.err) begin
                    $display("%t %m  ERR INJ TX REQ: Corrupted a request packet:\n\tbefore: %s\n\tafter : %s, err = %15b", $realtime, pkt.convert2string(), req_pkt_err.convert2string(), req_pkt_err.err);
                    pkt.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CreqTX_b");
                    req_pkt_err.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CreqTX_a");
                end
            end else begin
                assert(0) else $error("cast failed");
            end
            mb_tx_pkt_in.get(pkt); // free mailbox location
        end

    endtask : run_tx_pkt_in


    // Function: run_rx_pkt_in
    //
    task automatic run_rx_pkt_in();
        var       cls_pkt pkt,err_pkt;
        var   cls_req_pkt_err req_pkt_err;
        var   cls_rsp_pkt_err rsp_pkt_err;
        var      typ_rsp_tail tail;
        var      logic [31:0] crc;

        forever begin
            mb_rx_pkt_in.peek(pkt);
            tail = pkt.get_tail();

            // use crc to set poison bit
            crc = pkt.gen_crc();
            if (crc == ~tail.crc) begin
	       pkt.poison = 1;
                if (cfg_info_msg) begin
                    $display("%t %m RX: CRC inverted, poison set to 1; %s", $realtime, pkt.convert2string());
                end 
            end

            err_pkt = gen_err_pkt(pkt);
            err_pkt.poison = pkt.poison;
            mb_rx_pkt_out.put(err_pkt);
                        
            if ($cast(rsp_pkt_err,err_pkt)) begin
                mb_rsp_pkt_err_cov.write(err_pkt);

                if (rsp_pkt_err.err) begin
                    $display("%t %m ERR INJ RX RSP: Corrupted a response packet:\n\tbefore: %s\n\tafter : %s  err=%15b", $realtime, pkt.convert2string(), rsp_pkt_err.convert2string(), rsp_pkt_err.err);
                    pkt.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CresRX_b");
                    rsp_pkt_err.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CresRX_a");
                end

            end else if ($cast(req_pkt_err,err_pkt)) begin
                mb_req_pkt_err_cov.write(err_pkt);
                if (req_pkt_err.err) begin
                    $display("%t %m ERR INJ RX REQ: Corrupted a request packet:\n\tbefore: %s\n\tafter : %s  err=%15b", $realtime, pkt.convert2string(), req_pkt_err.convert2string(), req_pkt_err.err);
                    pkt.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CreqRX_b");
                    req_pkt_err.pkt_trace(debug_fd, link_cfg.cfg_link_id, "CreqRX_a");
                end

            end else begin
                assert(0) else $error("cast failed");
            end
            mb_rx_pkt_in.get(pkt); // free mailbox location
        end
    endtask : run_rx_pkt_in


endinterface : hmc_err_inj
