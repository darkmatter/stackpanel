# ==============================================================================
# default.nix
#
# Language toolchain module aggregator.
#
# These modules provide development toolchain setup (packages, env vars, PATH,
# auto-install hooks) for each language. They replace devenv's languages.*
# modules with native stackpanel implementations that write directly to
# stackpanel.devshell.{packages, env, hooks}.
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
    ./javascript.nix
    ./typescript.nix
  ];
}
