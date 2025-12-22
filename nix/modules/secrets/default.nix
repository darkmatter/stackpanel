# Secrets module - SOPS/vals-based secrets management
# Standalone module - no flake-parts dependency
#
# Uses standard SOPS workflow:
#   sops secrets/dev.yaml
#   sops secrets/production.yaml
#   sops exec-env secrets/dev.yaml './my-script.sh'
#
# Or with vals for multi-backend support:
#   vals eval -f secrets.template.yaml
#   vals exec -f secrets.template.yaml -- ./my-script.sh
#
# Code generation:
#   Define schema in Nix, get typed modules in TS/Python/Go
#
{...}: {
  imports = [./secrets.nix ./codegen.nix];
}
