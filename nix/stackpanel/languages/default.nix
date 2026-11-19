# ==============================================================================
# default.nix
#
# Language toolchain module aggregator.
#
# These modules provide development toolchain setup (packages, env vars, PATH,
# auto-install hooks) for each language.
#
# The shared Go and TypeScript toolchains are core batteries. Other language
# toolchains are installed as individual registry inputs.
#
# This is separate from the app-level modules in modules/go/ and modules/bun/
# which handle building, packaging, and file generation for specific apps.
# Language modules handle the shared toolchain that all apps of that language
# need (e.g., GOPATH, node_modules/.bin in PATH, bun install on shell entry).
# ==============================================================================
{ ... }:
{
  imports = [
    ./go.nix
    ./typescript.nix
  ];
}
