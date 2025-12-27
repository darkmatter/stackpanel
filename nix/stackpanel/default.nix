# ==============================================================================
# default.nix
#
# Main entry point for the stackpanel Nix module system.
#
# This file serves as the root import that loads the core module infrastructure.
# All stackpanel features are composed through the core/default.nix imports.
# ==============================================================================
{ ... }: { imports = [ ./core/default.nix ]; }