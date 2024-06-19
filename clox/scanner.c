#include <stdio.h>
#include <string.h>

#include "common.h"
#include "scanner.h"

typedef struct {
	const char *start;
	const char *current;
	int line;
} Scanner;

Scanner scanner;

void initScanner(const char* source) {
	scanner.start = source;
	scanner.current = source;
	scanner.line = 1;
}

static bool isAtEnd() {
	return *scanner.current == '\0';
}

// return the current char and advance the scanner by 1.
static char advance() {
	scanner.current ++;
	return scanner.current[-1];
}

static char peek() {
	return *scanner.current;
}

static char peekAhead() {
	if (isAtEnd()) return '\0';
	return scanner.current[1];
}

static Token makeToken(TokenType typ) {
	Token t;
	t.type = typ;
	t.start = scanner.start;
	t.length = (int)(scanner.current - scanner.start);
	t.line = scanner.line;
	return t;
}

static Token errorToken(const char* msg) {
	Token token;
	token.type = TOKEN_ERROR;
	token.start = msg;
	token.length = (int)strlen(msg);
	token.line = scanner.line;
	return token;
}

// check if the current char equals c. if so,
// consume it and return true. otherwise,
// do nothing and return false.
static bool match(char c) {
	if (isAtEnd()) return false;
	if (*scanner.current != c) return false; 
	scanner.current ++;
	return true;
}

static void skipWhitespace() {
	while (true) {
		switch (peek()) {
		case ' ':
		case '\r':
		case '\t':
			scanner.current++;
			break;
		case '\n':
			scanner.line++;
			scanner.current++;
			break;
		case '/':
			if (peekAhead() == '/') {
				while (peek() != '\n' && !isAtEnd()) advance();
			} else {
				return;
			}
		default:
			return;
		}
	}
}

static Token string() {
	while (peek() != '"' && !isAtEnd()) {
		if (peek() == '\n') scanner.line++;
		scanner.current++;
	}
	if (isAtEnd()) return errorToken("Unterminated string");

	advance();
	return makeToken(TOKEN_STRING);
}

static bool isAlpha(char c) {
	return c >= 'a' && c <= 'z' || 
		   c >= 'A' && c <= 'Z' || 
		   c == '_';
}
static bool isDigit(char c) {
	return c >= '0' && c <= '9';
}

static TokenType checkKeyword(int st, int len, const char *rest, TokenType typ) {
	if (scanner.current - scanner.start == st + len &&
			memcmp(scanner.start + st, rest, len) == 0) return typ;
	return TOKEN_IDENT;
}

// Figure out what token the current
// lexeme is by comparing it against the
// reserved words in Lox. 
static TokenType identType() {
	switch (scanner.start[0]) {
	case 'a': return checkKeyword(1, 2, "nd", TOKEN_AND);
	case 'c': return checkKeyword(1, 4, "lass", TOKEN_CLASS);
	case 'e': return checkKeyword(1, 3, "lse", TOKEN_ELSE);
	case 'f':
		if (scanner.current - scanner.start > 1) {
			switch (scanner.start[1]) {
				case 'a': return checkKeyword(2, 3, "lse", TOKEN_ELSE);
				case 'o': return checkKeyword(2, 1, "r", TOKEN_FOR);
				case 'u': return checkKeyword(2, 1, "n", TOKEN_FUN);
			}
		}
		break;
	case 'i': return checkKeyword(1, 1, "f", TOKEN_IF);
	case 'n': return checkKeyword(1, 2, "il", TOKEN_NIL);
	case 'o': return checkKeyword(1, 1, "r", TOKEN_OR);
	case 'p': return checkKeyword(1, 4, "rint", TOKEN_PRINT);
	case 'r': return checkKeyword(1, 5, "eturn", TOKEN_RETURN);
	case 's': return checkKeyword(1, 4, "uper", TOKEN_SUPER);
	case 't':
		if (scanner.current - scanner.start > 1) {
			switch (scanner.start[1]) {
			case 'h': return checkKeyword(2, 2, "is", TOKEN_THIS);
			case 'r': return checkKeyword(2, 2, "ue", TOKEN_TRUE);
			}
		}
		break;
	case 'v': return checkKeyword(1, 2, "ar", TOKEN_VAR);
	case 'w': return checkKeyword(1, 4, "hile", TOKEN_WHILE);
	}
	return TOKEN_IDENT;
}


static Token number() {
	while (isDigit(peek())) advance();
	if (peek() == '.' && isDigit(peekAhead())) {
		scanner.current++;
		while (isDigit(peek())) advance();
	}
	return makeToken(TOKEN_NUMBER);
}
static Token ident() {
	char c;
	while (isAlpha(peek()) || isDigit(peek())) advance();
	return makeToken(identType());
}

Token scanToken() {
	skipWhitespace();
	scanner.start = scanner.current;

	if (isAtEnd()) return makeToken(TOKEN_EOF);

	char c = advance();
	if (isDigit(c)) return number();
	if (isAlpha(c)) return ident();

	switch (c) {
		case '(': return makeToken(TOKEN_LEFT_PAREN);
		case ')': return makeToken(TOKEN_RIGHT_PAREN);
		case '{': return makeToken(TOKEN_LEFT_BRACE);
		case '}': return makeToken(TOKEN_RIGHT_BRACE);
		case ';': return makeToken(TOKEN_SEMICOLON);
		case ',': return makeToken(TOKEN_COMMA);
		case '.': return makeToken(TOKEN_DOT);
		case '-': return makeToken(TOKEN_MINUS);
		case '+': return makeToken(TOKEN_PLUS);
		case '/': return makeToken(TOKEN_SLASH);
		case '*': return makeToken(TOKEN_STAR);

		case '!':
			return makeToken(match('=') ? TOKEN_BANG_EQUAL : TOKEN_BANG);
		case '=':
			return makeToken(match('=') ? TOKEN_EQUAL_EQUAL : TOKEN_EQUAL);
		case '<':
			return makeToken(match('=') ? TOKEN_LESS_EQUAL : TOKEN_LESS);
		case '>':
			return makeToken(match('=') ? TOKEN_GREATER_EQUAL : TOKEN_GREATER);
	}

	return errorToken("Unexpected character");
}
