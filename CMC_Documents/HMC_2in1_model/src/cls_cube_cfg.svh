/*
 Class: cls_cube_cfg
 A class that allows for storing and updating configuration
 information for each HMC cube.
 
 You can reference the values of this class from any of the interfaces
 that are passed a handle to the class.  The passing of the handle is
 done in the testbench and also in hmc_flit_top.sv.

 There is one class instantiation per HMC.  Each
 member can update or read the values in the class.
*/

`ifdef ADG_SEED
    int unsigned adg_seed = `ADG_SEED;
`else
    int unsigned adg_seed = $urandom(); 
`endif

class cls_cube_cfg;
    randc bit             [2:0] cfg_cid                    = 0;            // SLID[5:3]
    rand  int unsigned          cfg_block_bits             = 128*8;        // default is 1024
    rand  bit[1:0]              cfg_cube_size              = 0;            //  0 2GB 4H

    // NOTE: these settings don't have an effect in 2in1 mode
         int                    cfg_rsp_min                = 50;           // idle latency in ns
    rand int unsigned           cfg_rsp_mean               = 600;          // avg response time in ns, added to cfg_rsp_min
    rand int unsigned           cfg_rsp_std_dev            = 300;          // standard deviation of response times in ns
    // NOTE: this setting only has an effect when running in 2in1 mode
    rand int unsigned           cfg_tj                     = 85;            // 'C ; operating temperature in degrees Celcius


    constraint con_cube_cfg {
        cfg_block_bits       inside{32*8, 64*8, 128*8};
        cfg_cube_size        <= 0;
        cfg_rsp_mean         <= 600;
        cfg_rsp_std_dev      <= 300;
        cfg_tj               <= 105; //'C
    }

    function void display (string modulename="");
        var string str;

        str = {
        $sformatf("cube_cfg (%s) \n", modulename), 
        $sformatf("  cfg_cid                    = %0d\n", cfg_cid                  ),
        $sformatf("  cfg_block_bits             = %0d\n", cfg_block_bits           ),
        $sformatf("  cfg_cube_size              = %0d\n", cfg_cube_size            ),
        $sformatf("  cfg_rsp_min                = %0d\n", cfg_rsp_min              ),
        $sformatf("  cfg_rsp_mean               = %0d\n", cfg_rsp_mean             ),
        $sformatf("  cfg_rsp_std_dev            = %0d\n", cfg_rsp_std_dev          ),
        $sformatf("  cfg_tj                     = %0d\n", cfg_tj                   )
       };

        $display(str);        
    endfunction : display        
endclass : cls_cube_cfg
