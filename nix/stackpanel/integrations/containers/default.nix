# ==============================================================================
# Containers Module
#
# Builds OCI container images using nix2container (default) or dockerTools.
#
# Backend selection:
#   stackpanel.containers.settings.backend = "nix2container"; # or "dockerTools"
#
# Per-app container configuration:
#   stackpanel.apps.web.container.enable = true;
#
# Commands:
#   container-build <name>    Build container image
#   container-copy <name>     Build + push to registry
#   container-run <name>      Build + run locally
# ==============================================================================
{
  imports = [
    ./module.nix
    ./builder.nix
    ./ui.nix
  ];
}
