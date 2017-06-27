/*
 Package: hmc_bfm_pkg
 A package to hold the configuration classes for hmc_bfm

 About: Example Use
 
 | interface hmc_retry ();
 |    import hmc_bfm_pkg::*;
 |    cls_link_cfg            link_cfg;   
 | ...
 |    $display("Reading Value of link_cfg.cfg_init_retry_rxcnt : %h", link_cfg.cfg_init_retry_rxcnt);
 
 */
`timescale 1ns/1ps

package hmc_bfm_pkg;
    import pkt_pkg::*;

    typedef virtual hmc_flit_bfm#(.CHAN(1)) hmc_flit_bfm_t;
    typedef       bit [8:0] typ_tag;
    
    `include "cls_link_cfg.svh"
    `include "cls_cube_cfg.svh"
    `include "cls_flit.svh"
    `include "hmc_rsp_gen.svh"
    `include "hmc_rsp_chk.svh"
    `include "hmc_pkt_monitor.svh"

    // wrapper class with virtual flit interface handle
    class cls_fi;
        virtual hmc_flit_bfm#(.CHAN(1)) fi;
    endclass: cls_fi

endpackage : hmc_bfm_pkg
