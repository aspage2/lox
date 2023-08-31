package lexer

import (
	"strings"
	"unicode/utf8"
)

type Lexer struct {
	source string
	tokens []Token

	// index of the start of current lexeme
	lexemeStart int
	// width of last character
	lastWidth int
	// current index
	current int
	// line number
	line int
}

func NewLexer(source string) *Lexer {
	return &Lexer{
		source: source,
		line:   1,
	}
}

func (l *Lexer) Next() rune {
	if l.IsAtEnd() {
		return utf8.RuneError
	}
	r, size := utf8.DecodeRuneInString(l.source[l.current:])
	if r == utf8.RuneError {
		return r
	}
	l.lastWidth = size
	l.current += size
	if r == '\n' {
		l.line += 1
	}

	return r
}

func (l *Lexer) Back() {
	if l.lastWidth == 0 {
		return
	}
	l.current -= l.lastWidth
	r, _ := utf8.DecodeRuneInString(l.source[l.current:])
	if r == '\n' {
		l.line -= 1
	}
	l.lastWidth = 0
}

func (l *Lexer) Peek() rune {
	if l.IsAtEnd() {
		return utf8.RuneError
	}
	r, _ := utf8.DecodeRuneInString(l.source[l.current:])
	return r
}

func (l *Lexer) Emit(typ TokenType, literal any) {
	var sb strings.Builder
	sb.WriteString(l.source[l.lexemeStart:l.current])
	res := sb.String()
	t := Token{
		Type:   typ,
		Line:   l.line,
		Lexeme: res,
		Value:  literal,
	}
	l.tokens = append(l.tokens, t)
	l.Discard()
}

func (l *Lexer) Discard() {
	l.lexemeStart = l.current
	l.lastWidth = 0
}

func (l *Lexer) IsAtEnd() bool {
	return len(l.source) <= l.current
}

func (l *Lexer) HasMoreTokens() bool {
	return len(l.source) > l.lexemeStart
}

func (l *Lexer) Lexeme() string {
	return l.source[l.lexemeStart:l.current]
}
