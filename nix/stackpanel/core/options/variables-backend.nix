# ==============================================================================
# variables-backend.nix
#
# Unified variables backend configuration.
#
# Options defined here:
#   stackpanel.secrets.backend          - "sops", "vals", or "chamber"
#   stackpanel.secrets.chamber.service-prefix - Chamber SSM path prefix
#
# NOTE: These options live under stackpanel.secrets (not stackpanel.variables)
# because stackpanel.variables is typed as `attrsOf submodule` (the variable
# data map) and doesn't support sibling child options.
#
# The backend determines how secrets are stored, read/written by the agent,
# injected via entrypoints, and surfaced in the UI.
#
# Supported backends:
#   sops    - Direct SOPS/AGE encryption using the generated `.sops.yaml`.
#             Secrets are stored as SOPS-encrypted YAML files.
#             This is the default.
#
#   vals    - Legacy AGE/SOPS mode with vals for external store references.
#             Secrets are stored as .age files or SOPS-encrypted YAML.
#
#   chamber - AWS Systems Manager Parameter Store via the chamber CLI.
#             Secrets are stored in SSM Parameter Store, encrypted with KMS.
#             Entrypoints use `chamber exec` for secret injection.
#             No .age files or SOPS YAML are generated.
#
# When backend = "chamber":
#   - SST KMS is force-enabled (chamber requires KMS for encryption)
#   - chamber is added to devshell packages
#   - Entrypoints use `chamber exec {service-prefix}/{env} -- "$@"`
#   - The Go agent shells out to `chamber write` / `chamber read`
#   - SOPS YAML generation is skipped in codegen
#   - The Secrets Panel in the UI shows a disabled state
#
# The chamber service path is auto-derived from the project owner/repo (or name):
#   {service-prefix}/{keygroup}
#   e.g., darkmatter/stackpanel/dev, darkmatter/stackpanel/prod
#
# Scope mapping (same ID scheme for all backends):
#   /dev/FOO                 -> scope/keygroup: dev
#   /staging/FOO             -> scope/keygroup: staging
#   /prod/FOO                -> scope/keygroup: prod
#   /secret/FOO              -> scope/keygroup: secret
#   /computed/apps/web/port  -> read-only from Nix modules (not backend stored)
#
# For chamber, each writable scope maps to chamber service {prefix}/{scope}.
# For sops/vals, each writable scope maps to vars/{scope}.sops.yaml.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  projectName = config.stackpanel.name or "my-project";
  projectCfg = config.stackpanel.project or { };
  owner = projectCfg.owner or "";
  repo = projectCfg.repo or "";

  # Prefer owner/repo for chamber prefix (better SSM path namespacing),
  # fall back to project name for backwards compatibility
  defaultPrefix = if owner != "" && repo != "" then "${owner}/${repo}" else projectName;
in
{
  # NOTE: Backend options live under stackpanel.secrets (not stackpanel.variables)
  # because stackpanel.variables is typed as `attrsOf submodule` in variables.nix
  # (the variable data map) and doesn't support sibling child options.

  options.stackpanel.secrets = {
    backend = lib.mkOption {
      type = lib.types.enum [
        "sops"
        "vals"
        "chamber"
      ];
      default = "sops";
      description = ''
        Secret storage backend for writable `stackpanel.variables` scopes.
        This is the single source of truth that controls where scoped variables
        are stored, how entrypoints inject them, how the agent reads/writes them,
        and what options are available in the UI.

        `/computed/*` variables are not stored through this backend. They are
        read-only values produced by Nix modules and exposed through the same
        variable registry for codegen/env consumers.

        Backends:
          "sops" (default): direct SOPS/AGE encryption using `.sops.yaml` files.
          "vals": legacy AGE/SOPS encryption with vals external references.
          "chamber": AWS SSM Parameter Store via the chamber CLI.

        Scope examples:
          `/dev/DATABASE_URL` -> dev scope
          `/prod/STRIPE_SECRET_KEY` -> prod scope
          `/computed/apps/web/port` -> computed, read-only, no backend write
      '';
      example = "sops";
    };

    chamber = {
      service-prefix = lib.mkOption {
        type = lib.types.str;
        default = defaultPrefix;
        description = ''
          Chamber service prefix used when `stackpanel.secrets.backend = "chamber"`.
          The full chamber service path is `{service-prefix}/{scope}`.

          For example, with prefix "darkmatter/stackpanel" and variable
          `/dev/DATABASE_URL`:
            chamber write darkmatter/stackpanel/dev DATABASE_URL <value>
            chamber exec darkmatter/stackpanel/dev -- <command>

          With `/prod/STRIPE_SECRET_KEY`, the service is
          `darkmatter/stackpanel/prod` and the chamber key is
          `STRIPE_SECRET_KEY`.

          `/computed/*` variables never use chamber because they are read-only
          Nix outputs, not stored secrets.

          Defaults to "{owner}/{repo}" when project owner/repo are configured,
          otherwise falls back to the project name.
        '';
        example = "darkmatter/stackpanel";
      };
    };
  };

  # No config in this file — config effects (force KMS, add chamber pkg, etc.)
  # are applied in the respective modules that own those concerns:
  #   - sst.nix: forces KMS on when backend=chamber
  #   - secrets/default.nix: adds chamber to devshell, serializes backend config
}
