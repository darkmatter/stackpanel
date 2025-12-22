{
  description = "Stackpanel - Infrastructure toolkit for NixOS, devenv, and flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }: {
    # Standalone NixOS/nix modules
    # Usage: imports = [ inputs.stackpanel.nixosModules.default ];
    nixosModules = {
      default = ./nix/modules;
      aws = ./nix/modules/aws;
      network = ./nix/modules/network;
      secrets = ./nix/modules/secrets;
      theme = ./nix/modules/theme;
      caddy = ./nix/modules/caddy;
      ci = ./nix/modules/ci;
    };

    # Flake-parts modules
    # Usage: imports = [ inputs.stackpanel.flakeModules.default ];
    flakeModules = {
      default = ./nix/modules/flake-parts.nix;
    };

    # Devenv modules (for use in devenv.yaml imports)
    # Usage in devenv.yaml:
    #   inputs:
    #     stackpanel:
    #       url: github:darkmatter/stackpanel
    #   imports:
    #     - stackpanel/nix/modules/devenv
    devenvModules = {
      default = ./nix/modules/devenv;
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
}
