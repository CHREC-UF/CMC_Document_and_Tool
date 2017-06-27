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

// HMC FLIT TOP
// - wrapper around all HMC core components
// - Uses FLIT interface for external communication
import hmc_bfm_pkg::*;
import pkt_pkg::*;

`ifdef TWO_IN_ONE 
    `define HMC_FLOW_CTRL_TYPE hmc_2in1_flow_ctrl
`else
    `define HMC_FLOW_CTRL_TYPE hmc_flow_ctrl
`endif

module hmc_flit_top #(
    num_links_c=4,
    num_hmc_c=1
) (
    hmc_flit_bfm        hmc_flit_bfm_tx[num_links_c],
    hmc_flit_bfm        hmc_flit_bfm_rx[num_links_c],

    // Group: Clocks & Reset
    input         REFCLKP,        // Differential Reference Clock, Positive.
    input         REFCLKN,        // Differential Reference Clock, Negative.
    input         REFCLKSEL,
    input         P_RST_N,        // Reset Pin.

    // Group: JTAG Interface
    input         TRST_N,         // Test Reset.
    input         TCK,            // Test Clock.
    input         TMS,            // Test Mode Select.
    input         TDI,            // Test Data Input.
    output        TDO,            // Test Data Output.

    // Group: I2C Interface
    input         SCL,            // Clock.
    inout         SDA,            // Data.

    // Group: Bootstrapping Pins
    input   [2:0] CUB,
    input   [1:0] REFCLK_BOOT,

    // Group: Analog Pins
    output        EXTRESTP,    // External Calibration Resistor, Top, Positive.
    output        EXTRESTN,    // External Calibration Resistor, Top, Negative.
    output        EXTRESBP,    // External Calibration Resistor, Bottom, Positive.
    output        EXTRESBN     // External Calibration Resistor, Bottom, Negative.

    // Group: Reserved Pins
    // input DNU

`ifdef TWO_IN_ONE
    , input [3:0] LINK_ACTIVE_2_IN_1
`endif //TWO_IN_ONE
);

    import pkt_pkg::cls_pkt;
    bit                refclk;
    assign              refclk = REFCLKP & ~REFCLKN;
    const int           tRST  = 20;
    realtime            tm_rst_neg;
    string fns,fclkns,str_refclkp;   //TIE::ADG debug
    int frefclk_handle; //TIE::ADG debug

    mailbox#(cls_pkt)   mb_err2driver[num_links_c];
    mailbox#(cls_pkt)   mb_driver2err[num_links_c];

    mailbox#(cls_pkt)   mb_err2retry[num_links_c];
    mailbox#(cls_pkt)   mb_retry2err[num_links_c];

    mailbox#(cls_pkt)   mb_flow2retry[num_links_c];
    mailbox#(cls_pkt)   mb_retry2flow[num_links_c];

`ifdef TWO_IN_ONE
    mailbox#(cls_pkt)   mb_retry2sysc_bad[num_links_c];
    mailbox#(cls_flit)  mb_flits2sysc[num_links_c];
    mailbox#(cls_pkt)   mb_flow2sysc[num_links_c];
    mailbox#(cls_pkt)   mb_sysc2flow[num_links_c];

    mailbox#(cls_pkt)   mb_rsp2sysc[num_links_c];
    mailbox#(cls_pkt)   mb_sysc2rsp[num_links_c];

    mailbox#(int unsigned)       mb_sysc2flow_tret[num_links_c];
    // wired from retry block to SC wrapper to stop flits in error abort mode
    wire inhibit_flit_rx[4];
    hmc_2in1#(num_links_c) hmc_sysc(.link_power_states(LINK_ACTIVE_2_IN_1), .inhibit_flit_rx(inhibit_flit_rx));

`else // regular BFM
    mailbox#(cls_pkt)   mb_flow2rsp[num_links_c];
    mailbox#(cls_pkt)   mb_rsp2flow[num_links_c];
`endif 

    hmc_err_inj         hmc_err_inj[num_links_c] ();
    hmc_retry           hmc_retry[num_links_c] ();
    `HMC_FLOW_CTRL_TYPE hmc_flow_ctrl[num_links_c] ();

`ifdef TWO_IN_ONE
    for (genvar i=0; i<num_links_c; ++i) begin : attach_inhibit_wires
        assign inhibit_flit_rx[i] = hmc_retry[i].sts_err_abort_mode;
    end
