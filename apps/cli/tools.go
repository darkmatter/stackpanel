//go:build tools
// +build tools

// Package tools tracks tool dependencies for cli.
// This file is used to declare tool dependencies that are not imported
// in production code, but are needed for development/build.
//
// Run: go mod tidy
// Then: gomod2nix generate --with-deps
package tools

import (
  _ "github.com/air-verse/air"
  _ "github.com/golangci/golangci-lint/cmd/golangci-lint"
  _ "mvdan.cc/gofumpt"
  
)
