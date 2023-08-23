
GOFILES=$(wildcard *.go)

main: $(GOFILES)
	go build -o main .

.PHONY: test
test:
	go test -coverprofile=unit.cover -v ./...

.PHONY: fmt
fmt:
	goimports -l -w .
	gofmt -l -w .

.PHONY: clean
clean:
	rm main
