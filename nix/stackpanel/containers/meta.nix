# ==============================================================================
# meta.nix - Containers Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "containers";
  name = "Containers";
  description = "nix2container-based container building via devenv integration";
  category = "infrastructure";
  version = "1.0.0";
  icon = "box";
  homepage = "https://github.com/nlewo/nix2container";
  author = "Stackpanel";

  tags = [
    "container"
    "nix2container"
    "docker"
    "oci"
    "devenv"
    "deployment"
  ];

  requires = [ ];
  conflicts = [ ];

  features = {
    files = false;
    scripts = false;
    healthchecks = false;
    packages = false;
    services = false;
    secrets = false;
    tasks = false;
    appModule = true; # Adds per-app container.* options
  };

  priority = 15;
}
