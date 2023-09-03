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
	for p.MatchType(types...) {
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

// LeftAssociativeLogical implements a grammar rule of the form
// rule -> f ( ( types ) f)*
// where {t0, t1, ...} <- types
func LeftAssociativeLogical(p *RecursiveDescent, f func() (ast.Expr, error), types ...lexer.TokenType) (ast.Expr, error) {
	e, err := f()
	if err != nil {
		return nil, err
	}
	for p.MatchType(types...) {
		op := p.Next()
		re, err := f()
		if err != nil {
			return nil, err
		}
		e = &ast.Logical{
			Left:     e,
			Operator: op,
			Right:    re,
		}
	}
	return e, nil
}
