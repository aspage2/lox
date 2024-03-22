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

/*
ResolveVariables performs a pass of the syntax tree to compute which
variable declaration a VariableExpression refers to.

Returns a map from a `VariableExpression` node to an integer distance.
This distance is how many layers up the call stack you need to go
to find the value this particular dereference is "bound" to. For example:

	{
		var a = 3;
		{
			// when a is dereferenced, it needs to
			// go 2 layers up the scope stack to find its value.
			fun f(x) { return x + a ; }

			// This will print 6, since the interpreter knows
			// to check 2 scopes above for the value of `a`.
			print f(3);

			// Even if we set `a` within this scope, the variable
			// `a` within the closure still maps to the definition
			// of `a` 2 scopes above, so f(3) will still print 6.
			var a = 4;
			print f(3);
		}
	}
*/
func ResolveVariables(stmts []ast.Stmt) (map[ast.Expr]int, error) {
	r := newresolver()
	for _, stmt := range stmts {
		if err := stmt.Accept(r); err != nil {
			return nil, err
		}
	}
	return r.localsMap, nil
}

type resolver struct {
	currentFunction FunctionType
	scopes          []map[string]bool
	localsMap       map[ast.Expr]int
}

func newresolver() *resolver {
	return &resolver{
		currentFunction: None,
		scopes:          make([]map[string]bool, 0),
		localsMap:       make(map[ast.Expr]int),
	}
}

// ---------------- Utils ----------------
func (r *resolver) BeginScope() {
	r.scopes = append(r.scopes, make(map[string]bool))
}

func (r *resolver) EndScope() {
	r.scopes = r.scopes[:len(r.scopes)-1]
}

func (r *resolver) CurrentScope() map[string]bool {
	if len(r.scopes) == 0 {
		return nil
	}
	return r.scopes[len(r.scopes)-1]
}

func (r *resolver) Declare(name string) error {
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
func (r *resolver) Define(name string) {
	cs := r.CurrentScope()
	if cs == nil {
		return
	}
	cs[name] = true
}

func (r *resolver) ResolveLocal(e ast.Expr, t lexer.Token) {
	for i := len(r.scopes) - 1; i >= 0; i -= 1 {
		if _, ok := r.scopes[i][t.Lexeme]; ok {
			r.localsMap[e] = len(r.scopes) - 1 - i
		}
	}
}

// ---------------- Visitor Implementation ----------------

func (r *resolver) VisitBlock(stmt *ast.Block) error {
	r.BeginScope()
	defer r.EndScope()
	for _, s := range stmt.Statements {
		if err := s.Accept(r); err != nil {
			return err
		}
	}
	return nil
}

func (r *resolver) VisitVar(stmt *ast.Var) error {
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

func (r *resolver) VisitVariable(e *ast.Variable) error {
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

func (r *resolver) VisitAssignment(e *ast.Assignment) error {
	if err := e.Value.Accept(r); e != nil {
		return err
	}
	r.ResolveLocal(e, e.Name)
	return nil
}

func (r *resolver) VisitFunction(s *ast.Function) error {
	r.Declare(s.Name.Lexeme)
	r.Define(s.Name.Lexeme)
	return r.ResolveFunction(s, Function)
}
func (r *resolver) ResolveFunction(s *ast.Function, typ FunctionType) error {
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

func (r *resolver) VisitWhile(s *ast.While) error {
	if err := s.Condition.Accept(r); err != nil {
		return err
	}
	return s.Do.Accept(r)
}

func (r *resolver) VisitIf(s *ast.If) error {
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

func (r *resolver) VisitBreak(s *ast.Break) error {
	return nil
}

func (r *resolver) VisitExpression(s *ast.Expression) error {
	return s.Expression.Accept(r)
}

func (r *resolver) VisitPrint(s *ast.Print) error {
	return s.Expression.Accept(r)
}

func (r *resolver) VisitReturn(s *ast.Return) error {
	if r.currentFunction == None {
		return s.Token.MakeError("return outside a function or method")
	}
	if s.Expression != nil {
		return s.Expression.Accept(r)
	}
	return nil
}

func (r *resolver) VisitBinary(e *ast.Binary) error {
	if err := e.Left.Accept(r); err != nil {
		return err
	}
	return e.Right.Accept(r)
}

func (r *resolver) VisitCall(e *ast.Call) error {
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

func (r *resolver) VisitLogical(e *ast.Logical) error {
	if err := e.Left.Accept(r); err != nil {
		return err
	}
	return e.Right.Accept(r)
}

func (r *resolver) VisitUnary(e *ast.Unary) error {
	return e.Right.Accept(r)
}

func (r *resolver) VisitGrouping(e *ast.Grouping) error {
	return e.Expression.Accept(r)
}

func (r *resolver) VisitLiteral(e *ast.Literal) error {
	return nil
}
