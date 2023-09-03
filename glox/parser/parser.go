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

func (p *Parser) MatchType(types ...lexer.TokenType) bool {
	typ := p.Peek().Type
	for _, t := range types {
		if t == typ {
			return true
		}
	}
	return false
}

func (p *Parser) TakeIfType(types ...lexer.TokenType) bool {
	if !p.MatchType(types...) {
		return false
	}
	p.Next()
	return true
}
