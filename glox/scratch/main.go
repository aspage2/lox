package main

import (
	"glox/ast"
	"glox/lexer"
)

func main() {
	e := ast.Binary{
		Left: &ast.Unary{
			Operator: lexer.Token{Type: lexer.MINUS, Lexeme: "-"},
			Right: &ast.Literal{Value: lexer.Token{Type: lexer.NUMBER, Lexeme: "123"}},
		},
		Right: &ast.Grouping{
			Expression: &ast.Literal{
				Value: lexer.Token{Type: lexer.NUMBER, Lexeme: "23.56"},
			},
		},
		Operator: lexer.Token{Type: lexer.STAR , Lexeme: "*"},
	}

	ast.Pprint(&e)
}