`endif

    // monitor
    hmc_pkt_monitor#(hmc_flit_bfm_t)     hmc_pkt_mon_tx[num_links_c];
    hmc_pkt_monitor#(hmc_flit_bfm_t)     hmc_pkt_mon_rx[num_links_c];
    pkt_analysis_port#()   mb_req_pkt[num_links_c];
    pkt_analysis_port#()   mb_rsp_pkt[num_links_c];

    //hmc_mem #( .num_links_c (num_links_c), .num_hmc_c (num_hmc_c))  hmc_mem[num_hmc_c] ();
    hmc_mem             hmc_mem[num_hmc_c] ();
    hmc_rsp_gen         hmc_rsp_gen[num_links_c];

    // analysis port
    pkt_analysis_port#()   mb_req_pkt_err_cov[num_links_c];
    pkt_analysis_port#()   mb_rsp_pkt_err_cov[num_links_c];
    
    cls_fi              tx_vif[num_links_c];
    cls_fi              rx_vif[num_links_c];
    
    virtual hmc_mem  #( .num_links_c (num_links_c), .num_hmc_c (num_hmc_c)) hmc_mem_if[num_hmc_c] = hmc_mem;
    bit [2:0]                    hmc_mem_cid[byte]; // associative array maps cube id to the index in hmc_mem_if
    virtual hmc_pkt_driver       hmc_pkt_driver_if[num_links_c];
    virtual hmc_err_inj          hmc_err_inj_if[num_links_c]   = hmc_err_inj;
    virtual hmc_retry            hmc_retry_if[num_links_c]     = hmc_retry;
    virtual `HMC_FLOW_CTRL_TYPE  hmc_flow_ctrl_if[num_links_c] = hmc_flow_ctrl;
    int debug_fd;

    cls_cube_cfg            cube_cfg[num_hmc_c]; // array of configuration objects
    cls_link_cfg            link_cfg[num_links_c];  // array of configuration objects

`ifdef ADG_DEBUG
    initial begin
            $display("%t %m : CUBE SEED=%0d",$realtime, adg_seed); 
    end
`endif

    for (genvar i=0; i<num_links_c; i++) begin : gen_links

        hmc_pkt_driver      hmc_pkt_driver ();

        initial begin
            hmc_rsp_gen[i]        = new(); //rsp_gen;
            hmc_pkt_mon_tx[i]     = new(i);
            hmc_pkt_mon_rx[i]     = new(i);

            /*
            debug_fd = $fopen($sformatf("retry_cube_%0d.tsv", i));
            $fdisplay(debug_fd, "time\tid\ttag\tlng\tcmd\trtc\tseq\tfrp\trrp\tcrc\textra");
            */
            hmc_retry_if[i].debug_fd = debug_fd;
            hmc_err_inj_if[i].debug_fd = debug_fd;

            // assign virtual interface handles
            hmc_pkt_driver_if[i]  = hmc_pkt_driver;
            //hmc_err_inj_if[i]     = hmc_err_inj[i];
            //hmc_retry_if[i]       = hmc_retry[i];
            //hmc_flow_ctrl_if[i]   = hmc_flow_ctrl[i];

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

            mb_req_pkt_err_cov[i] = new();
            mb_rsp_pkt_err_cov[i] = new();
            hmc_err_inj[i].mb_rsp_pkt_err_cov = mb_rsp_pkt_err_cov[i];
            hmc_err_inj[i].mb_req_pkt_err_cov = mb_req_pkt_err_cov[i];

            // connect mailboxes to hmc_retry
            mb_retry2flow[i] = new(1);
            mb_flow2retry[i] = new(1);
            hmc_retry[i].mb_tx_pkt_in  = mb_flow2retry[i];
            hmc_retry[i].mb_tx_pkt_out = mb_retry2err[i];
            hmc_retry[i].mb_rx_pkt_in  = mb_err2retry[i];
            hmc_retry[i].mb_rx_pkt_out = mb_retry2flow[i];


            // connect mailboxes to hmc_flow_ctrl
            hmc_flow_ctrl[i].mb_tx_pkt_out = mb_flow2retry[i];
            hmc_flow_ctrl[i].mb_rx_pkt_in  = mb_retry2flow[i];

            // PR: here's where the path diverges for the two in one -- the
            // regular BFM flow control gets hooked to response generator as
            // usual whereas the 2-in-1 hooks flow control to the systemC
            // wrapper and then hooks the systemC wrapper to response
            // generator


