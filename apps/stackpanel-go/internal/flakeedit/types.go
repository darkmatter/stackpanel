package flakeedit

// FlakeInput represents a flake input declaration to insert.
//
// Example:
//
//	my-module = {
//	  url = "github:author/my-module";
//	  inputs.nixpkgs.follows = "nixpkgs";
//	};
//
// The editor writes this as dot-notation (`my-module.url = ...`) to preserve
// compatibility with tree-sitter node offsets used by the existing parser.
type FlakeInput struct {
	// Name is the input key in the flake `inputs` attrset.
	Name string
	// URL is the flake URL value for `<name>.url`.
	URL string
	// FollowsNixpkgs adds `<name>.inputs.nixpkgs.follows = "nixpkgs"`.
	FollowsNixpkgs bool
}

// EditResult describes what changed in a combined AddInputAndImport operation.
type EditResult struct {
	// Modified is the modified source.
	Modified []byte
	// InputAdded is true when a new flake input was inserted.
	InputAdded bool
	// ImportAdded is true when a new stackpanel import entry was inserted.
	ImportAdded bool
	// InputAlreadyExists is true when the input was already present.
	InputAlreadyExists bool
}
