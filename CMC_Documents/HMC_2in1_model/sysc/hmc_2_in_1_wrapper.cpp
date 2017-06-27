#include <2in1Wrapper.h>
#include "hmc_2_in_1_wrapper.h"
#include <assert.h>
#include <algorithm> // std::min -- really?

static bool debug=false;

using namespace Micron::Internal::HMC2;

hmc_2_in_1_wrapper::hmc_2_in_1_wrapper(sc_module_name name, const char *hmcsim_config_filename) 
	: sc_module(name)
	  // PR: XXX: this *must* be done since the cadence tools look at the
	  // port's systemC name, not the C++ name
	  , cfg_link_speed("cfg_link_speed")
	  , cfg_link_width("cfg_link_width")
	  , cfg_host_num_tokens("cfg_host_num_tokens")
	  , cfg_cube_num_tokens("cfg_cube_num_tokens")
	  , cfg_block_bits("cfg_block_bits")
	  , cfg_cube_size("cfg_cube_size")
	  , cfg_response_open_loop("cfg_response_open_loop")
	  , cfg_tj("cfg_tj")
	  , bfm_bits_in0("bfm_bits_in0")
	  , bfm_bits_in1("bfm_bits_in1")
	  , bfm_bits_in2("bfm_bits_in2")
	  , bfm_bits_in3("bfm_bits_in3")
	  , token_adjust0("token_adjust0")
	  , token_adjust1("token_adjust1")
	  , token_adjust2("token_adjust2")
	  , token_adjust3("token_adjust3")
	  , bfm_bits_out0("bfm_bits_out0")
	  , bfm_bits_out1("bfm_bits_out1")
	  , bfm_bits_out2("bfm_bits_out2")
	  , bfm_bits_out3("bfm_bits_out3")
	  , bfm_return_tokens0("bfm_return_tokens0")
	  , bfm_return_tokens1("bfm_return_tokens1")
	  , bfm_return_tokens2("bfm_return_tokens2")
	  , bfm_return_tokens3("bfm_return_tokens3")
	  , link_power0("link_power0")
	  , link_power1("link_power1")
	  , link_power2("link_power2")
	  , link_power3("link_power3")
	  , expected_sysc_token_return0("expected_sysc_token_return0")
	  , expected_sysc_token_return1("expected_sysc_token_return1")
	  , expected_sysc_token_return2("expected_sysc_token_return2")
	  , expected_sysc_token_return3("expected_sysc_token_return3")
	  , simulationFinishedSignal("simulationFinishedSignal")
	  , cubeWrapper("cubeWrapper")
      , cfg_dram_tracing_en("cfg_dram_tracing_en")
	  , cfg_refresh_en("cfg_refresh_en")
{
	std::ostringstream oss; 


	// main wireup 
	// XXX: Create all of the adapters/arbiters/signals for the max number of links,
	// but only enable the same number as the systemC model
	for (unsigned i=0; i<MAX_LINKS; ++i) {
		oss << "adapter_"<<i;
		bfm_adapter *adapter = new bfm_adapter(oss.str().c_str(), i, this->cubeWrapper);
		adapters.push_back(adapter); 
		oss.str("");
		oss.clear();
	}

	SC_METHOD(setConfig);
	sensitive << cfg_link_speed;
	sensitive << cfg_link_width;
	sensitive << cfg_cube_num_tokens;
	sensitive << cfg_host_num_tokens;
	sensitive << cfg_block_bits;
	sensitive << cfg_cube_size;
	sensitive << cfg_response_open_loop;
	sensitive << cfg_tj;
    sensitive << cfg_dram_tracing_en;
	sensitive << cfg_refresh_en;

	// TODO: figure out if there's some kind of magic that can be done here to generate this at compile time;
	// at the very least, maybe some kind of preprocessor?
	// XXX: this must match the number of MAX_LINKS or else elaboration will fail
	adapters[0]->bits_in.bind(this->bfm_bits_in0);
	adapters[0]->bits_out.bind(this->bfm_bits_out0);
	adapters[0]->return_tokens.bind(this->bfm_return_tokens0);
	adapters[0]->link_power_state.bind(this->link_power0);
	adapters[0]->flits_sent.bind(this->expected_sysc_token_return0);
	adapters[0]->token_adjustment.bind(this->token_adjust0);

	adapters[1]->bits_in.bind(this->bfm_bits_in1);
	adapters[1]->bits_out.bind(this->bfm_bits_out1);
	adapters[1]->return_tokens.bind(this->bfm_return_tokens1);
	adapters[1]->link_power_state.bind(this->link_power1);
	adapters[1]->flits_sent.bind(this->expected_sysc_token_return1);
	adapters[1]->token_adjustment.bind(this->token_adjust1);

	adapters[2]->bits_in.bind(this->bfm_bits_in2);
	adapters[2]->bits_out.bind(this->bfm_bits_out2);
	adapters[2]->return_tokens.bind(this->bfm_return_tokens2);
	adapters[2]->link_power_state.bind(this->link_power2);
	adapters[2]->flits_sent.bind(this->expected_sysc_token_return2);
	adapters[2]->token_adjustment.bind(this->token_adjust2);

	adapters[3]->bits_in.bind(this->bfm_bits_in3);
	adapters[3]->bits_out.bind(this->bfm_bits_out3);
	adapters[3]->return_tokens.bind(this->bfm_return_tokens3);
	adapters[3]->link_power_state.bind(this->link_power3);
	adapters[3]->flits_sent.bind(this->expected_sysc_token_return3);
	adapters[3]->token_adjustment.bind(this->token_adjust3);
}

