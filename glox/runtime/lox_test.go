package runtime

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLox_Locals(t *testing.T) {
	l := NewLoxInterpreter()

	_, err := l.Run("fun thing(x) { return x + 2 ; }")
	assert.NoError(t, err)

	val, err := l.Run("print thing(3);")
	assert.NoError(t, err)
	assert.Equal(t, 5., val)
}

func TestLox_Resolution(t *testing.T) {
	prgm := `
	var a = 3;
	{
		var t = 0;
		fun f(x) { return x + 3; }
		t = t + f(3);
		var a = 5;
		t = t + f(3);
		print t;
		t;
	}
	`
	val, err := NewLoxInterpreter().Run(prgm)
	assert.NoError(t, err)
	assert.Equal(t, 12., val)
}
