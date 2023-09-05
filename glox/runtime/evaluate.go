package runtime

import (
	"fmt"
	"glox/ast"
	"glox/lexer"
)

type TreeEvaluator struct {
	env    Environment
	result any
}

func Evaluate(expr ast.Stmt, env Environment) (any, error) {
	te := &TreeEvaluator{env: env}
	err := expr.Accept(te)
	if err != nil {
		return nil, err
	}
	return te.result, nil
}

func (te *TreeEvaluator) VisitAssignment(exp *ast.Assignment) error {
	if err := exp.Value.Accept(te); err != nil {
		return err
	}
	if !te.env.Assign(exp.Name.Lexeme, te.result) {
		return exp.Name.MakeError("undefined variable")
	}
	return nil
}

func (te *TreeEvaluator) VisitLogical(exp *ast.Logical) error {
	if err := exp.Left.Accept(te); err != nil {
		return err
	}
	leftTruthy := truthy(te.result)
	switch exp.Operator.Type {
	case lexer.OR:
		if leftTruthy {
			te.result = true
			return nil
		}
	case lexer.AND:
		if !leftTruthy {
			te.result = false
			return nil
		}
	}

	return exp.Right.Accept(te)
}

func (te *TreeEvaluator) VisitBinary(exp *ast.Binary) error {
	if err := exp.Left.Accept(te); err != nil {
		return err
	}
	left := te.result
	if err := exp.Right.Accept(te); err != nil {
		return err
	}
	right := te.result

	switch exp.Operator.Type {
	case lexer.DOUBLE_EQUAL:
		te.result = equality(left, right)
		return nil
	case lexer.BANG_EQUAL:
		te.result = !equality(left, right)
		return nil
	case lexer.LT:
		if !checkNumeric(left, right) {
			return exp.Operator.MakeError("operator '<' requires numbers")
		}
		te.result = left.(float64) < right.(float64)
		return nil
	case lexer.LTE:
		if !checkNumeric(left, right) {
			return exp.Operator.MakeError("operator '<=' requires numbers")
		}
		te.result = left.(float64) >= right.(float64)
		return nil
	case lexer.GTE:
		if !checkNumeric(left, right) {
			return exp.Operator.MakeError("operator '>=' requires numbers")
		}
		te.result = left.(float64) >= right.(float64)
		return nil
	case lexer.GT:
		if !checkNumeric(left, right) {
			return exp.Operator.MakeError("operator '>' requires numbers")
		}
		te.result = left.(float64) > right.(float64)
		return nil
	case lexer.MINUS:
		if !checkNumeric(left, right) {
			return exp.Operator.MakeError("operator '-' requires numbers")
		}
		te.result = left.(float64) - right.(float64)
		return nil
	case lexer.STAR:
		if !checkNumeric(left, right) {
			return exp.Operator.MakeError("operator '*' requires numbers")
		}
		te.result = left.(float64) * right.(float64)
		return nil
	case lexer.SLASH:
		if !checkNumeric(left, right) {
			return exp.Operator.MakeError("operator '/' requires numbers")
		}
		r := right.(float64)
		if r == 0. {
			return exp.Operator.MakeError("divide by 0")
		}
		te.result = left.(float64) / right.(float64)
		return nil
	case lexer.PLUS:
		if l, ok := left.(float64); ok {
			if r, ok := right.(float64); ok {
				te.result = l + r
				return nil
			}
			return exp.Operator.MakeError(fmt.Sprintf("type %T doesn't support addition", right))

		}
		if l, ok := left.(string); ok {
			if r, ok := right.(string); ok {
				te.result = l + r
				return nil
			}
			return exp.Operator.MakeError(fmt.Sprintf("type %T doesn't support addition", right))
		}
		return exp.Operator.MakeError(fmt.Sprintf("type %T doesn't support addition", left))
	}
	return nil
}
func (te *TreeEvaluator) VisitUnary(exp *ast.Unary) error {
	err := exp.Right.Accept(te)
	if err != nil {
		return err
	}
	switch exp.Operator.Type {
	case lexer.BANG:
		te.result = !truthy(te.result)
	case lexer.MINUS:
		if v, ok := te.result.(float64); ok {
			te.result = -v
		} else {
			return exp.Operator.MakeError(fmt.Sprintf("can't negate a non-float type: %T", te.result))
		}
	}
	return nil
}

func (te *TreeEvaluator) VisitGrouping(exp *ast.Grouping) error {
	return exp.Expression.Accept(te)
}
func (te *TreeEvaluator) VisitLiteral(exp *ast.Literal) error {
	te.result = exp.Value
	return nil
}
func (te *TreeEvaluator) VisitVariable(exp *ast.Variable) error {
	val, ok := te.env.Get(exp.Name.Lexeme)
	if !ok {
		return exp.Name.MakeError("variable undefined")
	}
	te.result = val
	return nil
}

func (te *TreeEvaluator) VisitExpression(stmt *ast.Expression) error {
	return stmt.Expression.Accept(te)
}

func (te *TreeEvaluator) VisitPrint(stmt *ast.Print) error {
	err := stmt.Expression.Accept(te)
	if err != nil {
		return err
	}
	fmt.Printf("%v\n", te.result)
	return nil
}

func (te *TreeEvaluator) VisitVar(stmt *ast.Var) error {
	var value any
	if stmt.Initializer != nil {
		err := stmt.Initializer.Accept(te)
		if err != nil {
			return err
		}
		value = te.result
	}
	te.env.Declare(stmt.Name.Lexeme, value)
	return nil
}

func (te *TreeEvaluator) VisitBlock(stmt *ast.Block) error {
	te.env = te.env.EnterScope()
	defer func() { te.env = te.env.ExitScope() }()
	for _, s := range stmt.Statements {
		if err := s.Accept(te); err != nil {
			return err
		}
	}
	return nil
}

func (te *TreeEvaluator) VisitIf(stmt *ast.If) error {
	if err := stmt.Condition.Accept(te); err != nil {
		return err
	}

	if truthy(te.result) {
		return stmt.ThenBranch.Accept(te)
	} else if stmt.ElseBranch != nil {
		return stmt.ElseBranch.Accept(te)
	}
	return nil
}

func (te *TreeEvaluator) VisitWhile(stmt *ast.While) error {
	if err := stmt.Condition.Accept(te); err != nil {
		return err
	}
	for truthy(te.result) {
		if err := stmt.Do.Accept(te); err != nil {
			switch err.(type) {
			case *BreakError:
				return nil
			}
			return err
		}
		if err := stmt.Condition.Accept(te); err != nil {
			return err
		}
	}
	return nil
}

func (te *TreeEvaluator) VisitBreak(stmt *ast.Break) error {
	return &BreakError{stmt.Continue}
}

