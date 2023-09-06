package runtime

// BreakError tells a TreeEvaluator to escape out of the
// innermost loop of an execution.
type BreakError struct {
	Continue bool
}

func (e BreakError) Error() string {
	if e.Continue {
		return "continue statement outside of loop"
	} else {
		return "break statement outside of loop"
	}
}

// ReturnError tells a TreeEvaluator to escape out
// of a function call.
type ReturnError struct {
	Value any
}

func (rv *ReturnError) Error() string {
	return "return outside function declaration"
}
