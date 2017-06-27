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

// HMC FLIT Bus Functional Model
// -defines tasks to send, recieve, and monitor packets on a flit interface

`timescale 1ns/1ps 

import hmc_bfm_pkg::*; 

interface hmc_flit_bfm #(
    FLIT_W=128,
    QUAD_W=2,
    CHAN=3
) (
    input CLK, 
    input RESET_N
);
    logic [CHAN-1:0] [FLIT_W-1:0]   FLIT;
    logic [CHAN-1:0]                HEAD;
    logic [CHAN-1:0]                VALID;
    logic [CHAN-1:0]                TAIL;
    logic [CHAN-1:0]                CREDIT;

    modport TX (output  FLIT, HEAD, VALID, TAIL, input  CREDIT); //, monitor_pkt, send_pkt, send_null);
    modport RX (input   FLIT, HEAD, VALID, TAIL, output CREDIT); //, monitor_pkt, receive_pkt);

    import pkt_pkg::*;

    // internal signals
    int                 tx_credits; // credit counter: TX must stop when counter reaches 0
    int                 rx_credits; // credit counter: RX sends CREDIT to TX when buffer space is available
    logic       [127:0] tx_flits[$:CHAN+9];
    //int                 tx_head;
    bit                 tx_head[$:CHAN+9];
    bit                 tx_tail[$:CHAN+9];
    int                 tx_chan;

    // debug signals
    typ_req_header      debug_req_head[CHAN-1:0];
    typ_rsp_header      debug_rsp_head[CHAN-1:0];
    typ_req_tail        debug_req_tail[CHAN-1:0];
    typ_rsp_tail        debug_rsp_tail[CHAN-1:0];

    // Group: Configuration
    bit                 cfg_tx_en;
    bit                 cfg_rx_en;
    int                 cfg_rx_credits    = 2;  // enough credits to cover the round trip time

    int                 cfg_info_msg = 0;
`ifdef TWO_IN_ONE
    mailbox#(cls_flit) mb_flits2sysc;
    cls_flit last_head_flit;
