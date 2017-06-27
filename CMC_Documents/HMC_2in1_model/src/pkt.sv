//****** hmc_gen2/pkt.sv
// NAME
//    pkt_pkg - SystemVerilog package
// AUTHOR
//    Dave Spatafore <dspatafore@micron.com>
// DESCRIPTION
//    Defines packet classes for HMC link interface
//******
//
// Micron HMC Highly Confidential Information
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

`timescale 1ps/1ps

/*
 Package: pkt_pkg
 The packet package
*/


package pkt_pkg;

// `include "simple.svh"
`include "mvm_corrupter.svh"
import pkg_cad::*;

    
localparam FLIT_W = 128;
localparam PHIT_W = 64;

var int mcd; // multi-channel-descriptor, set by open_tsv funciton

typedef logic [PHIT_W-1:0] typ_phit;
typedef logic [FLIT_W-1:0] typ_flit;
typedef logic  [63:0] typ_phit_arr[];
typedef logic [127:0] typ_flit_arr[];

typedef enum {IDLE,SEND} typ_pkt_status;

// FIXME: PR: MAKE SANE -- this enum is not sorted by values, so it makes it
// very hard to figure out how to write ranges for constraints. Sort by value
// and highlight discontinuities
typedef enum logic [5:0] {
  NULL    = 'h00,
  PRET    = 'h01,
  TRET    = 'h02,
  IRTRY   = 'h03,
  RD16    = 'h30,
`ifdef APG_SPECIAL
  RD32    = 'h2f,//'h31,
`else
  RD32    = 'h31,
`endif
  RD48    = 'h32,
  RD64    = 'h33,
  RD80    = 'h34,
  RD96    = 'h35,
  RD112   = 'h36,
  RD128   = 'h37,
  WR16    = 'h08,
`ifdef APG_SPECIAL
  WR32    = 'h17,//'h09,
`else
  WR32    = 'h09,
`endif
  WR48    = 'h0A,
  WR64    = 'h0B,
  WR80    = 'h0C,
  WR96    = 'h0D,
  WR112   = 'h0E,
  WR128   = 'h0F,
  // PR: THESE ARE NOT CONTIGUOUS -- DO NOT WRITE WR16:P_WR128 UNLESS YOU WANT
  // A BIG PLATE OF DADD8/BWR FAILURE PIE
  P_WR16  = 'h18,
  P_WR32  = 'h19,
  P_WR48  = 'h1A,
  P_WR64  = 'h1B,
  P_WR80  = 'h1C,
  P_WR96  = 'h1D,
  P_WR112 = 'h1E,
  P_WR128 = 'h1F,
  MD_WR   = 'h10,
  BWR     = 'h11,
  DADD8   = 'h12,
`ifdef APG_SPECIAL
  ADD16   = 'h16,//'h13,
`else
  ADD16   = 'h13,
`endif
//  P_MD_WR = 'h20,
  P_BWR   = 'h21,
  P_DADD8 = 'h22,
  P_ADD16 = 'h23,
  MD_RD   = 'h28
} typ_req_cmd;

/*
 Struct: typ_reg_adr
 Register name structure
*/

typedef enum logic [21:0] {
  REQID0  = 'h000000,
  REQID1  = 'h010000,
  REQID2  = 'h020000,
  REQID3  = 'h030000,
  BUFTK0  = 'h040000,
  BUFTK1  = 'h050000,
  BUFTK2  = 'h060000,
  BUFTK3  = 'h070000,
  LKRTY0  = 'h0C0000,
  LKRTY1  = 'h0D0000,
  LKRTY2  = 'h0E0000,
  LKRTY3  = 'h0F0000,
  VLTCTL  = 'h108000,
  LKCTL0  = 'h240000,
  LKRLL0  = 'h240003,
  LKCTL1  = 'h250000,
  LKRLL1  = 'h250003,
  LKCTL2  = 'h260000,
  LKRLL2  = 'h260003,
  LKCTL3  = 'h270000,
  LKRLL3  = 'h270003,
  GLOBAL  = 'h280000,
  BOTSTR  = 'h280002,
  ADRREG  = 'h2C0000
} typ_reg_addr;
/*
 Struct: typ_req_header
 Request header structure
*/
typedef struct packed {
  logic [2:0]   cub;  //63:61
  logic [2:0]   res1;  //60:58
  logic [33:0]  adr;   //57:24
  logic [8:0]   tag;   //23:15
  logic [3:0]   dln;   //14:11
  logic [3:0]   lng;   //10:7
  logic [0:0]   res0;  //6
  typ_req_cmd   cmd;   //5:0
} typ_req_header;

/*
 Struct: typ_req_tail
 Request tail structure
*/
typedef struct packed {
  logic [31:0] crc;  //63:32
  logic [4:0]  rtc;  //31:27
  logic [2:0]  slid; //26:24
  logic [4:0]  res;  //23:19
  logic [2:0]  seq;  //18:16
  logic [7:0]  frp;  //15:8
  logic [7:0]  rrp;  //7:0
} typ_req_tail;

typedef enum logic [5:0] {
  RD_RS    = 6'h38,
  WR_RS    = 6'h39,
  MD_RD_RS = 6'h3A,
  MD_WR_RS = 6'h3B,
  ERROR    = 6'h3E
} typ_rsp_cmd;

/*
 typ_err_stat
*/

typedef enum logic [6:0] {
  NO_ERR       = 7'h00,
  WRN_TEMP       = 7'h01,
  WRN_TOKEN      = 7'h02,
  WRN_REPAIR1    = 7'h05,
  WRN_REPAIR2    = 7'h06,
  ERR_SBE        = 7'h10,
  ERR_MUE        = 7'h1F,
  ERR_LINK0      = 7'h20,
  ERR_LINK1      = 7'h21,
  ERR_LINK2      = 7'h22,
  ERR_LINK3      = 7'h23,
  ERR_CMD        = 7'h30,
  ERR_LNG        = 7'h31,
  ERR_VAULT0     = 7'h60,
  ERR_VAULT1     = 7'h61,
  ERR_VAULT2     = 7'h62,
  ERR_VAULT3     = 7'h63,
  ERR_VAULT4     = 7'h64,
  ERR_VAULT5     = 7'h65,
  ERR_VAULT6     = 7'h66,
  ERR_VAULT7     = 7'h67,
  ERR_VAULT8     = 7'h68,
  ERR_VAULT9     = 7'h69,
  ERR_VAULT10    = 7'h6A,
  ERR_VAULT11    = 7'h6B,
  ERR_VAULT12    = 7'h6C,
  ERR_VAULT13    = 7'h6D,
  ERR_VAULT14    = 7'h6E,
  ERR_VAULT15    = 7'h6F,
  ERR_RETRY_LINK0   = 7'h70,
  ERR_RETRY_LINK1   = 7'h71,
  ERR_RETRY_LINK2   = 7'h72,
  ERR_RETRY_LINK3   = 7'h73,
  ERR_BUF_LINK0     = 7'h78,
  ERR_BUF_LINK1     = 7'h79,
  ERR_BUF_LINK2     = 7'h7A,
  ERR_BUF_LINK3     = 7'h7B,
  ERR_INTR_TEMP     = 7'h7D,
  ERR_PKT_LNG       = 7'h7E,
  ERR_INTR_FATAL    = 7'h7F
} typ_err_stat;

/*
 Struct: typ_rsp_header
 Response header structure
*/
typedef struct packed {
  logic [21:0] res2;  //63:42
  logic [2:0]  slid;  //41:39
  logic [14:0] res1;  //38:24
  logic [8:0]  tag;   //23:15
  logic [3:0]  dln;   //14:11
  logic [3:0]  lng;   //10:7
  logic [0:0]  res0;  //6
  typ_rsp_cmd  cmd;
} typ_rsp_header;

/*
 Struct: typ_rsp_tail
 Response tail structure
*/
typedef struct packed {
  logic [31:0] crc;      //63:32
  logic [4:0]  rtc;      //31:27
  typ_err_stat errstat;  //26:20
  logic [0:0]  dinv;     //19
  logic [2:0]  seq;      //18:16
  logic [7:0]  frp;      //15:8
  logic [7:0]  rrp;      //7:0
} typ_rsp_tail;

function automatic bit must_respond(typ_req_cmd cmd);
  // these commands require a response
  case (cmd)
      RD16  ,
      RD32  ,
      RD48  ,
      RD64  ,
      RD80  ,
      RD96  ,
      RD112 ,
      RD128 ,
      WR16  ,
      WR32  ,
      WR48  ,
      WR64  ,
      WR80  ,
      WR96  ,
      WR112 ,
      WR128 ,
      MD_WR ,
      BWR   ,
      DADD8 ,
      ADD16 ,
      MD_RD   : must_respond = 1;
      default : must_respond = 0;
  endcase
endfunction

function automatic logic [31:0] gen_crc(
    input         [63:0] header,
    const ref    [127:0] data[],
    input         [63:0] tail
);
    var     logic [31:0] crcc = 0;
    var    logic [127:0] flits[];
        
    //flits = {<< 128{data}}; // reverse the data array
    //flits = {<< 128{32'h0, tail[31:0], flits, header}};       
    flits = new [data.size() + 1];
    flits[0] = header;
    foreach (data[i]) begin
        flits[i][127:64] = data[i][63:0];
        flits[i+1][63:0] = data[i][127:64];
    end
    flits[data.size()][127:64] = tail[31:0];

    crcc = 0;
    foreach (flits[i])
        crcc = nextCRC32_D128(flits[i], crcc);              
    return crcc;
endfunction

function automatic typ_flit_arr phits2flits(
    typ_phit_arr phits
);
    //typ_phit_arr tmp_phits;

    assert_mod_2: assert (phits.size() % 2 == 0) else
        $error ("Size must be a multiple of 2.  Actual size = %1d", phits.size());

    //tmp_phits = {<< 64{phits}}; // reverse the array
    //phits2flits = new [(tmp_phits.size() + 1)/2];
    //phits2flits = {<< 128{tmp_phits}}; // 128 bits at a time

    phits2flits = new [phits.size()/2];
    //for (int i=0; i<phits.size()/2; i++) begin
    foreach (phits2flits[i]) begin
        phits2flits[i] = {phits[i*2 + 1], phits[i*2]};
    end
    //if (phits.size())
    //    $display("phits2flits:\nphits:%p\nflits:%p", phits, phits2flits);
endfunction

function automatic typ_phit_arr flits2phits(
    typ_flit_arr flits
);
    //typ_flit_arr tmp_flits;

    //tmp_flits = {<< 128{flits}}; // reverse the array
    //flits2phits = new [tmp_flits.size()*2];
    //flits2phits = {<< 64{tmp_flits}}; // 64 bits at a time
    flits2phits = new [flits.size()*2];
    foreach (flits[i]) begin
        flits2phits[i*2]   = flits[i][63:0];
        flits2phits[i*2+1] = flits[i][127:64];
    end
   //if (flits.size())
   //     $display("flits2phits:\nphits:%p\nflits:%p", flits2phits, flits);
endfunction

