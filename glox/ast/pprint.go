package ast

import (
	"fmt"
	"strings"
)

type aststringer struct {
	strings.Builder
}

func (s *aststringer) VisitBinary(expr *Binary) {
	fmt.Fprintf(s, "(%s ", expr.Operator.Lexeme)
	expr.Left.Accept(s)
	s.WriteRune(' ')
	expr.Right.Accept(s)
	s.WriteRune(')')
}

func (s *aststringer) VisitUnary(expr *Unary) {
	fmt.Fprintf(s, "(%s ", expr.Operator.Lexeme)
	expr.Right.Accept(s)
	s.WriteRune(')')
}

func (s *aststringer) VisitLiteral(expr *Literal) {
	s.WriteString(expr.Value.Lexeme)
}

func (s *aststringer) VisitGrouping(expr *Grouping) {
	s.WriteString("(group ")
	expr.Expression.Accept(s)
	s.WriteRune(')')
}

func Pprint(expr Expr) {
	var str aststringer
	expr.Accept(&str)
	fmt.Println(str.String())
}
