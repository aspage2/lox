package runtime

import (
	"fmt"
	"glox/ast"
	"glox/lexer"
	"testing"

	"github.com/stretchr/testify/assert"
)

func makeBinaryExp(l, r any, op lexer.TokenType) *ast.Binary {
	return &ast.Binary{
		Left: &ast.Literal{Value: l},
		Right: &ast.Literal{Value: r},
		Operator: lexer.Token{
			Type: op,
			Value: nil,
			Lexeme: op.String(),
			Line: 1,
		},
	}
}

func TestBinary_Numeric(t *testing.T) {
	type tokenCase struct {
		typ lexer.TokenType
		op  func(a, b float64) any
	}
	ops := []tokenCase{
		{lexer.PLUS, func(a, b float64) any { return a + b }},
		{lexer.MINUS, func(a, b float64) any { return a - b }},
		{lexer.STAR, func(a, b float64) any { return a * b }},
		{lexer.LT, func(a, b float64) any { return a < b }},
		{lexer.LTE, func(a, b float64) any { return a <= b }},
		{lexer.GT, func(a, b float64) any { return a > b }},
		{lexer.GTE, func(a, b float64) any { return a >= b }},
	}

	for l := -2; l <= 2; l++ {
		for r := -2; r <= 2; r++ {
			for _, testcase := range ops {
				t.Run(
					fmt.Sprintf("%v %s %v", l, testcase.typ.String(), r),
					func(t *testing.T) {
						lf := float64(l)
						rf := float64(r)
						expected := testcase.op(lf, rf)
						expr := makeBinaryExp(lf, rf, testcase.typ)
						// nil here because we aren't using variables
						te := NewTreeEvaluator(nil)
						assert.NoError(t, expr.Accept(te))
						assert.Equal(t, expected, te.result)
					},
				)
			}
		}
	}
}

func TestBinary_Numeric_NotNum(t *testing.T) {
	typs := []lexer.TokenType{
		lexer.MINUS,
		lexer.STAR,
		lexer.SLASH,
		lexer.LT,
		lexer.LTE,
		lexer.GT,
		lexer.GTE,
	}

	for _, typ := range typs {
		t.Run(fmt.Sprintf("%s (LEFT)", &typ), func(t *testing.T) {
			exp := makeBinaryExp("bad", 1.0, typ)
			te := NewTreeEvaluator(nil)
			assert.Error(t, exp.Accept(te))
		})
		t.Run(fmt.Sprintf("%s (RIGHT)", &typ), func(t *testing.T) {
			exp := makeBinaryExp(1.0, "bad", typ)
			te := NewTreeEvaluator(nil)
			assert.Error(t, exp.Accept(te))
		})
		t.Run(fmt.Sprintf("%s (BOTH)", &typ), func(t *testing.T) {
			exp := makeBinaryExp("bad", "bad", typ)
			te := NewTreeEvaluator(nil)
			assert.Error(t, exp.Accept(te))
		})
	}
}

func TestBinary_Slash(t *testing.T) {
	l := 3.
	r := 2.
	expected := 1.5
	expr := makeBinaryExp(l, r, lexer.SLASH)
	te := NewTreeEvaluator(nil)
	assert.NoError(t, expr.Accept(te))
	assert.Equal(t, expected, te.result)
}

func TestBinary_Slash_Div_0(t *testing.T) {
	l := 3.
	r := 0.
	expr := makeBinaryExp(l, r, lexer.SLASH)
	te := NewTreeEvaluator(nil)
	assert.Error(t, expr.Accept(te))
}
