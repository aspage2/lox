package runtime

import (
	"fmt"
	"glox/ast"
)

// Functions defined in lox code with "fun" syntax.
type LoxFunction struct {
	Declaration *ast.Function
}

func (lf *LoxFunction) Call(te *TreeEvaluator, args []any) (any, error) {
	v := te.BaseEnv.EnterScope()
	for i := 0; i < lf.Arity(); i++ {
		v.Declare(lf.Declaration.Params[i].Lexeme, args[i])
	}
	if val, err := te.ExecuteStatementsWithEnv(lf.Declaration.Body, v); err != nil {
		if r, ok := err.(*ReturnError); ok {
			return r.Value, nil
		}
		return nil, err
	} else {
		return val, nil
	}
}

func (lf *LoxFunction) Arity() int {
	return len(lf.Declaration.Params)
}

func (lf *LoxFunction) String() string {
	return fmt.Sprintf("<fun %s>", lf.Declaration.Name.Lexeme)
}