void hmc_2_in_1_wrapper::simulationFinished() {
	cout << "^^^^^^^^^^^^^^ Dumping SystemC stats ^^^^^^^^^^^^\n";
	cubeWrapper.DumpStats();
}

void hmc_2_in_1_wrapper::setConfig() {
	sc_lv <1 > tmp_open_loop = cfg_response_open_loop.read();
	sc_lv <32 > tmp_tj = cfg_tj.read();
    sc_lv <1  > tmp_dram_tracing_en = cfg_dram_tracing_en.read();
	sc_lv <1  > tmp_refresh_en = cfg_refresh_en.read();

	sc_lv <10> tmp = cfg_cube_num_tokens.read();
	sc_lv <11> tmp_block_bits = cfg_block_bits.read();
	sc_lv <3 > tmp_cube_size = cfg_cube_size.read();
	sc_lv <3 > tmp_link_width = cfg_link_width.read();

    if (tmp_dram_tracing_en.is_01()) {
		cubeWrapper.setDramTracingEn(tmp_dram_tracing_en.to_uint());
	}

	if (tmp_refresh_en.is_01()) {
		cubeWrapper.setRefreshEn(tmp_refresh_en.to_uint());
	}

	if (tmp.is_01()) {
		cubeWrapper.setCubeTokens(tmp.to_uint());
	}

	tmp = cfg_host_num_tokens.read();
	if (tmp.is_01()) {
		cubeWrapper.setHostTokens(tmp.to_uint());
	}

	tmp = cfg_link_speed.read();
	if (tmp.is_01() && tmp_link_width.is_01()) {
		cubeWrapper.setLinkParams(tmp.to_uint(), 16>>tmp_link_width.to_uint());
	}

	if (tmp_open_loop.is_01()) {
		cubeWrapper.setResponseOpenLoopMode(tmp_open_loop.to_uint());
	}

	if (tmp_tj.is_01()) {
		cubeWrapper.setTj(tmp_tj.to_uint());
	}

	if (tmp_block_bits.is_01()) {
		cubeWrapper.setBlockSize(tmp_block_bits.to_uint());
	}

	if (tmp_cube_size.is_01()) {
		cubeWrapper.setCubeSize(tmp_cube_size.to_uint());
	}
}

bfm_adapter::bfm_adapter(sc_module_name name_, unsigned linkId_, Cube2in1Wrapper &cubeWrapper_) : sc_module(name_)
		, bits_in("bits_in")
		, bits_out("bits_out")
		, token_toggle_bit(false)
		, linkId(linkId_)
		, numFlitsSent(0)
		, cubeWrapper(cubeWrapper_)
		, responseWaitingEvent(cubeWrapper.getResponseWaitingEvent(linkId))
		, pendingResponseQueue(cubeWrapper.getPendingResponseQueue(linkId))
		, prevTag(0)
		, prevLng(0)
		, prevCmd(0)
		, prevTransactionId(0)
		, prevFlitNumber(0)
		, prevAddress(0)
		, dropTransactionId(0)
	{

		SC_METHOD(bits_to_flits); 
		sensitive << bits_in;
		dont_initialize();

		SC_THREAD(flit_to_bits);

		SC_METHOD(link_power_state_change);
		sensitive << link_power_state;
		dont_initialize();

		SC_METHOD(adjust_cube_tokens);
		sensitive << token_adjustment;
		dont_initialize();
	}
