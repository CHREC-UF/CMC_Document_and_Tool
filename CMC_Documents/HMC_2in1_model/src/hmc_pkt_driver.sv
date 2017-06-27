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

// HMC Packet Driver
// -The driver's role is to drive data items to the bus following the interface protocol
`timescale 1ns/1ps
interface hmc_pkt_driver;
// (
//    hmc_flit_bfm            hmc_flit_bfm_tx,
//    hmc_flit_bfm            hmc_flit_bfm_rx
//);
    import pkg_cad::*; //ADG:: debug
    import pkt_pkg::*;
    import hmc_bfm_pkg::*;

    cls_fi                  tx_fi;
    cls_fi                  rx_fi;
    cls_link_cfg            link_cfg;   
    
    // modports
    mailbox#(cls_pkt)       mb_tx_pkt; // get from mailbox, put to bfm
    mailbox#(cls_pkt)       mb_rx_pkt; // get from bfm, put to mailbox
    //virtual  hmc_flit_bfm   hmc_flit_bfm_tx;
    //virtual  hmc_flit_bfm   hmc_flit_bfm_rx;

    // Group Configuration
    bit                     cfg_info_msg  = 0;
    bit                     cfg_host_link = 1;
    bit                     cfg_check_pkt = 1; // check incoming RX packet for errors
    int                     drvr_data_handle;

    // PR: watchdog timer; set cfg_rx_timeout=0 to disable
    realtime                cfg_rx_timeout = 0; //1000ns; 
    realtime                tm_last_rx_pkt_in = 0; 

    string fdns; //ADG:: debug
    int                     num_rx, num_tx; 
    bit [2:0] cfg_link_id; //ADG:: debug
    initial begin
        wait (
            mb_tx_pkt       != null &&
            mb_rx_pkt       != null &&
            tx_fi           != null &&
            rx_fi           != null
        );
        
        fork
            timeout_monitor();
            run_tx();
            run_rx();
`ifdef TWO_IN_ONE
            forward_to_systemc();
