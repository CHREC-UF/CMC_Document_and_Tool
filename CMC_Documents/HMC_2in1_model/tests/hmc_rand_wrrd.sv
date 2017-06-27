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
// Random Write/Read Test
// -random writes followed by random reads to the same address

module hmc_rand_wrrd();
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    // create the environment
    //hmc_bfm_env hmc_bfm_env();

    // internal signals
    int seed;

    // configuration
    int unsigned num_txn;
    int unsigned nop_mean;
    int unsigned nop_std_dev;
    int unsigned single_link_only;

    initial begin
        var int                     rsp_expected;
        
        if ($value$plusargs("num_txn=%d"         , num_txn          )); else num_txn         = 1000;
        if ($value$plusargs("single_link_only=%d", single_link_only )); else single_link_only         = 0;
        if ($value$plusargs("nop_mean=%d"        , nop_mean         )); 
        else begin
            assert_nop_randomize:  assert (std::randomize(nop_mean) with { 
                nop_mean dist {0:=50, [1:4]:=25, [5:34]:=25}; // tRC=34ns
            }) else
                $error("nop randomize failed");
        end
        if ($value$plusargs("nop_std_dev=%d"     , nop_std_dev      )); else nop_std_dev     = nop_mean*0.2; // 20% standard deviation

        $display("PLUSARG: num_txn      = %0d"   , num_txn          );
        $display("PLUSARG: nop_mean     = %0d"   , nop_mean         );
        $display("PLUSARG: nop_std_dev  = %0d"   , nop_std_dev      );
        $display("PLUSARG: single_link_only  = %0d"   , single_link_only      );
        seed = $random;

        wait (`hmc_tb.P_RST_N);
        #20; // ns

        gen_pkts();
        //mon_pkts();

        fork
            `hmc_tb.wait_for_idle(0);
            `hmc_tb.wait_for_idle(1);
            `hmc_tb.wait_for_idle(2);
            `hmc_tb.wait_for_idle(3);
        join

        $display("TEST: SIMULATION IS COMPLETE");
        $finish();
    end

    task automatic gen_pkts();
        var        cls_pkt pkt;
        var    cls_req_pkt wr_pkt, rd_pkt;
        var typ_req_header header;
        //var   typ_req_tail tail;
        var   logic [63:0] pkt_data[];
        var      int nop;
        var      bit [1:0] link;
        var      bit [2:0] cube_ids[$];
        var      bit [2:0] c_size[$];  //TIE::ADG
//        var      bit [2:0] adr_msb; //TIE::ADG
        var      bit [2:0]cube_num; //TIE::ADG

        // build a queue of cube ids
        foreach (`hmc_tb.hmc_mem_cid[i]) begin
            cube_ids.push_back(i);
        end

        //TIE::ADG 
        for (int j = cube_ids.size() - 1; j >= 0; --j) begin
           c_size.push_back(`hmc_tb.cube_cfg[j].cfg_cube_size);
        end

        for (int i=0; i<num_txn; i++) begin
            wr_pkt = new();


            assert_head_cub_randomize: assert (std::randomize(header) with {
                header.cub inside {cube_ids};
                //header.adr[4] == 0; // 32B aligned
                header.res1 == 0;
                header.adr[33:32] == 0;
                header.res0 == 0;
                header.cmd dist {[WR16:WR128]:=40, [P_WR16:P_WR128]:=40};
                //header.cmd == MD_WR -> header.adr[15:4] == 0;
                header.cmd == MD_WR -> header.adr[14:4] == 0;
                //header.cmd == MD_WR -> {header.adr[31:22] == 0 && header.adr[14:4] == 0};
                header.lng == header.cmd[3]*header.cmd[2:0] + 2; // length is specific to command encoding
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

//            assert_wr_poison_randomize: assert (wr_pkt.randomize(poison)) else
//                $error("poison randomize failed");

            pkt_data = new[header.lng*2 - 2];
            assert_data_randomize: assert (std::randomize(pkt_data) with {
                header.cmd == MD_WR -> pkt_data[1] == 0 && pkt_data[0][63:32] == 0;
            }) else 
                $error("data randomize failed");
            link = header.adr[30:29];

            if (single_link_only) 
                link=0;

            wr_pkt.header = header;
            wr_pkt.data = pkt_data;
            wr_pkt.tail = 0;
            wr_pkt.tail.crc = wr_pkt.gen_crc();
            
            // clone the write command
            rd_pkt = new wr_pkt; // shallow copy

            `hmc_tb.mb_tx_pkt[link].put(wr_pkt);


 //           assert_rd_poison_randomize: assert (rd_pkt.randomize(poison)) else
 //               $error("poison randomize failed");

            rd_pkt.header.cmd[5:3] = 3'b110; // change to read request
            if (header.cmd == MD_WR)
                rd_pkt.header.cmd = MD_RD;
            else if (header.lng == 2)
                rd_pkt.header.cmd = RD16;
            rd_pkt.header.lng = 1;
            rd_pkt.header.dln = 1;
            rd_pkt.data.delete();
            rd_pkt.tail.crc = rd_pkt.gen_crc();

            `hmc_tb.mb_tx_pkt[link].put(rd_pkt);

            // LRM 9.4.1: If the delay expression evaluates to a negative value, 
            // it shall be interpreted as a twos-complement unsigned integer of the same size as a time variable.
            nop = $dist_normal(seed, nop_mean, nop_std_dev); // normal distribution of delays between commands
            if (nop > 0)
                #( nop ); 
        end

    endtask

endmodule
