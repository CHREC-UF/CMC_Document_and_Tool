/*
 Interface: hmc_cov

 Interface that contains covergoups
  
 About: License
 
 | DISCLAIMER OF WARRANTY
 |
 | This software code and all associated documentation, comments or other 
 | information (collectively "Software") is provided "AS IS" without 
 | warranty of any kind. MICRON TECHNOLOGY, INC. ("MTI") EXPRESSLY 
 | DISCLAIMS ALL WARRANTIES EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
 | TO, NONINFRINGEMENT OF THIRD PARTY RIGHTS, AND ANY IMPLIED WARRANTIES 
 | OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE. MTI DOES NOT 
 | WARRANT THAT THE SOFTWARE WILL MEET YOUR REQUIREMENTS, OR THAT THE 
 | OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE. 
 | FURTHERMORE, MTI DOES NOT MAKE ANY REPRESENTATIONS REGARDING THE USE OR 
 | THE RESULTS OF THE USE OF THE SOFTWARE IN TERMS OF ITS CORRECTNESS, 
 | ACCURACY, RELIABILITY, OR OTHERWISE. THE ENTIRE RISK ARISING OUT OF USE 
 | OR PERFORMANCE OF THE SOFTWARE REMAINS WITH YOU. IN NO EVENT SHALL MTI, 
 | ITS AFFILIATED COMPANIES OR THEIR SUPPLIERS BE LIABLE FOR ANY DIRECT, 
 | INDIRECT, CONSEQUENTIAL, INCIDENTAL, OR SPECIAL DAMAGES (INCLUDING, 
 | WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, BUSINESS INTERRUPTION, 
 | OR LOSS OF INFORMATION) ARISING OUT OF YOUR USE OF OR INABILITY TO USE 
 | THE SOFTWARE, EVEN IF MTI HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH 
 | DAMAGES. Because some jurisdictions prohibit the exclusion or 
 | limitation of liability for consequential or incidental damages, the 
 | above limitation may not apply to you.
 | 
 | Copyright 2013 Micron Technology, Inc. All rights reserved.
 
 */
`timescale 1ns/1ps 

interface hmc_cov;
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;
      
    // class handles are passed in via these variables
    var   cls_link_cfg link_cfg; // config class
    
    var   cls_req_pkt req_pkt;   // request packet
    var   cls_rsp_pkt rsp_pkt;   // response packet

    var   cls_req_pkt_err req_pkt_err;   // request packet
    var   cls_rsp_pkt_err rsp_pkt_err;   // response packet
    
    // mailboxes that recieve the request and response packets
    pkt_analysis_port#()    mb_req_pkt_cov;
    pkt_analysis_port#()    mb_rsp_pkt_cov;

    // analysis port that recieves the error request and response packets
    pkt_analysis_port#()    mb_req_pkt_err_cov;
    pkt_analysis_port#()    mb_rsp_pkt_err_cov;
  
    // Group: Configuration
    bit                     cfg_info_msg = 0;
    bit                     cfg_host_link = 1;

`ifdef HMC_COV //ADG:: for user not doing verification coverage.

    // VCS has a problem with this construct
    covergroup req_pkt_err_cg(string name, comment);
        // allows for capturing instance coverage information as well
        // as the aggregate - not needed if there is only one instance
        // you are capturing
        option.per_instance = 0;
        
        // maximum number of auto bins
        option.auto_bin_max = 32;
        
        // the comment string for the covergrp
        //option.comment = comment;

        // set the reporting name of the covergroup
        // option.name = name;
        
        // set the desired goal of coverage for the covergroup can be
        // set for the entire covergroup or on individual coverpoints
        //option.goal = 100;
        
        // the comment string for the covergroup type
        type_option.comment = "TYPE COMMENT HERE";
        
