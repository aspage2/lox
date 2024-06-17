
#include "common.h"
#include "vm.h"

VM vm;

void initVM() {

}

void freeVM() {

}

InterpretResult interpret(Chunk *c) {
	vm.chunk = c;
	vm.ip = vm.chunk->code;
	return INTERPRET_OK;
}

static InterpretResult run() {
#define READ_BYTE() (*vm.ip++)
	while (true) {
		uint8_t instruction;
		switch (instruction = READ_BYTE()) {
		case OP_RETURN:
			return INTERPRET_OK;
		}
	}
}
