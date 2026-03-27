# ==============================================================================
# services/aws/default.nix
#
# AWS service module aggregator.
#
# Consolidates all AWS-related Nix modules into a single directory:
#
#   services/aws/
#   ├── default.nix          # This file — imports all sub-modules
#   ├── lib.nix              # Pure library (mkAwsCredentialProcess, etc.)
#   ├── options.nix          # Option declarations (stackpanel.aws.*)
#   ├── roles-anywhere.nix   # Roles Anywhere devenv module (hooks, TUI, creds)
#   └── vault/               # aws-vault integration
#       ├── module.nix       # aws-vault module (wrappers, multi-profile)
#       ├── meta.nix         # Module metadata
#       ├── ui.nix           # Studio panel definitions
#       ├── example.nix      # Example configurations
#       └── README.md        # Documentation
#
# NOTE: lib.nix is a pure function library, NOT a NixOS module.
#       It is consumed directly via:
#         import ./lib.nix { inherit pkgs lib; }
#       and is NOT listed in imports below.
#
# NOTE: The proto schema (db/schemas/aws.proto.nix) remains in the db
#       directory — it is the source of truth for the data structure and
#       is shared across multiple consumers.
#
# NOTE: AWS env var definitions remain in core/lib/envvars.nix since
#       that file is a shared registry across all feature areas.
#
# Usage:
#   # In a module aggregator:
#   imports = [ ./services/aws ];
# ==============================================================================
{ ... }:
{
  imports = [
    ./options.nix
    ./roles-anywhere.nix
    ./vault/module.nix
    ./vault/ui.nix
  ];
}
