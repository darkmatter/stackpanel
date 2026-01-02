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
#   - Source: apps/agent (Go module) + packages/stackpanel-go (shared Go library)
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
  repoRoot = ../../../..;

  # Source paths - evaluated before being copied to store
  agentSrc = "${repoRoot}/apps/agent";
  goSrc = "${repoRoot}/packages/stackpanel-go";

  # Create composite source with proper directory structure for Go module resolution
  compositeSrc = pkgs.runCommand "stackpanel-agent-src" {
    preferLocalBuild = true;
    allowSubstitutes = false;
  } ''
    mkdir -p $out/apps/agent
    mkdir -p $out/packages/stackpanel-go
    cp -R ${agentSrc}/. $out/apps/agent/
    cp -R ${goSrc}/. $out/packages/stackpanel-go/
  '';
in
pkgs.buildGoApplication {
  pname = "stackpanel-agent";
  version = "0.1.0";

  # Use a minimal source tree that contains both the agent and the local module
  src = compositeSrc;
  pwd = compositeSrc + "/apps/agent";  # Tell gomod2nix where to find go.mod
  modules = compositeSrc + "/apps/agent/gomod2nix.toml";
  sourceRoot = "stackpanel-agent-src/apps/agent";  # Build from this subdirectory
  subPackages = [ "." ];  # Build from pwd (apps/agent)

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

