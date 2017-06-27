#include "mml_memory_manager.h"

mml_memory_manager::gp_t* mml_memory_manager::allocate()
{
#ifdef DEBUG_GENERATOR
	std::cout << "----------------------------- Called allocate(), #trans = " << ++count <<"\n";
#endif
	gp_t* ptr;
	if (free_list)
	{
		ptr = free_list->trans;
		empties = free_list;
		free_list = free_list->next;
	}
	else
	{
		ptr = new gp_t(this);
	}
	return ptr;
}

void mml_memory_manager::free(gp_t* trans)
{
#ifdef DEBUG_GENERATOR
	std::cout << "----------------------------- Called free(), #trans = " << --count << "\n";
#endif
	if (!empties)
	{
		empties = new access;
		empties->next = free_list;
		empties->prev = 0;
		if (free_list)
			free_list->prev = empties;
	}
	free_list = empties;
	free_list->trans = trans;
	empties = free_list->prev;
}
