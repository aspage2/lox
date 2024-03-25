package variable_resolver

import (
	"errors"
	"glox/ast"
	"glox/lexer"
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
	currentClass    ClassType
	scopes          []map[string]bool
	localsMap       map[ast.Expr]int
}

func newresolver() *resolver {
	return &resolver{
		currentFunction: FUNCTIONTYPE_NONE,
		currentClass:    CLASSTYPE_NONE,
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
