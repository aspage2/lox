package ast

import (
	"glox/lexer"
)

type Visitor interface {
	VisitBinary(*Binary)
	VisitUnary(*Unary)
	VisitGrouping(*Grouping)
	VisitLiteral(*Literal)
}

type Expr interface {
	Accept(Visitor)
}
type Unary struct {
	Operator lexer.Token
	Right    Expr
}

func (n *Unary) Accept(v Visitor) {
	v.VisitUnary(n)
}

type Grouping struct {
	Expression Expr
}

func (n *Grouping) Accept(v Visitor) {
	v.VisitGrouping(n)
}

type Literal struct {
	Value lexer.Token
}

func (n *Literal) Accept(v Visitor) {
	v.VisitLiteral(n)
}

type Binary struct {
	Left     Expr
	Operator lexer.Token
	Right    Expr
}

func (n *Binary) Accept(v Visitor) {
	v.VisitBinary(n)
}
