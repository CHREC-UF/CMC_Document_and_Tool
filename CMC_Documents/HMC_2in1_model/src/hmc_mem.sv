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

// HMC Memory
// -stores data for memory reads and writes
// -stores data for mode reads and writes
`timescale 1ns/1ps
interface hmc_mem #(
    num_links_c=4,
    num_hmc_c=1
);
    import pkg_cad::*;
    import pkt_pkg::*;

    import hmc_bfm_pkg::*;
    cls_cube_cfg            cube_cfg;

    localparam par_bnks = 1<<(par_sta_bits+par_bnk_bits);
    // Variable: mem
    //
    // associative memory array.  Stores data in mory using an address
    reg  [par_cas_bits-1:0] mem[typ_adrs];

    // Variable: cfg
    // associative configuration array.  
    // Stores the lower 16 addresses in each Target.
    // A Target is selected using address[21:16].
    reg              [31:0] cfg[bit [21:0]];

    // Group: Configuration
    bit                    cfg_info_msg  = 0;
    int mem_data_handle, num_wr, num_rd;
    var  typ_reg_addr reg_addr;
    cls_link_cfg            link_cfg[num_links_c];

    // covergroup for config cube
`ifdef HMC_COV //ADG:: for coverage analysis.
    covergroup cube_cfg_cg(string comment, name);
        
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

        
        cfg_block_bits: coverpoint cube_cfg.cfg_block_bits;
        // TODO: bins
        
        cfg_cube_size: coverpoint cube_cfg.cfg_cube_size {
            bins _4GB_8H = {0};
            bins _2GB_4H = {1};
            ignore_bins _1GB_2H = {2};
        }

    endgroup // cube_cfg

    cube_cfg_cg cube_cfg_cg_instance = new(
        .comment("my comment string"),
        .name($sformatf("%m"))
    );
