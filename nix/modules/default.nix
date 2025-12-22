# Stackpanel devenv module entry point
#
# This is the main entry point for devenv users.
#
# For devenv.yaml imports:
#   imports:
#     - ./nix/modules/stackpanel.nix
#
# For remote flake imports in devenv.yaml:
#   imports:
#     - stackpanel/nix/modules/stackpanel.nix
#
# For flake-parts + devenv users:
#   devenv.shells.default = {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#   };
#
./stackpanel.nix
