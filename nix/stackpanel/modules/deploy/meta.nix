# ==============================================================================
# meta.nix - Deploy Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "deploy";
  name = "Deploy";
  description = "Deploy apps to NixOS servers (colmena, nixos-rebuild) and Cloudflare Workers (alchemy)";
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
    packages = false;
    files = false;
    scripts = false;
    healthchecks = false;
    services = false;
    secrets = false;
    tasks = false;
  };
  priority = 30;
}
