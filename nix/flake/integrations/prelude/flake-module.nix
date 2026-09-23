# ==============================================================================
# prelude/flake-module.nix — Import Prelude + clear ACME demo defaults
#
# Dynamic catalogue bridge runs in perSystem (see default.nix). Do not eval
# stackpanel or touch `self` here — that causes flake-parts infinite recursion.
# ==============================================================================
{ localInputs }:
{ lib, ... }:
{
  imports = [ localInputs.prelude.flakeModules.default ];

  config.prelude = {
    commands = lib.mkForce { };
    prompt.enable = lib.mkDefault false;
    menu.enable = lib.mkDefault true;
    motd = {
      enable = lib.mkDefault true;
      description.text = lib.mkDefault "";
      # Tagline/subtitle filled by façade packages from stackpanel.prelude.* /
      # .stack/config.nix — keep flake-parts defaults neutral.
      header.tagline = {
        text = lib.mkDefault "devshell";
        subtitle = lib.mkDefault "your environment is ready";
      };
      header.statusHint.links = lib.mkForce [ ];
      header.status = lib.mkForce { };
      env = lib.mkForce [ ];
      recipes = lib.mkForce { };
      links = lib.mkForce [ ];
    };
    docs.pages = lib.mkForce [ ];
    sort.groups = [
      "develop"
      "database"
      "deploy"
      "ops"
    ];
  };
}
