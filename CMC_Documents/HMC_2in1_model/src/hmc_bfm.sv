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

// Hybrid Memory Cube Bus Functional Model
// -Parameterized number of serial link interfaces <num_links_c>
// -JTAG and I2C interfaces not supported at this time
import hmc_bfm_pkg::*;

module hmc_bfm #(
    num_links_c=4,
    num_hmc_c=1
) (
    // Group: Link Interface
`ifdef HMC_FLIT
    input  [num_links_c-1:0][127:0] LxRXFLIT,       // Link_x, Receiver Data, Positive.
    output [num_links_c-1:0][127:0] LxTXFLIT,       // Link_x, Receiver Data, Negative.
    input  [num_links_c-1:0]        FLITCLK,     
`else //HMC_SERDES
    input  [num_links_c-1:0][15:0] LxRXP,       // Link_x, Receiver Data, Positive.
    input  [num_links_c-1:0][15:0] LxRXN,       // Link_x, Receiver Data, Negative.
    output [num_links_c-1:0][15:0] LxTXP,       // Link_x, Transmitter Data, Positive.
    output [num_links_c-1:0][15:0] LxTXN,       // Link_x, Transmitter Data, Negative.
`endif
    input  [num_links_c-1:0]       LxRXPS,      // Power State, Link 0, Receiver.
    output [num_links_c-1:0]       LxTXPS,      // Power State, Link 0, Transmitter.
    output                         FERR_N,      // Fatal Error

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
    output        EXTRESBN    // External Calibration Resistor, Bottom, Negative.

    // Group: Reserved Pins
    // input DNU

);

    import pkt_pkg::cls_pkt;

    const int           tRST  = 20e3;
    realtime            tm_rst_neg;

    cls_link_cfg        link_cfg[num_links_c];
    cls_fi              tx_vif[num_links_c];
    cls_fi              rx_vif[num_links_c];
    
    wire           [0:num_links_c-1] LxTXCLK, LxRXCLK;
    wire           [0:num_links_c-1] RESET_N;

`ifdef TWO_IN_ONE
    // PR: systemC model always has 4 links 
    wire           [3:0]             LINK_ACTIVE_2_IN_1;
`endif //TWO_IN_ONE

`ifdef HMC_FLIT
    assign LxTXCLK = FLITCLK;
    assign LxRXCLK = FLITCLK;
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

/*
    vcs: Error-[IAPC] Illegal array port connection

    hmc_serdes hmc_serdes[num_links_c] (
        .REFCLKP    (REFCLKP),
        .REFCLKN    (REFCLKN),
        .P_RST_N    (P_RST_N),
        .LxRXP      (LxRXP), 
        .LxRXN      (LxRXN), 
        .LxTXP      (LxTXP), 
        .LxTXN      (LxTXN), 
        .LxRXPS     (LxRXPS),
        .LxTXPS     (LxTXPS),
        .LxTXCLK    (LxTXCLK),
        .LxRXCLK    (LxRXCLK),
        .tx_fi      (tx_fi),
        .rx_fi      (rx_fi)
    );

    hmc_flit_bfm        hmc_flit_bfm_tx[num_links_c] (tx_fi);
    hmc_flit_bfm        hmc_flit_bfm_rx[num_links_c] (rx_fi);

    hmc_pkt_driver      hmc_pkt_driver[num_links_c] (
        .hmc_flit_bfm_tx (hmc_flit_bfm_tx),
        .hmc_flit_bfm_rx (hmc_flit_bfm_rx)
    );
*/

    hmc_flit_top #(
        .num_links_c    (num_links_c),
        .num_hmc_c      (num_hmc_c)
    )
    hmc_flit_top (
        .hmc_flit_bfm_tx      (hmc_flit_bfm_tx),
        .hmc_flit_bfm_rx      (hmc_flit_bfm_rx),

        .REFCLKP    (REFCLKP),
        .REFCLKN    (REFCLKN),
        .REFCLKSEL  (REFCLKSEL),
        .P_RST_N    (P_RST_N),

        .TRST_N     (TRST_N),
        .TCK        (TCK),
        .TMS        (TMS),
        .TDI        (TDI),
        .TDO        (TDO),

        .SCL        (SCL),
        .SDA        (SDA),
          
        .CUB        (CUB),
        .REFCLK_BOOT(REFCLK_BOOT),

        .EXTRESTP   (EXTRESTP),
        .EXTRESTN   (EXTRESTN),
        .EXTRESBP   (EXTRESBP),
        .EXTRESBN   (EXTRESBN)
        
`ifdef TWO_IN_ONE
        ,  .LINK_ACTIVE_2_IN_1(LINK_ACTIVE_2_IN_1)
`endif //TWO_IN_ONE
    );

    virtual hmc_serdes      hmc_serdes_if[num_links_c];

    for (genvar i=0; i<num_links_c; i++) begin : gen_links

        hmc_serdes hmc_serdes (
            .REFCLKP    (REFCLKP),
            .REFCLKN    (REFCLKN),
            .P_RST_N    (P_RST_N),

`ifdef HMC_FLIT
            .LxRXFLIT       (LxRXFLIT[i]),
            .LxTXFLIT       (LxTXFLIT[i]), 
`else // HMC_SERDES
            .LxRXP      (LxRXP[i]), 
            .LxRXN      (LxRXN[i]), 
            .LxTXP      (LxTXP[i]), 
            .LxTXN      (LxTXN[i]), 
`endif
            .LxRXPS     (LxRXPS[i]),
            .LxTXPS     (LxTXPS[i]),
            .LxTXCLK    (LxTXCLK[i]),
            .LxRXCLK    (LxRXCLK[i]),
            .LxRXPSOR   (|LxRXPS)
`ifdef TWO_IN_ONE
            , .LINK_ACTIVE_2_IN_1 (LINK_ACTIVE_2_IN_1[i])
`endif //TWO_IN_ONE
        );

        assign RESET_N[i] = P_RST_N && hmc_serdes.tx_link_active;

        initial begin
            // assign virtual interface handles
            hmc_serdes_if[i]     = hmc_serdes;

            // connect virtual interaces to hmc_serdes
            tx_vif[i]        = new();
            rx_vif[i]        = new();
            tx_vif[i].fi     = hmc_flit_bfm_tx[i]; // assign interface to virtual interface handles
            rx_vif[i].fi     = hmc_flit_bfm_rx[i]; // assign interface to virtual interface handles
            hmc_serdes.tx_fi = tx_vif[i];
            hmc_serdes.rx_fi = rx_vif[i];

        end // initial begin
    
    end: gen_links
    
`ifdef TWO_IN_ONE
    // PR: tie all non-active links to zero (since systemC always assumes 4 links)
    for (genvar i=num_links_c; i<4; i++) begin
        assign LINK_ACTIVE_2_IN_1[i] = 0; 
    end
`endif //TWO_IN_ONE

    initial begin 
        string filename;
`ifdef GENERATE_VPD
    `define STRINGIFY(str) `"str`"
        $swrite(filename, "debug_%s.vpd", `STRINGIFY(`GENERATE_VPD));
        $display("Writing VPD file to %s", filename);
        $vcdplusfile(filename);
        $vcdpluson();
`endif
    end

    always @(negedge P_RST_N) begin

        if (!P_RST_N) begin
            $display("%t %m: Cold Reset", $realtime);
            foreach (link_cfg[i]) begin
                link_cfg[i] = new();
                link_cfg[i].cfg_link_id = i;
                hmc_serdes_if[i].set_config(link_cfg[i]);
            end
        end
    end

    function void set_config(cls_link_cfg cfg, int link_id);
        link_cfg[link_id] = cfg;

        hmc_serdes_if[link_id].set_config(link_cfg[link_id]);

        hmc_flit_top.set_config(cfg, link_id);
    endfunction: set_config

    function void set_cube_config(cls_cube_cfg cfg, int cube_num);
        `ifdef ADG_DEBUG
               cfg.display($sformatf("%m"));
        `endif

        hmc_flit_top.set_cube_config(cfg, cube_num);
    endfunction : set_cube_config

endmodule: hmc_bfm
