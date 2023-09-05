package runtime

func truthy(val any) bool {
	switch t := val.(type) {
	case bool:
		return t
	case float64:
		return t != 0.0
	case string:
		return len(t) > 0
	default:
		return val != nil
	}
}

func equality(l, r any) bool {
	return l == r
}

func checkNumeric(vals ...any) bool {
	for _, v := range vals {
		if _, ok := v.(float64); !ok {
			return false
		}
	}
	return true
}

type BreakError struct {
	Continue bool
}

func (e BreakError) Error() string {
	if e.Continue {
		return "continue statement"
	} else {
		return "break statement"
	}
}
