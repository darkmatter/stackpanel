package server

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func writeRegistryLockFixture(t *testing.T, root, nodes string) {
	t.Helper()
	data := `{"version":7,"root":"consumer","nodes":` + nodes + `}`
	if err := os.WriteFile(
		filepath.Join(root, "flake.lock"),
		[]byte(data),
		0o600,
	); err != nil {
		t.Fatal(err)
	}
}

func TestRegistryLockRootBindings(t *testing.T) {
	root := t.TempDir()
	lock, err := readRegistryLock(root)
	if err != nil {
		t.Fatal(err)
	}
	if _, exists, err := lock.input("rust"); exists || err != nil {
		t.Fatalf("missing lock: exists=%v err=%v", exists, err)
	}
	writeRegistryLockFixture(t, root, `{
		"consumer":{"inputs":{"rust":"registry_2","tools":"registry_2","alias":["tools","module"]}},
		"registry_2":{
			"inputs":{"module":["rust"]},
			"original":{"type":"github","owner":"org","repo":"registry","dir":"modules/rust","ref":"release"},
			"locked":{"type":"github","owner":"org","repo":"registry","dir":"modules/rust","rev":"1111111111111111111111111111111111111111"}
		}
	}`)
	lock, err = readRegistryLock(root)
	if err != nil {
		t.Fatal(err)
	}
	const source = "github:org/registry?dir=modules/rust"
	rust, exists, err := lock.input("rust")
	if !exists || err != nil || !rust.matchesPin(source, "release", "") {
		t.Fatalf("direct root input did not match: exists=%v err=%v", exists, err)
	}
	for _, other := range []string{"github:org/registry", "github:org/registry?dir=modules/go", source + "&host=other.example", source + "&futureOption=1"} {
		if rust.matchesSource(other) {
			t.Errorf("matched distinct source %q", other)
		}
	}
	alias, exists, err := lock.input("alias")
	if !exists || err != nil || alias.matchesSource(source) ||
		alias.matchesPin(source, "release", "") {
		t.Fatalf(
			"follows must occupy the name without owning the source: exists=%v err=%v",
			exists,
			err,
		)
	}
	if _, exists, err := lock.input("registry_2"); exists || err != nil {
		t.Fatalf("node key leaked into root inputs: exists=%v err=%v", exists, err)
	}
}

func TestRegistryLockRejectsBrokenGraph(t *testing.T) {
	for _, tc := range []struct{ name, nodes string }{
		{"no root", `{"not-consumer":{}}`},
		{"null inputs", `{"consumer":{"inputs":null}}`},
		{"missing node", `{"consumer":{"inputs":{"slug":"absent"}}}`},
		{"missing locked", `{"consumer":{"inputs":{"slug":"x"}},"x":{"original":{"type":"path","path":"./mod"}}}`},
		{"incomplete repository", `{"consumer":{"inputs":{"slug":"x"}},"x":{"original":{"type":"github","owner":"org"},"locked":{"type":"github","owner":"org"}}}`},
		{"broken follows", `{"consumer":{"inputs":{"slug":["not-bound"]}}}`},
		{"malformed follows", `{"consumer":{"inputs":{"slug":[null]}}}`},
		{"cyclic follows", `{"consumer":{"inputs":{"slug":["alias"],"alias":["slug"]}}}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			writeRegistryLockFixture(t, root, tc.nodes)
			lock, err := readRegistryLock(root)
			if err == nil {
				_, exists, lookupErr := lock.input("slug")
				if !exists || lookupErr == nil {
					t.Fatalf("broken graph reported exists=%v err=%v", exists, lookupErr)
				}
			}
		})
	}
}

func TestRegistryLockPolicyAndTransport(t *testing.T) {
	const rev = "0123456789abcdef0123456789abcdef01234567"
	const otherRev = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	const forge = `"type":"gitlab","host":"forge.example","owner":"o","repo":"r"`
	const ssh = `"type":"git","url":"ssh://alice@git.example:2222/team/r.git"`
	root := t.TempDir()
	local := filepath.Join(root, "vendor", "module")
	for _, tc := range []struct {
		name, original, locked, url, ref, rev string
		sourceMatch, pinMatch                 bool
	}{
		{"forge rev wins over ref", forge + `,"rev":"` + rev + `"`, forge + `,"rev":"` + rev + `"`, "gitlab:o/r?host=forge.example", "release", rev, true, true},
		{"locked commit alone is not a declared pin", forge + `,"ref":"release"`, forge + `,"rev":"` + rev + `"`, "gitlab:o/r?host=forge.example", "release", rev, true, false},
		{"declared commit alone is not a locked pin", forge + `,"rev":"` + rev + `"`, forge + `,"rev":"` + otherRev + `"`, "gitlab:o/r/" + rev + "?host=forge.example", "", "", true, false},
		{"git retains both selectors", ssh + `,"ref":"releases/v1","rev":"` + rev + `"`, ssh + `,"rev":"` + rev + `"`, "git+ssh://alice@git.example:2222/team/r.git", "releases/v1", rev, true, true},
		{"locked ref is not the declaration", ssh, ssh + `,"ref":"main","rev":"` + rev + `"`, "git+ssh://alice@git.example:2222/team/r.git", "main", "", true, false},
		{"same host different repository", ssh, ssh + `,"rev":"` + rev + `"`, "git+ssh://alice@git.example:2222/team/s.git", "", "", false, false},
		{"overridden locked URL", ssh, `"type":"git","url":"file:///different","rev":"` + rev + `"`, "git+ssh://alice@git.example:2222/team/r.git", "", "", false, false},
		{"different git tree options", ssh + `,"submodules":true`, ssh + `,"submodules":true,"rev":"` + rev + `"`, "git+ssh://alice@git.example:2222/team/r.git", "", "", false, false},
		{"path relative to lock root", `"type":"path","path":"./vendor/module","dir":"nested"`, fmt.Sprintf(`"type":"path","path":%q,"dir":"nested","narHash":"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="`, local), "path:vendor/module?dir=nested", "", "", true, true},
		{"git file resolves relative to project", `"type":"git","url":"file:./vendor/module"`, fmt.Sprintf(`"type":"git","url":"file://%s","rev":"%s"`, local, rev), "git+file://" + local, "", "", true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			writeRegistryLockFixture(
				t,
				root,
				`{"consumer":{"inputs":{"mod":"node"}},"node":{"original":{`+tc.original+`},"locked":{`+tc.locked+`}}}`,
			)
			lock, err := readRegistryLock(root)
			if err != nil {
				t.Fatal(err)
			}
			n, exists, err := lock.input("mod")
			if !exists || err != nil {
				t.Fatalf("exists=%v err=%v", exists, err)
			}
			if got := n.matchesSource(tc.url); got != tc.sourceMatch {
				t.Errorf("source match = %v, want %v", got, tc.sourceMatch)
			}
			if got := n.matchesPin(tc.url, tc.ref, tc.rev); got != tc.pinMatch {
				t.Errorf("pin match = %v, want %v", got, tc.pinMatch)
			}
		})
	}
}
