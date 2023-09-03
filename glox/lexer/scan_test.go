package lexer

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func assertScansTypes(t *testing.T, exp []TokenType, program string) {
	toks, err := ScanSource(program)
	assert.NoError(t, err)
	assertHasTypes(t, exp, toks)
}

func assertHasTypes(t *testing.T, exp []TokenType, actual []Token) {
	typs := make([]TokenType, len(actual))
	for i, typ := range actual {
		typs[i] = typ.Type
	}
	assert.Equal(t, exp, typs)
}

func TestScan_BinaryOp(t *testing.T) {
	tests := map[string]TokenType{
		">":   GT,
		">=":  GTE,
		"<":   LT,
		"<=":  LTE,
		"==":  DOUBLE_EQUAL,
		"!=":  BANG_EQUAL,
		"and": AND,
		"or":  OR,
		"+":   PLUS,
		"-":   MINUS,
		"*":   STAR,
		"/":   SLASH,
	}

	for op, typ := range tests {
		t.Run(op, func(t *testing.T) {
			expression := fmt.Sprintf("a %s b", op)
			toks, err := ScanSource(expression)
			assert.NoError(t, err)
			assertHasTypes(t, []TokenType{IDENT, typ, IDENT, EOF}, toks)
		})
	}
}

func TestScan_Comment(t *testing.T) {
	program := "// this is a comment\nprint a / b;"
	assertScansTypes(t, []TokenType{
		PRINT, IDENT, SLASH, IDENT, SEMICOLON, EOF,
	}, program)
}

func TestScan_BlockComment(t *testing.T) {
	program := "/* Block comment.\n/* inner block comment. */\ngood job. */ a + b"
	assertScansTypes(t, []TokenType{
		IDENT, PLUS, IDENT, EOF,
	}, program)
}

func TestScan_BlockComment_Error(t *testing.T) {
	program := "/* nah /* man */ foobar"
	_, err := ScanSource(program)
	assert.Error(t, err)
	assert.IsType(t, &ScanError{}, err)
}

func TestDiscardWhitespace(t *testing.T) {
	l := NewLexer("\n\t \t\n+")
	DiscardWhitespace(l)
	assert.Equal(t, 5, l.current)
	assert.Equal(t, 3, l.currentLine)
}

func TestStringLiteral(t *testing.T) {
	assertScansTypes(
		t,
		[]TokenType{STRING, PLUS, STRING, EOF},
		"\"Hello\n\tWorld!\" + \"How are you????\"",
	)
}
