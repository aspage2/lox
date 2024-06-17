
#ifndef clox_memory_h
#define clox_memory_h

#include "common.h"

#define GROW_CAPACITY(cap) \
	((cap) < 8 ? 8 : (cap) * 2)

#define GROW_ARRAY(typ, ptr, oldCap, newCap) \
	(typ*)reallocate(ptr, sizeof(typ)*(oldCap), sizeof(typ)*(newCap))

#define FREE_ARRAY(typ, ptr, cap) \
	reallocate(ptr, sizeof(typ) * (cap), 0)

void * reallocate(void *ptr, size_t oldSize, size_t newSize);

#endif
