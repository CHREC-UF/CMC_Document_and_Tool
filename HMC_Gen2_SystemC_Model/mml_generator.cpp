// ----------------------------------------------------------------------------
// Copyright (c) Micron Technology Inc. All rights reserved.
//
// Generator source file
//
// Author: Elliott Cooper-Balis 
// ----------------------------------------------------------------------------

//
//default values for parameters
//
#define PERCENTAGE_16B 0
#define PERCENTAGE_32B 0
#define PERCENTAGE_48B 0
#define PERCENTAGE_64B 100
#define PERCENTAGE_80B 0
#define PERCENTAGE_96B 0
#define PERCENTAGE_112B 0
#define PERCENTAGE_128B 0
#define MIN_ADDRESS 0
#define MAX_ADDRESS 4294967296
#define NUM_REQUESTS 1000000
#define PERCENTAGE_READ 50
#define PERCENTAGE_SEQUENTIAL 0
#define USE_FREQUENCY 100
#define PRINT_DEBUG true
#define BURST_TIME 100 
#define IDLE_TIME 0
#define EXPECT_WRITE_RESPONSES false

#include "mml_generator.h"

using namespace std;

SC_HAS_PROCESS(mml_generator);

mml_generator::mml_generator(sc_core::sc_module_name _module_name,
														 uint _id):
	sc_module(_module_name),
	requestSocket("requestSocket"),
	minAddress(MIN_ADDRESS),
	maxAddress(MAX_ADDRESS),
	numRequests(NUM_REQUESTS),
	percentageRead(PERCENTAGE_READ),
	percentageSequential(PERCENTAGE_SEQUENTIAL),
	useFrequency(USE_FREQUENCY),
	burstTime(BURST_TIME),
	idleTime(IDLE_TIME),
	expectWriteResponses(EXPECT_WRITE_RESPONSES),
	printDebug(PRINT_DEBUG),
	id(_id),
	issuedRequests(0),
	issuedReads(0),
	readResponses(0),
	issuedWrites(0),
	writeResponses(0),
	failedRequest(false),
	idlingBus(false),
	tempFinalAddress(0),
	requestSizePick(0),
	requestTypePick(0),
	requestLength(0),
	probabilityAccumulate(0)
{
	cout<<"=== Creating generator "<<_id<<" ==="<<endl;	

	if(PERCENTAGE_16B + 
		 PERCENTAGE_32B + 
		 PERCENTAGE_48B + 
		 PERCENTAGE_64B + 
		 PERCENTAGE_80B + 
		 PERCENTAGE_96B + 
		 PERCENTAGE_112B + 
		 PERCENTAGE_128B != 100)
	{
		cout<<"== ERROR - Request size percentages don't equal 100%"<<endl;
		assert(false);
	}
 
	//fill in our probabilities array
	probabilities[0] = PERCENTAGE_16B;
	probabilities[1] = PERCENTAGE_32B;
	probabilities[2] = PERCENTAGE_48B;
	probabilities[3] = PERCENTAGE_64B;
	probabilities[4] = PERCENTAGE_80B;
	probabilities[5] = PERCENTAGE_96B;
	probabilities[6] = PERCENTAGE_112B;
	probabilities[7] = PERCENTAGE_128B;
	
	//thread responsible for sending requests
	SC_CTHREAD(SendTraffic,clk.pos());

	//runs forever, doesn't need sensitivity 
	if(idleTime>0)
	{
		SC_THREAD(ToggleIdle);
	}

	SC_METHOD(ToggleDone);
	sensitive<<doneEvent;
	dont_initialize();

	//get TLM2.0 stuff ready
	lastAddress = GenerateAddress();
	lastSize = 0;
	tlmDelay = sc_time(0, SC_NS);
	requestSocket.register_nb_transport_bw(this, &mml_generator::nb_transport_bw);
}

tlm_utils::simple_initiator_socket<mml_generator>* mml_generator::GetRequestSocket()
{
	//return a handle to the TLM2.0 socket
	return &requestSocket;
}

void mml_generator::SetClock(sc_clock *c)
{
	this->clk(*c);
}

void mml_generator::SetDone(sc_signal<bool> *d)
{
	this->done(*d);
}

