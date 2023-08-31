package parser

import (
	"glox/ast"
	"glox/lexer"
)

// LeftAssociativeBinary implements a grammar rule of the form
// rule -> f ( ( types ) f)*
// where {t0, t1, ...} <- types
func LeftAssociativeBinary(p *RecursiveDescent, f func() (ast.Expr, error), types ...lexer.TokenType) (ast.Expr, error) {
	e, err := f()
	if err != nil {
		return nil, err
	}
	for p.TakeIfType(types...) {
		p.Back()
		op := p.Next()
		re, err := f()
		if err != nil {
			return nil, err
		}
		e = &ast.Binary{
			Left:     e,
			Operator: op,
			Right:    re,
		}
	}
	return e, nil
}