`endif
        join_none
    end

    // get from mailbox, call bfm task 
    task automatic run_tx();
        var       cls_pkt pkt;
        var   cls_req_pkt req_pkt;
        var   cls_rsp_pkt rsp_pkt;
        var logic [127:0] data[];
        //var logic  [63:0] pkt_data[];
        // these are for the next_xfer function
        var           int credits;
        var  logic [63:0] header;
        var  logic [63:0] tail;
        var  typ_rsp_cmd rsp_cmd;
        var  cls_cad cad;

        // ADG:: debug
        `ifdef ADG_DEBUG
            #1; //
            if (cfg_host_link == 1) begin
                cfg_info_msg  = 1;
                $sformat(fdns, "%0d", cfg_link_id);
                fdns = {"adg_drvr_data_out",fdns,".txt"};
                drvr_data_handle = $fopen(fdns); // ADG:: debug
            end
        `endif

        forever begin
            mb_tx_pkt.peek(pkt);
//            // PR: FIXME: HACK! doesn't work for errors because the retry
//            // block could stall the transaction before it reaches this packet
//            // driver
//`ifdef TWO_IN_ONE
//    if (cfg_host_link) begin //cube side
//            $display("%t %m: DRVR RX: packet %s" , $realtime, pkt.convert2string_short());
//            if ($cast(rsp_pkt, pkt)) begin
//                // 3 is the max number of things per cube cycle that can
//                // return from SC (each has a 1ps delay in
//                // sysc/hmc_2in1_wrapper.cpp)
//                assert($realtime/1ns - rsp_pkt.lat <= 2) else $fatal("%m %t: Response packet %s has added delay (pkt.lat=%0d)", $realtime, pkt.convert2string_short(), rsp_pkt.lat);
//            end
//    end // cube side
//`endif

            //pkt_data = pkt.data;
            //data = {<< 64{pkt_data}}; // reverse the data array
            //data = {<< 128{data}}; // 128 bits at a time
            data = phits2flits(pkt.data);
            header = pkt.get_header();
            tail   = pkt.get_tail();
            
            assert_req_cast: assert ($cast(req_pkt, pkt) || cfg_host_link) else 
                $error("illegal to send responses on a pass-thru link TX: %s", pkt.convert2string());

           if (cfg_info_msg)
               $display("%t %m: driver [%0d] TX: %s", $realtime, cfg_link_id,pkt.convert2string());
               //ADG:: debug
           if (cfg_info_msg && drvr_data_handle && header[5:0] > 6'h03) begin  
               string str_drvr_tx_data; 
               num_tx++;
               if (cfg_check_pkt) begin
                  assert_rsp_cmd_cast: assert ($cast(rsp_cmd, header[5:0])) else
                      $error("casting rsp_cmd failed");
               end
               assert_pkt2cad: assert (req_pkt.get_cad(cad))else 
                    $error("PKT TX: packet could not be converted to cad object");
               str_drvr_tx_data = "";
               if(cfg_host_link == 1) begin //TIE:ADG
                 if (rsp_cmd.name() == "WR_RS" || rsp_cmd.name() == "MD_WR_RS" ) begin
                    $fdisplay(drvr_data_handle,"%t: tx driving write response packet: %s: tag: 'h%h,",$realtime,rsp_cmd.name(),header[23:15]);
                 end 
                 if (rsp_cmd.name() == "RD_RS" || rsp_cmd.name() == "MD_RD_RS" )  begin                
                    foreach (pkt.data[i]) begin
                       string hex_data;
                       $sformat(hex_data, "%8h", pkt.data[i]);
                       str_drvr_tx_data = {hex_data,str_drvr_tx_data};
                    end 
                    $fdisplay(drvr_data_handle,"%t: tx driving read response packet: %s: tag: 'h%h, data: 'h%s;",$realtime,rsp_cmd.name(),header[23:15],str_drvr_tx_data);
                 end 
               end //TIE:ADG
           end 
        
           if (cfg_info_msg) begin
               $display("%t %m: (waiting on tx_fi) DRIVER TX: %s", $realtime,pkt.convert2string());
           end     
            tx_fi.fi.send_pkt(header, data, tail);
            mb_tx_pkt.get(pkt); // free mailbox location

            `ifdef FLOW
               $display("%t %m: (sent on tx_fi) DRIVER TX: %s", $realtime ,pkt.convert2string());
               if (drvr_data_handle && header[5:0] == 1)
                    $fdisplay(drvr_data_handle,"%t: tx driving flow control packet : PRET: rtc: %h; frp: %h; rrp: %h;",$realtime,tail[31:27],tail[15:8],tail[7:0]);
               if (drvr_data_handle && header[5:0] == 2 )
                    $fdisplay(drvr_data_handle,"%t: tx driving flow control packet : TRET: rtc: %h; frp: %h; rrp: %h;",$realtime,tail[31:27],tail[15:8],tail[7:0]);
               if (drvr_data_handle && header[5:0] == 3)
                    $fdisplay(drvr_data_handle,"%t: tx driving flow control packet : IRTRY: rtc: %h; frp: %h; rrp: %h;",$realtime,tail[31:27],tail[15:8],tail[7:0]);
             `endif
        end
    endtask

`ifdef TWO_IN_ONE
    task automatic forward_to_systemc(); 
        forever begin
            rx_fi.fi.forward_to_systemc(); // blocks until packet is available
        end
    endtask
`endif

    task automatic timeout_monitor();
        realtime tm_rx_delta=0;
        forever begin 
            if (cfg_rx_timeout > 0) begin // timeout enabled
                if (tm_last_rx_pkt_in > 0) begin // we've actually seen a packet before (i.e., after link training)
                    tm_rx_delta = $realtime - tm_last_rx_pkt_in;
                    //$display("%t %m: watchdog: have not received any packets for %t (timeout=%t)", $realtime, tm_rx_delta, cfg_rx_timeout);
                    assert(tm_rx_delta < cfg_rx_timeout) else $fatal("%t %m: have not received any packets for %t (timeout=%t)", $realtime, tm_rx_delta, cfg_rx_timeout);
                end
                #( cfg_rx_timeout );
            end else begin // timeout is disabled, so just wait a really long time so we don't keep triggering this loop
                #2s;
            end
        end // forever
    endtask

    // call bfm task, put to mailbox
    task automatic run_rx();
        var       cls_pkt pkt;
        var   cls_req_pkt req_pkt;
        var   cls_rsp_pkt rsp_pkt;

        var logic  [63:0] header;
        //var logic  [63:0] pkt_data[$];
        var logic [127:0] data[]; //, flits[$];
        var logic  [63:0] tail;
        var   typ_rsp_cmd rsp_cmd;
        var   typ_req_cmd req_cmd;
        var       cls_cad cad;
        var           bit poison;

        forever begin
            rx_fi.fi.receive_pkt(header, data, tail); // blocks until packet is available

            if (cfg_host_link) begin // receive request packets
                req_pkt = new();
                pkt = req_pkt;

            end else begin // receive response packets

                //assert_rx_crc: assert (pkt_pkg::gen_crc(header, data, tail) == tail[63:32]) begin
                    if ($cast(rsp_cmd, header[5:0])) begin
                        rsp_pkt = new();
                        pkt = rsp_pkt;
                    end else begin
                        req_pkt = new();
                        pkt = req_pkt;
                    end
                //end else begin
                //    $error("RX CRC Error.  header: %x, tail: %x", header, tail);
                //end
            end
            //pkt_data = {<< 128{data}}; // reverse the data array
            //pkt_data = {<< 64{pkt_data}};
            //pkt.data = pkt_data;
            pkt.data = flits2phits(data);
            pkt.set_header(header);
            pkt.set_tail(tail);

            // Add the SLID as per the spec: "The
            // physical link number is inserted into this [SLID] field by the HMC.
            // The host can ignore these bits with the exception of including
            // them in the CRC calculation." and remember to regenerate the
            // CRC
            // ceusebio: HMC_CMD_HEADER_BITS is not defined in hmc2
            //if (header[`HMC_CMD_HEADER_BITS-1:0] && $cast(req_pkt, pkt)) begin
            // ceusebio: need to check if packet is poisoned
            // if so, invert CRC
            if (header[5:0] && $cast(req_pkt, pkt)) begin
                if (req_pkt.tail.crc == ~req_pkt.gen_crc())
                    poison = 1;
                else
                    poison = 0;
                req_pkt.tail.slid = cfg_link_id;
                req_pkt.tail.crc = req_pkt.gen_crc();
                if (poison)
                    req_pkt.tail.crc = ~req_pkt.tail.crc;
            end

            if (cfg_check_pkt)
                assert_check_pkt: assert (!pkt.check_pkt()) else 
                    $error("%t %m PKT RX: invalid packet: %s", $realtime, pkt.convert2string());

           if (cfg_info_msg && header[5:0] != 0)
                $display("%t %m PKT RX: %s", $realtime, pkt.convert2string());
             //ADG:: debug
           if (cfg_info_msg && drvr_data_handle && header[5:0] > 6'h03) begin 
                   string str_drvr_rx_data; 
                   num_rx++;
                   if (cfg_check_pkt) begin
                      assert_req_cmd_cast: assert ($cast(req_cmd, header[5:0])) else
                             $error("%t %m casting req_cmd failed. %s", $realtime,pkt.convert2string());
                   end
                   assert_pkt2cad: assert (pkt.get_cad(cad))else 
                     $error("%t %m packet could not be converted to cad object.", $realtime);

                   str_drvr_rx_data = "";
                   if (cfg_host_link != 0) begin
                      foreach (pkt.data[i]) begin
                           string hex_rx_data;
                           $sformat(hex_rx_data, "%8h", pkt.data[i]);
                           str_drvr_rx_data = {hex_rx_data,str_drvr_rx_data};
                      end 
                      if (header[5:0] > 6'h03) begin
                         print_cad(cad,"rx",drvr_data_handle); 
                         if (header[5:0] < 6'h30 && pkt.data.size())
                            $fdisplay(drvr_data_handle,"%t: rx driving write request packet : %s: addr: 'h%h, tag: 'h%h, data: 'h%s;",$realtime,req_cmd.name(),header[57:24],header[23:15],str_drvr_rx_data);
                         if (header[5:0] >= 6'h30 && header[5:0] <= 6'h37 )
                            $fdisplay(drvr_data_handle,"%t: rx driving read request packet : %s: addr: 'h%h, tag: 'h%h,",$realtime,req_cmd.name(),header[57:24],header[23:15]);
                      end
                   end //(cfg_host_link != 0)                
           end //(cfg_info_msg && drvr_data_handle && header[5:0] > 6'h03)
         `ifdef FLOW
           if (drvr_data_handle && header[5:0] == 1 && cfg_host_link != 0)
                    $fdisplay(drvr_data_handle,"%t: tx driving flow control packet : PRET: rtc: %h; frp: %h; rrp: %h;",$realtime,tail[31:27],tail[15:8],tail[7:0]);
           if (drvr_data_handle && header[5:0] == 2 && cfg_host_link != 0)
                    $fdisplay(drvr_data_handle,"%t: tx driving flow control packet : TRET: rtc: %h; frp: %h; rrp: %h;",$realtime,tail[31:27],tail[15:8],tail[7:0]);
           if (drvr_data_handle && header[5:0] == 3)
                    $fdisplay(drvr_data_handle,"%t: tx driving flow control packet : IRTRY: rtc: %h; frp: %h; rrp: %h;",$realtime,tail[31:27],tail[15:8],tail[7:0]);
          `endif

            assert_full: assert (mb_rx_pkt.try_put(pkt)) else
                $error("mb_rx_pkt mailbox is full");

            // PR: TODO: write a base class function like
            // "is_non_flow_packet()" to make this less painful?
            if (cfg_rx_timeout > 0 && header) begin // if timeouts enabled
                if ($cast(req_pkt, pkt)) begin
                    if ((req_pkt.header.cmd != PRET) & (req_pkt.header.cmd != TRET) & (req_pkt.header.cmd != IRTRY)) begin // only count "real" packets toward timeout
                        tm_last_rx_pkt_in = $realtime;
                        if (cfg_info_msg)
                            $display("%t %m: resetting watchdog at %t for pkt %s", $realtime, tm_last_rx_pkt_in, pkt.convert2string_short());
                    end
                end else if ($cast(rsp_pkt, pkt)) begin
                    if ((rsp_pkt.header.cmd != PRET) & (rsp_pkt.header.cmd != TRET) & (rsp_pkt.header.cmd != IRTRY)) begin // only count "real" packets toward timeout
                        tm_last_rx_pkt_in = $realtime;
                        if (cfg_info_msg)
                            $display("%t %m: resetting watchdog at %t for pkt %s", $realtime, tm_last_rx_pkt_in, pkt.convert2string_short());
                    end
                end else begin
                    assert(0) else $fatal("unreachable?");
                end
            end
        end        
    endtask

    final begin 
        if (drvr_data_handle) begin 
            $fdisplay(drvr_data_handle, "%t DRIVER SUMMARY: TX Response PACKETS: %0d, RX Reqest PACKETS %0d\n",$realtime, num_tx, num_rx);
            $fclose(drvr_data_handle);
        end
    end
endinterface : hmc_pkt_driver
