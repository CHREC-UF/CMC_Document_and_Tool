//****** hmc_gen2/pkg_cad
// NAME
//    pkg_cad - SystemVerilog package
// AUTHOR
//    Jake Klier <jklier@micron.com>
// DESCRIPTION
//    Defines basic command/address/data class and queues to store them.
//
// NOTES
// coding conventions:
//    All names will be lower case with underscores separating words or abbreviations
//    Names start with a short (2-3) letter designator followed by underscore to indicate the type.
//    protected variables can prepend a leading "p" to indicate the scope.
//    Constant variables can prepend a "c" to indicate a constant.
//    Public class variables, members of user defined types, task/function arguments, and public task/functions do not require the type designator.
//        par_    parameter or localparam
//        typ_    typedef
//        mod_    module
//        cls_    class
//        pkg_    package
//        tm_     time
//        rtm_    realtime
//        reg_    reg or logic
//        bit_    bit
//        byt_    byte
//        net_    wire
//        int_    int or integer
//        lng_    longint
//        rl_     real
//        srl_    shortreal
//        str_    string
//        fx_     function
//        tsk_    task
//
//    Array designators can be used instead of the type designator to indicate arrays when there is more than one dimension.
//        arr_    array, associative array, or dynamic array
//        que_    queue
//
//        ex: bit [15:0] bit_word;            // single dimension
//            bit [15:0] arr_word [1:0];      // multiple dimensions
//
//    Instances of classes, modules or user defined types will repeat the name without the designator.
//    A single instance will include an "obj_" designator to indicate that it is an object.
//        ex: typedef bit [15:0] typ_word;    // declare user defined type
//            typ_word obj_word;              // single instance of user defined type repeats the name "word"
//            typ_word arr_word [1:0];        // instance of user defined type with array designator repeats the name "word"
//
//    Tasks and functions without required arguments will be called with parenthesis () even though SystemVerilog allows parenthesis to be omitted.
//    Arguments to tasks, functions, and ports will be declared with an explicit direction (input, output, inout, or ref)
//    Arguments passed to tasks, functions, and ports will be passed by position.
//    Required arguments to tasks and functions will be listed before optional arguments on function calls
//    local variables inside functions, tasks and begin-end blocks will be declared with the "var" keyword
//    Class constructors will not accept pointers to other objects.  Pointers will be set using public properties
//******
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

