package runtime

import (
	"fmt"
)

type LoxClass struct {
	Name    string
	Methods map[string]*LoxFunction
}

func (cls *LoxClass) Call(lox *TreeEvaluator, args []any) (any, error) {
	instance := NewLoxInstance(cls)
	if init, ok := cls.FindMethod("init"); ok {
		init.Bind(instance).Call(lox, args)
	}
	return instance, nil
}

func (cls *LoxClass) Arity() int {
	if init, ok := cls.FindMethod("init"); ok {
		return init.Arity()
	}
	return 0
}

func (cls *LoxClass) String() string {
	return fmt.Sprintf("<class '%s'>", cls.Name)
}

func (cls *LoxClass) FindMethod(name string) (*LoxFunction, bool) {
	val, ok := cls.Methods[name]
	return val, ok
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
	if val, ok := inst.fields[name]; ok {
		return val, true
	}
	if method, ok := inst.Cls.FindMethod(name); ok {
		return method.Bind(inst), true
	}
	return nil, false
}

func (inst *LoxInstance) Set(name string, value any) {
	inst.fields[name] = value
}
