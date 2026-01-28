# ==============================================================================
# meta.nix - Docker/Dockerfile Fallback Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
#
# NOTE: This is a FALLBACK module for Dockerfile generation.
# For nix2container (recommended), use the containers module instead.
# ==============================================================================
{
  id = "docker";
  name = "Dockerfile Fallback";
  description = "Dockerfile generation fallback for CI systems that cannot use nix2container";
  category = "infrastructure";
  version = "1.0.0";
  icon = "file-text";
  homepage = "https://docs.docker.com/reference/dockerfile/";
  author = "Stackpanel";

  tags = [
    "docker"
    "dockerfile"
    "container"
    "oci"
    "skopeo"
    "fallback"
  ];

  requires = [ ];
  conflicts = [ ];

  features = {
    files = true; # Generates Dockerfiles
    scripts = false;
    healthchecks = true;
    packages = true; # Provides skopeo
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };

  priority = 25; # Lower priority than containers module (15)
}
