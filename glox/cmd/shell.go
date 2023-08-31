package main

import (
	"bufio"
	"fmt"
	"glox/runtime"
	"io"
	"os"
	"strings"
)

func startUp() {
	fmt.Println("\u001b[38;2;128;204;204m", logo, "\u001b[0m")
	fmt.Println("\n  Interactive Shell \u001b[36m" + version + "\u001b[0m")
	fmt.Println("  (\u001b[32mCtrl+d or :q to exit\u001b[0m)")
}

func interactiveShell(l *runtime.Lox) {
	startUp()

	goodByeMessage := func() {
		fmt.Println("Goodbye.")
	}
	reader := bufio.NewReader(os.Stdin)

	for {
		fmt.Print(">>> ")
		data, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				goodByeMessage()
				return
			}
			panic(err)
		}
		data = strings.TrimSpace(data)
		if data == ":q" {
			goodByeMessage()
			return
		}

		l.Run(data)

		l.HadError = false
	}
}
