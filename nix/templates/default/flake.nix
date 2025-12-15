{
  description = "My project powered by stackpanel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # stackpanel.url = "github:stack-panel/nix";  # uncomment when published
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        # inputs.stackpanel.flakeModules.default  # uncomment when published
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

      perSystem = {
        config,
        pkgs,
        ...
      }: let
        # Import team data if it exists
        teamData =
          if builtins.pathExists ./.stackpanel/team.nix
          then import ./.stackpanel/team.nix
          else {
            users = {};
          };
      in {
        stackpanel = {
          # Secrets management
          secrets = {
            enable = false; # Enable when you have team members
            users = teamData.users;
            secrets = {
              # "api-key.age".owners = [ "alice" ];
            };
          };

          # CI/CD
          ci.github = {
            enable = true;
            checks = {
              enable = true;
              commands = ["nix flake check"];
            };
          };
        };

        # Your packages here
        packages.default = pkgs.hello;
      };
    };
}