void mml_generator::ToggleDone()
{
	//toggle the output port that indicates this generator has sent all requests, and received all responses
	done.write(true);
}

tlm::tlm_sync_enum mml_generator::nb_transport_bw(tlm::tlm_generic_payload& trans, tlm::tlm_phase& phase, sc_time& delay)
{
	cout<<"=["<<sc_time_stamp()<<"]= nb_transport_bw called in Generator "<<id<<endl;
	
	//Check phase
	//
	//If phase is END_REQ, the last request was finally accepted, so do some bookkeeping
	if(phase==tlm::END_REQ)
	{
		if(printDebug)cout<<"\t!! (Finally) Accepted !!"<<endl;

		failedRequest = false;
		issuedRequests++;
		if(transaction->is_read())
		{
			issuedReads++;
		}
		else
		{
			issuedWrites++;
		}
			
		//if we have issued all requests, check to see if we are done
		if(issuedRequests>numRequests)
		{
			cout<<"=["<<sc_time_stamp()<<"]= Generator "<<id<<" finished issuing ["<<(issuedReads/(float)(issuedReads+issuedWrites))*100<<"% R/W]"<<endl;
			if(!expectWriteResponses)
			{
				if(readResponses==issuedReads)
				{ 
					doneEvent.notify(SC_ZERO_TIME);
				}
			}
			else
			{
				if(readResponses==issuedReads && writeResponses==issuedWrites)
				{
					doneEvent.notify(SC_ZERO_TIME);
				}				
			}
		}		
	}
	//if phase is BEGIN_RESP, then we are receiving a response packet so keep track of our responses
	else if(phase==tlm::BEGIN_RESP)
	{
		if(trans.is_read())
		{
			if(printDebug)cout<<"=["<<sc_time_stamp()<<"]= Generator "<<id<<" received READ response from : 0x"<<hex<<setw(8)<<setfill('0')<<trans.get_address()<<dec<<endl;
			readResponses++;
		}
		else
		{
			if(printDebug)cout<<"=["<<sc_time_stamp()<<"]= Generator "<<id<<" received WRITE response from : 0x"<<hex<<setw(8)<<setfill('0')<<trans.get_address()<<dec<<endl;
			if(!expectWriteResponses)
			{
				cout<<"=["<<sc_time_stamp()<<"]= ERROR - Received a WRITE response to Generator "<<id<<" who is not expecting them"<<endl;
				exit(0);
			}
			else
			{
				writeResponses++;
			}
		}
			
		//if we have issued all requests, check to see if we are done
		if(issuedRequests>numRequests)
		{
			if(!expectWriteResponses)
			{
				if(readResponses==issuedReads)
				{
					cout<<"=["<<sc_time_stamp()<<"]= All responses receives in Generator "<<id<<endl;
					doneEvent.notify(SC_ZERO_TIME);
				}
			}
			else
			{
				if(readResponses==issuedReads && writeResponses==issuedWrites)
				{				
					doneEvent.notify(SC_ZERO_TIME);
				}
			}
		}

		//Free transaction back to memory pool
		trans.release();
		delay = SC_ZERO_TIME;
		return tlm::TLM_COMPLETED;
	}
	else
	{
		cout<<"=["<<sc_time_stamp()<<"]= ERROR - Unrecognized phase in nb_transport_bw in Generator "<<id<<endl;
		exit(0);
	}

	return tlm::TLM_ACCEPTED;
}

