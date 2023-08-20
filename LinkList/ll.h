
#ifndef LL_H
#define LL_H

#include <stdlib.h>

/**
 * Doubly-linked list implementation.
 *
 * Supports O(1) push/pop from either the head or tail of the list.
 */
typedef struct _ll ll;

/**
 * Create a new linked list
 */
struct ll* new_ll();

/**
 * Free the linked list.
 * All nodes and their data pointers are freed as well.
 */
void ll_free(struct ll *list);

/**
 * Return the length of the list
 */
size_t ll_size(struct ll *list);

/**
 * Push a new node onto the tail of the list.
 * Allocates a heap space of `blockSize` bytes and returns
 * a pointer to that block.
 */
void* ll_push_tail(struct ll *list, size_t blockSize);

/**
 * Push a new node onto the head of the list.
 * Allocates a heap space of `blockSize` bytes and returns
 * a pointer to that block.
 */
void* ll_push_head(struct ll *list, size_t blockSize);

/**
 * Remove a node from the head of the list
 * Client is responsible for freeing the returned
 * memory block.
 */
void* ll_pop_head(struct ll *list);

/**
 * Remove a node from the tail of the list
 * Client is responsible for freeing the returned
 * memory block.
 */
void* ll_pop_tail(struct ll *list);

#endif
