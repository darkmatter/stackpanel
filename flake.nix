{
  description = "Stackpanel - Infrastructure toolkit for NixOS and flake-utils";

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
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
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
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
    # stackpanel-root contains the absolute path to the project root
    # Created by .envrc: echo "$PWD" > .stackpanel-root
    # This enables pure evaluation (nix flake check, nix flake show)
    # stackpanel-root.url = "path:./.stackpanel-root";
    # stackpanel-root.flake = false;
		#inputs.sops-nix.url = "github:Mic92/sops-nix";
		#inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    let
      # Import consolidated exports
      exports = import ./nix/flake/exports.nix { inherit inputs self; };

      # Overlays for nixpkgs
      overlays = exports.lib.requiredOverlays;

      # Global outputs (nixosModules, nixosConfigurations, colmenaHive).
      # Evaluated once using lib only -- no per-system pkgs instantiation.
      globalOutputs = import ./nix/flake/global-outputs.nix {
        inherit inputs self;
        stackpanelImports =
          if builtins.pathExists (self + "/.stack/nix") then [ (self + "/.stack/nix") ]
          else if builtins.pathExists (self + "/.stackpanel/nix") then [ (self + "/.stackpanel/nix") ]
          else if builtins.pathExists (self + "/.stackpanel/modules") then [ (self + "/.stackpanel/modules") ]
          else [ ];
      };
    in
    # Per-system outputs
    flake-utils.lib.eachSystem exports.supportedSystems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Stackpanel packages (CLI, etc.)
        packages = import ./nix/flake/packages.nix { inherit pkgs inputs; };

        # Stackpanel outputs (devShells, checks, apps, legacyPackages)
        spOutputs = import ./nix/flake/per-system-outputs.nix {
          inherit
            pkgs
            inputs
            self
            system
            ;
          stackpanelImports =
            if builtins.pathExists (self + "/.stack/nix") then [ (self + "/.stack/nix") ]
            else if builtins.pathExists (self + "/.stackpanel/nix") then [ (self + "/.stackpanel/nix") ]
            else if builtins.pathExists (self + "/.stackpanel/modules") then [ (self + "/.stackpanel/modules") ]
            else [ ];
        };
      in
      {
        # Merge stackpanel packages with outputs packages
        packages = packages // (spOutputs.packages or { });

        # DevShells from stackpanel
        devShells = spOutputs.devShells;

        # Checks - include package checks plus stackpanel checks
        checks = {
          stackpanel = packages.stackpanel;
          default-package = packages.default;
        }
        // spOutputs.checks;

        # Apps from stackpanel
        apps = spOutputs.apps;

        # Legacy packages for introspection
        legacyPackages = spOutputs.legacyPackages;
      }
    )
    # Global (not per-system) outputs
    // {
      inherit (exports)
        lib
        devenvModules
        templates
        ;

      # nixosModules merges framework modules from exports with
      # per-app generated service modules from globalOutputs
      nixosModules = exports.nixosModules // globalOutputs.nixosModules;

      inherit (globalOutputs)
        nixosConfigurations
        colmenaHive
        ;
    };
}
