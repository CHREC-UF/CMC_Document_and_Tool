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

`timescale 1ns/1ps
// 1 Write 1 Read Test
// -A single write followed by a single read to the same address

module hmc_1wr1rd();
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;
    
    // create the environment
    //hmc_bfm_env hmc_bfm_env();
    int rsp_expected;

    initial begin

        wait (`hmc_tb.P_RST_N);

        #20; // ns

        gen_pkts();

        rsp_expected = `hmc_tb.hmc_rsp_chk[0].req_pkt_q.size();
        $display("TEST: Request generation finished.  Waiting for %0d responses", rsp_expected);

        // wait for transistion from sleep to down mode
        // #(`hmc_tb.link_cfg[0].cfg_ttxd * 4 + cfg_tpst + 100ns);

        // #(10 * `hmc_tb.link_cfg[0].cfg_ttxd)
        // #(150us);
        #(2000ns);
        
        for (int i=0; i<=rsp_expected; i++) begin
            rsp_expected = `hmc_tb.hmc_rsp_chk[0].req_pkt_q.size(); // + tags_out(1) + tags_out(2) + tags_out(3);
            if (!rsp_expected) begin
                break;
            end
        end

        assert_all_rsp: assert (!rsp_expected) 
            $info("TEST: %1d transactions complete", 2);
        else 
            $error("TEST: Test timed out waiting for %1d responses", rsp_expected);

        #(1000ns); // allow some time for retry pointer and token return
        fork
            `hmc_tb.wait_for_idle(0);
            `hmc_tb.wait_for_idle(1);
            `hmc_tb.wait_for_idle(2);
            `hmc_tb.wait_for_idle(3);
        join
        $display("SIMULATION IS COMPLETE");
        $finish();
    end

    task gen_pkts();
        var cls_pkt pkt;
        var cls_req_pkt req_pkt;
        var cls_rsp_pkt rsp_pkt;
       
        req_pkt = new();
        req_pkt.header.cub = `hmc_tb.cube_cfg[0].cfg_cid;
        req_pkt.header.cmd = WR32;
        req_pkt.header.lng = 3;
        req_pkt.header.dln = 3;
        req_pkt.data = '{64'hF1234567, 64'hABFFABFF, 64'hABFFABFF, 64'hFFABFFAB};
        req_pkt.tail.crc = req_pkt.gen_crc();

        rsp_expected += req_pkt.must_respond();
        `hmc_tb.mb_tx_pkt[0].put(req_pkt);

        req_pkt = new();
        req_pkt.header.cub = `hmc_tb.cube_cfg[0].cfg_cid;
        req_pkt.header.cmd = RD32;
        req_pkt.header.lng = 1;
        req_pkt.header.dln = 1;
        req_pkt.tail.crc = req_pkt.gen_crc();

        rsp_expected += req_pkt.must_respond();
        `hmc_tb.mb_tx_pkt[0].put(req_pkt);

    endtask

endmodule
