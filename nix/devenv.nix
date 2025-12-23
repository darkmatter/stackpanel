# Stackpanel devenv module entry point
#
# This is the main entry point for devenv users.
# Named devenv.nix to follow devenv's convention for directory imports.
#
# For devenv.yaml imports (directory import):
#   imports:
#     - stackpanel/nix/modules
#
# For flake-parts + devenv users:
#   devenv.shells.default = {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#   };
#
# Export the actual module (a function), not just a path.
import ./stackpanel.nix
