package runtime

import (
	"fmt"
	"glox/ast"
	"glox/lexer"
	"testing"

	"github.com/stretchr/testify/assert"
)

// -------------------------------------
//
//	BINARY ARITHMETIC EXPRESSIONS
//
// -------------------------------------
func assertBinaryExprEvaluates(t *testing.T, l, r any, op lexer.TokenType, exp any) {
	te := NewTreeEvaluator(nil, nil)
	expr := makeBinaryExp(l, r, op)
	assert.NoError(t, expr.Accept(te))
	assert.Equal(t, exp, te.result)
}

func assertBinaryExprErrs(t *testing.T, l, r any, op lexer.TokenType) {
	te := NewTreeEvaluator(nil, nil)
	expr := makeBinaryExp(l, r, op)
	assert.Error(t, expr.Accept(te))
}

func makeBinaryExp(l, r any, op lexer.TokenType) *ast.Binary {
	return &ast.Binary{
		Left:  &ast.Literal{Value: l},
		Right: &ast.Literal{Value: r},
		Operator: lexer.Token{
			Type:   op,
			Value:  nil,
			Lexeme: op.String(),
			Line:   1,
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

	// Test all triplets in [-2, 2] x [-2, 2] x ops
	// 25 * len(ops) tests.
	for l := -2; l <= 2; l++ {
		for r := -2; r <= 2; r++ {
			for _, testcase := range ops {
				t.Run(
					fmt.Sprintf("%v %s %v", l, testcase.typ.String(), r),
					func(t *testing.T) {
						lf := float64(l)
						rf := float64(r)
						expected := testcase.op(lf, rf)
						assertBinaryExprEvaluates(t, lf, rf, testcase.typ, expected)
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
			assertBinaryExprErrs(t, "bad", 1.0, typ)
		})
		t.Run(fmt.Sprintf("%s (RIGHT)", &typ), func(t *testing.T) {
			assertBinaryExprErrs(t, 1.0, "bad", typ)
		})
		t.Run(fmt.Sprintf("%s (BOTH)", &typ), func(t *testing.T) {
			assertBinaryExprErrs(t, "bad", "bad", typ)
		})
	}
}

func TestBinary_Slash(t *testing.T) {
	assertBinaryExprEvaluates(t, 3., 2., lexer.SLASH, 1.5)
}

func TestBinary_Slash_Div_0(t *testing.T) {
	assertBinaryExprErrs(t, 3., 0., lexer.SLASH)
}

func TestBinary_StrConcat(t *testing.T) {
	assertBinaryExprEvaluates(t, "hello", "world", lexer.PLUS, "helloworld")
}

func TestBinary_StrConcat_Error(t *testing.T) {
	t.Run("left", func(t *testing.T) {
		assertBinaryExprErrs(t, "hello", 3.0, lexer.PLUS)
	})
	t.Run("right", func(t *testing.T) {
		assertBinaryExprErrs(t, 3.0, "hello", lexer.PLUS)
	})
}

func TestBinary_Plus_NonAlphaNum(t *testing.T) {
	t.Run("left", func(t *testing.T) {
		assertBinaryExprErrs(t, true, 3.0, lexer.PLUS)
	})
	t.Run("right", func(t *testing.T) {
		assertBinaryExprErrs(t, 3.0, true, lexer.PLUS)
	})
}

func TestTruthy(t *testing.T) {
	cases := []struct {
		Arg any
		Exp bool
	}{
		{"", false},
		{"a", true},
		{0, false},
		{1, true},
		{nil, false},
		{true, true},
		{false, false},
	}

	for _, _case := range cases {
		t.Run(fmt.Sprint(_case), func(t *testing.T) {
			v := truthy(_case.Arg)
			assert.Equal(t, _case.Exp, v)
		})
	}
}

// -------------------------------------
//  BINARY LOGICAL EXPRESSIONS
// -------------------------------------

// -------------------------------------
//
//	UNARY EXPRESSIONS
//
// -------------------------------------
func assertUnaryExprEvaluates(t *testing.T, v any, op lexer.TokenType, exp any) {
	expr := &ast.Unary{
		Right: &ast.Literal{Value: v},
		Operator: lexer.Token{
			Type: op,
		},
	}
	te := NewTreeEvaluator(nil, nil)
	assert.NoError(t, expr.Accept(te))
	assert.Equal(t, exp, te.result)
}

func assertUnaryExprErrs(t *testing.T, v any, op lexer.TokenType) {
	expr := &ast.Unary{
		Right: &ast.Literal{Value: v},
		Operator: lexer.Token{
			Type: op,
		},
	}
	te := NewTreeEvaluator(nil, nil)
	assert.Error(t, expr.Accept(te))

}

func TestUnary(t *testing.T) {
	testCases := []struct {
		Operand any
		Op      lexer.TokenType
		Exp     any
	}{
		{true, lexer.BANG, false},
		{false, lexer.BANG, true},
		{"", lexer.BANG, true},
		{"a", lexer.BANG, false},
		{1., lexer.MINUS, -1.},
		{0., lexer.MINUS, 0.},
	}
	for _, c := range testCases {
		assertUnaryExprEvaluates(t, c.Operand, c.Op, c.Exp)
	}
}

// -------------------------------------
//  VARIABLE EXPRESSIONS
// -------------------------------------

func TestVariable(t *testing.T) {
	env := NewEnvironment(nil)
	env.Declare("x", 33)
	v := &ast.Variable{
		Name: lexer.Token{
			Type:   lexer.IDENT,
			Lexeme: "x",
		},
	}
	te := NewTreeEvaluator(env, nil)
	assert.NoError(t, v.Accept(te))
	assert.Equal(t, 33, te.result)
}

func TestVariable_Err(t *testing.T) {
	env := NewEnvironment(nil)
	v := &ast.Variable{
		Name: lexer.Token{
			Type:   lexer.IDENT,
			Lexeme: "x",
		},
	}
	te := NewTreeEvaluator(env, nil)
	assert.Error(t, v.Accept(te))

}

func TestLiteral(t *testing.T) {
	te := NewTreeEvaluator(nil, nil)
	exp := &ast.Literal{Value: 3}
	assert.NoError(t, exp.Accept(te))
	assert.Equal(t, 3, te.result)
}
