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
    type = lib.types.attrsOf moduleType;
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
        - `actions`: Executables available to the Studio and the CLI
        - `enablePath`, `configPath`: Writable project options relative to `stackpanel`
        - `readme`: Markdown documentation
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
            description = "Runs PostgreSQL as a local development database server";
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
        };

        my-custom-module = {
          enable = true;
          meta = {
            name = "My Custom Module";
            description = "Adds project-specific development helpers";
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

  options.stackpanel.modulesComputedAll = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    readOnly = true;
    internal = true;
    default = computed;
    description = "Module descriptors indexed by ID for SDK validation.";
  };

  options.stackpanel.modulesListAll = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = lib.attrValues computed;
    description = "Flat list of all modules including disabled (for API consumption)";
  };
}
