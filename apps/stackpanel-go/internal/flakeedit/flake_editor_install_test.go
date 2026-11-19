package flakeedit

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// Exercise the public file operations with the real parser. Only the external
// network-dependent Nix process is substituted; it writes its requested lock.
func installFixture(t *testing.T, source string) (root, log string) {
	t.Helper()
	root, bin := t.TempDir(), t.TempDir()
	log = filepath.Join(bin, "commands")
	require.NoError(
		t,
		os.WriteFile(filepath.Join(root, "flake.nix"), []byte(source), 0o640),
	)
	require.NoError(t, os.WriteFile(filepath.Join(bin, "nix"), []byte(`#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$NIX_TEST_LOG"
while [ "$1" != --output-lock-file ]; do shift; done
printf '%s\n' '{"nodes":{"root":{"inputs":{}}},"root":"root","version":7}' > "$2"
`), 0o755))
	t.Setenv("NIX_TEST_LOG", log)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	return root, log
}

func readInstallFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	require.NoError(t, err)
	return string(b)
}

func TestRegistryModuleLifecycle(t *testing.T) {
	const templateDir = "../../../../nix/flake/templates"
	const alias = `{ inputs.stackpanel.url = "github:darkmatter/stackpanel";
 outputs = all@{ stackpanel, ... }: stackpanel.lib.mkFlake { inputs = all; self = all.self; autoImportInputs = false; }; }`
	const parts = `{ inputs.flake-parts.url = "github:hercules-ci/flake-parts";
 inputs.stackpanel.url = "github:darkmatter/stackpanel";
 outputs = all@{ flake-parts, ... }: flake-parts.lib.mkFlake { inputs = all; } { imports = [ all.stackpanel.flakeModules.default ]; %s }; }`
	for _, tc := range []struct{ name, source, importPath, expr string }{
		{"default auto discovery", readInstallFile(t, filepath.Join(templateDir, "default/flake.nix")), "stackpanelModules.default", ""},
		{"minimal auto discovery", readInstallFile(t, filepath.Join(templateDir, "minimal/flake.nix")), "", ""},
		{"custom mkFlake output", readInstallFile(t, filepath.Join(templateDir, "minimal/flake.nix")), "custom.module", "inputs.demo.custom.module"},
		{"disabled discovery", alias, "", "all.demo.stackpanelModules.default"},
		{"flake parts create", strings.Replace(parts, "%s", "# keep this\n", 1), "", "all.demo.stackpanelModules.default"},
		{"flake parts dotted", strings.Replace(parts, "%s", "stackpanel.imports = [ ./keep.nix ];", 1), "custom.module", "all.demo.custom.module"},
		{"flake parts nested", strings.Replace(parts, "%s", "stackpanel = { imports = [ ./keep.nix ]; };", 1), "custom.module", "all.demo.custom.module"},
		{"flake parts module lambda", strings.Replace(strings.Replace(parts, "} { imports", "} ({ inputs, ... }: { imports", 1), "%s };", "stackpanel.imports = []; });", 1), "", "inputs.demo.stackpanelModules.default"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root, log := installFixture(t, tc.source)
			ctx := context.Background()
			file := filepath.Join(root, "flake.nix")
			input := FlakeInput{
				Name: "demo",
				URL:  "github:acme/modules?dir=modules/demo",
				Ref:  "v1",
			}
			deps := []FlakeInput{
				{Name: "helper", URL: "github:acme/helper", FollowsNixpkgs: true},
			}
			require.NoError(t, InstallModule(ctx, root, input, tc.importPath, deps))
			installed := readInstallFile(t, file)
			require.Contains(t, installed, "dir=")
			require.Contains(t, installed, "v1")
			require.Contains(t, installed, `helper.inputs.nixpkgs.follows = "nixpkgs";`)
			require.NotContains(t, installed, "demo.inputs.nixpkgs.follows")
			if tc.expr == "" {
				require.NotContains(t, installed, "stackpanelImports =")
			} else {
				require.Equal(t, 1, strings.Count(installed, tc.expr))
			}
			commands := readInstallFile(t, log)
			require.Contains(t, commands, "flake lock --update-input demo")
			require.NoError(t, InstallModule(ctx, root, input, tc.importPath, deps))
			require.Equal(t, installed, readInstallFile(t, file))
			require.Equal(t, commands, readInstallFile(t, log))

			input.Ref = "v2"
			require.NoError(t, UpdateModuleWithImports(ctx, root, input, tc.importPath, tc.importPath, deps))
			updated := readInstallFile(t, file)
			require.Contains(t, updated, "v2")
			require.NotContains(t, updated, "v1")
			require.Contains(t, readInstallFile(t, log), "flake update demo")
			require.NoError(t, UninstallRegistryModule(ctx, root, input, tc.importPath))
			removed := readInstallFile(t, file)
			require.NotContains(t, removed, "demo")
			require.Contains(t, removed, `helper.url = "github:acme/helper";`)
			for _, keep := range []string{"./keep.nix", "# keep this"} {
				if strings.Contains(tc.source, keep) {
					require.Contains(t, removed, keep)
				}
			}
			commands = readInstallFile(t, log)
			require.NoError(t, UninstallRegistryModule(ctx, root, input, tc.importPath))
			require.Equal(t, commands, readInstallFile(t, log))
		})
	}
}

