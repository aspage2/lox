package parser

import (
	"glox/lexer"
)

type Parser struct {
	current int
	tokens  []lexer.Token
}

func (p *Parser) IsAtEnd() bool {
	return p.current >= len(p.tokens)-1
}

func (p *Parser) Peek() lexer.Token {
	return p.tokens[p.current]
}

func (p *Parser) Next() lexer.Token {
	ret := p.Peek()
	if !p.IsAtEnd() {
		p.current++
	}
	return ret
}

func (p *Parser) Back() {
	if p.current > 0 {
		p.current--
	}
}

func (p *Parser) TakeIfType(types ...lexer.TokenType) bool {
	n := p.Next()
	for _, typ := range types {
		if typ == n.Type {
			return true
		}
	}
	p.Back()
	return false
}
