#include <stdio.h>

#include "value.h"
#include "debug.h"

// A simpleInstruction has no arguments.
// Static makes this a protected function in the c file.
static int simpleInstruction(const char * name, int offset) {
	printf("%s\n", name);
	return offset + 1;
}

static int constantInstruction(const char* name, Chunk *chunk, int offset) {
	uint8_t constant = chunk->code[offset + 1];
	printf("%-16s %4d '", name, constant);
	printValue(chunk->constants.data[constant]);
	printf("'\n");
	return offset + 2;
}

void disassembleChunk(Chunk *c, const char *name) {
	printf("== %s ==\n", name);

	int i = 0;
	while (i < c->count) {
		i = disassembleInstruction(c, i);
	}
}

int disassembleInstruction(Chunk *c, int offset) {
	printf("%04d ", offset);
	// Print the line number, or a vertical bar if consecutive
	// chunks belong to the same line.
	if (offset > 0 && c->lines[offset] == c->lines[offset - 1]) {
		printf("   | ");
	} else {
		printf("%4d ", c->lines[offset]);
	}
	uint8_t inst = c->code[offset];
	switch (inst) {
	case OP_RETURN:
		return simpleInstruction("OP_RETURN", offset);
	case OP_CONSTANT:
		return constantInstruction("OP_CONSTANT", c, offset);
	default:
		printf("Unknown opcode %d\n", inst);
		return offset + 1;
	}
}