func TestRegistryInstallFailsWithoutWriting(t *testing.T) {
	const outputs = `outputs = { stackpanel, ... }@inputs: stackpanel.lib.mkFlake { inherit inputs; };`
	module := FlakeInput{Name: "demo", URL: "github:acme/demo"}
	for _, tc := range []struct {
		name, source, path string
		input              FlakeInput
		deps               []FlakeInput
	}{
		{"parse error", `{ inputs = {}; ` + outputs, "", module, nil},
		{"unsupported outputs", `{ inputs = {}; outputs = inputs: {}; }`, "", module, nil},
		{"module collision", `{ inputs.demo.url = "github:other/demo"; ` + outputs + ` }`, "", module, nil},
		{"implicit input", `{ inputs = {}; outputs = { stackpanel, demo, ... }@inputs: stackpanel.lib.mkFlake { inherit inputs; }; }`, "", module, nil},
		{"pinned input", `{ inputs.demo.url = "github:acme/demo/user-pin"; ` + outputs + ` }`, "", module, nil},
		{"shadowed scope", `{ inputs = {}; outputs = { stackpanel, ... }@inputs: let stackpanel = other; in stackpanel.lib.mkFlake { inherit inputs; }; }`, "", module, nil},
		{"computed input", `{ inputs.demo.url = foo; ` + outputs + ` }`, "", module, nil},
		{"source override", `{ inputs.demo = { url = "github:acme/demo"; follows = "other"; }; ` + outputs + ` }`, "", module, nil},
		{"non-url input", `{ inputs.demo.follows = "other"; ` + outputs + ` }`, "", module, nil},
		{"transitive collision", `{ inputs = { helper = { url = "github:user/helper"; }; }; ` + outputs + ` }`, "", module, []FlakeInput{{Name: "helper", URL: "github:registry/helper"}}},
		{"interpolation", `{ inputs = {}; ` + outputs + ` }`, "", FlakeInput{Name: "demo", URL: `github:acme/${throw "x"}`}, nil},
		{"injected ref", `{ inputs = {}; ` + outputs + ` }`, "", FlakeInput{Name: "demo", URL: module.URL, Ref: `v1"; bad = 1; #`}, nil},
		{"injected name", `{ inputs = {}; ` + outputs + ` }`, "", FlakeInput{Name: `a.b`, URL: module.URL}, nil},
		{"injected path", `{ inputs = {}; ` + outputs + ` }`, "default ]; x = [", module, nil},
		{"input-qualified path", `{ inputs = {}; ` + outputs + ` }`, "inputs.demo.stackpanelModules.default", module, nil},
		{"inherited conflict", `{ inputs = { inherit (foo) demo; }; ` + outputs + ` }`, "", module, nil},
		{"dynamic key", `{ inputs = { ${name} = {}; }; ` + outputs + ` }`, "", module, nil},
		{"dynamic imports", `{ inputs = {}; outputs = { stackpanel, ... }@inputs: stackpanel.lib.mkFlake { inherit inputs; autoImportInputs = false; stackpanelImports = imports; }; }`, "", module, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root, log := installFixture(t, tc.source)
			require.Error(
				t,
				InstallModule(context.Background(), root, tc.input, tc.path, tc.deps),
			)
			require.Equal(t, tc.source, readInstallFile(t, filepath.Join(root, "flake.nix")))
			require.NoFileExists(t, log)
			require.NoFileExists(t, filepath.Join(root, "flake.lock"))
		})
	}
}

