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


// HMC Response Checker
// -combination tag tracker and response scoreboard.  
// todo: The tag tracking should be a seperate class from the response scoreboard.
// assigns tags to incoming commands
// stores write and read data in shadow memory
// compares read responses to shadow memory
// performs transaction retry when DINV==1 and recoverable ERRSTAT codes

class hmc_rsp_chk#(
    num_links_c=4,
    num_hmc_c=1
);

    mailbox#(cls_pkt)       mb_req_pkt_in;
    mailbox#(cls_pkt)       mb_req_pkt_out;
    mailbox#(cls_pkt)       mb_rsp_pkt; // get from bfm, put to mailbox
    pkt_analysis_port#()    rsp_pkt_port;
    pkt_analysis_port#()    req_pkt_port;
    virtual hmc_mem         #( .num_links_c (num_links_c), .num_hmc_c (num_hmc_c)) hmc_mem_if[]; 
    bit [2:0]               hmc_mem_cid[byte]; // associative array maps cube id to the position in hmc_mem_if


    bit               [8:0] last_tag;
    cls_req_pkt             req_pkt_q[typ_tag];

    // Group: Configuration
    cls_link_cfg            link_cfg;   
    bit                     cfg_info_msg  = 0;
//

    function new();
        fork
            run();
        join_none
    endfunction

    task automatic run();
        `ifdef ADG_DEBUG
           cfg_info_msg  = 1; 
        `endif 
        wait (
            hmc_mem_if.size()        &&
            hmc_mem_cid.size()       &&
            link_cfg         != null &&
            mb_req_pkt_in    != null &&
            mb_req_pkt_out   != null &&
            mb_rsp_pkt       != null &&
            req_pkt_port     != null &&
            rsp_pkt_port     != null
        );

        fork
            run_req();
            run_rsp();
        join_none
	
    endtask : run

    function automatic void run_reset();
        if (cfg_info_msg)
            $display("%t %m: Warm Reset", $realtime);

        assert_empty_buffers: assert (!req_pkt_q.size()) else begin
            $warning("%1d in flight transactions will be lost due to Warm Reset", req_pkt_q.size());
            //foreach (req_pkt_q[i])
            //    $warning("\tRequest Queue[%0d]: %s", i, req_pkt_q[i].convert2string());
        end
        req_pkt_q.delete();
        last_tag = 0;
    endfunction : run_reset

    // Function: run_req
    //
    // get from request mailbox, write to memory
    task automatic run_req();
        var       cls_pkt pkt, ap_pkt;
        var   cls_req_pkt req_pkt;
        var logic [127:0] data[$];
        var     bit [2:0] cube_num;

        forever begin
            mb_req_pkt_in.peek(pkt);

            assert_req_cast: assert ($cast(req_pkt, pkt)) else 
                $error("%t %m connection failure: must be connected to a request stream", $realtime);

            // make sure the outgoing packet is valid
            assert_check_pkt: assert (!pkt.check_pkt()) else 
                $error("RSP CHK: invalid packet: %s", pkt.convert2string());

            if (req_pkt.poison) begin
                // assign a random tag
                if (!req_pkt.header.tag)
                    req_pkt.header.tag = $urandom;
            end else begin

                // assign a tag that isn't currently in use
                if (req_pkt.must_respond()) begin 
                    get_nxt_tag(req_pkt.header.tag);

                    if (cfg_info_msg) 
                        $display("%t %m: Assigning pkt %s tag %0d", $realtime, req_pkt.convert2string(), req_pkt.header.tag);
                end else begin
                    req_pkt.header.tag = $urandom;
                end

                // cube number lookup using the cube ID
                if (hmc_mem_cid.exists(req_pkt.header.cub)) begin
                    cube_num = hmc_mem_cid[req_pkt.header.cub];
                end else begin
                    cube_num = 0;
                end

                // write or read memory
                case (req_pkt.header.cmd)
                    WR16    ,
                    WR32    ,
                    WR48    ,
                    WR64    ,
                    WR80    ,
                    WR96    ,
                    WR112   ,
                    WR128   ,
                    P_WR16  ,
                    P_WR32  ,
                    P_WR48  ,
                    P_WR64  ,
                    P_WR80  ,
                    P_WR96  ,
                    P_WR112 ,
                    P_WR128 ,
                    MD_WR   ,
                    BWR     ,
                    P_BWR   ,
                    DADD8   ,
                    P_DADD8 ,
                    ADD16   ,
                    P_ADD16 : begin
                        hmc_mem_if[cube_num].write(req_pkt);
                    end
                    RD16    ,
                    RD32    ,
                    RD48    ,
                    RD64    ,
                    RD80    ,
                    RD96    ,
                    RD112   ,
                    RD128   ,
                    MD_RD   : begin
                        req_pkt = new req_pkt; // shallow copy yourself
                        // use expected data if supplied in the read request, 
                        // otherwise get expected data from shadow memory
                        if (!req_pkt.data.size()) begin
                            hmc_mem_if[cube_num].read(req_pkt, req_pkt.data); // 
                        end
                        // read command does not contain data, 
                        // req_pkt goes to req_pkt_q and contains expected data
                        // pkt goes to driver and does not contain data
                        pkt.data.delete(); 
                    end
                endcase

                if (req_pkt.must_respond()) begin
                    assert_no_reuse: assert (!req_pkt_q.exists(req_pkt.header.tag)) else
                        $error ("%t %m RSP CHK[%0d]: Illegal resue of tag:%0d.  A response must be received prior to reusing a tag\n%s", $realtime, link_cfg.cfg_link_id, req_pkt.header.tag, req_pkt.convert2string());

                    // clone into tag tracker
                    req_pkt_q[req_pkt.header.tag] = req_pkt;
                end

            end

            if (cfg_info_msg)
                $display("%t %m  RSP CHK[%0d]: %s", $realtime, link_cfg.cfg_link_id, pkt.convert2string());

            ap_pkt = new pkt; // clone packet before writing to analysis port
            req_pkt_port.write(ap_pkt); // put to analysis port
            mb_req_pkt_out.put(pkt);
            mb_req_pkt_in.get(pkt); // free mailbox location
        end
    endtask

    // Function: run_rsp
    //
    // get from response mailbox, compare actual value to expected value in to memory
    task automatic run_rsp();
        var       cls_pkt pkt, ap_pkt;
        var   cls_req_pkt req_pkt;
        var   cls_rsp_pkt rsp_pkt;
        var logic [127:0] data[$];
        var           bit miscompare, type_mismatch;
        var           int i;
        var        string exp_data, act_data;

        forever begin
            mb_rsp_pkt.get(pkt);
            if (cfg_info_msg)
                $display("%t %m RSP CHK[%0d]: %s",$realtime, link_cfg.cfg_link_id, pkt.convert2string());

            if (pkt.poison) begin
                if (cfg_info_msg)
                    $display("%t %m RSP CHK[%0d]: Discarding Poisoned response: %s",$realtime, link_cfg.cfg_link_id, pkt.convert2string()); 
                continue;
            end

            assert ($cast(rsp_pkt, pkt)) else
                $error("connection failure: must be connected to a response stream; got pkt: %s", pkt.convert2string());

            if (rsp_pkt.tail.errstat) begin 
                var typ_err_stat err_stat;

                assert ($cast(err_stat, rsp_pkt.tail.errstat)) else
                    $error("%t %m RSP CHK[%0d]: Invalid errstat %h received: %s", $realtime, link_cfg.cfg_link_id, rsp_pkt.tail.errstat, rsp_pkt.convert2string());

                case (rsp_pkt.tail.errstat[6:4]) // todo: enumerate the error status codes
                    0: // WARNINGS
                        assert (0) else $warning("%t %m RSP CHK[%0d]: Warning %s received from cub: %d", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.header.tag);
                    1: begin // DRAM errors
                        $display("%t %m RSP CHK[%0d]: DRAM Err: %s received on tag %d", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.header.tag);
                        //This assetion ahould be in error status code 3. assert (rsp_pkt.header.cmd == RD_RS) else
                        //  $error("%t %m RSP CHK[%0d]: cmd must be RD_RS when errstat == %s: %s", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.convert2string());

                        assert (rsp_pkt.tail.errstat != ERR_MUE || rsp_pkt.tail.dinv) else
                          $error("%t %m RSP CHK[%0d]: dinv must be 1 when errstat == ERR_MUE: %s", $realtime, link_cfg.cfg_link_id, rsp_pkt.convert2string());
                    end
                    2: $display("%t %m RSP CHK[%0d]: Link retry successful: %s received from cub: %d", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.header.tag); 
                    3: begin // protocol errors
                        $display("%t %m RSP CHK[%0d]: Protocol Err: %s received on tag %d", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.header.tag);
                        assert (rsp_pkt.header.cmd == WR_RS) else
                          $error("%t %m RSP CHK[%0d]: cmd must be WR_RS when errstat == %s: %s", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.convert2string());

                        // todo: only requests that were error injected on the testbench side should be removed from the request queue, otherwise the DUT is misbehaving
                        req_pkt_q.delete(rsp_pkt.header.tag); // retire the tag
                    end
                    6: assert (0) else $error("%t %m RSP CHK[%0d]: Vault Critical Error: %s received from cub: %d", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.header.tag);
                    7: assert (0) else $error("%t %m RSP CHK[%0d]: Fatal Error: %s received from cub: %d", $realtime, link_cfg.cfg_link_id, err_stat.name(), rsp_pkt.header.tag);
                endcase
                if (rsp_pkt.tail.errstat[6:4] != 1) // further sbe/mue checking below, done processing everything else
                    continue; // done processing this response
            end

            // tag lookup to find the original request
            if (req_pkt_q.exists(rsp_pkt.header.tag)) begin
                req_pkt = req_pkt_q[rsp_pkt.header.tag];

                assert (req_pkt.data.size()) else
                       $error("%t %m RSP CHK[%0d]: data must be stored when the request happens: %s", $realtime, link_cfg.cfg_link_id,req_pkt.convert2string());

                case (req_pkt.header.cmd)
                    RD16    ,
                    RD32    ,
                    RD48    ,
                    RD64    ,
                    RD80    ,
                    RD96    ,
                    RD112   ,
                    RD128   ,
                    MD_RD   : ;
                    default : req_pkt.data.delete(); // = '{}; // skip data compare
                endcase

                
                case (req_pkt.header.cmd)
                    RD16    ,
                    RD32    ,
                    RD48    ,
                    RD64    ,
                    RD80    ,
                    RD96    ,
                    RD112   ,
                    RD128   : if(rsp_pkt.header.cmd != RD_RS) type_mismatch = 1;
                    MD_RD   : if(rsp_pkt.header.cmd != MD_RD_RS) type_mismatch = 1;
                    WR16    ,
                    WR32    ,
                    WR48    ,
                    WR64    ,
                    WR80    ,
                    WR96    ,
                    WR112   ,
                    WR128   : if(rsp_pkt.header.cmd != WR_RS) type_mismatch = 1;
                    MD_WR   : if(rsp_pkt.header.cmd != MD_WR_RS) type_mismatch = 1;
                    default : ;
                endcase
                
                // Check to make sure DINV was expected based off request
                // 6/25/14 TN:  Done for MUE verification
                if (req_pkt.exp_dinv && (rsp_pkt.tail.dinv && rsp_pkt.header.cmd == RD_RS)) begin
                    $display("%t %m RSP CHK[%0d]: DINV compare!!: %s ", $realtime, link_cfg.cfg_link_id, req_pkt.convert2string());
                end
                if (req_pkt.exp_dinv && (!rsp_pkt.tail.dinv && rsp_pkt.header.cmd == RD_RS)) begin
                    req_pkt = req_pkt_q[rsp_pkt.header.tag];
                    req_pkt_q.delete(rsp_pkt.header.tag);
                    req_pkt.data.delete();
                    assert (0) else $error("%t %m RSP CHK[%0d]: DINV miscompare: %s was expecting a DINV due to MUE but did not receive one", $realtime, link_cfg.cfg_link_id, req_pkt.convert2string());
                end
                // todo: use req_pkt.compare(rsp_pkt) when available
                miscompare = 0;
                if (!rsp_pkt.tail.dinv ) begin
                        foreach (req_pkt.data[i]) begin
                            if (req_pkt.data[i] !== rsp_pkt.data[i]) begin
                               miscompare = 1;
                               if(cfg_info_msg)
                                  $display("%t %m req_pkt: tag =  %h; adr = %h; data[i] = %h;",$realtime,req_pkt.header.tag,req_pkt.header.adr,data[i]);    
                               break;
                            end
                        end
                     //end
                end //end if (!rsp_pkt.tail.dinv )   
                assert_type_mismatch: assert (!type_mismatch) else
                  $error("%t %m RSP CHK[%0d]: Response type does not match request:  \nReq: %s  \nRsp: %s",  $realtime, link_cfg.cfg_link_id, req_pkt.convert2string(), rsp_pkt.convert2string());
                
                assert_data_compare: assert (!miscompare) begin
                    $swriteh(act_data, rsp_pkt.data);
                    if (req_pkt.data.size() && cfg_info_msg)
                        $display("%t %m RSP CHK[%0d]: Data compare passed: %s \nActual  : 'h%s", $realtime, link_cfg.cfg_link_id, req_pkt.convert2string(), act_data);
                end else begin
                    $swriteh(exp_data, req_pkt.data);
                    $swriteh(act_data, rsp_pkt.data);
                    $error("%t %m RSP CHK[%0d]: Data miscompare: %s \nExpected: 'h%s\nActual  : 'h%s", $realtime, link_cfg.cfg_link_id, req_pkt.convert2string(), exp_data, act_data);
                end
    
                req_pkt_q.delete(rsp_pkt.header.tag); // retire the tag
            end //if (req_pkt_q.exists(rsp_pkt.header.tag))
            else if (rsp_pkt.header.cmd[5:2]) begin // TODO: use the enumeration or a function is_response()
                assert_tag_not_found: assert (0) else 
                    $error("%t %m RSP CHK[%0d]: Response tag %1d not found. %s", $realtime, link_cfg.cfg_link_id, rsp_pkt.header.tag, rsp_pkt.convert2string());
            end
            
            ap_pkt = new pkt; // clone packet before writing to analysis port
            rsp_pkt_port.write(ap_pkt); // put to analysis port
        end
    endtask


    // Task: get_nxt_tag
    //
    // select the next available tag
    task automatic get_nxt_tag(output bit [8:0] tag);
        tag = last_tag;
        tag++;
        tag%=link_cfg.cfg_max_tags;

        fork
            wait (req_pkt_q.size() < link_cfg.cfg_max_tags && (!link_cfg.cfg_seq_tags || !req_pkt_q.exists(tag)));
            # 5us;
        join_any
        assert_max_tags_out: assert (req_pkt_q.size() < link_cfg.cfg_max_tags) else
            $error("%t %m RSP CHK[%0d]: no tags returned after waiting 5us", $realtime, link_cfg.cfg_link_id);
        assert_seqential_tag_out: assert (!link_cfg.cfg_seq_tags || !req_pkt_q.exists(tag)) else
            $error("%t %m RSP CHK[%0d]: tag:%0d was not returned after waiting 5us", $realtime, link_cfg.cfg_link_id, tag);

        while (req_pkt_q.exists(tag) && !link_cfg.cfg_seq_tags) begin
            tag++;
            tag%=link_cfg.cfg_max_tags;
            assert_nxt_tag_wrap:  assert (tag != last_tag) else
                $fatal("%t %m RSP CHK[%0d]: Failed to find a new tag.  Should be preceded by assert_max_tags_out", $realtime, link_cfg.cfg_link_id);
        end

        last_tag = tag;
    endtask


    // Task: wait_for_idle
    //
    // wait until there is nothing to do
    task automatic wait_for_idle();
        forever begin
            if (mb_req_pkt_in.num() || req_pkt_q.size()) begin
                $display ("%t %m RSP CHK[%0d]: waiting for idle", $realtime, link_cfg.cfg_link_id);
                print_outstanding();
                //$display ("%t %m mb_req_pkt_in.num() = %h; req_pkt_q.size() = %0d;", $realtime, mb_req_pkt_in.num(),req_pkt_q.size());
                #200ns;
            end else
                break;
        end

        // VCS: Error-[NYI] Not Yet Implemented
        //wait (!mb_req_pkt_in.num() && !req_pkt_q.size())
    endtask

    function automatic print_outstanding(); 
        $display("-- %t %m ----- Link %0d -------------------",$realtime, link_cfg.cfg_link_id);
        foreach(req_pkt_q[i]) begin 
            $display("\tRequest Queue[%0d]: %s", i, req_pkt_q[i].convert2string());
        end
    endfunction: print_outstanding

endclass : hmc_rsp_chk
