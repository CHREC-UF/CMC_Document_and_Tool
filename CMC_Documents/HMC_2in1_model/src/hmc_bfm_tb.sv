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
// PR: if we've set this already, don't change it
//`ifndef hmc_tb
//`endif
`define hmc_tb hmc_bfm_tb

// PR: only used by cfg_info_msg 
`define hmc_dut hmc_bfm_tb.hmc_bfm0

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

       bit  cfg_info_msg  = 1;
        
    initial begin
        $timeformat(-9, 3, " ns", 12); 
        #2ms;

        assert_deadman_timer: assert (0) else
                $error("%t %m Your test is too long.  Try breaking it into smaller pieces.", $realtime);
        $finish;
    end
    string tsv_filename = "pkt_log.tsv";
    initial begin
        #15;
        if (cfg_info_msg) begin
            if ($value$plusargs("tsv_filename=%s"    , tsv_filename));
            void'(open_tsvfile(tsv_filename));
        end
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


`ifdef TWOINONE_CORRELATION
    // debug change: write tss to 0 in cube so all host links start at the same time.
    initial begin
        #1
        for (int i=0; i<num_links_c; i++) begin
            hmc_bfm0.link_cfg[i].cfg_tss = 0ns;
            hmc_bfm0.hmc_serdes_if[i].set_config(hmc_bfm0.link_cfg[i]);
        end
    end
`endif


    // bfm to model interconnect
`ifdef HMC_FLIT
    wire     [num_links_c-1:0][127:0] LxRXFLIT;
    wire     [num_links_c-1:0][127:0] LxTXFLIT;
    bit      [num_links_c-1:0]        FLITCLK;
`else //HMC_SERDES
    wire     [num_links_c-1:0][15:0] LxRXP;
    wire     [num_links_c-1:0][15:0] LxRXN;
    wire     [num_links_c-1:0][15:0] LxTXP;
    wire     [num_links_c-1:0][15:0] LxTXN;
`endif
    wire     [num_links_c-1:0]       LxRXPS;
    wire     [num_links_c-1:0]       LxTXPS;
    wire                             SDA;

    wire           [0:num_links_c-1] LxTXCLK, LxRXCLK;
    wire           [0:num_links_c-1] RESET_N;

`ifdef HMC_FLIT
    assign LxRXCLK = FLITCLK;
    assign LxTXCLK = FLITCLK;
`endif

    localparam CHAN = 1;
    hmc_flit_bfm #(.CHAN(CHAN)) hmc_flit_bfm_tx[num_links_c] (
        .CLK        (LxTXCLK),
        .RESET_N    (RESET_N)
    );

    hmc_flit_bfm #(.CHAN(CHAN)) hmc_flit_bfm_rx[num_links_c] (
        .CLK        (LxRXCLK),
        .RESET_N    (P_RST_N)
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
    pkt_analysis_port#()   mb_req_pkt[num_links_c];
    pkt_analysis_port#()   mb_rsp_pkt[num_links_c];

    // monitor coverage
    pkt_analysis_port#()   mb_req_pkt_err_cov[num_links_c];
    pkt_analysis_port#()   mb_rsp_pkt_err_cov[num_links_c];

    cls_fi              tx_vif[num_links_c];
    cls_fi              rx_vif[num_links_c];
    
    // scoreboard
    hmc_mem             hmc_mem[num_hmc_c]();
    hmc_rsp_chk         hmc_rsp_chk[num_links_c];

    // dut
    hmc_bfm #(
        .num_links_c    (num_links_c),
        .num_hmc_c      (num_hmc_c)
    ) 
    hmc_bfm0 (
`ifdef HMC_FLIT
        .LxRXFLIT       (LxRXFLIT), 
        .LxTXFLIT       (LxTXFLIT), 
        .FLITCLK        (FLITCLK),  