`endif
/*
    always @* begin
        for(int i=0; i<CHAN; i++) begin
            debug_req_head[i] = {64{HEAD[i]}} & FLIT[i];
            debug_rsp_head[i] = {64{HEAD[i]}} & FLIT[i];
            debug_req_tail[i] = {64{TAIL[i]}} & FLIT[i][64+:64];
            debug_rsp_tail[i] = {64{TAIL[i]}} & FLIT[i][64+:64];
        end
    end
*/
    always_comb begin
        for(int i=0; i<CHAN; i++) begin
            debug_req_head[i] = {64{HEAD[i]}} & FLIT[i];
            debug_rsp_head[i] = {64{HEAD[i]}} & FLIT[i];
            debug_req_tail[i] = {64{TAIL[i]}} & FLIT[i][64+:64];
            debug_rsp_tail[i] = {64{TAIL[i]}} & FLIT[i][64+:64];
        end
    end

    always @(negedge RESET_N or posedge CLK) begin
        if (cfg_tx_en) begin // driving the FLIT interface
            if (!RESET_N) begin
                FLIT <= 0; // workaround for FLIT monitor 'bx;
                HEAD <= 0;
                VALID <= 0;
                TAIL <= 0;
                tx_chan = 0;
                //tx_head.delete(); // = 0;
                tx_credits <= 0;
            end else begin
                for(int i=0; i<CHAN; i++) begin
                    if (CREDIT[tx_chan])
                        tx_credits++;
                   
                    assert_size_chk: assert (tx_head.size() == tx_flits.size());

                    if (tx_credits && tx_flits.size()) begin
                        FLIT[tx_chan]  <= tx_flits.pop_front();
                        HEAD[tx_chan]  <= tx_head.pop_front(); //[0];
                        VALID[tx_chan] <= 1;
                        //TAIL[tx_chan]  <= tx_head[0] || !tx_flits.size();
                        TAIL[tx_chan]  <= tx_tail.pop_front();

                        tx_credits--;
                        //tx_head >>= 1;
                    end else begin
                        FLIT[tx_chan]  <= 0; //'bx;
                        HEAD[tx_chan]  <= 0;
                        VALID[tx_chan] <= 0;
                        TAIL[tx_chan]  <= 0;
                    end
                    tx_chan++;
                    tx_chan %= CHAN;
                end
            
            end
        end
        if (cfg_rx_en) begin // receiving from the FLIT interface
            if (!RESET_N) begin
                rx_credits <= cfg_rx_credits;                
		    CREDIT <= 0;          //TIE::ADG
            end else begin
                // track credits, return credit immediately
                rx_credits += VALID[tx_chan];
            
                for(int i=0; i<CHAN; i++) begin
                    if (rx_credits) begin
                        CREDIT[tx_chan] <= 1;
                        rx_credits--;
                    end else begin
                        CREDIT[tx_chan] <= 0;
                    end
                end
            end
        end
         
    end

    // Task: send_flit
    //
    // send a single FLIT
    task automatic send_flit(
        input        [127:0] flit,
        input                head,
//        input                valid,
        input                tail
    );
        tx_flits.push_back(flit);
        tx_head.push_back(head);
//        tx_valid.push_back(valid);
        tx_tail.push_back(tail);
//        wait (tx_flits.size() < CHAN);
    endtask : send_flit

    // Task: send_pkt
    //
    // send a packet on flit interface.
    task automatic send_pkt(
        input         [63:0] header,
        input        [127:0] data[],
        input         [63:0] tail
    );
        //static int           chan;
        var logic         [63:0] phits[$];
        var logic        [127:0] flits[$];

        //$display("%t %m size:%1d %p %p", $time, flits.size(), pkt_pkg::typ_req_header'(header), pkt_pkg::typ_req_tail'(tail)); //flits.size());
        //data = {<< 128{data}}; // reverse the data array
        //flits = {<< 128{tail, data, header}};
        phits.push_back(header);
        foreach(data[i]) begin
            phits.push_back(data[i][63:0]);
            phits.push_back(data[i][127:64]);
        end
        phits.push_back(tail);
        flits = pkt_pkg::phits2flits(phits);

        //tx_head[tx_flits.size()] = 1;
        tx_head = {tx_head, 1}; //tx_head.push_back(1);
        for (int i=1; i<flits.size(); i++) begin
            tx_head.push_back(0);
            tx_tail.push_back(0);
        end
        tx_tail = {tx_tail, 1};
        tx_flits = {tx_flits, flits};

        assert_size_chk: assert (tx_head.size() == tx_flits.size());
        wait (tx_flits.size() < CHAN);
    endtask


    // Task: receive_pkt
    //
    // receive a packet on flit interface.
    task automatic receive_pkt(
        output        [63:0] header,
        output       [127:0] data[],
        output        [63:0] tail
    ); 
        static int           chan;
        //var logic        [127:0] flits[$];
        var logic         [63:0] phits[$];
        var bit                  tail_bit;

        //flits = '{ }; //reset size of queue to 0;
        phits.delete();

        wait (RESET_N); // && HEAD[chan]);
        do begin
            
            if (chan == 0)
                @(posedge CLK);
            if (VALID[chan]) begin
                //flits.push_back(FLIT[chan]);
                //phits = '{phits, FLIT[chan][63:0], FLIT[chan][127:64]};
                phits.push_back(FLIT[chan][63:0]);
                phits.push_back(FLIT[chan][127:64]);
            end

            //CREDIT[chan] <= VALID[chan]; // return credits immediately
            tail_bit = TAIL[chan] && VALID[chan];
            chan++;
            chan %= CHAN;
        end while (!tail_bit);
        //$display("%t chan=%d, size=%d", $time, chan, flits.size());

        // ncvlog: *E,SOLTHS: Streaming operator - use on left hand side of assignment statements not supported at this time
        //{<< 128{tail, data, header}} = flits;
        //data = {<< 128{data}}; // reverse the data array

        header = phits.pop_front();
        tail = phits.pop_back();

        //data = new [phits.size()/2];
        //phits = {<< 64{phits}}; // reverse the data array
        //data = {<< 128{phits}}; // 128 bits at a time
        data = pkt_pkg::phits2flits(phits);
    endtask

`ifdef TWO_IN_ONE
    // Task: forward_to_systemc
    //
    // Take flits as they come out of the serdes block and forward them
    // directly to SystemC
    // 

    task automatic forward_to_systemc(); 
        static int           chan;
        var bit              tail_bit;
        var cls_flit         curr_flit;

        wait (RESET_N); // && HEAD[chan]);
        do begin
            
            if (chan == 0)
                @(posedge CLK);
            tail_bit = TAIL[chan] && VALID[chan];
            // ceusebio: SysC needs to see NULLs
            /*
            // valid non-null flits
            if (VALID[chan] && FLIT[chan] || last_head_flit) begin
            */
            if (VALID[chan] || last_head_flit) begin
                if (HEAD[chan]) begin
                    curr_flit = new(FLIT[chan], HEAD[chan], TAIL[chan], null);
                    last_head_flit = new curr_flit;
                end else begin
                    curr_flit = new(FLIT[chan], HEAD[chan], TAIL[chan], last_head_flit);
                end

            if (VALID[chan] && TAIL[chan] && last_head_flit)
                last_head_flit = null;

                if (mb_flits2sysc) begin // PR: this will not execute on testbench side
                    if (cfg_info_msg)
                        $display("%t %m created flit %s ", $realtime, curr_flit.convert2string());

                    if (curr_flit.head.cmd != PRET && curr_flit.head.cmd != IRTRY) begin
                        assert(mb_flits2sysc.try_put(curr_flit)) else $fatal(0, "%t %m: overran sysc mbox", $realtime);
                        if (cfg_info_msg)
                            $display("%t %m Forwarding %s to systemC", $realtime, curr_flit.convert2string());
                    end
                end
            end
            chan++;
            chan %= CHAN;
        end while (!tail_bit);
    endtask : forward_to_systemc
`endif

    // Task: monitor_pkt
    //
    // monitor a packet on flit interface.
    // same as receive_pkt
    task automatic monitor_pkt(
        output        [63:0] header,
        output       [127:0] data[],
        output        [63:0] tail
    ); 

        receive_pkt(header, data, tail);
    endtask

    // Task: send_null
    //
    // send 1 or more NULL FLITs
    task automatic send_null(
        input int            n = 1
    );
        var logic    [127:0] data[];

        repeat (n) begin
            send_pkt(0, data, 0); // send a FLIT with header==0, data.size == 0, and tail == 0
        end
    endtask

    assert_credit_overflow: assert property (@(posedge CLK) tx_credits <= cfg_rx_credits) else
        $error("%t %m Credit overflow tx_credits: %h cfg_rx_credits: %h",$realtime, tx_credits, cfg_rx_credits);

    assert_valid: assert property (@(posedge CLK) disable iff (!RESET_N) !$isunknown(VALID)) else
        $error("VALID signal cannot be x or z");
//    final begin
//        assert_all_credits: assert (tx_credits == cfg_rx_credits) else 
//            $error("Test ended before all credits were returned.  Expected: %1d, Actual: %1d", cfg_rx_credits, tx_credits);
//    end
endinterface : hmc_flit_bfm
