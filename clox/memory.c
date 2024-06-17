#include <stdlib.h>

#include "memory.h"

void* reallocate(void* ptr, size_t oldSize, size_t newSize) {
	if (newSize == 0) {
		free(ptr);
		return NULL;
	}

	void * ret = realloc(ptr, newSize);
	if (ret == NULL)
		exit(1);
	return ret;
}
