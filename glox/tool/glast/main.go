package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
)

type Generator struct {
	strings.Builder
	Name    string
	Types   map[string][]string
	Package string
	Imports []string
}

func (g *Generator) packageAndImports() {
	fmt.Fprintf(g, "package %s\n", g.Package)

	if len(g.Imports) > 0 {
		g.WriteString("import (\n")
		for _, k := range g.Imports {
			fmt.Fprintf(g, "\t\"%s\"\n", k)
		}
		g.WriteString(")\n")
	}
}

func (g *Generator) visitorInterface() {
	fmt.Fprintf(g, "type %sVisitor interface {\n", g.Name)
	for k := range g.Types {
		fmt.Fprintf(g, "\tVisit%s(*%s) error\n", k, k)
	}
	g.WriteString("}\n")
}

func (g *Generator) exprInterface() {
	fmt.Fprintf(g, "type %s interface {\n", g.Name)
	fmt.Fprintf(g, "\tAccept(%sVisitor) error\n}\n", g.Name)
}

func (g *Generator) nodeTypes() {
	for k, v := range g.Types {
		fmt.Fprintf(g, "type %s struct {\n", k)

		for _, fld := range v {
			fld = strings.TrimSpace(fld)
			fmt.Fprintf(g, "\t%s\n", fld)
		}
		g.WriteString("}\n")

		fmt.Fprintf(g, "func (n *%s) Accept(v %sVisitor) error {\n\treturn v.Visit%s(n)\n}\n", k, g.Name, k)
	}
}

func DefineAST(name string, types map[string][]string, pkg string, imports []string) string {
	g := &Generator{Name: name, Types: types, Package: pkg, Imports: imports}
	g.packageAndImports()
	g.visitorInterface()
	g.exprInterface()
	g.nodeTypes()

	return g.String()
}

type AstDefn map[string][]string

func Must[V any](value V, err error) V {
	if err != nil {
		panic(err)
	}
	return value
}

func main() {
	pkg := flag.String("p", "", "Package name")
	name := flag.String("t", "", "type in ast file to render")
	flag.Parse()
	if *pkg == "" || *name == "" {
		flag.Usage()
		os.Exit(1)
	}
	fname := flag.Arg(0)

	data := Must(os.ReadFile(fname))
	var defns map[string]AstDefn
	if err := json.Unmarshal(data, &defns); err != nil {
		panic(err)
	}
	defn, ok := defns[*name]
	if !ok {
		panic(errors.New(*name + " is not a definition in " + fname))
	}
	code := DefineAST(
		*name,
		defn,
		"ast",
		[]string{"glox/lexer"},
	)
	fmt.Println(code)
}
