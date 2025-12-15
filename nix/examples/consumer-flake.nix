# Example: What a user's flake.nix would look like
#
# This is NOT part of stackpanel - it's showing how someone would USE it.
# Put this in templates/default/flake.nix when ready.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    stackpanel.url = "github:stack-panel/nix";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [inputs.stackpanel.flakeModules.default];

      systems = ["x86_64-linux" "aarch64-darwin"];

      # ─────────────────────────────────────────────────────
      # stackpanel config
      # ─────────────────────────────────────────────────────
      perSystem = {pkgs, ...}: let
        # Agent writes this file when you click "Install Agenix" in UI
        # It syncs your GitHub team members + their SSH pubkeys
        teamConfig = import ./.stackpanel/secrets.nix;
      in {
        stackpanel = {
          # ── Secrets (agenix) ──────────────────────────────
          # Users are synced from GitHub by the agent
          secrets = {
            enable = true;
            users = teamConfig.users;

            # Define which secrets exist and who can access them
            # (you add these manually or via UI)
            secrets = {
              "api-key.age".owners = ["alice" "bob"];
              "db-password.age".owners = ["alice"]; # admin-only
              "stripe-key.age".owners = ["alice" "bob" "charlie"];
            };

            # Auto-rekey workflow (enabled by default)
            rekey = {
              enable = true;
              sshKeySecret = "AGENIX_SSH_KEY"; # GitHub secret name
            };
          };

          # ── CI ────────────────────────────────────────────
          ci.github = {
            enable = true;
            checks = {
              enable = true;
              commands = ["nix flake check"];
            };
          };
        };
      };
    };
}
# ============================================================================
# WORKFLOW
# ============================================================================
#
# 1. User opens localhost:1111 (agent UI)
# 2. Clicks "Install Agenix"
# 3. Agent prompts to connect GitHub
# 4. Agent fetches team from github.com/orgs/acme-corp/members
# 5. Agent fetches SSH keys from github.com/<user>.keys for each member
# 6. Agent writes .stackpanel/secrets.nix with user data
# 7. Agent enables stackpanel.secrets in flake.nix (or user does manually)
# 8. User runs: nix run .#generate
# 9. Generated files:
#      - secrets/secrets.nix (agenix format)
#      - .github/workflows/rekey.yml
#
# When team changes:
# 1. User clicks "Sync Team" in UI
# 2. Agent updates .stackpanel/secrets.nix
# 3. User runs: nix run .#generate
# 4. Commits and pushes
# 5. GitHub Action auto-rekeys all secrets
#
# ============================================================================

