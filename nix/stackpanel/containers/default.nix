# ==============================================================================
# Containers Module
#
# Provides nix2container-based container building via devenv's containers module.
# This enables reproducible OCI container images without a Docker daemon.
#
# Usage:
#   stackpanel.apps.web.container.enable = true;
#   # Then: devenv container copy web
# ==============================================================================
{
  imports = [
    ./module.nix
  ];
}
