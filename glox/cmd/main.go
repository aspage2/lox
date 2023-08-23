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
	if l == 1 {
		interactiveShell(&runtime.Lox{})
	} else if l == 2 {
		runFromFile(&runtime.Lox{}, os.Args[1])
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
		loxError.Report()
		os.Exit(1)
	}

}
