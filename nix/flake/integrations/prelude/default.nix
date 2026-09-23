# ==============================================================================
# integrations/prelude — Prelude shell DX (MOTD, menu/x, docs)
#
# stackpanel.motd.* is a contribution façade: mapped via facade.nix into a
# prelude-shaped fragment, then built into packages (build.nix). Full
# config.prelude cannot be set from perSystem — Prelude only declares
# perSystem.prelude.commands; motd/docs/menu live at top-level (cleared of
# ACME demos in flake-module.nix). Packages are mkForce'd from the façade
# until Prelude generators reliably honor late top-level merges from eval.
# ==============================================================================
{
  localFlake,
  localInputs,
  inputs,
}: # inputs unused; kept for interface uniformity
let
  available = localInputs ? prelude;

  mkFacade =
    {
      lib,
      spConfig,
      self,
      ...
    }:
    import ../../../stackpanel/modules/prelude/facade.nix { inherit lib; } {
      name = spConfig.name or "project";
      github = spConfig.github or "";
      motd =
        spConfig.motd or {
          commands = [ ];
          features = [ ];
          hints = [ ];
        };
      preludeCfg = spConfig.prelude or { };
      projectRoot = self;
    };

  mkBuilt =
    ctx@{
      pkgs,
      lib,
      spConfig,
      ...
    }:
    if !(available && (spConfig.prelude.enable or false)) then
      null
    else
      let
        facade = mkFacade ctx;
        unstablePkgs =
          if pkgs.stdenv.hostPlatform.system == "x86_64-darwin" then
            pkgs
          else
            import localInputs.nixpkgs-unstable {
              inherit (pkgs.stdenv.hostPlatform) system;
            };
        built = import ../../../stackpanel/modules/prelude/build.nix {
          inherit pkgs lib;
          preludeLib = localInputs.prelude.lib;
          inherit facade;
          buildGoModule = unstablePkgs.buildGoModule;
        };
      in
      {
        inherit facade;
        inherit (built)
          prelude
          motd
          menu
          docs
          ;
      };
in
{
  inherit available;

  flakeModules = if available then [ (import ./flake-module.nix { inherit localInputs; }) ] else [ ];

  extraShellPackages =
    ctx:
    let
      built = mkBuilt ctx;
    in
    if built != null then [ built.prelude ] else [ ];

  perSystem =
    ctx@{ lib, ... }:
    let
      built = mkBuilt ctx;
    in
    lib.mkIf (built != null) {
      # System-local catalogue merge (only perSystem.prelude.* option Prelude
      # declares). Motd chrome / docs pages come from build.nix packages.
      prelude.commands = built.facade.commands or { };
      packages.prelude = lib.mkForce built.prelude;
      packages.motd = lib.mkForce built.motd;
      packages.menu = lib.mkIf (built.menu != null) (lib.mkForce built.menu);
      packages.docs = lib.mkIf (built.docs != null) (lib.mkForce built.docs);
    };
}
