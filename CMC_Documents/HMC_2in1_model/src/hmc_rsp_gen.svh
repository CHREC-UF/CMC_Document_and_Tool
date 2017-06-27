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

// HMC Response Generator
// -generates read and write responses from an incoming request stream
// -generates an error if it recieves flow commands

//import pkt_pkg::*;
//import hmc_bfm_pkg::*;

class hmc_rsp_gen;
    // ports
    mailbox#(cls_pkt)       mb_req_pkt; // incoming request stream
    mailbox#(cls_pkt)       mb_rsp_pkt; // outgoing response stream
    virtual hmc_mem         hmc_mem_if[];
    bit [2:0]               hmc_mem_cid[byte]; // associative array maps cube id to the position in hmc_mem_if
   // for delay task 
    cls_req_pkt	responses [$];
    int rsp_delays [$];

    // internal signals
    cls_link_cfg            link_cfg;
    cls_cube_cfg            cube_cfg[]; // array of configuration objects
    bit                     cfg_info_msg = 0;
    int                     seed = adg_seed;
    int                     rsp_proccess_count;
    
    function new();
        fork
            run();
        join_none
    endfunction

    task automatic run();

        wait (
            link_cfg           != null &&
            //cube_cfg.size()            &&
            hmc_mem_if.size()          &&
            hmc_mem_cid.size()         &&
            mb_req_pkt         != null &&
            mb_rsp_pkt         != null
        );
        `ifdef ADG_DEBUG
               cfg_info_msg = 1;
        `endif

        fork
            run_rsp_gen();
        join_none
    endtask : run

    task automatic run_rsp_gen();
        var       cls_pkt pkt;
        var   cls_req_pkt req_pkt;
        var   cls_rsp_pkt rsp_pkt;
        var   cls_rsp_pkt poison_pkt;
        var     bit [2:0] cube_num;
        var          byte cube_id;
        var  cls_cube_cfg c_cfg;
        

        forever begin
            mb_req_pkt.peek(pkt);
            assert_req_cast: assert ($cast(req_pkt, pkt)) else
                $error("%t %m connection failure: must be connected to a request stream",$realtime);

            assert_recast: assert ($cast(req_pkt, pkt)) else
                $error("%t %m connection failure: must be connected to a request stream",$realtime);
            assert_no_flow: assert(req_pkt.header.cmd[5:2] != 4'h0) else
                $error("Flow packets are not allowed in the input stream");

            // cube number lookup using the cube ID
            if (hmc_mem_cid.exists(req_pkt.header.cub)) begin
                cube_num = hmc_mem_cid[req_pkt.header.cub];
            end else begin
                cube_num = 0;
                assert_valid_cid: assert (0) else begin
                    var string str_cid;
                    str_cid = "";
                    foreach (hmc_mem_cid[i])
                        str_cid = $sformatf("%0d, %s", hmc_mem_cid[i], str_cid);
                    $error("Invalid Cube ID:%d.  Valid Cube IDs are:%s. Discarding: %s", req_pkt.header.cub, str_cid, req_pkt.convert2string());
                    return; 
                 end 
            end

            // Check request address is valid based on cube size
            c_cfg = cube_cfg[cube_num];
            //$display("%t %m c_cfg.cfg_cube_size = %0d;",$realtime,c_cfg.cfg_cube_size);
            if (c_cfg.cfg_cube_size == 0) begin
                assert_valid_cube_2g_adr: assert (req_pkt.header.adr < 34'h80000000) else begin 
                    $error("%t %m Invalid address: %h. HMC cube size 2G, valid address should be within 0x07FFFFFFF",$realtime, req_pkt.header.adr);
                end 
            end 
            else if (c_cfg.cfg_cube_size == 1)begin
                assert_valid_cube_4g_adr: assert (req_pkt.header.adr < 34'h100000000) else begin
                    $error("%t %m Invalid address: %h. HMC cube size 4G, valid address should be within 0x0FFFFFFFF",$realtime, req_pkt.header.adr);
                end 
            end
            else begin
                assert_valid_cube_size: assert (0) else begin

                end
            end


            rsp_pkt = hmc_mem_if[cube_num].get_response(req_pkt);
            rsp_pkt.header.slid = req_pkt.tail.slid;

				// check for invalid LEN for command and issue errstat x31
				if (! req_pkt.check_cmd_lng() ) begin
                    $error("%t %m Bad packet: Invalid length %h for command %h ", $realtime, req_pkt.header.lng, req_pkt.header.cmd);
						  rsp_pkt.tail.errstat = ERR_LNG;
				end	

            if (req_pkt.must_respond()) begin
                //c_cfg = cube_cfg[cube_num];
                poison_pkt = new rsp_pkt; // shallow copy

               //`ifdef HMC_COV //ADG:: for user not doing verification coverage.
                //assert_poison_randomize: assert (poison_pkt.randomize(poison)) else
                assert_poison_randomize: assert (poison_pkt.randomize(poison) with {
                        poison_pkt.poison dist {0 := (1000 - link_cfg.cfg_rsp_poison), 1  := link_cfg.cfg_rsp_poison};
                }) else
                    $error("poison randomize failed");
               //`endif
                
                if (poison_pkt.poison) begin
                     poison_pkt.tail.crc = ~poison_pkt.tail.crc;
                    // send the poisoned packet immediately
                        mb_rsp_pkt.put(poison_pkt);
                end
                fork 
                    delay_response(req_pkt, rsp_pkt, c_cfg);
                join_none
                #0; // start the fork join
                //mb_rsp_pkt.put(rsp_pkt); // move it inside delay_resopense task
            end
            mb_req_pkt.get(pkt);  // free the location in the request mailbox
        end
    endtask

    // wait for a random amout of time before sending to output port
    task automatic delay_response(input cls_req_pkt pkt, cls_rsp_pkt rsp_pkt, cls_cube_cfg cube_cfg);
        var           int rsp_dly;
	bit [3:0] vlt_id, bnk_id, i_vlt_id, i_bnk_id ;
	int cube_size_block_bits;

        rsp_proccess_count++;

        rsp_dly = $dist_normal(seed, cube_cfg.cfg_rsp_mean, cube_cfg.cfg_rsp_std_dev); // normal distribution of delays between commands

        // set the minimum if the normal distribution gets too low
        if (rsp_dly < cube_cfg.cfg_rsp_min) begin
            rsp_dly = cube_cfg.cfg_rsp_min;
        end

	cube_size_block_bits = cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits;
        // set the maximum delay if another command goes to same vault and bank
        case (cube_size_block_bits)
	    //
	    // 2GB cite HMC gen 2 Rev. B data sheet
            //
	    //{0+32*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
	    256 : begin
	    		vlt_id = pkt.header.adr[8:5];
			bnk_id = pkt.header.adr[11:9];
		end	    
            //{0+64*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            512 : begin
	    		vlt_id = pkt.header.adr[9:6];
			bnk_id = pkt.header.adr[12:10];
		end
            //{0+128*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            1024 : begin
	    		vlt_id = pkt.header.adr[10:7];
			bnk_id = pkt.header.adr[13:11];
		end
            //
	    // 4GB cite HMC gen 2 Rev. B data sheet
            //
	    //{1+32*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
	    257 : begin
	    		vlt_id = pkt.header.adr[8:5];
			bnk_id = pkt.header.adr[12:9];
		end
            //{1+64*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            513 : begin
	    		vlt_id = pkt.header.adr[9:6];
			bnk_id = pkt.header.adr[13:10];
		end
            //{1+128*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            1025 : begin
	    		vlt_id = pkt.header.adr[10:7];
			bnk_id = pkt.header.adr[14:11];
		end
       endcase

	
        responses.push_back(pkt);

	for(int i = 0; i < responses.size() - 1; ++i) begin
           case (cube_size_block_bits)
	    //
	    // 2GB cite HMC gen 2 Rev. B data sheet
            //
	    //{0+32*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
	    256 : begin
	    		i_vlt_id = responses[i].header.adr[8:5];
			i_bnk_id = responses[i].header.adr[11:9];
		end	    
            //{0+64*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            512 : begin
	    		i_vlt_id = responses[i].header.adr[9:6];
			i_bnk_id = responses[i].header.adr[12:10];
		end
            //{0+128*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            1024 : begin
	    		i_vlt_id = responses[i].header.adr[10:7];
			i_bnk_id = responses[i].header.adr[13:11];
		end
            //
	    // 4GB cite HMC gen 2 Rev. B data sheet
            //
	    //{1+32*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
	    257 : begin
	    		i_vlt_id = responses[i].header.adr[8:5];
			i_bnk_id = responses[i].header.adr[12:9];
		end
            //{1+64*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            513 : begin
	    		i_vlt_id = responses[i].header.adr[9:6];
			i_bnk_id = responses[i].header.adr[13:10];
		end
            //{1+128*8} cube_cfg.cfg_cube_size + cube_cfg.cfg_block_bits
            1025 : begin
	    		i_vlt_id = responses[i].header.adr[10:7];
			i_bnk_id = responses[i].header.adr[14:11];
		end
          endcase
          if (i_vlt_id == vlt_id && i_bnk_id == bnk_id) begin
			rsp_dly = rsp_delays[i];
          end
	end //for loop
	
 	rsp_delays.push_back(rsp_dly);
	//
`ifndef TWO_IN_ONE // regular BFM
    // do not delay responses for 2in1
        #( rsp_dly ); 
`endif
	//
        mb_rsp_pkt.put(rsp_pkt);
        assert_rsp_resposes_pop_front: assert(responses.pop_front()) else
                               $error("%t %m : responses.pop_front failed !",$realtime);
         assert_rsp_delays_pop_front: assert(rsp_delays.pop_front()) else
                               $error("%t %m : rsp_delays.pop_front failed !",$realtime);

	//void'(responses.pop_front());
	//void'(rsp_delays.pop_front());
        if (cfg_info_msg)
            $display("%t %m RSP GEN[%0d]: Sending Response after waiting %t: %s", $realtime, link_cfg.cfg_link_id, rsp_dly, rsp_pkt.convert2string()); 
        rsp_proccess_count--;

    endtask

    // Task: wait_for_idle
    //
    // wait until there is nothing to do
    task automatic wait_for_idle();
        forever begin
            if (mb_req_pkt.num() || 
                mb_rsp_pkt.num() ||
                rsp_proccess_count
            ) 
                #200ns;
            else
                break;
        end

    endtask

endclass : hmc_rsp_gen
