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

// disables testbench monitors and enables BFM to report traffic
`timescale 1ns/1ps

module hmc_info_msg();

    generate
        for (genvar i=0; i<num_links_c; i++) begin
            initial begin
                #10ns;
                // turn off monitors in the testbench
                `hmc_tb.hmc_pkt_mon_tx[i].cfg_info_msg = 0;
                `hmc_tb.hmc_pkt_mon_rx[i].cfg_info_msg = 0;

                // turn on monitors in the bfm
                `hmc_dut.hmc_flit_top.hmc_pkt_mon_tx[i].cfg_info_msg = 1;
                `hmc_dut.hmc_flit_top.hmc_pkt_mon_rx[i].cfg_info_msg = 1;
                `hmc_dut.hmc_flit_top.hmc_flow_ctrl[i].cfg_info_msg = 1;
                `hmc_dut.hmc_flit_top.hmc_retry[i].cfg_info_msg = 1;
            end
        end
    endgenerate

endmodule
