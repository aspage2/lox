package runtime

type GoCallable struct {
	F func(*TreeEvaluator, []any) (any, error)
	A int
}

func (gc *GoCallable) String() string {
	return "<built-in fun>"
}

func (gc *GoCallable) Call(l *TreeEvaluator, args []any) (any, error) {
	return gc.F(l, args)
}

func (gc *GoCallable) Arity() int {
	return gc.A
}

func NewGoCallable(f func(*TreeEvaluator, []any) (any, error), arity int) Callable {
	return &GoCallable{F: f, A: arity}
}
