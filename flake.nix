{
  description = "Stackpanel - Infrastructure toolkit for NixOS, devenv, and flake-parts";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    allow-import-from-derivation = "true";
    extra-substituters = "https://devenv.cachix.org https://darkmatter.cachix.org";
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= darkmatter.cachix.org-1:7R5qAiOVHxDpFy7yguECfC1JqVDgMdckGc+CDKk2pWA=";
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Util that makes it easy to build all outputs of a flake.
    # devour-flake.url = "github:srid/devour-flake";
    # devour-flake.flake = false;
    devenv.url = "github:cachix/devenv";
    # Required for devenv containers outputs
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";

    # Required when enabling stackpanel.devenv.recommended.formatters
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    gomod2nix.url = "github:nix-community/gomod2nix";
    gomod2nix.inputs.nixpkgs.follows = "nixpkgs";
    stackpanel-root.url = "file+file:///dev/null";
    stackpanel-root.flake = false;
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({
      withSystem,
      flake-parts-lib,
      ...
    }: let
      devshell = import ./nix/flake/devshells { inherit inputs; };
      inherit (flake-parts-lib) importApply;
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # =============================================================
      # FLAKE MODULES (for users to import)
      #
      # These are modules that OTHER flakes import when they use stackpanel.
      # The importApply pattern allows them to reference things from THIS flake.
      # Usage:
      #
      # imports = [
      #   inputs.stackpanel.flakeModules.default
      #   inputs.stackpanel.flakeModules.devshell
      # ];
      # stackpanel.devshell.enable = true;
      # stackpanel.devshell.modules = [ .
      #   inputs.stackpanel.lib.mkDevShellModule.postgres
      #   ({ lib, pkgs, ... }: {
      #      postgres.enable = true;
      #      devshell.packages = [ pkgs.psql ];
      #      devshell.hooks.before = lib.mkBefore [ "echo enter" ];
      #   })
      # ];
      # =============================================================
      flakeModules.default = importApply ./nix/internal/flake-module.nix {
        localFlake = self;
        inherit withSystem devshell;
      };

      # Helper module for pure flake evaluation (like `nix flake check`)
      # Users add this to their imports and provide a stackpanel-root input:
      #
      #   inputs.stackpanel-root = {
      #     url = "file+file:///dev/null";
      #     flake = false;
      #   };
      #
      # Then their .envrc writes the actual path:
      #   echo "$PWD" > .stackpanel-root
      #
      flakeModules.readStackpanelRoot = {
        inputs,
        lib,
        ...
      }: {
        config = let
          rootContent =
            if inputs ? stackpanel-root
            then builtins.readFile inputs.stackpanel-root.outPath
            else "";
        in
          lib.mkIf (rootContent != "") {
            # Set the stackpanel root for all devenv shells
            perSystem = {lib, ...}: {
              devenv.shells = lib.mkDefault {
                default.stackpanel.root = lib.strings.trim rootContent;
              };
            };
          };
      };
    in {
      # =============================================================
      # LOCAL DEVELOPMENT (dogfooding)
      #
      # We use devenv via flake-parts to develop stackpanel itself.
      # This means we're testing the exact same integration our users get.
      #
      # Run with: nix develop --no-pure-eval
      # =============================================================
      imports = [
        flakeModules.readStackpanelRoot
        flakeModules.default # Dogfood our own module!
      ] ++ nixpkgs.lib.optionals (builtins.getEnv "SKIP_DEVENV" != "true") [
        # Import devenv unless explicitly skipped (e.g., for FlakeHub which doesn't support --impure)
        # Set SKIP_DEVENV=true to disable devenv for pure evaluation contexts
        inputs.devenv.flakeModule
      ];
      systems = supportedSystems;

      perSystem = {
        config,
        pkgs,
        lib,
        system,
        ...
      }: let
        # Shared devenv configuration used by multiple shells
        sharedDevenvConfig = {
          # Import our own devenv modules (dogfooding!)
          imports = [
            self.devenvModules.default
            # Local-only config that shouldn't be in the exported module
            ./nix/internal/devenv/devenv.nix
            # Stackpanel-specific config for this repo
            ./nix/internal/stackpanel.nix
          ];

          # Enable stackpanel
          stackpanel.enable = true;

          # Core packages
          packages = with pkgs; [
            bun
            nodejs_22
            go
            air  # Go live reload for CLI development
            jq
            git
            nixd
            nixfmt
          ];

          # Languages
          languages = {
            javascript = {
              enable = true;
              bun.enable = true;
              bun.install.enable = true;
            };
            typescript.enable = true;
            go = {
              enable = true;
              package = pkgs.go;
            };
          };

          # Environment variables
          env = {
            EDITOR = "vim";
            STEP_CA_URL = "https://ca.internal:443";
            STEP_CA_FINGERPRINT = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
          };

          # Note: AWS credentials are handled by stackpanel.aws.certAuth module
          # which adds aws-creds-env to enterShell with proper error handling
        };
      in {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [ inputs.gomod2nix.overlays.default ];
        };
        # Packages we build
        packages = let
          stackpanel-cli-unwrapped = pkgs.callPackage ./nix/stackpanel/packages/stackpanel-cli {};
          stackpanel-agent = pkgs.callPackage ./nix/stackpanel/packages/stackpanel-agent {};
        in {
          # CLI package export (wrapped to include agent in PATH)
          stackpanel-cli = pkgs.symlinkJoin {
            name = "stackpanel-cli-${stackpanel-cli-unwrapped.version}";
            paths = [ stackpanel-cli-unwrapped stackpanel-agent ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              # Wrap stackpanel to have stackpanel-agent in PATH
              wrapProgram $out/bin/stackpanel \
                --prefix PATH : ${stackpanel-agent}/bin
            '';
          };

          # Expose agent separately too
          inherit stackpanel-agent;

          default = pkgs.hello; # placeholder

          # Note: We don't merge devenv outputs here since they include container outputs
          # that require Linux-only packages (shadow). The devenv shell is still accessible
          # via `nix develop` or `devenv shell`.
        };

      } // (if builtins.getEnv "SKIP_DEVENV" != "true" then {
        # Local development shell - uses the same pattern users would
        devenv.shells.default = sharedDevenvConfig;

        # CI shell for Darwin - excludes container outputs that require Linux-only packages
        devenv.shells.ci-darwin = sharedDevenvConfig // {
          # Explicitly disable containers to avoid evaluating Linux-only packages
          containers = lib.mkForce {};
        };
      } else {});

      # =============================================================
      # EXPORTS (for users)
      #
      # These are what users import when they add stackpanel to their flake.
      # =============================================================
      flake = let
        devshell = import ./nix/flake/devshells { inherit inputs; };
      in {
        # Flake-parts modules (for flake-parts users)
        # Usage: imports = [ inputs.stackpanel.flakeModules.default ];
        inherit flakeModules;

        # Expose evaluated option trees to provide support for language servers
        # Usage (vscode settings.json):
        #   (builtins.getFlake (toString ./.)).stackpanelOptions.${builtins.currentSystem}.secrets
        stackpanelOptions = nixpkgs.lib.genAttrs supportedSystems (system:
          withSystem system ({ pkgs, ...}:
            let
              lib = pkgs.lib;
              mkOptions = modules:
                (lib.evalModules {
                  modules = modules ++ [
                    {
                      _module.args = { inherit pkgs lib; };
                    }
                  ];
                }).options;
            in {
              # network = mkOptions [
              #   ./nix/modules/network.nix
              #   {
              #     stackpanel.network.enable = true;
              #   }
              # ]
              all = mkOptions [
                ./nix/stackpanel/core/options/default.nix
                {
                  stackpanel = {
                    enable = true;
                  };
                }
              ];
            }
          )
        );

        # Standalone NixOS/nix modules (for NixOS users)
        # Usage: imports = [ inputs.stackpanel.nixosModules.default ];
        nixosModules = {
          # Point directly at module files, not directories
          default = ./nix/flake/modules/devenv;
          aws = ./nix/stackpanel/services/aws.nix;
          network = ./nix/stackpanel/network/network.nix;
          secrets = ./nix/stackpanel/secrets/default.nix;
          theme = ./nix/stackpanel/lib/theme.nix;
          caddy = ./nix/stackpanel/services/caddy.nix;
          ci = ./nix/stackpanel/apps/ci.nix;
        };

        # Devenv modules (for devenv users - both yaml and flake-parts)
        # Usage in devenv.yaml:
        #   inputs:
        #     stackpanel:
        #       url: github:darkmatter/stackpanel
        #   imports:
        #     - stackpanel/nix/modules
        #
        # Usage in flake-parts:
        #   devenv.shells.default = {
        #     imports = [ inputs.stackpanel.devenvModules.default ];
        #   };
        devenvModules = {

          # Main devenv module (imports core stackpanel options + adapter)
          default = import ./nix/flake/modules/devenv {
            inherit devshell;
          };

          # Adapter to reuse a stackpanel devshell inside devenv
          devshell = import ./nix/flake/modules/devenv-devshell-adapter.nix {
            inherit devshell;
          };
        };

        # Library functions for use in other flakes
        lib = {
          # AWS credential helpers
          mkAwsCredScripts = pkgs:
            import ./nix/stackpanel/lib/services/aws.nix {
              inherit pkgs;
              lib = pkgs.lib;
            };
          # Step CA certificate helpers
          mkStepScripts = pkgs:
            import ./nix/stackpanel/lib/services/step.nix {
              inherit pkgs;
              lib = pkgs.lib;
            };
          # Global dev services for `nix develop` / mkShell
          # Usage: stackpanel.lib.mkDevShell pkgs { projectName = "myapp"; postgres.enable = true; }
          # new config-based mkDevShell
          mkDevShell = { pkgs, modules ? [], specialArgs ? {} }:
            (import ./nix/stackpanel/devshell { inherit pkgs; }) {
              inherit modules specialArgs;
            };

          # export feature modules (so consumers can import them)
          devshellModules = devshell.devshellModules;
        };

        # Templates for bootstrapping new projects
        templates = {
          default = {
            path = ./nix/flake/templates/default;
            description = "Basic stackpanel project with devenv";
          };
        };
      };
    });
}