/*
 Class: cls_pkt
 The packet base class
*/   
virtual class cls_pkt;

  int flit_count, phit_count, max_flits, max_phits, header_phits, data_phits, tail_phits, data_bytes, nop, lnk_num, rrp;

  typ_phit data[];
    
  bit token_pkt;
  string address_mode;
  time start_time;
  string inst_path;
  bit poison;
  bit [31:0] quad_lut;
  bit [63:0] dest_lut;
  bit [1:0] quad;
  bit [3:0] dest;
  longint unsigned lat; // latency timer
  longint unsigned tok_lat; // token latency timer
  longint unsigned req_lat; // rtc->req or rsp latency timer

`ifdef TWO_IN_ONE
  int unsigned transaction_id; // unique identifier assigned at SC wrapper
`endif

  function new();
    flit_count = 0;
    phit_count = 0;
    max_flits = 0;
    max_phits = 0;
    header_phits = 0;
    data_phits = 0;
    tail_phits = 0;
    data_bytes = 0;
    nop = 0;
    token_pkt = 0;
    lnk_num = 0;
    address_mode = "4GB_128B";
    start_time = $time;
    inst_path = "";
    poison = 0;
    quad_lut = 32'b11_11_11_11_10_10_10_10_01_01_01_01_00_00_00_00;
    dest_lut = 64'h3210321032103210;
`ifdef TWO_IN_ONE
    transaction_id =0;
`endif
  endfunction

  pure virtual function string convert2string();
  pure virtual function string convert2string_short();
  pure virtual function void   set_header(logic [63:0] header);
  pure virtual function void   set_tail(logic [63:0] tail);
  pure virtual function [63:0] get_header();
  pure virtual function [63:0] get_tail();
  pure virtual function logic [31:0] gen_crc();
  pure virtual function void print_tsv(string id = " ");
  pure virtual function int get_tag();

  pure virtual function void pkt_trace(int fd, int link, string id = " ", string extra="");

  virtual function void dsize (int size);
    data_phits = size;
    data = new[data_phits];
  endfunction

  virtual function void build_pkt (ref cls_cad cad, ref int credit_return, input int tag0, input int seq);
    int i = 0;
  endfunction

  virtual function void build_tok (ref int credit_return);
    int i = 0;
  endfunction

  virtual function typ_pkt_status next_xfer (ref int credits,
                                             output typ_flit            flit,
                                             output logic               valid,
                                             output logic               tl,
                                             output logic               phase,
                                             output logic [1:0]         quad,
                                             output logic [3:0]         dest);
    next_xfer = SEND;
  endfunction
  
  pure virtual function typ_pkt_status append_pkt (input logic [FLIT_W-1:0] flit);
  pure virtual function int credits_returned ();
  pure virtual function int retry_ptr_returned ();
  pure virtual function int get_cad (output cls_cad cad);

  function void num(int if_num);
    lnk_num = if_num;
  endfunction

  pure virtual function int check_pkt();
  pure virtual function int check_cmd_lng();
  pure virtual function void seq_num(input int seq);


//define link request LNG field
function int siz_to_bytes(int siz);
  siz_to_bytes = 0;

  //assert_legal_pkt_siz: assert (siz >= 1 & siz <=9)
  //else begin
  //  $error("%s: Illegal packet data size specified: %d", inst_path, siz);
  //end

  if (siz >= 1 & siz <=9) siz_to_bytes = (siz - 1)*16;
endfunction

function int bytes_to_siz(int bytes);
  bytes_to_siz = 1;
  
  assert_legal_cad_bytes: assert (bytes==0 | bytes==8 | bytes==16 | bytes==32 | bytes==48 | bytes==64 | bytes==80 | bytes==96 | bytes==112 | bytes==128)
  else begin
    $error("%s: Illegal data byte count specified: %d", inst_path, bytes);
  end

  bytes_to_siz = bytes/16 + 1;
endfunction

function void set_lut(input bit [31:0] quad_lut, input bit [63:0] dest_lut);
  this.quad_lut = quad_lut;
  this.dest_lut = dest_lut;
endfunction

endclass : cls_pkt





//////////////////////////////
//
//  Request packet class
//
//////////////////////////////



/*
 Class: cls_req_pkt
 The packet request class
*/
class cls_req_pkt extends cls_pkt;

  
  typ_req_header header;
  //typ_phit   data[];
  typ_req_tail   tail;
  
  typ_phit pkt[$];
  //longint adrs;
  logic [31:0]  crc;
  bit           exp_dinv;
    

  function new();
    super.new();
    header = '0;
    tail = '0;
    header_phits = ($bits(header)/PHIT_W);
    tail_phits   = ($bits(tail)/PHIT_W);
    crc = '0;
    exp_dinv = 1'b0;
  endfunction

  function string convert2string();
`ifdef TWO_IN_ONE
    $swriteh(convert2string, "(tid=%0d) header:%p, data.lng:%1d, tail:%p, poison:%1d", transaction_id, header, data.size()/2, tail, poison);
`else
    $swriteh(convert2string, "header:%p, data.lng:%1d, tail:%p, poison:%1d", header, data.size()/2, tail, poison);