void mml_generator::GenerateRequestTLM()
{ 
	transaction = memoryManager.allocate();
	transaction->acquire();
	
	//randomly determine if request is sequential from past address
	sequentialPick = rand()%100;
	if(sequentialPick<=percentageSequential)
	{
		if(printDebug) cout<<"=["<<sc_time_stamp()<<"]= [Sequential lastAddress:"<<hex<<lastAddress<<dec<<" lastSize:"<<lastSize<<"] ";
		transaction->set_address(lastAddress + lastSize);
		lastAddress += lastSize;
	}
	else
	{
		if(printDebug) cout<<"=["<<sc_time_stamp()<<"]= ";

		//get the address and store it in a field in case next address is sequential
		lastAddress = GenerateAddress();
		//set the transaction address
		transaction->set_address( lastAddress );
	}
	
	//sets the link id that this request should be sent on
	transaction->set_streaming_width(id);
	
	//set the transaction size
	requestSizePick = rand() % 100;
	probabilityAccumulate=0;				
	for(int i=0;i<8;i++)
	{
		probabilityAccumulate+=probabilities[i];
		if(probabilityAccumulate>requestSizePick)
		{
			lastSize = 16*(i+1);
			transaction->set_data_length( lastSize );
			break;
		}
	}
	
	//set the transaction type
	requestTypePick = rand() % 100;
	if(requestTypePick<percentageRead)
	{
		transaction->set_command(tlm::TLM_READ_COMMAND);
	}
	else
	{
		transaction->set_command(tlm::TLM_WRITE_COMMAND);
	}
	
	if(printDebug)
	{
		cout<<"Generator "<<id<<" - Creating Request : ";
		if(transaction->is_read())
			cout<<"READ ";
		else
			cout<<"WRITE ";
		cout<<" of "<<transaction->get_data_length()<<"B to 0x"<<setw(8)<<setfill('0')<<hex<<transaction->get_address()<<dec<<endl;
	}

	//write this transaction to the socket if we pass the USE_FREQUENCY TEST
	if(rand()%100<=USE_FREQUENCY)
	{
		tlmPhase = tlm::BEGIN_REQ; 
		returnValue = requestSocket->nb_transport_fw(*transaction, tlmPhase, tlmDelay);
	}
	else
	{
		transaction->release();
		if(printDebug)cout<<"\t!! Tossed !!"<<endl;
		return;
	}
			
	//check the response
	//
	//if return value was TLM_UPDATED, then the request was accepted so do some bookkeeping
	if(returnValue==tlm::TLM_UPDATED)
	{ 
		if(printDebug)cout<<"\t!! Accepted !!"<<endl;
		issuedRequests++;
		if(transaction->is_read())
		{
			issuedReads++;
		}
		else
		{
			issuedWrites++;
		}
		
		if(issuedRequests>numRequests)
		{
			cout<<"=["<<sc_time_stamp()<<"]= Generator "<<id<<" finished issuing ["<<(issuedReads/(float)(issuedReads+issuedWrites))*100<<"% R/W]"<<endl;
			if(!expectWriteResponses)
			{				
				if(readResponses==issuedReads)
				{		
					doneEvent.notify(SC_ZERO_TIME);
				}
			}
			else
			{
				if(readResponses==issuedReads && writeResponses==issuedWrites)
				{
					doneEvent.notify(SC_ZERO_TIME);
				}				
			}
		}
	}
	//if return value was TLM_ACCEPTED, then the request is pending an explicit call will indicate it has finished
	else if(returnValue==tlm::TLM_ACCEPTED)
	{
		if(printDebug)cout<<"\t!! Waiting for acceptance !!"<<endl;
		failedRequest = true;
	}
	else
	{
		cout<<"=["<<sc_time_stamp()<<"]= ERROR - Unknown TLM response in generator"<<endl;
		assert(false);
	}
}


uint64_t mml_generator::GenerateAddress()
{
	//Generate an address based on minAddress and maxAddress fields
	tempFinalAddress = (rand() % (maxAddress + 1 - minAddress)) + minAddress;
	
	return tempFinalAddress;
}

void mml_generator::SendTraffic()
{
	while(true)
	{
		wait();			 
			
		//if we have issued all of our requests, break out of this loop
		if(issuedRequests>numRequests)break;

		//generate a request as long as we are not idling or waiting for a prior request to be accepted
		if(!idlingBus && !failedRequest)GenerateRequestTLM();
	}
}

void mml_generator::ToggleIdle()
{
	while(true)
	{
		//stop toggling if we are at our max requests
		if(issuedRequests==numRequests)break;

		wait(burstTime, SC_NS);
		idlingBus = true;
		if(printDebug)cout<<"=["<<sc_time_stamp()<<"]= Idling Generator "<<id<<endl;
		wait(idleTime, SC_NS);			
		if(printDebug)cout<<"=["<<sc_time_stamp()<<"]= Resuming Generator "<<id<<endl;
		idlingBus = false;
	}
}
