# ==============================================================================
# Docker & Container Module
#
# Provides container tooling (skopeo, nix2container) and a shared option
# namespace (stackpanel.docker.images) for other modules to contribute to.
# ==============================================================================
{
  imports = [
    ./module.nix
  ];
}