`else // HMC_SERDES
        .LxRXP          (LxRXP),
        .LxRXN          (LxRXN),
        .LxTXP          (LxTXP),
        .LxTXN          (LxTXN),
`endif
        .LxRXPS         (LxTXPS),
        .LxTXPS         (),
        .FERR_N         (),

        .REFCLKP        (REFCLKP),
        .REFCLKN        (REFCLKN),
        .REFCLKSEL      (1'b0),
        .P_RST_N        (P_RST_N),

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

    virtual hmc_mem         hmc_mem_if[num_hmc_c];
    bit [2:0]               hmc_mem_cid[byte]; // associative array maps cube id to the position in hmc_mem_if
    virtual hmc_serdes      hmc_serdes_if[num_links_c];
    //virtual hmc_flit_bfm    hmc_flit_bfm_tx_if[num_links_c];
    //virtual hmc_flit_bfm    hmc_flit_bfm_rx_if[num_links_c];
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
            for (int m=0; m<num_links_c; m++) begin
              link_cfg[m]         = new(); // :ADG
              link_cfg[m].cfg_link_id = m; //               
              hmc_mem[i].link_cfg[m] = link_cfg[m]; // 
            end
        end
    end

    for (genvar i=0; i<num_links_c; i++) begin : gen_links

        //modport TX (output  FLIT, HEAD, VALID, TAIL, BYPASS, QUAD, DEST, input  CLK, RESET_N, CREDIT, CMD_CREDIT);
        //modport RX (input   FLIT, HEAD, VALID, TAIL, BYPASS, QUAD, DEST, CLK, RESET_N, output CREDIT, CMD_CREDIT);
        hmc_serdes hmc_serdes (
            .REFCLKP    (REFCLKP),
            .REFCLKN    (REFCLKN),
            .P_RST_N    (P_RST_N),
`ifdef HMC_FLIT
            .LxRXFLIT   (LxTXFLIT[i]), 
            .LxTXFLIT   (LxRXFLIT[i]),
`else // HMC_SERDES
            .LxRXP      (LxTXP[i]), 
            .LxRXN      (LxTXN[i]), 
            .LxTXP      (LxRXP[i]), 
            .LxTXN      (LxRXN[i]), 
`endif
            .LxRXPS     (LxTXPS[i]),
            .LxTXPS     (), // unconnected  LxRXPS[i]),
            .LxTXCLK    (LxTXCLK[i]),
            .LxRXCLK    (LxRXCLK[i]),
            .LxRXPSOR   (|LxTXPS)
            
`ifdef TWO_IN_ONE
            // PR: this is unconnected on the host side 
            , .LINK_ACTIVE_2_IN_1 () 
`endif //TWO_IN_ONE
        );

        hmc_pkt_driver      hmc_pkt_driver ();
        hmc_cov             hmc_cov();

        int debug_fd;
        
        assign LxTXPS[i] = LxTXPS_reg[i];
        assign RESET_N[i] = P_RST_N && hmc_serdes.tx_link_active;
        
        initial begin

            /*
            debug_fd = $fopen($sformatf("retry_host_%0d.tsv", i));
            $fdisplay(debug_fd, "time\tid\ttag\tlng\tcmd\trtc\tseq\tfrp\trrp\tcrc\textra");
            */

            hmc_retry_if[i].debug_fd = debug_fd;
            hmc_err_inj_if[i].debug_fd = debug_fd;
            hmc_rsp_chk[i]        = new();
            hmc_pkt_mon_tx[i]     = new(i);
            hmc_pkt_mon_rx[i]     = new(i);

            // assign virtual interface handles
            hmc_serdes_if[i]      = hmc_serdes;
            //hmc_flit_bfm_tx_if[i] = hmc_flit_bfm_tx;
            //hmc_flit_bfm_rx_if[i] = hmc_flit_bfm_rx;
            //hmc_pkt_driver_if[i]  = hmc_pkt_driver;
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
            arr_hm[i].cube_cfg           = cube_cfg[0]; // cad objects do not have a cube number 

            // connect virtual interaces to hmc_serdes
            tx_vif[i]        = new();
            rx_vif[i]        = new();
            tx_vif[i].fi     = hmc_flit_bfm_tx[i]; // assign interface to virtual interface handles
            rx_vif[i].fi     = hmc_flit_bfm_rx[i]; // assign interface to virtual interface handles
            hmc_serdes.tx_fi = tx_vif[i];
            hmc_serdes.rx_fi = rx_vif[i];
            hmc_pkt_driver.tx_fi = tx_vif[i];
            hmc_pkt_driver.rx_fi = rx_vif[i];

            // configure
            hmc_serdes.cfg_info_msg       = 0;
            hmc_serdes.cfg_host_mode      = 2'h3;
            hmc_serdes.cfg_send_null      = 0;
            hmc_pkt_driver.cfg_host_link  = 0;
            hmc_pkt_mon_tx[i].cfg_host_link = 1; // sending requests
            hmc_pkt_mon_rx[i].cfg_host_link = 0; // receiving responses
            hmc_pkt_mon_tx[i].cfg_info_msg  = 1;
            hmc_pkt_mon_rx[i].cfg_info_msg  = 1;
            hmc_rtc_monitor[i].cfg_info_msg   = 1;
            hmc_rtc_monitor[i].cfg_str_id     = $sformatf("LINK%1d", i);         
       
            
            hmc_flit_bfm_tx[i].cfg_tx_en     = 1;
            hmc_flit_bfm_rx[i].cfg_rx_en     = 1;
            link_cfg[i] = new();
            link_cfg[i].cfg_link_id       = i;
            link_cfg[i].cfg_host_mode     = 2'h3;

            // initialize and pass handle to the link_cfg object
            hmc_serdes.set_config     (link_cfg[i]);
            //hmc_flit_bfm_tx.link_cfg  = link_cfg[i];
            //hmc_flit_bfm_rx.link_cfg  = link_cfg[i];
            //hmc_pkt_driver.link_cfg   = link_cfg[i];
            hmc_err_inj[i].link_cfg   = link_cfg[i];
            hmc_retry[i].link_cfg     = link_cfg[i];
            hmc_flow_ctrl[i].link_cfg = link_cfg[i];
            hmc_rsp_chk[i].link_cfg   = link_cfg[i];
            hmc_cov.link_cfg          = link_cfg[i];
            hmc_rtc_monitor[i].link_cfg = link_cfg[i];

`ifdef HMC_FLIT
            $display("%m: refclk_pd=%f cfg_tx_clk_ratio=%d, cfg_half_link_mode_tx=%d", REFCLK_PERIOD, link_cfg[i].cfg_tx_clk_ratio, link_cfg[i].cfg_half_link_mode_tx);
            forever #(REFCLK_PERIOD/(link_cfg[i].cfg_tx_clk_ratio / (2<<link_cfg[i].cfg_half_link_mode_tx))) FLITCLK[i] = !FLITCLK[i];
`endif

            assert_connection_finished: assert ($time == 0) else
                $error("Link %d interconnect did not complete at time 0", i);
        end // initial block

        final begin
            assert_all_rsp: assert (hmc_rsp_chk[i].req_pkt_q.size() == 0) else begin
                bit[8:0] idx;
                void'(hmc_rsp_chk[i].req_pkt_q.first(idx));
                $error("%m LINK%0d: Test ended while waiting for %1d responses", i, hmc_rsp_chk[i].req_pkt_q.size());
                $display("Waiting for response on link %d to pkt: %s", i, hmc_rsp_chk[i].req_pkt_q[idx].convert2string());
            end

            if(!link_cfg[i].cfg_rsp_open_loop) begin
                assert_tx_token_match: assert(hmc_flow_ctrl[i].sts_tx_tokens == hmc_bfm0.link_cfg[i].cfg_tokens) else
                    $error("%m LINK%0d: Host has %1d tokens, expected %1d", i, hmc_flow_ctrl[i].sts_tx_tokens, hmc_bfm0.link_cfg[i].cfg_tokens);
            end

            if(!link_cfg[i].cfg_tail_rtc_dsbl) begin
                assert_rx_token_match: assert(hmc_bfm0.hmc_flit_top.hmc_flow_ctrl[i].sts_tx_tokens == link_cfg[i].cfg_tokens) else
                    $error("%m LINK%0d: DUT has %1d tokens, expected %1d", i, hmc_bfm0.hmc_flit_top.hmc_flow_ctrl[i].sts_tx_tokens, link_cfg[i].cfg_tokens);
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
            /*
            // ceusebio: call the set_config function
            foreach (link_cfg[i]) begin
                set_config(link_cfg[i], i);
            end
            */
`ifdef TWOINONE_CORRELATION
            // for 2in1 correlation, wait for all links active
            // before issuing pkts
            wait_for_all_links_active();
`endif
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
        // PR: avoid null pointer error when we have less than 4 links
        if (link_num < num_links_c) begin
            hmc_rsp_chk[link_num].wait_for_idle();
            hmc_flow_ctrl_if[link_num].wait_for_idle();
            hmc_retry_if[link_num].wait_for_idle();
            hmc_bfm0.hmc_flit_top.wait_for_idle(link_num);
        end
    endtask

`ifdef TWOINONE_CORRELATION
    // wait for all links to be active, then set flag in hmc_cad2pkt
    task automatic wait_for_all_links_active();
        foreach (hmc_flow_ctrl_if[j]) begin
            forever begin
                if (hmc_flow_ctrl_if[j].sts_tx_tokens != hmc_bfm0.link_cfg[j].cfg_tokens) begin
                    $display ("%t %m: Waiting for link %1d to receive all tx tokens", $realtime, j);
                    #200ns;
                end else begin
                    $display ("%t %m: link %1d has all tx tokens", $realtime, j);
                    break;
                end
            end
        end
        $display("%t %m: All links have all tx tokens, enable requests", $realtime);
        // set flag in hmc_cad2pkt
        for (int j=0; j<num_links_c; j++) begin
            arr_hm_if[j].all_links_active  = 1;
        end
    endtask
`endif

    function automatic void set_config(cls_link_cfg cfg, int link_num);
        var cls_link_cfg bfm_link_cfg;

        // Set tb to be pass through
        cfg.cfg_host_mode = 2'h3;
        link_cfg[link_num] = cfg;

        // todo: remove: do not allow tb to send bad traffic
        link_cfg[link_num].cfg_tx_rl_lim = 0;
        
        // Setup individual components
        hmc_serdes_if[link_num].set_config(cfg);
        //hmc_flit_bfm_tx_if[link_num].link_cfg = cfg;
        //hmc_flit_bfm_rx_if[link_num].link_cfg = cfg;
        hmc_pkt_driver_if[link_num].cfg_check_pkt = cfg.cfg_check_pkt;
        hmc_err_inj_if[link_num].link_cfg = cfg;
        hmc_retry_if[link_num].link_cfg = cfg;
        hmc_flow_ctrl_if[link_num].link_cfg = cfg;
        hmc_cov_if[link_num].link_cfg = cfg;
        // hmc_cov_if[link_num].sample();
        hmc_rtc_monitor_if[link_num].link_cfg = cfg;
		hmc_rsp_chk[link_num].link_cfg = cfg;

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
        bfm_link_cfg.cfg_descram_enb = cfg.cfg_scram_enb;
        bfm_link_cfg.cfg_scram_enb = cfg.cfg_descram_enb;
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
              link_cfg[link_num].cfg_link_id = link_num; // 
              for (int s=0; s<num_hmc_c; s++) begin                            
                  hmc_mem_if[s].link_cfg[link_num] = link_cfg[link_num]; //TIE :: ADG set tb link config. and shallow mem as well.
              end
        // Push config down to bfm
        hmc_bfm0.set_config(bfm_link_cfg, link_num);

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
        hmc_bfm0.set_cube_config(bfm_cube_cfg, cube_num);

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
    initial begin 
        prg_subtest.run_py();
        fork
            `hmc_tb.wait_for_idle(0);
            `hmc_tb.wait_for_idle(1);
            `hmc_tb.wait_for_idle(2);
            `hmc_tb.wait_for_idle(3);
        join
        prg_subtest.check_py();
        wait(0);
    end
endprogram
`endif 