`ifdef TWO_IN_ONE
    mb_retry2sysc_bad[i]           = new(1);
    hmc_retry[i].mb_rx_bad_pkt_out = mb_retry2sysc_bad[i];
    hmc_sysc.mb_bad_req_in[i]      = mb_retry2sysc_bad[i];

    // PR: new path: retry <-> flow <-> systemC <-> rsp_gen
    mb_flits2sysc[i] = new(1);
    mb_flow2sysc[i] = new(1);
    mb_sysc2rsp[i]  = new(1);
    mb_rsp2sysc[i]  = new(1);
    mb_sysc2flow_tret[i] = new(1);

    hmc_flow_ctrl[i].mb_rx_pkt_out = mb_flow2sysc[i];
    hmc_sysc.mb_rx_pkt_in[i]       = mb_flow2sysc[i];

    hmc_sysc.mb_rx_pkt_out[i] = mb_sysc2rsp[i];
    hmc_rsp_gen[i].mb_req_pkt = mb_sysc2rsp[i]; 

    hmc_sysc.mb_rsp_in[i]     = mb_rsp2sysc[i]; 
    hmc_rsp_gen[i].mb_rsp_pkt = mb_rsp2sysc[i];

    hmc_sysc.mb_flits_from_serdes[i] = mb_flits2sysc[i]; // hooks to rx_vif[i] below

    // systemC responses to flow control; leave it unbounded
    mb_sysc2flow[i] = new();
    hmc_flow_ctrl[i].mb_tx_pkt_in  = mb_sysc2flow[i];
    hmc_sysc.mb_rsp_out[i]         = mb_sysc2flow[i];

    //
    // Hook up the systemC token return mbox to flow control 
    hmc_sysc.mb_return_tokens[i]      = mb_sysc2flow_tret[i];
    hmc_flow_ctrl[i].mb_return_tokens = mb_sysc2flow_tret[i];
`else // Regular BFM
    mb_flow2rsp[i] = new(1);
    mb_rsp2flow[i] = new(1);

    hmc_flow_ctrl[i].mb_tx_pkt_in  = mb_rsp2flow[i];
    hmc_rsp_gen[i].mb_rsp_pkt      = mb_rsp2flow[i]; // transmit response packets

    hmc_flow_ctrl[i].mb_rx_pkt_out = mb_flow2rsp[i];
    hmc_rsp_gen[i].mb_req_pkt      = mb_flow2rsp[i]; // receive request packets
