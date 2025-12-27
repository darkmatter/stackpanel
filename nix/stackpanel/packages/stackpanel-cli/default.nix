# ==============================================================================
# stackpanel-cli/default.nix
#
# Nix package definition for the StackPanel CLI - a Go-based command-line tool
# for managing local development services and environments.
#
# This package creates a composite source derivation that includes both the CLI
# application and the shared stackpanel-go module, allowing proper Go module
# resolution during the build.
#
# Build inputs:
#   - Source: apps/cli (Go module) + packages/stackpanel-go (shared Go library)
#   - Output: stackpanel binary (renamed from 'cli')
#
# Usage: Run `stackpanel` commands to manage development services, certificates,
# Caddy configuration, and more.
# ==============================================================================

{
  pkgs,
  lib,
  ...
}:
let
  stackpanelGoSrc = pkgs.callPackage ../stackpanel-go {};
in
let
  repoRoot = ../../..;
  compositeSrc = pkgs.runCommand "stackpanel-cli-src" { } ''
    mkdir -p $out/apps/cli
    mkdir -p $out/packages/stackpanel-go
    cp -R ${repoRoot}/apps/cli/* $out/apps/cli/
    cp -R ${repoRoot}/packages/stackpanel-go/* $out/packages/stackpanel-go/
  '';
in
pkgs.buildGoModule {
  pname = "stackpanel-cli";
  version = "0.1.0";

  # Use a minimal source tree that contains both the CLI and the local module
  src = compositeSrc;
  modRoot = "apps/cli";


  # Nix will vendor deterministically from go.mod/go.sum
  vendorHash = "sha256-orEq07AQsCXLLn7bLBZQMA+KXzz3NPuFt4Uh1O8KjaI=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/darkmatter/stackpanel/cli/cmd.Version=0.1.0"
  ];

  # Rename the binary from "cli" to "stackpanel"
  postInstall = ''
    mv $out/bin/cli $out/bin/stackpanel
  '';

  meta = with lib; {
    description = "Stackpanel development CLI";
    homepage = "https://github.com/darkmatter/stackpanel";
    license = licenses.mit;
    maintainers = [];
  };
}
