
#ifndef clox_chunk_h
#define clox_chunk_h

#include "common.h"
#include "value.h"

typedef enum {
	OP_RETURN,
	OP_CONSTANT,
	OP_NEGATE,
	OP_ADD,
	OP_SUBTRACT,
	OP_MULTIPLY,
	OP_DIVIDE
} OpCode;

typedef struct {
	uint8_t* code;
	int* lines;

	// Dynamic Array
	int count;
	int capacity;

	ValueArray constants;
} Chunk;

void initChunk(Chunk *c);
void writeChunk(Chunk *c, uint8_t byte, int line);
void freeChunk(Chunk *c);
int addConstant(Chunk *c, Value v);

#endif
