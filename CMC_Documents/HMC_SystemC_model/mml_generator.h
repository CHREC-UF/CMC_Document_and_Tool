#ifndef GENERATOR_H
#define GENERATOR_H
// ----------------------------------------------------------------------------
// Copyright (c) Micron Technology Inc. All rights reserved.
//
// Header file for generator object
//
// Author: Elliott Cooper-Balis
// ----------------------------------------------------------------------------

#define SC_INCLUDE_DYNAMIC_PROCESSES

#include <iostream>
#include <iomanip>
#include "systemc.h"
#include "tlm.h"
#include "tlm_utils/simple_initiator_socket.h"
#include "mml_memory_manager.h"

class mml_generator : public sc_core::sc_module
{
 public:
	//constructor
	mml_generator(sc_core::sc_module_name _module_name,
								uint _id);

	//ports
	sc_in<bool> clk;
	sc_out<bool> done;

	void GenerateRequestTLM();
	uint64_t GenerateAddress();
	void SetClock(sc_clock *clk);
	void SetDone(sc_signal<bool> *done);
	tlm::tlm_sync_enum nb_transport_bw(tlm::tlm_generic_payload& trans, tlm::tlm_phase& phase, sc_time& delay);
	tlm_utils::simple_initiator_socket<mml_generator>* GetRequestSocket();
	void SendTraffic(); 
	void ToggleIdle();
	void ToggleDone();
	
	//fields
	//TLM.20
	tlm_utils::simple_initiator_socket<mml_generator> requestSocket;
	tlm::tlm_generic_payload *transaction;
	sc_time tlmDelay;
	mml_memory_manager memoryManager;
	tlm::tlm_sync_enum returnValue;
	tlm::tlm_phase tlmPhase;
	tlm::tlm_command tlmCommand;

	//parameters
	unsigned probabilities[8];
	uint64_t minAddress;
	uint64_t maxAddress;
	uint64_t numRequests;
	unsigned percentageRead;
	unsigned percentageSequential;
	unsigned useFrequency;
	unsigned burstTime;
	unsigned idleTime;
	bool expectWriteResponses;
	bool printDebug;

	//fields
	uint id; 

	uint64_t issuedRequests;
	uint64_t issuedReads;
	uint64_t readResponses;
	uint64_t issuedWrites;
	uint64_t writeResponses;

	bool failedRequest;
	bool idlingBus;

	uint64_t lastAddress;
	uint64_t lastSize;
	uint64_t tempFinalAddress;

	uint sequentialPick;
	uint requestSizePick;
	uint requestTypePick;
	uint requestLength;
	uint probabilityAccumulate;

	sc_event doneEvent;
};		 

#endif