package pkg_cad;

    // parameters
    parameter par_lnk_bits  = 2;
    parameter par_tag_bits  = 14; // need at least 10000 tags
    parameter par_vlt_bits  = 4;
    parameter par_sta_bits  = 2;
    parameter par_bnk_bits  = 2;
    parameter par_row_bits  = 13;
    parameter par_col_bits  = 6;
    parameter par_byt_bits  = 5;
    parameter par_ram_bits  = 20;
    parameter par_cas_bits  = 8<<par_byt_bits; // number of bits per memory address, must be a multiple of 32

    // constants
    const string str_comment = "#";

    // types
    typedef enum bit [3:0] {enu_write, enu_read, enu_refresh, enu_mwrite, enu_mread, enu_bwrite, enu_2add8, enu_add16} typ_cmd;
    typedef enum bit {enu_in, enu_out} typ_in_out;
    typedef enum bit {enu_req, enu_rsp} typ_phase;

    parameter par_io_size   = 1<<$bits(typ_in_out);
    parameter par_cmd_size  = 1<<$bits(typ_cmd);

    typedef struct packed { // this structure needs to store 34 bits in order to convert from pkt::typ_req_header.adr
        bit  [33-par_sta_bits-par_bnk_bits-par_row_bits-par_col_bits:0] vlt; // vault
        bit  [par_sta_bits-1:0] sta; // strata
        bit  [par_bnk_bits-1:0] bnk; // bank
        bit  [par_row_bits-1:0] row; // row
        bit  [par_col_bits-1:0] col; // column
    } typ_adrs;

    typedef struct packed {
        bit  [par_vlt_bits-1:0] vlt; // vault
        bit  [par_bnk_bits+par_sta_bits-1:0] bnk; // bank
        bit  [par_ram_bits-1:0] dram; // dram
    } typ_spec_adrs;

    typedef struct packed {
        int unsigned            unq; // unique id
        bit               [2:0] lnk; // link: this field needs to store 3 bits in order to convert from pkt::typ_req_header.slid
        bit  [par_tag_bits-1:0] tag; // tag
    } typ_id;

    //class cls_id;
    //    // public properties
    //    int unsigned            unq; // unique id
    //    bit  [par_lnk_bits-1:0] lnk; // link
    //    bit  [par_tag_bits-1:0] tag; // tag
    //endclass

    //****c* pkg_cad/cls_cad
    // NAME
    //    cls_cad - SystemVerilog Class
    // DESCRIPTION
    //    Basic command/address/data class.  data and mask use dynamic memory allocation.
    //******
    class cls_cad;
        // public properties
        typ_id                      id;
        typ_cmd                     cmd;
        typ_phase                   phase;
        typ_adrs                    adrs;
        bit      [par_byt_bits-1:0] byt; // byte address
        int unsigned                cabytes; // size of the command and address transfer in bytes, >0 means that command and data share the same wires
        int unsigned                dbytes; // size of the data transfer in bytes
        reg                  [31:0] data [$];
        bit                   [3:0] dmask [$]; // data mask, 1 mask bit per byte,  0 = write data to memory
        longint unsigned            lat; // latency timer
        int unsigned                nop; // number of cycles to wait before using a command
        bit                         rsp; // cmd requires a response
        bit                   [2:0] cube;

        function void new_cad(
            typ_id                      id = 0,
            typ_cmd                     cmd = enu_write,
            typ_phase                   phase = enu_req,
            typ_adrs                    adrs = 0,
            bit      [par_byt_bits-1:0] byt = 0,
            int unsigned                cabytes = 16,
            int unsigned                dbytes = 0,
            reg                  [31:0] data [$] = '{},
            bit                   [3:0] dmask [$] = '{},
            longint unsigned            lat = 0,
            int unsigned                nop = 0,
            bit                         rsp = 1,
            bit                   [3:0] cube = 0
        );
            this.id = id;
            this.cmd = cmd;
            this.phase = phase;
            this.adrs = adrs;
            this.byt = byt;
            this.cabytes = cabytes;
            this.dbytes = dbytes;
            this.data = data;
            this.dmask = dmask;
            this.lat = lat;
            this.nop = nop;
            this.rsp = rsp;
            this.cube = cube;
        endfunction

        function void new_txn(
            typ_id                      id = 0,
            typ_cmd                     cmd = enu_write,
            typ_phase                   phase = enu_req,
            typ_spec_adrs               adrs = 0,
            bit      [par_byt_bits-1:0] byt = 0,
            int unsigned                cabytes = 16,
            int unsigned                dbytes = 0,
            reg                  [31:0] data [$] = '{},
            bit                   [3:0] dmask [$] = '{},
            longint unsigned            lat = 0,
            int unsigned                nop = 0,
            bit                         rsp = 1,
            bit                   [3:0] cube = 0
        );
            this.id = id;
            this.cmd = cmd;
            this.phase = phase;
            this.adrs.vlt = adrs.vlt;
            this.adrs.bnk = adrs.bnk[par_bnk_bits-1:0];
            this.adrs.sta = adrs.bnk[par_bnk_bits+:par_sta_bits];
            this.adrs.row = adrs.dram[(par_col_bits+1)+:par_row_bits];
            this.adrs.col = adrs.dram[par_col_bits:1];
            this.byt = {adrs.dram[0],byt[par_byt_bits-2:0]};
            this.cabytes = cabytes;
            this.dbytes = dbytes;
            this.data = data;
            this.dmask = dmask;
            this.lat = lat;
            this.nop = nop;
            this.rsp = rsp;
            this.cube = cube;
        endfunction

        function bit is_write;
            is_write = (cmd == enu_write || cmd == enu_mwrite || cmd == enu_bwrite || cmd == enu_2add8 || cmd == enu_add16);
        endfunction
    
        function bit is_read;
            is_read = (cmd == enu_read || cmd == enu_mread);
        endfunction

        function bit fx_data_mvmt();
            fx_data_mvmt = (this.is_write() && phase == enu_req) || (this.is_read() && phase == enu_rsp);
        endfunction

    endclass

    function void print_cad (input cls_cad cad, input string msg = "", input int mcd = 1);
        var typ_spec_adrs adrs;
        
        adrs = cad.adrs<<1 | cad.byt>>4;
        $fdisplay (mcd, "%t: %s id:'{unq:'h%4h, lnk:'h%h, tag:'h%h}, cmd:%9s, adrs:'{vlt:'h%h, bnk:'h%h, dram:'h%h}, nop:%0d, dbytes:%0d, phase:%s",
            $time, msg, cad.id.unq, cad.id.lnk, cad.id.tag, cad.cmd.name(), adrs.vlt, adrs.bnk, adrs.dram, cad.nop, cad.dbytes, cad.phase.name());
    endfunction

    //****c* pkg_cad/cls_que_cad
    // NAME
    //    cls_que_cad - SystemVerilog Class
    // DESCRIPTION
    //    Sized queue of cls_cad.
    //    Maintains most SystemVerilog queue behavior.
    //    Has properties to track bandwidth and queue depth.
    //    Has properties to link and filter during push and pop
    // USAGE
    //    Properties depth and byte_credit_pool control when the queue overflows.
    //    Must call test() prior to push_back() to prevent overflow.
    //    que_cad_push and que_cad_pop can be used to link queues.
    //    *_filter properties can be used to discard commands during push_back or pop.
    //******
    class cls_que_cad;
        // private properties

        // public properties
        cls_cad que_cad[$]; // storage of the cad structures
        int unsigned depth; // max size before overflow
        int unsigned byte_credit_pool; // max number of bytes before overflow
        bit signed [32:0] byte_credits; // number of bytes free
        bit signed [32:0] size_credits; // number of cad slots free

        // properties for performance monitoring
        int unsigned cmd_cnt[par_cmd_size-1:0];
        longint unsigned dbyte_cnt[par_cmd_size-1:0];
        int unsigned max_size; // max size of que_cad
        int unsigned max_used;
        int unsigned max_bytes;
        real avg_used;
        int tot_used;
        string inst_name;

        bit [par_cmd_size-1:0] filter; // don't store this command type when set
        cls_que_cad que_cad_push[$]; // optional queues to push when something is pushed
        cls_que_cad que_cad_pop[$];  // optional queues to push when something is popped
        bit [par_cmd_size-1:0] que_cad_push_filter[$]; // must match the size of que_cad_push
        bit [par_cmd_size-1:0] que_cad_pop_filter[$]; // must match the size of que_cad_pop

        // private methods
        //function bit pfx_data_mvmt(input cls_cad item);
        //    pfx_data_mvmt = (item.cmd == enu_write && item.phase == enu_req) || (item.cmd == enu_read && item.phase == enu_rsp);
        //endfunction

        // public methods
        virtual function void push_back(input cls_cad item);
            if (!filter[item.cmd]) begin
                //vcs - Error-[IUMC] Invalid use of method call: void'(que_cad.push_back(item));
                que_cad.push_back(item);
                byte_credits -= item.cabytes + item.dbytes*item.fx_data_mvmt();
                size_credits -= 1;
            end

            assert (item.cmd>>1 || ((size_credits >= 0) && (byte_credits >= 0)) ) else // only enu_read and enu_write must stop at "depth"
                $error("%s: buffer overflow, max size=%0d, actual size=%0d, max bytes=%0d, actual bytes=%0d", inst_name, depth, que_cad.size(), byte_credit_pool, byte_credit_pool - byte_credits);
            foreach (que_cad_push[i])
                if (!que_cad_push_filter[i][item.cmd])
                    void'(que_cad_push[i].push_back(item));

            cmd_cnt[enu_write] += item.is_write();
            cmd_cnt[enu_read] += item.is_read();
            dbyte_cnt[item.cmd] += item.dbytes;
            if (que_cad.size() > max_size)
                max_size = que_cad.size();
            if (byte_credit_pool - byte_credits > max_bytes)
                max_bytes = byte_credit_pool - byte_credits;
        endfunction

        virtual task put(input cls_cad item); // just like push_back, but blocks until there is room in the queue
            wait (((size_credits > 0) && (byte_credits >= item.cabytes + item.dbytes*item.fx_data_mvmt())) || filter[item.cmd]);
            push_back(item);
        endtask

        virtual function cls_cad pop(input int index);
            const cls_cad item = que_cad[index];

            foreach (que_cad_pop[i])
                if (!que_cad_pop_filter[i][item.cmd])
                    void'(que_cad_pop[i].push_back(item));

            // vcs - Error-[IUMC] Invalid use of method call: void'(que_cad.delete(index));
            que_cad.delete(index);
            byte_credits += item.cabytes + item.dbytes*item.fx_data_mvmt();
            size_credits += 1;
            // update stats
            if (index > max_used)
                max_used = index;
            tot_used++;
            avg_used += 1.0*(index - avg_used)/tot_used;
            pop = item;
        endfunction

        virtual function cls_cad item(input int index);
            item = que_cad[index];
        endfunction

        virtual function int size();
            size = que_cad.size();
        endfunction

        virtual function void delete(input int i);
            const cls_cad item = que_cad[i];

            que_cad.delete(i);
            byte_credits += item.cabytes + item.dbytes*item.fx_data_mvmt();
            size_credits += 1;
        endfunction

        virtual function cls_cad pop_front();
            const cls_cad item = que_cad[0];

            foreach (que_cad_pop[i])
                if (!que_cad_pop_filter[i][item.cmd])
                    void'(que_cad_pop[i].push_back(item));
            pop_front = que_cad.pop_front();
            byte_credits += item.cabytes + item.dbytes*item.fx_data_mvmt();
            size_credits += 1;
        endfunction

        virtual function bit test(ref cls_cad item); // test to see if the buffer can hold the comamnd
            test = (size_credits > 0) && (byte_credits >= (item.cabytes + item.dbytes*item.fx_data_mvmt())) || filter[item.cmd];
        endfunction

        function new(input int unsigned depth = -1, input int unsigned byte_credit_pool = -1);
            this.depth = depth;
            this.byte_credit_pool = byte_credit_pool;
            byte_credits = byte_credit_pool;
            size_credits = depth;
            $sformat(inst_name, "%m");
        endfunction

    endclass

    //****c* pkg_cad/cls_que_rsvid
    // NAME
    //    cls_que_rsvid - SystemVerilog Class
    // DERIVED FROM
    //    cls_que_cad
    // DESCRIPTION
    //    Adds the ability to reserve slots in the queue based on cls_cad.id
    //******
    class cls_que_rsvid extends cls_que_cad;
        // private properties

        // public properties
        //cls_cad que_cad[typ_id]; // storage of the cad structures
        reg [$bits(typ_id)-1:0] que_iden[$]; // define enables for id's
        int unsigned que_idrsv[$]; // max size to reserve for each enable, must match the size of que_iden
        int unsigned que_idcnt[$]; // current count of each enable, must match the size of que_iden
        int unsigned int_idrsv_sum;

        // private methods

        // public methods
        virtual function void push_back(input cls_cad item);
            assert (test(item)) else begin
                print_cad(item, "CAD cannot be added to the queue", 1);
                $error();
            end
            super.push_back(item);
            if (!filter[item.cmd])
                foreach (que_iden[i]) begin
                    if (item.id ==? que_iden[i]) begin // X and Z values in que_iden[i] act as wildcards
                        que_idcnt[i] += 1;
                    end
                end
        endfunction

        virtual function cls_cad pop(input int index);
            pop = super.pop(index);
            foreach (que_iden[i]) begin
                if (pop.id ==? que_iden[i]) begin // X and Z values in que_iden[i] act as wildcards
                    que_idcnt[i] -= 1;
                end
            end
        endfunction

        virtual function cls_cad pop_front();
            pop_front = super.pop_front();
            foreach (que_iden[i]) begin
                if (pop_front.id ==? que_iden[i]) begin // X and Z values in que_iden[i] act as wildcards
                    que_idcnt[i] -= 1;
                end
            end
        endfunction

        virtual function bit test(ref cls_cad item);

            test = super.test(item);
