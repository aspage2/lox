package runtime

import (
	"fmt"
	"glox/errors"
	"glox/lexer"
	"glox/parser"

	"glox/runtime/variable_resolver"
)

type Lox struct {
	HadError bool
	Globals  *Environment
}

func NewLoxInterpreter() *Lox {
	globals := NewEnvironment(nil)
	DefineNativeFunctions(globals)
	return &Lox{
		Globals:  globals,
		HadError: false,
	}
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
			l.Report(se)
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
	locals, err := variable_resolver.ResolveVariables(stmts)
	if err != nil {
		l.Report(err)
		return nil, err
	}
	te := NewTreeEvaluator(l.Globals, locals)
	last, err := te.ExecuteStatementsWithEnv(stmts, te.BaseEnv)
	if err != nil {
		l.Report(err)
		return nil, err
	}
	return last, nil
}
