# ==============================================================================
# mkInfraModule.nix
#
# Helper for creating infrastructure modules with less boilerplate.
#
# Eliminates the repetitive patterns across infra modules:
#   - enable option
#   - sync-outputs option with mkOutput helper
#   - config guard (lib.mkIf cfg.enable)
#   - stackpanel.infra.enable = lib.mkDefault true
#   - stackpanel.infra.modules.<id> = { ... } registration
#   - kebab-to-camel key transformation for inputs
#
# Usage:
#
#   # Minimal module
#   { lib, config, ... }:
#   lib.stackpanel.mkInfraModule {
#     id = "my-s3-buckets";
#     name = "S3 Buckets";
#     description = "Provision S3 buckets";
#     path = ./index.ts;
#     inherit lib config;
#
#     options = {
#       buckets = lib.mkOption {
#         type = lib.types.attrsOf lib.types.str;
#         default = {};
#       };
#     };
#
#     inputs = cfg: {
#       buckets = cfg.buckets;
#     };
#
#     dependencies = {
#       "@aws-sdk/client-s3" = "catalog:";
#     };
#
#     outputs = {
#       bucketArns = "Bucket ARNs (JSON)";
#     };
#   }
#
#   # Outputs with sensitivity/sync control
#   outputs = {
#     connectionUrl = { description = "Connection URL"; sensitive = true; };
#     provider = "Active provider name";  # shorthand: string = description
#   };
#
#   # Conditional dependencies
#   dependencies = cfg: lib.optionalAttrs (cfg.source == "aws-ec2") {
#     "@aws-sdk/client-ec2" = "catalog:";
#   };
#
# ==============================================================================
{ lib }:
let
  # ==========================================================================
  # mkOutput: shared helper (replaces the per-module copy-paste)
  # ==========================================================================
  mkOutput =
    syncOutputs: key: desc:
    {
      description = desc;
      sensitive = false;
      sync = builtins.elem key syncOutputs;
    };

  # ==========================================================================
  # Normalize an output declaration.
  #
  # Accepts two forms:
  #   "description string"     → { description, sensitive = false, sync = true }
  #   { description, ... }     → passthrough with defaults
  # ==========================================================================
  normalizeOutput =
    key: value:
    if builtins.isString value then {
      description = value;
      sensitive = false;
      sync = true;
    } else {
      description = value.description or "";
      sensitive = value.sensitive or false;
      sync = value.sync or true;
    };

  # ==========================================================================
  # Collect output keys where sync defaults to true (for sync-outputs default)
  # ==========================================================================
  defaultSyncKeys =
    outputs:
    builtins.filter (
      key:
      let
        v = outputs.${key};
      in
      if builtins.isString v then true else v.sync or true
    ) (builtins.attrNames outputs);

in
{
  mkInfraModule =
    {
      # Required: module identifier (e.g., "aws-key-pairs")
      id,

      # Required: human name (e.g., "AWS Key Pairs")
      name,

      # Optional: description
      description ? "${name} infrastructure provisioning",

      # Required: path to TypeScript implementation (./index.ts or ./impl)
      path,

      # Required: config from the calling module
      config,

      # Optional: module-specific options (merged alongside enable + sync-outputs)
      options ? { },

      # Required: function from cfg → inputs attrset
      # The result is serialized to JSON for the TypeScript runtime.
      inputs ? _cfg: { },

      # Optional: NPM dependencies (attrset or function from cfg)
      dependencies ? { },

      # Required: output declarations
      # Short form: { key = "description"; }
      # Long form:  { key = { description; sensitive; sync; }; }
      outputs ? { },

      # Optional: override enable default (normally false)
      enableDefault ? false,

      # Optional: extra config beyond the registration
      extraConfig ? _cfg: { },

      # Optional: additional guard condition
      # When set, the config block uses: lib.mkIf (guard && cfg.enable)
      extraGuard ? null,
    }:
    let
      cfg = config.stackpanel.infra.${id};
      normalizedOutputs = lib.mapAttrs normalizeOutput outputs;
      syncDefaults = defaultSyncKeys outputs;

      resolvedDeps =
        if builtins.isFunction dependencies then dependencies cfg else dependencies;

      guard =
        if extraGuard != null then extraGuard && cfg.enable else cfg.enable;

      # Build the final outputs attrset, respecting cfg.sync-outputs
      finalOutputs = lib.mapAttrs (
        key: out:
        {
          inherit (out) description sensitive;
          sync = builtins.elem key (cfg.sync-outputs or syncDefaults);
        }
      ) normalizedOutputs;
    in
    {
      # ======================================================================
      # Options
      # ======================================================================
      options.stackpanel.infra.${id} =
        {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = enableDefault;
            description = "Enable ${name}.";
          };

          sync-outputs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = syncDefaults;
            description = "Which outputs to sync to the storage backend.";
          };
        }
        // options;

      # ======================================================================
      # Config
      # ======================================================================
      config = lib.mkIf guard (
        lib.mkMerge [
          {
            stackpanel.infra.enable = lib.mkDefault true;

            stackpanel.infra.modules.${id} = {
              inherit name description path;
              inputs = inputs cfg;
              dependencies = resolvedDeps;
              outputs = finalOutputs;
            };
          }
          (extraConfig cfg)
        ]
      );
    };
}
