package main

import (
	"fmt"
	"strings"
)

var AST = map[string]string{
	"Binary":   "Left Expr, Operator lexer.Token, Right Expr",
	"Unary":    "Operator lexer.Token, Right Expr",
	"Grouping": "Expression Expr",
	"Literal":  "Value lexer.Token",
}

type Generator struct {
	strings.Builder
	Types map[string]string
}

func (g *Generator) packageAndImports(packageName string) {
	fmt.Fprintf(g, "package %s\n", packageName)

	imports := []string{"glox/lexer"}

	if len(imports) > 0 {
		g.WriteString("import (\n")
		for _, k := range imports {
			fmt.Fprintf(g, "\t\"%s\"\n", k)
		}
		g.WriteString(")\n")
	}
}

func (g *Generator) visitorInterface() {
	g.WriteString("type Visitor interface {\n")
	for k := range g.Types {
		fmt.Fprintf(g, "\tVisit%s(*%s)\n", k, k)
	}
	g.WriteString("}\n")
}

func (g *Generator) exprInterface() {
	g.WriteString(`
type Expr interface {
	Accept(Visitor)
}
`)
}

func (g *Generator) nodeTypes() {
	for k, v := range g.Types {
		fmt.Fprintf(g, "type %s struct {\n", k)

		for _, fld := range strings.Split(v, ",") {
			fld = strings.TrimSpace(fld)
			fmt.Fprintf(g, "\t%s\n", fld)
		}
		g.WriteString("}\n")

		fmt.Fprintf(g, "func (n *%s)Accept(v Visitor) {\n\tv.Visit%s(n)\n}\n", k, k)
	}
}

func main() {
	g := &Generator{Types: AST}
	g.packageAndImports("ast")
	g.visitorInterface()
	g.exprInterface()
	g.nodeTypes()

	fmt.Println(g.String())
}
