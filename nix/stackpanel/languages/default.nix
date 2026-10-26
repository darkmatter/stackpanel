# ==============================================================================
# default.nix
#
# Language toolchain module aggregator.
#
# These modules provide development toolchain setup (packages, env vars, PATH,
# auto-install hooks) for each language.
#
# devenv/ is the cachix/devenv language set, copied in-tree and retargeted at
# stackpanel.languages. go.nix and typescript.nix stay beside it: those copies
# already include Darwin CGO and IDE paths.
#
# This is separate from the app-level modules in modules/go/ and modules/bun/
# which handle building, packaging, and file generation for specific apps.
# Language modules handle the shared toolchain that all apps of that language
# need (e.g., GOPATH, node_modules/.bin in PATH, bun install on shell entry).
# ==============================================================================
{ ... }:
{
  imports = [
    ./devenv
    ./go.nix
    ./typescript.nix
  ];
}
