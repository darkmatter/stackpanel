# ==============================================================================
# stackpanel-cli/default.nix
#
# Nix package definition for the StackPanel CLI - a unified Go-based command-line
# tool that includes both the CLI and agent functionality.
#
# The CLI and agent have been merged into a single application at apps/stackpanel-go.
# The agent is now a subcommand: `stackpanel agent`
#
# Build inputs:
#   - Source: apps/stackpanel-go (unified Go module with CLI, agent, and shared packages)
#   - Output: stackpanel binary
#
# Usage:
#   - Run `stackpanel` for interactive TUI
#   - Run `stackpanel agent` to start the local agent server
#   - Run `stackpanel --help` for all available commands
# ==============================================================================
{
  pkgs,
  lib,
  ...
}:
let
  repoRoot = ../../../..;

  # Source path - the unified stackpanel-go app
  srcPath = "${repoRoot}/apps/stackpanel-go";
in
pkgs.buildGoApplication {
  pname = "stackpanel";
  version = "0.1.0";

  src = srcPath;
  pwd = srcPath;
  modules = srcPath + "/gomod2nix.toml";
  subPackages = [ "." ];

  # Skip tests during build (some tests require specific environment)
  doCheck = false;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/darkmatter/stackpanel/apps/stackpanel-go/cmd/cli.Version=0.1.0"
  ];

  # Rename the binary from stackpanel-go to stackpanel
  # Go names the binary after the module's last path component
  postInstall = ''
    mv $out/bin/stackpanel-go $out/bin/stackpanel
  '';

  meta = with lib; {
    description = "Stackpanel unified CLI and agent";
    homepage = "https://github.com/darkmatter/stackpanel";
    license = licenses.mit;
    maintainers = [ ];
  };
}
