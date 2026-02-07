{
  description = "Stackpanel - Nix-based development environment framework";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    allow-import-from-derivation = "true";
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://darkmatter.cachix.org"
      "https://nixpkgs-python.cachix.org"
    ];
    extra-trusted-public-keys = [
      "darkmatter.cachix.org-1:7R5qAiOVHxDpFy7yguECfC1JqVDgMdckGc+CDKk2pWA="
      "nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.904620";
    git-hooks.url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1.1149";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
    flake-parts.url = "https://flakehub.com/f/hercules-ci/flake-parts/0.1.424";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "https://flakehub.com/f/numtide/treefmt-nix/0.1.512";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    gomod2nix.url = "github:nix-community/gomod2nix";
    gomod2nix.inputs.nixpkgs.follows = "nixpkgs";
    gomod2nix.inputs.flake-utils.follows = "flake-utils";
    bun2nix.url = "github:nix-community/bun2nix";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        withSystem,
        flake-parts-lib,
        ...
      }:
      let
        # Import consolidated exports
        exports = import ./nix/flake/exports.nix {
          inherit
            inputs
            withSystem
            flake-parts-lib
            self
            ;
        };
      in
      {
        systems = exports.supportedSystems;
        debug = true;

        # =============================================================
        # DOGFOODING: Use our own flakeModule
        # =============================================================
        imports = [
          exports.flakeModules.default
        ];

        # =============================================================
        # PER-SYSTEM CONFIG
        # =============================================================
        perSystem =
          {
            config,
            pkgs,
            lib,
            system,
            ...
          }:
          let
            packages = import ./nix/flake/packages.nix { inherit pkgs inputs; };
          in
          {
            _module.args.pkgs = import nixpkgs {
              inherit system;
              overlays = [
                inputs.gomod2nix.overlays.default
                inputs.bun2nix.overlays.default
              ];
            };

            # stackpanel.enable is set in .stackpanel/config.nix
            # The flakeModule auto-loads it and creates devShells.default

            # Packages
            packages = packages;

            # Checks
            checks = {
              stackpanel = config.packages.stackpanel;
              default-package = config.packages.default;
            };
          };

        # =============================================================
        # EXPORTS (for users)
        # =============================================================
        flake = {
          inherit (exports)
            flakeModules
            nixosModules
            lib
            templates
            ;
          # Note: stackpanelOptions is available via:
          #   - inputs.stackpanel.lib.getOptions { inherit pkgs; }  (function)
          #   - .#legacyPackages.${system}.stackpanelOptions  (per-project)
        };
      }
    );
}
