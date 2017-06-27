// ----------------------------------------------------------------------------
// Copyright (c) Micron Technology Inc. All rights reserved.
//
// ©2015 Micron Technology, Inc. All rights reserved.  All information is provided on an "AS IS" basis 
// without warranties of any kind. Micron, the Micron logo, and all other Micron trademarks are the 
// property of Micron Technology, Inc.  All other trademarks are the property of their respective owners.
//
// MICRON HIGHLY CONFIDENTIAL AND PROPRIETY
//
// Author: Elliott Cooper-Balis
// ----------------------------------------------------------------------------

#ifndef __FLIT_P_H__
#define __FLIT_P_H__

#include <iostream>
#include <stdint.h>
#include <systemc>

using std::ostream; 

namespace Micron 
{
	namespace Internal 
	{
		namespace HMC2
		{
			struct Flit; 

			//
			//List of commands used in the HMC protocol
			//
			enum HMCCommand
			{
				READ_REQUEST,
				READ_RESPONSE,
				P_WRITE_REQUEST,
				WRITE_REQUEST,
				WRITE_RESPONSE,
				TOKEN_RETURN,	
				ATOMIC_BWR,
				ATOMIC_P_BWR,
				ATOMIC_DADD8,
				ATOMIC_P_DADD8,
				ATOMIC_ADD16,
				ATOMIC_P_ADD16,
				NULL_COMMAND
			};

			class Flit_P
			{
			public:
				//main constructor 
				Flit_P(unsigned tag=0, uint64_t addr=0, HMCCommand cmd=NULL_COMMAND, unsigned length=0, bool header=0, bool tail=0, unsigned number=0);

				//attaches tokens - must be a tail flit
				void AttachTokens(unsigned tokenCount);

				//gets the tag of the packet that this flit is associated with
				unsigned GetTag() const;
				//indicates if this flit is a header flit
				bool IsHead() const;
				//indicates if this flit is a tail flit
				bool IsTail() const; 
				//gets the address of the packet that this flit is associated with
				uint64_t GetAddress() const; 
				//gets the request size of the packet that this flit is associated with
				unsigned GetRequestSize() const;
				//gets the command type of the packet that this flit is associated with
				HMCCommand GetCommand() const;
				//returns the number of tokens attached to this flit
				unsigned GetNumReturnTokens() const;
				//gets the position of this flit in its respective packet
				unsigned GetFlitNumber() const;

				//operator that allows a flit to be printed to a stream
				friend ostream& operator<<(ostream& os, const Flit_P &f);



				//
				//NOT USED
				//
				//global ID for this flit
				static uint64_t guid;
				//internal flit object
				Flit* flit;
				//ID for this flit
				uint64_t uniqueID;				

				Flit_P(Flit* f)
					{flit=f;uniqueID=++guid;}

				inline Flit& operator*()
				{return *(this->flit);}

				bool operator==(const Flit_P &flit_p) const;

				inline Flit_P& operator=(const Flit_P &flit_p) 
					{
						flit = flit_p.flit;
						uniqueID = flit_p.uniqueID;
						return *this;
					}	
					
				friend void sc_trace(sc_core::sc_trace_file*& tf, const Micron::Internal::HMC2::Flit_P& object, const std::string &name)
				{}	
			};			
		}// namespace HMC
	}// namespace Internal
}//namespace Micron
#endif // guard 
