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
`define hmc_tb hmc_flit_top_tb
`define hmc_dut hmc_flit_top_tb

// HMC Bus Functional Model Test Bench
// -instantiates a flit bfm connected to a serdes interface
// -instantiates the device under test (dut): <hmc_bfm>
// -drives the REFCLK and P_RST_N into the dut
import pkt_pkg::*;
import pkg_cad::cls_cad;
import hmc_bfm_pkg::*;

//global space parameters:
parameter num_links_c = 4;
parameter num_hmc_c   = 1;
//
module `hmc_tb;
        
    bit  cfg_info_msg  = 0;
    initial begin
        $timeformat(-9, 3, " ns", 12); 
        #2ms;

        assert_deadman_timer: assert (0) else
                $error("%t %m Your test is too long.  Try breaking it into smaller pieces.", $realtime);
        $finish;
    end

    initial begin
        #15;
        if (cfg_info_msg)
           void'(open_tsvfile());
    end
    final   $fclose(mcd);
    logic [num_links_c-1:0]          LxTXPS_reg = {num_links_c{1'b1}};
    
    // generate the clock
    parameter REFCLK_PERIOD = 8.0; //ns = 125MHz
    bit REFCLKP = 0;
    initial
        forever #(REFCLK_PERIOD/2.0) REFCLKP = !REFCLKP;
    wire REFCLKN = ~REFCLKP;

    // generate the RESET
    reg P_RST_N;
    initial begin
        P_RST_N <= 0;
        P_RST_N <= #(50) 1;
    end
    
    wire SDA;

    // clocks
    bit                 clk_txui;
    bit                 clk_rxui;
    bit                 refclk;
    time                tm_refclk;
    time                tm_refclk_period;
    assign              refclk = REFCLKP & ~REFCLKN;
    bit           [1:0] cnt_txui;
    bit           [1:0] cnt_rxui;

    // Group Configuration
    int                 cfg_tx_clk_ratio  = 60; //125MHz REFCLK * 60 = 750MHz UICLK = 1.5Gbps UI
    int                 cfg_rx_clk_ratio  = 60;

    // pll model
    always @(posedge refclk) begin
        tm_refclk_period = $time - tm_refclk;

        if (tm_refclk_period <= 16ns) begin
            for (real i=0; i<cfg_tx_clk_ratio; i++) begin
                clk_txui <= #(i*tm_refclk_period/cfg_tx_clk_ratio) refclk;
                clk_txui <= #((i+0.5)*tm_refclk_period/cfg_tx_clk_ratio) !refclk;
            end
            for (real i=0; i<cfg_rx_clk_ratio; i++) begin
                clk_rxui <= #(i*tm_refclk_period/cfg_rx_clk_ratio) refclk;
                clk_rxui <= #((i+0.5)*tm_refclk_period/cfg_rx_clk_ratio) !refclk;
            end
        end
        tm_refclk = $time;
    end

    // flit clock divider
    always @(posedge clk_txui) begin
        cnt_txui--;
    end
    assign LxTXCLK = cnt_txui[1];

    always @(posedge clk_rxui) begin
        cnt_rxui--;
    end
    assign LxRXCLK = cnt_rxui[1];

    localparam CHAN = 1;

    hmc_flit_bfm #(.CHAN(CHAN)) hmc_flit_bfm_tx[num_links_c] (
        .CLK        (LxTXCLK),
        .RESET_N    (P_RST_N)
    );

    hmc_flit_bfm #(.CHAN(CHAN)) hmc_flit_bfm_rx[num_links_c] (
        .CLK        (LxRXCLK),
        .RESET_N    (P_RST_N)
    );   
    
    hmc_flit_top #(
        .num_links_c    (num_links_c),
        .num_hmc_c      (num_hmc_c)
    ) 
    hmc_flit_top (
        .REFCLKP        (REFCLKP),
        .REFCLKN        (REFCLKN),
        .P_RST_N        (P_RST_N),
        .REFCLKSEL      (1'b0),

        .hmc_flit_bfm_tx(hmc_flit_bfm_rx),
        .hmc_flit_bfm_rx(hmc_flit_bfm_tx),

        .TRST_N         (1'b0),
        .TCK            (1'b0),
        .TMS            (1'b0),
        .TDI            (1'b0),
        .TDO            (),

        .SCL            (1'b0),
        .SDA            (SDA),

        .CUB            (3'b0),
        .REFCLK_BOOT    (2'b0),

        .EXTRESTP       (),
        .EXTRESTN       (),
        .EXTRESBP       (),
        .EXTRESBN       ()

    );

    mailbox#(cls_cad)   mb_tx_cad[num_links_c];
    mailbox#(cls_pkt)   mb_tx_pkt[num_links_c];
    pkt_analysis_port#() rx_pkt_port[num_links_c];
    pkt_analysis_port#() tx_pkt_port[num_links_c];

    mailbox#(cls_pkt)   mb_err2driver[num_links_c];
    mailbox#(cls_pkt)   mb_driver2err[num_links_c];

    mailbox#(cls_pkt)   mb_err2retry[num_links_c];
    mailbox#(cls_pkt)   mb_retry2err[num_links_c];

    mailbox#(cls_pkt)   mb_flow2retry[num_links_c];
    mailbox#(cls_pkt)   mb_retry2flow[num_links_c];

    mailbox#(cls_pkt)   mb_chk2flow[num_links_c];
    mailbox#(cls_pkt)   mb_flow2chk[num_links_c];
    
    hmc_err_inj         hmc_err_inj[num_links_c] ();
    hmc_retry           hmc_retry[num_links_c] ();
    hmc_flow_ctrl       hmc_flow_ctrl[num_links_c] ();
    hmc_cad2pkt         arr_hm[num_links_c] ();

    // link monitors
    hmc_perf_monitor                     hmc_rtc_monitor[num_links_c] ();
    hmc_pkt_monitor#(hmc_flit_bfm_t)     hmc_pkt_mon_tx[num_links_c];
    hmc_pkt_monitor#(hmc_flit_bfm_t)     hmc_pkt_mon_rx[num_links_c];
    pkt_analysis_port#()                 mb_req_pkt[num_links_c];
    pkt_analysis_port#()                 mb_rsp_pkt[num_links_c];

    // monitor coverage
    pkt_analysis_port#()   mb_req_pkt_err_cov[num_links_c];
    pkt_analysis_port#()   mb_rsp_pkt_err_cov[num_links_c];

    cls_fi              tx_vif[num_links_c];
    cls_fi              rx_vif[num_links_c];
    
    // scoreboard
    hmc_mem             hmc_mem[num_hmc_c]();
    hmc_rsp_chk         hmc_rsp_chk[num_links_c];

    virtual hmc_mem           hmc_mem_if[num_hmc_c]         = hmc_mem;
    bit [2:0]                 hmc_mem_cid[byte]; // associative array maps cube id to the index in hmc_mem_if
    virtual hmc_pkt_driver    hmc_pkt_driver_if[num_links_c];
    virtual hmc_err_inj       hmc_err_inj_if[num_links_c]   = hmc_err_inj;
    virtual hmc_retry         hmc_retry_if[num_links_c]     = hmc_retry;
    virtual hmc_flow_ctrl     hmc_flow_ctrl_if[num_links_c] = hmc_flow_ctrl;
    virtual hmc_cad2pkt       arr_hm_if[num_links_c]        = arr_hm;
    virtual hmc_cov           hmc_cov_if[num_links_c];
    virtual hmc_perf_monitor  hmc_rtc_monitor_if[num_links_c]     = hmc_rtc_monitor;

    cls_link_cfg        link_cfg[num_links_c]; // array of configuration objects
    cls_cube_cfg        cube_cfg[num_hmc_c]; // array of configuration objects

    for (genvar i=0; i<num_hmc_c; i++) begin : gen_hmc
        initial begin
            hmc_mem_cid[i]      = i;
            hmc_mem_if[i]       = hmc_mem[i];

            cube_cfg[i]         = new();
            cube_cfg[i].cfg_cid = i;

            // initialize and pass handle to the cube_cfg object
            hmc_mem[i].cube_cfg = cube_cfg[i];
        end
    end

    for (genvar i=0; i<num_links_c; i++) begin : gen_links

        hmc_pkt_driver      hmc_pkt_driver();
        hmc_cov             hmc_cov();
        
        initial begin
            hmc_rsp_chk[i]        = new();
            hmc_pkt_mon_tx[i]     = new();
            hmc_pkt_mon_rx[i]     = new();

            // assign virtual interface handles
            hmc_pkt_driver_if[i]  = hmc_pkt_driver;
            hmc_cov_if[i]         = hmc_cov;

            // connect mailboxes to hmc_pkt_driver
            mb_driver2err[i] = new(1);
            mb_err2driver[i] = new(1);
            hmc_pkt_driver.mb_tx_pkt = mb_err2driver[i];
            hmc_pkt_driver.mb_rx_pkt = mb_driver2err[i];

            // connect mailboxes to hmc_err_inj
            mb_err2retry[i] = new(1);
            mb_retry2err[i] = new(1);
            hmc_err_inj[i].mb_tx_pkt_in  = mb_retry2err[i];
            hmc_err_inj[i].mb_tx_pkt_out = mb_err2driver[i];
            hmc_err_inj[i].mb_rx_pkt_in  = mb_driver2err[i];
            hmc_err_inj[i].mb_rx_pkt_out = mb_err2retry[i];

            // connect mailboxes to hmc_retry
            mb_retry2flow[i] = new(1);
            mb_flow2retry[i] = new(1);
            hmc_retry[i].mb_tx_pkt_in  = mb_flow2retry[i];
            hmc_retry[i].mb_tx_pkt_out = mb_retry2err[i];
            hmc_retry[i].mb_rx_pkt_in  = mb_err2retry[i];
            hmc_retry[i].mb_rx_pkt_out = mb_retry2flow[i];

            // connect mailboxes to hmc_flow_ctrl
            mb_tx_pkt[i] = new(1);
            mb_chk2flow[i] = new(1);
            mb_flow2chk[i] = new(1);
            hmc_flow_ctrl[i].mb_tx_pkt_in  = mb_chk2flow[i];
            hmc_flow_ctrl[i].mb_tx_pkt_out = mb_flow2retry[i];
            hmc_flow_ctrl[i].mb_rx_pkt_in  = mb_retry2flow[i];
            hmc_flow_ctrl[i].mb_rx_pkt_out = mb_flow2chk[i];

            // connect mailboxes to hmc_pkt_monitor
            mb_req_pkt[i] = new();
            mb_rsp_pkt[i] = new();
            hmc_pkt_mon_tx[i].mb_pkt = mb_req_pkt[i];
            hmc_pkt_mon_rx[i].mb_pkt = mb_rsp_pkt[i];
            hmc_pkt_mon_tx[i].flit_bfm = hmc_flit_bfm_tx[i];
            hmc_pkt_mon_rx[i].flit_bfm = hmc_flit_bfm_rx[i];

            // connect mailbox to hmc_cov
            hmc_cov.mb_req_pkt_cov = mb_req_pkt[i];
            hmc_cov.mb_rsp_pkt_cov = mb_rsp_pkt[i];
            hmc_cov.mb_req_pkt_err_cov = mb_req_pkt_err_cov[i];
            hmc_cov.mb_rsp_pkt_err_cov = mb_rsp_pkt_err_cov[i];

            // connect mailboxes to hmc_err_inj
            mb_req_pkt_err_cov[i] = new();
            mb_rsp_pkt_err_cov[i] = new();
            hmc_err_inj[i].mb_req_pkt_err_cov = mb_req_pkt_err_cov[i];
            hmc_err_inj[i].mb_rsp_pkt_err_cov = mb_rsp_pkt_err_cov[i];

            // connect mailbox to hmc_rsp_chk
            wait (hmc_mem_if[0] != null);
            hmc_rsp_chk[i].hmc_mem_if     = hmc_mem_if;
            hmc_rsp_chk[i].hmc_mem_cid    = hmc_mem_cid;
            hmc_rsp_chk[i].mb_req_pkt_in  = mb_tx_pkt[i];
            hmc_rsp_chk[i].mb_req_pkt_out = mb_chk2flow[i];
            hmc_rsp_chk[i].mb_rsp_pkt     = mb_flow2chk[i];
            rx_pkt_port[i] = new();
            tx_pkt_port[i] = new();
            hmc_rsp_chk[i].rsp_pkt_port   = rx_pkt_port[i];
            hmc_rsp_chk[i].req_pkt_port   = tx_pkt_port[i];
            hmc_rtc_monitor[i].req_pkt_port = mb_req_pkt[i];
            hmc_rtc_monitor[i].rsp_pkt_port = mb_rsp_pkt[i];

            // connect mailbox to arr_hm
            arr_hm[i].mb_tx_pkt_out       = mb_tx_pkt[i];
            arr_hm[i].cube_cfg            = cube_cfg[0]; // cad objects do not have a cube number 

            // connect virtual interaces to hmc_serdes
            tx_vif[i]        = new();
            rx_vif[i]        = new();
            tx_vif[i].fi     = hmc_flit_bfm_tx[i]; // assign interface to virtual interface handles
            rx_vif[i].fi     = hmc_flit_bfm_rx[i]; // assign interface to virtual interface handles
            hmc_pkt_driver.tx_fi = tx_vif[i];
            hmc_pkt_driver.rx_fi = rx_vif[i];

            // configure
            hmc_pkt_driver.cfg_host_link  = 0;
            hmc_pkt_mon_tx[i].cfg_host_link = 1; // sending requests
            hmc_pkt_mon_rx[i].cfg_host_link = 0; // receiving responses
            hmc_pkt_mon_tx[i].cfg_info_msg  = 1;
            hmc_pkt_mon_rx[i].cfg_info_msg  = 1;
            //hmc_rtc_monitor[i].cfg_info_msg   = 1;
            hmc_rtc_monitor[i].cfg_info_msg   = 0; // TIE::ADG make it default to 0.
            hmc_rtc_monitor[i].cfg_str_id     = $sformatf("LINK%1d", i);         
            
            hmc_flit_bfm_tx[i].cfg_tx_en     = 1;
            hmc_flit_bfm_rx[i].cfg_rx_en     = 1;
            link_cfg[i] = new();
            link_cfg[i].cfg_link_id       = i;
            link_cfg[i].cfg_host_mode     = 2'h3;

            // initialize and pass handle to the link_cfg object
            hmc_err_inj[i].link_cfg   = link_cfg[i];
            hmc_retry[i].link_cfg     = link_cfg[i];
            hmc_flow_ctrl[i].link_cfg = link_cfg[i];
            hmc_rsp_chk[i].link_cfg   = link_cfg[i];

            assert_connection_finished: assert ($time == 0) else
                $error("Link %d interconnect did not complete at time 0", i);
        end

        final begin
            assert_all_rsp: assert (hmc_rsp_chk[i].req_pkt_q.size() == 0) else 
                $error("TB: Test ended while waiting for %1d responses", hmc_rsp_chk[i].req_pkt_q.size());

/*
            assert_tx_token_match: assert(hmc_flow_ctrl[i].sts_tx_tokens == hmc_flit_top.link_cfg[i].cfg_tokens) else
                $error("TB: Host has %1d tokens, expected %1d", hmc_flow_ctrl[i].sts_tx_tokens, hmc_flit_top.link_cfg[i].cfg_tokens);

            assert_rx_token_match: assert(hmc_flit_top.hmc_flow_ctrl[i].sts_tx_tokens == link_cfg[i].cfg_tokens) else
                $error("TB: DUT has %1d tokens, expected %1d", hmc_flit_top.hmc_flow_ctrl[i].sts_tx_tokens, link_cfg[i].cfg_tokens);
*/
            if(!link_cfg[i].cfg_rsp_open_loop) begin
            assert_tx_token_match: assert(hmc_flow_ctrl[i].sts_tx_tokens == hmc_flit_top.link_cfg[i].cfg_tokens) else
                $error("%m LINK%0d: Host has %1d tokens, expected %1d", i, hmc_flow_ctrl[i].sts_tx_tokens, hmc_flit_top.link_cfg[i].cfg_tokens);
            end
            if(!link_cfg[i].cfg_tail_rtc_dsbl) begin
            assert_rx_token_match: assert(hmc_flit_top.hmc_flow_ctrl[i].sts_tx_tokens == link_cfg[i].cfg_tokens) else
                $error("%m LINK%0d: DUT has %1d tokens, expected %1d", i, hmc_flit_top.hmc_flow_ctrl[i].sts_tx_tokens, link_cfg[i].cfg_tokens);
            end
        end
    end

    always @(posedge P_RST_N) begin

        // requirement: each link must be given a valid configuration prior to reset deassertion
        if (P_RST_N) begin
            foreach (cube_cfg[i]) begin
                cube_warmrst(i);
            end
            // delete memory contents when cold reset
            foreach (hmc_mem_if[i]) begin    // TIE::ADG added to clear mem when cold reset
                hmc_mem_if[i].mem.delete();
            end
        end
    end

    // reset a Cube and all links with matching Cube ID
    function automatic void cube_warmrst(int i); // i = cube_num, j = link_num
        $display("%t %m: Cube %0d Warm Reset", $realtime, i);
        foreach (link_cfg[j]) begin
            if (link_cfg[j].cfg_cid == cube_cfg[i].cfg_cid) begin
                $display("%t %m : Link %0d Warm Reset connected to Cube: %0d with Cube ID: %0d", $realtime, j, i, link_cfg[j].cfg_cid);
                hmc_rsp_chk[i].run_reset();
                hmc_flow_ctrl_if[j].run_reset();
                hmc_retry_if[j].run_reset();
                hmc_rtc_monitor_if[j].run_reset();
                arr_hm_if[j].run_reset(); 
            end
        end
    endfunction : cube_warmrst

    // Task: wait_for_idle
    //
    // wait until there is nothing to do
    task automatic wait_for_idle(int link_num);
        hmc_rsp_chk[link_num].wait_for_idle();
        hmc_flow_ctrl_if[link_num].wait_for_idle();
        hmc_retry_if[link_num].wait_for_idle();
        hmc_flit_top.wait_for_idle(link_num);
    endtask

    function automatic void set_config(cls_link_cfg cfg, int link_num);
        var cls_link_cfg bfm_link_cfg;

        // Set tb to be pass through
        cfg.cfg_host_mode = 2'h3;
        link_cfg[link_num] = cfg;

        // todo: remove: do not allow tb to send bad traffic
        link_cfg[link_num].cfg_tx_rl_lim = 0;
        
        // Setup individual components
        hmc_pkt_driver_if[link_num].cfg_check_pkt = cfg.cfg_check_pkt;
        hmc_err_inj_if[link_num].link_cfg = cfg;
        hmc_retry_if[link_num].link_cfg = cfg;
        hmc_flow_ctrl_if[link_num].link_cfg = cfg;
        hmc_cov_if[link_num].link_cfg = cfg;
        // hmc_cov_if[link_num].sample();
        hmc_rtc_monitor_if[link_num].link_cfg = cfg;


        // Clone tb config for bfm config
        bfm_link_cfg = new cfg; // shallow copy
        //bfm_link_cfg.copy(cfg);

        // Make each end of the serdes link match
        bfm_link_cfg.cfg_rx_clk_ratio = cfg.cfg_tx_clk_ratio;
        bfm_link_cfg.cfg_tx_clk_ratio = cfg.cfg_rx_clk_ratio;
        bfm_link_cfg.cfg_half_link_mode_tx = cfg.cfg_half_link_mode_rx;
        bfm_link_cfg.cfg_half_link_mode_rx = cfg.cfg_half_link_mode_tx;
        bfm_link_cfg.cfg_lane_reverse = cfg.cfg_tx_lane_reverse;
        bfm_link_cfg.cfg_tx_lane_reverse = cfg.cfg_lane_reverse;        
        bfm_link_cfg.cfg_host_mode = 2'h1;
        if(cfg.cfg_rsp_open_loop) begin
            bfm_link_cfg.cfg_rsp_open_loop = 1;
            bfm_link_cfg.cfg_tail_rtc_dsbl = 0;
            cfg.cfg_tail_rtc_dsbl = 1; 
            cfg.cfg_rsp_open_loop = 0;
        end
        
        bfm_link_cfg.cfg_host_mode = 2'h1;
        
        // reverse token count at the other end of the link
        if (cfg.cfg_tokens_expected) begin
            bfm_link_cfg.cfg_tokens          = cfg.cfg_tokens_expected;
            bfm_link_cfg.cfg_tokens_expected = cfg.cfg_tokens;
        end
        // Push config down to bfm
        hmc_flit_top.set_config(bfm_link_cfg, link_num);
    endfunction : set_config
    
    function automatic void set_cube_config(cls_cube_cfg cfg, int cube_num);
        var cls_cube_cfg bfm_cube_cfg;

        cube_cfg[cube_num] = cfg;

        // assign cube_cfg object to objects that use it
        hmc_mem_if[cube_num].cube_cfg = cfg;

        // update the map of cube IDs 
        hmc_mem_cid.delete(); // delete all elements
        foreach (hmc_mem_if[i])
            hmc_mem_cid[hmc_mem_if[i].cube_cfg.cfg_cid] = i;

        // push cube ID map to objects that use it
        foreach (hmc_rsp_chk[i]) begin
            hmc_rsp_chk[i].hmc_mem_cid = hmc_mem_cid;
            arr_hm_if[i].cube_cfg = cube_cfg[0]; // cad objects do not have a cube number 
        end
        
        // Clone tb config for bfm config
        bfm_cube_cfg = new cfg; // shallow copy
        hmc_flit_top.set_cube_config(bfm_cube_cfg, cube_num);

    endfunction : set_cube_config

    // instantiate tests
    simtest prg_simtest();
    subtest prg_subtest();

endmodule : `hmc_tb

`ifdef SUBTESTVH
    `include "subtest.svh"
`else
    program subtest();
        task run_py();
        endtask
        task check_py();
        endtask
    endprogram
`endif

`ifdef SIMTESTVH
`include "simtest.vh"
`else
program simtest();
    initial wait(0);
endprogram
`endif 
