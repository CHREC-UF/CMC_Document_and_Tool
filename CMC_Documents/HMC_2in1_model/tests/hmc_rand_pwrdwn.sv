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

// randomized requests with random power down on randomized links
module hmc_rand_pwrdwn();
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    // create the environment
    //hmc_bfm_env hmc_bfm_env();
    bit mode_lock;

    int seed;

    // configuration
    int unsigned read_percent;
    int unsigned num_txn;
    int unsigned txn_cnt;
    int nop_mean;
    int unsigned nop_std_dev;
    int pwrdwn_mean;
    int unsigned pwrdwn_std_dev;
    bit [3:0] dwn_links;
    bit down_mode; // flag to indicate that HMC is in self refresh

    generate
        // turn off request monitors
        for (genvar i=0; i<num_links_c; i++) begin
            initial begin #10ns; `hmc_tb.hmc_pkt_mon_tx[i].cfg_info_msg = 0; end
        end
    endgenerate

    initial begin

        if ($value$plusargs("read_percent=%d"    , read_percent     )); else read_percent    = $urandom%101;
        if ($value$plusargs("num_txn=%d"         , num_txn          )); else num_txn         = 1000;
        if ($value$plusargs("nop_mean=%d"        , nop_mean         )); 
        else begin
            assert_nop_randomize: assert (std::randomize(nop_mean) with { 
                nop_mean dist {0:=50, [1:4]:=25, [5:34]:=25}; // tRC=34ns
            }) else
                $error("nop randomize failed");
        end
        if ($value$plusargs("nop_std_dev=%d"     , nop_std_dev      )); else nop_std_dev     = nop_mean*0.2; // 20% standard deviation
        if ($value$plusargs("pwrdwn_mean=%d"     , pwrdwn_mean      )); else pwrdwn_mean     = num_txn/4; // average 4 power downs per simulation
        if ($value$plusargs("pwrdwn_std_dev=%d"  , pwrdwn_std_dev   )); else pwrdwn_std_dev  = pwrdwn_mean*0.2; // 20% standard deviation
        if ($value$plusargs("dwn_links=%d"       , dwn_links        )); //else dwn_links       = 0; // all links are active
        else begin
            assert_dwn_links_randomize: assert (std::randomize(dwn_links) with {
                &dwn_links == 0;
            }) else
                $error("dwn_links randomize failed");
        end
        assert_1_link_active: assert (&dwn_links == 0) else
            $error("at leaset one link must be active.  dwn_links='h%h", dwn_links);
        $display("PLUSARG: read_percent    = %0d"   , read_percent     );
        $display("PLUSARG: num_txn         = %0d"   , num_txn          );
        $display("PLUSARG: nop_mean        = %0d"   , nop_mean         );
        $display("PLUSARG: nop_std_dev     = %0d"   , nop_std_dev      );
        $display("PLUSARG: pwrdwn_mean     = %0d"   , pwrdwn_mean      );
        $display("PLUSARG: pwrdwn_std_dev  = %0d"   , pwrdwn_std_dev   );
        $display("PLUSARG: dwn_links       = %0h"   , dwn_links        );
        seed = $random;

        // disable links based on plusarg
        assign `hmc_tb.LxTXPS_reg = ~dwn_links;
        wait (`hmc_tb.P_RST_N);
        #20; // ns
        deassign `hmc_tb.LxTXPS_reg;

        // start the monitors
        fork
            if (!dwn_links[0]) begin 
                mon_pkts(0);
            end else begin
                $assertoff(0,`hmc_tb.hmc_bfm0.hmc_flit_top.hmc_retry[0].assert_all_pointers_returned);;
            end

            if (!dwn_links[1]) begin
                mon_pkts(1);
            end else begin
                $assertoff(0,`hmc_tb.hmc_bfm0.hmc_flit_top.hmc_retry[1].assert_all_pointers_returned);;
            end

            if (!dwn_links[2]) begin
                mon_pkts(2);
            end else begin
                $assertoff(0,`hmc_tb.hmc_bfm0.hmc_flit_top.hmc_retry[2].assert_all_pointers_returned);;
            end

            if (!dwn_links[3]) begin
                mon_pkts(3);
            end else begin
                $assertoff(0,`hmc_tb.hmc_bfm0.hmc_flit_top.hmc_retry[3].assert_all_pointers_returned);;
            end

        join_none

        for (int i = 0; i < 4; i++) begin
            if (dwn_links[i]) begin

                `hmc_tb.hmc_bfm0.link_cfg[i].cfg_tokens = 0;
                `hmc_tb.link_cfg[i].cfg_tokens = 0;
            end
        end
        
        // generate the stimulus
        fork
            if (!dwn_links[0]) gen_pkts(0);
            if (!dwn_links[1]) gen_pkts(1);
            if (!dwn_links[2]) gen_pkts(2);
            if (!dwn_links[3]) gen_pkts(3);
        join

        fork
            if (!dwn_links[0]) `hmc_tb.wait_for_idle(0);
            if (!dwn_links[1]) `hmc_tb.wait_for_idle(1);
            if (!dwn_links[2]) `hmc_tb.wait_for_idle(2);
            if (!dwn_links[3]) `hmc_tb.wait_for_idle(3);
        join

        $display("%t %m TEST: %1d transactions complete", $realtime, num_txn);
        #(100); // allow some time for retry pointer and token return
        $display("%t %m TEST: SIMULATION IS COMPLETE", $realtime);
        $finish();
    end

    task automatic gen_pkts(input bit [1:0] link);
        var        cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var typ_req_header header;
        var   logic [63:0] pkt_data[];
        var            int nop;
        //var      bit [1:0] link;
        var   int unsigned pwrdwn_nxt;
        var      bit [2:0] cube_ids[$];
        var      bit [2:0] c_size[$];  //TIE::ADG
        var      bit [2:0]cube_num; //TIE::ADG

        // build a queue of cube ids
        foreach (`hmc_tb.hmc_mem_cid[i]) begin
            cube_ids.push_back(i);
        end

        //TIE::ADG 
        for (int j = cube_ids.size() - 1; j >= 0; --j) begin
           c_size.push_back(`hmc_tb.cube_cfg[j].cfg_cube_size);
        end


        pwrdwn_nxt = $dist_normal(seed, pwrdwn_mean, pwrdwn_std_dev);

        //for (int i=0; i<num_txn; i++) begin
        while (txn_cnt < num_txn) begin
            req_pkt = new();

            assert_head_randomize: assert (std::randomize(header) with {
                header.cub inside {cube_ids};
                //header.adr[4] == 0; // 32B aligned
                //header.slid == 0;
                header.res1 == 0;
                header.adr[33:32] == 0;
                header.adr[30:29] == link;
                header.res0 == 0;
                header.cmd dist {[WR16:WR128]:=(100-read_percent), [BWR:P_ADD16]:=(100-read_percent), [RD16:RD128]:=read_percent}; //, MD_WR:=(100-read_percent), MD_RD:=read_percent};

                (header.cmd == MD_WR || header.cmd == MD_RD) -> !mode_lock && header.adr[14:4] && (header.adr[21:16] < 6'h20  || header.adr[21:16] >= 6'h24);
                (header.cmd == BWR   || header.cmd == P_BWR) -> header.adr[2:0] == 0;

                header.cmd < MD_RD -> header.lng == header.cmd[3]*header.cmd[2:0] + 2; // write packet length is specific to command encoding
                header.cmd >= MD_RD -> header.lng == 1;
                header.dln == header.lng;
                header.tag == 0;
            }) else 
                $error("packet randomize failed");

            cube_num = header.cub;
            //$display("%t %m cube_num = %d", $realtime, cube_num);
               if(c_size.size() <= 1) begin
                     if(c_size[0] == 1)
                         header.adr[33:32] = 2'b00;
                     else
                         header.adr[33:31] = 3'b000;
               end
               else begin
                     if(c_size[cube_num] == 1)
                         header.adr[33:32] = 2'b00;
                     else
                         header.adr[33:31] = 3'b000;
               end                   
              

            //assert_wr_poison_randomize: assert (req_pkt.randomize(poison)) else
            //    $error("poison randomize failed");

            pkt_data = new[header.lng*2 - 2];
            assert_data_randomize: assert (std::randomize(pkt_data) with {
                header.cmd == MD_WR -> pkt_data[1] == 0 && pkt_data[0][63:32] == 0;
                (header.cmd == DADD8 || header.cmd ==  P_DADD8) -> {pkt_data[1][63:32] == 0; pkt_data[0][63:32] == 0;}
            }) else
                $error("data randomize failed");

            if (header.cmd == MD_WR || header.cmd == MD_RD) begin
                assert (!mode_lock) else
                    $error("unexpected MD_WR or MD_RD command");
                mode_lock = 1; 
            end

            req_pkt.header = header;
            req_pkt.data = pkt_data;
            req_pkt.tail = 0;
            req_pkt.tail.crc = req_pkt.gen_crc();
            
            `hmc_tb.mb_tx_pkt[link].put(req_pkt);

            // LRM 9.4.1: If the delay expression evaluates to a negative value, 
            // it shall be interpreted as a twos-complement unsigned integer of the same size as a time variable.
            nop = $dist_normal(seed, nop_mean, nop_std_dev); // normal distribution of delays between commands
            if (nop > 0)
                #( nop ); 

            if (txn_cnt >= pwrdwn_nxt) begin
                $display ("%t %m TEST: %1d Transactions complete.  Starting Power Down sequence", $realtime, txn_cnt);
                power_down(link);
                pwrdwn_nxt = txn_cnt + $dist_normal(seed, pwrdwn_mean, pwrdwn_std_dev);
            end

            txn_cnt++;
        end

    endtask

    // waits for link idle followed by 1 or more links into and out of power down
    task automatic power_down(input bit [1:0] link);
//        var cls_link_cfg link_cfg;

        `hmc_tb.wait_for_idle(link);
        //#(100); // allow some time for retry pointer and token return
//        link_cfg = `hmc_tb.link_cfg[link];
//        link_cfg.cfg_pkt_rx_enb = 0;
//        `hmc_tb.set_config(link_cfg, link);
        `hmc_tb.LxTXPS_reg[link] = 0;

        if (!`hmc_tb.LxTXPS_reg) begin
            down_mode <= 1;
            down_mode <= #(2.2us) 0; // minimum down time
        end
        #(2.2us); // wait for minimum power down time (tPST + 3*tSS + tSME) = 80 +3*500 + 600 = 2180
        wait (!down_mode);
//        link_cfg.cfg_pkt_rx_enb = 1;
//        `hmc_tb.set_config(link_cfg, link);
        `hmc_tb.LxTXPS_reg[link] = 1;
        #(200ns); // tRXD wait for host to exit sleep mode
    endtask

    // clears the mode_lock bit when a MD_RD_RS or MD_WR_RS is observed
    task automatic mon_pkts(input bit [1:0] link);
        var        cls_pkt pkt;
        var typ_rsp_header header;

        forever begin
            case (link)
                0: `hmc_tb.rx_pkt_port[0].get(pkt);
                1: `hmc_tb.rx_pkt_port[1].get(pkt);
                2: `hmc_tb.rx_pkt_port[2].get(pkt);
                3: `hmc_tb.rx_pkt_port[3].get(pkt);
            endcase

            header = pkt.get_header();
            if (header.cmd == MD_WR_RS || header.cmd == MD_RD_RS) begin
                mode_lock = 0;
                $display("%t %m TEST: %s recieved on link %d with tag %h", $realtime, header.cmd.name(), link, header.tag);
            end
        end
    endtask


endmodule
