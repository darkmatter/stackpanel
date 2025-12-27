# ==============================================================================
# stackpanel-agent/default.nix
#
# Nix package definition for the StackPanel Agent - a Go-based background
# service that enables web UI integration with local development environments.
#
# The agent acts as a bridge between the StackPanel web interface and local
# services, providing real-time monitoring and control capabilities.
#
# Build inputs:
#   - Source: apps/agent (Go module)
#   - Output: stackpanel-agent binary
#
# Usage: This package is typically included via the stackpanel flake outputs.
# ==============================================================================

{
  pkgs,
  lib,
  ...
}:
let
  repoRoot = ../../..;
in
pkgs.buildGoModule {
  pname = "stackpanel-agent";
  version = "0.1.0";

  src = "${repoRoot}/apps/agent";

  # Nix will vendor deterministically from go.mod/go.sum
  vendorHash = "sha256-o9p/JdqaChJYVahojkFgq/3xiuSZvyXEjpEEo4GT9PU=";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=0.1.0"
  ];

  # Rename binary from 'agent' to 'stackpanel-agent'
  postInstall = ''
    mv $out/bin/agent $out/bin/stackpanel-agent
  '';

  meta = with lib; {
    description = "StackPanel agent for web UI integration";
    homepage = "https://github.com/darkmatter/stackpanel";
    license = licenses.mit;
    maintainers = [];
  };
}