`ifdef MODEL_TECH
        // uses constructs that NCV cannot use
        
        // this will report individual bins for a coverpoint so you
        // can see which bins are hit and which are not
        option.get_inst_coverage = 0;
        
        // this controls how the bins are collected together for
        // coverage
        //   1 means that overlapping bins of different
        //   covergroups are combined
        //   2 means that each bin is independent and not combined but
        //   added to the number of bins
        type_option.merge_instances = 1;
        
`endif

        // cub: coverpoint req_pkt_err[req_pkt_err.cub_p];
        cub:    coverpoint req_pkt_err.err[0];
        res1:   coverpoint req_pkt_err.err[1];
        adr:    coverpoint req_pkt_err.err[2];
        tag:    coverpoint req_pkt_err.err[3];
        dln:    coverpoint req_pkt_err.err[4];
        lng:    coverpoint req_pkt_err.err[5];
        res0:   coverpoint req_pkt_err.err[6];
        cmd:    coverpoint req_pkt_err.err[7];
        crc:    coverpoint req_pkt_err.err[8];
        rtc:    coverpoint req_pkt_err.err[9];
        res:    coverpoint req_pkt_err.err[10];
        seq:    coverpoint req_pkt_err.err[11];
        frp:    coverpoint req_pkt_err.err[12];
        rrp:    coverpoint req_pkt_err.err[13];
        data:   coverpoint req_pkt_err.err[14];
        random: coverpoint req_pkt_err.err[15];
        poison: coverpoint req_pkt_err.poison;
        

        cmd_value: coverpoint req_pkt_err.header.cmd;
                
        cmd_cub:  cross cmd_value, cub;
        cmd_res1: cross cmd_value, res1;
        cmd_adr:  cross cmd_value, adr;
        cmd_tag:  cross cmd_value, tag;
        cmd_dln:  cross cmd_value, dln;
        cmd_lng:  cross cmd_value, lng;
        cmd_res0: cross cmd_value, res0;
        cmd_crc:  cross cmd_value, crc;
        cmd_rtc:  cross cmd_value, rtc;
        cmd_res:  cross cmd_value, res;
        cmd_seq:  cross cmd_value, seq;
        cmd_frp:  cross cmd_value, frp;
        cmd_rrp:  cross cmd_value, rrp;
        cmd_data: cross cmd_value, data;
        cmd_poison: cross cmd_value, poison;
        x_cmd_all_err: cross cmd_value, dln, seq, crc, poison;
                
    endgroup

    // VCS has a problem with this construct
    covergroup rsp_pkt_err_cg(string name, comment);
        // allows for capturing instance coverage information as well
        // as the aggregate - not needed if there is only one instance
        // you are capturing
        option.per_instance = 0;
        
        // maximum number of auto bins
        option.auto_bin_max = 32;
        
        // the comment string for the covergroup
        //option.comment = comment;

        // set the reporting name of the covergroup
        // option.name = name;
        
        // set the desired goal of coverage for the covergroup can be
        // set for the entire covergroup or on individual coverpoints
        //option.goal = 100;
        
        // the comment string for the covergroup type
        type_option.comment = "TYPE COMMENT HERE";
        
