package runtime

import (
	"fmt"
	"glox/ast"
)

// Functions defined in lox code with "fun" syntax.
type LoxFunction struct {
	Declaration *ast.Function
	Closure     *Environment
}

func (lf *LoxFunction) Call(te *TreeEvaluator, args []any) (any, error) {
	// The closure is the environment that the function declaration
	// was defined in. We set this as the parent scope for this invocation
	// so we can access variables defined within this closure.
	v := lf.Closure.EnterScope()

	for i := 0; i < lf.Arity(); i++ {
		v.Declare(lf.Declaration.Params[i].Lexeme, args[i])
	}

	if val, err := te.ExecuteStatementsWithEnv(lf.Declaration.Body, v); err != nil {
		// return statements produce this error to indicate that a function should stop execution.
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

func (lf *LoxFunction) Bind(inst *LoxInstance) *LoxFunction {
	env := NewEnvironment(lf.Closure)
	env.Declare("this", inst)
	return &LoxFunction{
		Declaration: lf.Declaration,
		Closure:     env,
	}
}

func (lf *LoxFunction) String() string {
	return fmt.Sprintf("<fun %s>", lf.Declaration.Name.Lexeme)
}
