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
  repoRoot = ../../../..;

  # Source paths - evaluated before being copied to store
  cliSrc = "${repoRoot}/apps/cli";
  goSrc = "${repoRoot}/packages/stackpanel-go";

  # Create composite source with proper directory structure for Go module resolution
  compositeSrc = pkgs.runCommand "stackpanel-cli-src" {
    preferLocalBuild = true;
    allowSubstitutes = false;
  } ''
    mkdir -p $out/apps/cli
    mkdir -p $out/packages/stackpanel-go
    cp -R ${cliSrc}/. $out/apps/cli/
    cp -R ${goSrc}/. $out/packages/stackpanel-go/
  '';
in
pkgs.buildGoModule {
  pname = "stackpanel-cli";
  version = "0.1.0";

  # Use a minimal source tree that contains both the CLI and the local module
  src = compositeSrc;
  modRoot = "apps/cli";

  # Use proxy vendoring to handle the local replace directive
  proxyVendor = true;

  # Nix will vendor deterministically from go.mod/go.sum
  vendorHash = "sha256-7AMYyjWa1o3sxwSPG/PYSUkv6Sezkgxz9vlhjPAKkDM=";

  # Skip tests during build (some tests require specific environment)
  doCheck = false;

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
