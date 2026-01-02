{
  pkgs,
  lib,
  ...
}:
let
  root = ../../../..;
  mkGoInstall = name: {
    description = "Install go dependencies for ${name}";
    script = ''
      set -euo pipefail
      cd ${pkgs.stackpanel.root}/apps/${name}
      ${pkgs.go}/bin/go mod download
    '';
  };
in
{
  tasks."stackpanel-go:install" = {
    description = "Install Go dependencies for StackPanel Go projects";
    script = ''
      set -euo pipefail
      cd ${pkgs.stackpanel.root}/apps/agent
      ${pkgs.go}/bin/go mod download
    '';
  };
}
