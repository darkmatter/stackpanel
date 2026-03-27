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
    files = false;
    scripts = true;
    healthchecks = true;
    packages = true;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };
  priority = 35;

  # Configuration boilerplate injected into user's config.nix when module is installed
  configBoilerplate = ''
    # Colmena - NixOS fleet deployment orchestration
    # See: https://colmena.cli.rs/
    # colmena = {
    #   enable = true;
    #   flake = ".#colmena";
    #   parallel = 4;
    #   buildOnTarget = false;
    # };
  '';
}
