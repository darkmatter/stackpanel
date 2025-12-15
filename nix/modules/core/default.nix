# Core module - base options and file generation system
# Standalone module - no flake-parts dependency
{...}: {
  imports = [./options.nix ./generate.nix ./datadir.nix];
}
