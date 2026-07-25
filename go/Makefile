BINARY_DIR := ../bin
CMDS := swissknife pmxctl kvmctl

.PHONY: all build clean test lint tidy

all: build

build:
	@for cmd in $(CMDS); do \
		echo "Building $$cmd..."; \
		mkdir -p $(BINARY_DIR); \
		go build -ldflags "-s -w" -o $(BINARY_DIR)/$$cmd.exe ./cmd/$$cmd; \
	done

test:
	go test -v -race -count=1 ./...

lint:
	golangci-lint run ./...

clean:
	rm -rf $(BINARY_DIR)

tidy:
	go mod tidy