`endif

            // connect mailboxes to hmc_pkt_monitor
            mb_req_pkt[i] = new();
            mb_rsp_pkt[i] = new();
            hmc_pkt_mon_tx[i].mb_pkt = mb_req_pkt[i];
            hmc_pkt_mon_rx[i].mb_pkt = mb_rsp_pkt[i];
            hmc_pkt_mon_tx[i].flit_bfm = hmc_flit_bfm_tx[i];
            hmc_pkt_mon_rx[i].flit_bfm = hmc_flit_bfm_rx[i];

            // connect mailboxes to hmc_rsp_gen
            foreach (hmc_mem_if[j])
                wait (hmc_mem_if[j] != null);
            hmc_rsp_gen[i].hmc_mem_if = hmc_mem_if;
            hmc_rsp_gen[i].hmc_mem_cid = hmc_mem_cid;


            // connect virtual interaces to hmc_pkt_driver
            tx_vif[i]        = new();
            rx_vif[i]        = new();
            tx_vif[i].fi     = hmc_flit_bfm_tx[i]; // assign interface to virtual interface handles
            rx_vif[i].fi     = hmc_flit_bfm_rx[i]; // assign interface to virtual interface handles
        `ifdef TWO_IN_ONE
            rx_vif[i].fi.mb_flits2sysc = mb_flits2sysc[i];
        `endif
            hmc_pkt_driver.tx_fi = tx_vif[i];
            hmc_pkt_driver.rx_fi = rx_vif[i];

            // configure
            //hmc_flow_ctrl[0].cfg_info_msg = 1;
            //hmc_retry[0].cfg_info_msg = 1;
            //hmc_pkt_driver.cfg_info_msg = 1;
            hmc_flit_bfm_tx[i].cfg_tx_en  = 1;
            hmc_flit_bfm_rx[i].cfg_rx_en  = 1;
            hmc_pkt_mon_rx[i].cfg_host_link = 1; // receiveing requests
            hmc_pkt_mon_tx[i].cfg_host_link = 0; // sending responses

            assert_connection_finished: assert ($time == 0) else
                $error("Link %0d interconnect did not complete at time 0", i);
        end

    end : gen_links


    // JTAG and I2C
    assert_no_jtag: assert property (@(posedge TCK) (!TRST_N || !TCK)) else
        $error("JTAG interface is not supported");

    assert_no_i2c: assert property (@(posedge SCL) (!SCL)) else
        $error("I2C interface is not supported");

    // P_RST_N has a minimum time of 20 ns
    always @(negedge P_RST_N) begin
        tm_rst_neg <= $time;

        if (!P_RST_N) begin
            $display("%t %m: Cold Reset", $realtime);
            foreach (link_cfg[i]) begin
                link_cfg[i] = new();
                link_cfg[i].cfg_link_id = i;		
                set_config(link_cfg[i], i, 1);
                `ifdef ADG_DEBUG
                       link_cfg[i].display(i);
                `endif
            end

            hmc_mem_cid.delete(); // delete all elements

            foreach (cube_cfg[i]) begin
                cube_cfg[i] = new();
                cube_cfg[i].cfg_cid = i;
                // this will re-initialize hmc_mem_cid
                set_cube_config(cube_cfg[i], i, 0);
            end
        end
    end

    // check reset connections
    always @(posedge P_RST_N) begin
        var bit connected;
        var string str_cid;

        assert_trst: assert ($time - tm_rst_neg >= tRST) else
            $error("tRST violation.  P_RST_N must be held low for %t prior to deassertion", tRST);

        assert_unique_cid: assert (hmc_mem_cid.size() == num_hmc_c) else
            $error("%t %m : Each Cube must be assigned a unique Cube ID; hmc_mem_cid.size() = %0d; num_hmc_c = %0d;",$realtime,hmc_mem_cid.size(), num_hmc_c);

        // requirement: each link must be given a valid configuration prior to reset deassertion
        if (P_RST_N) begin
            foreach (cube_cfg[i]) begin
                cube_warmrst(i);
            end

            foreach (link_cfg[j]) begin
                connected = 0;
                str_cid = "";
                foreach (cube_cfg[i]) begin
                    str_cid = $sformatf("%0d, %s", cube_cfg[i].cfg_cid, str_cid);
                    if (link_cfg[j].cfg_cid == cube_cfg[i].cfg_cid) begin
                        connected = 1;
                    end
                end
                assert_reset_connected: assert (connected) else
                    $error("%t %m Link %0d Invalid Cube ID:%0d.  Valid Cube IDs are:%s.",$realtime,j,link_cfg[j].cfg_cid, str_cid);
            end
            // delete memory contents when cold reset
            foreach (hmc_mem_if[i]) begin    // TIE::ADG clear mem when cold reset
                hmc_mem_if[i].mem.delete();
            end
        end
    end

    initial begin
        assert_num_hmc: assert (num_hmc_c > 0 && num_hmc_c <= 8) else
            $error("1 to 8 HMC devices are supported");

        assert_num_links: assert (num_links_c > 0 && num_links_c <= 8) else
            $error("1 to 8 Links are supported");
    end

    always @(refclk)begin
          if (frefclk_handle) begin 
                 $fdisplay(frefclk_handle,"%t %0d",$realtime, refclk); 
          end 
    end

    // reset a Cube and all links with matching Cube ID
    function automatic void cube_warmrst(int i); // i = cube_num, j = link_num
        $display("%t %m: Cube %0d Warm Reset", $realtime, i);
        foreach (link_cfg[j]) begin
            if (link_cfg[j].cfg_cid == cube_cfg[i].cfg_cid) begin
                //$display("%t %m CFG: Link %0d Warm Reset connected to Cube: %0d with Cube ID: %0d", $realtime, j, i, link_cfg[j].cfg_cid);
                hmc_flow_ctrl_if[j].run_reset();
                hmc_retry_if[j].run_reset();
            end
        end
    endfunction : cube_warmrst

    // Task: wait_for_idle
    //
    // wait until there is nothing to do
    task automatic wait_for_idle(int link_num);
        hmc_rsp_gen[link_num].wait_for_idle();
        hmc_flow_ctrl_if[link_num].wait_for_idle();
        hmc_retry_if[link_num].wait_for_idle();
`ifdef TWO_IN_ONE
        hmc_sysc.wait_for_idle();
