package runtime


type Environment map[string]any

func (e Environment) Declare(name string, value any) {
	e[name] = value
}

func (e Environment) Assign(name string, value any) bool {
	if _, ok := e[name]; ok {
		e[name] = value
		return true
	}
	return false
}

func (e Environment) Get(name string) (val any, ok bool) {
	val, ok = e[name]
	return
}

