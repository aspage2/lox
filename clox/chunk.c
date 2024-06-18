#include <stdlib.h>

#include "chunk.h"
#include "memory.h"

void initChunk(Chunk *c) {
	c->count = 0;
	c->capacity = 0;
	c->code = NULL;
	c->lines = NULL;

	initValueArray(&c->constants);
}

void freeChunk(Chunk *c) {
	FREE_ARRAY(uint8_t, c->code, c->capacity);
	FREE_ARRAY(int, c->lines, c->capacity);
	freeValueArray(&c->constants);
	initChunk(c);
}

void writeChunk(Chunk *c, uint8_t byte, int line) {
	if (c->count >= c->capacity) {
		int oldCap = c->capacity;
		c->capacity = GROW_CAPACITY(oldCap); 
		c->code = GROW_ARRAY(uint8_t, c->code, oldCap, c->capacity);
		c->lines = GROW_ARRAY(int, c->lines, oldCap, c->capacity);
	}
	c->code[c->count] = byte;
	c->lines[c->count] = line;
	c->count += 1;
}

int addConstant(Chunk *c, Value v) {
	writeValueArray(&c->constants, v);
	return c->constants.count - 1;
}