void bfm_adapter::adjust_cube_tokens() {
	sc_lv <32> tmp = token_adjustment.read().range(31,0);
	if (tmp.is_01()) {
		unsigned adjustBy = tmp.to_int();
		cubeWrapper.tokenAdjustment(linkId,adjustBy);
	}
}
void bfm_adapter::write_sent_flits(unsigned transactionId, unsigned num_flits) {
	sc_lv<41> tmp; 
	static bool toggle = 0; 
	toggle = !toggle;
	tmp[40] = toggle; 
	tmp.range(39,8) = transactionId;
	tmp.range(7,0) = num_flits;
	if (debug)
		cout << sc_time_stamp()<<": Reporting back "<<num_flits<<" sent flits for transaction "<<transactionId<<" (bits="<<std::hex<<tmp<<std::dec<<")\n";

	flits_sent.write(tmp);
}

void bfm_adapter::bits_to_flits() {

	if (debug)
		cout << sc_time_stamp()<<"===== BFM Adapter "<<linkId<<" inside bits_to_flits()"<<endl;

	// Toggle bit is the highest order bit, discard
	sc_lv< 1> bits_in_toggle_bit  = this->bits_in.read().range(162,162);
	bool  transaction_is_bad      = this->bits_in.read().range(160,160).to_uint();
	bool  is_tail                 = this->bits_in.read().range(161,161).to_uint();
	sc_lv<32> transaction_id_bits = this->bits_in.read().range(159,128);
	sc_lv<64> header              = this->bits_in.read().range(127,64);
	sc_lv<64> tail                = this->bits_in.read().range(63,0);

	if (debug) {
		cout << sc_time_stamp()<<"===== BFM Adapter "<<linkId<<" toggle bit="<<bits_in_toggle_bit<<endl;
		cout << sc_time_stamp()<<"===== BFM Adapter "<<linkId<<" seen header="<<header<<" tail="<<tail<<endl;
		cout << sc_time_stamp()<<"===== BFM Adapter "<<linkId<<" is bad="<<transaction_is_bad<<endl;
		cout << sc_time_stamp()<<"===== BFM Adapter "<<linkId<<" is tail="<<is_tail<<" tid="<<transaction_id_bits<<endl;
	}

	static unsigned id = 0;


	bool is_head      = prevTransactionId == 0;

	unsigned transaction_id = transaction_id_bits.to_uint();

	// XXX: protocol v1 packet layout
	unsigned cmd            = is_head ? header.range(5 , 0).to_uint() : prevCmd;
	unsigned lng            = is_head ? header.range(10, 7).to_uint() : prevLng;
	unsigned tag            = is_head ? header.range(23,15).to_uint() : prevTag;
	uint64_t address        = is_head ? header.range(57,24).to_uint64() : prevAddress;

	unsigned rtc       = is_tail ? tail.range(31, 27).to_uint() : 0; 

	bool is_tret      = cmd == 0x02;
	bool is_bad_tail  = is_tail && transaction_is_bad;
	bool is_bad_cmd   = 0;
	bool is_bad_lng   = 0; 
	// ceusebio: SysC now needs to see NULLs
	bool is_null      = cmd == 0x0;

	// XXX: for a write, the data length is lng minus the single head+tail flit
	unsigned length   = 16U*(lng-1);

	HMCCommand hmcCmd = READ_REQUEST;
	switch (cmd) {
		case 0x30:
			hmcCmd = READ_REQUEST;
			length = 16; 
			break;
		case 0x31:
			hmcCmd = READ_REQUEST;
			length = 32; 
			break;
		case 0x32:
			hmcCmd = READ_REQUEST;
			length = 48; 
			break;
		case 0x33:
			hmcCmd = READ_REQUEST;
			length = 64; 
			break;
		case 0x34:
			hmcCmd = READ_REQUEST;
			length = 80; 
			break;
		case 0x35:
			hmcCmd = READ_REQUEST;
			length = 96; 
			break;
		case 0x36:
			hmcCmd = READ_REQUEST;
			length = 112; 
			break;
		case 0x37:
			hmcCmd = READ_REQUEST;
			length = 128; 
			break;

		case 0x08: 
		case 0x09: 
		case 0x0A: 
		case 0x0B: 
		case 0x0C: 
		case 0x0D: 
		case 0x0E: 
		case 0x0F: 
		case 0x4F: 
			hmcCmd = WRITE_REQUEST;
			break;

		case 0x18: 
		case 0x19: 
		case 0x1A: 
		case 0x1B: 
		case 0x1C: 
		case 0x1D: 
		case 0x1E: 
		case 0x1F: 
			hmcCmd = P_WRITE_REQUEST;
			break;

	case 0x11: // BWR
		hmcCmd = ATOMIC_BWR;
		length = 16; 
		break;
	case 0x12: // 2ADD8
		hmcCmd = ATOMIC_DADD8;
		length = 16; 
		break;
	case 0x13: // ADD16
		hmcCmd = ATOMIC_ADD16;
		length = 16; 
		break;
	case 0x21: // P_BWR
		hmcCmd = ATOMIC_P_BWR;
		length = 16; 
		break;
	case 0x22: // P_2ADD8
		hmcCmd = ATOMIC_P_DADD8;
		length = 16; 
		break;			
	case 0x23: // P_ADD16
		hmcCmd = ATOMIC_P_ADD16;
		length = 16; 
		break;

		// PR: These commands aren't supported by SC and should have been bypassed by the wrapper
		case 0x10: // MDWR
		case 0x28: // MDRD
			cout << sc_time_stamp() << ": Found packet with illegal cmd going to SC: "<<cmd<<endl;
			abort();
			break;
		case 0x02: // TRET
			hmcCmd = TOKEN_RETURN;
			break;

		// ceusebio: SysC now needs to see NULLs
		case 0x00: // NULL
			hmcCmd = NULL_COMMAND;
			break;
		default: 
			is_bad_cmd = true;
			break;
	}

	// error conditions: lng not between 1-9, lng of read request isn't 1, less than 2 flit write
	if (is_head) {
		// 'b000xxx and 'b111xxx commands are "vendor specific" (i.e., we shouldn't get any)
		// This will likely get caught by the 'default' case above, but leave this here as a note
		// Except the case where cmd = 'b000010 is a token return -- the spec is confusing
		unsigned top_cmd_bits = (cmd >> 3) & 0x7;
		// ceusebio: SysC now needs to see NULLs
		is_bad_lng = (!is_null && lng < 1) || lng > 9 || (hmcCmd == READ_REQUEST && lng != 1) || ((hmcCmd == WRITE_REQUEST || hmcCmd == P_WRITE_REQUEST) && lng < 2) || (is_tret && lng != 1) ||
			((hmcCmd==ATOMIC_BWR || hmcCmd==ATOMIC_P_BWR || hmcCmd==ATOMIC_DADD8 || hmcCmd==ATOMIC_P_DADD8 || hmcCmd==ATOMIC_ADD16 || hmcCmd==ATOMIC_P_ADD16) && lng != 2);
		is_bad_cmd = is_bad_cmd || (!is_tret && !is_null  && (top_cmd_bits == 0 || top_cmd_bits == 7)) || (is_tret && rtc == 0) || (is_null && rtc != 0);


		if (is_bad_tail || is_bad_lng || is_bad_cmd)
		{
			// PR: TODO: use an istringstream and feed it to printf or something?
			if (debug) {
				cout <<sc_time_stamp();
				printf(" ********** Bogus packet cmd=%x lng=%u tag=%u tid=%u addr=0x%lx (bad_tail=%u, bad_lng=%u, bad_cmd=%u)\n", cmd, lng, tag, transaction_id, address, is_bad_tail, is_bad_lng, is_bad_cmd);
			}
			dropTransactionId = transaction_id;
			write_sent_flits(transaction_id, 0);
		}
	}


	if (dropTransactionId != transaction_id) {
		numFlitsSent++;
		// PR: The BFM has no metadata about which flit inside of a transaction we
		// are on, so we need to store this manually based on the previous flits
		// we've received
		unsigned currentFlitNumber = prevFlitNumber+1; 

		Flit_P flit(new Flit(id++, address, hmcCmd, length, is_head, is_tail, currentFlitNumber));
		(*flit).sourceLink = linkId;

		(*flit).destinationField = 0; 

		if (is_tail) {
			(*flit).returnTokens = rtc;
		}

		// Since the SC model doesn't do anything with poisoned packets, we
		// just strip out the return tokens (which will be replayed along with
		// the "good" later on).
		if (is_bad_tail) {
			(*flit).returnTokens = 0; 
		}

		(*flit).tag = transaction_id;
		(*flit).svTag = tag;

		if (debug)
			std::cout<<"===== (adapter"<<this->linkId<<"->SysC) cmd=0x"<<std::hex<<cmd<<std::dec<<", addr="<<std::hex<<address<<std::dec<<", lng="<<lng<<", rtc="<<rtc<<", tag="<<tag<<" Translated to "<<*flit<<"\n";

		if (is_tail) {
			// Report zero flits for tret (since it didn't consume any tokens to send)
			// ceusebio: SysC now needs to see NULLs
			if (is_tret || is_null) {
				write_sent_flits(transaction_id, 0);
			} else {
				if (numFlitsSent != lng) {
					cout << sc_time_stamp() << ": Expected to send "<<lng<<", got "<<numFlitsSent<<" for: "<<*flit<<"\n";
					assert(0);
				}
				write_sent_flits(transaction_id, numFlitsSent);
			}
		}


		this->cubeWrapper.addRequestFlit(this->linkId, *flit);

		// update bookkeeping
		if (is_tail) {
			// TODO: stop being lazy
			prevTag =  prevLng = prevCmd = prevTransactionId = prevAddress = prevFlitNumber = 0;
			numFlitsSent = 0;
		} else {
			// TODO: everything except flit number needs to be set only on head
			prevCmd = cmd;
			prevTag = tag;
			prevLng = lng;
			prevAddress = address;
			prevTransactionId = transaction_id;
			prevFlitNumber = currentFlitNumber;
		}
	} else { 
		if (debug)
			printf("Wrapper dropping remaining flit cmd=%x lng=%u tag=%u tid=%u addr=0x%lx\n", cmd, lng, tag, transaction_id, address);
		numFlitsSent = 0;
	}
}

