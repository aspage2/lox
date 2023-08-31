package ast

import (
	"fmt"
	"strings"
)

type aststringer struct {
	strings.Builder
}

func (s *aststringer) VisitBinary(expr *Binary) error {
	fmt.Fprintf(s, "(%s ", expr.Operator.Lexeme)
	expr.Left.Accept(s)
	s.WriteRune(' ')
	expr.Right.Accept(s)
	s.WriteRune(')')
	return nil
}

func (s *aststringer) VisitUnary(expr *Unary) error {
	fmt.Fprintf(s, "(%s ", expr.Operator.Lexeme)
	expr.Right.Accept(s)
	s.WriteRune(')')
	return nil
}

func (s *aststringer) VisitLiteral(expr *Literal) error {
	s.WriteString(fmt.Sprintf("%v", expr.Value))
	return nil
}

func (s *aststringer) VisitGrouping(expr *Grouping) error {
	s.WriteString("(group ")
	expr.Expression.Accept(s)
	s.WriteRune(')')
	return nil
}

func Pprint(expr Expr) {
	var str aststringer
	expr.Accept(&str)
	fmt.Println(str.String())
}
