package parser

import (
	"glox/ast"
	"glox/lexer"
)

// RecursiveDescent wraps the core Parser object, adding the functions that
// implement Lox's grammar rules.
type RecursiveDescent struct {
	Parser
}

// Parse converts a sequence of tokens into a syntax tree.
// Returns the AST or any parse error that was encountered.
// basically the grammar start rule, [program -> declaration* EOF ;]
func Parse(tokens []lexer.Token) ([]ast.Stmt, error) {
	tree := &RecursiveDescent{Parser: Parser{tokens: tokens}}
	var ret []ast.Stmt
	for !tree.IsAtEnd() {
		s, err := tree.Declaration()
		if err != nil {
			return nil, err
		}
		ret = append(ret, s)
	}
	return ret, nil
}

// declaration -> varDecl | statement ;
func (p *RecursiveDescent) Declaration() (ast.Stmt, error) {
	var f func() (ast.Stmt, error)
	if p.TakeIfType(lexer.VAR) {
		f = p.VarDeclaration
	} else {
		f = p.Statement
	}
	s, err := f()
	if err != nil {
		p.synchronize()
		return nil, err
	}
	return s, nil
}

// varDecl -> "var" IDENTIFIER ("=" expression)? ";" ;
// *note that "var" was consumed by the calling function, Declaration
func (p *RecursiveDescent) VarDeclaration() (ast.Stmt, error) {
	id := p.Next()
	if id.Type != lexer.IDENT {
		return nil, id.MakeError("expect a variable name.")
	}

	var (
		initializer ast.Expr
		err         error
	)
	if p.TakeIfType(lexer.EQUAL) {
		initializer, err = p.Expression()
		if err != nil {
			return nil, err
		}
	}
	if tok := p.Next(); tok.Type != lexer.SEMICOLON {
		return nil, tok.MakeError("expect ';' after variable declaration")
	}
	return &ast.Var{Name: id, Initializer: initializer}, nil
}

// statement -> printStmt | block | ifStmt | exprStmt ;
func (p *RecursiveDescent) Statement() (ast.Stmt, error) {
	if p.TakeIfType(lexer.PRINT) {
		return p.PrintStatement()
	}
	if p.TakeIfType(lexer.LEFT_BRACE) {
		return p.BlockStatement()
	}
	if p.TakeIfType(lexer.IF) {
		return p.IfStatement()
	}
	if p.TakeIfType(lexer.WHILE) {
		return p.WhileStatement()
	}
	return p.ExpressionStatement()
}

// block -> "{" declaration* "}" ;
func (p *RecursiveDescent) BlockStatement() (ast.Stmt, error) {
	var ret []ast.Stmt

	for !p.MatchType(lexer.RIGHT_BRACE) && !p.IsAtEnd() {
		d, err := p.Declaration()
		if err != nil {
			return nil, err
		}
		ret = append(ret, d)
	}
	if !p.MatchType(lexer.RIGHT_BRACE) {
		return nil, p.Peek().MakeError("expect closing '}'")
	}
	p.Next()
	return &ast.Block{Statements: ret}, nil
}

// ifStmt -> "if" "(" expression ")" statement ("else" statement)? ;
func (p *RecursiveDescent) IfStatement() (ast.Stmt, error) {
	if !p.TakeIfType(lexer.LEFT_PAREN) {
		return nil, p.Peek().MakeError("expect '(' after 'if'")
	}
	condition, err := p.Expression()
	if err != nil {
		return nil, err
	}
	if !p.TakeIfType(lexer.RIGHT_PAREN) {
		return nil, p.Peek().MakeError("expect closing ')' in 'if' statement")
	}
	then, err := p.Statement()
	if err != nil {
		return nil, err
	}
	var (
		elseStmt ast.Stmt
	)
	if p.TakeIfType(lexer.ELSE) {
		elseStmt, err = p.Statement()
		if err != nil {
			return nil, err
		}
	}
	return &ast.If{
		Condition:  condition,
		ThenBranch: then,
		ElseBranch: elseStmt,
	}, nil
}

func (p *RecursiveDescent) WhileStatement() (ast.Stmt, error) {
	if !p.TakeIfType(lexer.LEFT_PAREN) {
		return nil, p.Peek().MakeError("expect '(' after 'while'")
	}
	condition, err := p.Expression()
	if err != nil {
		return nil, err
	}
	if !p.TakeIfType(lexer.RIGHT_PAREN) {
		return nil, p.Peek().MakeError("expect closing ')' in 'while' statement")
	}
	doBlock, err := p.Statement()
	if err != nil {
		return nil, err
	}
	return &ast.While{
		Condition: condition,
		Do:        doBlock,
	}, nil
}

// PrintStatement -> "print" expression ";"
func (p *RecursiveDescent) PrintStatement() (ast.Stmt, error) {
	val, err := p.Expression()
	if err != nil {
		return nil, err
	}
	if tok := p.Next(); tok.Type != lexer.SEMICOLON {
		return nil, tok.MakeError("expect ';' after value")
	}
	return &ast.Print{Expression: val}, nil
}

