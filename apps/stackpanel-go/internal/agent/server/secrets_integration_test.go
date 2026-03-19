package server

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	sharedexec "github.com/darkmatter/stackpanel/stackpanel-go/pkg/exec"
)

const fakeSerializableSecretsJSON = `{
  "secretsDir": ".stack/secrets",
  "sopsConfigFile": ".stack/secrets/.sops.yaml",
  "recipients": {
    "alice": {
      "publicKey": "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
      "tags": [
        "dev"
      ]
    },
    "bob": {
      "publicKey": "age1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "tags": [
        "dev",
        "ops"
      ]
    }
  },
  "variables": {
    "/secret/api-key": {
      "file": "vars/api-key.sops.yaml",
      "yamlKey": "api_key",
      "tags": [
        "dev"
      ],
      "recipients": [
        "alice",
        "bob"
      ]
    },
    "/secret/db-url": {
      "file": "vars/db-url.sops.yaml",
      "yamlKey": "db_url",
      "tags": [
        "ops"
      ],
      "recipients": [
        "bob"
      ]
    }
  },
  "groups": {
    "dev": {
      "tags": [
        "dev"
      ],
      "recipients": [
        "alice",
        "bob"
      ]
    },
    "prod": {
      "tags": [
        "ops"
      ],
      "recipients": [
        "bob"
      ]
    }
  }
}`

func writeFakeNixFixture(t *testing.T, workingDir string) {
	t.Helper()

	binDir := filepath.Join(workingDir, "bin")
	if err := os.MkdirAll(binDir, 0o755); err != nil {
		t.Fatalf("failed to create fixture bin dir: %v", err)
	}

	nixPath := filepath.Join(binDir, "nix")
	script := `#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "eval" && "$2" == "--impure" && "$3" == "--json" && "$4" == ".#stackpanelFullConfig.serializable.secrets" ]]; then
  cat <<'JSON'
` + fakeSerializableSecretsJSON + `
JSON
  exit 0
fi

echo "unexpected nix command: $*" >&2
exit 1
`
	if err := os.WriteFile(nixPath, []byte(script), 0o755); err != nil {
		t.Fatalf("failed to write fake nix script: %v", err)
	}

	currentPath := os.Getenv("PATH")
	if currentPath == "" {
		t.Fatalf("PATH is unexpectedly empty")
	}

	t.Setenv("PATH", fmt.Sprintf("%s:%s", binDir, currentPath))
}

func TestGetSerializableSecretsConfigContract(t *testing.T) {
	tempDir := t.TempDir()
	writeFakeNixFixture(t, tempDir)

	exec, err := sharedexec.NewWithoutDevshell(tempDir, nil)
	if err != nil {
		t.Fatalf("failed to create executor: %v", err)
	}

	server := &Server{
		exec: exec,
	}

	serializable, err := server.getSerializableSecretsConfig()
	if err != nil {
		t.Fatalf("getSerializableSecretsConfig returned error: %v", err)
	}

	if len(serializable.Recipients) != 2 {
		t.Fatalf("expected 2 recipients, got %d", len(serializable.Recipients))
	}

	if got := serializable.Recipients["alice"].PublicKey; got != "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" {
		t.Fatalf("unexpected public key for alice: %q", got)
	}

	apiMeta, ok := serializable.Variables["/secret/api-key"]
	if !ok {
		t.Fatal("expected /secret/api-key variable metadata")
	}

	if apiMeta.File != "vars/api-key.sops.yaml" {
		t.Fatalf("unexpected variable file, got %q", apiMeta.File)
	}

	if len(apiMeta.Recipients) != 2 {
		t.Fatalf("expected 2 recipients for /secret/api-key, got %d", len(apiMeta.Recipients))
	}

	groupRecipients, err := server.getGroupRecipients("dev")
	if err != nil {
		t.Fatalf("getGroupRecipients returned error: %v", err)
	}

	if len(groupRecipients) != 2 {
		t.Fatalf("expected 2 recipients for dev group, got %d", len(groupRecipients))
	}
}

func TestGetVariableSecretMetaFromSerializableConfig(t *testing.T) {
	tempDir := t.TempDir()
	writeFakeNixFixture(t, tempDir)

	exec, err := sharedexec.NewWithoutDevshell(tempDir, nil)
	if err != nil {
		t.Fatalf("failed to create executor: %v", err)
	}

	server := &Server{
		exec: exec,
	}

	meta, ok, err := server.getVariableSecretMeta("/secret/db-url")
	if err != nil {
		t.Fatalf("getVariableSecretMeta returned error: %v", err)
	}
	if !ok {
		t.Fatal("expected /secret/db-url metadata to exist")
	}

	if meta.File != "vars/db-url.sops.yaml" {
		t.Fatalf("unexpected db-url variable file: %q", meta.File)
	}

	if meta.YamlKey != "db_url" {
		t.Fatalf("unexpected db-url yaml key: %q", meta.YamlKey)
	}

	if len(meta.Recipients) != 1 || meta.Recipients[0] != "bob" {
		t.Fatalf("expected db-url recipients [\"bob\"], got %#v", meta.Recipients)
	}
}