func TestRegistryUpdateChecksLiveSourceAndMigratesImport(t *testing.T) {
	const source = `{
  inputs = {
    "demo" = { # owner's comment
      url = "github:acme/catalog/v1?dir=demo"; # pin
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helper.url = "github:acme/helper";
  };
  outputs = { stackpanel, ... }@inputs: stackpanel.lib.mkFlake {
    inherit inputs;
    autoImportInputs = false;
    stackpanelImports = [ ./keep.nix inputs.demo.old.module /* keep inline */ ];
  };
}`
	root, log := installFixture(t, source)
	ctx := context.Background()
	file := filepath.Join(root, "flake.nix")
	input := FlakeInput{Name: "demo", URL: "github:acme/catalog?dir=other", Ref: "v2"}
	require.Error(
		t,
		UpdateModuleWithImports(ctx, root, input, "old.module", "new.module", nil),
	) // different subdirectory is a different source
	require.Error(t, UninstallRegistryModule(ctx, root, input, "old.module"))
	require.Equal(t, source, readInstallFile(t, file))
	require.NoFileExists(t, log)
	input.PreviousURL = "github:acme/catalog?dir=demo"
	deps := []FlakeInput{
		{Name: "helper", URL: "github:acme/helper", FollowsNixpkgs: true},
	}
	require.NoError(
		t,
		UpdateModuleWithImports(ctx, root, input, "old.module", "new.module", deps),
	)
	updated := readInstallFile(t, file)
	require.NotContains(t, updated, "old.module")
	require.Equal(
		t,
		1,
		strings.Count(updated, `inputs.nixpkgs.follows = "nixpkgs";`),
	) // only helper remains
	require.Equal(t, 1, strings.Count(updated, "helper.url"))
	for _, want := range []string{"github:acme/catalog/v2?dir=other", "inputs.demo.new.module", "helper.inputs.nixpkgs.follows", "/* keep inline */", "./keep.nix"} {
		require.Contains(t, updated, want)
	}
	input.PreviousURL = ""
	require.NoError(t, UninstallRegistryModule(ctx, root, input, "new.module"))
	removed := readInstallFile(t, file)
	require.NotContains(t, removed, `"demo"`)
	require.NotContains(t, removed, "inputs.demo.")
	for _, keep := range []string{"# owner's comment", "# pin", "/* keep inline */", "./keep.nix", "helper.url"} {
		require.Contains(t, removed, keep)
	}
}

func TestPinnedModuleURL(t *testing.T) {
	const rev = "1234567890abcdef1234567890abcdef12345678"
	for _, tc := range []struct{ src, ref, revision, want string }{
		{"github:acme/repo?dir=modules/demo", "v2", "", "github:acme/repo/v2?dir=modules/demo"},
		{"github:acme/repo/main?dir=demo", "v2", rev, "github:acme/repo/" + rev + "?dir=demo"},
		{"git+https://git.acme.test/repo?ref=v1&dir=demo", "v2", rev, "git+https://git.acme.test/repo?dir=demo&ref=v2&rev=" + rev},
		{"https://acme.test/archive?ref=v2", "", "", "https://acme.test/archive?ref=v2"},
	} {
		t.Run(tc.src, func(t *testing.T) {
			got, err := (FlakeInput{Name: "demo", URL: tc.src, Ref: tc.ref, Rev: tc.revision}).PinnedURL()
			require.NoError(t, err)
			require.Equal(t, tc.want, got)
		})
	}
}

func TestDeleteModuleSettingsKeepsSiblingsAndComments(t *testing.T) {
	for _, src := range []string{
		`{ apps = {}; modules.demo.enable = true; /* keep */ modules.demo.opt = 42; modules.peer.enable = true; }`,
		`{ config, ... }: { modules = { demo = { opt = 42; /* keep */ }; peer.enable = true; }; apps = {}; }`,
	} {
		out, err := DeleteNixPath([]byte(src), []string{"modules", "demo"})
		require.NoError(t, err)
		require.NotContains(t, string(out), "demo")
		for _, keep := range []string{"apps = {};", "/* keep */", "peer.enable = true;"} {
			require.Contains(t, string(out), keep)
		}
	}
}

func TestModuleSettingsTreatKeysAsLiterals(t *testing.T) {
	key := `demo.${notNixCode}`
	path := []string{key, "enable"}
	modified, err := PatchNixPath([]byte(`{ peer = 1; }`), path, "true")
	require.NoError(t, err)
	require.Contains(t, string(modified), `"demo.\${notNixCode}"`)
	present, err := HasTopLevelBinding(modified, key)
	require.NoError(t, err)
	require.True(t, present)
	removed, err := DeleteNixPath(modified, []string{key})
	require.NoError(t, err)
	require.NotContains(t, string(removed), "notNixCode")
	require.Contains(t, string(removed), "peer = 1;")
}

func TestModuleImportPath(t *testing.T) {
	const before = `{ inputs.demo.url = "github:acme/demo"; outputs = {stackpanel, ...}@all: assert true; stackpanel.lib.mkFlake { inputs = all; `
	for _, tc := range []struct{ label, options, want string }{
		{"automatic default", "", "stackpanelModules.default"},
		{"explicit custom", `stackpanelImports = [ ./keep.nix all.demo.custom."name.with.dots" ];`, `custom."name.with.dots"`},
		{"disabled discovery", `autoImportInputs = false;`, ""},
		{"ambiguous", `stackpanelImports = [ all.demo.one all.demo.two ];`, ""},
		{"computed", `stackpanelImports = [ all.demo.${dynamic} ];`, ""},
	} {
		t.Run(tc.label, func(t *testing.T) {
			e, err := NewFlakeEditor([]byte(before + tc.options + ` }; }`))
			require.NoError(t, err)
			defer e.Close()
			got, err := e.ModuleImportPath("demo")
			if tc.want == "" {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			require.Equal(t, tc.want, got)
		})
	}
}
