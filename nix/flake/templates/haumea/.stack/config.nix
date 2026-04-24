# ==============================================================================
# config.nix
#
# Stackpanel project configuration (root scalars only).
#
# This template uses the haumea tree layout: each top-level config key lives
# in its own file under .stack/config/ (e.g. .stack/config/theme.nix,
# .stack/config/ide.nix). The tree overlays on top of this file at load time.
#
# See: https://stackpanel.dev/docs/config-layouts
# ==============================================================================
{
  enable = true;
  name = "my-project";
  github = "owner/repo";
  # debug = false;
}
