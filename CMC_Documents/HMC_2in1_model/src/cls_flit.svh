`ifdef TWO_IN_ONE

import pkt_pkg::*;
    /************************ cls_flit ***************************************
    * Class to store a decoded flit for the 2in1
    *
    * These get piped from the flit_bfm to the systemc wrapper for more
    * accurate timing information
    */

   class cls_flit;
        static int unsigned _transaction_count=1; 

       bit is_head; 
       bit is_tail; 
       bit is_invalid;

       int tag; // tag from the head of the head flit 
       int transaction_id; // a unique identifier that is independent of tag

       typ_req_header head;
       typ_req_tail   tail;

       function new(logic [127:0] flit_in, logic [0:0] HEAD, logic [0:0] TAIL, cls_flit last_head_flit);
           if (HEAD) begin
               this.head = typ_req_header'(flit_in[63:0]);
               this.is_head = 1;
               this.tag = this.head.tag;
               this.transaction_id = ++_transaction_count;

           end else begin // every non-head flit gets the last head for meta data purposes
               assert(last_head_flit != null) else $fatal("impossible");
               this.head = last_head_flit.head;
               this.tag = last_head_flit.tag;
               this.transaction_id = last_head_flit.transaction_id;
           end

           if (TAIL) begin
               this.tail = typ_req_tail'(flit_in[127:64]);
               this.is_tail = 1; 
           end
   endfunction

   function string convert2string();
       string tmp;
       $swriteh(tmp, "(tid=%0d) is_head:%0d, head:%p , is_tail:%0d, tail:%p, tag=%0d", this.transaction_id, this.is_head, this.head, this.is_tail, this.tail, this.tag);
       convert2string = tmp;
   endfunction

endclass : cls_flit
`endif // TWO_IN_ONE
