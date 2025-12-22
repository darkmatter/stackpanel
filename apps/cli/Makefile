.PHONY: build install clean test dev

# Build variables
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
LDFLAGS := -ldflags "-X github.com/darkmatter/stackpanel/cli/cmd.Version=$(VERSION) -X github.com/darkmatter/stackpanel/cli/cmd.BuildDate=$(BUILD_DATE)"

# Output
BINARY := stackpanel
BUILD_DIR := ./build

# Go settings
GOBIN ?= $(shell go env GOPATH)/bin

all: build

# Build for current platform
build:
	@echo "Building $(BINARY)..."
	@mkdir -p $(BUILD_DIR)
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY) .

# Install to GOBIN
install: build
	@echo "Installing to $(GOBIN)/$(BINARY)..."
	@cp $(BUILD_DIR)/$(BINARY) $(GOBIN)/$(BINARY)

# Build for all platforms
release:
	@echo "Building releases..."
	@mkdir -p $(BUILD_DIR)
	GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-darwin-arm64 .
	GOOS=darwin GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-darwin-amd64 .
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-linux-amd64 .
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-linux-arm64 .

# Development build with hot reload
dev:
	@echo "Starting development mode..."
	@which watchexec > /dev/null || (echo "Install watchexec: cargo install watchexec-cli" && exit 1)
	watchexec -r -e go -- go run .

# Run tests
test:
	go test -v ./...

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	go clean

# Format code
fmt:
	go fmt ./...

# Lint code
lint:
	@which golangci-lint > /dev/null || go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	golangci-lint run

# Update dependencies
deps:
	go mod tidy
	go mod download

# Show help
help:
	@echo "Stackpanel CLI build targets:"
	@echo ""
	@echo "  build    - Build for current platform"
	@echo "  install  - Build and install to GOBIN"
	@echo "  release  - Build for all platforms"
	@echo "  dev      - Run with hot reload (requires watchexec)"
	@echo "  test     - Run tests"
	@echo "  clean    - Clean build artifacts"
	@echo "  fmt      - Format code"
	@echo "  lint     - Lint code"
	@echo "  deps     - Update dependencies"
	@echo ""
