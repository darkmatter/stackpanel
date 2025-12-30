# ==============================================================================
# default.nix
#
# Main entry point for the Stackpanel Nix library. This module aggregates and
# exposes all library functions for creating development shells, managing
# services, and configuring IDE integrations.
#
# Architecture:
#   lib/core/        - Pure logic: ports, services, global-services
#   lib/devshell.nix - mkDevShell function for standalone usage
#   lib/services/    - Per-service helpers (postgres, redis, minio, step)
#   lib/integrations/- IDE/devshell scripts (vscode, starship)
#   lib/*.nix        - Individual helper libraries (paths, theme, codegen, ide)
#
# Usage:
#   let stackpanelLib = import ./lib { inherit pkgs lib; };
#   in stackpanelLib.mkDevShell projectConfig
#   in stackpanelLib.ports.computeBasePort { name = "myproject"; }
#
# Some functions require `pkgs` to be passed; pure functions work without it.
# ==============================================================================
{
  lib,
  pkgs ? null,
}:
let

  # Import devshell library (requires pkgs)
  devshellLib = if pkgs != null then import ../devshell { inherit pkgs lib; } else null;

in
{
  # ============================================================================
  # MAIN ENTRY POINTS
  # ============================================================================

  # Create a development shell from project configuration
  # This is THE primary function both flake and devenv adapters use.
  #
  # Usage:
  #   let shell = stackpanelLib.mkDevShell projectConfig;
  #   in shell.shell  # Ready-to-use mkShell derivation
  #
  mkDevShell =
    if devshellLib != null then
      devshellLib.mkDevShell
    else
      throw "stackpanel.lib.mkDevShell requires pkgs to be passed";

  # ============================================================================
  # CORE LIBRARIES (Pure functions, no pkgs needed)
  # ============================================================================

  # Port computation utilities (pure, no pkgs needed)
  ports = import ./ports.nix { inherit lib; };

  # Path utilities for finding project root and resolving paths
  # Works without pkgs - pure functions and shell script generators
  paths = import ./paths.nix { inherit lib; };

  # Convert attrs to YAML using nixpkgs yaml format
  toYAML =
    attrs:
    if pkgs != null then
      let
        yaml = pkgs.formats.yaml { };
      in
      builtins.readFile (yaml.generate "output.yml" attrs)
    else
      throw "stackpanel.lib.toYAML requires pkgs to be passed";

  # ============================================================================
  # SERVICE LIBRARIES (Require pkgs)
  # ============================================================================

  # AWS cert-auth utilities
  aws =
    if pkgs != null then
      import ./services/aws.nix { inherit pkgs lib; }
    else
      throw "stackpanel.lib.aws requires pkgs to be passed";

  # Network/Step CA utilities
  network =
    if pkgs != null then
      import ./services/step.nix { inherit pkgs lib; }
    else
      throw "stackpanel.lib.network requires pkgs to be passed";

  # Theme utilities (starship, etc.)
  theme =
    if pkgs != null then
      import ./theme.nix { inherit pkgs lib; }
    else
      throw "stackpanel.lib.theme requires pkgs to be passed";

  # Caddy reverse proxy utilities
  caddy =
    if pkgs != null then
      import ./services/caddy.nix { inherit pkgs lib; }
    else
      throw "stackpanel.lib.caddy requires pkgs to be passed";

  # Per-service helpers (postgres, redis, minio)
  services =
    if pkgs != null then
      import ./services { inherit pkgs lib; }
    else
      throw "stackpanel.lib.services requires pkgs to be passed";

  # Global services orchestration
  globalServices =
    if pkgs != null then
      import ./core/global-services.nix { inherit pkgs lib; }
    else
      throw "stackpanel.lib.globalServices requires pkgs to be passed";

  # ============================================================================
  # INTEGRATION LIBRARIES
  # ============================================================================

  # IDE integration utilities (VS Code, etc.)
  integrations =
    if pkgs != null then
      {
        ide = import ./integrations/ide.nix { inherit pkgs lib; };
      }
    else
      throw "stackpanel.lib.integrations requires pkgs to be passed";

  # ============================================================================
  # ADVANCED: Direct access to core modules
  # ============================================================================

  # Full devshell library with all helpers
  devshell =
    if devshellLib != null then
      devshellLib
    else
      throw "stackpanel.lib.devshell requires pkgs to be passed";
}
