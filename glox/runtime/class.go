package runtime

import (
	"fmt"
)

type LoxClass struct {
	Name string
}

func (cls *LoxClass) Call(lox *TreeEvaluator, args []any) (any, error) {
	return NewLoxInstance(cls), nil
}

func (cls *LoxClass) Arity() int {
	return 0
}

func (cls *LoxClass) String() string {
	return fmt.Sprintf("<class '%s'>", cls.Name)
}

type LoxInstance struct {
	Cls    *LoxClass
	fields map[string]any
}

func NewLoxInstance(cls *LoxClass) *LoxInstance {
	return &LoxInstance{
		Cls:    cls,
		fields: make(map[string]any),
	}
}

func (inst *LoxInstance) String() string {
	return fmt.Sprintf("<instance '%s'>", inst.Cls.Name)
}

func (inst *LoxInstance) Get(name string) (any, bool) {
	val, ok := inst.fields[name]
	return val, ok
}

func (inst *LoxInstance) Set(name string, value any) {
	inst.fields[name] = value
}
