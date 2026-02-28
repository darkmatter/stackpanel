# ==============================================================================
# meta.nix - Containers Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "containers";
  name = "Containers";
  description = "Container building with nix2container (default) or dockerTools backend";
  category = "infrastructure";
  version = "2.0.0";
  icon = "box";
  homepage = "https://github.com/nlewo/nix2container";
  author = "Stackpanel";

  tags = [
    "container"
    "nix2container"
    "docker"
    "dockerTools"
    "oci"
    "deployment"
  ];

  requires = [ ];
  conflicts = [ ];

  features = {
    files = true;
    scripts = true; # Provides container-build, container-copy, container-run
    healthchecks = false;
    packages = true; # Provides skopeo
    services = false;
    secrets = false;
    tasks = false;
    appModule = true; # Adds per-app container.* options
  };

  priority = 15;
}
