# ==============================================================================
# envs.nix
#
# Root-level, per-environment variable registry.
#
# This is the canonical source of truth for "what variables exist in
# environment X". Apps automatically contribute their declared `app.env`
# entries here for each of their `environmentIds`, and other modules
# (infra, custom Nix code, deploy targets, …) can also write directly:
#
#   stackpanel.envs.dev.DATABASE_URL = {
#     required = true;
#     secret = true;
#     sops = "/dev/database-url";
#   };
#
#   stackpanel.envs.prod.PORT = { value = "443"; required = true; };
#
# Codegen reads from this attrset to produce the per-env SOPS payloads
# (under `<env-package>/data/_envs/<env>.sops.json`). The same shape is
# also fed back into the per-app codegen so the two stay in lockstep.
#
# Schema mirrors `EnvironmentVariable` from
# `nix/stackpanel/db/schemas/apps.proto.nix`. Submodule semantics handle
# multi-source merges: declaring `KEY.required = true` in two places is
# a no-op (boolean equality), declaring different `value`/`sops` is a
# Nix evaluation error pointing at the conflict.
#
# Apps that contribute via `apps.<app>.env` go through a custom OR-merge
# step in `nix/stackpanel/lib/codegen/env-package.nix` that reduces
# multiple app contributions for the same KEY into a single submodule
# definition before it reaches this option, so legitimate cross-app
# differences (e.g., `secret` set by one app, not the other) merge
# cleanly without surfacing as conflicts here.
# ==============================================================================
{ lib, ... }:
let
  envVarSubmodule =
    { name, ... }:
    {
      options = {
        key = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''
            The actual environment variable name. Defaults to the attribute key,
            so `stackpanel.envs.dev.DATABASE_URL` exposes `$DATABASE_URL`.
          '';
        };
        required = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the variable must be present at runtime.";
        };
        secret = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether the value is sensitive. Affects how the value is rendered
            in UIs and whether it is encoded into the SOPS payload vs. emitted
            as a literal in metadata.
          '';
        };
        value = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Literal value (use for non-secret config).";
        };
        sops = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            SOPS reference of the form `/group/name`. Resolves to
            `<secrets-dir>/vars/<group>.sops.yaml` and reads the
            snake_case form of `<name>`.

            Setting this implies `secret = true`.
          '';
        };
        defaultValue = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Fallback value used when neither `value` nor `sops` resolves.
            A defaulted key is treated as guaranteed-present in the per-app
            TypeScript `Env` interface (i.e., not optional).
          '';
        };
      };
    };
in
{
  options.stackpanel.envs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf (lib.types.submodule envVarSubmodule));
    default = { };
    description = ''
      Environment variables grouped by environment name.

      Auto-populated from `apps.<app>.env` for each environment listed in
      that app's `environmentIds`. Other modules can also write directly
      (e.g., `stackpanel.envs.dev.MY_INFRA_KEY = { ... }`) without owning
      an app — useful for one-off envs like deploy-only secrets.

      Codegen reads from this attrset to produce per-env SOPS payloads
      under `<env-package>/data/_envs/<env>.sops.json` (one file per env,
      encrypted to all recipients eligible for that env).
    '';
    example = lib.literalExpression ''
      {
        dev = {
          DATABASE_URL = { secret = true; sops = "/dev/database-url"; required = true; };
          PORT         = { value = "3000"; required = true; };
          LOG_LEVEL    = { defaultValue = "info"; };
        };
        prod = {
          DATABASE_URL = { secret = true; sops = "/prod/database-url"; required = true; };
          PORT         = { value = "443"; required = true; };
        };
      }
    '';
  };
}
