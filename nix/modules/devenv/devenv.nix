# Stackpanel devenv module entry point (directory import)
#
# This makes `imports: - stackpanel/nix/modules/devenv` work in `devenv.yaml`.
#
# Keep this file very small: all real logic lives in `nix/stackpanel.nix`
# and the modules under `nix/modules/`.
import ../../stackpanel.nix


