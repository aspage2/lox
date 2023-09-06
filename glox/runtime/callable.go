package runtime

import (
	"fmt"
	"time"
)

type Callable interface {
	Arity() int
	Call(*TreeEvaluator, []any) (any, error)
}

func LoxTime(l *TreeEvaluator, args []any) (any, error) {
	return float64(time.Now().UnixMilli()) / 1000., nil
}

func LoxStringify(l *TreeEvaluator, args []any) (any, error) {
	return fmt.Sprintf("%v", args[0]), nil
}

func DefineNativeFunctions(e *Environment) {
	e.Declare("to_string", NewGoCallable(LoxStringify, 1))
	e.Declare("time", NewGoCallable(LoxTime, 0))
}
