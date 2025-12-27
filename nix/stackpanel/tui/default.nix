# ==============================================================================
# default.nix
#
# TUI (Terminal User Interface) module aggregator.
#
# This file serves as the entry point for TUI-related functionality,
# currently importing the theme module for terminal customization.
# Future TUI features (interactive menus, dashboards) would be added here.
# ==============================================================================
{ ... }: { imports = [ ./theme.nix ]; }