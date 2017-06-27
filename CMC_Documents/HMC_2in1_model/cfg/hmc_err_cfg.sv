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

// Error Injection Configuration
// -Example of randomized error injection

module hmc_err_cfg();
    import hmc_bfm_pkg::*;

    for(genvar i=0; i<num_links_c; i++) begin
        initial begin
            var cls_link_cfg link_cfg;

            link_cfg = new();

            @(posedge `hmc_tb.REFCLKP); // give some time for testbench initialization
            // Disable packet Error checking 
            link_cfg.cfg_check_pkt=0;
            // Set Infinite Retry Limit
            link_cfg.cfg_retry_limit='1;

            link_cfg.cfg_tx_clk_ratio = 60;
            link_cfg.cfg_rx_clk_ratio = 60;
            link_cfg.cfg_half_link_mode_tx = 1;
            link_cfg.cfg_half_link_mode_rx = 1;

            // randomize error injection with default constraints
            assert_link_randomize: assert (link_cfg.randomize(
                cfg_rsp_dln     ,
                cfg_rsp_lng     ,
                cfg_rsp_crc     ,
                cfg_rsp_seq     ,
                cfg_rsp_dinv    ,
                cfg_rsp_errstat ,
                //todo: move to hmc_rsp_gen cfg_rsp_err     ,
                cfg_rsp_poison  ,
                cfg_req_dln     ,
                cfg_req_lng     ,
                cfg_req_crc     ,
                cfg_req_seq
            )) else
                $error("link%0d link_cfg randomize failed", i);
            // apply configuration to each link
            `hmc_tb.set_config(link_cfg, i);
	     link_cfg = new link_cfg; // shallow copy 
   
        end
    end

endmodule
