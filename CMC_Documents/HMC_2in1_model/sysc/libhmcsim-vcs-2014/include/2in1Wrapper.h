#ifndef _2in1_WRAPPER_
#define _2in1_WRAPPER_

#include <deque>
#include <vector>
#include <systemc>
#include "hmc2_flit.h"

namespace Micron {
	namespace Internal {
		namespace HMC2 {
			class hmc2_cube;
		}
	}
}

#ifdef MENTOR
	#include "sc_vector.h"
	using sc_core::sc_vector;
#endif

class CubeDriver;
using std::deque;
using std::vector;
using sc_core::sc_event;
using sc_core::sc_vector;
using sc_core::sc_signal;
using sc_dt::sc_lv;
using Micron::Internal::HMC2::hmc2_cube;
using Micron::Internal::HMC2::Flit;
using Micron::Internal::HMC2::Flit_P;

SC_MODULE(Cube2in1Wrapper) {
	hmc2_cube &cube; 

	// one per link
	vector<CubeDriver *> drivers; 

	sc_vector < sc_signal <Flit_P> >  cubeToDriver, driverToCube;
	sc_vector < sc_signal <bool> >   linkPowerStates;
	sc_signal <bool> clk;

	public:
	sc_event responseFlitsAddedEvent;

	void addRequestFlit(unsigned linkId, Flit &request); 
	void changeLinkState(unsigned linkId, unsigned state); 

	void tokenAdjustment(unsigned linkId, int adjustBy);

	void setLinkParams(unsigned bfmRate, unsigned numLanes);
	void setCubeTokens(unsigned numTokens);
	void setHostTokens(unsigned numTokens);
	void setCubeSize(unsigned numPartitions);
	void setBlockSize(unsigned blockSize);
	void setResponseOpenLoopMode(unsigned responseOpenLoopMode);
	void setTj(unsigned tj);
    void setDramTracingEn(unsigned dramTracingEn);
	void setRefreshEn(unsigned refreshEn);

	deque<Flit_P> &getPendingResponseQueue(unsigned linkId);
	sc_event &getResponseWaitingEvent(unsigned linkId);


	void DumpStats();

	Cube2in1Wrapper(sc_core::sc_module_name name_);

};

#endif // _2in1_WRAPPER_
