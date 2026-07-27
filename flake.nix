{
  description = "Stackpanel - flake-parts development environment framework and studio";

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
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks.url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1.1149";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "https://flakehub.com/f/numtide/treefmt-nix/0.1.512";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    gomod2nix.url = "github:nix-community/gomod2nix";
    gomod2nix.inputs.nixpkgs.follows = "nixpkgs";
    gomod2nix.inputs.flake-utils.follows = "flake-utils";
    # Pinned: revs after this dropped x86_64-darwin from their per-system
    # packages (following nixpkgs 26.11), and this flake still supports
    # x86_64-darwin — its overlay throws 'does not have packages.x86_64-darwin'
    # at eval time (breaks flakehub-push and Intel-Mac devshells).
    bun2nix.url = "github:nix-community/bun2nix/f2bc12af1a6369648aac41041ceeaa0b866599c6";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    nixtest.url = "github:jetify-com/nixtest";
    namaka.url = "github:nix-community/namaka/v0.2.1";
    namaka.inputs.nixpkgs.follows = "nixpkgs";
    # Filesystem-based module loader. Powers the optional "tree" config
    # layout (see nix/flake/load-config.nix). Pinned because the main branch
    # may introduce breaking changes per their versioning policy.
    haumea.url = "github:nix-community/haumea/v0.2.2";
    haumea.inputs.nixpkgs.follows = "nixpkgs";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
    #inputs.sops-nix.url = "github:Mic92/sops-nix";
    #inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { flake-parts, ... }@inputs:
    let
      exports = import ./nix/flake/exports.nix { inherit inputs; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = exports.supportedSystems;
      imports = [ exports.flakeModules.default ];

      stackpanel.includeRootOutputs = true;

      perSystem =
        { system, ... }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = exports.lib.requiredOverlays;
          };
        };

      flake = {
        inherit (exports) lib templates flakeModules;
      };
    };
}
