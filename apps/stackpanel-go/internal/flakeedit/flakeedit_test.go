package flakeedit

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ============================================================================
// Test: AddInput
// ============================================================================

func TestAddInput_DotNotation(t *testing.T) {
	// Standard flake.nix with dot-notation inputs
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name:           "my-module",
		URL:            "github:author/my-module",
		FollowsNixpkgs: true,
	})
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, `my-module.url = "github:author/my-module";`)
	assert.Contains(t, modified, `my-module.inputs.nixpkgs.follows = "nixpkgs";`)
	// Original content preserved
	assert.Contains(t, modified, `nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";`)
	assert.Contains(t, modified, `flake-utils.url = "github:numtide/flake-utils";`)
	assert.Contains(t, modified, `outputs = { self, nixpkgs, ... }: { };`)
}

func TestAddInput_WithoutFollows(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name:           "process-compose-flake",
		URL:            "github:Platonic-Systems/process-compose-flake",
		FollowsNixpkgs: false,
	})
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, `process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";`)
	assert.NotContains(t, modified, `process-compose-flake.inputs.nixpkgs.follows`)
}

func TestAddInput_EmptyInputsBlock(t *testing.T) {
	source := `{
  inputs = { };

  outputs = { self, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name:           "nixpkgs",
		URL:            "github:NixOS/nixpkgs/nixos-unstable",
		FollowsNixpkgs: false,
	})
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, `nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";`)
}

func TestAddInput_Idempotent(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    my-module.url = "github:author/my-module";
  };

  outputs = { self, nixpkgs, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name:           "my-module",
		URL:            "github:author/my-module",
		FollowsNixpkgs: true,
	})
	require.NoError(t, err)

	// Source should be unchanged
	assert.Equal(t, source, string(result))
}

func TestAddInput_PreservesComments(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # This is a comment about git-hooks
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    # Commented out:
    #sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name:           "devenv",
		URL:            "github:cachix/devenv",
		FollowsNixpkgs: true,
	})
	require.NoError(t, err)

	modified := string(result)
	// Comments preserved
	assert.Contains(t, modified, "# This is a comment about git-hooks")
	assert.Contains(t, modified, "#sops-nix.url")
	// New input added
	assert.Contains(t, modified, `devenv.url = "github:cachix/devenv";`)
	assert.Contains(t, modified, `devenv.inputs.nixpkgs.follows = "nixpkgs";`)
}