void bfm_adapter::flit_to_bits() {
	while (true) {
		wait(responseWaitingEvent);
		while (!this->pendingResponseQueue.empty()) {

			Flit &flit = *pendingResponseQueue.front();
			flit.consumedByBFM=true;
			pendingResponseQueue.pop_front();

			if (flit.command == TOKEN_RETURN) {
				flit.tag = 0;
			}

			// extra bit is the toggle bit; see hmc.sv for details
			sc_lv <RTC_BITS+1> returnTokenBits; 

			if (debug)
				std::cout << sc_time_stamp()<< "======== (SysC->adapter"<<this->linkId<<") BFM Wrapper popping response flit "<< flit<< "\n";

			// In these cases, 'tag' is really 'transaction_id' because that's what we passed on the input path
			if (flit.tag > 0 && flit.header) {
				sc_lv<64> tag = flit.tag;
				tag[63] = tag_toggle_bit;
				tag_toggle_bit = !tag_toggle_bit;

				if (debug)
					std::cout << sc_time_stamp()<<"~~~~~~~~  (SysC->adapter"<<this->linkId<<") writing tag bits "<<tag<<" back to BFM\n";
				bits_out.write(tag);
			}
			if (flit.returnTokens > 0 && (flit.header || flit.tail)) {
				// Put the toggle bit into the highest order bit 
				// PR: perhaps something like (!!token_toggle_bit) << RTC_BITS + flit.returnTokens ? 

				returnTokenBits = (token_toggle_bit ? (1<<RTC_BITS) : 0) + flit.returnTokens;
				token_toggle_bit = !token_toggle_bit;
				if (debug)
					std::cout << sc_time_stamp()<<"~~~~~~~~  (SysC->adapter"<<this->linkId<<") returning "<<flit.returnTokens<<" tokens (raw value="<<returnTokenBits<<")\n";
				this->return_tokens.write(returnTokenBits);
			//	wait(1, SC_PS);
			}
			delete(&flit);
			wait(1, SC_PS);
		}
	}
}

void bfm_adapter::link_power_state_change() {
	cubeWrapper.changeLinkState(this->linkId, this->link_power_state.read());
}

#if defined(NCSC) || defined(MTI_SYSTEMC) // cadence or mentor
SC_MODULE_EXPORT(hmc_2_in_1_wrapper); // VCS is not a fan of this line
#endif
