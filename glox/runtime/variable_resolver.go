package runtime

import (
	"errors"
	"glox/ast"
	"glox/lexer"
)

type FunctionType int

const (
	None FunctionType = iota
	Function
	Method
)

type Resolver struct {
	Lox             *Lox
	currentFunction FunctionType
	scopes          []map[string]bool
}

func NewResolver(l *Lox) *Resolver {
	return &Resolver{
		Lox:             l,
		currentFunction: None,
		scopes:          make([]map[string]bool, 0),
	}
}

// ---------------- Utils ----------------
func (r *Resolver) BeginScope() {
	r.scopes = append(r.scopes, make(map[string]bool))
}

func (r *Resolver) EndScope() {
	r.scopes = r.scopes[:len(r.scopes)-1]
}

func (r *Resolver) CurrentScope() map[string]bool {
	if len(r.scopes) == 0 {
		return nil
	}
	return r.scopes[len(r.scopes)-1]
}

func (r *Resolver) Declare(name string) error {
	cs := r.CurrentScope()
	if cs == nil {
		return nil
	}
	if _, ok := cs[name]; ok {
		return errors.New("variable already declared")
	}
	cs[name] = false
	return nil
}
func (r *Resolver) Define(name string) {
	cs := r.CurrentScope()
	if cs == nil {
		return
	}
	cs[name] = true
}

func (r *Resolver) ResolveLocal(e ast.Expr, t lexer.Token) {
	for i := len(r.scopes) - 1; i >= 0; i -= 1 {
		if _, ok := r.scopes[i][t.Lexeme]; ok {
			r.Lox.Resolve(e, len(r.scopes)-1-i)
		}
	}
}

// ---------------- Visitor Implementation ----------------

func (r *Resolver) VisitBlock(stmt *ast.Block) error {
	r.BeginScope()
	defer r.EndScope()
	for _, s := range stmt.Statements {
		if err := s.Accept(r); err != nil {
			return err
		}
	}
	return nil
}

func (r *Resolver) VisitVar(stmt *ast.Var) error {
	if err := r.Declare(stmt.Name.Lexeme); err != nil {
		return stmt.Name.MakeError(err.Error())
	}
	if stmt.Initializer != nil {
		if err := stmt.Initializer.Accept(r); err != nil {
			return err
		}
	}
	r.Define(stmt.Name.Lexeme)
	return nil
}

func (r *Resolver) VisitVariable(e *ast.Variable) error {
	cs := r.CurrentScope()
	if cs != nil {
		defined, ok := cs[e.Name.Lexeme]
		if ok && !defined {
			return e.Name.MakeError("can't read local variable in its own initializer")
		}
	}
	r.ResolveLocal(e, e.Name)
	return nil
}

func (r *Resolver) VisitAssignment(e *ast.Assignment) error {
	if err := e.Value.Accept(r); e != nil {
		return err
	}
	r.ResolveLocal(e, e.Name)
	return nil
}

func (r *Resolver) VisitFunction(s *ast.Function) error {
	r.Declare(s.Name.Lexeme)
	r.Define(s.Name.Lexeme)
	return r.ResolveFunction(s, Function)
}
func (r *Resolver) ResolveFunction(s *ast.Function, typ FunctionType) error {
	enclosingFunction := r.currentFunction
	r.currentFunction = typ
	r.BeginScope()
	defer r.EndScope()
	for _, param := range s.Params {
		if err := r.Declare(param.Lexeme); err != nil {
			return param.MakeError("parameter defined twice")
		}
		r.Define(param.Lexeme)
	}
	for _, bodyStmt := range s.Body {
		if err := bodyStmt.Accept(r); err != nil {
			return err
		}
	}
	r.currentFunction = enclosingFunction
	return nil
}

func (r *Resolver) VisitWhile(s *ast.While) error {
	if err := s.Condition.Accept(r); err != nil {
		return err
	}
	return s.Do.Accept(r)
}

func (r *Resolver) VisitIf(s *ast.If) error {
	if err := s.Condition.Accept(r); err != nil {
		return err
	}
	if err := s.ThenBranch.Accept(r); err != nil {
		return err
	}
	if s.ElseBranch != nil {
		return s.ElseBranch.Accept(r)
	}
	return nil
}

func (r *Resolver) VisitBreak(s *ast.Break) error {
	return nil
}

func (r *Resolver) VisitExpression(s *ast.Expression) error {
	return s.Expression.Accept(r)
}

func (r *Resolver) VisitPrint(s *ast.Print) error {
	return s.Expression.Accept(r)
}

func (r *Resolver) VisitReturn(s *ast.Return) error {
	if r.currentFunction == None {
		return s.Token.MakeError("return outside a function or method")
	}
	if s.Expression != nil {
		return s.Expression.Accept(r)
	}
	return nil
}

func (r *Resolver) VisitBinary(e *ast.Binary) error {
	if err := e.Left.Accept(r); err != nil {
		return err
	}
	return e.Right.Accept(r)
}

func (r *Resolver) VisitCall(e *ast.Call) error {
	if err := e.Callee.Accept(r); err != nil {
		return err
	}
	for _, arg := range e.Args {
		if err := arg.Accept(r); err != nil {
			return err
		}
	}
	return nil
}

func (r *Resolver) VisitLogical(e *ast.Logical) error {
	if err := e.Left.Accept(r); err != nil {
		return err
	}
	return e.Right.Accept(r)
}

func (r *Resolver) VisitUnary(e *ast.Unary) error {
	return e.Right.Accept(r)
}

func (r *Resolver) VisitGrouping(e *ast.Grouping) error {
	return e.Expression.Accept(r)
}

func (r *Resolver) VisitLiteral(e *ast.Literal) error {
	return nil
}
