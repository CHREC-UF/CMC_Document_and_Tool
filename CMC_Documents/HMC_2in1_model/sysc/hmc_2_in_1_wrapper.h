#include <stdio.h>
#include <systemc.h>
#include <deque>

#include <hmc2_flit.h>
#include <2in1Wrapper.h>

// XXX: This *must* match the number of input/output ports in
// hmc_2_in_1_wrapper or else elaboration will fail 
#define MAX_LINKS 4

static const unsigned RTC_BITS=5;

using Micron::Internal::HMC2::Flit;
using Micron::Internal::HMC2::Flit_P;
using Micron::Internal::HMC2::hmc2_cube;

typedef std::deque<Flit_P> FlitQueue; 


SC_MODULE(bfm_adapter) {
	// One extra bit for toggle bit; see hmc.sv for details 
	sc_in < sc_lv<162+1> > bits_in;
	sc_in < bool > link_power_state;
	sc_in < sc_lv<33>  > token_adjustment;

	// flit -> bits
	// PR: TODO: make this symmetric
	sc_out< sc_lv<64> > bits_out;

	sc_out< sc_lv<41> > flits_sent;

	// One extra bit for toggle bit; see hmc.sv for details 
	sc_out< sc_lv<RTC_BITS+1> > return_tokens;
	bool token_toggle_bit, tag_toggle_bit;


	unsigned linkId; 
	unsigned numFlitsSent;

	Cube2in1Wrapper &cubeWrapper;

	SC_HAS_PROCESS(bfm_adapter);
	bfm_adapter(sc_module_name name_, unsigned linkId_, Cube2in1Wrapper &cubeWrapper_);
	
	sc_event &responseWaitingEvent; 
	FlitQueue &pendingResponseQueue; 

	unsigned prevTag, prevLng, prevCmd, prevTransactionId, prevFlitNumber; 
	uint64_t prevAddress; 

	unsigned dropTransactionId;

	/**
	 * Translate the header/tail bits into a an HMC flit 
	 */
	void bits_to_flits();

	/**
	 * Translate the HMC flit into pin-level (tags or tokens) going back to the
	 * BFM
	 */
	void flit_to_bits();

	void link_power_state_change(); 

	void adjust_cube_tokens();
	void write_sent_flits(unsigned transactionId, unsigned num_flits);
};

/**
 * The 2_in_1_wrapper is the pin-level interface to/from systemverilog. This is the 
 * module that gets compiled and imported into systemverilog.
 *
 * It acts as a top level for three modules: 
 * - The adapter that converts pin-level packet headers to hmcsim flits and queues them
 * - The arbiter that sends flits to the cube from the adapter
 * - The hmcsim cube itself
 */
SC_MODULE(hmc_2_in_1_wrapper) {
	// config options
	sc_in< sc_lv< 10 > > cfg_link_speed;
	sc_in< sc_lv< 3 > >  cfg_link_width;
	sc_in< sc_lv< 10 > > cfg_host_num_tokens;
	sc_in< sc_lv< 10 > > cfg_cube_num_tokens;
	sc_in< sc_lv< 11 > > cfg_block_bits;
	sc_in< sc_lv< 3 > >  cfg_cube_size;
	sc_in< sc_lv< 1 > >  cfg_response_open_loop;
	sc_in< sc_lv< 32 > >  cfg_tj;
    sc_in< sc_lv< 1  > > cfg_dram_tracing_en;
	sc_in< sc_lv< 1  > > cfg_refresh_en;

	// ports 
	// One extra bit for toggle bit; see hmc.sv for details 
	sc_in < sc_lv<162+1> > bfm_bits_in0, bfm_bits_in1, bfm_bits_in2, bfm_bits_in3;
	sc_in < sc_lv<33>  > token_adjust0,token_adjust1,token_adjust2,token_adjust3;
	sc_out< sc_lv<64> > bfm_bits_out0,bfm_bits_out1,bfm_bits_out2,bfm_bits_out3;
	sc_out< sc_lv<41> > expected_sysc_token_return0,expected_sysc_token_return1,expected_sysc_token_return2,expected_sysc_token_return3;

	// One extra bit for toggle bit; see hmc.sv for details 
	sc_out< sc_lv<RTC_BITS+1> > bfm_return_tokens0,bfm_return_tokens1,bfm_return_tokens2,bfm_return_tokens3;
	sc_in < bool > link_power0, link_power1, link_power2, link_power3; 


	// the BFM will let us know when to stop simulating; unused for now 
	sc_in <bool> simulationFinishedSignal;

	// internal signals
	sc_signal < bool > clk_signal;
	sc_vector < sc_signal < bool > >  link_power_to_adapter;


	// modules
	std::vector<bfm_adapter *> adapters;
	Cube2in1Wrapper cubeWrapper; 

	// constructor
	SC_HAS_PROCESS(hmc_2_in_1_wrapper);
	hmc_2_in_1_wrapper(sc_module_name name, const char *hmcsim_config_filename="config.ini");

	// functions
	void simulationFinished(); 
	void setConfig();

	void end_of_simulation() {
		simulationFinished();
	}

};
unsigned inline closestPowerOf2(uint32_t v) 
{
	/* PR: I won't pretend I know how this works, but I tested it and it does
	 * produce the nearest power of two correctly. 
	 * Source: http://graphics.stanford.edu/~seander/bithacks.html#IntegerLogDeBruijn
	 */
	int r;      // result goes here

	static const int MultiplyDeBruijnBitPosition[32] = 
	{
		0, 9, 1, 10, 13, 21, 2, 29, 11, 14, 16, 18, 22, 25, 3, 30,
		8, 12, 20, 28, 15, 17, 24, 7, 19, 27, 23, 6, 26, 5, 4, 31
	};

	v |= v >> 1; // first round down to one less than a power of 2 
	v |= v >> 2;
	v |= v >> 4;
	v |= v >> 8;
	v |= v >> 16;

	r = MultiplyDeBruijnBitPosition[(uint32_t)(v * 0x07C4ACDDU) >> 27];
	return r; 
}
unsigned inline return_tokens_to_bits(unsigned rtc) {
	if (rtc == 0)
		return 0;
	// 0-> 0   = 0 
	// 1-> 0+1 = 1 
	// 2-> 1+1 = 2
	// 4-> 2+1 = 3
	// ... 
	// 64->6+1 = 7 
	return closestPowerOf2(rtc) + 1; 
}