func TestAddInput_ConsumerTemplate(t *testing.T) {
	// The standard consumer template uses mkFlake
	source := `{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    stackpanel.url = "github:darkmatter/stackpanel";

    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs =
    { self, nixpkgs, flake-utils, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake { inherit inputs self; }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.hello = pkgs.hello;
      }
    );
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name:           "my-db-module",
		URL:            "github:stackpanel/db-module",
		FollowsNixpkgs: true,
	})
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, `my-db-module.url = "github:stackpanel/db-module";`)
	assert.Contains(t, modified, `my-db-module.inputs.nixpkgs.follows = "nixpkgs";`)
	// Existing inputs preserved
	assert.Contains(t, modified, `stackpanel.url = "github:darkmatter/stackpanel";`)
	assert.Contains(t, modified, `stackpanel-root.flake = false;`)
}

func TestAddInput_MatchesExistingIndentation(t *testing.T) {
	// 2-space indentation
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { self, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name: "foo",
		URL:  "github:bar/foo",
	})
	require.NoError(t, err)

	modified := string(result)
	// Should match the 4-space indent of the existing bindings
	lines := strings.Split(modified, "\n")
	found := false
	for _, line := range lines {
		if strings.Contains(line, `foo.url`) {
			found = true
			// Count leading spaces
			trimmed := strings.TrimLeft(line, " ")
			indent := len(line) - len(trimmed)
			assert.Equal(t, 4, indent, "should match existing 4-space indent")
		}
	}
	assert.True(t, found, "foo.url line should be present")
}

// ============================================================================
// Test: HasInput
// ============================================================================

func TestHasInput(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	assert.True(t, editor.HasInput("nixpkgs"))
	assert.True(t, editor.HasInput("git-hooks"))
	assert.False(t, editor.HasInput("devenv"))
	assert.False(t, editor.HasInput("sops-nix"))
}

// ============================================================================
// Test: AddStackpanelImport
// ============================================================================

func TestAddStackpanelImport_SingleLine(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { self, nixpkgs, ... }@inputs:
    let
      spOutputs = import ./nix/flake/default.nix {
        stackpanelImports = [ ./.stackpanel/modules ];
      };
    in { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddStackpanelImport("inputs.my-module.stackpanelModules.default")
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, "inputs.my-module.stackpanelModules.default")
	// Original import preserved
	assert.Contains(t, modified, "./.stackpanel/modules")
}

func TestAddStackpanelImport_MultiLine(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { self, nixpkgs, ... }@inputs:
    let
      spOutputs = import ./nix/flake/default.nix {
        stackpanelImports = [
          ./.stackpanel/modules
        ];
      };
    in { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddStackpanelImport("inputs.my-module.stackpanelModules.default")
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, "inputs.my-module.stackpanelModules.default")
	assert.Contains(t, modified, "./.stackpanel/modules")
}

func TestAddStackpanelImport_Idempotent(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { self, nixpkgs, ... }@inputs:
    let
      spOutputs = import ./nix/flake/default.nix {
        stackpanelImports = [ ./.stackpanel/modules inputs.my-module.stackpanelModules.default ];
      };
    in { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddStackpanelImport("inputs.my-module.stackpanelModules.default")
	require.NoError(t, err)

	// Source should be unchanged
	assert.Equal(t, source, string(result))
}

func TestAddStackpanelImport_MkFlakePattern(t *testing.T) {
	// The mkFlake function accepts stackpanelImports
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    stackpanel.url = "github:darkmatter/stackpanel";
  };
  outputs = { self, nixpkgs, stackpanel, ... }@inputs:
    stackpanel.lib.mkFlake {
      inherit inputs self;
      stackpanelImports = [ ];
    };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddStackpanelImport("inputs.my-module.stackpanelModules.default")
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, "inputs.my-module.stackpanelModules.default")
}

// ============================================================================
// Test: AddInputAndImport (combined)
// ============================================================================

func TestAddInputAndImport(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    stackpanel.url = "github:darkmatter/stackpanel";
  };
  outputs = { self, nixpkgs, stackpanel, ... }@inputs:
    let
      spOutputs = import ./nix/flake/default.nix {
        stackpanelImports = [ ./.stackpanel/modules ];
      };
    in { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	editResult, err := editor.AddInputAndImport(
		FlakeInput{
			Name:           "my-module",
			URL:            "github:stackpanel/my-module",
			FollowsNixpkgs: true,
		},
		"inputs.my-module.stackpanelModules.default",
	)
	require.NoError(t, err)

	assert.True(t, editResult.InputAdded)
	assert.True(t, editResult.ImportAdded)
	assert.False(t, editResult.InputAlreadyExists)

	modified := string(editResult.Modified)
	assert.Contains(t, modified, `my-module.url = "github:stackpanel/my-module";`)
	assert.Contains(t, modified, `my-module.inputs.nixpkgs.follows = "nixpkgs";`)
	assert.Contains(t, modified, `inputs.my-module.stackpanelModules.default`)
	// Original content preserved
	assert.Contains(t, modified, `nixpkgs.url = "github:NixOS/nixpkgs";`)
	assert.Contains(t, modified, `./.stackpanel/modules`)
}

func TestAddInputAndImport_InputExists(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    my-module.url = "github:stackpanel/my-module";
    my-module.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, ... }@inputs:
    let
      spOutputs = import ./nix/flake/default.nix {
        stackpanelImports = [ ./.stackpanel/modules ];
      };
    in { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	editResult, err := editor.AddInputAndImport(
		FlakeInput{
			Name:           "my-module",
			URL:            "github:stackpanel/my-module",
			FollowsNixpkgs: true,
		},
		"inputs.my-module.stackpanelModules.default",
	)
	require.NoError(t, err)

	assert.False(t, editResult.InputAdded)
	assert.True(t, editResult.InputAlreadyExists)
	assert.True(t, editResult.ImportAdded)

	modified := string(editResult.Modified)
	assert.Contains(t, modified, "inputs.my-module.stackpanelModules.default")
}

func TestAddInputAndImport_NoStackpanelImports(t *testing.T) {
	// A flake.nix without stackpanelImports — import should be silently skipped
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { self, nixpkgs, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	editResult, err := editor.AddInputAndImport(
		FlakeInput{
			Name:           "my-module",
			URL:            "github:author/my-module",
			FollowsNixpkgs: true,
		},
		"inputs.my-module.stackpanelModules.default",
	)
	require.NoError(t, err)

	assert.True(t, editResult.InputAdded)
	assert.False(t, editResult.ImportAdded) // No stackpanelImports found
	assert.Contains(t, string(editResult.Modified), `my-module.url = "github:author/my-module";`)
}

func TestAddInputAndImport_EmptyImportExpr(t *testing.T) {
	// When importExpr is empty, only the input should be added
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { self, nixpkgs, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	editResult, err := editor.AddInputAndImport(
		FlakeInput{
			Name:           "my-module",
			URL:            "github:author/my-module",
			FollowsNixpkgs: false,
		},
		"",
	)
	require.NoError(t, err)

	assert.True(t, editResult.InputAdded)
	assert.False(t, editResult.ImportAdded)
	assert.Contains(t, string(editResult.Modified), `my-module.url = "github:author/my-module";`)
}

// ============================================================================
// Test: Real flake.nix
// ============================================================================

func TestAddInput_RealFlakeNix(t *testing.T) {
	// Tests against the actual project flake.nix structure
	source := []byte(`{
  description = "Stackpanel - Infrastructure toolkit for NixOS and flake-utils";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
  };

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.904620";
    git-hooks.url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1.1149";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    # stackpanel-root contains the absolute path to the project root
    stackpanel-root.url = "path:./.stackpanel-root";
    stackpanel-root.flake = false;
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    let
      exports = import ./nix/flake/exports.nix { inherit inputs self; };
      overlays = exports.lib.requiredOverlays;
      projectRoot = exports.lib.readStackpanelRoot { inherit inputs; };
    in
    flake-utils.lib.eachSystem exports.supportedSystems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        spOutputs = import ./nix/flake/default.nix {
          inherit pkgs inputs self system projectRoot;
          stackpanelImports = [ ./.stackpanel/modules ];
        };
      in
      {
        packages = spOutputs.packages;
        devShells = spOutputs.devShells;
      }
    );
}
`)

	editor, err := NewFlakeEditor(source)
	require.NoError(t, err)
	defer editor.Close()

	// Verify existing inputs are detected
	assert.True(t, editor.HasInput("nixpkgs"))
	assert.True(t, editor.HasInput("git-hooks"))
	assert.True(t, editor.HasInput("agenix"))
	assert.True(t, editor.HasInput("devenv"))
	assert.True(t, editor.HasInput("process-compose-flake"))
	assert.True(t, editor.HasInput("stackpanel-root"))
	assert.False(t, editor.HasInput("sops-nix"))

	// Add a new input and import
	editResult, err := editor.AddInputAndImport(
		FlakeInput{
			Name:           "sops-nix",
			URL:            "github:Mic92/sops-nix",
			FollowsNixpkgs: true,
		},
		"inputs.sops-nix.stackpanelModules.default",
	)
	require.NoError(t, err)

	assert.True(t, editResult.InputAdded)
	assert.True(t, editResult.ImportAdded)

	modified := string(editResult.Modified)

	// New input present
	assert.Contains(t, modified, `sops-nix.url = "github:Mic92/sops-nix";`)
	assert.Contains(t, modified, `sops-nix.inputs.nixpkgs.follows = "nixpkgs";`)

	// Import present
	assert.Contains(t, modified, `inputs.sops-nix.stackpanelModules.default`)

	// All original content preserved
	assert.Contains(t, modified, `description = "Stackpanel - Infrastructure toolkit for NixOS and flake-utils"`)
	assert.Contains(t, modified, `extra-experimental-features = "nix-command flakes"`)
	assert.Contains(t, modified, `nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.904620"`)
	assert.Contains(t, modified, `# stackpanel-root contains the absolute path to the project root`)
	assert.Contains(t, modified, `./.stackpanel/modules`)
	assert.Contains(t, modified, `exports = import ./nix/flake/exports.nix`)
}

