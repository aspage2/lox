#include "common.h"
#include "chunk.h"
#include "debug.h"
#include "vm.h"

int main(int argc, const char ** argv) {
	initVM();
	Chunk c;
	initChunk(&c);
	writeChunk(&c, OP_RETURN, 1);
	int constOffset = addConstant(&c, 1.22);
	writeChunk(&c, OP_CONSTANT, 1);
	writeChunk(&c, constOffset, 1);
	disassembleChunk(&c, "Chunky Boi");
	interpret(c);
	freeChunk(&c);
	freeVM();
	return 0;
}
