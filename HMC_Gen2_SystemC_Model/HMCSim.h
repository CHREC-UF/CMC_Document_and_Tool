#ifndef HMCSIM_H
#define HMCSIM_H

#include <vector>
#include "tlm.h"
#include "tlm_utils/simple_initiator_socket.h"
#include "tlm_utils/simple_target_socket.h"

namespace Micron
{ 
  namespace Internal
  {
    namespace HMC2
    {
      //foreward declaration of configuration object
      class Config;
      class hmc2_call_wrapper;

      //traffic generator 
      class hmc2_generator : public sc_core::sc_module
				{
				public:
					//used to dictate request generation rate
					void SetClock(sc_clock *clock);
					//used to indicate requests have been issued and responses have been received
					void SetDone(sc_signal<bool> *done);
					//gets the TLM socket that each generator uses to issue commands
					tlm_utils::simple_initiator_socket<hmc2_generator>* GetRequestSocket();
				};
		
			//trace reader
			class hmc2_trace_reader : public sc_core::sc_module
				{
				public:
					//used to dictate request generation rate
					void SetClock(sc_clock *clock);
					//used to indicate requests have been issued and responses have been received
					void SetDone(sc_signal<bool> *done);
					//gets the TLM socket that each generator uses to issue commands
					tlm_utils::simple_initiator_socket<hmc2_trace_reader>* GetRequestSocket();
				};
      
      //object which contains both the HMC host controller and the cube itself
      class hmc2_hmc_wrapper : public sc_core::sc_module
				{
				public:
					//receive the TLM sockets of the HMC host controller object
					std::vector<tlm_utils::simple_target_socket<hmc2_call_wrapper>*> GetControllerSockets();
					//print the statistics to the screen
					void DumpStats();	  
				};
      
      //getter functions 
      Config* GetConfig(std::string configFilename);
      hmc2_hmc_wrapper* GetHMCWrapper(const Config& config);
      hmc2_generator* GetGenerator(sc_core::sc_module_name module_name, unsigned index, const Config& config);
			hmc2_trace_reader* GetTraceReader(sc_core::sc_module_name module_name, unsigned id, const Config& config);        
      unsigned GetNumGenerators(const Config& config);
			bool TraceEnabled(const Config& cfg);	

      //
      //
      //Class used to check when all traffic generators have completed
      //
      //
      class hmc2_monitor : public sc_core::sc_module
				{
					SC_HAS_PROCESS(hmc2_monitor);	 
				public:
					//ports
					sc_vector< sc_in<bool> > done;
					//fields
					unsigned numGenerators;
					std::vector<bool> finishedGenerators;
	  
					//constructor
				hmc2_monitor(sc_core::sc_module_name _module_name,
										 unsigned _numGenerators):
					sc_module(_module_name),
						numGenerators(_numGenerators)
						{
							done.init(_numGenerators);
							finishedGenerators = std::vector<bool>(_numGenerators, false);
	      
							SC_METHOD(GeneratorDone);
							for(unsigned i=0;i<_numGenerators;i++)sensitive<<done[i];
						}		
	  
					//method
					void GeneratorDone()
					{
						for(unsigned i=0;i<numGenerators;i++)
							{
								if(done[i].event())
									{
										cout<<"=["<<sc_time_stamp()<<"]= GENERATOR "<<i<<" DONE!!!"<<endl;
										finishedGenerators[i]=true;
									}
							}
	    
						//check to see if everyone is done
						for(unsigned i=0;i<numGenerators;i++)
							{
								if(!done[i]) return;
							}
						sc_stop();
					}
				};
    }
  }
}


#endif
