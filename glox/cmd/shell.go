package main

import (
	"fmt"
	"glox/runtime"
	"io"
	"strings"

	"github.com/chzyer/readline"
)

func startUpMessage() {
	fmt.Println("\u001b[38;2;128;204;204m", logo, "\u001b[0m")
	fmt.Println("\n  Interactive Shell \u001b[36m" + version + "\u001b[0m")
	fmt.Println("  (\u001b[32mCtrl+d or :q to exit\u001b[0m)")
}

func goodbyeMessage() {
	fmt.Println("Goodbye.")
}

func interactiveShell(l *runtime.Lox) {
	startUpMessage()

	rl, err := readline.New(">>> ")
	if err != nil {
		panic(err)
	}
	defer rl.Close()

	for {
		fmt.Print(">>> ")
		data, err := rl.Readline()
		if err != nil {
			if err == io.EOF {
				goodbyeMessage()
				return
			}
			panic(err)
		}
		data = strings.TrimSpace(data)
		if data == ":q" {
			goodbyeMessage()
			return
		}

		value, _ := l.Run(data)
		if value != nil {
			fmt.Printf("[out] -> %v\n", value)
		}

		l.HadError = false
	}
}
