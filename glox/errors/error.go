package errors

import "fmt"

type LoxError struct {
	LineNumber int
	Context    string
	Message    string
}

func NewLoxError(ln int, ctx, msg string) *LoxError {
	return &LoxError{
		LineNumber: ln,
		Context:    ctx,
		Message:    msg,
	}
}

func (le *LoxError) Error() string {
	return fmt.Sprintf("[line %d] at '%s': %s\n", le.LineNumber, le.Context, le.Message)
}