`ifdef MODEL_TECH
        // uses constructs that NCV cannot use
        
        // this will report individual bins for a coverpoint so you
        // can see which bins are hit and which are not
        option.get_inst_coverage = 0;
        
        // this controls how the bins are collected together for
        // coverage
        //   1 means that overlapping bins of different
        //   covergroups are combined
        //   2 means that each bin is independent and not combined but
        //   added to the number of bins
        type_option.merge_instances = 1;
        
`endif
        
        res1:    coverpoint rsp_pkt_err.err[0];
        tag:     coverpoint rsp_pkt_err.err[2];
        dln:     coverpoint rsp_pkt_err.err[3];
        lng:     coverpoint rsp_pkt_err.err[4];
        res0:    coverpoint rsp_pkt_err.err[5];
        cmd:     coverpoint rsp_pkt_err.err[6];
        crc:     coverpoint rsp_pkt_err.err[7];
        rtc:     coverpoint rsp_pkt_err.err[8];
        errstat: coverpoint rsp_pkt_err.err[9];
        dinv:    coverpoint rsp_pkt_err.err[10];
        seq:     coverpoint rsp_pkt_err.err[11];
        rrp:     coverpoint rsp_pkt_err.err[12];
        data:    coverpoint rsp_pkt_err.err[13];
        err:     coverpoint rsp_pkt_err.err[14];
        poison:  coverpoint rsp_pkt_err.poison;

        cmd_value: coverpoint rsp_pkt_err.header.cmd;

        cmd_res1:    cross cmd_value, res1;
        cmd_tag:     cross cmd_value, tag;
        cmd_dln:     cross cmd_value, dln;
        cmd_lng:     cross cmd_value, lng;
        cmd_res0:    cross cmd_value, res0;
        cmd_crc:     cross cmd_value, crc;
        cmd_rtc:     cross cmd_value, rtc;
        cmd_errstat: cross cmd_value, errstat;
        cmd_dinv:    cross cmd_value, dinv;
        cmd_seq:     cross cmd_value, seq;
        cmd_rrp:     cross cmd_value, rrp;
        cmd_data:    cross cmd_value, data;
        cmd_err:     cross cmd_value, err;
        cmd_poison: cross cmd_value, poison;
        x_cmd_all_err: cross cmd_value, dln, seq, crc, poison;

        
    endgroup
    
    // covergroup for request packets
    covergroup req_cg(string name, comment);
        // allows for capturing instance coverage information as well
        // as the aggregate - not needed if there is only one instance
        // you are capturing
        option.per_instance = 1;

        // maximum number of auto bins
        option.auto_bin_max = 32;

        // the comment string for the covergroup
        option.comment = comment;

        // set the reporting name of the covergroup
        option.name = name;

        // set the desired goal of coverage for the covergroup can be
        // set for the entire covergroup or on individual coverpoints
        option.goal = 100;

        `ifdef MODEL_TECH
        // uses constructs that NCV cannot use       
        option.get_inst_coverage = 1;
        type_option.merge_instances = 1;
        `endif

        // HEADER
        cub_cp: coverpoint req_pkt.header.cub;
        // TODO: is SLID also a reserved field instead of SLID in HEADER?
        res1_cp: coverpoint req_pkt.header.res1;        
        // TODO: review these bins with team

        adr_cp: coverpoint req_pkt.header.adr {
            ignore_bins low_ignore = {[0:15]};
            ignore_bins high_ignore = {[2**32:$]};
            bins lowest_adr = {16};
            wildcard bins _b00 = {34'b?????????????????????????????????1};
            wildcard bins _b01 = {34'b????????????????????????????????1?};
            wildcard bins _b02 = {34'b???????????????????????????????1??};
            wildcard bins _b03 = {34'b??????????????????????????????1???};
            wildcard bins _b04 = {34'b?????????????????????????????1????};
            wildcard bins _b05 = {34'b????????????????????????????1?????};
            wildcard bins _b06 = {34'b???????????????????????????1??????};
            wildcard bins _b07 = {34'b??????????????????????????1???????};
            wildcard bins _b08 = {34'b?????????????????????????1????????};
            wildcard bins _b09 = {34'b????????????????????????1?????????};            
            wildcard bins _b10 = {34'b???????????????????????1??????????};            
            wildcard bins _b11 = {34'b??????????????????????1???????????};
            wildcard bins _b12 = {34'b?????????????????????1????????????};
            wildcard bins _b13 = {34'b????????????????????1?????????????};
            wildcard bins _b14 = {34'b???????????????????1??????????????};
            wildcard bins _b15 = {34'b??????????????????1???????????????};
            wildcard bins _b16 = {34'b?????????????????1????????????????};
            wildcard bins _b17 = {34'b????????????????1?????????????????};
            wildcard bins _b18 = {34'b???????????????1??????????????????};
            wildcard bins _b19 = {34'b??????????????1???????????????????};
            wildcard bins _b20 = {34'b?????????????1????????????????????};
            wildcard bins _b21 = {34'b????????????1?????????????????????};
            wildcard bins _b22 = {34'b???????????1??????????????????????};
            wildcard bins _b23 = {34'b??????????1???????????????????????};
            wildcard bins _b24 = {34'b?????????1????????????????????????};
            wildcard bins _b25 = {34'b????????1?????????????????????????};
            wildcard bins _b26 = {34'b???????1??????????????????????????};
            wildcard bins _b27 = {34'b??????1???????????????????????????};
            wildcard bins _b28 = {34'b?????1????????????????????????????};
            wildcard bins _b29 = {34'b????1?????????????????????????????};
            wildcard bins _b30 = {34'b???1??????????????????????????????};
            wildcard bins _b31 = {34'b??1???????????????????????????????};


        `ifdef MODEL_TECH
            // NCV has the error: ncvlog: *E,EHTBCG The wildcard bin
            // definition creates more than 2**20 non-contiguous
            // values.            
            wildcard ignore_bins _b32 = {34'b?1????????????????????????????????};
            wildcard ignore_bins _b33 = {34'b1?????????????????????????????????};           
        `endif
                      
            // NCV has the error:
            // ncelab: *E,CUVUSB (./env/hmc_cov.sv,133|37):
            // Unsupported expression used in the bin range definition
            // of coverpoint greater than 32 bits.
            // bins highest_adr = {2**32};
            // bins exp_two_04_to_11 = {[2**4:2**11]};
            // bins exp_two_11_to_18 = {[2**11:2**18]};
            // bins exp_two_18_to_25 = {[2**18:2**25]};
            // bins exp_two_25_to_32 = {[2**25:2**32]};
            
            bins others[] = default;
            option.auto_bin_max = 16;
        }
        // tag_cp: coverpoint req_pkt.header.tag;
        // dln_cp: coverpoint req_pkt.header.dln;
        // lng_cp: coverpoint req_pkt.header.lng;
        res0_cp: coverpoint req_pkt.header.res0;
        cmd_cp: coverpoint req_pkt.header.cmd {
            option.comment = "command";
        }
        
        // TAIL
        rtc_cp: coverpoint req_pkt.tail.rtc;
        // slid_cp: coverpoint req_pkt.tail.slid;
        res_cp: coverpoint req_pkt.tail.res;
        seq_cp: coverpoint req_pkt.tail.seq;
        // frp_cp: coverpoint req_pkt.tail.frp;
        // rrp_cp: coverpoint req_pkt.tail.rrp;
        
    endgroup

    // covergroup for response packets
    covergroup rsp_cg(string name, comment);
        // allows for capturing instance coverage information as well
        // as the aggregate - not needed if there is only one instance
        // you are capturing
        option.per_instance = 1;

        // maximum number of auto bins
        option.auto_bin_max = 32;

        // the comment string for the covergroup
        option.comment = comment;

        // set the reporting name of the covergroup
        option.name = name;

        // set the desired goal of coverage for the covergroup can be
        // set for the entire covergroup or on individual coverpoints
        option.goal = 100;

        `ifdef MODEL_TECH
        // uses constructs that NCV cannot use       
        option.get_inst_coverage = 1;
        type_option.merge_instances = 1;
        `endif

        // HEADER
        res1_cp: coverpoint rsp_pkt.header.res1;
        tag_cp: coverpoint rsp_pkt.header.tag;
        // dln_cp: coverpoint rsp_pkt.header.dln;
        // lng_cp: coverpoint rsp_pkt.header.lng;
        res0_cp: coverpoint rsp_pkt.header.res0;
        cmd_cp: coverpoint rsp_pkt.header.cmd;

        // TAIL
        // crc_cp: coverpoint rsp_pkt.tail.crc;
        rtc_cp: coverpoint rsp_pkt.tail.rtc;
        errstat_cp: coverpoint rsp_pkt.tail.errstat {
            bins no_error = {0};
            bins warnings = {1,2,5,6};
            bins dram_errors = {16,31};
            bins link_errors = {32,33,34,35};
            bins protocol_errors = {48,49};
            bins vault_critical_errors = {[96:111]};
            bins fault_errors = {[112:115], [120:127]};
            bins invalid = default;
        }
        dinv_cp: coverpoint rsp_pkt.tail.dinv;
        seq_cp: coverpoint rsp_pkt.tail.seq;
        // frp_cp: coverpoint rsp_pkt.tail.frp;
        // rrp_cp: coverpoint rsp_pkt.tail.rrp;
        
    endgroup

    // covergroup for config
    covergroup link_cfg_cg(string comment, name);
        
        // allows for capturing instance coverage information as well
        // as the aggregate - not needed if there is only one instance
        // you are capturing
        option.per_instance = 1;
        
        // maximum number of auto bins
        option.auto_bin_max = 32;
        
        // the comment string for the covergroup
        option.comment = comment;

        // set the reporting name of the covergroup
        option.name = name;
        
        // set the desired goal of coverage for the covergroup can be
        // set for the entire covergroup or on individual coverpoints
        option.goal = 100;
        
        // the comment string for the covergroup type
        type_option.comment = "TYPE COMMENT HERE";
        
`ifdef MODEL_TECH
        // uses constructs that NCV cannot use
        
        // this will report individual bins for a coverpoint so you
        // can see which bins are hit and which are not
        option.get_inst_coverage = 1;
        
        // this controls how the bins are collected together for
        // coverage
        //   1 means that overlapping bins of different
        //   covergroups are combined
        //   2 means that each bin is independent and not combined but
        //   added to the number of bins
        type_option.merge_instances = 1;
        
`endif
        

        cfg_host_mode: coverpoint link_cfg.cfg_host_mode {
            bins link_off = {0};
            bins host_and_source = {1};
            bins host_not_source = {2};
            bins cube_link = {3};
        }
        cfg_tokens: coverpoint link_cfg.cfg_tokens {
            // [7:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:31]};
            bins med = {[32:63]};
            bins high = {[64:$]};
            illegal_bins invalid = default;
        }
        cfg_rsp_open_loop: coverpoint link_cfg.cfg_tail_rtc_dsbl {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_tail_rtc_dsbl: coverpoint link_cfg.cfg_tail_rtc_dsbl {
            // bit
            bins _0 = {0};
            bins _1 = {1};            
        }
        cfg_retry_enb: coverpoint link_cfg.cfg_retry_enb {
            // bit
            bins _0 = {0};
            bins _1 = {1};            
        }
        
        cfg_retry_limit: coverpoint link_cfg.cfg_retry_limit {
            // [2:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:5]};
            bins high = {[6:$]};
            illegal_bins invalid = default;
        }
        
        cfg_retry_timeout: coverpoint link_cfg.cfg_retry_timeout {
            // [2:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:5]};
            bins high = {[6:$]};
            illegal_bins invalid = default;
        }           
        cfg_init_retry_txcnt: coverpoint link_cfg.cfg_init_retry_txcnt {
            // [6:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:15]};
            bins high = {[16:$]};
            illegal_bins invalid = default;
        }           
        cfg_init_retry_rxcnt: coverpoint link_cfg.cfg_init_retry_rxcnt {
            // [5:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:15]};
            bins high = {[16:$]};
            illegal_bins invalid = default;
        }           
        sts_init_retry_state: coverpoint link_cfg.sts_init_retry_state {
            // [3:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:6]};
            bins high = {[7:$]};
            illegal_bins invalid = default;
        }           
        cfg_link_id: coverpoint link_cfg.cfg_link_id {
            // [2:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:6]};
            bins high = {[7:$]};
            illegal_bins invalid = default;
        }           
        cfg_cid: coverpoint link_cfg.cfg_cid {
            // [2:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:6]};
            bins high = {[7:$]};
            illegal_bins invalid = default;
        }   
//        // TODO: what is range for this?
//        cfg_block_bits: coverpoint link_cfg.cfg_block_bits {
//            // int
//            bins _1 = {1};
//            bins _32 = {32};
//            bins _64 = {64};
//            bins _128 = {128};
//            // illegal_bins invalid = default;
//        }           
//        cfg_cube_size: coverpoint link_cfg.cfg_cube_size {
//             // [1:0] // bits
//            bins _0 = {0};
//            bins _1 = {1};
//            bins _2 = {2};
//            illegal_bins invalid = default;
//        }
//        cfg_uninit_rand: coverpoint link_cfg.cfg_uninit_rand {
//            // bit
//            bins _0 = {0};
//            bins _1 = {1};
//        }
        cfg_tx_clk_ratio: coverpoint link_cfg.cfg_tx_clk_ratio {
            // int
            bins _40 = {40};
            bins _50 = {50};
            bins _60 = {60};
            illegal_bins invalid = default;
        }                  
        cfg_rx_clk_ratio: coverpoint link_cfg.cfg_rx_clk_ratio {
            // int
            bins _40 = {40};
            bins _50 = {50};
            bins _60 = {60};
            illegal_bins invalid = default;
        }            
        cfg_pkt_rx_enb: coverpoint link_cfg.cfg_pkt_rx_enb {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_pkt_tx_enb: coverpoint link_cfg.cfg_pkt_tx_enb {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_descram_enb: coverpoint link_cfg.cfg_descram_enb {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_scram_enb: coverpoint link_cfg.cfg_scram_enb {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_lane_auto_correct: coverpoint link_cfg.cfg_lane_auto_correct {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_lane_reverse: coverpoint link_cfg.cfg_lane_reverse {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_half_link_mode_tx: coverpoint link_cfg.cfg_half_link_mode_tx {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_half_link_mode_rx: coverpoint link_cfg.cfg_half_link_mode_rx {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_hsstxoe: coverpoint link_cfg.cfg_hsstxoe {
            // [15:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:31]};
            bins med = {[32:1023]};
            bins high = {[1024:$]};
            illegal_bins invalid = default;
        }
        cfg_tx_rl_lim: coverpoint link_cfg.cfg_tx_rl_lim {
            // [7:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:7]};
            bins med = {[8:31]};
            bins high = {[32:$]};
            illegal_bins invalid = default;
        }
        cfg_send_null: coverpoint link_cfg.cfg_send_null {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_hsstx_inv: coverpoint link_cfg.cfg_hsstx_inv {
            // [15:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:31]};
            bins med = {[32:1023]};
            bins high = {[1024:$]};
            illegal_bins invalid = default;
        }
        cfg_hssrx_inv: coverpoint link_cfg.cfg_hssrx_inv {
            // [15:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:31]};
            bins med = {[32:1023]};
            bins high = {[1024:$]};
            illegal_bins invalid = default;
        }
        cfg_tx_lane_reverse: coverpoint link_cfg.cfg_tx_lane_reverse {
            // bit
            bins _0 = {0};
            bins _1 = {1};
        }
        cfg_tx_lane_delay0: coverpoint link_cfg.cfg_tx_lane_delay[0] {
            // [3:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:6]};
            bins high = {[7:$]};
            illegal_bins invalid = default;
        }           
        cfg_tx_lane_delay1: coverpoint link_cfg.cfg_tx_lane_delay[1] {
            // [3:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:6]};
            bins high = {[7:$]};
            illegal_bins invalid = default;
        }           
        cfg_tx_lane_delay2: coverpoint link_cfg.cfg_tx_lane_delay[2] {
            // [3:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:6]};
            bins high = {[7:$]};
            illegal_bins invalid = default;
        }           
        cfg_tx_lane_delay3: coverpoint link_cfg.cfg_tx_lane_delay[3] {
            // [3:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:3]};
            bins med = {[4:6]};
            bins high = {[7:$]};
            illegal_bins invalid = default;
        }
        cfg_tx_lane_delay_divisor: coverpoint link_cfg.cfg_tx_lane_delay_divisor {
            // int
            // [3:0] bits
            bins _0 = {0};
            bins _1 = {1};
            bins low = {[2:31]};
            bins med = {[32:127]};
            bins high = {[128:$]};
            illegal_bins invalid = default;
        }

    endgroup

    /*
     Instantiate the covergroups
     */

    req_cg req_cg_instance = new(
        .comment("my comment string"),
        .name($sformatf("%m"))
    );

    rsp_cg rsp_cg_instance = new(
        .comment("my comment string"),
        .name($sformatf("%m"))
    );

    link_cfg_cg link_cfg_cg_instance = new(
        .comment("my comment string"),
        .name($sformatf("%m"))
    );

    // VCS has a problem with this construct
    rsp_pkt_err_cg rsp_pkt_err_cg_instance = new(
                             .comment("my comment string"),
                             .name($sformatf("%m"))
                             );                

    // VCS has a problem with this construct
    req_pkt_err_cg req_pkt_err_cg_instance = new(
                             .comment("my comment string"),
                             .name($sformatf("%m"))
                             );
    
    /*
     Function: write_err_cov
     
     When called try to sample incoming packet - do checks before the
     sample to make sure that it really is a packet that coverage can
     be taken on.

     Parameters:
     pkt  - the packet coming in
               
     */     

    function automatic void write_err_cov(cls_pkt pkt);
        //req_pkt_err = null;
        //rsp_pkt_err = null;

        assert ($cast(req_pkt_err, pkt))
            req_pkt_err_cg_instance.sample(); // sample req_pkt_err
        else assert ($cast(rsp_pkt_err, pkt))
            rsp_pkt_err_cg_instance.sample(); // sample rsp_pkt_err
        else
            $error("failed to cast to request or response packet");

        if (cfg_info_msg) begin
            $display("%t %m COV: %s", $realtime, pkt.convert2string());
        end
        
    endfunction

    /*
     Function: write_cov
     
     When called try to sample incoming packet - do checks before the
     sample to make sure that it really is a packet that coverage can
     be taken on.

     Parameters:
     pkt  - the packet coming in
               
     */     
    function automatic void write_cov(cls_pkt pkt);
        //req_pkt = null;
        //rsp_pkt = null;

        assert ($cast(req_pkt, pkt))
            req_cg_instance.sample(); // sample req_pkt
        else assert ($cast(rsp_pkt, pkt))
            rsp_cg_instance.sample(); // sample rsp_pkt
        else
            $error("failed to cast to request or response packet");

        if (cfg_info_msg) begin
            $display("%t %m COV: %s", $realtime, pkt.convert2string());
        end
        
    endfunction

    /*
     Function: sample_cfg
     
     When called sample the config object.
     
     Parameters:
     NONE
               
     */  
    function automatic void sample_cfg();
`ifdef MODEL_TECH
        link_cfg_cg_instance.sample();       
`endif
    endfunction

    // start collecting coverage as the mailbox fills
    task check_result_req();
        cls_pkt pkt;
        
        forever begin
            mb_req_pkt_cov.get(pkt);
            write_cov(pkt);
        end
       
    endtask : check_result_req

    // start collecting coverage as the mailbox fills
    task check_result_rsp();
        cls_pkt pkt;

        forever begin
            mb_rsp_pkt_cov.get(pkt);
            write_cov(pkt);
        end
    endtask : check_result_rsp

    // sample the link_cfg object ever time the handle to the object
    // is updated
    always @ (link_cfg) begin
        sample_cfg();
    end

    // wait until the mailbox is not null before starting
    initial begin
        wait (
            mb_req_pkt_cov       != null &&
            mb_rsp_pkt_cov       != null && 
            mb_req_pkt_err_cov   != null && 
            mb_rsp_pkt_err_cov   != null
        );

        fork
            check_result_req();
            check_result_rsp();
            check_result_req_err();
            check_result_rsp_err();
        join_none
    end

    // ERROR PACKET
    
    // start collecting coverage as the mailbox fills
    task check_result_req_err();
        cls_pkt pkt;
        
        forever begin
            mb_req_pkt_err_cov.get(pkt);
            write_err_cov(pkt);
        end
       
    endtask : check_result_req_err

    // start collecting coverage as the mailbox fills
    task check_result_rsp_err();
        cls_pkt pkt;

        forever begin
            
            mb_rsp_pkt_err_cov.get(pkt);
            write_err_cov(pkt);
        end
    endtask : check_result_rsp_err

`endif   //ADG:: ifdef HMC_COV                                               

        
endinterface : hmc_cov
