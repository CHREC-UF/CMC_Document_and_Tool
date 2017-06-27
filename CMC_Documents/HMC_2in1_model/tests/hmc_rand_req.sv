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
// Randomizes transaction layer request types

module hmc_rand_req();
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    // create the environment
    //hmc_bfm_env hmc_bfm_env();
    bit mode_lock;

    int seed;

    // configuration
    int unsigned read_percent;
    int unsigned num_txn;
    int nop_mean;
    int unsigned nop_std_dev;
    int unsigned single_link_only;
    int unsigned no_atomics;
    int unsigned only_atomics;
    int unsigned verbose;

    initial begin
        var int                     rsp_expected;

        if ($value$plusargs("read_percent=%d"    , read_percent     )); else read_percent    = $urandom%101;
        if ($value$plusargs("num_txn=%d"         , num_txn          )); else num_txn         = 1000;
        if ($value$plusargs("single_link_only=%d", single_link_only )); else single_link_only= 0;
        if ($value$plusargs("no_atomics=%d"      , no_atomics       )); else no_atomics= 0;
        if ($value$plusargs("only_atomics=%d"    , only_atomics     )); else only_atomics= 0;
        if ($value$plusargs("verbose=%d"         , verbose          )); else verbose= 0;
        if ($value$plusargs("nop_mean=%d"        , nop_mean         )); 
        else begin
            assert_nop_randomize:  assert (std::randomize(nop_mean) with { 
                nop_mean dist {0:=50, [1:4]:=25, [5:34]:=25}; // tRC=34ns
            }) else
                $error("nop randomize failed");
        end
        if ($value$plusargs("nop_std_dev=%d"     , nop_std_dev      )); else nop_std_dev     = nop_mean*0.2; // 20% standard deviation

        if (no_atomics > 0) 
            only_atomics = 0;

        $display("PLUSARG: read_percent     = %0d"   , read_percent     );
        $display("PLUSARG: num_txn          = %0d"   , num_txn          );
        $display("PLUSARG: nop_mean         = %0d"   , nop_mean         );
        $display("PLUSARG: nop_std_dev      = %0d"   , nop_std_dev      );
        $display("PLUSARG: single_link_only = %0d"   , single_link_only );
        $display("PLUSARG: no_atomics       = %0d"   , no_atomics       );
        $display("PLUSARG: only_atomics     = %0d"   , only_atomics     );
        $display("PLUSARG: verbose          = %0d"   , verbose          );
        seed                                = $random;


        wait (`hmc_tb.P_RST_N);
        #20ns;

        fork
            gen_pkts();
            mon_rsp(0);
            mon_rsp(1);
            mon_rsp(2);
            mon_rsp(3);
//            mon_req(0);
//            mon_req(1);
//            mon_req(2);
//            mon_req(3);
        join_any

        $display("%t %m TEST: REQUEST GENERATOR COMPLETE", $realtime);

        fork
            `hmc_tb.wait_for_idle(0);
            `hmc_tb.wait_for_idle(1);
            `hmc_tb.wait_for_idle(2);
            `hmc_tb.wait_for_idle(3);
        join

        $display("%t %m TEST: SIMULATION IS COMPLETE", $realtime);
        $finish();
    end

    task automatic gen_pkts();
        var        cls_pkt pkt;
        var    cls_req_pkt req_pkt;
        var typ_req_header header;
        var   logic [63:0] pkt_data[];
        var            int nop;
        var      bit [1:0] link;
        var      bit [2:0] cube_ids[$];
        var            int num_sent;
        var      bit [2:0] c_size[$];  //TIE::ADG
        var      bit [2:0]cube_num; //TIE::ADG

        // build a queue of cube ids
        foreach (`hmc_tb.hmc_mem_cid[i]) begin
            cube_ids.push_back(i);
        end

        for (int j = cube_ids.size() - 1; j >= 0; --j) begin
           c_size.push_back(`hmc_tb.cube_cfg[j].cfg_cube_size);
        end

        num_sent = 0; 
        for (int i=0; i<num_txn; ++i) begin
            req_pkt = new();

            assert_head_cub_randomize: assert (std::randomize(header) with {
                header.cub inside {cube_ids};
                //header.adr[4] == 0; // 32B aligned
                header.res1 == 0;
                header.adr[33:32] == 0;
                header.res0 == 0;

                only_atomics -> header.cmd dist {
                    [BWR:ADD16], [P_BWR:P_ADD16], MD_WR :/ (100-read_percent),
                    MD_RD                :/ read_percent
                };

                no_atomics -> header.cmd dist {
                    // PR: do NOT write WR16:P_WR128 -- see the comments in pkt.sv
                    [WR16:WR128], [P_WR16:P_WR128] :/ (100-read_percent),
                    [RD16:RD128] :/ read_percent
                };
                !no_atomics -> header.cmd dist {
                    [WR16:WR128],[P_WR16:P_WR128],  [BWR:P_ADD16], MD_WR :/ (100-read_percent),
                    [RD16:RD128], MD_RD                :/ read_percent
                };
                (header.cmd == MD_WR || header.cmd == MD_RD) -> !mode_lock && header.adr[14:4]  && (header.adr[21:16] < 6'h20  || header.adr[21:16] >= 6'h2B);
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

            link = header.adr[30:29];
            if (single_link_only)
                link = 0;
   
            if (header.cmd == MD_WR || header.cmd == MD_RD) begin
                assert (!mode_lock) else
                    $error("unexpected MD_WR or MD_RD command");
                mode_lock = 1; 
            end

            req_pkt.header = header;
            req_pkt.data = pkt_data;
            req_pkt.tail = 0;
            req_pkt.tail.crc = req_pkt.gen_crc();
            
            //$display("%t %m ADG TEST TX (link %0d): waiting on mb_tx_pkt: %s", $realtime, link, req_pkt.convert2string());
            `hmc_tb.mb_tx_pkt[link].put(req_pkt); 
            if (verbose)
                $display("%t %m ADG TEST TX (link %0d): got mb_tx_pkt, sent (%d/%d): %s", $realtime, link, num_sent, num_txn, req_pkt.convert2string());
            num_sent++;

            // LRM 9.4.1: If the delay expression evaluates to a negative value, 
            // it shall be interpreted as a twos-complement unsigned integer of the same size as a time variable.
            nop = $dist_normal(seed, nop_mean, nop_std_dev); // normal distribution of delays between commands
            if (nop > 0)
                #( nop ); 

        end

    endtask

    task automatic mon_rsp(input bit [1:0] link);
        var        cls_pkt pkt;
        var typ_rsp_header header;

        forever begin
            case (link)
                0: `hmc_tb.rx_pkt_port[0].get(pkt);
                1: `hmc_tb.rx_pkt_port[1].get(pkt);
                2: `hmc_tb.rx_pkt_port[2].get(pkt);
                3: `hmc_tb.rx_pkt_port[3].get(pkt);
            endcase
            $display("%t %m ADG RSP TEST: link %d response: %s", $realtime, link, pkt.convert2string());

            header = pkt.get_header();
            if (header.cmd == MD_WR_RS || header.cmd == MD_RD_RS) begin
                mode_lock = 0;
                $display("%t %m TEST: %s recieved on link %d with tag %h", $realtime, header.cmd.name(), link, header.tag);
            end
            
        end
    endtask

    task automatic mon_req(input bit [1:0] link);
        var        cls_pkt pkt;

        forever begin
            case (link)
                0: `hmc_tb.tx_pkt_port[0].get(pkt);
                1: `hmc_tb.tx_pkt_port[1].get(pkt);
                2: `hmc_tb.tx_pkt_port[2].get(pkt);
                3: `hmc_tb.tx_pkt_port[3].get(pkt);
            endcase
            $display("%t %m TEST: link %d request: %s", $realtime, link, pkt.convert2string());

        end
    endtask

endmodule
