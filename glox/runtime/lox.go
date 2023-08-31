package runtime

import (
	"fmt"
	"glox/ast"
	"glox/errors"
	"glox/lexer"
	"glox/parser"
)

type Lox struct {
	HadError bool
	Env Environment
}

func (l *Lox) Report(err error) {
	fmt.Println(err.Error())
	l.HadError = true
}

func (l *Lox) Run(line string) error {
	tokens, err := lexer.ScanSource(line)
	if err != nil {
		switch err.(type) {
		case *lexer.ScanError:
			se := err.(*lexer.ScanError)
			return &errors.LoxError{LineNumber: se.Line, Message: se.Message}
		default:
			return err
		}
	}

	stmts, err := parser.Parse(tokens)
	if err != nil {
		l.Report(err)
		return err
	}
	if err := l.ExecuteStatements(stmts); err != nil {
		l.Report(err)
		return err
	}
	return nil
}

func (l *Lox) ExecuteStatements(stmts []ast.Stmt) error {
	for _, s := range stmts {
		if _, err := Evaluate(s, l.Env); err != nil {
			return err
		}
	}
	return nil
}
