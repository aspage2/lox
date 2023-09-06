package runtime

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestEnvironment_NewEnvironment(t *testing.T) {
	env := NewEnvironment(nil)
	assert.Nil(t, env.parent)
	assert.Empty(t, env.data)
}

func TestEnvironment_Declare(t *testing.T) {
	env := &Environment{data: make(map[string]any)}
	env.Declare("x", 3)
	assert.Equal(t, 3, env.data["x"])
}

func TestEnvironment_Declare_Overwrite(t *testing.T) {
	env := &Environment{data: make(map[string]any)}
	env.Declare("x", 3)
	env.Declare("x", 44)

	assert.Equal(t, 44, env.data["x"])
}

func TestEnvironment_Get(t *testing.T) {
	type testcase struct {
		scopes []map[string]any
		key    string
		expVal any
		expOk  bool
	}
	testcases := []testcase{
		{
			scopes: []map[string]any{
				{"x": 3, "y": "hello"},
			},
			key:    "x",
			expVal: 3,
			expOk:  true,
		},
		{
			scopes: []map[string]any{
				{"x": 3, "y": "Hello"},
			},
			key:    "z",
			expVal: nil,
			expOk:  false,
		},
		{
			scopes: []map[string]any{
				{"x": "Hello"},
				{"y": "Goodbye"},
			},
			key:    "x",
			expVal: "Hello",
			expOk:  true,
		},
	}
	for i, testcase := range testcases {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			env := &Environment{data: testcase.scopes[0]}
			for _, scope := range testcase.scopes[1:] {
				env = &Environment{parent: env, data: scope}
			}
			val, ok := env.Get(testcase.key)
			assert.Equal(t, testcase.expVal, val)
			assert.Equal(t, testcase.expOk, ok)
		})
	}
}

func TestEnvironment_Assign(t *testing.T) {
	type testcase struct {
		scope map[string]any
		key   string
		value any
		expOk bool
	}

	testcases := []testcase{
		{
			scope: map[string]any{"x": 33},
			key:   "x",
			value: "hi",
			expOk: true,
		},
		{
			scope: map[string]any{},
			key:   "x",
			value: "hi",
			expOk: false,
		},
	}
	for i, testcase := range testcases {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			e := &Environment{data: testcase.scope}
			ok := e.Assign(testcase.key, testcase.value)
			assert.Equal(t, testcase.expOk, ok)
			if testcase.expOk && ok {
				assert.Equal(t, testcase.value, e.data[testcase.key])
			}
		})
	}
}