`endif
  endfunction

  function string convert2string_short();
    $swriteh(convert2string_short,"cmd:%p adrs:%0h lng:%0d tag:%0d rtc:%0d", header.cmd, header.adr, header.lng, header.tag, tail.rtc); 
  endfunction

  function void print_tsv(string id = " ");
      var cls_cad cad;
      var typ_spec_adrs adrs;

      void'(get_cad(cad));
      adrs = cad.adrs<<1 | cad.byt>>4;

      //$fdisplay(mcd, "time\tslid\tcub\tvlt\tbnk\tdram\ttag\tlng\tcmd\trtc\tseq\tfrp\trrp");
      $fdisplay(pkt_pkg::mcd, "%0.3f\t%s\t%0d\t%0d\t%0d\t%0d\t0x%x\t0x%x\t%0d\t%s\t%0d\t%0d\t%0d\t%0d\t\t%0.3f\t%0.3f",
        $realtime/1ns, id, tail.slid, header.cub, adrs.vlt, adrs.bnk, adrs.dram, header.tag, header.lng, header.cmd.name(), tail.rtc, tail.seq, tail.frp, tail.rrp, tok_lat/1ns, req_lat/1ns);
  endfunction

  function void pkt_trace(int fd, int link, string id = " ", string extra="");
      /*
      $fdisplay(fd, "%0.3f\t%s\t%0d\t%0d\t%s\t%0d\t%0d\t%0d\t%0d\t%0x\t%s",
        $realtime/1ns, id, header.tag, header.lng, header.cmd.name(), tail.rtc, tail.seq, tail.frp, tail.rrp, tail.crc, extra);
    */
  endfunction

  function void   set_header(logic [63:0] header);
    this.header = header;
  endfunction

  function void   set_tail(logic [63:0] tail);
    this.tail = tail;
  endfunction

  function int get_tag();
    get_tag = header.tag;
  endfunction

  function [63:0] get_header();
    get_header = header;
  endfunction

  function [63:0] get_tail();
    get_tail = tail;
  endfunction

  function bit must_respond();
    must_respond =  pkt_pkg::must_respond(header.cmd);
  endfunction

  function int credits_returned ();
    credits_returned = tail.rtc;
  endfunction

  function int retry_ptr_returned ();
    retry_ptr_returned = tail.frp;
  endfunction

  function void seq_num(input int seq);
    tail.seq = seq;
    if (rrp != -1) tail.rrp = rrp;
    tail.crc = '0;
    pkt = {};
    for (int i=0; i<header_phits; i++) pkt.push_back(header[i*PHIT_W+:PHIT_W]);
    for (int i=0; i<data_phits;   i++) pkt.push_back(data[i]);
    for (int i=0; i<tail_phits;   i++) pkt.push_back(tail[i*PHIT_W+:PHIT_W]);
    crc = '0;
    for (int i=0; i<max_flits; i++) begin
      crc = nextCRC32_D128({pkt[i*2+1],pkt[i*2]},crc);
      //$display("Calc CRC: %h, flit %h", crc, {pkt[i*2+1],pkt[i*2]});
    end
    tail.crc = crc; 
    for (int i=0; i<tail_phits;   i++) void'(pkt.pop_back());
    for (int i=0; i<tail_phits;   i++) pkt.push_back(tail[i*PHIT_W+:PHIT_W]);
  endfunction

  function void build_pkt (ref cls_cad cad, ref int credit_return, input int tag0, input int seq);
    data_bytes = cad.dbytes;

    case (cad.cmd)
      enu_write: begin //Write
      
        data_phits = data_bytes * 8 / PHIT_W;
        data = new[data_phits];

        for (int i=0;i<data_phits;i++) begin
          for (int j=0;j<PHIT_W;j++) begin
            data[i][j] = cad.data[(i*PHIT_W+j)/32][(i*PHIT_W+j)%32];
          end
        end

        //tail.crc = crc;
      
        if (cad.rsp)
          case (data_bytes)
            0:    header.cmd = WR16;
            16:   header.cmd = WR16;
            32:   header.cmd = WR32;
            48:   header.cmd = WR48;
            64:   header.cmd = WR64;
            80:   header.cmd = WR80;
            96:   header.cmd = WR96;
            112:  header.cmd = WR112;
            128:  header.cmd = WR128;
          endcase
        else
          case (data_bytes)
            0:    header.cmd = P_WR16;
            16:   header.cmd = P_WR16;
            32:   header.cmd = P_WR32;
            48:   header.cmd = P_WR48;
            64:   header.cmd = P_WR64;
            80:   header.cmd = P_WR80;
            96:   header.cmd = P_WR96;
            112:  header.cmd = P_WR112;
            128:  header.cmd = P_WR128;
          endcase

        header.lng = bytes_to_siz(data_bytes);
        header.dln = bytes_to_siz(data_bytes);
      end
      enu_read: begin //Read
        header.lng = 1;
        header.dln = 1;

        case (data_bytes)
          0:    header.cmd = RD16; 
          16:   header.cmd = RD16; 
          32:   header.cmd = RD32; 
          48:   header.cmd = RD48; 
          64:   header.cmd = RD64; 
          80:   header.cmd = RD80; 
          96:   header.cmd = RD96; 
          112:  header.cmd = RD112; 
          128:  header.cmd = RD128;
        endcase
      end
      enu_bwrite: begin //Bit Write
     
        data_phits = 2;
        data = new[data_phits];

        for (int i=0;i<data_phits;i++) begin
          for (int j=0;j<PHIT_W;j++) begin
            data[i][j] = cad.data[(i*PHIT_W+j)/32][(i*PHIT_W+j)%32];
          end
        end
          if (cad.rsp)
            header.cmd = BWR;
          else
          header.cmd = P_BWR;

        header.lng = 2;
        header.dln = 2;
      end
      enu_mwrite: begin //Mode Write
        data_phits = 2;
        data = new[data_phits];

        for (int i=0;i<data_phits;i++) begin
          for (int j=0;j<PHIT_W;j++) begin
            data[i][j] = cad.data[(i*PHIT_W+j)/32][(i*PHIT_W+j)%32];
          end
        end
//        if (cad.rsp)
          header.cmd = MD_WR;
//        else
//          header.cmd = P_MD_WR;

        header.lng = 2;
        header.dln = 2;
        address_mode = "direct";
      end
      enu_mread: begin //Mode Read
        header.cmd = MD_RD;

        header.lng = 1;
        header.dln = 1;
        address_mode = "direct";
      end
      enu_2add8: begin //Dual add 8
        data_phits = 2;
        data = new[data_phits];

        for (int i=0;i<data_phits;i++) begin
          for (int j=0;j<PHIT_W;j++) begin
            data[i][j] = cad.data[(i*PHIT_W+j)/32][(i*PHIT_W+j)%32];
          end
        end
        if (cad.rsp)
          header.cmd = DADD8;
        else
          header.cmd = P_DADD8;

        header.lng = 2;
        header.dln = 2;
      end
      enu_add16: begin //Add 16
      
        data_phits = 2;
        data = new[data_phits];

        for (int i=0;i<data_phits;i++) begin
            for (int j=0;j<PHIT_W;j++) begin
                data[i][j] = cad.data[(i*PHIT_W+j)/32][(i*PHIT_W+j)%32];
            end
        end
        if (cad.rsp)
          header.cmd = ADD16;
        else
          header.cmd = P_ADD16;

        header.lng = 2;
        header.dln = 2;
      end
      default: begin 
        assert (0) else
            $error("Illegal Request: %s", cad.cmd.name()); 
      end
    endcase

    header.cub = cad.cube;
    case (address_mode)
        "direct"    :
                header.adr = cad.adrs;
        "vp_tb"    :
                header.adr = {cad.adrs,cad.byt[4:0]};
        "2GB_32B"    :                                        // 2GB 32B Max Packet Size
            begin
                header.adr[33:31] = 0;                   // Not Used
                header.adr[30:18] = cad.adrs.row[12:0];  // row
                header.adr[17:12] = cad.adrs.col[5:0];   // col
                header.adr[11]    = cad.adrs.sta[0];     // strata  (expand to two bits for 4G)
                header.adr[10:9]  = cad.adrs.bnk[1:0];   // bank
                header.adr[8:5]   = cad.adrs.vlt[3:0];   // vault
                header.adr[4:0]   = cad.byt[4:0];        // byte
            end
        "2GB_64B"    :                                        // 2GB 64B Max Packet Size
            begin
                header.adr[33:31] = 0;                   // Not Used
                header.adr[30:18] = cad.adrs.row[12:0];  // row
                header.adr[17:13] = cad.adrs.col[5:1];   // col
                header.adr[12]    = cad.adrs.sta[0];     // strata  (expand to two bits for 4G)
                header.adr[11:10] = cad.adrs.bnk[1:0];   // bank
                header.adr[9:6]   = cad.adrs.vlt[3:0];   // vault
                header.adr[5]     = cad.adrs.col[0];     // col
                header.adr[4:0]   = cad.byt[4:0];        // byte
            end
        "2GB_128B"    :                                        // 2GB 128B Max Packet Size
            begin
                header.adr[33:31] = 0;                   // Not Used
                header.adr[30:18] = cad.adrs.row[12:0];  // row
                header.adr[17:14] = cad.adrs.col[5:2];   // col
                header.adr[13]    = cad.adrs.sta[0];     // strata  (expand to two bits for 4G)
                header.adr[12:11] = cad.adrs.bnk[1:0];   // bank
                header.adr[10:7]  = cad.adrs.vlt[3:0];   // vault
                header.adr[6:5]   = cad.adrs.col[1:0];   // col
                header.adr[4:0]   = cad.byt[4:0];        // byte
            end
        "4GB_32B"    :                                        // 4GB 32B Max Packet Size
            begin
                header.adr[33:32] = 0;                   // Not Used
                header.adr[31:19] = cad.adrs.row[12:0];  // row
                header.adr[18:13] = cad.adrs.col[5:0];   // col
                header.adr[12:11] = cad.adrs.sta[1:0];   // strata  (expand to two bits for 4G)
                header.adr[10:9]  = cad.adrs.bnk[1:0];   // bank
                header.adr[8:5]   = cad.adrs.vlt[3:0];   // vault
                header.adr[4:0]   = cad.byt[4:0];        // byte
            end
        "4GB_64B"    :                                        // 4GB 64B Max Packet Size
            begin
                header.adr[33:32] = 0;                   // Not Used
                header.adr[31:19] = cad.adrs.row[12:0];  // row
                header.adr[18:14] = cad.adrs.col[5:1];   // col
                header.adr[13:12] = cad.adrs.sta[1:0];   // strata  (expand to two bits for 4G)
                header.adr[11:10] = cad.adrs.bnk[1:0];   // bank
                header.adr[9:6]   = cad.adrs.vlt[3:0];   // vault
                header.adr[5]     = cad.adrs.col[0];     // col
                header.adr[4:0]   = cad.byt[4:0];        // byte
            end
        "4GB_128B"    :                                        // 4GB 128B Max Packet Size
            begin
                header.adr[33:32] = 0;                   // Not Used
                header.adr[31:19] = cad.adrs.row[12:0];  // row
                header.adr[18:15] = cad.adrs.col[5:2];   // col
                header.adr[14:13] = cad.adrs.sta[1:0];   // strata  (expand to two bits for 4G)
                header.adr[12:11] = cad.adrs.bnk[1:0];   // bank
                header.adr[10:7]  = cad.adrs.vlt[3:0];   // vault
                header.adr[6:5]   = cad.adrs.col[1:0];   // col
                header.adr[4:0]   = cad.byt[4:0];        // byte
            end
        default : 
            assert (0) else
                $error("Invalid address_mode: %s", address_mode); 
    endcase



    header.tag = cad.id.tag;
    nop = cad.nop;

    //if (address_mode == "direct" | address_mode == "vp_tb") tail.slid = cad.id.lnk;
    tail.slid = cad.id.lnk;
    
    tail.seq = seq;
    if (credit_return > 31)
      tail.rtc = 31;
    else
      tail.rtc = credit_return;
    credit_return -= tail.rtc;


    max_phits = header_phits+data_phits+tail_phits;
    max_flits = max_phits/(FLIT_W/PHIT_W);
    
    tail.crc = '0;
    for (int i=0; i<header_phits; i++) pkt.push_back(header[i*PHIT_W+:PHIT_W]);
    for (int i=0; i<data_phits;   i++) pkt.push_back(data[i]);
    for (int i=0; i<tail_phits;   i++) pkt.push_back(tail[i*PHIT_W+:PHIT_W]);
    crc = '0;
    for (int i=0; i<max_flits; i++) begin
      crc = nextCRC32_D128({pkt[i*2+1],pkt[i*2]},crc);
      //$display("Calc CRC: %h, flit %h", crc, {pkt[i*2+1],pkt[i*2]});
    end
    tail.crc = crc; 
    for (int i=0; i<tail_phits;   i++) void'(pkt.pop_back());
    for (int i=0; i<tail_phits;   i++) pkt.push_back(tail[i*PHIT_W+:PHIT_W]);

    quad = quad_lut[cad.adrs.vlt[3:0]*2+:2];
    dest = dest_lut[cad.adrs.vlt[3:0]*4+:4];

  endfunction




  function typ_pkt_status next_xfer (ref int credits,
                                     output typ_flit            flit,
                                     output logic               valid,
                                     output logic               tl,
                                     output logic               phase,
                                     output logic [1:0]         quad,
                                     output logic [3:0]         dest);
    flit = '0;
    valid = 0;
    tl = '0;
    phase = '0;
    quad = '0;
    dest = '0;
    
    if (credits>0) begin
      for (int i=0; i<(FLIT_W/PHIT_W); i++) begin
        flit[i*PHIT_W+:PHIT_W] = pkt[phit_count];
        //$display("phit %h", pkt[phit_count]);
        phit_count++;
      end
      valid=1;
      //$display("Driver flit TX %h  time %t flit_count %d", flit, $time, flit_count);
      credits--;
      flit_count++;
      phase = ~(&header.cmd[5:3]);
      if (header.cmd[5:3] != 3'b111) begin
          quad = this.quad ;      
          dest = this.dest ;
      end    
    end
    
    if (flit_count==max_flits) begin
      tl = 1;
      next_xfer = IDLE;
    end
    else
      next_xfer = SEND;



  endfunction


  function typ_pkt_status append_pkt (input logic [FLIT_W-1:0] flit);
    //$display("Driver flit RX %h  time %t flit_count %d", flit, $time, flit_count);
    //$display("append_pkt, flit_count %d, header_ph %d, data_ph %d tail_ph %d", flit_count, header_phits, data_phits, tail_phits);
    for (int i=0; i<(FLIT_W/PHIT_W); i++) begin
      if (phit_count < header_phits) begin
          header[phit_count*i*PHIT_W+:PHIT_W] = flit[i*PHIT_W+:PHIT_W];
          phit_count++;
          //$display("RX HEADER %h phit_count %d  time %t", flit[i*PHIT_W+:PHIT_W], phit_count,  $time);
      end
      else if (phit_count >= header_phits & phit_count < data_phits+header_phits) begin
          data[phit_count-header_phits] = flit[i*PHIT_W+:PHIT_W];
          phit_count++;
          //$display("RX DATA %h phit_count %d time %t", flit[i*PHIT_W+:PHIT_W], phit_count, $time);
      end
      else if (phit_count >= data_phits+header_phits) begin
          tail[(phit_count-header_phits-data_phits)*i*PHIT_W+:PHIT_W] = flit[i*PHIT_W+:PHIT_W];
          phit_count++;
          //$display("RX TAIL %h phit_count %d time %t", flit[i*PHIT_W+:PHIT_W], phit_count, $time);
      end

      if (phit_count==header_phits) begin
        data_bytes = siz_to_bytes(header.lng);
        data_phits = data_bytes * 8 / PHIT_W;
        max_phits = header_phits+data_phits+tail_phits;
        max_flits = max_phits/(FLIT_W/PHIT_W);
        data = new[data_phits];
      end
    end
    flit_count++;
    
    if (flit_count==max_flits) begin 
      crc = nextCRC32_D128({32'b0,flit[FLIT_W-1-32:0]}, crc);
      //$display("Check CRC %h, flit %h", crc, {32'b0,flit[FLIT_W-1-32:0]});
      if (~crc==tail.crc) poison = 1;
      append_pkt = IDLE;
    end
    else begin
      crc = nextCRC32_D128(flit, crc);
      
      //$display("Check CRC %h, flit %h", crc, flit);
      append_pkt = SEND;
    end  
  
  endfunction


  function int get_cad (output cls_cad cad);
    cls_cad new_cad = new();
    new_cad.new_cad();
    new_cad.rsp = 1;
    
    if (header.cmd >= WR16 & header.cmd <= WR128 | header.cmd >= P_WR16 & header.cmd <= P_WR128) begin
      new_cad.cmd = enu_write;
      new_cad.dbytes = siz_to_bytes(header.lng);
      if (header.cmd >= P_WR16 & header.cmd <= P_WR128) new_cad.rsp = 0;
    end
    else if (header.cmd >= RD16 & header.cmd <= RD128) begin 
      new_cad.cmd = enu_read;
      case (header.cmd)
        RD16:   new_cad.dbytes = 16;
        RD32:   new_cad.dbytes = 32;
        RD48:   new_cad.dbytes = 48;
        RD64:   new_cad.dbytes = 64;
        RD80:   new_cad.dbytes = 80;
        RD96:   new_cad.dbytes = 96;
        RD112:  new_cad.dbytes = 112;
        RD128:  new_cad.dbytes = 128;
      endcase
    end
    else if (header.cmd == BWR | header.cmd == P_BWR) begin
      new_cad.cmd = enu_bwrite;
      new_cad.dbytes = 16;
      if (header.cmd == P_BWR) new_cad.rsp = 0;
    end
//    else if (header.cmd == MD_WR | header.cmd == P_MD_WR) begin
    else if (header.cmd == MD_WR ) begin
      new_cad.cmd = enu_mwrite;
      new_cad.dbytes = 16;
//      if (header.cmd == P_MD_WR) new_cad.rsp = 0;
    end
    else if (header.cmd == MD_RD) begin
      new_cad.cmd = enu_mread;
      new_cad.dbytes = 16;
    end
    else if (header.cmd == DADD8 | header.cmd == P_DADD8) begin
      new_cad.cmd = enu_2add8;
      new_cad.dbytes = 16;
      if (header.cmd == P_DADD8) new_cad.rsp = 0;
    end
    else if (header.cmd == ADD16 | header.cmd == P_ADD16) begin
      new_cad.cmd = enu_add16;
      new_cad.dbytes = 16;
      if (header.cmd == P_ADD16) new_cad.rsp = 0;
    end
    
    //new_cad.adrs = header.adr;
    new_cad.cube = header.cub;

    case (address_mode)
        "direct"    :
                new_cad.adrs = header.adr;
        "vp_tb"    :
                {new_cad.adrs,new_cad.byt[4:0]} = header.adr;
        "2GB_32B"    :                                        // 2GB 32B Max Packet Size
            begin
                new_cad.adrs.row[12:0] = header.adr[30:18];   // row
                new_cad.adrs.col[5:0]  = header.adr[17:12];   // col
                new_cad.adrs.sta[0]    = header.adr[11];      // strata  (expand to two bits for 4G)
                new_cad.adrs.bnk[1:0]  = header.adr[10:9];    // bank
                new_cad.adrs.vlt[3:0]  = header.adr[8:5];     // vault
                new_cad.byt[4:0]       = header.adr[4:0];     // byte
            end
        "2GB_64B"    :                                        // 2GB 64B Max Packet Size
            begin
                new_cad.adrs.row[12:0] = header.adr[30:18];   // row
                new_cad.adrs.col[5:1]  = header.adr[17:13];   // col
                new_cad.adrs.sta[0]    = header.adr[12];      // strata  (expand to two bits for 4G)
                new_cad.adrs.bnk[1:0]  = header.adr[11:10];   // bank
                new_cad.adrs.vlt[3:0]  = header.adr[9:6];     // vault
                new_cad.adrs.col[0]    = header.adr[5];       // col
                new_cad.byt[4:0]       = header.adr[4:0];     // byte
            end
        "2GB_128B"    :                                        // 2GB 128B Max Packet Size
            begin
                new_cad.adrs.row[12:0] = header.adr[30:18];   // row
                new_cad.adrs.col[5:2]  = header.adr[17:14];   // col
                new_cad.adrs.sta[0]    = header.adr[13];      // strata  (expand to two bits for 4G)
                new_cad.adrs.bnk[1:0]  = header.adr[12:11];   // bank
                new_cad.adrs.vlt[3:0]  = header.adr[10:7];    // vault
                new_cad.adrs.col[1:0]  = header.adr[6:5];     // col
                new_cad.byt[4:0]       = header.adr[4:0];     // byte
            end
        "4GB_32B"    :                                        // 4GB 32B Max Packet Size
            begin
                new_cad.adrs.row[12:0] = header.adr[31:19];   // row
                new_cad.adrs.col[5:0]  = header.adr[18:13];   // col
                new_cad.adrs.sta[1:0]  = header.adr[12:11];   // strata  (expand to two bits for 4G)
                new_cad.adrs.bnk[1:0]  = header.adr[10:9];    // bank
                new_cad.adrs.vlt[3:0]  = header.adr[8:5];     // vault
                new_cad.byt[4:0]       = header.adr[4:0];     // byte
            end
        "4GB_64B"    :                                        // 4GB 64B Max Packet Size
            begin
                new_cad.adrs.row[12:0] = header.adr[31:19];   // row
                new_cad.adrs.col[5:1]  = header.adr[18:14];   // col
                new_cad.adrs.sta[1:0]  = header.adr[13:12];   // strata  (expand to two bits for 4G)
                new_cad.adrs.bnk[1:0]  = header.adr[11:10];   // bank
                new_cad.adrs.vlt[3:0]  = header.adr[9:6];     // vault
                new_cad.adrs.col[0]    = header.adr[5];       // col
                new_cad.byt[4:0]       = header.adr[4:0];     // byte
            end
        "4GB_128B"    :                                        // 4GB 128B Max Packet Size
            begin
                new_cad.adrs.row[12:0] = header.adr[31:19];  // row
                new_cad.adrs.col[5:2]  = header.adr[18:15];  // col
                new_cad.adrs.sta[1:0]  = header.adr[14:13];  // strata  (expand to two bits for 4G)
                new_cad.adrs.bnk[1:0]  = header.adr[12:11];  // bank
                new_cad.adrs.vlt[3:0]  = header.adr[10:7];   // vault
                new_cad.adrs.col[1:0]  = header.adr[6:5];    // col
                new_cad.byt[4:0]       = header.adr[4:0];    // byte
            end

        default : 
            assert (0) else
                $error("Invalid address_mode: %s", address_mode); 
    endcase


    data_bytes = new_cad.dbytes;
    
    //for (int i=0;i<data_burst;i++)
    //  new_cad.data[i*FLIT_W+:FLIT_W] = data[i];

    for (int i=0;i<data_bytes*8/32;i++) begin
      for (int j=0;j<32;j++) begin
        new_cad.data[i][j] = data[(i*32+j)/PHIT_W][(i*32+j)%PHIT_W];
      end
      new_cad.dmask[i] = 0;
    end


    new_cad.id.tag = header.tag;
    new_cad.id.lnk = tail.slid;
    new_cad.lat = this.lat;
//    new_cad.tok_lat = 0;
    new_cad.phase = enu_req;
    cad = new_cad;  //return pkt converted to cad;
      get_cad = 1;
  endfunction
    function int check_cmd_lng();
        return (
           header.cmd==WR16    & header.lng==2 ||
           header.cmd==WR32    & header.lng==3 ||
           header.cmd==WR48    & header.lng==4 ||
           header.cmd==WR64    & header.lng==5 ||
           header.cmd==WR80    & header.lng==6 ||
           header.cmd==WR96    & header.lng==7 ||
           header.cmd==WR112   & header.lng==8 ||
           header.cmd==WR128   & header.lng==9 ||

           header.cmd==MD_WR   & header.lng==2 ||
           header.cmd==BWR     & header.lng==2 ||
           header.cmd==DADD8   & header.lng==2 ||
           header.cmd==ADD16   & header.lng==2 ||

           header.cmd==P_WR16  & header.lng==2 ||
           header.cmd==P_WR32  & header.lng==3 ||
           header.cmd==P_WR48  & header.lng==4 ||
           header.cmd==P_WR64  & header.lng==5 ||
           header.cmd==P_WR80  & header.lng==6 ||
           header.cmd==P_WR96  & header.lng==7 ||
           header.cmd==P_WR112 & header.lng==8 ||
           header.cmd==P_WR128 & header.lng==9 ||
           
           header.cmd==PRET    & header.lng==1 ||
           header.cmd==TRET    & header.lng==1 ||
           header.cmd==IRTRY   & header.lng==1 ||
          
           header.cmd==P_BWR   & header.lng==2 ||
           header.cmd==P_DADD8 & header.lng==2 ||
           header.cmd==P_ADD16 & header.lng==2 ||

           header.cmd==RD16    & header.lng==1 ||
           header.cmd==RD32    & header.lng==1 ||
           header.cmd==RD48    & header.lng==1 ||
           header.cmd==RD64    & header.lng==1 ||
           header.cmd==RD80    & header.lng==1 ||
           header.cmd==RD96    & header.lng==1 ||
           header.cmd==RD112   & header.lng==1 ||
           header.cmd==RD128   & header.lng==1 ||
           
           header.cmd==MD_RD   & header.lng==1);
    endfunction
    /*
     Function: check_pkt
     Checks the packet for valid values in fields
     */
    function int check_pkt(); 
    begin : blk_check_pkt
        
        // Hierarchy of request packet errors - first error in the
        // list found will return 1 and exit function
        //
        // NAME               ASSERTION
        // ----------------------------------------
        // CRC FAILURE      - assert_req_crc
        // CRC Posion       - assert_req_crc_poison
        // LNG / DLN w/Posion assert_req_dln_posion
        // --- ABOVE ERROR WILL STOP CHECKS BELOW
        // VALID CMD        - assert_req_cmd_valid
        // LNG / DLN MATCH  - assert_req_dln
        // POSTED WRITE TAG - assert_req_tag_posted ($info only)
        // CMD / LEN MATCH  - assert_req_cmd_lng
        // NULL FLIT CHECK  - assert_req_null_pkt
        // FLOW ADRS CHECK  - assert_req_flow_adrs_pkt
        // FLOW FRP CHECK   - assert_req_flow_frp_pkt
        // FLOW RTC CHECK   - assert_req_flow_rtc_pkt
        // FLOW SEQ CHECK   - assert_req_flow_seq_pkt
        // FLOW TAG CHECK   - assert_req_flow_tag_pkt
        // ADR MSB ZEROES   - assert_req_adrs_msb_zeroes ($info only)
        // RESERVED FIELDS  - assert_req_header_reserved_zeroes ($info only)
        // RESERVED FIELDS  - assert_req_tail_reserved_zeroes ($info only)
        // -- assert_tail_reserved_zeroes cannot be used
        // REQ DATA SIZE    - assert_rsp_data_size
        // REQ 2GIG ZEROES  - assert_req_adrs_2gig_zeroes
        // REQ ADDRESS MODE - assert_req_address_mode_error
        // REQ assert dadd8 - assert_req_dadd8_zeroes
        // REQ assert md_wr - assert_req_mode_wr_zeroes
        
        /*
         Variable: data_size
         A temporary variable to store the size of the data queue
         */
        int data_size;
        
        /*        
         Variable: crcc
         A temporary variable to store the value of the calculated crc
         */
        logic [31:0]      crcc = 0;

        /*
         Variable: exp_data
         A temporary variable to store expected and actual data strings
         */
        string            exp_data;
        string            act_data;
        
        crcc = gen_crc();

        // save the size of the data object because it is used a lot
        // in the test
        data_size = data.size();
        
        // start with check_pkt being good
        check_pkt = 0;       

        // lng and dln should match even during poision crc
        assert_req_dln: assert (header.lng==header.dln)
          else begin
              $error("Request LNG/DLN mismatch, LNG=%d DLN=%d", header.lng, header.dln);
              check_pkt = 1;
          end

        assert_req_crc: assert (tail.crc==crcc || tail.crc==~crcc)
          else begin
              $error("Request CRC Error, CRC=%h Expected=%h", tail.crc, crcc);
              return 1;
          end

        assert_req_cmd_valid: assert
          (
           header.cmd==WR16    ||
           header.cmd==WR32    ||
           header.cmd==WR48    ||
           header.cmd==WR64    ||
           header.cmd==WR80    ||
           header.cmd==WR96    ||
           header.cmd==WR112   ||
           header.cmd==WR128   ||
           
           header.cmd==MD_WR   ||
           header.cmd==BWR     ||
           header.cmd==DADD8   ||
           header.cmd==ADD16   ||
           
           header.cmd==P_WR16  ||
           header.cmd==P_WR32  ||
           header.cmd==P_WR48  ||
           header.cmd==P_WR64  ||
           header.cmd==P_WR80  ||
           header.cmd==P_WR96  ||
           header.cmd==P_WR112 ||
           header.cmd==P_WR128 ||
           
           header.cmd==P_BWR   ||
           header.cmd==P_DADD8 ||
           header.cmd==P_ADD16 ||
           
           header.cmd==RD16    ||
           header.cmd==RD32    ||
           header.cmd==RD48    ||
           header.cmd==RD64    ||
           header.cmd==RD80    ||
           header.cmd==RD96    ||
           header.cmd==RD112   ||
           header.cmd==RD128   ||
           header.cmd==MD_RD   ||

           // valid flow commands
           header.cmd==PRET    ||
           header.cmd==TRET    ||
           header.cmd==IRTRY   ||
           // Null command
           int'(header.cmd)==0 ||
           
           // if crc inversion poison
           tail.crc==~crcc)
          else begin
              $error("Request CMD=%5h not valid", header.cmd);
          end
        
        /*
        // if a posted write raise an info if the tag field is not
        // zero
        if (header.cmd==P_WR16  & header.lng==2 ||
            header.cmd==P_WR32  & header.lng==3 ||
            header.cmd==P_WR48  & header.lng==4 ||
            header.cmd==P_WR64  & header.lng==5 ||
            header.cmd==P_WR80  & header.lng==6 ||
            header.cmd==P_WR96  & header.lng==7 ||
            header.cmd==P_WR112 & header.lng==8 ||
            header.cmd==P_WR128 & header.lng==9)
        begin
            assert_req_tag_posted: assert (header.tag == 0)
              else begin
                  $info("A POSTED WRITE command with a TAG other than zero - can be any value but recommend zero: CMD=%s TAG=%h", header.cmd.name(), header.tag);
                  // $assertoff(1, assert_req_tag_posted); // only issue this info one time
              end                          
        end
        */
        
        // compare cmd field with the correct packet length
        // if crc is inverted that is okay too
        assert_req_cmd_lng: assert
          (
            
           int'(header.cmd)==0 & header.lng==0 ||
            check_cmd_lng() ||
           
           tail.crc==~crcc)
          
          // make sure that the cmd field has valid values         
          else begin
              $error("Request CMD/LNG mismatch, CMD=%s LNG=%d", header.cmd.name(), header.lng);
          end        
        
        // if cmd is zero the whole header and tail must be zero
        if (int'(header.cmd) == 0) begin
            assert_req_null_pkt: assert (header==0 && tail==0)
              else begin
                  $error("Request CMD is NULL - header and tail must be 0, header=%h tail=%h", header, tail);
              end
        end
        
        // if FLOW command
        if (int'(header.cmd) == 0 || header.cmd == PRET || header.cmd == TRET || header.cmd == IRTRY) begin
            assert_req_flow_adrs_pkt: assert (header.adr==0)
              else begin
                  $error("Request a FLOW CMD - HEADER ADR must be 0, CMD=%s header=%h", header.cmd.name(), header.adr);
              end

            assert_req_flow_tag_pkt: assert (header.tag==0)
              else begin
                  $error("Request a NULL/PRET/IRTRY CMD - HEADER TAG MUST BE 0, CMD=%s header.tag=%h", header.cmd.name(), header.tag);
              end

        end

        // if FLOW subset
        assert_req_flow_frp_pkt: assert (tail.frp==0 || (header.cmd && header.cmd != PRET)) else
            $error("Request a NULL/PRET CMD - TAIL FRP MUST BE 0, CMD=%s tail.frp=%h", header.cmd.name(), tail.frp);
        
        assert_req_irtry_frp_pkt: assert (tail.frp[7:2]==0 || header.cmd != IRTRY) else begin
            $warning("Request a IRTRY CMD - TAIL FRP[7:2] are not used during IRTRY command, CMD=%s tail.frp=%h", header.cmd.name(), tail.frp);
            // $assertoff(1, assert_req_irtry_frp_pkt); // only issue this warning one time
        end

        assert_req_flow_rtc_pkt: assert (tail.rtc==0 || (header.cmd && header.cmd != PRET && header.cmd != IRTRY)) else
            $error("Request a NULL/PRET/IRTRY CMD - TAIL RTC MUST BE 0, CMD=%s tail.rtc=%h", header.cmd.name(), tail.rtc);

        assert_req_flow_seq_pkt: assert (tail.seq==0 || (header.cmd && header.cmd != PRET && header.cmd != IRTRY)) else
            $error("Request a NULL/PRET/IRTRY CMD - TAIL SEQ MUST BE 0, CMD=%s tail.seq=%h", header.cmd.name(), tail.seq);

        // currently the two MSB of the adr are not used in current
        // designs - they should be zero for now
        assert_req_adrs_msb_zeroes: assert (header.adr[33:32]==0)
          else begin
              $warning("Nonzero adr[32:32] are not used.  header.adr[33:32]='h%h are ignored by the HMC", header.adr[33:32]);
              // $assertoff(1, assert_req_adrs_msb_zeroes); // only issue this warning one time
          end

        // RESERVED FIELDS  - assert_header_reserved_zeroes ($info only)
        assert_req_header_reserved_zeroes: assert (!header.res0 && !header.res1)
        else begin
            $warning("Nonzero header reserved fields.  Header[6]='h%h and header[60:58]='h%h are ignored by the HMC", header.res0, header.res1);
            // $assertoff(1, assert_req_header_reserved_zeroes); // only issue this warning one time
        end

        // RESERVED FIELDS  - assert_req_tail_reserved_zeroes ($info only)
        // HMC is using these fields
        assert_req_tail_reserved_zeroes: assert (!tail.res)
        else begin
            $warning("Nonzero tail reserved field.  Tail[23:19]='h%h is ignored by the HMC", tail.res);
            // $assertoff(1, assert_req_tail_reserved_zeroes); // only issue this warning one time
        end

        // data_size is 64 bit chunks but a flit is 128 bit chunks
        // the maximum data payload is 128 bytes which is 1024 bits
        // making the maximum data size 1024 / 64 = 16
        assert_req_data_size: assert (
            ( header.lng==0 && data_size==0 ) ||
            ( header.lng==1 && data_size==0 ) ||
            ( header.lng==2 && data_size==2 ) ||
            ( header.lng==3 && data_size==4 ) ||
            ( header.lng==4 && data_size==6 ) ||
            ( header.lng==5 && data_size==8 ) ||
            ( header.lng==6 && data_size==10 ) ||                                      
            ( header.lng==7 && data_size==12 ) ||
            ( header.lng==8 && data_size==14 ) ||
            ( header.lng==9 && data_size==16 ) ||
            tail.crc==~crc                                  
        ) 
          else begin
              $error("REQ DATA SIZE VERSUS CMD CHECK CMD=%s LNG=%h data.size()=%h", header.cmd.name(), header.lng, data_size);
          end     


        // BWR command requires zeros in header.adr[2:0]
        assert_req_adrs_bwr_zeroes: assert ((header.cmd!=BWR && header.cmd!=P_BWR) || header.adr[2:0] == 0) else
            $error("Nonzero address bits during %s command.  header.adr[2:0] must be 000 - header.adr=%h", header.cmd.name(), header.adr);

        // data_size check for assertions on data payload
        if (data_size >= 2)
        begin

            // DADD8 dual 8 byte add immediate assertion on data payload zeroes
            assert_req_dadd8_zeroes: assert (                                            
            (
                (header.cmd==P_DADD8 || header.cmd==DADD8) &&
                (data[0][63:32]==0 && data[1][63:32]==0)
            ) ||
                (header.cmd != DADD8 && header.cmd != P_DADD8) // or it is not a dual 8 byte
            )
              else begin
                  foreach (data[i]) begin
                      $display("data[%d] = %h", i, data[i]);
                  end
                  $error("when doing the DADD8 cmd: %h data payload has required 4 bytes of zeros between the 2 4 byte operands data:", header.cmd);
              end

            
            assert_req_md_wr_zeroes: assert (
                ((header.cmd==MD_WR) && (data[0][63:32]==0) && (data[1]) == 0) || // a MD_WR with the correct data payload
                header.cmd!=MD_WR  // or it is not a MD_WR
            )
              else begin
                  // save data into a string variable for printing
                  $swriteh(act_data, data[0]);
                  $warning("when doing the MD_WR cmd: %h data payload has recommended zeros from bit [95:32] \nData: %s", header.cmd, act_data);
                  // $assertoff(1, assert_req_md_wr_zeroes); // only issue this warning one time
              end
            
        end   
    end : blk_check_pkt
    endfunction : check_pkt

    
    function logic [31:0] gen_crc();
        var  logic [31:0] crcc;
        var logic  [63:0] phits[$];
        var logic [127:0] flits[];
            
        //flits = {<< 64{data}}; // reverse the data array
        //flits = {<< 128{32'h0, tail[31:0], flits, header}};       
        //vcs Error-[IUDA] Incompatible dimensions phits = {header, data, tail[31:0]};
        phits = data;
        phits.push_front(header);
        phits.push_back(tail[31:0]);
        flits = phits2flits(phits);

        crcc = 0;
        foreach (flits[i])
            crcc = nextCRC32_D128(flits[i], crcc);              
        return crcc;
    endfunction

endclass  //cls_req_pkt

/*
 Class: cls_req_pkt_err
 The packet request class
*/
class cls_req_pkt_err extends cls_req_pkt;


    static const int    cub_p    = 0;
    static const int    slid_p   = 1;
    static const int    adr_p    = 2;
    static const int    tag_p    = 3;
    static const int    dln_p    = 4;
    static const int    lng_p    = 5;
    static const int    res0_p   = 6;
    static const int    cmd_p    = 7;
    static const int    crc_p    = 8;
    static const int    rtc_p    = 9;
    static const int    res_p    = 10;
    static const int    seq_p    = 11;
    static const int    frp_p    = 12;
    static const int    rrp_p    = 13;
    static const int    data_p   = 14;
    static const int    random_p = 15;
    
    // variables to be randomized to determine if or if not the field
    // components should be error injected or not
    rand bit [15:0]err;
    
    // the percentage used in the constraint block below
    // 1000 corrupt 100% of the time
    // 0    corrupt 0%   of the time
    rand int seq_c, dln_c, crc_c, lng_c;
    
    int cub_c, slid_c, adr_c, tag_c, res0_c,
      cmd_c, rtc_c, res_c, frp_c, rrp_c, data_c, 
      random_c = 0;

    function new();
        super.new();

        // initialize the percentages to corrupt the fields
        cub_c    = 0;
        slid_c   = 0;
        adr_c    = 0;
        tag_c    = 0;
        dln_c    = 0;
        lng_c    = 0;
        res0_c   = 0;
        cmd_c    = 0;
        crc_c    = 0;
        rtc_c    = 0;
        res_c    = 0;
        seq_c    = 0;
        frp_c    = 0;
        rrp_c    = 0;
        data_c   = 0;
        random_c = 0;

    endfunction
       
    // constraint block for random values
    constraint confields {
        err[cub_p]    dist {0 := (1000 - cub_c)   , 1 := cub_c};
        err[slid_p]   dist {0 := (1000 - slid_c)  , 1 := adr_c};
        err[adr_p]    dist {0 := (1000 - adr_c)   , 1 := adr_c};
        err[tag_p]    dist {0 := (1000 - tag_c)   , 1 := tag_c};
        err[dln_p]    dist {0 := (1000 - dln_c)   , 1 := dln_c};
        err[lng_p]    dist {0 := (1000 - lng_c)   , 1 := lng_c};
        err[res0_p]   dist {0 := (1000 - res0_c)  , 1 := res0_c};
        err[cmd_p]    dist {0 := (1000 - cmd_c)   , 1 := cmd_c};
        err[crc_p]    dist {0 := (1000 - crc_c)   , 1 := crc_c};
        err[rtc_p]    dist {0 := (1000 - rtc_c)   , 1 := rtc_c};
        err[res_p]    dist {0 := (1000 - res_c)   , 1 := res_c};
        err[res_p]    dist {0 := (1000 - res_c)   , 1 := res_c};
        err[seq_p]    dist {0 := (1000 - seq_c)   , 1 := seq_c};
        err[frp_p]    dist {0 := (1000 - frp_c)   , 1 := frp_c};
        err[rrp_p]    dist {0 := (1000 - rrp_c)   , 1 := rrp_c};
        err[data_p]   dist {0 := (1000 - data_c)  , 1 := data_c};
        err[random_p] dist {0 := (1000 - random_c), 1 := random_c};
    }

    // post randomize function which will corrupt pieces of the packet
    // does a check against the randomized variables to see if the
    // fields should be corrupted
    function void post_randomize();
        if (err[cub_p]) begin
            corrupt_pkt("cub");
        end
        if (err[slid_p]) begin
            corrupt_pkt("slid");
        end
        if (err[adr_p]) begin
            corrupt_pkt("adr");
        end
        if (err[tag_p]) begin
            corrupt_pkt("tag");
        end
        if (err[dln_p]) begin
            corrupt_pkt("dln");
        end
        if (err[lng_p]) begin
            corrupt_pkt("lng");
        end
        if (err[res0_p]) begin
            corrupt_pkt("res0");
        end
        if (err[cmd_p]) begin
            corrupt_pkt("cmd");
        end
        if (err[crc_p]) begin
            corrupt_pkt("crc");
        end
        if (err[rtc_p]) begin
            corrupt_pkt("rtc");
        end
        if (err[res_p]) begin
            corrupt_pkt("res");
        end
        if (err[seq_p]) begin
            corrupt_pkt("seq");
        end
        if (err[frp_p]) begin
            corrupt_pkt("frp");
        end
        if (err[rrp_p]) begin
            corrupt_pkt("rrp");
        end
        if (err[data_p]) begin
            corrupt_pkt("data");
        end
        if (err[random_p]) begin
            corrupt_pkt("random");
        end

    endfunction // post_randomize

    
//    function void poison_pkt();
//        tail.crc = ~gen_crc();
//        
//    endfunction // poison_pkt

    // /*
    //  Function: corrupt_pkt
    //  Corrupts a user selectable pieces of the packet
    //  */   
    function void corrupt_pkt(string field="random");
        
        case (field)
            "cub"    : // header packet
              header.cub  = mvm_corrupter#(3)::random_corrupt(header.cub);
            "res1"   :
              header.res1 = mvm_corrupter#(3)::random_corrupt(header.res1);
            "adr"    :
              header.adr  = mvm_corrupter#(34)::random_corrupt(header.adr);
            "tag"    :
              header.tag  = mvm_corrupter#(9)::random_corrupt(header.tag);
            "dln"    :
              header.dln  = mvm_corrupter#(4)::random_corrupt(header.dln);
            "lng"    :
              header.lng  = mvm_corrupter#(4)::random_corrupt(header.lng);
            "res0"   :
              header.res0 = mvm_corrupter#(1)::random_corrupt(header.res0);
            "cmd"    :
              // typ_req_cmd
              // header.cmd  =
              // mvm_corrupter#(6)::random_corrupt(header.cmd);
              // TODO: FIX THE CMD corruption - requires casting
              header.res0 = mvm_corrupter#(1)::random_corrupt(header.res0);
            "crc"    : // tail packet
              tail.crc    = mvm_corrupter#(32)::random_corrupt(tail.crc);
            "rtc"    :
              tail.rtc    = mvm_corrupter#(5)::random_corrupt(tail.rtc);
            "res"    :
              tail.res    = mvm_corrupter#(5)::random_corrupt(tail.res);
            "seq"    :
              tail.seq    = mvm_corrupter#(3)::random_corrupt(tail.seq);
            "frp"    :
              tail.frp    = mvm_corrupter#(8)::random_corrupt(tail.frp);
            "rrp"    :
              tail.rrp    = mvm_corrupter#(8)::random_corrupt(tail.rrp);
            "data"   :
              foreach (data[i])
                begin
                    data[i] = mvm_corrupter#(64)::random_corrupt(data[i]);
                end
            "random" :
              // TODO: for random corruption something more elaborate
              // needs to go here
              header.dln    = mvm_corrupter#(4)::random_corrupt(header.dln);
            default:
              assert (0) else
                $error("ERROR REQ supplied %s which is not a valid flit field to corrupt", field);
        endcase // case (address_mode)
        
        
    endfunction // corrupt_pkt   
    
endclass






//////////////////////////////////////
//
//  Response packet class
//
//////////////////////////////////////


/*
 Class: cls_rsp_pkt
 The packet response class
*/
class cls_rsp_pkt extends cls_pkt;
  

  typ_rsp_header header;
  //typ_phit   data[];
  typ_rsp_tail   tail;
  bit  [2:0] lnk ;
  
  typ_phit pkt[$];
  int tags[$];
  int new_rsp;
  logic [31:0]  crc;
  
  function new();
    super.new();
    header_phits = $bits(header)/PHIT_W;
    tail_phits = $bits(tail)/PHIT_W;
    header = '0;
    tail = '0;
    new_rsp = 1;
    crc = '0;
  endfunction

  function string convert2string();
`ifdef TWO_IN_ONE
    $swriteh(convert2string, "(tid=%0d) header:%p, data.lng:%1d, tail:%p, poison:%1d", transaction_id, header, data.size()/2, tail, poison);
