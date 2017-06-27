`define hmc_tb hmc_multicube_bfm_tb

module hmc_multicube_bfm_tb;

	parameter num_cubes_c = 4;

	hmc_bfm_tb cubes[num_cubes_c] ();

	task automatic send_request(int cube_num, int link_num, cls_pkt req_pkt);
		// ##################### HACK ALERT ###############################
		// Resetting the packet's cube ID to 0 to avoid BFM crashing 
		// 
		// Explanation: 
		// The cube ID is used in the BFM as an identifier for a chained configuration,
		// so when a particular testbench instance gets a non-zero ID, it checks how many
		// cubes are in its chain and it sees that the ID is not valid and errors out. To
		// avoid unnecessarily changing the BFM code, we use the cube ID to figure out
		// which testbench to send the request to, but then reset the cube ID in the
		// packet to zero. 
		// 
		// In a "real" host, the host will know which link to send on to access
		// a particular cube, so the cube ID should be zero in all the packets that it
		// sends on a link. In other words, the host doesn't need any extra data inside
		// of the packet to determine where to send its linke, whereas this artificial
		// example does need this information. 
		
		// ################################################################

		typ_req_header header;
		typ_req_tail   tail; 

		header = req_pkt.get_header();
		tail = req_pkt.get_tail();

		header.cub = 0;
		req_pkt.set_header(header);

		// regenerate CRC on the packet
		tail.crc = req_pkt.gen_crc();
		req_pkt.set_tail(tail);


			case(cube_num)
			0: cubes[0].mb_tx_pkt[link_num].put(req_pkt);
			 1: cubes[1].mb_tx_pkt[link_num].put(req_pkt);
			 2: cubes[2].mb_tx_pkt[link_num].put(req_pkt);
			 3: cubes[3].mb_tx_pkt[link_num].put(req_pkt);
		 endcase

	endtask : send_request

	task automatic get_response(int cube_num, int link_num, ref cls_pkt pkt);
		case (cube_num)
			0: cubes[0].rx_pkt_port[link_num].get(pkt);
			1: cubes[1].rx_pkt_port[link_num].get(pkt);
			2: cubes[2].rx_pkt_port[link_num].get(pkt);
			3: cubes[3].rx_pkt_port[link_num].get(pkt);
		endcase

	endtask : get_response

	task automatic wait_for_idle(int cube_num);
		fork 
			case(cube_num)
			0: begin
			cubes[0].wait_for_idle(0);
			cubes[0].wait_for_idle(1);
			cubes[0].wait_for_idle(2);
			cubes[0].wait_for_idle(3);
			end

			1: begin
			cubes[1].wait_for_idle(0);
			cubes[1].wait_for_idle(1);
			cubes[1].wait_for_idle(2);
			cubes[1].wait_for_idle(3);
			end
			2: begin
			cubes[2].wait_for_idle(0);
			cubes[2].wait_for_idle(1);
			cubes[2].wait_for_idle(2);
			cubes[2].wait_for_idle(3);
			end
			3: begin
			cubes[3].wait_for_idle(0);
			cubes[3].wait_for_idle(1);
			cubes[3].wait_for_idle(2);
			cubes[3].wait_for_idle(3);
			end
		endcase
		join 
	endtask : wait_for_idle

endmodule : hmc_multicube_bfm_tb
