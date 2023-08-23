package runtime

import (
	"fmt"
	"glox/lexer"
)

type Lox struct {
}

type LoxError struct {
	LineNumber int
	File       string
	Message    string
}

func (le *LoxError) Report() {
	fmt.Printf("Error: Line %d: %s\n", le.LineNumber, le.Message)
}

func (l *Lox) Run(line string) *LoxError {
	tokens, err := lexer.ScanSource(line)
	if err != nil {
		switch err.(type) {
		case *lexer.ScanError:
			se := err.(*lexer.ScanError)
			return &LoxError{LineNumber: se.Line, File: "???", Message: se.Message}
		default:
			panic(err)
		}
	}
	for _, token := range tokens {
		fmt.Println(token.String())
	}
	return nil
}
