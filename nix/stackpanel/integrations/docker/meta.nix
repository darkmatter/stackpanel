# ==============================================================================
# meta.nix - Container Tooling Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
#
# NOTE: This module provides container TOOLING (skopeo, image refs).
# For container BUILDING, use the containers module instead.
# ==============================================================================
{
  id = "docker";
  name = "Container Tooling";
  description = "Container tooling (skopeo) for OCI image operations";
  category = "infrastructure";
  version = "2.0.0";
  icon = "package";
  homepage = "https://github.com/containers/skopeo";
  author = "Stackpanel";

  tags = [
    "docker"
    "container"
    "oci"
    "skopeo"
    "registry"
  ];

  requires = [ ];
  conflicts = [ ];

  features = {
    files = false;
    scripts = true; # Provides image-inspect, image-copy, etc.
    healthchecks = true;
    packages = true; # Provides skopeo
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };

  priority = 25;
}
