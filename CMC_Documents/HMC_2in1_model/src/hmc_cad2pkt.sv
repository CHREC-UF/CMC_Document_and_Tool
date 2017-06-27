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

// HMC CAD to PKT converter
// -Converts incoming CAD objects to PKT objects 

`timescale 1ns/1ps
interface hmc_cad2pkt;
    import pkg_cad::*;
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    // modports
    mailbox#(cls_pkt)       mb_tx_pkt_out; // with flow control
    cls_que_cad             req_que = new(1);

    // Group: Configuration
    cls_cube_cfg            cube_cfg;   
    string                  address_mode;
    bit                     cfg_info_msg  = 0;
`ifdef TWOINONE_CORRELATION
    bit                     all_links_active = 0;
`endif


    initial begin
        wait (
            cube_cfg           != null &&
            mb_tx_pkt_out      != null
        );

        run_reset();

        //fork
            run_tx();
        //join_none
    end

    function automatic void run_reset();
        var string          csize;
        var string          block;

        if (cfg_info_msg)
            $display("%t %m: Warm Reset", $realtime);

        // get the address_mode from cube_cfg object
        case(cube_cfg.cfg_block_bits)
            1024 : block = "128";
            512  : block = "64";
            256  : block = "32";
        endcase
        case(cube_cfg.cfg_cube_size)
            0 : csize = "2GB";
            1 : csize = "4GB";
            2 : csize = "8GB";
        endcase
        // make the string for address_mode
        address_mode = {csize, "_", block, "B"};
    endfunction

    // Function: run_tx
    //
    // get from req_que, convert to req_pkt, then put into mb_tx_pkt_out
    task automatic run_tx();
        var     cls_cad txn;
        var     cls_req_pkt req_pkt;
        var int credit_return;

        forever begin
            //wait (req_que.size());
            @ (req_que.size_credits);
            txn = req_que.item(0);

            // Generate Random data if no data was supplied
            if (txn.is_write() && !txn.data.size()) begin
                for (int i=0; i<(txn.dbytes/4); i++)
                    txn.data.push_back($urandom);
                if (cfg_info_msg)
                    $displayh("%t %m CAD2PKT TX: generated random data, size: %d", $realtime, txn.data.size());
            end

            // convert cad to pkt
            req_pkt = new();
            req_pkt.address_mode = address_mode;
            req_pkt.build_pkt(txn, credit_return, 0, 0);
            req_pkt.tail.crc = req_pkt.gen_crc();

            if (cfg_info_msg)
                $display("%t %m CAD2PKT TX: req_que.size=%0d, %s", $realtime, req_que.size(), req_pkt.convert2string());
`ifdef TWOINONE_CORRELATION
            // ceusebio: for 2in1 correlation, wait for all links active
            // before issuing pkt
            wait(all_links_active);
`endif
            mb_tx_pkt_out.put(req_pkt);
            req_que.delete(0); // free queue location
        end
    endtask

endinterface : hmc_cad2pkt
