package flakeedit

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestUpdateRegistryDependencyOwnership(t *testing.T) {
	old := FlakeInput{
		Name:           "helper",
		URL:            "github:acme/tools?dir=helper",
		Ref:            "v1",
		FollowsNixpkgs: true,
	}
	for _, tc := range []string{"owned", "user-owned", "shared", "different live pin", "different live follows", "missing declaration", "no previous release", "validation rollback"} {
		t.Run(tc, func(t *testing.T) {
			src := txnSource
			if tc == "user-owned" {
				src = strings.Replace(
					src,
					"inputs = {",
					`inputs = { helper.url = "github:acme/tools/v1?dir=helper";`,
					1,
				)
			}
			root, log := installFixture(t, src)
			m := FlakeInput{
				Name: "calendar",
				URL:  "github:acme/modules?dir=calendar",
				Ref:  "one",
			}
			require.NoError(t, InstallModule(t.Context(), root, m, "", []FlakeInput{old}))
			if tc == "shared" {
				peer := FlakeInput{Name: "peer", URL: "github:acme/peer"}
				require.NoError(
					t,
					InstallModule(t.Context(), root, peer, "", []FlakeInput{old}),
				)
			}
			path := filepath.Join(root, "flake.nix")
			before := readInstallFile(t, path)
			switch tc {
			case "different live pin":
				before = strings.Replace(before, "tools/v1", "tools/user-pin", 1)
			case "different live follows":
				before = strings.Replace(
					before,
					`helper.inputs.nixpkgs.follows = "nixpkgs"`,
					`helper.inputs.nixpkgs.follows = "pkgs"`,
					1,
				)
			case "missing declaration":
				before = strings.Replace(before, "helper.url =", "other.url =", 1)
			}
			require.NoError(t, os.WriteFile(path, []byte(before), 0o640))
			lock := filepath.Join(root, "flake.lock")
			require.NoError(t, os.WriteFile(lock, []byte(`{"original": true}`), 0o640))
			commands := readInstallFile(t, log)
			m.Ref = "two"
			dep := old
			dep.Ref, dep.FollowsNixpkgs = "v2", false
			if tc != "no previous release" {
				dep.PreviousDependency = &old
			}
			seen := false
			err := UpdateModuleWithImports(
				t.Context(),
				root,
				m,
				"",
				"",
				[]FlakeInput{dep},
				func() error {
					seen = true
					current := readInstallFile(t, path)
					require.Contains(t, current, `github:acme/tools/v2?dir=helper`)
					require.Contains(t, current, `github:acme/modules/two?dir=calendar`)
					require.NotContains(t, current, `helper.inputs.nixpkgs.follows`)
					if tc == "validation rollback" {
						return errors.New("dependency failed validation")
					}
					return nil
				},
			)
			if tc == "owned" {
				require.NoError(t, err)
				require.True(t, seen)
				return
			}
			require.Error(t, err)
			require.Equal(t, before, readInstallFile(t, path))
			require.JSONEq(t, `{"original": true}`, readInstallFile(t, lock))
			require.Equal(t, tc == "validation rollback", seen)
			if !seen {
				require.Equal(t, commands, readInstallFile(t, log))
			}
		})
	}
}
