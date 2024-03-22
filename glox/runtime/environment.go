package runtime

type Environment struct {
	parent *Environment
	data   map[string]any
}

func NewEnvironment(parent *Environment) *Environment {
	return &Environment{
		parent: parent,
		data:   make(map[string]any),
	}
}

func (e *Environment) GetAt(i int, name string) (val any, ok bool) {
	t := e
	for ; i > 0; i -= 1 {
		t = t.parent
	}
	return t.Get(name)
}

func (e *Environment) AssignAt(i int, name string, value any) bool {
	t := e
	for ; i > 0; i -= 1 {
		t = t.parent
	}
	t.data[name] = value
	return true
}

func (e *Environment) Declare(name string, value any) {
	e.data[name] = value
}

func (e *Environment) Assign(name string, value any) bool {
	if _, ok := e.data[name]; ok {
		e.data[name] = value
		return true
	}
	if e.parent != nil {
		return e.parent.Assign(name, value)
	}
	return false
}

func (e *Environment) Get(name string) (val any, ok bool) {
	val, ok = e.data[name]
	if !ok && e.parent != nil {
		val, ok = e.parent.Get(name)
	}

	return
}

func (e *Environment) EnterScope() *Environment {
	return NewEnvironment(e)
}

func (e Environment) ExitScope() *Environment {
	if e.parent != nil {
		return e.parent
	}
	return nil
	//panic(errors.New("can't exit the global environment"))
}
