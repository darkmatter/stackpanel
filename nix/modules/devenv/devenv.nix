# Stackpanel devenv module entry point (directory import)
#
# This makes `imports: - stackpanel/nix/modules/devenv` work in `devenv.yaml`.
#
# There are TWO modes of usage:
#
# 1. FULL MODULES (current): Import all the individual modules for full control
#    This is the current behavior - all logic lives in `nix/stackpanel.nix`
#    and the modules under `nix/modules/`.
#
# 2. ADAPTER MODE (new): Use the thin adapter that calls mkDevShell
#    Import `./adapter.nix` for a simplified experience that shares
#    the same core logic with `nix develop`.
#
# For backwards compatibility, we import the full modules by default.
# Users can explicitly import `./adapter.nix` for the unified approach.
#
import ../../stackpanel.nix

