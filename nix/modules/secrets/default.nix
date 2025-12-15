# Secrets module - SOPS-based secrets management
# Standalone module - no flake-parts dependency
#
# Uses standard SOPS workflow:
#   sops secrets/dev.yaml
#   sops secrets/production.yaml
#   sops exec-env secrets/dev.yaml './my-script.sh'
#
# Code generation:
#   Define schema in Nix, get typed modules in TS/Python/Go
#
{...}: {
  imports = [./sops.nix ./codegen.nix];
}
