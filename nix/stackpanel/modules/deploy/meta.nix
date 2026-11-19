# ==============================================================================
# meta.nix - Deploy Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "deploy";
  name = "Deploy";
  description = "Provides deployment tools, deploy-time credential declarations, and per-app NixOS services";
  category = "deployment";
  version = "1.0.0";
  icon = "rocket";
  homepage = "";
  author = "Stackpanel";
  tags = [
    "deploy"
    "nixos"
    "colmena"
    "alchemy"
    "cloudflare"
    "nixos-rebuild"
  ];
  requires = [ ];
  conflicts = [ ];
  features = {
    appModule = true;
    packages = true;
    files = false;
    scripts = false;
    healthchecks = false;
    services = false;
    secrets = true;
    tasks = false;
  };
  priority = 30;
}
