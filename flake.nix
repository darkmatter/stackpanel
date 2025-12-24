{
  description = "Stackpanel - Infrastructure toolkit for NixOS, devenv, and flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
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
      inherit (flake-parts-lib) importApply;

      # =============================================================
      # FLAKE MODULES (for users to import)
      #
      # These are modules that OTHER flakes import when they use stackpanel.
      # The importApply pattern allows them to reference things from THIS flake.
      # =============================================================
      flakeModules.default = importApply ./nix/flake-module.nix {
        localFlake = self;
        inherit withSystem;
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
        flakeModules.default # Dogfood our own module!
      ] ++ nixpkgs.lib.optionals (builtins.getEnv "SKIP_DEVENV" != "true") [
        # Import devenv unless explicitly skipped (e.g., for FlakeHub which doesn't support --impure)
        # Set SKIP_DEVENV=true to disable devenv for pure evaluation contexts
        inputs.devenv.flakeModule
      ];

      # Only support systems that all our dependencies (nix2container, etc.) support
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

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
            ./infra/devenv/devenv.nix
            # Stackpanel-specific config for this repo
            ./infra/stackpanel/stackpanel.nix
          ];

          # Enable stackpanel
          stackpanel.enable = true;

          # Core packages
          packages = with pkgs; [
            bun
            nodejs_22
            go
            jq
            git
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

          # Shell hooks
          enterShell = ''
            # Build stackpanel CLI if needed
            if [[ ! -f "$DEVENV_STATE/stackpanel" ]] || [[ "$DEVENV_ROOT/apps/cli/main.go" -nt "$DEVENV_STATE/stackpanel" ]]; then
              echo "Building stackpanel CLI..."
              (cd "$DEVENV_ROOT/apps/cli" && go build -o "$DEVENV_STATE/stackpanel" . 2>/dev/null) || true
            fi
            export PATH="$DEVENV_STATE:$PATH"

            # Authenticate AWS certs on shell entry
            eval "$(aws-creds-env)" || true
          '';
        };
      in {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [ inputs.gomod2nix.overlays.default ];
        };
        # Packages we build
        packages = {
          # CLI package export
          stackpanel-cli = pkgs.callPackage ./nix/packages/stackpanel-cli {};

          default = pkgs.hello; # placeholder

          # Note: We don't merge devenv outputs here since they include container outputs
          # that require Linux-only packages (shadow). The devenv shell is still accessible
          # via `nix develop` or `devenv shell`.
        };

        # Local development shell - uses the same pattern users would
        devenv.shells.default = sharedDevenvConfig;

        # CI shell for Darwin - excludes container outputs that require Linux-only packages
        devenv.shells.ci-darwin = sharedDevenvConfig // {
          # Explicitly disable containers to avoid evaluating Linux-only packages
          containers = lib.mkForce {};
        };
      };

      # =============================================================
      # EXPORTS (for users)
      #
      # These are what users import when they add stackpanel to their flake.
      # =============================================================
      flake = {
        # Flake-parts modules (for flake-parts users)
        # Usage: imports = [ inputs.stackpanel.flakeModules.default ];
        inherit flakeModules;

        # Standalone NixOS/nix modules (for NixOS users)
        # Usage: imports = [ inputs.stackpanel.nixosModules.default ];
        nixosModules = {
          # Point directly at module files, not directories
          default = ./nix/modules/devenv.nix;
          aws = ./nix/modules/aws.nix;
          network = ./nix/modules/network.nix;
          secrets = ./nix/modules/secrets/default.nix;
          theme = ./nix/modules/theme.nix;
          caddy = ./nix/modules/caddy.nix;
          ci = ./nix/modules/ci.nix;
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
          # devenv.nix is the entry point (devenv convention for directory imports)
          default = ./nix/devenv.nix;
        };

        # Library functions for use in other flakes
        lib = {
          # AWS credential helpers
          mkAwsCredScripts = pkgs:
            import ./nix/lib/aws.nix {
              inherit pkgs;
              lib = pkgs.lib;
            };
          # Step CA certificate helpers
          mkStepScripts = pkgs:
            import ./nix/lib/network.nix {
              inherit pkgs;
              lib = pkgs.lib;
            };
          # Global dev services for `nix develop` / mkShell
          # Usage: stackpanel.lib.mkDevShell pkgs { projectName = "myapp"; postgres.enable = true; }
          mkDevShell = pkgs: (import ./nix/lib/devshell.nix {inherit pkgs;}).mkDevShell;
        };

        # Templates for bootstrapping new projects
        templates = {
          default = {
            path = ./nix/templates/default;
            description = "Basic stackpanel project with devenv";
          };
        };
      };
    });
}