`else
    $swriteh(convert2string, "header:%p, data.lng:%1d, tail:%p, poison:%1d", header, data.size()/2, tail, poison);
`endif
  endfunction

  function string convert2string_short();
    $swriteh(convert2string_short,"cmd:%p lng:%0d tag:%0d rtc:%0d", header.cmd, header.lng, header.tag, tail.rtc); 

  endfunction  

  function void print_tsv(string id = " ");      //$fdisplay(mcd, "time\tslid\tcub\tvlt\tbnk\tdram\ttag\tlng\tcmd\trtc\tseq\tfrp\trrp");
      $fdisplay(pkt_pkg::mcd, "%0.3f\t%s\t%0d\t\t\t\t\t0x%x\t%0d\t%s\t%0d\t%0d\t%0d\t%0d\t%0.3f\t%0.3f\t%0.3f",
        $realtime/1ns, id, header.slid, header.tag, header.lng, header.cmd.name(), tail.rtc, tail.seq, tail.frp, tail.rrp, lat/1ns, tok_lat/1ns, req_lat/1ns); // header.cub
  endfunction

  function void pkt_trace(int fd, int link, string id = " ", string extra="");
      /*
      $fdisplay(fd, "%0.3f\t%s\t%0d\t%0d\t%s\t%0d\t%0d\t%0d\t%0d\t%0x\t%s",
        $realtime/1ns, id, header.tag, header.lng, header.cmd.name(), tail.rtc, tail.seq, tail.frp, tail.rrp, tail.crc, extra);
    */
  endfunction

  function void   set_header(logic [63:0] header);
    this.header = header;
  endfunction

  function void   set_tail(logic [63:0] tail);
    this.tail = tail;
  endfunction

  function int get_tag();
    get_tag = header.tag;
  endfunction

  function [63:0] get_header();
    get_header = header;
  endfunction

  function [63:0] get_tail();
    get_tail = tail;
  endfunction

  function int credits_returned ();
    credits_returned = tail.rtc;
  endfunction

  function int retry_ptr_returned ();
    retry_ptr_returned = tail.frp;
  endfunction

  function void seq_num(input int seq);
    tail.seq = seq;
  endfunction

  function typ_pkt_status append_pkt (input logic [FLIT_W-1:0] flit);
    for (int i=0; i<(FLIT_W/PHIT_W); i++) begin
      if (phit_count < header_phits) begin
          header[phit_count*PHIT_W+:PHIT_W] = flit[i*PHIT_W+:PHIT_W];
          phit_count++;
          //$display("RX HEADER %h phit_count %d  time %t", flit[i*PHIT_W+:PHIT_W], phit_count,  $time);
      end
      else if (phit_count >= header_phits & phit_count < data_phits+header_phits) begin
          data[phit_count-header_phits] = flit[i*PHIT_W+:PHIT_W];
          phit_count++;
          //$display("RX DATA %h phit_count %d time %t", flit[i*PHIT_W+:PHIT_W], phit_count, $time);
      end
      else if (phit_count >= data_phits+header_phits) begin
          tail[(phit_count-header_phits-data_phits)*PHIT_W+:PHIT_W] = flit[i*PHIT_W+:PHIT_W];
          phit_count++;
          //$display("RX TAIL %h phit_count %d time %t", flit[i*PHIT_W+:PHIT_W], phit_count, $time);
      end
      
      if (phit_count==header_phits) begin
        //$display(header.cmd, header.lng);
 
        if (header.lng>0) begin
          data_bytes = siz_to_bytes(header.lng);
          //$display(data_bytes);
          data_phits = data_bytes * 8 / PHIT_W;
          tail_phits = ($bits(tail)/PHIT_W);
        end
        max_phits = header_phits+data_phits+tail_phits;
        max_flits = max_phits/(FLIT_W/PHIT_W);
        data = new[data_phits];
      end
    end
    flit_count++;

    if (flit_count==max_flits) begin 
      crc = nextCRC32_D128({32'b0,flit[FLIT_W-1-32:0]}, crc);
      append_pkt = IDLE;
      if (~crc==tail.crc) poison = 1;
      //$display("CRC %h", tail.crc);
    end
    else begin 
      crc = nextCRC32_D128(flit, crc);
      append_pkt = SEND;
    end

  endfunction

  function int get_cad (output cls_cad cad);
    
    cls_cad new_cad = new();
    new_cad.new_cad();

    get_cad = 0;
    if (new_rsp) begin
      tags.push_back(header.tag);
    end
    


    if (data_bytes > 0 & new_rsp) begin
      //Assign cmd
      new_cad.cmd = enu_read;
      
      //Assign data
      for (int i=0;i<data_bytes*8/32;i++) begin
        for (int j=0;j<32;j++) begin
          new_cad.data[i][j] = data[(i*32+j)/PHIT_W][(i*32+j)%PHIT_W];
        end
      end

      //Assign length
      new_cad.dbytes = data_bytes;
    end
    else begin
      new_cad.cmd = enu_write;
      new_cad.dbytes = 0;
    end

    new_rsp = 0;

    if (tags.size() > 0) begin
      get_cad = tags.size();
      new_cad.id.tag = tags.pop_front();
    end
    new_cad.phase = enu_rsp;


    cad = new_cad;  //output pkt converted to cad;

  endfunction



  function void build_pkt (ref cls_cad cad, ref int credit_return, input int tag0, input int seq);

    if (cad.cmd == enu_read || cad.cmd == enu_mread)
      data_bytes = cad.dbytes;

    if (data_bytes) begin
      data_phits = data_bytes * 8 / PHIT_W;
      data = new[data_phits];

      for (int i=0;i<data_phits;i++) begin
        for (int j=0;j<PHIT_W;j++) begin
          data[i][j] = cad.data[(i*PHIT_W+j)/32][(i*PHIT_W+j)%32];
        end
      end

    end

    header.lng = bytes_to_siz(data_bytes);
    header.dln = header.lng;
    header.tag = cad.id.tag;
    lnk = cad.id.lnk;
    nop = cad.nop;
    case (cad.cmd)
      enu_read : header.cmd = RD_RS;
      enu_mread: header.cmd = MD_RD_RS;
      enu_write,
      enu_bwrite,
      enu_2add8,
      enu_add16 : header.cmd = WR_RS;
      enu_mwrite: header.cmd = MD_WR_RS;
      default: begin 
        assert (0) else
            $error("Illegal Response: %s", cad.cmd.name()); 
      end
    endcase

    tail.seq = seq;
    if (credit_return > 31)
      tail.rtc = 31;
    else
      tail.rtc = credit_return;
    credit_return -= tail.rtc;

    assert (tag0 == -1) else
        $error("tag = %0d cannot be embedded into responses", tag0);
    
    header_phits = ($bits(header)/PHIT_W);
    tail_phits = ($bits(tail)/PHIT_W);

    max_phits = header_phits+data_phits+tail_phits;
    max_flits = max_phits/(FLIT_W/PHIT_W);

    tail.crc = '0;
    for (int i=0; i<header_phits; i++) pkt.push_back(header[i*PHIT_W+:PHIT_W]);
    for (int i=0; i<data_phits;   i++) pkt.push_back(data[i]);
    for (int i=0; i<tail_phits;   i++) pkt.push_back(tail[i*PHIT_W+:PHIT_W]);
    crc = '0;
    for (int i=0; i<max_flits; i++) crc = nextCRC32_D128({pkt[i*2+1],pkt[i*2]},crc);
    tail.crc = crc; 
    for (int i=0; i<tail_phits;   i++) void'(pkt.pop_back());
    for (int i=0; i<tail_phits;   i++) pkt.push_back(tail[i*PHIT_W+:PHIT_W]);
    
  endfunction
  
  
  function typ_pkt_status next_xfer (ref int credits,
                                     output typ_flit            flit,
                                     output logic               valid,
                                     output logic               tl,
                                     output logic               phase,
                                     output logic [1:0]         quad,
                                     output logic [3:0]         dest);
    flit = '0;
    valid = 0;
    tl = '0;
    phase = '0;
    //quad = quad_lut[lnk[1:0]*8+:2];  //quad routing to source link
    quad = lnk[1:0];
    case (lnk)
      3'b100 : dest = 4'hf;  // APG
      3'b111 : dest = 4'he;  // APG Broadcast
      default: dest = 4'h8;  // default to LM
    endcase

    if (credits>0) begin
      for (int i=0; i<(FLIT_W/PHIT_W); i++) begin
        flit[i*PHIT_W+:PHIT_W] = pkt[phit_count];
        //$display("phit %h", pkt[phit_count]);
        phit_count++;
      end
      valid=1;
      //$display("Driver flit TX %h  time %t flit_count %d", flit, $time, flit_count);
      credits--;
      flit_count++;
      phase = ~(&header.cmd[5:3]);
    end
      
    //$display("RSP FLIT %h", flit);

    if (phit_count==max_phits) begin
      tl = 1;
      next_xfer = IDLE;
    end
    else begin
      next_xfer = SEND;
    end

  endfunction
    function int check_cmd_lng();
        int data_size;
        data_size = data.size();
        return (
                  ( (header.cmd==RD_RS)    && (data_size>=1) && (data_size<=16)) ||
                  ( (header.cmd==WR_RS)    && (data_size==0) ) ||
                  ( (header.cmd==MD_RD_RS) && (data_size==2) ) ||
                  ( (header.cmd==MD_WR_RS) && (data_size==0) ) ||
                  ( (header.cmd==ERROR)    && (data_size==0) ) ||
                  ( (int'(header.cmd)==0)  && (data_size==0) )
              );
    endfunction;
    /*
     Function: check_pkt
     Checks the packet for valid values in fields
     */
    function int check_pkt();
    begin : blk_check_pkt

        int data_size;
        logic [31:0] crcc;
        typ_err_stat err_stat;
        
        // save the size of the data object because it is used a lot
        // in the function
        data_size = data.size();

        // save the value of the crcc (crc calculated) in a temp
        // variable used a lot in the function
        crcc = gen_crc();
                
        check_pkt = 0;
                        
        // Hierarchy of request packet errors - first error in the
        // list found will return 1 and exit function
        //
        // NAME               ASSERTION
        // ----------------------------------------
        // RESPONSE LNG/DLN - assert_rsp_dln
        // CHECK CRC        - assert_rsp_crc
        // CHECK POISON     - assert_rsp_crc_poison
        // --- AN ABOVE ERROR WILL STOP CHECKS BELOW
        // RSP CMD VALID    - assert_rsp_cmd_valid
        // Non ZERO ERR ST  - assert_rsp_errstat
        // CMD / LNG check  - assert_rsp_cmd_lng
        // NULL PACKET      - assert_rsp_null_pkt
        // RSP DATA SIZE    - assert_rsp_data_size
        // RESERVED FIELDS  - assert_rsp_header_res_zero ($info only)
        // ERRSTAT FIELDS   - assert_rsp_errstat_check_fields        
        // VALID ERRSTAT    - assert_rsp_errstat_valid
        // RSP assert md_rd - assert_rsp_mode_rd_rs_zeroes
        
        
        // // lng and dln should match even during poision crc
        assert_rsp_dln: assert (header.lng==header.dln)
          else begin
              $error("Response LNG/DLN mismatch, LNG=%d DLN=%d", header.lng, header.dln);
              check_pkt = 1;
          end
        
        assert_rsp_crc: assert (tail.crc==crcc || tail.crc==~crcc) else begin
            $error("Response CRC Error, CRC=%h Expected=%h", tail.crc, crcc);
            return 1;                 
        end
        
        assert_rsp_errstat: assert (!tail.errstat || tail.crc==~crc ) else begin
            $info("Response non-zero Err Status, ERRSTAT=x%h", tail.errstat);
            // $assertoff(1, assert_rsp_errstat); // only issue this info one time
        end

        assert_rsp_cmd_valid: assert
          (
           header.cmd==RD_RS    ||
           header.cmd==WR_RS    ||
           header.cmd==MD_RD_RS ||
           header.cmd==MD_WR_RS ||
           header.cmd==ERROR    ||
           int'(header.cmd)==0  ||
           tail.crc==~crcc
           )
          else begin
              $error("Response CMD not valid CMD: %5h", int'(header.cmd));
          end
        
        assert_rsp_cmd_lng: assert (
                                    ((header.cmd==RD_RS)    && (header.lng>=2) && (header.lng<=9)) ||
                                    ((header.cmd==WR_RS)    && (header.lng==1)) ||
                                    ((header.cmd==MD_RD_RS) && (header.lng==2)) ||
                                    ((header.cmd==MD_WR_RS) && (header.lng==1)) ||
                                    ((header.cmd==ERROR)    && (header.lng==1)) ||
                                    ((int'(header.cmd)==0)  && (header.lng==0)) ||
                                    tail.crc==~crc
                                    ) else begin
            $error("Response CMD/LNG mismatch, CMD=%s LNG=%d", header.cmd.name(), header.lng);
        end
        
        // if cmd is zero the whole header and tail must be zero
        if (int'(header.cmd) == 0) begin
            assert_rsp_null_pkt: assert (header==0 && tail==0) else begin
                $error("RSP CMD is NULL - header and tail must be 0, header=%h tail=%h", header, tail);
            end
        end

        // data_size is 64 bit chunks but a flit is 128 bit chunks
        // the maximum data payload is 128 bytes which is 1024 bits
        // making the maximum data size 1024 / 64 = 16
        assert_rsp_data_size: assert (
            check_cmd_lng() || tail.crc==~crc                                  
                                      ) else begin
            $error("RSP DATA SIZE VERSUS CMD CHECK CMD=%s LNG=%h data.size()=%h", header.cmd.name(), header.lng, data_size);
        end     
        
        // RESERVED FIELDS  - assert_rsp_header_res_zero ($info only)
        assert_rsp_header_res_zero: assert  (!header.res0 && !header.res1 && !header.res2) else begin
            $warning("Nonzero header reserved fields.  Header[6]='h%h, header[38:24]='h%h, and header[63:42]='h%h are ignored by the HMC", header.res0, header.res1, header.res2);
            // $assertoff(1, assert_rsp_header_res_zero); // only issue this warning one time
        end

        assert_rsp_dinv_zero: assert  (!tail.dinv || header.cmd == RD_RS || header.cmd == MD_RD_RS) else begin
            $warning("Nonzero dinv.  dinv is is only valid during read response");
        end
  
        assert_rsp_errstat_check_fields: assert (!tail.errstat || !header.tag[8:3] || (!tail.errstat[6] && tail.errstat[4])) else begin
            $error("CUB number must be returned in the TAG field when ERRSTAT == 6'h%0h.  Actual TAG == %0h", tail.errstat, header.tag);
        end

        // Valid errstat value
        assert_rsp_errstat_valid: assert (!tail.errstat || $cast(err_stat, tail.errstat)) else
            $error("the tail.errstat value %h is not a valid errstat value", tail.errstat);
        
        assert_rsp_md_rd_rs_zeroes: assert (
                                            (
                                             header.cmd==MD_RD_RS && // a MD_RD_RS with the correct payload
                                             (data[0][63:32]==0 && data[1]==0)
                                             ) ||
                                            (header.cmd!=MD_RD_RS) // or it is not a MD_RD_RS                                        
                                         ) else begin
            foreach (data[i])
                begin
                    $display("data[%d] = %h", i, data[i]);
                end
            $error("when doing the MD_RD_RS cmd: %h data payload has required zeros from byte 4 through 15:", header.cmd);
        end
    end : blk_check_pkt
    endfunction : check_pkt

    function logic [31:0] gen_crc();
        var  logic [31:0] crcc;
        var logic  [63:0] phits[$];
        var logic [127:0] flits[];
            
        //flits = {<< 64{data}}; // reverse the data array
        //flits = {<< 128{32'h0, tail[31:0], flits, header}};       
        //vcs Error-[IUDA] Incompatible dimensions phits = {header, data, tail[31:0]};
        phits = data;
        phits.push_front(header);
        phits.push_back(tail[31:0]);
        flits = phits2flits(phits);

        crcc = 0;
        foreach (flits[i])
            crcc = nextCRC32_D128(flits[i], crcc);              
        return crcc;
    endfunction
    
endclass  //cls_rsp_pkt


/*
 Class: cls_rsp_pkt_err
 The packet response class with errors
*/
class cls_rsp_pkt_err extends cls_rsp_pkt;
    
    const int    res1_p = 0;
    const int    unused_p =1;
    const int    tag_p = 2;
    const int    dln_p = 3;
    const int    lng_p = 4; //
    const int    res0_p = 5;
    const int    cmd_p = 6;
    const int    crc_p = 7; //
    const int    rtc_p = 8;
    const int    errstat_p = 9; //
    const int    dinv_p = 10; //
    const int    seq_p = 11; //
    const int    rrp_p = 12;
    const int    data_p = 13;
    const int    err_p = 14;
    

      
    // variables to be randomized to determine if or if not the field
    // components should be error injected or not
    rand bit [14:0]err;
    // cube id for err rsp
    rand bit [2:0] cid;
    rand typ_err_stat errstat;
    
    
    
    /*rand bit[0:0] res1_p, tag_p, dln_p, lng_p, res0_p,
      cmd_p, crc_p, rtc_p, errstat_p, dinv_p, seq_p,
      rrp_p, data_p;*/
    
    
    // the percentage used in the constraint block below
    // 1000 corrupt 100% of the time
    // 0    corrupt 0%   of the time
    rand int lng_c, dln_c, crc_c, dinv_c, seq_c, err_c, errstat_c;
    
    
    int res1_c, tag_c, res0_c,
      cmd_c, rtc_c, rrp_c, data_c = 0;

    function new();
        super.new();

        // initialize the percentages to corrupt the fields
        res1_c = 0;
        tag_c = 0;
        dln_c = 0;
        lng_c = 0; //
        res0_c = 0;
        cmd_c = 0;
        crc_c = 0; //
        rtc_c = 0;
        errstat_c = 0; //
        dinv_c = 0; //
        seq_c = 0; //
        rrp_c = 0;
        data_c = 0;
        err_c = 0;
    endfunction
       
    // constraint block for random values
    constraint confields {
        err[res1_p]    dist {0 := (1000 - res1_c)    , 1  := res1_c};
        err[tag_p]     dist {0 := (1000 - tag_c)     , 1  := tag_c};
        err[dln_p]     dist {0 := (1000 - dln_c)     , 1  := dln_c};
        err[lng_p]     dist {0 := (1000 - lng_c)     , 1  := lng_c};
        err[res0_p]    dist {0 := (1000 - res0_c)    , 1  := res0_c};
        err[cmd_p]     dist {0 := (1000 - cmd_c)     , 1  := cmd_c};
        err[crc_p]     dist {0 := (1000 - crc_c)     , 1  := crc_c};
        err[rtc_p]     dist {0 := (1000 - rtc_c)     , 1  := rtc_c};
        err[errstat_p] dist {0 := (1000 - errstat_c) , !tail.errstat  := errstat_c}; // only corrupt when tail.errstat == 0
        err[dinv_p]    dist {0 := (1000 - dinv_c)    , !tail.dinv  := dinv_c}; // only corrupt when tail.dinv == 0
        err[seq_p]     dist {0 := (1000 - seq_c)     , 1  := seq_c};
        err[rrp_p]     dist {0 := (1000 - rrp_c)     , 1  := rrp_c};
        err[data_p]    dist {0 := (1000 - data_c)    , 1  := data_c};
        err[err_p]     dist {0 := (1000 - err_c)     , 1  := err_c};
        err[unused_p] == 0;
    }

    // constraint for ERROR response errstat field
    constraint errstat_rand {

        // tag == cub number
        if(err[err_p]){
            errstat[6:4] != 3'b001; // DRAM Errors
            errstat[6:4] != 3'b011; // Protocol Errors
            errstat[6:4] != 3'b100; // Undefined
            if(errstat[6:4] == 0){  // Warnings
                errstat[3:0] inside {1,2,4,5,6};
            }
            else if (errstat[6:4] == 3'b010){ // Link Errors
                errstat[2:0] inside {[0:7]};
            }
            else if (errstat[6:4] == 3'b111){ // Fatal Errors
                if (errstat[3] == 1) {
                    errstat[2:0] inside {0,1,3,4};
                }
            }
        }
        // tag == tag of corresponding request
        else if (err[errstat_p]){
            errstat inside {ERR_SBE, ERR_MUE, ERR_CMD, ERR_LNG};
        }
        header.cmd != WR_RS -> int'(errstat[6:4]) != 3; // Protocol Errors must be injected into WR_RS cmd
    }


    // post randomize function which will corrupt pieces of the packet
    // does a check against the randomized variables to see if the
    // fields should be corrupted
    function void post_randomize();
                
        if (err[res1_p])  begin 
            corrupt_pkt("res1");
        end       
        if (err[tag_p])  begin 
            corrupt_pkt("tag");
        end       
        if (err[dln_p])  begin
            corrupt_pkt("dln");
        end       
        if (err[lng_p])  begin 
            corrupt_pkt("lng");
        end       
        if (err[res0_p])  begin 
            corrupt_pkt("res0");
        end       
        if (err[cmd_p])  begin 
            corrupt_pkt("cmd");
        end       
        if (err[crc_p])  begin 
            corrupt_pkt("crc");
        end       
        if (err[rtc_p])  begin 
            corrupt_pkt("rtc");
        end       
        if (err[dinv_p])  begin 
            corrupt_pkt("dinv");
        end       
        if (err[errstat_p])  begin 
            //corrupt_pkt("errstat");
            tail.errstat = errstat;
            // The DINV flag will also be active when errstat == ERR_MUE
            if (tail.errstat == ERR_MUE) begin
                err[dinv_p] = 1;
                tail.dinv = 1; 
            end
        end       
        if (err[seq_p])  begin 
            corrupt_pkt("seq");
        end       
        if (err[rrp_p])  begin 
            corrupt_pkt("rrp");
        end       
        if (err[data_p])  begin 
            corrupt_pkt("data");
        end 
        if (err[err_p])  begin 
            gen_err_pkt();
        end 
    endfunction // post_randomize
   
//    function void poison_pkt();
//        tail.crc = ~gen_crc();
//        
//    endfunction // poison_pkt

    function void gen_err_pkt();
        header.cmd = ERROR;
        header.tag[2:0] = cid;
        tail.errstat = errstat;
        
    endfunction

    /*
     Function: corrupt_pkt
     Corrupts a user selectable pieces of the packet
     */   
    function void corrupt_pkt(string field="random");
        case (field)
            "res1"    : // header packet
              header.res1  = mvm_corrupter#(31)::random_corrupt(header.res1);
            "tag"     :
              header.tag   = mvm_corrupter#(9)::random_corrupt(header.tag);
            "dln"     :
              header.dln   = mvm_corrupter#(4)::random_corrupt(header.dln);
            "lng"     :
              header.lng   = mvm_corrupter#(4)::random_corrupt(header.lng);
            "res0"    :
              header.res0  = mvm_corrupter#(1)::random_corrupt(header.res0);
            "cmd"     :    ; // TODO: FIX cmd randomization
              // header.cmd   = mvm_corrupter#(6)::random_corrupt(header.res0);
            "crc"     :
              tail.crc     = mvm_corrupter#(32)::random_corrupt(tail.crc);
            "rtc"     :
              tail.rtc     = mvm_corrupter#(5)::random_corrupt(tail.rtc);
            "errstat" :    ; // TODO: FIX errstat randomization
              // tail.errstat = mvm_corrupter#(7)::random_corrupt(tail.errstat);
            "dinv"     :
              tail.dinv    = mvm_corrupter#(1)::random_corrupt(tail.dinv);
            "seq"     :
              tail.seq     = mvm_corrupter#(3)::random_corrupt(tail.seq);
            "frp"     :
              tail.frp     = mvm_corrupter#(8)::random_corrupt(tail.frp);
            "rrp"     :
              tail.rrp     = mvm_corrupter#(8)::random_corrupt(tail.rrp);
            "data"   :
              foreach (data[i])
                begin
                    data[i] = mvm_corrupter#(64)::random_corrupt(data[i]);
                end
            "random" :
              // TODO: for random corruption something more elaborate
              // needs to go here
              header.dln    = mvm_corrupter#(4)::random_corrupt(header.dln);
            default:
              assert (0) else
                $error("ERROR RSP supplied %s which is not a valid flit field to corrupt", field);
        endcase // case (field)
        
       
    endfunction // corrupt_pkt
    
    
endclass // cls_req_pkt_err

// similar to uvm_analysis_port
// stores an object of type T
class pkt_analysis_port #(type T = cls_pkt);
    protected T t;

    // immediately updates the stored object
    function void write (input T t);
        this.t = t;
    endfunction: write

    // immediately return the stored object
    function T read ();
        read = this.t;
    endfunction: read

    // blocks until t has been updated
    task get (ref T t);
        @(this.t);
        t = this.t;
    endtask: get

endclass: pkt_analysis_port
    
function [31:0] nextCRC32;
  input [511:0] data;
  input [31:0] crc;
  nextCRC32 = 32'h0;
endfunction

`include "nextCRC32_D128.vh"

function string print_txn (input cls_cad cad, input string msg = "");
//    var typ_spec_adrs adrs;
//    adrs = cad.adrs<<1 | cad.byt>>4;
//    $sformat (print_txn, "id:'{unq:'h%0h, lnk:'h%0h, tag:'h%0h}, cmd:%s, adrs:'{vlt:'h%0h, sta:'h%0h, bnk:'h%0h, row:'h%0h, col:'h%0h, dram:'h%0h}, cube:%0d, nop:%0d, dbytes:%0d, phase:%s",
//        cad.id.unq, cad.id.lnk, cad.id.tag, cad.cmd.name(), cad.adrs.vlt, cad.adrs.sta, cad.adrs.bnk, cad.adrs.row, cad.adrs.col, adrs.dram, cad.cube, cad.nop, cad.dbytes, cad.phase.name());
        var typ_spec_adrs adrs;
        adrs = cad.adrs<<1 | cad.byt>>4;
        $sformat (print_txn, "%0t: %s id:'{unq:'h%4h, lnk:'h%h, tag:'h%h}, cmd:%9s, adrs:'{vlt:'h%h, bnk:'h%h, dram:'h%h}, nop:%0d, dbytes:%0d, phase:%s",
            $time, msg, cad.id.unq, cad.id.lnk, cad.id.tag, cad.cmd.name(), adrs.vlt, adrs.bnk, adrs.dram, cad.nop, cad.dbytes, cad.phase.name());
endfunction

function string print_txn_data (input cls_cad cad, input string msg = "");
    string str_data;
    str_data = "";
    print_txn_data = "";
    if (cad.is_read() & cad.phase==enu_rsp | cad.is_write() & cad.phase==enu_req) begin
      foreach (cad.data[i]) begin
        string hex_data;
        //hex_data.hextoa(cad.data[i]);
        $sformat(hex_data, "%8h", cad.data[i]);
        str_data = {hex_data,str_data};
      end
      $sformat (print_txn_data, "\n%1d'h%s",cad.data.size()*32, str_data);
    end
endfunction

// print transactions to Tab Seperated Value Files (*.tsv)
// opens a file, adds the header, and returns the multi-channel-descriptor
function int open_tsvfile(input string filename = "pkt_log.tsv");
    pkt_pkg::mcd = $fopen(filename, "w");
    $fdisplay(pkt_pkg::mcd, "time\tID\tslid\tcub\tvlt\tbnk\tdram\ttag\tlng\tcmd\trtc\tseq\tfrp\trrp\tlatency\trtc_lat\trq/rs_lat");
    open_tsvfile = pkt_pkg::mcd;
endfunction
endpackage : pkt_pkg