//            assert (que_idrsv.sum() <= depth) else
//                $error("que_cad depth must be >= to the total number of reserved locations");
            if (!filter[item.cmd])
                // check to see if int_idrsv_sum has been initialized
                if (!int_idrsv_sum && que_idrsv.size()) begin
                    foreach (que_idrsv[i]) begin
                        int_idrsv_sum += que_idrsv[i];
                    end
                end
                foreach (que_iden[i]) begin
                    if (item.id ==? que_iden[i]) begin // X and Z values in que_iden[i] act as wildcards
                        test &= (que_idcnt[i] < depth - int_idrsv_sum + que_idrsv[i]);
                    end
                end
        endfunction

        function new(input int unsigned depth = -1, input int unsigned byte_credit_pool = -1);
            super.new(depth, byte_credit_pool);
        endfunction
    endclass


endpackage

/*
import pkg_cad::*;
interface cad_if #(CHAN=3) (input bit clk);
    bit [0:CHAN-1] valid;
    int int_chan;
    int int_cad_bytes;
    cls_cad cad[$:CHAN]; // queue with max size

    task automatic put(cls_cad obj_cad);

        int_cad_bytes = obj_cad.cabytes + obj_cad.dbytes*obj_cad.fx_data_mvmt();
        cad.push_back(obj_cad);
        while (int_cad_bytes > 0) begin
            valid[int_chan] <= 1;
            int_cad_bytes -= 16;
            int_chan++;
            if (int_chan == CHAN) begin
                int_chan = 0;
                @ (negedge clk);
                valid <= 0;
            end
        end 
        @ (negedge clk);
        cad.delete(0);
        valid <= 0;
                
    endtask
endinterface
*/
