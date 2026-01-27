# ==============================================================================
# meta.nix - Docker/Container Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "docker";
  name = "Docker & Containers";
  description = "Container tooling: skopeo, nix2container, image definitions";
  category = "infrastructure";
  version = "1.0.0";
  icon = "container";
  homepage = "https://github.com/nlewo/nix2container";
  author = "Stackpanel";

  tags = [
    "docker"
    "container"
    "oci"
    "skopeo"
    "nix2container"
    "registry"
  ];

  requires = [ ];
  conflicts = [ ];

  features = {
    files = false;
    scripts = false;
    healthchecks = true;
    packages = true;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };

  priority = 20;
}
