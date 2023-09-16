package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	rd := bufio.NewReader(os.Stdin)

	for {
		fmt.Print(" > ")
		data, err := rd.ReadString('\n')
		if err != nil {
			panic(err)
		}
		num, err := strconv.ParseInt(strings.TrimSpace(string(data)), 16, 32)
		if err != nil {
			panic(err)
		}

		fmt.Printf("%c\n", rune(num))
	}
}