`endif   //ADG:: ifdef HMC_COV                                               

    always @(cube_cfg) begin
        if (cube_cfg != null) begin 
          `ifdef HMC_COV
                 cube_cfg_cg_instance.sample();
          `endif
          `ifdef ADG_DEBUG
                 cube_cfg.display($sformatf("%m"));
                 cfg_info_msg  = 1;
                 $display("%t %m cfg_cube_id = %b;",$realtime,cube_cfg.cfg_cid);
          `endif
        end
    end
     // Registers defualt value access ADG
    always @(cube_cfg) begin
    if (cfg_info_msg == 1) $display("%t %m Configuration update",$realtime);
    cfg[22'h108000] = {19'b0,1'b0,1'b1,1'b1,1'b0,3'b001,1'b1,1'b1,1'b1,1'b0,2'b0};   // Vault Control Register
    cfg[22'h280000] = {25'b0,1'b0,1'b0,1'b0,4'b0};                                  // Global Configuration Registers
    if (cube_cfg != null) begin 
    cfg[22'h280002] = {23'b0,1'b0,2'b00,2'b00,cube_cfg.cfg_cid,1'b0};               // Bootstrap Register Status
    cfg[22'h2C0000] = {18'b0,5'b0,5'b0,cube_cfg.cfg_block_bits/512};                // Address Configuration Register
    end 
    if (link_cfg[0] != null && cube_cfg != null) begin 
    cfg[22'h000000] = {cube_cfg.cfg_cid, link_cfg[0].cfg_link_id};                     // Request Identification Register link 0 
    cfg[22'h040000] = {24'b0, link_cfg[0].cfg_tokens};                                // Input Buffer Token Count Register link 0
    cfg[22'h240000] = {1'b1,link_cfg[0].cfg_scram_enb,link_cfg[0].cfg_descram_enb,1'b1,1'b1,1'b1,1'b1,1'b1,link_cfg[0].cfg_seq_tags,link_cfg[0].cfg_rsp_open_loop,link_cfg[0].cfg_host_mode}; // Link Configuration Register link 0 
    cfg[22'h240003] = {link_cfg[0].cfg_tx_rl_lim,16'b0};                              // Link Run Length Limit Register link 0
    cfg[22'h0C0000] = {4'b0001,2'b0,link_cfg[0].cfg_init_retry_rxcnt,2'b0,link_cfg[0].cfg_init_retry_txcnt,1'b0,link_cfg[0].cfg_retry_timeout,link_cfg[0].cfg_retry_limit,link_cfg[0].cfg_retry_enb}; // Link Retry Register link 0
    end 
    if (link_cfg[1] != null && cube_cfg != null) begin 
    cfg[22'h010000] = {cube_cfg.cfg_cid, link_cfg[1].cfg_link_id};                     // Request Identification Register link 1
    cfg[22'h050000] = {24'b0, link_cfg[1].cfg_tokens};                                // Input Buffer Token Count Register link 1
    cfg[22'h250000] = {1'b1,link_cfg[1].cfg_scram_enb,link_cfg[1].cfg_descram_enb,1'b1,1'b1,1'b1,1'b1,1'b1,link_cfg[1].cfg_seq_tags,link_cfg[1].cfg_rsp_open_loop,link_cfg[1].cfg_host_mode}; // Link Configuration Register link 1 
    cfg[22'h250003] = {link_cfg[1].cfg_tx_rl_lim,16'b0};                               // Link Run Length Limit Register link 1
    cfg[22'h0D0000] = {4'b0001,2'b0,link_cfg[1].cfg_init_retry_rxcnt,2'b0,link_cfg[1].cfg_init_retry_txcnt,1'b0,link_cfg[1].cfg_retry_timeout,link_cfg[1].cfg_retry_limit,link_cfg[1].cfg_retry_enb}; // Link Retry Register link 1
    end 
    if (link_cfg[2] != null && cube_cfg != null) begin 
    cfg[22'h020000] = {cube_cfg.cfg_cid, link_cfg[2].cfg_link_id};                     // Request Identification Register link 2
    cfg[22'h060000] = {24'b0, link_cfg[2].cfg_tokens};                                // Input Buffer Token Count Register link 2
    cfg[22'h260000] = {1'b1,link_cfg[2].cfg_scram_enb,link_cfg[2].cfg_descram_enb,1'b1,1'b1,1'b1,1'b1,1'b1,link_cfg[2].cfg_seq_tags,link_cfg[2].cfg_rsp_open_loop,link_cfg[2].cfg_host_mode}; // Link Configuration Register link 2 
    cfg[22'h260003] = {link_cfg[2].cfg_tx_rl_lim,16'b0};                              // Link Run Length Limit Register link 2
    cfg[22'h0E0000] = {4'b0001,2'b0,link_cfg[2].cfg_init_retry_rxcnt,2'b0,link_cfg[2].cfg_init_retry_txcnt,1'b0,link_cfg[2].cfg_retry_timeout,link_cfg[2].cfg_retry_limit,link_cfg[2].cfg_retry_enb}; // Link Retry Register link 2
    end 
    if (link_cfg[3] != null && cube_cfg != null) begin 
    cfg[22'h030000] = {cube_cfg.cfg_cid, link_cfg[3].cfg_link_id};                     // Request Identification Register link 3
    cfg[22'h070000] = {24'b0, link_cfg[3].cfg_tokens};                                // Input Buffer Token Count Register link 3
    cfg[22'h270000] = {1'b1,link_cfg[3].cfg_scram_enb,link_cfg[3].cfg_descram_enb,1'b1,1'b1,1'b1,1'b1,1'b1,link_cfg[3].cfg_seq_tags,link_cfg[3].cfg_rsp_open_loop,link_cfg[3].cfg_host_mode}; // Link Configuration Register link 3 
    cfg[22'h270003] = {link_cfg[3].cfg_tx_rl_lim,16'b0};                               // Link Run Length Limit Register link 3
    cfg[22'h0F0000] = {4'b0001,2'b0,link_cfg[3].cfg_init_retry_rxcnt,2'b0,link_cfg[3].cfg_init_retry_txcnt,1'b0,link_cfg[3].cfg_retry_timeout,link_cfg[3].cfg_retry_limit,link_cfg[3].cfg_retry_enb}; // Link Retry Register link 3
    end 
//                 
    end // end always
//    
    function automatic [(par_cas_bits-1)/32:0][31:0] mem_read (input typ_adrs adrs);
        var reg [(par_cas_bits-1)/32:0][31:0] rdata;

        if (mem.exists(adrs)) begin
            rdata = mem[adrs];
        end else begin
            rdata = 'b0;
        end
        mem_read = rdata;
    endfunction

    function automatic void fx_cad(ref cls_cad cad);
        var typ_adrs obj_adrs;
        var byte byt_cols_per_block = cube_cfg.cfg_block_bits/par_cas_bits;
        var bit  [4:0] start;
        var bit  [5:0] size;
        var bit [31:0] mask;
        var reg [31:0] rdata;

        assert_size: assert (cad.dbytes%4 == 0) else
            $error("Illegal size = %0dB", cad.dbytes);

        obj_adrs = cad.adrs;

        start = cad.adrs[31:27];
        size  = {cad.adrs[26:22] == 0, cad.adrs[26:22]};
        if (cad.cmd == enu_mwrite) begin
            //assert_wr_public_csr: assert (cad.adrs[15:4] == 0) begin
            assert_wr_public_csr: assert (!cad.adrs[14:4] || (cad.adrs[21:16] >= 6'h20  &&  cad.adrs[21:16] < 6'h2B)) begin
                mask = ((1<<size)-1)<<start;
                
                if (size == 32) begin
                    cfg[cad.adrs] = cad.data[0];
                end else begin
                    if (cfg.exists(cad.adrs)) begin
                        rdata = cfg[cad.adrs];
                    end else begin
                        rdata = 32'b0;
                    end
                    cfg[cad.adrs] = (cad.data[0] & mask) | (rdata & ~mask);
                end

                case (cad.adrs)
                    22'h280000: begin // GLBLCTL
                        assert_illegal_warmrst: assert (!cad.data[0][6]) else
                            $error("%t %m Warm Reset must be written using I2C or JTAG interface.  This uses the cube_warmrst function to approximate warm reset behavior",$realtime);
                    end
                endcase
            end else begin
                $warning("Mode Write to a non-existent register will not be performed. Address = 'h%h", cad.adrs);
            end
        end else if (cad.cmd == enu_mread) begin
            foreach (cad.data[i]) begin
                cad.data[i] = 32'b0;
            end
            assert_rd_public_csr: assert (cad.adrs[14:4] == 0) begin

                if (cfg.exists(cad.adrs)) begin
          
                    cad.data[0] = (cfg[cad.adrs] >> start) & ((1<<size)-1); // TIE ::ADG changed mask to let data pass through.
                end
            end else begin
                $warning("Mode Read to a non-existent register will return zeros. Address = 'h%h", cad.adrs);
            end

        end else if (cad.is_write()) begin // commit write data to memory
            var reg [(par_cas_bits-1)/32:0][31:0] wdata;
            var reg [(par_cas_bits-1)/32:0][31:0] rdata;
            var bit [(par_cas_bits-1)/32:0][31:0] edata;
            var bit [(par_byt_bits-3):0] j; //j counts from 0-(par_cas_bits-1)/32
            

            // HMC is 16B addressible
            // an exception is the BIT WRITE command   
            if (cad.cmd == enu_bwrite) begin
                cad.byt &= - 'h8; // byt[2:0] == 0 == 8B adddressible
            end else begin 
                cad.byt &= - 'h10; // byt[3:0] == 0 == 16B addressible
            end
            j = cad.byt/4; // initial data offset

            for (int i=0; i<(cad.dbytes/4); i+=1) begin
                
                if (!i || !(j%(par_cas_bits/32))) begin // cas boundary
                    wdata = 'bx;
                    edata = 'b0;
                    rdata = mem_read(obj_adrs);
                end

                // fill write data
                wdata[j] = cad.data[i];
                if (cad.cmd == enu_bwrite) begin
                    edata[j] = ~cad.data[i + 2]; // mask is in bytes 8-15
                    if (i == 1) i = (cad.dbytes-1)/4 ; // commit 8B write
                end else begin
                    edata[j] = 32'hFFFFFFFF;
                end

                if (j%(par_cas_bits/32) == (par_cas_bits-1)/32 || i == (cad.dbytes-1)/4) begin // cas boundary or final cas

                    if (cad.cmd == enu_2add8) begin // dual 8 byte add
                        var reg signed [1:0][63:0] result;
                        result[0] = signed'(rdata[cad.byt/4+:2]) + signed'(wdata[cad.byt/4]); // wdata implicitly sign extended to 8B
                        result[1] = signed'(rdata[(cad.byt/4+2)+:2]) + signed'({wdata[cad.byt/4+2]}); // wdata implicitly sign extended to 8B
                        wdata[cad.byt/4+:4] = result;
                    end else if (cad.cmd == enu_add16) begin // 16B add
                        var reg signed [127:0] result;
                        result = signed'(rdata[cad.byt/4+:4]) + signed'(wdata[cad.byt/4+:2]); // wdata implicitly sign extended to 16B
                        wdata[cad.byt/4+:4] = result;
                    end

                    // commit write data
                    mem[obj_adrs] = (wdata & edata) | (rdata & ~edata); // masked write
                    // increment column address
                    obj_adrs.col = (obj_adrs.col & -byt_cols_per_block) | (obj_adrs.col + 1)%byt_cols_per_block; // column address wraps within a block
                end
                // increment data offset
                j += 1;
            end
            //$display("%m memory size = %0d write adrs = %h data = %h j = %d", mem.size(), obj_adrs, mem[obj_adrs], j);
        end else if (cad.is_read()) begin // fill read data from memory
            var reg [(par_cas_bits-1)/32:0][31:0] rdata;
            var bit [(par_byt_bits-3):0] j; //j counts from 0-(par_cas_bits-1)/32

            cad.data.delete(); // = '{}; //ncvlog likes .delete();

            // HMC is 16B addressible on all memory reads
            cad.byt &= - 'h10; // byt[3:0] == 0 == 16B addressible
            j = cad.byt/4; // initial data offset

            for (int i=0; i<(cad.dbytes/4); i+=1) begin
                if (!i || !(j%(par_cas_bits/32))) begin // cas boundary
                    rdata = mem_read(obj_adrs);
                end
                
                // fill read data
                cad.data.push_back(rdata[j]);

                if (j%(par_cas_bits/32) == (par_cas_bits-1)/32) begin // cas boundary
                    // increment column address
                    obj_adrs.col = (obj_adrs.col & -byt_cols_per_block) | (obj_adrs.col + 1)%byt_cols_per_block; // column address wraps within a block
                end
                // increment data offset
                j += 1;
            end
        end
    endfunction // end fx_cad

    function cls_rsp_pkt get_response(cls_req_pkt req_pkt);
        var         int credit_return;
        var     cls_cad cad;
        var cls_rsp_pkt rsp_pkt;

        string          address_mode; // address mode string
        string          csize; // string to use for memsize
        string          block; // string to use for block size

        case(cube_cfg.cfg_block_bits)
            1024 : block = "128";
            512  : block = "64";
            256  : block = "32";
        endcase // case (cube_cfg.cfg_block_bits)
        
        case(cube_cfg.cfg_cube_size)
            0 : csize = "2GB";
            1 : csize = "4GB";
            2 : csize = "8GB";
        endcase // case (cube_cfg.cfg_cube_size)

        // $display("address_mode : %s", address_mode);

        // make the string for address_mode
        address_mode = {csize, "_", block, "B"};
        //$display("address_mode : %s", address_mode);
        // address_mode = "direct";
        
        if (req_pkt.header.cmd == MD_WR || req_pkt.header.cmd == MD_RD) begin
            req_pkt.address_mode = "direct";
        end else begin
            req_pkt.address_mode = address_mode;
        end

        assert_pkt2cad: assert (req_pkt.get_cad(cad)) begin
            //ADG:: debug
           if (cfg_info_msg && mem_data_handle) begin
               string str_write_data; //ADG:: debug
               str_write_data = "";
               if(cad.is_write) begin 
                 num_wr++;
                 print_cad(cad,req_pkt.header.cmd.name(),mem_data_handle); 
                 foreach (req_pkt.data[i]) begin
                       string hex_data;
                       $sformat(hex_data, "%8h", req_pkt.data[i]);
                       //str_write_data = {str_write_data,hex_data};
                       str_write_data = {hex_data,str_write_data};
                 end 
                 $fdisplay(mem_data_handle,"%t: %s data : 'h%s;",$realtime,req_pkt.header.cmd.name(),str_write_data );
               end 
           end 
            //assert (cad.byt[4] == 0) else
            //    $error("MEM: 16B offset: %s", req_pkt.convert2string());

				// ignore op if bad command length -- this check used to reside in hmc_retry.sv
				if (! req_pkt.check_cmd_lng() )
					$error("%t %m Ignoring bad packet: Invalid length %h for command %h ",$realtime, req_pkt.header.lng, req_pkt.header.cmd);
				else
            	fx_cad(cad);

        end else begin
            $error("packet could not be converted to cad object");
        end
        rsp_pkt = new();
        rsp_pkt.build_pkt(cad, credit_return, -1, 0);
`ifdef TWO_IN_ONE
        rsp_pkt.transaction_id = req_pkt.transaction_id;
