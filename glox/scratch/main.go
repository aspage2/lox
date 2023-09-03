package main

import (
	"fmt"
	"os"
)

func main() {
	data := make([]byte, 1)
	_, err := os.Stdin.Read(data)
	if err != nil {
		fmt.Println(err)
	}
	fmt.Printf("%v\n", data)
}
