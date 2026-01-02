# ==============================================================================
# secrets.nix
#
# Secrets management options - SOPS-encrypted secrets with codegen.
#
# Pure option definitions for secrets management (no implementation).
# Works with any Nix module system (devenv, NixOS, lib.evalModules).
#
# Options:
#   - enable: Enable StackPanel secrets utilities
#   - input-directory: Directory for SOPS-encrypted files
#   - environments: Environment-specific configurations
#     - name: Environment name
#     - public-keys: AGE public keys for decryption
#     - sources: SOPS-encrypted source files
#   - codegen: Code generation settings per language
#     - name: Package name
#     - directory: Output directory
#     - language: "typescript" or "go"
#
# Usage:
#   stackpanel.secrets = {
#     enable = true;
#     environments.prod = {
#       name = "production";
#       public-keys = ["age1..."];
#     };
#   };
# ==============================================================================
{ lib, ... }:
let
  types = lib.types;
in
{
  options.stackpanel.users = lib.mkOption {
    description = ''
      Users of the repository who should have access to secrets.
    '';
    example = {
      cooper = {
        name = "Cooper Maruyama";
        github = "coopermaruyama";
        secrets-allowed-environments = [
          "dev"
          "staging"
          "production"
        ];
        public-keys = [
          "age1..."
          "ssh-ed25519 AAAA..."
        ];
      };
      alice = {
        name = "Alice Example";
        github = "aliceexample";
        secrets-allowed-environments = [ "dev" ];
        public-keys = [ "age1..." ];
      };
      ci = {
        name = "CI Bot";
        public-keys = [ "age1..." ];
        secrets-allowed-environments = [
          "dev"
          "staging"
          "production"
        ];
      };
    };
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Display name";
            };

            github = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Github username for this user. Enable for automatic access control in GitHub Actions.";
            };

            secrets-allowed-environments = lib.mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "List of environment names this user should have access to.";
              example = [
                "dev"
                "staging"
                "production"
              ];
            };

            public-keys = lib.mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "public keys for this user. will be autopopulated if user has github username with public key. accepts age and ssh keys.";
            };
          };
        }
      )
    );
    default = { };
  };

  options.stackpanel.users-settings = {
    disable-github-sync = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Disable automatic GitHub public key synchronization for users with GitHub usernames.";
    };
  };
}
