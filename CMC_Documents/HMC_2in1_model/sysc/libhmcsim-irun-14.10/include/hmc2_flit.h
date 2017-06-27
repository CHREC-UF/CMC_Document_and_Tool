#ifndef _HMC2_FLIT_H_
#define _HMC2_FLIT_H_

#include <iostream>
#include <iomanip>
#include <stdint.h>
#include <systemc>
#include <string>
#include "hmc2_flit_p.h"

using sc_core::sc_time;
using sc_core::SC_ZERO_TIME;

using std::ostream;
using std::hex;
using std::dec;
using std::setw;
using std::setfill;
using std::endl;

namespace Micron 
{
	namespace Internal
	{
		namespace HMC2
		{
			//
			// Flit object which is used as basic means of communication within the system
			//
			struct Flit
			{	
				unsigned tag;
				int svTag; //original tag from BFM
				bool consumedByBFM; // has response been consumed by BFM?
				uint64_t address;
				HMCCommand command;
				unsigned requestLength;
				bool header;
				bool tail;
				unsigned flitNumber;
				unsigned returnTokens;
				unsigned sourceLink;
				unsigned destinationField;
				int currentLane;
				sc_time startTimeReqLink;
				sc_time startTimeLSW_L;
				sc_time startTimeLSW_R;
				sc_time startTimeTransQ;
				sc_time startTimeReqQ;
				sc_time startTimeVSW_L;
				sc_time startTimeVSW_R;
				sc_time startTimeRspLink;
				unsigned valid; 

				~Flit();// {
				//valid=0;
				//}
				Flit();
				Flit(unsigned ID, uint64_t addr, HMCCommand cmd, unsigned length, bool header, bool tail, unsigned number);//:
				/*
					tag(ID),
					svTag(-1),
					consumedByBFM(false),
					valid(0x123456), // this magic number will be explicitly cleared by the destructor
					address(addr),
					command(cmd),
					requestLength(length),
					header(header),
					tail(tail),
					flitNumber(number),
					returnTokens(0),
					sourceLink(-1),
					destinationField(-1)
					{}
				*/
		
				// PR: vastly reduces merge conflicts with 2in1 branch
				unsigned getTag() const {
					return svTag >= 0 ? (unsigned)svTag : tag;
				}

				std::string getSvTagStr() const {
					char tmp[16]; 
					snprintf(tmp, 16, "%03x", getTag());
					return std::string(tmp);
				}

				friend std::ostream& operator<<(std::ostream& os, const Flit &f);
				bool operator==(const Flit &flit) const;
				Flit& operator=(const Flit &flit);
				friend void sc_trace(sc_core::sc_trace_file*& tf, const Micron::Internal::HMC2::Flit& object, const std::string &name);
			};
		}// namespace HMC
	} // namespace Internal 
} // namespace Micron 

#endif // guards 