// ============================================================================
// Test: Edge cases
// ============================================================================

func TestNewFlakeEditor_InvalidSyntax(t *testing.T) {
	// tree-sitter produces a best-effort tree even for invalid syntax.
	// It can still extract useful information from partially valid input.
	source := `{ inputs = { nixpkgs.url = "github:NixOS/nixpkgs"; }; outputs = let in ??? }`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	// tree-sitter may or may not flag errors depending on the grammar's error recovery.
	// The key invariant is that partial parsing still works:
	assert.True(t, editor.HasInput("nixpkgs"))
	assert.False(t, editor.HasInput("nonexistent"))
}

func TestAddInput_NoInputsBlock(t *testing.T) {
	source := `{ outputs = { self, ... }: { }; }`

	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	_, err = editor.AddInput(FlakeInput{
		Name: "foo",
		URL:  "github:bar/foo",
	})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "could not find")
}

func TestAddInput_SpecialCharactersInURL(t *testing.T) {
	source := `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };
  outputs = { self, ... }: { };
}
`
	editor, err := NewFlakeEditor([]byte(source))
	require.NoError(t, err)
	defer editor.Close()

	result, err := editor.AddInput(FlakeInput{
		Name:           "my-pkg",
		URL:            "https://flakehub.com/f/author/my-pkg/0.1.234",
		FollowsNixpkgs: true,
	})
	require.NoError(t, err)

	modified := string(result)
	assert.Contains(t, modified, `my-pkg.url = "https://flakehub.com/f/author/my-pkg/0.1.234";`)
}

// ============================================================================
// Test: insertAt helper
// ============================================================================

func TestInsertAt(t *testing.T) {
	source := []byte("hello world")

	// Insert at beginning
	result := insertAt(source, 0, []byte(">>> "))
	assert.Equal(t, ">>> hello world", string(result))

	// Insert at end
	result = insertAt(source, uint(len(source)), []byte(" <<<"))
	assert.Equal(t, "hello world <<<", string(result))

	// Insert in middle
	result = insertAt(source, 5, []byte(" beautiful"))
	assert.Equal(t, "hello beautiful world", string(result))
}
