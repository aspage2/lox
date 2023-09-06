
GOFILES=$(shell find . -type f -name '*.go')


build/glox: $(GOFILES) lexer/tokentype_string.go ast/Expr_gen.go ast/Stmt_gen.go
	go build -o build/glox ./cmd

lexer/tokentype_string.go: lexer/tokentype.go
	stringer -type TokenType ./lexer/

ast/%_gen.go: ast.json tool/glast/main.go
	go run tool/glast/main.go -p ast -t $(*F) ast.json > $@
	goimports -w $@
	gofmt -w $@

unit.cover: $(GOFILES)
	$(MAKE) test

coverage.html: unit.cover
	go tool cover -html unit.cover -o $(@)

# -------------------- PHONY Targets

.PHONY: cover
cover: coverage.html

.PHONY: stubs
stubs:
	$(MAKE) lexer/tokentype_string.go ast/Expr_gen.go ast/Stmt_gen.go

.PHONY: debug
debug:
	dlv debug --headless --listen :4040 ./cmd

.PHONY: run
run:
	go run ./cmd

.PHONY: test
test:
	go test -coverprofile=unit.cover  ./...

.PHONY: fmt
fmt:
	goimports -l -w .
	gofmt -l -w .

.PHONY: clean
clean:
	rm -rf build
	rm -f ast/Expr_gen.go
	rm -f ast/Stmt_gen.go
	rm -f lexer/tokentype_string.go
