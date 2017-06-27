#ifndef __HMC2_H__
#define __HMC2_H__
#include <stdint.h>

#include <iostream>
#include <vector>
#include <string>
#include <systemc>

#include <Flit_P.h>

using sc_core::sc_time;
using sc_core::sc_vector;
using sc_core::sc_in;
using sc_core::sc_out;

namespace Micron
{ 
	namespace Internal
	{
		namespace HMC2
		{
			class hmc2_cube;
			class Config;

			// Create a cube object to send to the functions below
			hmc2_cube* GetCube(std::string *configFilename=NULL);

			//returns a handle to an sc_vector of the request links
			sc_vector< sc_in<Flit_P> >* GetRequestLinks(hmc2_cube *cube);
			//returns a handle to an sc_vector of the response links
			sc_vector< sc_out<Flit_P> >* GetResponseLinks(hmc2_cube *cube);
			//get the sc_time corresponding to the link rate
			sc_time GetLinkRate(hmc2_cube *cube, unsigned linkID);
			//print the statistics to the screen
			void DumpStats(hmc2_cube *cube);

		}// HMC2
	} // Internal
} // Micron
#endif
