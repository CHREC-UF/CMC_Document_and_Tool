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


// HMC Packet Monitor
// -A monitor is a passive entity that samples DUT signals but does not drive them. Monitors collect coverage information and perform checking

class hmc_pkt_monitor #(parameter type bfm_t = hmc_flit_bfm_t);

    pkt_analysis_port#()    mb_pkt; // get from bfm, put to mailbox
    bfm_t                   flit_bfm;

    // Group Configuration
    bit                     cfg_info_msg = 0;
    bit                     cfg_host_link = 1;
    int unsigned            link_id; 
                                           
    function new(int unsigned i=-1);
        link_id = i;
        fork
            run();
        join_none
    endfunction

    task automatic run();
        wait (
            mb_pkt       != null &&
            flit_bfm     != null
        );
        `ifdef ADG_DEBUG
               cfg_info_msg = 1;
        `endif
       
        run_mon();
    endtask : run

    // call bfm task, try_put to mailbox
    task automatic run_mon();
        var       cls_pkt pkt;
        var   cls_req_pkt req_pkt;
        var   cls_rsp_pkt rsp_pkt;

        var logic  [63:0] header;
        var logic [127:0] data[$];
        //var logic  [63:0] pkt_data[$];
        var logic  [63:0] tail;
        var   typ_rsp_cmd rsp_cmd;
        const      string str_id[2] = '{"RSP", "REQ"};

        forever begin
            flit_bfm.monitor_pkt(header, data, tail); // blocks until packet is available

            if (cfg_host_link) begin // receive request packets
                req_pkt = new();
                pkt = req_pkt;

            end else begin // receive response packets

                if ($cast(rsp_cmd, header[5:0])) begin // command is a response
                    rsp_pkt = new();
                    pkt = rsp_pkt; 
                end else begin // command is a request
                    req_pkt = new();
                    pkt = req_pkt;
                end

            end
            pkt.data = flits2phits(data);
            pkt.set_header(header);
            pkt.set_tail(tail);
            if (cfg_info_msg && header[5:0]) begin  // don't display NULL packets
                $display("%t %m %s MON[%0d]: %s", $realtime, str_id[cfg_host_link], link_id, pkt.convert2string());
                //for(int i=0; i<pkt.data.size();++i) begin
                 //$display("%t %m %s data: %h", $realtime, str_id[cfg_host_link], pkt.data[i]);                  
                //end
            end
            mb_pkt.write(pkt);
            #0;   // Wait until monitor ports can observe all FLIT issues on the same cycle
        end
            
    endtask
endclass : hmc_pkt_monitor
