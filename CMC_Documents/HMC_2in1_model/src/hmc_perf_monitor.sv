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

`timescale 1ps/1ps
interface hmc_perf_monitor ();
    import pkt_pkg::*;
    import hmc_bfm_pkg::typ_tag;
    import hmc_bfm_pkg::cls_link_cfg;

    pkt_analysis_port#()    req_pkt_port;
    pkt_analysis_port#()    rsp_pkt_port;

    bit                     reset_done;
    // latency tracking
    realtime transactionstarttime [typ_tag];  // associative array of time indexed by tag 
    realtime transactionendtime      = 0;
    realtime lattime      = 0;
    realtime rd_latmin    = 1e18;
    realtime rd_latmax    = 0;
    realtime rd_latavg    = 0;
    realtime rd_lattot    = 0;
    int      rd_latcnt    = 0;
    realtime wr_latmin    = 1e18;
    realtime wr_latmax    = 0;
    realtime wr_latavg    = 0;
    realtime wr_lattot    = 0;
    int      wr_latcnt    = 0;



    // token tracking
    int      link_retry         = 0;  // Flag to track if an IRTRY was found to indicate Link Retries
    int      host_token_count   = 0;  // count of total tokens.  Used to skip the initial tokens for flow control
    int      hmc_token_count    = 0;
    realtime host_token_starttime [$];  // queue of timestamps, size = one per token 
    realtime hmc_token_starttime [$];  // queue of timestamps, size = one per token 
    
    realtime token_time    = 0;
    realtime tok_lat       = 0;
    
    realtime hmc_latmin    = 1e18;
    realtime hmc_latmax    = 0;
    realtime hmc_latavg    = 0;
    realtime hmc_lattot    = 0;
    int      hmc_latcnt    = 0;
    realtime host_latmin   = 1e18;
    realtime host_latmax   = 0;
    realtime host_latavg   = 0;
    realtime host_lattot   = 0;
    int      host_latcnt   = 0;

    // Response RTC -> Host Request Latency
    realtime host_req_starttime [$];  // queue of timestamps, size = one per token 
    realtime host_req_latmin    = 1e18;
    realtime host_req_latmax    = 0;
    realtime host_req_latavg    = 0;
    realtime host_req_lattot    = 0;
    int      host_req_latcnt    = 0;
    
    // Request RTC -> HMC Response Latency
    realtime hmc_rsp_starttime [$];  // queue of timestamps, size = one per token 
    realtime hmc_rsp_latmin    = 1e18;
    realtime hmc_rsp_latmax    = 0;
    realtime hmc_rsp_latavg    = 0;
    realtime hmc_rsp_lattot    = 0;
    int      hmc_rsp_latcnt    = 0;
    
    

    // bandwidth tracking
    int      req_byte_cnt = 0;
    int      rsp_byte_cnt = 0;
    realtime starttime    = 0;
    realtime endtime      = 0;
    realtime runtime      = 0;

    // Group: Configuration
    cls_link_cfg            link_cfg;   
    bit      cfg_info_msg = 0;
    string   cfg_str_id = " ";

    initial begin
        
        wait (
            req_pkt_port       != null &&
            rsp_pkt_port       != null &&
            link_cfg           != null &&
            reset_done
            //hmc_flit_bfm != null
        );

                // check_pkt will be 0 when retry is expected on the link
                if (link_cfg.cfg_check_pkt) begin
                   fork
                      run_req_mon();
                      run_rsp_mon();
                   join_none
                end else begin
                    $display("%t %m: disabled. link %0d cfg_check_pkt : %0d; Performance Monitor results are not valid if retry occurrs on the link.", $realtime,link_cfg.cfg_link_id,link_cfg.cfg_check_pkt);
                end
    end

    function automatic void run_reset();
        if (cfg_info_msg)
            $display("%t %m: Warm Reset", $realtime);
        assert_empty_buffers: assert (!host_token_starttime.size() && !hmc_token_starttime.size()) else begin
            $warning("%1d in flight tokens have been lost due to Warm Reset", host_token_starttime.size() + hmc_token_starttime.size());
        end
        host_token_starttime.delete();
        hmc_token_starttime.delete();
        host_token_count   = 0; 
        hmc_token_count    = 0;
        reset_done         = 1;
        
        host_req_starttime.delete();
        hmc_rsp_starttime.delete();
    endfunction : run_reset


    final begin
        if (cfg_info_msg) begin
            if (rd_latcnt) begin
                rd_latavg = rd_lattot / rd_latcnt ;
                $display("%s Avg Read Latency:             %t",cfg_str_id, rd_latavg);
                $display("%s Max Read Latency:             %t",cfg_str_id, rd_latmax);
                $display("%s Min Read Latency:             %t",cfg_str_id, rd_latmin);
            end    
               
            if (wr_latcnt) begin
                wr_latavg = wr_lattot / wr_latcnt ;
                $display("%s Avg Write Latency:            %t",cfg_str_id, wr_latavg);
                $display("%s Max Write Latency:            %t",cfg_str_id, wr_latmax);
                $display("%s Min Write Latency:            %t",cfg_str_id, wr_latmin);
            end    
               
            runtime = endtime - starttime;
            if (runtime) begin
                $display("%s Write Bandwidth:               %8.2f GB/s", cfg_str_id, (req_byte_cnt*1e-9)/(runtime*1e-12));
                $display("%s Read Bandwidth:                %8.2f GB/s", cfg_str_id, (rsp_byte_cnt*1e-9)/(runtime*1e-12));
                $display("%s Total Bandwidth:               %8.2f GB/s", cfg_str_id, ((req_byte_cnt+rsp_byte_cnt)*1e-9)/(runtime*1e-12));
            end
            
            if (cfg_str_id.substr(0, 3) == "LINK") begin
                if (link_retry == 0) begin
                    if (hmc_latcnt) begin
                        hmc_latavg = hmc_lattot / hmc_latcnt ;
                        $display("%s Avg Cube RTC Latency:          %t",cfg_str_id, hmc_latavg);
                        $display("%s Max Cube RTC Latency:          %t",cfg_str_id, hmc_latmax);
                        $display("%s Min Cube RTC Latency:          %t",cfg_str_id, hmc_latmin);
                    end    
                    if (host_latcnt) begin
                        host_latavg = host_lattot / host_latcnt ;
                        $display("%s Avg Host RTC Latency:          %t",cfg_str_id, host_latavg);
                        $display("%s Max Host RTC Latency:          %t",cfg_str_id, host_latmax);
                        $display("%s Min Host RTC Latency:          %t",cfg_str_id, host_latmin);
                    end    
                    if (hmc_rsp_latcnt) begin
                        hmc_rsp_latavg = hmc_rsp_lattot / hmc_rsp_latcnt ;
                        $display("%s Avg Cube RTC_to_RSP Latency:   %t",cfg_str_id, hmc_rsp_latavg);
                        $display("%s Max Cube RTC_to_RSP Latency:   %t",cfg_str_id, hmc_rsp_latmax);
                        $display("%s Min Cube RTC_to_RSP Latency:   %t",cfg_str_id, hmc_rsp_latmin);
                    end    
                    if (host_req_latcnt) begin
                        host_req_latavg = host_req_lattot / host_req_latcnt ;
                        $display("%s Avg Host RTC_to_REQ Latency:   %t",cfg_str_id, host_req_latavg);
                        $display("%s Max Host RTC_to_REQ Latency:   %t",cfg_str_id, host_req_latmax);
                        $display("%s Min Host RTC_to_REQ Latency:   %t",cfg_str_id, host_req_latmin);
                    end    
                    assert (host_token_starttime.size == 0) else
                        $error("%s:  Outstanding Cube Req to Cube token return queue not empty.  Missing Tokens = %d", cfg_str_id, host_token_starttime.size );
                    assert (hmc_token_starttime.size == 0) else
                        $error("%s:  Outstanding Cube Rsp to Host token return queue not empty.  Missing Tokens = %d", cfg_str_id, hmc_token_starttime.size );
  
                end
            end
        end
    end

    // call bfm task, try_put to mailbox
    task automatic run_req_mon();
        var   cls_pkt     pkt;
        var   cls_req_pkt req_pkt;
        var typ_req_header header;
        var typ_req_tail tail;

        forever begin
            // Get packet
            req_pkt_port.get(pkt);
            header = pkt.get_header();
            tail = pkt.get_tail();

            if (header.cmd == IRTRY) begin
                link_retry = 1;
                $display("%t %m: disabled.  Performance Monitor results are not valid if retry occurrs on the link.", $realtime);
                return;
            end
            
            if (header.cmd && header.cmd != PRET && cfg_str_id.substr(0, 3) == "LINK") begin // Host Token Retrun - for a subset of packets
                //$display("%s *RTC* POP host_token cmd = %s rtc = %d, size=%d", cfg_str_id,header.cmd.name(), tail.rtc, host_token_starttime.size) ;
                for (int i=0; i<tail.rtc; i=i+1) begin 
                    host_token_count++ ; 
                    if (host_token_count > link_cfg.cfg_tokens)   // ignore the initial tokens
                       token_time = host_token_starttime.pop_back() ;
                end
            
                //$display("%s *RTC* POP host_token cmd = %s rtc = %d, size=%d", cfg_str_id,header.cmd.name(), tail.rtc, host_token_starttime.size) ;
                if ((host_token_count > link_cfg.cfg_tokens) && (tail.rtc > 0)) begin   // ignore the initial tokens
                   tok_lat     = $realtime - token_time ;
                   pkt.tok_lat = tok_lat ;
                   if (tok_lat > host_latmax)
                       host_latmax = tok_lat;
                   if (tok_lat < host_latmin)
                       host_latmin = tok_lat;
                   host_latcnt += 1 ;
                   host_lattot += tok_lat ;
                end
            
                if (header.cmd != TRET) begin // Host Token Retrun - for a subset of packets
                    //$display("%s *REQ* POP host_req_starttime cmd = %s header.lng = %d, size=%d", cfg_str_id,header.cmd.name(), header.lng, host_req_starttime.size) ;
                    for (int i=0; i<header.lng; i=i+1) begin 
                        hmc_token_starttime.push_front($realtime) ; // Host Commands to HMC.  Add timestamp of Request FLIT to hmc_token_start_time queue
                        token_time = host_req_starttime.pop_back() ;
                    end
                    tok_lat     = $realtime - token_time ;
                    pkt.req_lat = tok_lat ;
                    if (tok_lat > host_req_latmax)
                        host_req_latmax = tok_lat;
                    if (tok_lat < host_req_latmin)
                        host_req_latmin = tok_lat;
                    host_req_latcnt += 1 ;
                    host_req_lattot += tok_lat ;
                end
                
                if (tail.rtc && !link_cfg.cfg_tail_rtc_dsbl) begin   // Capture the incoming RTC times
                    //$display("%s *REQ* PUSH hmc_rsp_starttime cmd = %s rtc = %d, size=%d", cfg_str_id,header.cmd.name(), tail.rtc, hmc_rsp_starttime.size) ;
                    for (int i=0; i<tail.rtc; i=i+1) 
                       hmc_rsp_starttime.push_front($realtime) ;
                end
            end 
                   
            if ((header.cmd != TRET) && (header.cmd != PRET)) begin 
                // convert to req packet
                assert_req_cast: assert ($cast(req_pkt, pkt)) else 
                    $error("%t %m connection failure: must be connected to a request stream", $realtime);
                if (req_pkt.must_respond()) 
                    // grab start time of transaciton of non posted transaction
                    transactionstarttime[req_pkt.header.tag] = $realtime;

                // grab the data payload size
                req_byte_cnt += pkt.data.size() * 8;
                // grab times for start and stop
                endtime = $realtime ;
                if (starttime == 0)
                    starttime = $realtime;            
            end

            if (header.cmd && cfg_info_msg) begin
                //TODO: Hard coded address mode below.  should be set using cube configuration object.
                if (cfg_str_id.substr(0, 3) == "LINK")
                    pkt.address_mode = "2GB_128B"  ;    // Temp fix for running modeling with 2GB_128B address mode.  This needs to be set in the monitor.
                else    
                    pkt.address_mode = "vp_tb";
            
                pkt.print_tsv({cfg_str_id,"_req"});
            end 
            
        end
    endtask
            
    // call bfm task, try_put to mailbox
    task automatic run_rsp_mon();
        var   cls_pkt     pkt;
        var   cls_rsp_pkt rsp_pkt;
        var typ_req_header header;
        var typ_req_tail tail;
        int tokens_expected = (link_cfg.cfg_tokens_expected > 0) ? link_cfg.cfg_tokens_expected : link_cfg.cfg_tokens ;
        
        forever begin
            rsp_pkt_port.get(pkt);
            header = pkt.get_header();
            tail = pkt.get_tail();

            if (header.cmd == IRTRY) begin
                link_retry = 1;
                $display("%t %m: disabled.  Performance Monitor results are not valid if retry occurrs on the link.", $realtime);
                return;
            end
                
            if (header.cmd && header.cmd != PRET && cfg_str_id.substr(0, 3) == "LINK") begin // Host Token Retrun - for a subset of packets
                for (int i=0; i<tail.rtc; i=i+1) begin 
                    hmc_token_count++ ; 
                    if (hmc_token_count > tokens_expected)   // ignore the initial tokens
                       token_time = hmc_token_starttime.pop_back() ;
                end
            
                if ((hmc_token_count > tokens_expected) && (tail.rtc > 0)) begin   // ignore the initial tokens or transactions with no token retrun
                   tok_lat     = $realtime - token_time ;
                   pkt.tok_lat = tok_lat ;
                   if (tok_lat > hmc_latmax)
                       hmc_latmax = tok_lat;
                   if (tok_lat < hmc_latmin)
                       hmc_latmin = tok_lat;
                   hmc_latcnt += 1 ;
                   hmc_lattot += tok_lat ;
                end        
            
                if (tail.rtc) begin   
                    //$display("%s *RSP* PUSH host_req cmd = %s rtc = %d, size=%d", cfg_str_id, header.cmd.name(), tail.rtc, host_req_starttime.size) ;
                    for (int i=0; i<tail.rtc; i=i+1) begin 
                           host_req_starttime.push_front($realtime) ;
                    end
                end
            
                if ((header.cmd != TRET) && (!link_cfg.cfg_tail_rtc_dsbl)) begin
                    //$display("%s *RSP* POP hmc_rsp_starttime cmd = %s header.len = %d, size=%d", cfg_str_id, header.cmd.name(), header.lng, hmc_rsp_starttime.size()) ;
                    for (int i=0; i<header.lng; i=i+1) begin 
                        token_time = hmc_rsp_starttime.pop_back() ;
                        host_token_starttime.push_front($realtime) ;
                    end
                    tok_lat     = $realtime - token_time ;
                    pkt.req_lat = tok_lat ;
                    if (tok_lat > hmc_rsp_latmax)
                        hmc_rsp_latmax = tok_lat;
                    if (tok_lat < hmc_rsp_latmin)
                        hmc_rsp_latmin = tok_lat;
                    hmc_rsp_latcnt += 1 ;
                    hmc_rsp_lattot += tok_lat ;
                end        
            end        
            
            if ((header.cmd == RD_RS) || (header.cmd == WR_RS) || (header.cmd == MD_RD_RS) || (header.cmd == MD_WR_RS)) begin 
                    
                // convert to req packet
                assert_rsp_cast: assert ($cast(rsp_pkt, pkt)) else 
                    $error("%t %m connection failure: must be connected to a response stream", $realtime);

                transactionendtime = $realtime;
                lattime = transactionendtime - transactionstarttime[rsp_pkt.header.tag];
                pkt.lat = lattime;
                if (rsp_pkt.header.cmd == RD_RS)
                begin
                    if (lattime > rd_latmax)
                        rd_latmax = lattime;
                    if (lattime < rd_latmin)
                        rd_latmin = lattime;
                    rd_latcnt += 1 ;
                    rd_lattot += lattime ;
                    //$display("Latency is %d", lattime) ;
                end
                if (rsp_pkt.header.cmd == WR_RS)
                begin
                    if (lattime > wr_latmax)
                        wr_latmax = lattime;
                    if (lattime < wr_latmin)
                        wr_latmin = lattime;
                    wr_latcnt += 1 ;
                    wr_lattot += lattime ;
                    //$display("Latency is %d", lattime) ;
                end

                rsp_byte_cnt += pkt.data.size() * 8;
                endtime = $realtime ;
                if (starttime == 0)
                    starttime = $realtime;  
            end

            if (header.cmd && cfg_info_msg) begin 
                pkt.print_tsv({cfg_str_id,"_rsp"});
            end        

        end
    endtask

endinterface : hmc_perf_monitor
