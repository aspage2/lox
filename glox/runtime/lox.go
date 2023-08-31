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
	Env      Environment
	AcceptRawExpressions bool
}

func (l *Lox) Report(err error) {
	fmt.Println(err.Error())
	l.HadError = true
}

func (l *Lox) Run(line string) (any, error) {
	tokens, err := lexer.ScanSource(line)
	if err != nil {
		switch err.(type) {
		case *lexer.ScanError:
			se := err.(*lexer.ScanError)
			return nil, &errors.LoxError{LineNumber: se.Line, Message: se.Message}
		default:
			return nil, err
		}
	}

	stmts, err := parser.Parse(tokens)
	if err != nil {
		l.Report(err)
		return nil, err
	}
	last, err := l.ExecuteStatements(stmts)
	if err != nil {
		l.Report(err)
		return nil, err
	}
	return last, nil
}

func (l *Lox) ExecuteStatements(stmts []ast.Stmt) (any, error) {
	var last any
	for _, s := range stmts {
		if v, err := Evaluate(s, l.Env); err != nil {
			return nil, err
		} else {
			last = v
		}
	}
	return last, nil
}