// exprStmt -> expression ";" ;
func (p *RecursiveDescent) ExpressionStatement() (ast.Stmt, error) {
	val, err := p.Expression()
	if err != nil {
		return nil, err
	}
	if tok := p.Next(); tok.Type != lexer.SEMICOLON && tok.Type != lexer.EOF {
		return nil, tok.MakeError("expect ';' after value")
	}
	return &ast.Expression{Expression: val}, nil
}

// expression -> equality ;
func (p *RecursiveDescent) Expression() (ast.Expr, error) {
	return p.Assignment()
}

func (p *RecursiveDescent) Assignment() (ast.Expr, error) {
	expr, err := p.Or()
	if err != nil {
		return nil, err
	}
	if p.TakeIfType(lexer.EQUAL) {
		p.Back()
		eq := p.Next()
		value, err := p.Assignment()
		if err != nil {
			return nil, err
		}
		if v, ok := expr.(*ast.Variable); ok {
			return &ast.Assignment{Name: v.Name, Value: value}, nil
		}
		return nil, eq.MakeError("Invalid assignment target")
	}
	return expr, nil
}

// logic_or -> logic_and ("or" logic_and)* ;
func (p *RecursiveDescent) Or() (ast.Expr, error) {
	return LeftAssociativeLogical(p, p.And, lexer.OR)
}

func (p *RecursiveDescent) And() (ast.Expr, error) {
	return LeftAssociativeLogical(p, p.Equality, lexer.AND)
}

// equality -> comparison ( ( "==" | "!=" ) comparison )*
func (p *RecursiveDescent) Equality() (ast.Expr, error) {
	return LeftAssociativeBinary(p, p.Comparison, lexer.DOUBLE_EQUAL, lexer.BANG_EQUAL)
}

// comparison -> term ( ( ">" | "<" | ">=" | "<=" ) term )* ;
func (p *RecursiveDescent) Comparison() (ast.Expr, error) {
	return LeftAssociativeBinary(p, p.Term, lexer.LTE, lexer.LT, lexer.GTE, lexer.GT)
}

// term -> factor ( ( "-" | "+" ) factor )*
func (p *RecursiveDescent) Term() (ast.Expr, error) {
	return LeftAssociativeBinary(p, p.Factor, lexer.MINUS, lexer.PLUS)
}

// factor -> unary ( ( "/" | "*" ) unary )* ;
func (p *RecursiveDescent) Factor() (ast.Expr, error) {
	return LeftAssociativeBinary(p, p.Unary, lexer.SLASH, lexer.STAR)
}

// unary -> ("!" | "-") unary | primary ;
func (p *RecursiveDescent) Unary() (ast.Expr, error) {
	if p.TakeIfType(lexer.BANG, lexer.MINUS) {
		p.Back()
		op := p.Next()
		re, err := p.Unary()
		if err != nil {
			return nil, err
		}
		return &ast.Unary{
			Operator: op,
			Right:    re,
		}, nil
	}
	return p.Primary()
}

// primary -> "true" | "false" | "nil" | NUMBER | STRING | "(" expression ")" | IDENT ;
func (p *RecursiveDescent) Primary() (ast.Expr, error) {
	if p.TakeIfType(lexer.FALSE) {
		return &ast.Literal{Value: false}, nil
	}
	if p.TakeIfType(lexer.TRUE) {
		return &ast.Literal{Value: true}, nil
	}
	if p.TakeIfType(lexer.NIL) {
		return &ast.Literal{Value: nil}, nil
	}
	if p.TakeIfType(lexer.NUMBER, lexer.STRING) {
		p.Back()
		return &ast.Literal{Value: p.Next().Value}, nil
	}

	if p.TakeIfType(lexer.LEFT_PAREN) {
		e, err := p.Expression()
		if err != nil {
			return nil, err
		}
		if p.Next().Type != lexer.RIGHT_PAREN {
			return nil, p.Peek().MakeError("expected ending ')'.")
		}
		return &ast.Grouping{Expression: e}, nil
	}

	if p.TakeIfType(lexer.IDENT) {
		p.Back()
		return &ast.Variable{Name: p.Next()}, nil
	}

	return nil, p.Peek().MakeError("unexpected token.")
}

// When a parser encounters an error while parsing a statement,
// it can call synchronize to discard tokens until it reaches the start of
// a new statement.
func (p *RecursiveDescent) synchronize() {
	var prevType lexer.TokenType
	prevType = p.Next().Type
	for !p.IsAtEnd() {
		if prevType == lexer.SEMICOLON {
			return
		}
		switch p.Peek().Type {
		case lexer.CLASS, lexer.FUN, lexer.VAR, lexer.FOR, lexer.IF, lexer.WHILE, lexer.PRINT, lexer.RETURN:
			return
		}
		prevType = p.Next().Type
	}
}
