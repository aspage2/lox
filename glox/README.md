
# Glox

[](https://craftinginterpreters.com/)

Glox is a procedural toy-language designed for hacking and learning some stuff about
building programming languages. It is the product of the first section of the "Crafting
Interpreters" book by Robert Nystrom.

## Usage

### Installation
Glox can only be built from source.

First, make sure the following is installed:
* GNU Make
* [stringer](https://pkg.go.dev/golang.org/x/tools/cmd/stringer)

then, run `make` to create the `./build/glox` binary.

### CLI

Run `.lx` scripts with `glox [filename]`, or begin the glox REPL by omitting the file name.

