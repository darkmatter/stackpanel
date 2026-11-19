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
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    # Modules used by this repository's .stack/config.nix, not by consumers.
    fly.url = "github:darkmatter/stackpanel-registry?dir=modules/fly";
    javascript.url = "github:darkmatter/stackpanel-registry?dir=modules/javascript";
    nextjs.url = "github:darkmatter/stackpanel-registry?dir=modules/nextjs";
    oxlint.url = "github:darkmatter/stackpanel-registry?dir=modules/oxlint";
    git-hooks.url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1.1149";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.inputs.flake-parts.follows = "flake-parts";
    agenix-rekey.inputs.treefmt-nix.follows = "treefmt-nix";
    flake-utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "https://flakehub.com/f/numtide/treefmt-nix/0.1.512";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    gomod2nix.url = "github:nix-community/gomod2nix";
    gomod2nix.inputs.nixpkgs.follows = "nixpkgs";
    gomod2nix.inputs.flake-utils.follows = "flake-utils";
    bun2nix.url = "github:nix-community/bun2nix";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.flake-parts.follows = "flake-parts";
    bun2nix.inputs.treefmt-nix.follows = "treefmt-nix";
    nixtest.url = "github:jetify-com/nixtest";
    namaka.url = "github:nix-community/namaka/v0.2.1";
    namaka.inputs.nixpkgs.follows = "nixpkgs";
    namaka.inputs.haumea.follows = "haumea";
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
    # Devshell UI suite (MOTD, menu/x, docs). Delivered transitively to
    # consumers via flakeModules.default / mkFlake — they do not need this
    # input themselves. Disable packages/banner with stackpanel.prelude.enable = false.
    prelude.url = "github:darkmatter/prelude";
    # Prelude needs a newer Go than Stackpanel's pinned nixpkgs; follow unstable.
    prelude.inputs.nixpkgs.follows = "nixpkgs-unstable";
    prelude.inputs.flake-parts.follows = "flake-parts";
    prelude.inputs.treefmt-nix.follows = "treefmt-nix";
    # Folder-structure flake outputs. Re-exported as `blueprint` from
    # nix/flake/exports.nix with Stackpanel overlays and supported systems
    # applied, so consumers do not add this input themselves.
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
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

      flake = {
        inherit (exports)
          lib
          templates
          flakeModules
          devenvModules
          nixosModules
          ;
        # Re-export the pinned Prelude input for power users who want
        # `nix run` / docs against the same revision Stackpanel ships.
        inherit (exports) prelude;
        # Wrapped numtide/blueprint (overlays + supported systems).
        inherit (exports) blueprint;
      };
    };
}
