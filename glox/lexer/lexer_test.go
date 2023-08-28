package lexer

import (
	"testing"
	"unicode/utf8"

	"github.com/stretchr/testify/assert"
)

func TestLexer_NewLexer(t *testing.T) {
	l := NewLexer("Hello")
	assert.Equal(t, 0, l.current)
	assert.Equal(t, 0, l.lexemeStart)
	assert.Equal(t, 1, l.line)
}

func TestLexer_Next(t *testing.T) {
	l := NewLexer("hello, world")

	assert.Equal(t, 'h', l.Next())
	assert.Equal(t, 'e', l.Next())
	assert.Equal(t, 'l', l.Next())

	assert.Equal(t, 3, l.current)
	assert.Equal(t, 0, l.lexemeStart)
}

func TestLexer_Next_Unicode(t *testing.T) {
	l := NewLexer("доброе утро")

	assert.Equal(t, 'д', l.Next())
	assert.Equal(t, 'о', l.Next())

	assert.Equal(t, 4, l.current)
	assert.Equal(t, 0, l.lexemeStart)
}

func TestLexer_Next_AtEnd(t *testing.T) {
	l := NewLexer("A")
	l.Next()
	c := l.current
	assert.Equal(t, utf8.RuneError, l.Next())
	assert.Equal(t, c, l.current)
}

func TestLexer_Peek_AtEnd(t *testing.T) {
	l := NewLexer("A")
	l.Next()
	assert.Equal(t, utf8.RuneError, l.Peek())
}

func TestLexer_Peek(t *testing.T) {
	l := NewLexer("доброе утро")

	l.Next()
	l.Next()
	l.Next()

	peek1 := l.Peek()
	current1 := l.current
	peek2 := l.Peek()
	current2 := l.current

	assert.Equal(t, 'р', peek1)
	assert.Equal(t, 'р', peek2)
	assert.Equal(t, 6, current1)
	assert.Equal(t, 6, current2)
}

func TestLexer_Back(t *testing.T) {
	l := NewLexer("test")

	l.Next()
	l.Next()
	l.Back()
	assert.Equal(t, 1, l.current)
	assert.Equal(t, 0, l.lexemeStart)
	assert.Equal(t, 1, l.line)
	assert.Equal(t, 'e', l.Peek())
}

func TestLexer_Emit(t *testing.T) {
	l := NewLexer("hello")

	l.Next()
	l.Next()
	l.Next()

	l.Emit(STRING)
	assert.Equal(t, 1, len(l.tokens))
	tok := l.tokens[0]
	assert.Equal(t, STRING, tok.Type)
	assert.Equal(t, 1, tok.Line)
	assert.Equal(t, "hel", tok.Lexeme)

	assert.Equal(t, 3, l.current)
	assert.Equal(t, 3, l.lexemeStart)
}

func TestLexer_Lexeme(t *testing.T) {
	l := NewLexer("доброе утро")
	for i := 0; i < 6; i++ {
		l.Next()
	}
	assert.Equal(t, "доброе", l.Lexeme())
}

func TestLexer_IsAtEnd(t *testing.T) {
	l := NewLexer("H")
	assert.False(t, l.IsAtEnd())
	l.Next()
	assert.True(t, l.IsAtEnd())
}

func TestLexer_HasMoreTokens(t *testing.T) {
	l := NewLexer("Hi")
	assert.True(t, l.HasMoreTokens())
	l.Next()
	assert.True(t, l.HasMoreTokens())
	l.Discard()
	assert.True(t, l.HasMoreTokens())
	l.Next()
	l.Discard()
	assert.False(t, l.HasMoreTokens())
}

func TestLexer_Discard(t *testing.T) {
	l := NewLexer("доброе утро")
	l.Next()
	l.Next()
	l.Next()
	l.Discard()
	assert.Equal(t, 6, l.current)
	assert.Equal(t, 6, l.lexemeStart)
}
