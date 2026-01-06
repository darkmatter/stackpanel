{
  pkgs,
  lib,
  ...
}:
{
  tasks."stackpanel-go:install" = {
    description = "Install Go dependencies for StackPanel Go projects";
    script = ''
      set -euo pipefail
      cd ${pkgs.stackpanel.root}/apps/stackpanel-go
      ${pkgs.go}/bin/go mod download
    '';
  };
}
