# ==============================================================================
# default.nix - Turbo Module Entry Point
#
# Turborepo task orchestration with turbo.json generation.
#
# Components:
# - meta.nix: Static metadata for discovery
# - module.nix: Options, task compilation, file generation
# - ui.nix: UI panel definitions
#
# Usage:
#   stackpanel.tasks = {
#     build = { exec = "npm run build"; outputs = [ "dist/**" ]; };
#     dev = { persistent = true; cache = false; };
#   };
# ==============================================================================
{
  ...
}:
{
  imports = [
    ./module.nix
    ./packages.nix
    ./ui.nix
  ];
}
