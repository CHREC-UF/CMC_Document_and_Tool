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

// Randomizes the cube configuration objects and does a limited constraint on
// link configurations to test the permutations of symmetric link speeds and half-link mode

module hmc_rand_link_mode_cfg #(
    num_links_c=4,
    num_hmc_c=1
) ();
    import hmc_bfm_pkg::*;

    cls_cube_cfg            arr_cube_cfg[num_hmc_c];
    cls_link_cfg            arr_link_cfg[num_links_c];

    cls_cube_cfg            cube_cfg = new();
    cls_link_cfg            random_link_cfg = new();
	cls_link_cfg            link_cfg = new();

    bit               [2:0] cube_ids[$];
    int unsigned enable_errors;

    initial begin

        if ($value$plusargs("enable_errors=%d"      , enable_errors       )); else enable_errors= 0;

        $display("PLUSARG: enable_errors=%d", enable_errors);

        @(posedge `hmc_tb.REFCLKP); // give some time for testbench initialization

        $display("%t %m: randomizing Cube and Link configuration", $realtime);

        for (int i=0; i<num_hmc_c; i++) begin

            // re-randomize cube_cfg object for randc
            assert_cube_randomize: assert (cube_cfg.randomize()) else
                $error("cube_cfg randomize failed");

            cube_ids.push_back(cube_cfg.cfg_cid);
            arr_cube_cfg[i] = new cube_cfg;
            // apply configuration to each cube
            `hmc_tb.set_cube_config(arr_cube_cfg[i], i);
        end

		// create a single link config with certain randomly constrained
		// fields and the rest default
		assert_link_randomize: assert (random_link_cfg.randomize() with {
			cfg_cid inside {cube_ids};

		// random link speed (not constraining cfg_*_clk_ratio )
        // but make it RX and TX symmetric
		cfg_rx_clk_ratio == cfg_tx_clk_ratio;	
		cfg_half_link_mode_rx == cfg_half_link_mode_tx;

		}) else
			$error("link_cfg randomize failed");
		// copy just the randomized fields into a default config
		link_cfg.cfg_cid               = random_link_cfg.cfg_cid; // PR: required or else will catch fire
		link_cfg.cfg_tx_clk_ratio      = random_link_cfg.cfg_tx_clk_ratio;
		link_cfg.cfg_rx_clk_ratio      = random_link_cfg.cfg_rx_clk_ratio;
		link_cfg.cfg_half_link_mode_rx = random_link_cfg.cfg_half_link_mode_rx;
		link_cfg.cfg_half_link_mode_tx = random_link_cfg.cfg_half_link_mode_tx;
        link_cfg.cfg_rsp_open_loop     = random_link_cfg.cfg_rsp_open_loop;


        if (enable_errors) begin
            link_cfg.cfg_check_pkt   = 0;
            link_cfg.cfg_retry_limit = '1;
            link_cfg.cfg_rsp_lng     = random_link_cfg.cfg_rsp_lng;
            link_cfg.cfg_rsp_crc     = random_link_cfg.cfg_rsp_crc;
            link_cfg.cfg_rsp_seq     = random_link_cfg.cfg_rsp_seq;
            link_cfg.cfg_rsp_dinv    = random_link_cfg.cfg_rsp_dinv;
            link_cfg.cfg_rsp_errstat = random_link_cfg.cfg_rsp_errstat;
            link_cfg.cfg_rsp_poison  = random_link_cfg.cfg_rsp_poison;
            link_cfg.cfg_req_lng     = random_link_cfg.cfg_req_lng;
            link_cfg.cfg_req_crc     = random_link_cfg.cfg_req_crc;
            link_cfg.cfg_req_seq     = random_link_cfg.cfg_req_seq;
            link_cfg.cfg_req_dln     = random_link_cfg.cfg_req_dln;
            link_cfg.cfg_rsp_dln     = random_link_cfg.cfg_rsp_dln;
        end

		// apply the single link config to all links
		for (int i=0; i<num_links_c; i++) begin
			arr_link_cfg[i]                = new link_cfg;
			arr_link_cfg[i].display(i);
			// apply configuration to each link
			`hmc_tb.set_config(arr_link_cfg[i], i);
		end
        arr_link_cfg[0].display(0);
	end

    final begin
        for (int i=0; i<num_hmc_c; i++) begin
            assert_cube_eq: assert (arr_cube_cfg[i] == `hmc_tb.cube_cfg[i]) else
                $error("Cube %0d configuration miscompare", i);
        end

        for (int i=0; i<num_links_c; i++) begin
            assert_link_eq: assert (arr_link_cfg[i] == `hmc_tb.link_cfg[i]) else
                $error("Link %0d configuration miscompare", i);
        end
    end

endmodule
