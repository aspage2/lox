package lexer

import (
	"fmt"
	"glox/errors"
)

// Enum for all possible token types in the Lox grammar
type TokenType uint64

const (
	// One character tokens
	NOT_INITIALIZED TokenType = iota

	LEFT_PAREN  // (
	RIGHT_PAREN // )
	LEFT_BRACE  // {
	RIGHT_BRACE // }
	COMMA       // ,
	DOT         // .
	MINUS       // -
	PLUS        // +
	SEMICOLON   // ;
	SLASH       // /
	STAR        // *

	// One or two character tokens
	BANG         // !
	BANG_EQUAL   // !=
	EQUAL        // =
	DOUBLE_EQUAL // ==
	GT           // >
	GTE          // >=
	LT           // <
	LTE          // <=

	// Literals
	IDENT  // generic identities
	STRING // "hello, world"
	NUMBER // 1, 2, 3.333

	// Keywords
	AND
	CLASS
	ELSE
	FALSE
	FUN
	FOR
	IF
	NIL
	OR
	PRINT
	RETURN
	SUPER
	THIS
	TRUE
	VAR
	WHILE

	EOF
)

func matchSingleChar(r rune) TokenType {
	switch r {
	// -- Single Character --
	case '(':
		return LEFT_PAREN
	case ')':
		return RIGHT_PAREN
	case '{':
		return LEFT_BRACE
	case '}':
		return RIGHT_BRACE
	case '+':
		return PLUS
	case '-':
		return MINUS
	case '*':
		return STAR
	case ',':
		return COMMA
	case ';':
		return SEMICOLON
	case '.':
		return DOT
	default:
		return NOT_INITIALIZED
	}
}

func matchKeyword(s string) TokenType {
	switch s {
	case "and":
		return AND
	case "class":
		return CLASS
	case "else":
		return ELSE
	case "false":
		return FALSE
	case "fun":
		return FUN
	case "for":
		return FOR
	case "if":
		return IF
	case "nil":
		return NIL
	case "or":
		return OR
	case "print":
		return PRINT
	case "return":
		return RETURN
	case "super":
		return SUPER
	case "this":
		return THIS
	case "true":
		return TRUE
	case "var":
		return VAR
	case "while":
		return WHILE
	}
	return NOT_INITIALIZED
}

type Token struct {
	Type   TokenType
	Lexeme string
	Line   int
	Value  any
}

func (t Token) String() string {
	return fmt.Sprintf("%s %s", t.Type, t.Lexeme)
}

func (t Token) MakeError(msg string) error {
	return errors.NewLoxError(t.Line, t.Lexeme, msg)
}
