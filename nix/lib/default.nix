# Utility functions for stackpanel modules
#
# These are pure functions that work with any Nix module system
# (flake-parts, devenv, NixOS, etc.)
#
# Usage:
#   let stackpanelLib = import ./lib { inherit pkgs lib; };
#   in stackpanelLib.aws.mkAwsCredScripts { ... }
#
{
  lib,
  pkgs ? null,
}: {
  # Convert attrs to YAML using nixpkgs yaml format
  toYAML = attrs: let
    yaml = pkgs.formats.yaml {};
  in
    builtins.readFile (yaml.generate "output.yml" attrs);

  # AWS cert-auth utilities
  # Requires pkgs to be passed
  aws =
    if pkgs != null
    then import ./aws.nix {inherit pkgs lib;}
    else throw "stackpanel.lib.aws requires pkgs to be passed";

  # Network/Step CA utilities
  # Requires pkgs to be passed
  network =
    if pkgs != null
    then import ./network.nix {inherit pkgs lib;}
    else throw "stackpanel.lib.network requires pkgs to be passed";

  # Theme utilities (starship, etc.)
  # Requires pkgs to be passed
  theme =
    if pkgs != null
    then import ./theme.nix {inherit pkgs lib;}
    else throw "stackpanel.lib.theme requires pkgs to be passed";

  # Caddy reverse proxy utilities
  # Requires pkgs to be passed
  caddy =
    if pkgs != null
    then import ./caddy.nix {inherit pkgs lib;}
    else throw "stackpanel.lib.caddy requires pkgs to be passed";
}
