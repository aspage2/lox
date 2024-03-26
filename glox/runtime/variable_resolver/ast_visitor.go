package variable_resolver

import (
	"glox/ast"
)

type FunctionType int

const (
	FUNCTIONTYPE_NONE FunctionType = iota
	FUNCTIONTYPE_FUNCTION
	FUNCTIONTYPE_METHOD
)

type ClassType int

const (
	CLASSTYPE_NONE = iota
	CLASSTYPE_CLASS
)

// ---------------- Visitor Implementation ----------------

func (r *resolver) VisitThis(expr *ast.This) error {
	if r.currentClass == CLASSTYPE_NONE {
		return expr.Keyword.MakeError("use of 'this' outside a class definition")
	}
	r.ResolveLocal(expr, expr.Keyword)
	return nil
}

func (r *resolver) VisitSet(expr *ast.Set) error {
	if err := expr.Value.Accept(r); err != nil {
		return err
	}
	if err := expr.Object.Accept(r); err != nil {
		return err
	}
	return nil
}

func (r *resolver) VisitGet(expr *ast.Get) error {
	return expr.Object.Accept(r)
}

func (r *resolver) VisitClass(stmt *ast.Class) error {
	prevClass := r.currentClass
	r.currentClass = CLASSTYPE_CLASS
	defer func() { r.currentClass = prevClass }()
	r.Declare(stmt.Name.Lexeme)
	r.Define(stmt.Name.Lexeme)

	r.BeginScope()
	defer r.EndScope()
	r.CurrentScope()["this"] = true
	for _, method := range stmt.Methods {
		if err := r.ResolveFunction(method, FUNCTIONTYPE_METHOD); err != nil {
			return err
		}
	}
	return nil
}

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
	if err := e.Value.Accept(r); err != nil {
		return err
	}
	r.ResolveLocal(e, e.Name)
	return nil
}

func (r *resolver) VisitFunction(s *ast.Function) error {
	r.Declare(s.Name.Lexeme)
	r.Define(s.Name.Lexeme)
	return r.ResolveFunction(s, FUNCTIONTYPE_FUNCTION)
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
	if r.currentFunction == FUNCTIONTYPE_NONE {
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
