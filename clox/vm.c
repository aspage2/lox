#include <stdio.h>

#include "vm.h"
#include "chunk.h"
#include "value.h"
#include "debug.h"
#include "scanner.h"
#include "compiler.h"

VM vm;

static void resetStack() {
	vm.stackTop = vm.stack;
}

void initVM() {
	resetStack();
}

void freeVM() {
	resetStack();
}

static InterpretResult run() {
#define READ_BYTE() (*vm.ip++)
#define READ_CONSTANT() (vm.chunk->constants.data[READ_BYTE()])
#define BINARY_OP(operator) do { \
	double b = pop(); \
	double a = pop(); \
	push(a operator b); \
} while (false)

	while (true) {
#ifdef DEBUG_TRACE_EXECUTION
		printf("     ");
		for (Value* slot = vm.stack; slot < vm.stackTop; slot ++) {
			printf("[ ");
			printValue(*slot);
			printf(" ]");
		}
		printf("\n");
		disassembleInstruction(vm.chunk, (int)(vm.ip - vm.chunk->code));
#endif
		uint8_t instruction;
		switch (instruction = READ_BYTE()) {

			case OP_RETURN:
				printValue(pop());
				printf("\n");
				return INTERPRET_OK;

			case OP_CONSTANT:
				push(READ_CONSTANT());
				break;

			case OP_NEGATE: 
				push(-pop());
				break;

			case OP_ADD:      BINARY_OP(+); break;
			case OP_SUBTRACT: BINARY_OP(-); break;
			case OP_MULTIPLY: BINARY_OP(*); break;
			case OP_DIVIDE:   BINARY_OP(/); break;
		}
	}
#undef READ_BYTE
#undef READ_CONSTANT
#undef BINARY_OP
}

InterpretResult interpret(const char * source) {
	Chunk chunk;
	initChunk(&chunk);

	if (!compile(source, &chunk)) {
		freeChunk(&chunk);
		return INTERPRET_COMPILE_ERROR;
	}

	vm.chunk = &chunk;
	vm.ip = vm.chunk->code;

	InterpretResult r = run();

	freeChunk(&chunk);
	return r;
}

void push(Value value) {
	*vm.stackTop = value;
	vm.stackTop++;
}

Value pop() {
	vm.stackTop--;
	return *vm.stackTop;
}

