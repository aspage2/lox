package main

import (
	_ "embed"
	"fmt"
	"os"

	"glox/runtime"
)

//go:embed logo.txt
var logo string

//go:embed version.txt
var version string

func main() {
	l := len(os.Args)
	lox := &runtime.Lox{
		Env: make(runtime.Environment),
	}
	if l == 1 {
		interactiveShell(lox)
	} else if l == 2 {
		runFromFile(lox, os.Args[1])
	} else {
		fmt.Println("Usage: glox [filename]")
		os.Exit(2)
	}
}

func runFromFile(l *runtime.Lox, fname string) {
	data, err := os.ReadFile(fname)
	if err != nil {
		panic(err)
	}
	loxError := l.Run(string(data))
	if loxError != nil {
		os.Exit(1)
	}

}
