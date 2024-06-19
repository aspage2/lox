#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "scanner.h"
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
	case OP_NEGATE:
		return simpleInstruction("OP_NEGATE", offset);
	case OP_ADD:
		return simpleInstruction("OP_ADD", offset);
	case OP_SUBTRACT:
		return simpleInstruction("OP_SUBTRACT", offset);
	case OP_MULTIPLY:
		return simpleInstruction("OP_MULTIPLY", offset);
	case OP_DIVIDE:
		return simpleInstruction("OP_DIVIDE", offset);
	default:
		printf("Unknown opcode %d\n", inst);
		return offset + 1;
	}
}

void showToken(Token t) {
	char *p;
	char *s;
	switch (t.type) {
		case TOKEN_LEFT_PAREN:		p = "LPAREN"; break;
		case TOKEN_RIGHT_PAREN:		p = "RPAREN"; break;
		case TOKEN_LEFT_BRACE:		p = "LBRACE"; break;
		case TOKEN_RIGHT_BRACE:		p = "RBRACE"; break;
		case TOKEN_COMMA:			p = "COMMA"; break;
		case TOKEN_DOT:				p = "DOT"; break;
		case TOKEN_MINUS:			p = "MINUS"; break;
		case TOKEN_PLUS:			p = "PLUS"; break;
		case TOKEN_SEMICOLON:		p = "SEMICOLON"; break;
		case TOKEN_SLASH:			p = "SLASH"; break;
		case TOKEN_STAR:			p = "STAR"; break;
		case TOKEN_BANG:			p = "BANG"; break;
		case TOKEN_BANG_EQUAL:		p = "NEQ"; break;
		case TOKEN_EQUAL:			p = "ASSIGN"; break;
		case TOKEN_EQUAL_EQUAL:		p = "EQ"; break;
		case TOKEN_GREATER:			p = "LT"; break;
		case TOKEN_GREATER_EQUAL:	p = "LTE"; break;
		case TOKEN_LESS:			p = "GT"; break;
		case TOKEN_LESS_EQUAL:		p = "GTE"; break;
		case TOKEN_AND:				p = "and"; break;
		case TOKEN_CLASS:			p = "class"; break;
		case TOKEN_ELSE:			p = "else"; break;
		case TOKEN_FALSE:			p = "false"; break;
		case TOKEN_FOR:				p = "for"; break;
		case TOKEN_FUN:				p = "fun"; break;
		case TOKEN_IF:				p = "if"; break;
		case TOKEN_NIL:				p = "nil"; break;
		case TOKEN_OR:				p = "or"; break;
		case TOKEN_PRINT:			p = "print"; break;
		case TOKEN_RETURN:			p = "return"; break;
		case TOKEN_SUPER:			p = "super"; break;
		case TOKEN_THIS:			p = "this"; break;
		case TOKEN_TRUE:			p = "true"; break;
		case TOKEN_VAR:				p = "var"; break;
		case TOKEN_WHILE:			p = "while"; break;
		case TOKEN_EOF:				p = "EOF"; break;
		
		case TOKEN_IDENT:
			printf("IDENT(%.*s)\n", t.length, s);
			return;
		case TOKEN_STRING:
			printf("STRING(%.*s)\n", t.length, s);
			return;
		case TOKEN_NUMBER:
			printf("NUMBER(%.*s)\n", t.length, s);
			return;
		case TOKEN_ERROR: 
			printf("ERROR(%.*s)\n", t.length, s);
			return;
		default:
			p = "???";
	}
	printf("%s\n", p);
}
