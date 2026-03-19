{
  lib,
  types,
  computed,
}:
let
  inherit (types)
    moduleType
    ;
in
{
  # ============================================================================
  # Options
  # ============================================================================

  options.stackpanel.modules = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf moduleType;
    };
    default = { };
    description = ''
      Stackpanel modules that provide features and UI panels.

      Modules are the unified way to extend stackpanel functionality:
        - Add packages, scripts, and environment configuration
        - Generate files and manage secrets
        - Define health checks and background services
        - Provide UI panels for the web studio
        - Extend per-app configuration

      Each module can define:
        - `enable`: Whether the module is active
        - `meta`: Display metadata (name, description, icon, category)
        - `source`: Where the module comes from (builtin, local, flake-input, registry)
        - `features`: Which stackpanel systems it uses
        - `panels`: UI panels to render in the web studio
        - `configSchema`: JSON Schema for configuration form generation
        - `healthcheckModule`: Link to health checks

      Modules can be:
        - Builtin: Shipped with stackpanel
        - Local: Defined in your project
        - Remote: Installed via flake inputs or module registry
    '';
    example = lib.literalExpression ''
      {
        postgres = {
          enable = true;
          meta = {
            name = "PostgreSQL";
            description = "PostgreSQL database server";
            icon = "database";
            category = "database";
          };
          source.type = "builtin";
          features = {
            services = true;
            healthchecks = true;
            packages = true;
          };
          healthcheckModule = "postgres";
          panels = [{
            id = "postgres-status";
            title = "PostgreSQL Status";
            type = "PANEL_TYPE_STATUS";
            fields = [{
              name = "metrics";
              type = "FIELD_TYPE_JSON";
              value = "[{\"label\":\"Status\",\"value\":\"Running\",\"status\":\"ok\"}]";
            }];
          }];
        };

        my-custom-module = {
          enable = true;
          meta = {
            name = "My Custom Module";
            description = "Does something useful";
            category = "development";
          };
          source = {
            type = "flake-input";
            flakeInput = "my-module";
          };
        };
      }
    '';
  };

  # ============================================================================
  # Computed Read-Only Options
  # ============================================================================

  options.stackpanel.modulesComputed = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.modulesComputedEnabled;
    description = "Computed module configurations (only enabled modules, serializable)";
  };

  options.stackpanel.modulesComputedAll = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.modulesComputed;
    description = "Computed module configurations (all modules including disabled, serializable)";
  };

  options.stackpanel.modulesList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = computed.modulesListEnabled;
    description = "Flat list of enabled modules (for API consumption)";
  };

  options.stackpanel.modulesListAll = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = computed.modulesList;
    description = "Flat list of all modules including disabled (for API consumption)";
  };

  options.stackpanel.modulesBuiltin = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.builtinModules;
    description = "Builtin modules shipped with stackpanel";
  };

  options.stackpanel.modulesExternal = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    default = computed.externalModules;
    description = "External modules (local, flake-input, or registry)";
  };

  # Fast metadata discovery - allows reading module metadata without full evaluation
  # Set by modules/default.nix from each module's meta.nix file
  options.stackpanel._moduleMetas = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
    description = ''
      Fast module metadata for discovery without full module evaluation.
      Each key is a module ID, value is the contents of that module's meta.nix.
      This is set automatically by the module auto-discovery in modules/default.nix.
    '';
  };

  # ============================================================================
  # Config: Validation
  # ============================================================================

  # NOTE: Assertions are not available in devenv's module system.
  # Module dependency validation would need to be implemented differently,
  # perhaps using devenv's warning system or runtime checks.
  # For now, dependency checks are skipped.
  #
  # TODO: Implement module dependency validation using devenv-compatible mechanism
  # The validation logic should check:
  # - Required modules are enabled when a module that requires them is enabled
  # - Conflicting modules are not both enabled simultaneously
}