`endif //TWO_IN_ONE
    endtask

    function automatic void set_config(cls_link_cfg cfg, int link_num, bit display = 0);
        
        link_cfg[link_num] = cfg;
       `ifdef ADG_DEBUG  
            display = 1;
        `endif

        if (display) begin
            //$display("Link %0d configuration:", link_num);
            cfg.display(link_num);
        end

        // TIE::ADG debug
       `ifdef ADG_DEBUG  
            foreach (hmc_mem_if[i]) begin
                hmc_mem_if[i].cfg_info_msg = 1;
                $sformat(fns, "%0d", i);
                fns = {"adg_mem_data_out",fns,".txt"};
                hmc_mem_if[i].mem_data_handle = $fopen(fns); 
            end
            fclkns = {"adg_frefclk.txt"};
            frefclk_handle = $fopen(fclkns); 
        `endif

        hmc_pkt_driver_if[link_num].cfg_check_pkt = cfg.cfg_check_pkt;
        hmc_pkt_driver_if[link_num].cfg_link_id = link_num;
        hmc_err_inj_if[link_num].link_cfg = cfg;
        hmc_retry_if[link_num].link_cfg = cfg;
        hmc_retry_if[link_num].link_cfg.cfg_link_id = link_num;
        hmc_flow_ctrl_if[link_num].link_cfg = cfg;
        hmc_rsp_gen[link_num].link_cfg = cfg;       
        foreach (hmc_mem_if[m]) begin // TIE for mode w/r
               hmc_mem_if[m].link_cfg[link_num] = cfg;
        end
`ifdef TWO_IN_ONE
        hmc_sysc.set_config(cfg);
`endif

    endfunction : set_config

    function automatic void set_cube_config(cls_cube_cfg cfg, int cube_num, bit display = 0);
        cube_cfg[cube_num] = cfg;
       `ifdef ADG_DEBUG  
            display = 1;
        `endif

        if (display) begin
            $display("Cube %0d configuration:", cube_num);
            cfg.display($sformatf("%m"));
        end

        // assign cube_cfg object to objects that use it
        hmc_mem_if[cube_num].cube_cfg = cfg;

        // update the map of cube IDs
        hmc_mem_cid[cube_cfg[cube_num].cfg_cid] = cube_num;

        for (int i=0; i<num_links_c; i++) begin
            hmc_rsp_gen[i].hmc_mem_cid = hmc_mem_cid;
            hmc_rsp_gen[i].cube_cfg = cube_cfg;
        end
`ifdef TWO_IN_ONE
            assert(num_hmc_c == 1) else $fatal("2in1 doesn't support chaining");
            hmc_sysc.set_cube_config(cfg);
`endif

    endfunction : set_cube_config

endmodule: hmc_flit_top
