#define SC_INCLUDE_DYNAMIC_PROCESSES

#include <systemc.h>
#include "HMCSim.h"
#include <time.h>

using namespace Micron::Internal::HMC2;
using namespace std;

void usage(){
  // Prints each argument on the command line.
  cout<<"== Usage : Tester.o <Config File>"<<endl;
  exit(0);
}

int sc_main( int argc, char* argv[] )
{
  if(argc<2)
    {
      usage();
    }

  //uses the file name from the command line as the configuration file for this simulation
  string configFileName = string(argv[1]);
  Config* cfg = GetConfig(configFileName);

  //creates the wrapper, which contains the HMC host controller and a single cube
  hmc2_hmc_wrapper *wrapper = GetHMCWrapper(*cfg);

  //creates a clock used for request generation
  sc_clock clk("TestClock", sc_time(1.6, SC_NS), 0.5);

  //stores references to the TLM2.0 sockets on the hmc2_hmc_controller module
  vector<tlm_utils::simple_target_socket<hmc2_call_wrapper>*> controllerSockets = wrapper->GetControllerSockets();

  //find out how man generators we expect
  unsigned numGenerators = GetNumGenerators(*cfg);

  //monitor used to determine when the simulation should be stopped
  hmc2_monitor monitor("monitor", numGenerators);

  //signals which attach the monitor to each generator
  sc_vector< sc_signal<bool> > generatorDone;
  generatorDone.init(numGenerators);

  char buff[32];

	bool useTrace=TraceEnabled(*cfg);
	
  //traffic generators
	
	if(useTrace)
	{
		hmc2_trace_reader** traceReaders = (hmc2_trace_reader**)malloc(sizeof(hmc2_trace_reader*)*numGenerators);
		for(unsigned i=0;i<numGenerators;i++)
		{
			sprintf(buff,"tracereader%d",i);
			traceReaders[i] = GetTraceReader(buff, i, *cfg);
			traceReaders[i]->SetClock(&clk);
			traceReaders[i]->SetDone(&generatorDone[i]);
			traceReaders[i]->GetRequestSocket()->bind(*(controllerSockets[i]));	 
			monitor.done[i](generatorDone[i]);
		}			
	}
	else
	{
		hmc2_generator** generators = (hmc2_generator**)malloc(sizeof(hmc2_generator*)*numGenerators);
		for(unsigned i=0;i<numGenerators;i++)
    {
      sprintf(buff,"generator%d",i);
      generators[i] = GetGenerator(buff, i, *cfg);
      generators[i]->SetClock(&clk);
      generators[i]->GetRequestSocket()->bind(*(controllerSockets[i]));
      generators[i]->SetDone(&generatorDone[i]);
      monitor.done[i](generatorDone[i]);
    }
	}

  //start the simulation
  cout<<"Starting simulation!!!!"<<endl;
  sc_start(100000, SC_NS);

  //print statistics to the console
  bool printStats = true;
  if(printStats)
    {
      wrapper->DumpStats();
    }

  return 0;
}
