package lexer

import (
	"fmt"
	"strconv"
	"unicode"
)

type ScanError struct {
	Line    int
	Message string
}

func (s *ScanError) Error() string {
	return fmt.Sprintf("scan error: line %d: %s", s.Line, s.Message)
}

func NewScanError(line int, msg string) *ScanError {
	return &ScanError{
		Line:    line,
		Message: msg,
	}
}

func ScanSource(source string) ([]Token, error) {
	l := NewLexer(source)
	emitTernary := func(r rune, ifTrue TokenType, ifFalse TokenType) {
		if l.Next() == r {
			l.Emit(ifTrue, nil)
		} else {
			l.Back()
			l.Emit(ifFalse, nil)
		}
	}

	for l.HasMoreTokens() {
		r := l.Next()

		// -- non-significant whitespace --
		if r == ' ' || r == '\t' || r == '\n' {
			DiscardWhitespace(l)
			continue
		}

		// -- Single Characters --
		if typ := matchSingleChar(r); typ != NOT_INITIALIZED {
			l.Emit(typ, nil)
			continue
		}

		// -- One or two character tokens --
		switch r {
		case '!':
			emitTernary('=', BANG_EQUAL, BANG)
			continue
		case '=':
			emitTernary('=', DOUBLE_EQUAL, EQUAL)
			continue
		case '<':
			emitTernary('=', LTE, LT)
			continue
		case '>':
			emitTernary('=', GTE, GT)
			continue
		}

		// String literal
		if r == '"' {
			l.Discard()
			if err := StringLiteral(l); err != nil {
				return nil, err
			}
			continue
		}

		// Numeric literal
		if unicode.IsDigit(r) {
			for (unicode.IsDigit(l.Peek()) || l.Peek() == '.') && !l.IsAtEnd() {
				l.Next()
			}
			if unicode.IsLetter(l.Peek()) {
				return nil, NewScanError(l.currentLine, "numbers must be separated from letters by whitespace")
			}
			v, _ := strconv.ParseFloat(l.Lexeme(), 64)
			l.Emit(NUMBER, v)
			continue
		}

		// Idents
		if unicode.IsLetter(r) {
			r2 := l.Peek()
			for unicode.IsDigit(r2) || unicode.IsLetter(r2) && !l.IsAtEnd() {
				l.Next()
				r2 = l.Peek()
			}
			if typ := matchKeyword(l.Lexeme()); typ != NOT_INITIALIZED {
				l.Emit(typ, nil)
			} else {
				l.Emit(IDENT, nil)
			}
			continue
		}

		// Comment (or divide symbol)
		if r == '/' {
			// One-line comment
			if l.Peek() == '/' {
				for l.Peek() != '\n' && !l.IsAtEnd() {
					l.Next()
				}
				l.Discard()
			} else if l.Peek() == '*' {
				l.Next()
				if err := BlockComment(l); err != nil {
					return nil, err
				}
			} else {
				l.Emit(SLASH, nil)
			}
			continue
		}

		return nil, NewScanError(l.currentLine, fmt.Sprintf("unexpected character: %c", r))
	}
	l.Emit(EOF, nil)
	return l.tokens, nil
}

func DiscardWhitespace(l *Lexer) {
	isspace := func(r rune) bool {
		return r == ' ' || r == '\n' || r == '\t'
	}
	for isspace(l.Peek()) {
		l.Next()
	}
	l.Discard()
}

func StringLiteral(l *Lexer) error {
	for l.Peek() != '"' && !l.IsAtEnd() {
		l.Next()
	}
	if l.IsAtEnd() {
		return NewScanError(l.currentLine, "unterminated string")
	}
	l.Emit(STRING, l.Lexeme())

	// Dump the ending double-quote
	l.Next()
	l.Discard()
	return nil
}

func BlockComment(l *Lexer) error {
	nestLevel := 1
	for nestLevel > 0 && !l.IsAtEnd() {
		c := l.Next()
		// End a block
		if c == '*' && l.Peek() == '/' {
			nestLevel--
			l.Next()
		} else if c == '/' && l.Peek() == '*' {
			nestLevel++
			l.Next()
		}
	}
	if nestLevel > 0 {
		return NewScanError(l.currentLine, "unterminated block comment")
	}
	l.Discard()
	return nil
}
