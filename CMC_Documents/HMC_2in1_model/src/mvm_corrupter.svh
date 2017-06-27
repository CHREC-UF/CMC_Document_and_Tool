/*
 Class: mvm_corrupter
 Helper functions to allow for specific corruption of passed in bit fields. 
 
 About: Example Use
 | `include "mvm_corrupter.svh"
 |  
 | $display("corrupt_one_bit", mvm_corrupter#(100)::corrupt_one_bit(100'h3));
 | $display("random_corrupt ", mvm_corrupter#(100)::random_corrupt(100'h0));
 | $display("incr           ", mvm_corrupter#(100)::incr(100'h0));
 | $display("decr           ", mvm_corrupter#(100)::decr(100'h0));
 |
 | OUTPUT IN SIMULATOR
 | # corrupt_one_bit 0000000000080000000000003
 | # random_corrupt  00000000000000000203f922b
 | # incr            0000000000000000000000001
 | # decr            fffffffffffffffffffffffff
 
 About: License
 
 | DISCLAIMER OF WARRANTY
 |
 | This software code and all associated documentation, comments or other 
 | information (collectively "Software") is provided "AS IS" without 
 | warranty of any kind. MICRON TECHNOLOGY, INC. ("MTI") EXPRESSLY 
 | DISCLAIMS ALL WARRANTIES EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
 | TO, NONINFRINGEMENT OF THIRD PARTY RIGHTS, AND ANY IMPLIED WARRANTIES 
 | OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE. MTI DOES NOT 
 | WARRANT THAT THE SOFTWARE WILL MEET YOUR REQUIREMENTS, OR THAT THE 
 | OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE. 
 | FURTHERMORE, MTI DOES NOT MAKE ANY REPRESENTATIONS REGARDING THE USE OR 
 | THE RESULTS OF THE USE OF THE SOFTWARE IN TERMS OF ITS CORRECTNESS, 
 | ACCURACY, RELIABILITY, OR OTHERWISE. THE ENTIRE RISK ARISING OUT OF USE 
 | OR PERFORMANCE OF THE SOFTWARE REMAINS WITH YOU. IN NO EVENT SHALL MTI, 
 | ITS AFFILIATED COMPANIES OR THEIR SUPPLIERS BE LIABLE FOR ANY DIRECT, 
 | INDIRECT, CONSEQUENTIAL, INCIDENTAL, OR SPECIAL DAMAGES (INCLUDING, 
 | WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, BUSINESS INTERRUPTION, 
 | OR LOSS OF INFORMATION) ARISING OUT OF YOUR USE OF OR INABILITY TO USE 
 | THE SOFTWARE, EVEN IF MTI HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH 
 | DAMAGES. Because some jurisdictions prohibit the exclusion or 
 | limitation of liability for consequential or incidental damages, the 
 | above limitation may not apply to you.
 | 
 | Copyright 2013 Micron Technology, Inc. All rights reserved.
 
 */
 
class mvm_corrupter#(int WIDTH=1);
    
    /*
     Typedef: vector_t
     
     Typedef for the passed in input vector
     */
    typedef logic[WIDTH-1:0] vector_t;

    /*
     Function: corrupt_one_bit

     Corrupt one bit chosen at random from the input vector by
     toggling it - can also send in an index to toggle as well.
     
     Parameters:
     data  - The logic vector being sent in.
     index - A positive integer of the index of the vector to toggle.
     If this option is not sent in the default is to toggle a random
     index of the data vector.

     */   
    static function vector_t corrupt_one_bit(vector_t data, int index = -1);
        int                  corrupt_index;
        
        if( index == -1 ) 
            corrupt_index = $urandom_range(WIDTH-1, 0);
        else
            corrupt_index = index;
        
        corrupt_one_bit = data;
        corrupt_one_bit[corrupt_index] = !corrupt_one_bit[corrupt_index];
    endfunction

    /*
     Function: random_corrupt
     
     Send back a randomized vector that is guaranteed to be different
     than the one sent in
     
     Parameters:
     data  - The logic vector being sent in.

     */
    static function vector_t random_corrupt(vector_t data);
        
        random_corrupt = $urandom_range((2**WIDTH - 1), 0);               
        if (data == random_corrupt)
        begin
            random_corrupt = incr(data);
        end
    endfunction

    /*
     Function: incr
     
     Increment the vector passed in by one.

     Parameters:
     data  - The logic vector being sent in.
               
     */
    static function vector_t incr(vector_t data);
        incr = data + 1;
    endfunction
    
    /*
     Function: decr
     
     Decrement the vector passed in by one.

     Parameters:
     data  - The logic vector being sent in.
     
     */
    static function vector_t decr(vector_t data);
        decr = data - 1;
    endfunction

    /*
     Function: random_type
     TODO: Choose one of the above corruption types

     */
    // static function vector_t random_corrupt();
    // endfunction   
    
endclass // corrupter
