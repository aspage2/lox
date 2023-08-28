
GOFILES=$(wildcard *.go)

main: $(GOFILES) lexer/tokentype_string.go ast/ast_gen.go
	go build -o main ./cmd

lexer/tokentype_string.go: lexer/tokentype.go
	stringer -type TokenType ./lexer/

ast/ast_gen.go: tool/glast/main.go
	go run tool/glast/main.go | goimports | gofmt > ast/ast_gen.go

.PHONY: test
test:
	go test -coverprofile=unit.cover -v ./...

.PHONY: fmt
fmt:
	goimports -l -w .
	gofmt -l -w .

.PHONY: clean
clean:
	rm -f main
	rm -f ast/ast_gen.go
	rm -f lexer/tokentype_string.go
