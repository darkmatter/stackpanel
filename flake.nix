{
  description = "Stackpanel - Infrastructure toolkit for NixOS, devenv, and flake-parts";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    allow-import-from-derivation = "true";
    extra-substituters = "https://devenv.cachix.org https://darkmatter.cachix.org";
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= darkmatter.cachix.org-1:7R5qAiOVHxDpFy7yguECfC1JqVDgMdckGc+CDKk2pWA= nixpkgs-python.cachix.org-1:hxjI7pFxTyuTHn2NkvWCrAUcNZLNS3ZAvfYNuYifcEU=";
  };

  inputs = {
    git-hooks.url = "https://flakehub.com/f/cachix/git-hooks.nix/0.1.1147";
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "git+https://github.com/hercules-ci/flake-parts";
    devenv.url = "git+https://github.com/cachix/devenv?ref=refs/tags/v1.11.2";
    nix2container.url = "git+https://github.com/nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "git+https://github.com/rrbutani/nix-mk-shell-bin";
    pre-commit-hooks.url = "git+https://github.com/cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "git+https://github.com/numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    gomod2nix.url = "git+https://github.com/nix-community/gomod2nix";
    gomod2nix.inputs.nixpkgs.follows = "nixpkgs";
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      git-hooks,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { withSystem, flake-parts-lib, ... }:
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

        # =============================================================
        # LOCAL DEVELOPMENT (dogfooding)
        # =============================================================
        imports = [
          exports.flakeModules.readStackpanelRoot
          exports.flakeModules.default
        ]
        ++ nixpkgs.lib.optionals (builtins.getEnv "SKIP_DEVENV" != "true") [
          inputs.devenv.flakeModule
        ];

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

            # Import local shell configuration
            localShell = import ./shell.nix {
              inherit pkgs lib inputs system;
              git-hooks = git-hooks;
            };

            # Derivation that creates bin directory with all devshell packages
            devshell-bin = pkgs.callPackage ./nix/flake/packages/devshell-bin.nix {
              devShell = localShell.nativeDevshell;
            };
          in
          {
            _module.args.pkgs = import nixpkgs {
              inherit system;
              overlays = [ inputs.gomod2nix.overlays.default ];
            };

            packages = packages // {
              inherit devshell-bin;
            };

            checks = {
              stackpanel-cli = config.packages.stackpanel-cli;
              stackpanel-agent = config.packages.stackpanel-agent;
              default-package = config.packages.default;
            } // lib.optionalAttrs (localShell.pre-commit-check != null) {
              inherit (localShell) pre-commit-check;
            };
          }
          // (
            # When useDevenv is true, use devenv
            if localShell.useDevenv && builtins.getEnv "SKIP_DEVENV" != "true" then
              {
                # Devenv provides devShells.default via its flakeModule
                devenv.shells.default = {
                  imports = [ localShell.localDevshellModule ];
                  # Install git hooks on shell entry
                  enterShell = lib.optionalString (localShell.pre-commit-check != null) ''
                    ${localShell.pre-commit-check.shellHook}
                  '';
                };
                devenv.shells.ci-darwin = {
                  imports = [ localShell.localDevshellModule ];
                  containers = lib.mkForce { };
                  devenv.flakesIntegration = true;
                };
              }
            # When useDevenv is false but devenv flakeModule is loaded, use native + CI shell
            else if builtins.getEnv "SKIP_DEVENV" != "true" then
              {
                # Native Nix devShell using stackpanel modules (not devenv)
                devShells.default = localShell.nativeDevshell;
                # CI shell still uses devenv for compatibility
                devenv.shells.ci-darwin = {
                  imports = [ localShell.localDevshellModule ];
                  containers = lib.mkForce { };
                };
              }
            # SKIP_DEVENV=true: pure native shell only
            else
              {
                devShells.default = localShell.nativeDevshell;
              }
          );

        # =============================================================
        # EXPORTS (for users)
        # =============================================================
        flake = {
          inherit (exports)
            flakeModules
            nixosModules
            devenvModules
            lib
            templates
            ;
          stackpanelOptions = exports.mkStackpanelOptions nixpkgs;
        };
      }
    );
}
