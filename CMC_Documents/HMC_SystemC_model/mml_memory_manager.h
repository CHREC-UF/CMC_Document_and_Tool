#ifndef MEMORY_MANAGER_H
#define MEMORY_MANAGER_H

#include "tlm.h"

class mml_memory_manager: public tlm::tlm_mm_interface
{
	typedef tlm::tlm_generic_payload gp_t;
	
 public:
 mml_memory_manager() : free_list(0), empties(0)
#ifdef DEBUG_GENERATOR
		, count(0)
#endif
		{}
	
	gp_t* allocate();
	void	free(gp_t* trans);
	
 private:
	struct access
	{
		gp_t* trans;
		access* next;
		access* prev;
	};
	
	access* free_list;
	access* empties;
	
#ifdef DEBUG_GENERATOR
	int			count;
#endif
};

#endif
