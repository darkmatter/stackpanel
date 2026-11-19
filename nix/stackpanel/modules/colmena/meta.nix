# ==============================================================================
# meta.nix - Colmena Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "colmena";
  name = "Colmena";
  description = "NixOS fleet deployment orchestration with configurable colmena flags";
  category = "deployment";
  version = "1.0.0";
  icon = "ship";
  homepage = "https://colmena.cli.rs/";
  author = "Stackpanel";
  tags = [
    "colmena"
    "nixos"
    "deployment"
    "fleet"
    "orchestration"
  ];
  requires = [ ];
  conflicts = [ ];
  features = {
    files = true; # Generates the hive and machine inventory
    scripts = true;
    healthchecks = true;
    packages = true;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };
  priority = 35;
}
