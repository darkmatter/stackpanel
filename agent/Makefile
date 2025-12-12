BINARY=stackpanel-agent
VERSION?=dev
COMMIT=$(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
LDFLAGS=-ldflags "-X main.version=${VERSION} -X main.commit=${COMMIT}"

.PHONY: build run test clean install

build:
	go build ${LDFLAGS} -o ${BINARY} .

run:
	go run . --debug

test:
	go test -v ./...

clean:
	rm -f ${BINARY}

install:
	go install ${LDFLAGS} .

# Cross-compile for distribution
dist:
	GOOS=darwin GOARCH=arm64 go build ${LDFLAGS} -o dist/${BINARY}-darwin-arm64 .
	GOOS=darwin GOARCH=amd64 go build ${LDFLAGS} -o dist/${BINARY}-darwin-amd64 .
	GOOS=linux GOARCH=amd64 go build ${LDFLAGS} -o dist/${BINARY}-linux-amd64 .
	GOOS=linux GOARCH=arm64 go build ${LDFLAGS} -o dist/${BINARY}-linux-arm64 .

# Test client
test-client:
	go run ./cmd/test-client