`endif
        //ADG:: debug
        if (cfg_info_msg && mem_data_handle) begin  //ADG:: debug
           string str_read_data;
           str_read_data = "";
           if(cad.is_read) begin
             num_rd++;
             print_cad(cad,rsp_pkt.header.cmd.name(),mem_data_handle); 
             foreach (rsp_pkt.data[i]) begin
                 string str_hex_data;
                 $sformat(str_hex_data, "%8h", rsp_pkt.data[i]);
                 //str_read_data = {str_read_data,str_hex_data};
                 str_read_data = {str_hex_data,str_read_data};
             end
             $fdisplay(mem_data_handle,"%t: %s data  : 'h%s;",$realtime,rsp_pkt.header.cmd.name(),str_read_data);
           end 
        end //ADG:: debug

        get_response = rsp_pkt;
    endfunction

    function void write(cls_req_pkt req_pkt); 
        void'(get_response(req_pkt));
    endfunction


    function void read(cls_req_pkt req_pkt, output [63:0] data[]); 
        var cls_rsp_pkt rsp_pkt;
       
          rsp_pkt = get_response(req_pkt);
          data = rsp_pkt.data;
          if(req_pkt.header.cmd == MD_RD && cfg_info_msg) begin
            $display("%t %m req_pkt: tag =  %h; adr = %h; data = %h;",$realtime,req_pkt.header.tag,req_pkt.header.adr,data[0]);
          end
    endfunction

    final begin 
        if (mem_data_handle) begin 
            $fdisplay(mem_data_handle, "%t: MEM SUMMARY: WR PACKETS: %0d, RD PACKETS %0d\n",$realtime, num_wr,num_rd);
            $fclose(mem_data_handle);
        end
    end
//
/*
    function void mode_write(cls_req_pkt req_pkt); 
        void'(get_response(req_pkt));
    endfunction

    function void mode_read(cls_req_pkt req_pkt, output [63:0] data[]); 
        var cls_rsp_pkt rsp_pkt;

        rsp_pkt = get_response(req_pkt);
        data = rsp_pkt.data;
    endfunction

    function void bit_write(cls_req_pkt req_pkt); 
        void'(get_response(req_pkt));
    endfunction

    function void dual_add8(cls_req_pkt req_pkt); 
        void'(get_response(req_pkt));
    endfunction

    function void add16(cls_req_pkt req_pkt); 
        void'(get_response(req_pkt));
    endfunction
    */

endinterface
